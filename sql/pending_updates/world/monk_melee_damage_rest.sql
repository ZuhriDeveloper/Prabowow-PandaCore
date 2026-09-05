-- The rest of the monk kit, on the same footing as 2026_09_05_world_00.sql: Spinning
-- Crane Kick, Rushing Jade Wind, Fists of Fury, Keg Smash and Expel Harm.
--
-- Their DBC damage effect carries a placeholder too (1, or 100 for the Fists of Fury
-- tick), while MoP keeps the real coefficient in the tooltip text -- "[1.59 * <low>]",
-- "[7.5 * <low>]", "[10.00 * <low>]", "[7 * <low>]" -- and builds the number out of
-- weapon damage per second plus attack power.
--
-- Spinning Crane Kick, Rushing Jade Wind and Fists of Fury deal their damage through a
-- spell the channel triggers, so the script goes on the triggered spell. Keg Smash and
-- Expel Harm already have script rows and only gained a damage hook.

DELETE FROM `spell_script_names` WHERE `ScriptName` IN
    ('spell_monk_spinning_crane_kick_damage', 'spell_monk_rushing_jade_wind_damage',
     'spell_monk_fists_of_fury_damage');
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
(107270, 'spell_monk_spinning_crane_kick_damage'),   -- triggered every 0.75 sec
(148187, 'spell_monk_rushing_jade_wind_damage'),     -- triggered every 0.75 sec
(117418, 'spell_monk_fists_of_fury_damage');         -- triggered every 1 sec

-- Pin the spell power coefficient at 0, as the first batch did: the scripts already
-- carry the attack power share, and the default coefficient would otherwise let a
-- mana-using monk add intellect based spell power to a physical strike. Expel Harm
-- needs it on both halves, since the same coefficient applies to healing.
DELETE FROM `spell_bonus_data` WHERE `entry` IN (107270, 115072, 115129, 117418, 121253, 148187);
INSERT INTO `spell_bonus_data` (`entry`, `direct_bonus`, `dot_bonus`, `ap_bonus`, `ap_dot_bonus`, `comments`) VALUES
(107270, 0, 0, 0, 0, 'Monk - Spinning Crane Kick tick (weapon damage handled by spell_monk_spinning_crane_kick_damage)'),
(148187, 0, 0, 0, 0, 'Monk - Rushing Jade Wind tick (weapon damage handled by spell_monk_rushing_jade_wind_damage)'),
(117418, 0, 0, 0, 0, 'Monk - Fists of Fury tick (weapon damage handled by spell_monk_fists_of_fury_damage)'),
(121253, 0, 0, 0, 0, 'Monk - Keg Smash (weapon damage handled by spell_monk_keg_smash)'),
(115072, 0, 0, 0, 0, 'Monk - Expel Harm (healing handled by spell_monk_expel_harm)'),
(115129, 0, 0, 0, 0, 'Monk - Expel Harm area damage (half of the healing, passed in by the script)');
