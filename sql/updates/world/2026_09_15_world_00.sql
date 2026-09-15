-- Pandaria flying trainers: give Skydancer Shun and Cloudrunner Leng a spell
-- list, and put "Wisdom of the Four Winds" (115913) in it.
--
-- Symptom
--   A level 90 walks up to the riding trainer at the Shrine of Two Moons or the
--   Shrine of Seven Stars and cannot learn Wisdom of the Four Winds, the spell
--   that turns flight on in Pandaria. Nothing is offered at all.
--
-- Why
--   `npc_trainer` has no row for either NPC. Not an incomplete list -- no rows.
--   SendTrainerList (NPCHandler.cpp:125) asks Creature::GetTrainerSpells() for
--   the entry, gets nothing back, logs "Training spells not found for creature"
--   (:128) and returns without sending SMSG_TRAINER_LIST, so the window has
--   nothing to show.
--
--   Both NPCs are otherwise fine and were never the problem: entry 60167
--   "Skydancer Shun" stands at 1555.22 890.88 478.43 on map 870 and entry 60166
--   "Cloudrunner Leng" at 911.60 349.37 510.97, both unphased, both faction
--   2481, both carrying npcflag 80 -- UNIT_NPC_FLAG_TRAINER (0x10) plus
--   UNIT_NPC_FLAG_TRAINER_PROFESSION (0x40), the same pair every other riding
--   trainer in the dump carries.
--
--   The dump has 22 other riding trainers and every one of them points at a
--   shared reference block instead of listing spells: `npc_trainer`.`spell` =
--   -200300 for ground riding, -200301 for ground plus flight.
--   ObjectMgr::LoadTrainerSpell (:8109) expands those with
--   `INNER JOIN npc_trainer AS b ON a.entry = -(b.spell)`, and
--   AddSpellToTrainer (:8026) refuses to make a trainer out of a block itself
--   because its entry is at or above SKYFIRE_TRAINER_START_REF (200000). The
--   two Pandaria trainers were simply never linked to one.
--
--   115913 is not in any block either. It appears nowhere in `npc_trainer` in
--   the entire dump, so no trainer anywhere could teach it.
--
-- Why the learned spell is the whole fix
--   Nothing else in the core gates Pandaria flight. Player::IsKnowHowFlyIn
--   (Player.cpp:21305) special-cases map 571 only, Northrend. Mounting goes
--   through Unit::GetMountCapability (Unit.cpp:3830), which walks
--   MountCapability.dbc and skips any row whose `RequiredSpell` the player does
--   not know (:3879). The Pandaria flight rows name 115913 -- which is why the
--   core's own character boost writes exactly that spell into `character_spell`
--   (CharacterBoost.h:549, commented "Wisdom of the Four Winds"). Hand the
--   player the spell and flight works. No C++ change is involved.
--
-- Shape of the fix
--   Each trainer gets two rows: the -200301 reference, which is the same list
--   Roxi Ramrocket and Hira Snowdawn already hand out (Apprentice through
--   Master Riding, the Flight Master's License and Cold Weather Flying), and a
--   direct row for 115913.
--
--   115913 goes on the two NPCs rather than into block 200301 so that the 20
--   trainers already sharing that block are not changed by this file. If
--   Pandaria flight should be trainable from Azeroth as well, moving the row
--   into the block is a one-line follow-up.
--
--   It is listed as itself, not as a "teach" spell. Block 200301 lists the
--   caster-side wrappers -- 33389 teaches 33388, 34092 teaches 34090, 90266
--   teaches 90265 -- but no such wrapper for 115913 exists in this data, and
--   none is needed: AddSpellToTrainer sets learnedSpell[0] to the spell itself
--   when it carries no SPELL_EFFECT_LEARN_SPELL (:8074), and
--   HandleTrainerBuySpellOpcode then calls Player::learnSpell on it
--   (NPCHandler.cpp:278) -- the same thing the character boost does.
--
-- Price and requirement
--   2500g at level 90 with Expert Riding, which is what retail charged. Expert
--   Riding is riding skill (762) at 225, the same bar block 200301 puts on Cold
--   Weather Flying (54198) and the Flight Master's License (90269) -- the two
--   other per-continent flight unlocks, and the closest thing to a precedent.
--
-- Left alone on purpose
--   Softpaws (70301, Orgrimmar) and Mei Lin (70296, Stormwind), the two
--   pandaren riding trainers in the capitals, are broken in their own way --
--   Softpaws teaches only Apprentice and Journeyman riding, Mei Lin has npcflag
--   0 and so is not a trainer at all. Neither stands in Pandaria and neither is
--   what was reported here, so they are a separate change.
--
--   The duplicate spawn of 60167 (guids 1042 and 8155725 at identical
--   coordinates) is also left as it is. It is cosmetic and predates this file.

SET @LENG   := 60166;      -- Cloudrunner Leng <Flying Trainer>, Shrine of Seven Stars
SET @SHUN   := 60167;      -- Skydancer Shun  <Flying Trainer>, Shrine of Two Moons

SET @RIDING_REF := -200301;  -- shared reference block: ground riding + flight
SET @WISDOM     := 115913;   -- Wisdom of the Four Winds
SET @COST       := 25000000; -- 2500g, in copper
SET @SKILL_RIDING   := 762;
SET @EXPERT_RIDING  := 225;  -- riding skill granted by Expert Riding (34090)
SET @REQ_LEVEL      := 90;

-- ---------------------------------------------------------------------------
-- 1. The spell list
--
-- Re-runnable: both entries are cleared first, so applying this twice leaves
-- the same four rows. `npc_trainer` is keyed on (entry, spell).
-- ---------------------------------------------------------------------------

DELETE FROM `npc_trainer` WHERE `entry` IN (@LENG, @SHUN);

INSERT INTO `npc_trainer` (`entry`, `spell`, `spellcost`, `reqskill`, `reqskillvalue`, `reqlevel`) VALUES
(@LENG, @RIDING_REF, 0,      0,             0,               0),
(@LENG, @WISDOM,     @COST,  @SKILL_RIDING, @EXPERT_RIDING,  @REQ_LEVEL),
(@SHUN, @RIDING_REF, 0,      0,             0,               0),
(@SHUN, @WISDOM,     @COST,  @SKILL_RIDING, @EXPERT_RIDING,  @REQ_LEVEL);

-- ---------------------------------------------------------------------------
-- 2. trainer_type
--
-- Both NPCs carry trainer_type 2 (TRAINER_TYPE_TRADESKILLS); every other riding
-- trainer in the dump carries 1 (TRAINER_TYPE_MOUNTS). This changes no
-- behaviour today -- the core reads creature_template.trainer_type in exactly
-- two places, Creature::isCanTrainingAndResetTalentsOf (Creature.cpp:877) and
-- the GOSSIP_OPTION_TRAINER arm of Player::PrepareGossipMenu (Player.cpp:11962),
-- and both only act when the value is 0 (CLASS). The type the client is sent
-- comes from TrainerSpellData::trainerType, which AddSpellToTrainer computes
-- from the spells themselves. This is consistency, not a fix, and is written
-- separately so it can be dropped without touching the part that matters.
-- ---------------------------------------------------------------------------

UPDATE `creature_template`
SET `trainer_type` = 1
WHERE `entry` IN (@LENG, @SHUN);

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------

-- Both trainers, with the spell list they will actually serve: the direct rows
-- plus everything the reference block expands to. This mirrors the query in
-- ObjectMgr::LoadTrainerSpell, so an empty result here means an empty trainer
-- window in game.
SELECT `ct`.`entry`,
       `ct`.`name`,
       `ct`.`subname`,
       `ct`.`npcflag`,
       `ct`.`trainer_type`,
       (SELECT COUNT(*) FROM `creature` `c` WHERE `c`.`id` = `ct`.`entry`) AS `spawns`,
       (SELECT COUNT(*)
          FROM `npc_trainer` `a`
          JOIN `npc_trainer` `b` ON `a`.`entry` = -(`b`.`spell`)
         WHERE `b`.`entry` = `ct`.`entry`)                                  AS `spells_via_ref`,
       (SELECT COUNT(*)
          FROM `npc_trainer` `d`
         WHERE `d`.`entry` = `ct`.`entry` AND `d`.`spell` > 0)              AS `spells_direct`
FROM `creature_template` `ct`
WHERE `ct`.`entry` IN (@LENG, @SHUN)
ORDER BY `ct`.`entry`;

-- Every spell each trainer ends up offering, resolved the same way the server
-- resolves it. Wisdom of the Four Winds must appear once per trainer.
SELECT `b`.`entry` AS `trainer`, `a`.`spell`, `a`.`spellcost`, `a`.`reqskill`, `a`.`reqskillvalue`, `a`.`reqlevel`
FROM `npc_trainer` `a`
JOIN `npc_trainer` `b` ON `a`.`entry` = -(`b`.`spell`)
WHERE `b`.`entry` IN (@LENG, @SHUN)
UNION
SELECT `entry`, `spell`, `spellcost`, `reqskill`, `reqskillvalue`, `reqlevel`
FROM `npc_trainer`
WHERE `entry` IN (@LENG, @SHUN) AND `spell` > 0
ORDER BY `trainer`, `reqlevel`, `spell`;
