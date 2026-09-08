-- Mount Hyjal: bikin emissary Cenarion memindahkan pemain lagi.
--
-- Latar belakang
--   Rantai Hyjal dimulai dari papan tugas: "Hero's Call: Mount Hyjal!" (27726)
--   untuk Alliance dan "Warchief's Command: Mount Hyjal!" (27721) untuk Horde.
--   Keduanya menyuruh pemain menemui Cenarion Emissary Jademoon di Stormwind
--   Keep (entry 15187) atau Cenarion Emissary Blackhoof di Orgrimmar (15188).
--   Emissary itu tidak menerbangkan pemain ke Hyjal -- tugasnya memindahkan
--   pemain ke Moonglade, tempat Emissary Windsong (39865) menerima kedua
--   breadcrumb itu dan memberi "As Hyjal Burns" (25316) yang berakhir di Ysera
--   di Nordrassil.
--
--   Di server ini gossip emissary tidak melakukan apa-apa, jadi rantainya buntu
--   di langkah pertama. File ini memasang kembali pilihan gossip, aksi
--   pemindahannya, dan Windsong di ujung Moonglade.
--
-- Kenapa teleport, bukan spell 86587 seperti aslinya
--   Data 4.3.4 memakai SMART_ACTION_CROSS_CAST dengan spell 86587 (Teleport:
--   Moonglade). Spell itu berasal dari DBC Cataclysm dan keberadaannya di
--   client 5.4.8 tidak bisa diperiksa lewat SQL. SMART_ACTION_TELEPORT tidak
--   punya ketergantungan DBC sama sekali, jadi itu yang dipakai. Harganya:
--   tidak ada animasi dan cast time teleport, pemain langsung pindah.
--
-- Kenapa koordinat tujuan dihitung, bukan ditulis
--   Sama seperti prabowow_heirloom_vendor_capitals.sql: yang pasti benar adalah
--   posisi NPC yang sudah ada di DB. Titik mendarat diambil 5 yard di depan
--   Windsong, menghadap balik ke arahnya, dengan cadangan koordinat spawn
--   aslinya kalau Windsong ternyata belum ter-spawn sama sekali.
--
-- Idempotent: baris milik file ini dihapus dulu, lalu diisi ulang. Yang bisa
-- saja sudah benar di SFDB (template, link quest, game_tele) hanya diisi kalau
-- belum ada, tidak pernah ditimpa.

SET @JADEMOON  := 15187;    -- Cenarion Emissary Jademoon, Stormwind Keep
SET @BLACKHOOF := 15188;    -- Cenarion Emissary Blackhoof, Orgrimmar
SET @WINDSONG  := 39865;    -- Emissary Windsong, Nighthaven
SET @MENU_ALLIANCE := 12129;
SET @MENU_HORDE    := 12125;

-- guid tetap di rentang modul, tepat di bawah blok yang dipakai
-- prabowow_hyjal_zone_spawns.sql (8400001+).
SET @GUID_WINDSONG := 8400000;

-- ---------------------------------------------------------------------------
-- 1. Emissary Windsong di Moonglade
--
-- Ia berada di zona 493, jadi tidak ikut terbawa file spawn zona 616. Tanpa dia
-- quest 27726 tidak bisa diserahkan dan 25316 tidak pernah ditawarkan.
-- ---------------------------------------------------------------------------

INSERT IGNORE INTO `creature_template`
    (`entry`, `modelid1`, `name`, `subname`, `minlevel`, `maxlevel`, `faction_A`, `faction_H`,
     `npcflag`, `speed_walk`, `speed_run`, `scale`, `npc_rank`, `baseattacktime`, `rangeattacktime`,
     `unit_class`, `unit_flags`, `unit_flags2`, `type`, `AIName`, `MovementType`, `InhabitType`,
     `HoverHeight`, `Health_mod`, `Mana_mod`, `Armor_mod`, `RegenHealth`, `ScriptName`,
     `ModLevel`, `detection_range`)
VALUES
    (@WINDSONG, 15321, 'Emissary Windsong', '', 80, 80, 2233, 2233,
     2, 1, 1.14286, 1, 0, 2000, 2000,
     8, 32768, 2048, 7, '', 0, 3,
     1, 1, 1, 1, 1, '',
     0, 20);

DELETE FROM `creature` WHERE `guid` = @GUID_WINDSONG;

INSERT INTO `creature`
    (`guid`, `id`, `map`, `modelid`, `equipment_id`, `position_x`, `position_y`, `position_z`,
     `orientation`, `spawntimesecs`, `spawndist`, `currentwaypoint`, `curhealth`, `curmana`,
     `MovementType`, `spawnMask`, `phaseid`, `phasegroup`, `npcflag`, `unit_flags`, `dynamicflags`)
SELECT @GUID_WINDSONG, @WINDSONG, 1, 0, 0, 7801.04, -2430.96, 487.675,
       0.296706, 300, 0, 0, 0, 0,
       0, 1, 0, 0, 0, 0, 0
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `creature` `c` WHERE `c`.`id` = @WINDSONG);

-- 27726 Alliance, 27721 Horde. Quest 29386 memakai judul yang sama tapi tidak
-- punya pemberi maupun penutup di data retail, jadi tidak diikutkan.
INSERT IGNORE INTO `creature_questender`   (`id`, `quest`) VALUES (@WINDSONG, 27726), (@WINDSONG, 27721);
INSERT IGNORE INTO `creature_queststarter` (`id`, `quest`) VALUES (@WINDSONG, 25316);

-- ---------------------------------------------------------------------------
-- 2. Titik mendarat di Moonglade
-- ---------------------------------------------------------------------------

SET @WX := COALESCE((SELECT `position_x`  FROM `creature` WHERE `id` = @WINDSONG LIMIT 1), 7801.04);
SET @WY := COALESCE((SELECT `position_y`  FROM `creature` WHERE `id` = @WINDSONG LIMIT 1), -2430.96);
SET @WZ := COALESCE((SELECT `position_z`  FROM `creature` WHERE `id` = @WINDSONG LIMIT 1), 487.675);
SET @WO := COALESCE((SELECT `orientation` FROM `creature` WHERE `id` = @WINDSONG LIMIT 1), 0.296706);

-- 5 yard di depan Windsong, sisi tempat lawan bicaranya berdiri.
SET @LAND_X := @WX + 5.0 * COS(@WO);
SET @LAND_Y := @WY + 5.0 * SIN(@WO);
SET @LAND_Z := @WZ;
SET @LAND_O := @WO + PI();      -- menghadap balik ke Windsong

-- ---------------------------------------------------------------------------
-- 3. Pilihan gossip di kedua emissary
--
-- Nama kolom gossip_menu ada dua varian di SkyFire (MenuID/TextID versus
-- entry/text_id, lihat GossipSchema.cpp), jadi baris teks salamnya dipasang
-- lewat statement yang dipilih dari information_schema. gossip_menu_option
-- hanya punya satu varian, jadi ditulis langsung.
-- ---------------------------------------------------------------------------

SET @GOSSIP_MENU_HAS_MENUID := (
    SELECT COUNT(*) FROM `information_schema`.`COLUMNS`
    WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = 'gossip_menu' AND `COLUMN_NAME` = 'MenuID');

SET @SQL := IF(@GOSSIP_MENU_HAS_MENUID > 0,
    'INSERT IGNORE INTO `gossip_menu` (`MenuID`, `TextID`) VALUES (12129, 17035), (12125, 17031)',
    'INSERT IGNORE INTO `gossip_menu` (`entry`, `text_id`) VALUES (12129, 17035), (12125, 17031)');
PREPARE stmt FROM @SQL;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DELETE FROM `gossip_menu_option`
WHERE `MenuID` IN (@MENU_ALLIANCE, @MENU_HORDE) AND `OptionID` = 0;

INSERT INTO `gossip_menu_option`
    (`MenuID`, `OptionID`, `OptionIcon`, `OptionText`, `OptionBroadcastTextID`, `OptionType`,
     `OptionNpcflag`, `ActionMenuID`, `ActionPoiID`, `BoxCoded`, `BoxMoney`, `BoxText`, `BoxBroadcastTextID`)
VALUES
    (@MENU_ALLIANCE, 0, 0, 'Could you please send me to Moonglade, Emissary?', 46530, 1, 1, 0, 0, 0, 0, '', 0),
    (@MENU_HORDE,    0, 0, 'Could you please send me to Moonglade, Emissary?', 46530, 1, 1, 0, 0, 0, 0, '', 0);

-- Menu-nya harus benar-benar menempel di NPC, dan npcflag GOSSIP (0x1) harus
-- menyala supaya pilihannya dikirim ke client. AIName dipaksa SmartAI dan
-- ScriptName dikosongkan: script C++ yang mungkin tertulis di sana tidak ada di
-- core ini, dan kalau keduanya terisi core hanya mengeluh di log.
UPDATE `creature_template`
SET `gossip_menu_id` = @MENU_ALLIANCE, `npcflag` = `npcflag` | 1, `AIName` = 'SmartAI', `ScriptName` = ''
WHERE `entry` = @JADEMOON;

UPDATE `creature_template`
SET `gossip_menu_id` = @MENU_HORDE, `npcflag` = `npcflag` | 1, `AIName` = 'SmartAI', `ScriptName` = ''
WHERE `entry` = @BLACKHOOF;

-- ---------------------------------------------------------------------------
-- 4. Aksinya
--
-- SMART_EVENT_GOSSIP_SELECT (62) menerima menuId dan gossipListId. Menu ini
-- cuma punya satu pilihan, jadi list id-nya 0. Baris pertama menutup jendela
-- gossip, baris kedua (SMART_EVENT_LINK) memindahkan si penekan tombol:
-- SMART_ACTION_TELEPORT (62) memakai action_param1 sebagai map dan target_x/y/z
-- sebagai tujuan, dengan target SMART_TARGET_ACTION_INVOKER (7) supaya yang
-- pindah pemainnya, bukan NPC-nya.
-- ---------------------------------------------------------------------------

DELETE FROM `smart_scripts` WHERE `source_type` = 0 AND `entryorguid` IN (@JADEMOON, @BLACKHOOF);

INSERT INTO `smart_scripts`
    (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
     `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`,
     `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
     `target_type`, `target_param1`, `target_param2`, `target_param3`,
     `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
    (@JADEMOON, 0, 0, 1, 62, 0, 100, 0, @MENU_ALLIANCE, 0, 0, 0, 0,
     72, 0, 0, 0, 0, 0, 0,
     1, 0, 0, 0, 0, 0, 0, 0,
     'Cenarion Emissary Jademoon - On gossip select - Close gossip'),
    (@JADEMOON, 0, 1, 0, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     62, 1, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @LAND_X, @LAND_Y, @LAND_Z, @LAND_O,
     'Cenarion Emissary Jademoon - Linked - Teleport player to Moonglade'),
    (@BLACKHOOF, 0, 0, 1, 62, 0, 100, 0, @MENU_HORDE, 0, 0, 0, 0,
     72, 0, 0, 0, 0, 0, 0,
     1, 0, 0, 0, 0, 0, 0, 0,
     'Cenarion Emissary Blackhoof - On gossip select - Close gossip'),
    (@BLACKHOOF, 0, 1, 0, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     62, 1, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @LAND_X, @LAND_Y, @LAND_Z, @LAND_O,
     'Cenarion Emissary Blackhoof - Linked - Teleport player to Moonglade');

-- ---------------------------------------------------------------------------
-- 5. Titik .tele untuk GM
--
-- Koordinatnya dari game_tele 'MountHyjal' di dump 4.3.4, satu-satunya angka
-- Hyjal di sini yang sudah terbukti dipakai server lain.
-- ---------------------------------------------------------------------------

SET @TELE_ID := (SELECT COALESCE(MAX(`id`), 0) + 1 FROM `game_tele`);

INSERT INTO `game_tele` (`id`, `position_x`, `position_y`, `position_z`, `orientation`, `map`, `name`)
SELECT @TELE_ID, 5075.76, -3201.27, 1889.44, 1.41445, 1, 'MountHyjal'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `game_tele` `t` WHERE `t`.`name` = 'MountHyjal');
