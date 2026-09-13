-- "The King's Command" (29547): complete it on accept, and put the NPC the
-- quest actually names into the room it names.
--
-- Follow-up to sql/updates/world/2026_09_12_world_04.sql, which is promoted and
-- must not be touched. Everything here is written to be correct whether or not
-- that file has run.
--
-- Symptom
--   The quest is still a dead end in the client. Its objective text reads
--   "Find Grand Admiral Jes-Tereth in the war room at Stormwind Keep in
--   Stormwind City", and no such NPC is there to be found.
--
-- Why it stayed broken after the chain repair
--   2026_09_12_world_04.sql made Rell Nightwind the ender and had him credit
--   the objective on hello -- Rell is the SFDB giver of the next quest and the
--   only NPC standing in the war room, so he was the best target the data
--   offered. But the quest never tells the player to talk to Rell, so nobody
--   does. Grand Admiral Jes-Tereth is the name in the objective, in the quest
--   details ("I will be waiting in the King's war room") and in
--   `quest_template`.`QuestGiverTargetName` -- and SFDB carries her as
--   creature_template 55579 with npcflag 0, no AI, level 1, and **no spawn row
--   at all**. She exists as a name and a model and nothing else.
--
-- What this file does
--   1. Deletes the objective of 29547, so the quest is complete the moment it
--      is accepted -- which is what was asked for, and leaves the player one
--      step: go and hand it in.
--   2. Turns 55579 into a real questgiver, spawns her beside Rell in the war
--      room, and moves the turn-in from Rell to her.
--   3. Gives her the next quest too, so "The King's Command" and "The Mission"
--      happen in one conversation, and accepting "The Mission" from her takes
--      the same ride to The Jade Forest that accepting it from Rell does.
--
-- Why the objective is deleted and `Method` is not set to 0
--   Method = 0 looks like the obvious switch -- Quest::IsAutoComplete() is
--   exactly `Method == 0` (QuestDef.cpp:199) and CanCompleteQuest returns true
--   for it at PlayerQuestState.cpp:297. It does not work here. That early
--   return is guarded by `CanTakeQuest(qInfo, false)`, and CanTakeQuest (:249)
--   runs SatisfyQuestStatus (:1143), which returns false as soon as the quest
--   is in the log at all. AddQuest sets the status to INCOMPLETE (:512) before
--   it reaches `if (CanCompleteQuest(questId)) CompleteQuest(questId)` (:559),
--   so by then the autocomplete path is already closed and the objective loop
--   decides everything.
--
--   With no objective rows that loop has nothing to fail on, so it returns true
--   and AddQuest completes the quest on the spot. That is not a trick: quest
--   31853 "All Aboard!" ships with zero objectives and behaves exactly this way.
--
--   The deleted row is recoverable -- it is
--   (259891, 0, 0, 55567, 1, 0, 'Stormwind Keep visited') in the SFDB dump.
--   Kill credit 55567 has no spawn and no script anywhere in the DB, which is
--   why nothing could ever grant it.
--
-- Players who already hold the quest
--   Deleting the objective does not by itself complete a quest already sitting
--   in someone's log -- nothing re-runs CanCompleteQuest for it. Jes-Tereth
--   therefore calls SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS (15) on hello,
--   which ends in `if (CanCompleteQuest) CompleteQuest` (PlayerQuestState.cpp
--   :1722), so walking up to her finishes it for them too. Their orphaned row
--   in `character_queststatus_objectives` is skipped at load (Player.cpp:13809,
--   the objective no longer resolves to a quest id), not an error.
--
-- Left alone on purpose
--   Rell's own rows from the promoted file: he keeps giving "The Mission", and
--   his hello still calls a kill credit that now belongs to no objective, which
--   is a no-op. Only his questender row for 29547 is removed, so exactly one
--   NPC shows the turn-in.

SET @Q_KINGS_COMMAND := 29547;   -- The King's Command
SET @Q_THE_MISSION   := 29548;   -- The Mission

SET @JES  := 55579;              -- Grand Admiral Jes-Tereth
SET @RELL := 55789;              -- Rell Nightwind, already standing in the war room

-- Fresh creature guid block. 8450001-8450100 belongs to the capital emissaries
-- in 2026_09_10_world_01.sql; 8460001-8460099 is a *gameobject* block
-- (2026_09_11_world_00.sql), kept clear here anyway to avoid confusion.
SET @GUID := 8470001;

-- ---------------------------------------------------------------------------
-- 1. Complete on accept
-- ---------------------------------------------------------------------------

DELETE FROM `quest_objective` WHERE `questId` = @Q_KINGS_COMMAND;

-- ---------------------------------------------------------------------------
-- 2. Jes-Tereth becomes an NPC that can be spoken to
--
-- npcflag bit 2 (UNIT_NPC_FLAG_QUESTGIVER) is all that is needed. The gossip
-- bit is not: with no gossip menu the client sends CMSG_QUEST_GIVER_HELLO, and
-- QuestHandler.cpp:147 runs the AI hook on that path before building the quest
-- menu. Same reasoning as 2026_09_12_world_04.sql, same as Rell next to her.
--
-- Level 1 is left over from her never being used; 90 is what a Grand Admiral
-- in a level-85 war room should read as. She is faction 35, so nothing about
-- her is a combat decision.
--
-- ScriptName = '' is a condition: a creature carrying both a ScriptName and
-- AIName = 'SmartAI' is rejected at load, so if a later SFDB release gives her
-- a C++ script this file steps aside rather than fighting it. The report at the
-- bottom shows which way it went.
-- ---------------------------------------------------------------------------

UPDATE `creature_template`
SET `npcflag`  = `npcflag` | 2,
    `minlevel` = 90,
    `maxlevel` = 90
WHERE `entry` = @JES;

UPDATE `creature_template`
SET `AIName` = 'SmartAI'
WHERE `entry` = @JES
  AND `ScriptName` = ''
  AND `AIName` IN ('', 'SmartAI');

-- ---------------------------------------------------------------------------
-- 3. Spawn her in the war room
--
-- The position is derived from Rell's own spawn row rather than typed in: two
-- and a half yards to his left, same height, same facing. The war room is
-- otherwise empty -- the nearest other spawn in the SFDB dump is 13 yards away
-- -- so there is nothing to stand inside of. The literals are Rell's shipped
-- coordinates, used only if his row is missing.
--
-- The insert is skipped when a Jes-Tereth spawn already stands within 30 yards
-- of Rell, so a future SFDB release that places her properly wins and this file
-- adds nothing. A spawn of hers somewhere else entirely -- on the Skyfire, say,
-- where the player cannot reach her -- does not count as that.
-- ---------------------------------------------------------------------------

SET @RELL_X := COALESCE((SELECT `position_x`  FROM `creature` WHERE `id` = @RELL AND `map` = 0 ORDER BY `guid` LIMIT 1), -8458.65);
SET @RELL_Y := COALESCE((SELECT `position_y`  FROM `creature` WHERE `id` = @RELL AND `map` = 0 ORDER BY `guid` LIMIT 1), 353.062);
SET @RELL_Z := COALESCE((SELECT `position_z`  FROM `creature` WHERE `id` = @RELL AND `map` = 0 ORDER BY `guid` LIMIT 1), 135.569);
SET @RELL_O := COALESCE((SELECT `orientation` FROM `creature` WHERE `id` = @RELL AND `map` = 0 ORDER BY `guid` LIMIT 1), 5.40221);

DELETE FROM `creature` WHERE `guid` = @GUID;

SET @JES_IN_WAR_ROOM := (
    SELECT COUNT(*) FROM `creature`
    WHERE `id` = @JES AND `map` = 0
      AND POW(`position_x` - @RELL_X, 2) + POW(`position_y` - @RELL_Y, 2) < 900);

INSERT INTO `creature`
    (`guid`, `id`, `map`, `modelid`, `equipment_id`,
     `position_x`, `position_y`, `position_z`, `orientation`,
     `spawntimesecs`, `spawndist`, `currentwaypoint`, `curhealth`, `curmana`,
     `MovementType`, `spawnMask`, `phaseid`, `phasegroup`,
     `npcflag`, `unit_flags`, `dynamicflags`)
SELECT @GUID, @JES, 0, 0, 0,
       @RELL_X + 2.5 * COS(@RELL_O + PI() / 2),
       @RELL_Y + 2.5 * SIN(@RELL_O + PI() / 2),
       @RELL_Z, @RELL_O,
       120, 0, 0, 1, 0,
       0, 1, 0, 0, 0, 0, 0
FROM DUAL
WHERE @JES_IN_WAR_ROOM = 0
  AND EXISTS (SELECT 1 FROM `creature_template` WHERE `entry` = @JES);

-- ---------------------------------------------------------------------------
-- 4. The quest relations move to her
--
-- Rell's questender row for 29547 goes, hers arrives, and she also gains the
-- giver row for 29548 -- Rell keeps his, so The Mission can still be taken from
-- either of them. NextQuestIdChain (29547 -> 29548) means the client offers The
-- Mission immediately after the turn-in when the same NPC has both, which is
-- the whole point of giving her the second row.
-- ---------------------------------------------------------------------------

DELETE FROM `creature_questender`   WHERE `id` IN (@RELL, @JES) AND `quest` = @Q_KINGS_COMMAND;
DELETE FROM `creature_queststarter` WHERE `id` = @JES AND `quest` = @Q_THE_MISSION;

INSERT INTO `creature_questender` (`id`, `quest`)
SELECT `ct`.`entry`, `q`.`Id`
FROM `creature_template` `ct`
JOIN `quest_template` `q`
  ON `ct`.`entry` = @JES AND `q`.`Id` = @Q_KINGS_COMMAND;

INSERT INTO `creature_queststarter` (`id`, `quest`)
SELECT `ct`.`entry`, `q`.`Id`
FROM `creature_template` `ct`
JOIN `quest_template` `q`
  ON `ct`.`entry` = @JES AND `q`.`Id` = @Q_THE_MISSION;

-- ---------------------------------------------------------------------------
-- 5. Her scripts
--
--   SMART_EVENT_GOSSIP_HELLO                     = 64
--   SMART_EVENT_ACCEPTED_QUEST                   = 19 (event_param1 = quest id)
--   SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS = 15 (action_param1 = quest id)
--   SMART_ACTION_TELEPORT                        = 62 (action_param1 = map)
--   SMART_TARGET_ACTION_INVOKER                  =  7
--
-- The teleport is the same ride Rell gives, to the same place: the destination
-- of SFDB's own Alliance ride spell 130321, read from `spell_target_position`
-- with its shipped values as the fallback. Sky Admiral Rogers stands four yards
-- from it.
-- ---------------------------------------------------------------------------

SET @JF_MAP := COALESCE((SELECT `target_map`         FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), 870);
SET @JF_X   := COALESCE((SELECT `target_position_x`  FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), -668.56);
SET @JF_Y   := COALESCE((SELECT `target_position_y`  FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), -1482.19);
SET @JF_Z   := COALESCE((SELECT `target_position_z`  FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), 130.2);
SET @JF_O   := COALESCE((SELECT `target_orientation` FROM `spell_target_position` WHERE `id` = 130321 LIMIT 1), 5.97);

DELETE FROM `smart_scripts` WHERE `source_type` = 0 AND `entryorguid` = @JES;

INSERT INTO `smart_scripts`
    (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
     `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`,
     `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
     `target_type`, `target_param1`, `target_param2`, `target_param3`,
     `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
    (@JES, 0, 0, 0, 64, 0, 100, 0, 0, 0, 0, 0, 0,
     15, @Q_KINGS_COMMAND, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'Grand Admiral Jes-Tereth - On gossip hello - Complete The King''s Command for player'),
    (@JES, 0, 1, 0, 19, 0, 100, 0, @Q_THE_MISSION, 0, 0, 0, 0,
     62, @JF_MAP, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @JF_X, @JF_Y, @JF_Z, @JF_O,
     'Grand Admiral Jes-Tereth - On quest The Mission accepted - Teleport player to The Jade Forest');

-- ---------------------------------------------------------------------------
-- 6. Report, read in the import output
--
-- `objectives` must be 0 for 29547 -- that is what completes it on accept.
-- 29547 must show exactly one ender and 29548 two givers. On Jes-Tereth
-- `npcflag` must be odd-or-even but at least carry bit 2, `ai` must read
-- SmartAI, and `spawns` must be 1 or more; a 0 there means she is still not in
-- the world and the quest still cannot be handed in.
-- ---------------------------------------------------------------------------

SELECT `q`.`Id` AS `quest`, `q`.`Title`,
       (SELECT COUNT(*) FROM `quest_objective`      `o` WHERE `o`.`questId` = `q`.`Id`) AS `objectives`,
       (SELECT COUNT(*) FROM `creature_queststarter` `s` WHERE `s`.`quest` = `q`.`Id`)  AS `givers`,
       (SELECT COUNT(*) FROM `creature_questender`   `e` WHERE `e`.`quest` = `q`.`Id`)  AS `enders`
FROM `quest_template` `q`
WHERE `q`.`Id` IN (@Q_KINGS_COMMAND, @Q_THE_MISSION)
ORDER BY `q`.`Id`;

SELECT `ct`.`entry`, `ct`.`name`, `ct`.`npcflag`, `ct`.`minlevel`, `ct`.`AIName` AS `ai`, `ct`.`ScriptName`,
       (SELECT COUNT(*) FROM `smart_scripts` `ss`
        WHERE `ss`.`source_type` = 0 AND `ss`.`entryorguid` = `ct`.`entry`) AS `smart_rows`,
       (SELECT COUNT(*) FROM `creature` `c` WHERE `c`.`id` = `ct`.`entry`) AS `spawns`
FROM `creature_template` `ct`
WHERE `ct`.`entry` IN (@JES, @RELL)
ORDER BY `ct`.`entry`;

SELECT `c`.`guid`, `c`.`map`,
       ROUND(`c`.`position_x`, 2) AS `x`, ROUND(`c`.`position_y`, 2) AS `y`,
       ROUND(`c`.`position_z`, 2) AS `z`, ROUND(`c`.`orientation`, 3) AS `o`,
       ROUND(SQRT(POW(`c`.`position_x` - @RELL_X, 2) + POW(`c`.`position_y` - @RELL_Y, 2)), 2) AS `yards_from_rell`
FROM `creature` `c`
WHERE `c`.`id` = @JES;
