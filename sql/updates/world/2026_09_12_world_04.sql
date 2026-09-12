-- Pandaria intro chain: make it playable from "The King's Command" onward.
--
-- Symptom
--   The intro quest now shows up on the capital quest board (promoted as
--   sql/updates/world/2026_09_10_world_01.sql), but the chain behind it goes
--   nowhere. Alliance accept "The King's Command" and it never completes and
--   can never be handed in; Horde accept "The Art of War", walk into Grommash
--   Hold, and the objective stays at 0/1.
--
-- What the chain looks like in the DB
--   Alliance  29547 The King's Command     -> 29548 The Mission   -> 31732 Unleash Hell
--   Horde     29611/29612 The Art of War   -> 31853 All Aboard!   -> 29690 Into the Mists
--   (NextQuestIdChain; PrevQuestId is 0 everywhere, so nothing is gated.)
--
-- Four separate defects, all in the data
--
--   1. 29547 has no quest ender at all -- not a creature, not a gameobject.
--      It is the only quest in the chain with none. Even a completed objective
--      would leave the player holding it forever.
--
--   2. Every objective in the chain is `quest_objective`.`type` = 0
--      (QUEST_OBJECTIVE_TYPE_NPC, QuestDef.h:193), and this core credits that
--      type from exactly one place: Player::KilledMonsterCredit
--      (PlayerQuestState.cpp:1850). Player::TalkedToCreature (:2004) only ever
--      credits type 3 (NPC_INTERACT). So "Stormwind Keep visited" (credit
--      55567) and "Report to Grommash Hold" (credit 54870) cannot be earned by
--      walking in or by talking -- they need a kill credit, and nothing in the
--      DB fires one. 55567 has no spawn either; it is a bunny that retail
--      credits from a script this core does not have.
--
--   3. SFDB does wire up two of the credits, but behind NPCs nobody can reach.
--      Sky Admiral Rogers (66292) and General Nazgrim (55054) each carry a
--      gossip-select script that credits the objective and then teleports the
--      player to Pandaria -- the retail gunship/ship ride. Rogers stands on the
--      Skyfire deck at (-7879.8, 1279.5, 358.6) on map 0, Nazgrim at
--      (1862.3, -5461.9, 443.8) on map 1. Both are in mid-air over the capital:
--      that ride can only be taken by a player who can already fly up to the
--      deck, because the ship the quest text describes is not a transport in
--      this DB, just a parked crew.
--
--   4. The ender of 31853 and the giver of 29690 are that same unreachable
--      Nazgrim (55054), so the Horde chain dead-ends even once the credit
--      works. The Alliance side is luckier: Rogers has a second, unphased spawn
--      at (-664.9, -1483.3, 130.2) on map 870, four yards from where the
--      Pandaria teleport lands, so he can end 29548 and give 31732 in person.
--
-- The fix, in the same shape as the Hyjal breadcrumb repair
--   sql/updates/world/2026_09_09_world_07.sql replaced an unportable scripted
--   flight with a teleport on quest accept. The gunship ride is the same class
--   of problem, so it gets the same answer:
--
--     - Rell Nightwind ends "The King's Command" in Stormwind Keep, and credits
--       "Stormwind Keep visited" the moment the player speaks to him. He is
--       already the giver of "The Mission", so the turn-in and the next quest
--       happen in one conversation.
--     - Accepting "The Mission" from Rell teleports the player to The Jade
--       Forest, next to Sky Admiral Rogers. That is the Skyfire ride.
--     - General Nazgrim in Grommash Hold credits "Report to Grommash Hold" on
--       hello, and accepting "All Aboard!" from him teleports the player to the
--       Horde landing site. That is the ship.
--     - General Nazgrim at the Horde landing site (55135) also ends
--       "All Aboard!" and gives "Into the Mists", and credits "Discovered
--       Pandaria" -- which is simply true, the player is standing in Pandaria.
--
--   Landing coordinates are not invented here. They are the destinations of
--   SFDB's own ride spells, read from `spell_target_position` (130321 Alliance,
--   125060 Horde) with the same literals as a fallback that
--   2026_09_10_world_01.sql already uses for the capital emissaries.
--
-- Why no npcflag change
--   Rell (55789), Nazgrim (54870) and Nazgrim (55135) are npcflag 2 --
--   questgiver, no gossip bit -- so the client sends CMSG_QUEST_GIVER_HELLO,
--   not a gossip hello. That path still runs the AI hook:
--   QuestHandler.cpp:147 calls creature->AI()->OnGossipHello() before building
--   the quest menu, and SmartAI::OnGossipHello (SmartAI.cpp:732) fires
--   SMART_EVENT_GOSSIP_HELLO and returns _gossipReturn, which nothing in
--   SmartScript ever sets. So the credit lands first and the turn-in appears in
--   the same window, with the template otherwise left alone.
--
-- Where this stops, and why
--   The quest the player is holding at the end of it -- 31732 Unleash Hell
--   (Alliance) and 31765 Paint it Red! (Horde) -- is the scripted gunship
--   battle, and that is not fixable as data. 31732 wants two kill credits
--   (66400 Bladefist Reaper, 66401 Stygian Scar) that have no spawn, and its
--   two killable objectives (66398, 66397) exist only in phase 1740, which no
--   player can enter: this core grants phases from auras, spells and SmartAI
--   only, and `phase_area` (ObjectMgr.cpp:9045) is read solely to block phase
--   removal. Every objective of 31733, 31765, 31766, 31767 and 31769 is an
--   unspawned credit bunny as well. Nothing is lost by stopping here -- no
--   quest anywhere in the DB names any of these as PrevQuestId, so the Jade
--   Forest questline (136 of its 150 quests have an unphased giver) stays open.
--
-- Idempotent
--   Only the rows this file owns are deleted and rewritten. Quest relations are
--   deleted by exact (id, quest) pair so SFDB's own rows for the same quests
--   survive, and Rogers keeps his three SFDB smart_scripts rows -- this file
--   uses id 10 on him and deletes only that one.

SET @Q_KINGS_COMMAND   := 29547;   -- The King's Command       (Alliance)
SET @Q_THE_MISSION     := 29548;   -- The Mission              (Alliance)
SET @Q_ART_OF_WAR      := 29611;   -- The Art of War           (Horde)
SET @Q_ART_OF_WAR_ALT  := 29612;   -- The Art of War, Vashj'ir survivor version
SET @Q_ALL_ABOARD      := 31853;   -- All Aboard!              (Horde)
SET @Q_INTO_THE_MISTS  := 29690;   -- Into the Mists           (Horde)

SET @CREDIT_KEEP       := 55567;   -- "Stormwind Keep visited"       (29547)
SET @CREDIT_ROGERS     := 66292;   -- "Speak to Admiral Rogers"      (29548)
SET @CREDIT_HOLD       := 54870;   -- "Report to Grommash Hold"      (29611, 29612)
SET @CREDIT_PANDARIA   := 67040;   -- "Discovered Pandaria"          (29690)

SET @RELL              := 55789;   -- Rell Nightwind, Stormwind Keep
SET @ROGERS            := 66292;   -- Sky Admiral Rogers
SET @NAZGRIM_ORGRIMMAR := 54870;   -- General Nazgrim, Grommash Hold
SET @NAZGRIM_JADE      := 55135;   -- General Nazgrim, Horde landing site

-- ---------------------------------------------------------------------------
-- 1. The quest relations that are missing
--
-- Each of these creatures already carries UNIT_NPC_FLAG_QUESTGIVER, so none of
-- the rows can trip ObjectMgr.cpp:7310 / :7325. The joins against
-- `creature_template` and `quest_template` keep the file safe on a DB where one
-- of the quests or creatures is absent.
-- ---------------------------------------------------------------------------

DELETE FROM `creature_questender`
WHERE (`id` = @RELL         AND `quest` = @Q_KINGS_COMMAND)
   OR (`id` = @NAZGRIM_JADE AND `quest` = @Q_ALL_ABOARD);

INSERT INTO `creature_questender` (`id`, `quest`)
SELECT `ct`.`entry`, `q`.`Id`
FROM `creature_template` `ct`
JOIN `quest_template` `q`
  ON (`ct`.`entry` = @RELL         AND `q`.`Id` = @Q_KINGS_COMMAND)
  OR (`ct`.`entry` = @NAZGRIM_JADE AND `q`.`Id` = @Q_ALL_ABOARD);

DELETE FROM `creature_queststarter`
WHERE `id` = @NAZGRIM_JADE AND `quest` = @Q_INTO_THE_MISTS;

INSERT INTO `creature_queststarter` (`id`, `quest`)
SELECT `ct`.`entry`, `q`.`Id`
FROM `creature_template` `ct`
JOIN `quest_template` `q`
  ON `ct`.`entry` = @NAZGRIM_JADE AND `q`.`Id` = @Q_INTO_THE_MISTS;

-- ---------------------------------------------------------------------------
-- 2. Landing sites
--
-- Read from SFDB's own ride spells; the literals are the values those rows were
-- shipped with (SFDB_Release_20.2_to_20.3), and are the same pair the capital
-- emissaries in 2026_09_10_world_01.sql travel to.
-- ---------------------------------------------------------------------------

SET @JF_A_MAP := COALESCE((SELECT `target_map`         FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), 870);
SET @JF_A_X   := COALESCE((SELECT `target_position_x`  FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), -668.56);
SET @JF_A_Y   := COALESCE((SELECT `target_position_y`  FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), -1482.19);
SET @JF_A_Z   := COALESCE((SELECT `target_position_z`  FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), 130.2);
SET @JF_A_O   := COALESCE((SELECT `target_orientation` FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), 5.97);

SET @JF_H_MAP := COALESCE((SELECT `target_map`         FROM `spell_target_position` WHERE `id` = 125060 LIMIT 1), 870);
SET @JF_H_X   := COALESCE((SELECT `target_position_x`  FROM `spell_target_position` WHERE `id` = 125060 LIMIT 1), 3138.64);
SET @JF_H_Y   := COALESCE((SELECT `target_position_y`  FROM `spell_target_position` WHERE `id` = 125060 LIMIT 1), -721.332);
SET @JF_H_Z   := COALESCE((SELECT `target_position_z`  FROM `spell_target_position` WHERE `id` = 125060 LIMIT 1), 324.9845);
SET @JF_H_O   := COALESCE((SELECT `target_orientation` FROM `spell_target_position` WHERE `id` = 125060 LIMIT 1), 0.38);

-- ---------------------------------------------------------------------------
-- 3. SmartAI on the three NPCs that have no AI yet
--
-- ScriptName = '' is a condition, not tidiness: a creature with both a
-- ScriptName and AIName = 'SmartAI' is rejected at load, and if a later SFDB
-- release gives one of them a C++ script this file must not fight it. The
-- report at the bottom prints what each entry ended up with.
-- ---------------------------------------------------------------------------

UPDATE `creature_template`
SET `AIName` = 'SmartAI'
WHERE `entry` IN (@RELL, @NAZGRIM_ORGRIMMAR, @NAZGRIM_JADE)
  AND `ScriptName` = ''
  AND `AIName` IN ('', 'SmartAI');

-- ---------------------------------------------------------------------------
-- 4. The scripts
--
--   SMART_EVENT_GOSSIP_HELLO        = 64 (no parameters)
--   SMART_EVENT_ACCEPTED_QUEST      = 19 (event_param1 = quest id)
--   SMART_ACTION_CALL_KILLEDMONSTER = 33 (action_param1 = credit entry)
--   SMART_ACTION_TELEPORT           = 62 (action_param1 = map, target x/y/z/o)
--   SMART_TARGET_ACTION_INVOKER     =  7 (the player, not the NPC)
--
-- Action 33 with a target type other than NONE/SELF calls
-- Player::KilledMonsterCredit on every player in the target list
-- (SmartScript.cpp:886-893), which is a no-op unless that player is holding the
-- quest the credit belongs to. Each of these four credit entries is used by
-- exactly one quest objective in the whole DB, so nothing else can catch them.
--
-- The teleports fire on SMART_EVENT_ACCEPTED_QUEST, which QuestHandler.cpp:259
-- reaches only after the quest is in the log and CompleteQuest has already run
-- (:254) -- so "All Aboard!", which has no objectives at all, is complete
-- before the player lands, and waits for them at the Jade Forest Nazgrim.
-- ---------------------------------------------------------------------------

DELETE FROM `smart_scripts`
WHERE `source_type` = 0
  AND `entryorguid` IN (@RELL, @NAZGRIM_ORGRIMMAR, @NAZGRIM_JADE);

DELETE FROM `smart_scripts`
WHERE `source_type` = 0 AND `entryorguid` = @ROGERS AND `id` = 10;

INSERT INTO `smart_scripts`
    (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
     `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`,
     `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
     `target_type`, `target_param1`, `target_param2`, `target_param3`,
     `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
    (@RELL, 0, 0, 0, 64, 0, 100, 0, 0, 0, 0, 0, 0,
     33, @CREDIT_KEEP, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'Rell Nightwind - On gossip hello - Credit Stormwind Keep visited'),
    (@RELL, 0, 1, 0, 19, 0, 100, 0, @Q_THE_MISSION, 0, 0, 0, 0,
     62, @JF_A_MAP, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @JF_A_X, @JF_A_Y, @JF_A_Z, @JF_A_O,
     'Rell Nightwind - On quest The Mission accepted - Teleport player to The Jade Forest'),

    (@ROGERS, 0, 10, 0, 64, 0, 100, 0, 0, 0, 0, 0, 0,
     33, @CREDIT_ROGERS, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'Sky Admiral Rogers - On gossip hello - Credit Speak to Admiral Rogers'),

    (@NAZGRIM_ORGRIMMAR, 0, 0, 0, 64, 0, 100, 0, 0, 0, 0, 0, 0,
     33, @CREDIT_HOLD, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'General Nazgrim - On gossip hello - Credit Report to Grommash Hold'),
    (@NAZGRIM_ORGRIMMAR, 0, 1, 0, 19, 0, 100, 0, @Q_ALL_ABOARD, 0, 0, 0, 0,
     62, @JF_H_MAP, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @JF_H_X, @JF_H_Y, @JF_H_Z, @JF_H_O,
     'General Nazgrim - On quest All Aboard! accepted - Teleport player to The Jade Forest'),

    (@NAZGRIM_JADE, 0, 0, 0, 64, 0, 100, 0, 0, 0, 0, 0, 0,
     33, @CREDIT_PANDARIA, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'General Nazgrim - On gossip hello - Credit Discovered Pandaria'),
    (@NAZGRIM_JADE, 0, 1, 0, 19, 0, 100, 0, @Q_INTO_THE_MISTS, 0, 0, 0, 0,
     33, @CREDIT_PANDARIA, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'General Nazgrim - On quest Into the Mists accepted - Credit Discovered Pandaria');

-- ---------------------------------------------------------------------------
-- 5. Report, read in the import output
--
-- Every quest in the first table must show at least one giver and one ender.
-- In the second, `ai` must be SmartAI on all four NPCs -- an empty one means
-- the UPDATE above found a ScriptName and stepped aside, and that NPC's rows
-- will not run. `visible_spawns` counts the spawns a player carrying no phases
-- can actually see (Object.cpp:3502-3508): if Rogers or the Jade Forest Nazgrim
-- reads 0, the chain still cannot be finished on this DB and the landing site
-- needs a spawn before anything else is tried.
-- ---------------------------------------------------------------------------

SELECT `q`.`Id` AS `quest`, `q`.`Title`,
       (SELECT COUNT(*) FROM `creature_queststarter` `s` WHERE `s`.`quest` = `q`.`Id`) AS `givers`,
       (SELECT COUNT(*) FROM `creature_questender`   `e` WHERE `e`.`quest` = `q`.`Id`) AS `enders`,
       (SELECT COUNT(*) FROM `gameobject_queststarter` `g` WHERE `g`.`quest` = `q`.`Id`) AS `board_entries`
FROM `quest_template` `q`
WHERE `q`.`Id` IN (@Q_KINGS_COMMAND, @Q_THE_MISSION, @Q_ART_OF_WAR, @Q_ART_OF_WAR_ALT,
                   @Q_ALL_ABOARD, @Q_INTO_THE_MISTS)
ORDER BY `q`.`Id`;

SELECT `ct`.`entry`, `ct`.`name`, `ct`.`npcflag`, `ct`.`AIName` AS `ai`, `ct`.`ScriptName`,
       (SELECT COUNT(*) FROM `smart_scripts` `ss`
        WHERE `ss`.`source_type` = 0 AND `ss`.`entryorguid` = `ct`.`entry`) AS `smart_rows`,
       (SELECT COUNT(*) FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`phaseid` IN (0, 169) AND `c`.`phasegroup` = 0) AS `visible_spawns`
FROM `creature_template` `ct`
WHERE `ct`.`entry` IN (@RELL, @ROGERS, @NAZGRIM_ORGRIMMAR, @NAZGRIM_JADE)
ORDER BY `ct`.`entry`;

SELECT @JF_A_MAP AS `alliance_map`, @JF_A_X AS `x`, @JF_A_Y AS `y`, @JF_A_Z AS `z`,
       @JF_H_MAP AS `horde_map`,    @JF_H_X AS `hx`, @JF_H_Y AS `hy`, @JF_H_Z AS `hz`;
