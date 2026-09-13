-- "Unleash Hell" (31732) and "The White Pawn" (29555): complete them on accept.
--
-- Both are Alliance Jade Forest quests from Sky Admiral Rogers (66292), the NPC
-- at the end of the ride that "The Mission" puts the player on. Neither can be
-- finished on this realm, so both are made to complete the moment they are
-- accepted, leaving the player one step: walk to the turn-in.
--
-- Why they are dead ends in the data
--   31732 "Unleash Hell" asks for four things. Two of them are kill credits
--   that do not exist in the world: creature_template 66400 "Ship 1 Kill
--   Credit" and 66401 "Ship 2 Kill Credit" carry no `creature` row anywhere in
--   the SFDB dump, and no `smart_scripts` row grants either of them
--   (action_type 33, SMART_ACTION_KILL_CREDIT). They were meant to come from
--   the Skyfire Gyrocopter vehicle sequence, which this core has no script for.
--   The Garrosh'ar grunts (66398) and shredders (66397) do spawn, so the first
--   two objectives are reachable and the last two never are.
--
--   29555 "The White Pawn" asks for 3 x kill credit 55161 "Kill Credit: Royal
--   Chest" plus item 89603 "Encoded Captain's Log". 55161 has no spawn and no
--   script that grants it either, and nothing in the DB hands out 89603. The
--   clues in the Wreck of the Vanguard are a scripted search that is not here.
--
-- Why the objective rows are deleted and `Method` is not set to 0
--   This is the same reasoning as 2026_09_13_world_00.sql, which did it for
--   "The King's Command", and it is written out once more here so this file
--   stands on its own.
--
--   Method = 0 looks like the switch: Quest::IsAutoComplete() is exactly
--   `Method == 0` (QuestDef.cpp:199) and CanCompleteQuest returns true for it
--   at PlayerQuestState.cpp:297. It does not work. That early return is guarded
--   by CanTakeQuest(qInfo, false), which runs SatisfyQuestStatus (:1143) and is
--   false as soon as the quest is in the log at all -- and AddQuest sets the
--   status to INCOMPLETE (:512) before it reaches
--   `if (CanCompleteQuest(questId)) CompleteQuest(questId)` (:559). By then the
--   autocomplete path is closed and the objective loop decides everything.
--
--   With no objective rows that loop has nothing to fail on, returns true, and
--   AddQuest completes the quest on the spot. Quest 31853 "All Aboard!" ships
--   with zero objectives and behaves exactly this way.
--
-- The deleted rows, should they ever need restoring from this file
--   31732: (269135,0,0,66398,60,0,'Garrosh''ar Horde slain')
--          (269136,1,0,66397, 8,0,'Garrosh''ar Shredder')
--          (269137,2,0,66400, 1,0,'Bladefist Reaper sunk')
--          (269138,3,0,66401, 1,0,'Stygian Scar sunk')
--   29555: (261420,0,0,55161, 3,0,'Clues found')
--          (269107,3,1,89603, 1,1,'')
--   (`id`, `index`, `type`, `objectId`, `amount`, `flags`, `description`)
--
-- Players who already hold either quest
--   Deleting objectives does not by itself finish a quest already sitting in
--   someone's log -- nothing re-runs CanCompleteQuest for it. So the NPC that
--   takes each quest back gets SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS
--   (15) on gossip hello, which ends in
--   `if (CanCompleteQuest) CompleteQuest` (PlayerQuestState.cpp:1722): walking
--   up to the turn-in finishes it for them too. For a player who does not have
--   the quest the action returns at the first line (:1668) and costs nothing.
--
--   Their orphaned rows in `character_queststatus_objectives` are skipped at
--   load (Player.cpp:13809, the objective no longer resolves to a quest id),
--   not an error.
--
-- Idempotent, and safe to re-run.

SET @Q_UNLEASH_HELL := 31732;   -- Unleash Hell,    ends at Sky Admiral Rogers
SET @Q_WHITE_PAWN   := 29555;   -- The White Pawn,  ends at Nodd Codejack

SET @ROGERS := 66292;           -- Sky Admiral Rogers, gives both, ends 31732
SET @NODD   := 54615;           -- Nodd Codejack, ends 29555

-- ---------------------------------------------------------------------------
-- 1. Complete on accept
--
-- The locale rows go first, while the objective ids they point at can still be
-- looked up. Leaving them behind is not fatal but LoadQuestObjectiveLocales
-- (ObjectMgr.cpp:9721) logs one sql.sql error per orphan on every startup.
-- ---------------------------------------------------------------------------

DELETE FROM `locales_quest_objective`
WHERE `id` IN (SELECT `id` FROM `quest_objective`
               WHERE `questId` IN (@Q_UNLEASH_HELL, @Q_WHITE_PAWN));

DELETE FROM `quest_objective` WHERE `questId` IN (@Q_UNLEASH_HELL, @Q_WHITE_PAWN);

-- ---------------------------------------------------------------------------
-- 2. Nothing else may hold the completion back
--
-- QUEST_SPECIAL_FLAGS_EXPLORATION_OR_EVENT (2) is checked before the objective
-- loop (PlayerQuestState.cpp:307) and returns false until the quest is
-- explored, which would undo everything above. SFDB ships SpecialFlags = 0 for
-- both, so this is a guard, not a fix.
--
-- It is only half a guard: ObjectMgr re-sets that flag at load for any quest a
-- spell completes (SPELL_EFFECT_QUEST_COMPLETE, ObjectMgr.cpp:4279) or an
-- areatrigger ends (:5369). Neither table names these two quests, and the DBCs
-- cannot be read from here. If one of them turns out to, the quest will not be
-- complete on accept and the gossip-hello row below is what finishes it --
-- which is the same walk to the same NPC either way.
-- ---------------------------------------------------------------------------

UPDATE `quest_template`
SET `SpecialFlags` = `SpecialFlags` & ~2
WHERE `Id` IN (@Q_UNLEASH_HELL, @Q_WHITE_PAWN)
  AND `SpecialFlags` & 2;

-- ---------------------------------------------------------------------------
-- 3. The turn-in NPCs finish it for players who already hold the quest
--
--   SMART_EVENT_GOSSIP_HELLO                     = 64
--   SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS = 15 (action_param1 = quest)
--   SMART_TARGET_ACTION_INVOKER                  =  7
--
-- Rogers already runs SmartAI with rows 0-2 (his gossip-select chain: close
-- gossip, kill credit 66292, cast the ride 130321). Those are left alone and
-- the new row is id 20, clear of anything a later SFDB release is likely to
-- add. Nodd Codejack has no AI at all and no gossip menu, so his hello arrives
-- as CMSG_QUEST_GIVER_HELLO, which runs the same AI hook
-- (QuestHandler.cpp:147) before building the quest menu.
--
-- Action 15 does not set SmartAI's gossip return (only SEND_GOSSIP_MENU and
-- CLOSE_GOSSIP do, SmartScript.cpp:2031/2036), so Rogers' own gossip window
-- still opens exactly as before.
--
-- AIName is only set where the creature has no C++ script: a creature carrying
-- both a ScriptName and AIName = 'SmartAI' is rejected at load. The report at
-- the bottom shows which way it went.
-- ---------------------------------------------------------------------------

UPDATE `creature_template`
SET `AIName` = 'SmartAI'
WHERE `entry` IN (@ROGERS, @NODD)
  AND `ScriptName` = ''
  AND `AIName` IN ('', 'SmartAI');

DELETE FROM `smart_scripts`
WHERE `source_type` = 0 AND `id` = 20 AND `entryorguid` IN (@ROGERS, @NODD);

INSERT INTO `smart_scripts`
    (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
     `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`,
     `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
     `target_type`, `target_param1`, `target_param2`, `target_param3`,
     `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
    (@ROGERS, 0, 20, 0, 64, 0, 100, 0, 0, 0, 0, 0, 0,
     15, @Q_UNLEASH_HELL, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'Sky Admiral Rogers - On gossip hello - Complete Unleash Hell for player'),
    (@NODD, 0, 20, 0, 64, 0, 100, 0, 0, 0, 0, 0, 0,
     15, @Q_WHITE_PAWN, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'Nodd Codejack - On gossip hello - Complete The White Pawn for player');

-- ---------------------------------------------------------------------------
-- 4. Report, read in the import output
--
-- `objectives` must be 0 for both quests -- that is what completes them on
-- accept -- and `special_explore` must be 0. Each quest must keep exactly one
-- giver and one ender.
--
-- On the two NPCs, `ai` must read SmartAI with an empty `ScriptName`, and
-- `hello_rows` must be 1. `visible_spawns` counts only spawns a player can
-- actually see: phaseid 0 or 169, since this core hands out no other phase
-- (phases come from auras, spells and SmartAI alone). A 0 there means the
-- turn-in is not standing anywhere reachable and the quest still cannot be
-- handed in.
-- ---------------------------------------------------------------------------

SELECT `q`.`Id` AS `quest`, `q`.`Title`, `q`.`Method`, `q`.`SpecialFlags` & 2 AS `special_explore`,
       (SELECT COUNT(*) FROM `quest_objective`       `o` WHERE `o`.`questId` = `q`.`Id`) AS `objectives`,
       (SELECT COUNT(*) FROM `creature_queststarter` `s` WHERE `s`.`quest`   = `q`.`Id`) AS `givers`,
       (SELECT COUNT(*) FROM `creature_questender`   `e` WHERE `e`.`quest`   = `q`.`Id`) AS `enders`
FROM `quest_template` `q`
WHERE `q`.`Id` IN (@Q_UNLEASH_HELL, @Q_WHITE_PAWN)
ORDER BY `q`.`Id`;

SELECT `ct`.`entry`, `ct`.`name`, `ct`.`npcflag`, `ct`.`AIName` AS `ai`, `ct`.`ScriptName`,
       (SELECT COUNT(*) FROM `smart_scripts` `ss`
        WHERE `ss`.`source_type` = 0 AND `ss`.`entryorguid` = `ct`.`entry`
          AND `ss`.`event_type` = 64 AND `ss`.`action_type` = 15) AS `hello_rows`,
       (SELECT COUNT(*) FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`phaseid` IN (0, 169))  AS `visible_spawns`
FROM `creature_template` `ct`
WHERE `ct`.`entry` IN (@ROGERS, @NODD)
ORDER BY `ct`.`entry`;
