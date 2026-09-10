-- Pandaria: pasang quest intronya di papan tugas, dan sediakan tumpangannya.
--
-- Gejala
--   Pemain level 85 membuka Hero's Call Board di Stormwind atau Warchief's
--   Command Board di Orgrimmar dan tidak melihat satu pun quest yang mengarah ke
--   Pandaria. Tidak ada jalan masuk ke map 870 sama sekali.
--
-- Sebabnya: bukan gerbang expansion
--   Core ini tidak punya SatisfyQuestExpansion sama sekali -- CanTakeQuest
--   (PlayerQuestState.cpp:248-259) menjalankan 17 pemeriksaan Satisfy* dan tidak
--   satu pun soal expansion. `quest_template` juga tidak punya kolomnya.
--   Expansion = 4 (worldserver.conf.dist:800), MaxPlayerLevel = 90,
--   `account`.`expansion` default 4, gamebuild 18414. Tidak ada yang menghalangi
--   pemain level 85.
--
--   Papan tugas itu GAMEOBJECT_TYPE_QUESTGIVER polos tanpa script C++:
--   GameObject.cpp:1480-1490 -> Player::PrepareGossipMenu -> PrepareQuestMenu
--   (PlayerQuestState.cpp:29-87). Untuk GO, fungsi itu HANYA membaca
--   `gameobject_queststarter` dan `gameobject_questender`. Dan dump SFDB tidak
--   punya satu pun baris papan untuk quest intro Pandaria:
--
--     29547 The King's Command   (A) MinLevel 85, zona 1519 -- tanpa pemberi
--     29611 The Art of War       (H) MinLevel 85, zona 1637 -- tanpa pemberi
--     29612 The Art of War (alt) (H) MinLevel 85, zona 1637 -- tanpa pemberi
--
--   Jadi mekanismenya sehat, isinya yang kosong. Papan yang sama sudah terbukti
--   membagikan "Hero's Call: Mount Hyjal!" (27726) di realm ini.
--
-- Perbaikannya, dua bagian yang berdiri sendiri
--   1. Quest intronya ditempelkan ke papan. Itu menjawab keluhannya secara
--      harfiah: papan menunjukkan Pandaria ada dan ke mana harus pergi.
--   2. Sepasang emissary berdiri di samping tiap papan dan memindahkan pemain ke
--      The Jade Forest. Ini jaring pengaman, bukan pengganti rantai quest-nya:
--      src/server/scripts/Pandaria/ tidak punya script Jade Forest maupun
--      gunship Skyfire, jadi penerbangan kapal versi retail tidak akan jalan.
--      Polanya persis Cenarion Emissary di sql/updates/world/2026_09_08_world_01.sql.
--
-- Yang SENGAJA belum ada di file ini
--   Baris yang menandai breadcrumb selesai, dan baris questender 29547 /
--   queststarter 29548. Keduanya bergantung pada dua hal yang cuma bisa dibaca
--   dari DB hidup, lewat tools/dev/audit_pandaria_intro.sql:
--
--     - Bentuk objective 29547 di tabel `quest_objective`. Kalau tipenya 0 (NPC)
--       penandanya SMART_ACTION_CALL_KILLEDMONSTER (33) dengan objectId-nya;
--       kalau 10 (DUMMY) penandanya SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS
--       (15). Memasang yang salah tidak merusak apa pun, tapi juga tidak
--       melakukan apa pun -- jadi menebak tidak ada gunanya. Nama creature 55567
--       di SFDB adalah "Kill Credit: A King's Request", yang mengarah kuat ke
--       tipe 0, tapi itu tetap dugaan sampai barisnya dibaca.
--     - Siapa NPC Jes-Tereth yang sebenarnya dan apakah ia terspawn. 55567 sudah
--       pasti BUKAN dia -- itu bunny kill-credit dengan npcflag 0, tidak bisa
--       diajak bicara.
--
--   Emissary di file ini sengaja TIDAK menyelesaikan breadcrumb apa pun. Ia
--   transportasi, bukan jalan pintas: objective 29547 adalah "temui Jes-Tereth",
--   dan diantar ke Pandaria bukan itu. Bandingkan dengan Hyjal, di mana
--   objective-nya memang "Transportation to Moonglade Secured" sehingga
--   emissary-nya memang pantas menandainya.
--
-- Idempotent
--   Semua baris milik file ini dihapus dulu lalu diisi ulang. Baris papan
--   dihapus per-quest, bukan per-papan, supaya file ini jadi pemilik tunggal
--   ketiga quest itu dan hasilnya selalu sama berapa kali pun dijalankan.
--
-- Alternatif yang dipertimbangkan dan ditolak
--   Memasang gossip langsung di GO papannya (MiscHandler.cpp:653-727 memang
--   meneruskan gossip select GO ke GameObjectAI, dan SMART_EVENT_GOSSIP_SELECT
--   punya mask GAMEOBJECT). Elegan, tanpa NPC baru, dan otomatis benar
--   faksinya. Tapi ia menuntut menulis `data3` dan `AIName` ke baris
--   `gameobject_template` bersama yang dipakai 13 entry papan; satu salah tulis
--   mematikan papannya untuk semua orang. Tidak sepadan.

SET @Q_KINGS_COMMAND  := 29547;   -- The King's Command       (Alliance)
SET @Q_ART_OF_WAR     := 29611;   -- The Art of War           (Horde)
SET @Q_ART_OF_WAR_ALT := 29612;   -- The Art of War, versi penyintas Vashj'ir

SET @EMISSARY_A := 900002;        -- melanjutkan 900001 milik mod-prabowow
SET @EMISSARY_H := 900003;
SET @MENU_A     := 900002;
SET @MENU_H     := 900003;

-- Blok guid 8450001+ masih kosong: 8440001-8449999 dicadangkan Vashj'ir.
SET @GUID_BASE  := 8450000;
SET @GUID_LAST  := 8450100;

-- ---------------------------------------------------------------------------
-- 1. Quest intro ditempelkan ke papan
--
-- Entry papan diambil dari DB hidup, bukan dari daftar mati, dengan `type` = 2
-- sebagai syarat. Dengan begitu dua error yang biasa muncul jadi mustahil:
-- ObjectMgr.cpp:7274 ("not existed gameobject entry") dan :7276 ("not
-- GAMEOBJECT_TYPE_QUESTGIVER"). Identifikasinya ganda -- daftar entry dari dump
-- 4.3.4 ATAU namanya -- supaya papan yang hanya ada di SFDB tetap kebagian.
--
-- Hanya 29611 yang dipasang, bukan 29612. Judul keduanya sama persis, dan
-- PrepareQuestMenu memanggil CanTakeQuest per quest: untuk Horde level 85 yang
-- masih bersih keduanya lolos, jadi papannya akan menampilkan dua baris kembar.
-- ExclusiveGroup negatif tidak menolong -- ia baru menyembunyikan saudaranya
-- SETELAH salah satunya diserahkan. Teks 29612 juga mengandaikan pemain selamat
-- dari Vashj'ir, jadi menjadikannya versi umum justru salah. Penutupnya (54870)
-- dibiarkan utuh supaya siapa pun yang terlanjur memegangnya tetap bisa selesai.
-- ---------------------------------------------------------------------------

DELETE FROM `gameobject_queststarter`
WHERE `quest` IN (@Q_KINGS_COMMAND, @Q_ART_OF_WAR, @Q_ART_OF_WAR_ALT);

INSERT INTO `gameobject_queststarter` (`id`, `quest`)
SELECT `gt`.`entry`, @Q_KINGS_COMMAND
FROM `gameobject_template` `gt`
WHERE `gt`.`type` = 2
  AND (`gt`.`entry` IN (206111, 206294, 207320, 207321, 207322, 208316)
       OR `gt`.`name` = 'Hero''s Call Board')
  AND EXISTS (SELECT 1 FROM `quest_template` `q` WHERE `q`.`Id` = @Q_KINGS_COMMAND);

INSERT INTO `gameobject_queststarter` (`id`, `quest`)
SELECT `gt`.`entry`, @Q_ART_OF_WAR
FROM `gameobject_template` `gt`
WHERE `gt`.`type` = 2
  AND (`gt`.`entry` IN (206109, 206116, 207279, 207323, 207324, 207325, 208317)
       OR `gt`.`name` = 'Warchief''s Command Board')
  AND EXISTS (SELECT 1 FROM `quest_template` `q` WHERE `q`.`Id` = @Q_ART_OF_WAR);

-- ---------------------------------------------------------------------------
-- 2. Emissary
--
-- npcflag 3 = GOSSIP (0x1) + QUESTGIVER (0x2). Bit GOSSIP wajib dan bukan cuma
-- soal menu: tanpa itu client mengirim CMSG_QUESTGIVER_HELLO, dan jalur itu
-- tidak pernah memanggil Player::TalkedToCreature -- hanya NPCHandler.cpp:341
-- yang memanggilnya. Bit QUESTGIVER dipasang sekarang supaya baris questender
-- yang menyusul setelah audit tidak perlu menyentuh template lagi; tanpa relasi
-- quest ia tidak melakukan apa-apa.
--
-- faction 35 = ramah ke semua, jadi tidak ada yang bisa menyerangnya.
-- flags_extra 0x200000 = CREATURE_FLAG_EXTRA_ALL_PHASES (Creature.h:44), flag
-- custom yang sama dipakai vendor heirloom: ibu kota penuh phasing dan tanpa ini
-- emissary-nya hilang untuk sebagian pemain.
-- ModLevel 0, karena 1 memaksa level creature jadi 90 lewat jalur lain.
--
-- Model dipinjam dari NPC yang memang ada di SFDB supaya wajahnya masuk akal per
-- faksi, dengan 15321 sebagai cadangan -- model itu sudah terbukti tampil di
-- server ini lewat Emissary Windsong.
-- ---------------------------------------------------------------------------

SET @MODEL_A := COALESCE((SELECT `modelid1` FROM `creature_template`
                          WHERE `entry` = 66292 AND `modelid1` > 0), 15321);
SET @MODEL_H := COALESCE((SELECT `modelid1` FROM `creature_template`
                          WHERE `entry` = 54870 AND `modelid1` > 0), 15321);

DELETE FROM `creature`          WHERE `id`    IN (@EMISSARY_A, @EMISSARY_H);
DELETE FROM `creature`          WHERE `guid`  BETWEEN @GUID_BASE + 1 AND @GUID_LAST;
DELETE FROM `creature_template` WHERE `entry` IN (@EMISSARY_A, @EMISSARY_H);

INSERT INTO `creature_template`
    (`entry`, `modelid1`, `name`, `subname`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`,
     `faction_A`, `faction_H`, `npcflag`, `speed_walk`, `speed_run`, `scale`, `npc_rank`,
     `baseattacktime`, `rangeattacktime`, `unit_class`, `unit_flags`, `unit_flags2`, `type`,
     `AIName`, `MovementType`, `InhabitType`, `HoverHeight`, `Health_mod`, `Mana_mod`,
     `Armor_mod`, `RegenHealth`, `flags_extra`, `ScriptName`, `ModLevel`, `detection_range`)
VALUES
    (@EMISSARY_A, @MODEL_A, 'Pandaria Emissary', 'Alliance Vanguard', @MENU_A, 90, 90, 4,
     35, 35, 3, 1, 1.14286, 1, 0,
     2000, 2000, 8, 32768, 2048, 7,
     'SmartAI', 0, 3, 1, 1, 1,
     1, 1, 0x200000, '', 0, 20),
    (@EMISSARY_H, @MODEL_H, 'Pandaria Emissary', 'Horde Vanguard', @MENU_H, 90, 90, 4,
     35, 35, 3, 1, 1.14286, 1, 0,
     2000, 2000, 8, 32768, 2048, 7,
     'SmartAI', 0, 3, 1, 1, 1,
     1, 1, 0x200000, '', 0, 20);

-- ---------------------------------------------------------------------------
-- 3. Spawn: satu emissary per papan yang benar-benar berdiri
--
-- Posisinya diturunkan dari papan itu sendiri -- dua yard di depannya,
-- menghadap pemain yang baru saja membacanya. Jadi tidak ada satu pun koordinat
-- kota yang ditulis mati, dan kota mana pun yang punya papan otomatis kebagian,
-- termasuk yang belum kita tahu. Pola yang sama dipakai vendor heirloom di
-- 2026_09_02_world_02.sql, yang menurunkan posisinya dari `playercreateinfo`.
--
-- guid-nya dari ROW_NUMBER(), bukan variabel yang dinaikkan di dalam SELECT:
-- urutan evaluasi variabel di dalam SELECT tidak dijamin MySQL 8.
-- ---------------------------------------------------------------------------

INSERT INTO `creature`
    (`guid`, `id`, `map`, `modelid`, `equipment_id`,
     `position_x`, `position_y`, `position_z`, `orientation`,
     `spawntimesecs`, `spawndist`, `currentwaypoint`, `curhealth`, `curmana`,
     `MovementType`, `spawnMask`, `phaseid`, `phasegroup`,
     `npcflag`, `unit_flags`, `dynamicflags`)
SELECT @GUID_BASE + ROW_NUMBER() OVER (ORDER BY `papan`.`name`, `papan`.`map`, `papan`.`guid`),
       `papan`.`emissary`,
       `papan`.`map`, 0, 0,
       `papan`.`position_x` + 2 * COS(`papan`.`orientation`),
       `papan`.`position_y` + 2 * SIN(`papan`.`orientation`),
       `papan`.`position_z`,
       MOD(`papan`.`orientation` + PI(), 2 * PI()),
       300, 0, 0, 0, 0,
       0, 1, 0, 0, 0, 0, 0
FROM (
    SELECT `g`.`guid`, `g`.`map`, `g`.`position_x`, `g`.`position_y`, `g`.`position_z`,
           `g`.`orientation`, `gt`.`name`,
           CASE WHEN `gt`.`name` = 'Hero''s Call Board' THEN @EMISSARY_A ELSE @EMISSARY_H END AS `emissary`
    FROM `gameobject` `g`
    JOIN `gameobject_template` `gt` ON `gt`.`entry` = `g`.`id`
    WHERE `gt`.`type` = 2
      AND `gt`.`name` IN ('Hero''s Call Board', 'Warchief''s Command Board')
) `papan`;

-- ---------------------------------------------------------------------------
-- 4. Gossip
--
-- Nama kolom `gossip_menu` ada dua varian di SkyFire (MenuID/TextID versus
-- entry/text_id), jadi baris salamnya dipasang lewat statement yang dipilih dari
-- information_schema -- sama seperti 2026_09_08_world_01.sql.
-- `gossip_menu_option` hanya punya satu varian, jadi ditulis langsung.
--
-- Teks 17035 / 17031 dipinjam dari Cenarion Emissary: salam generik "ada yang
-- bisa saya bantu". Peminjaman yang disadari, bukan kebetulan.
-- ---------------------------------------------------------------------------

SET @GOSSIP_MENU_HAS_MENUID := (
    SELECT COUNT(*) FROM `information_schema`.`COLUMNS`
    WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = 'gossip_menu' AND `COLUMN_NAME` = 'MenuID');

SET @SQL := IF(@GOSSIP_MENU_HAS_MENUID > 0,
    'INSERT IGNORE INTO `gossip_menu` (`MenuID`, `TextID`) VALUES (900002, 17035), (900003, 17031)',
    'INSERT IGNORE INTO `gossip_menu` (`entry`, `text_id`) VALUES (900002, 17035), (900003, 17031)');
PREPARE stmt FROM @SQL;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DELETE FROM `gossip_menu_option` WHERE `MenuID` IN (@MENU_A, @MENU_H);

INSERT INTO `gossip_menu_option`
    (`MenuID`, `OptionID`, `OptionIcon`, `OptionText`, `OptionBroadcastTextID`, `OptionType`,
     `OptionNpcflag`, `ActionMenuID`, `ActionPoiID`, `BoxCoded`, `BoxMoney`, `BoxText`, `BoxBroadcastTextID`)
VALUES
    (@MENU_A, 0, 0, 'Send me to Pandaria.', 0, 1, 1, 0, 0, 0, 0, '', 0),
    (@MENU_H, 0, 0, 'Send me to Pandaria.', 0, 1, 1, 0, 0, 0, 0, '', 0);

-- Pilihannya dikunci level 85. Emissary berdiri di alun-alun ibu kota, terbuka
-- untuk siapa saja; tanpa kunci ini seorang level 10 bisa mengklik dan mati di
-- zona level 85 tanpa jalan pulang selain hearthstone.
--   SourceTypeOrReferenceId 15 = CONDITION_SOURCE_TYPE_GOSSIP_MENU_OPTION
--                                (ConditionMgr.h:120), SourceGroup = MenuID dan
--                                SourceEntry = OptionID (ConditionMgr.cpp:1183)
--   ConditionTypeOrReference 27 = CONDITION_LEVEL (ConditionMgr.h:51)
--   ConditionValue2 3           = COMP_TYPE_HIGH_EQ (Util.h:692), jadi
--                                 level >= ConditionValue1
DELETE FROM `conditions`
WHERE `SourceTypeOrReferenceId` = 15 AND `SourceGroup` IN (@MENU_A, @MENU_H);

INSERT INTO `conditions`
    (`SourceTypeOrReferenceId`, `SourceGroup`, `SourceEntry`, `SourceId`, `ElseGroup`,
     `ConditionTypeOrReference`, `ConditionTarget`,
     `ConditionValue1`, `ConditionValue2`, `ConditionValue3`,
     `NegativeCondition`, `ErrorType`, `ErrorTextId`, `ScriptName`)
VALUES
    (15, @MENU_A, 0, 0, 0, 27, 0, 85, 3, 0, 0, 0, 0, ''),
    (15, @MENU_H, 0, 0, 0, 27, 0, 85, 3, 0, 0, 0, 0, '');

-- ---------------------------------------------------------------------------
-- 5. Titik mendarat di The Jade Forest (map 870)
--
-- Angkanya bukan tebakan. SFDB sendiri sudah memasang gossip "I am ready to
-- depart." pada Sky Admiral Rogers (66292, menu 14971) dan General Nazgrim
-- (55054, menu 14988); keduanya menyuruh pemain merapal spell teleport, dan
-- tujuan spell itu ada di `spell_target_position`:
--
--   sql/old/5.4.8/world/SFDB_Release_20.2_to_20.3/2020_02_22_02_world.sql
--       (130321, 0, 870, -668.56, -1482.19, 130.2, 5.97)     -- Alliance
--   sql/old/5.4.8/world/SFDB_Release_20.2_to_20.3/2020_02_21_01_world.sql
--       (125060, 1, 870, 3138.64, -721.332, 324.9845, 0.38)  -- Horde
--
-- Dibaca dari DB kalau ada, jatuh ke angka yang sama sebagai literal kalau
-- tidak. Pola yang sama dipakai 2026_09_08_world_01.sql untuk Moonglade.
--
-- Keduanya WAJIB dicek dengan .go xyz sebelum file ini dipromosikan: angkanya
-- berasal dari delta 2020 dan belum pernah dilihat langsung di client 5.4.8.
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
-- 6. Aksinya
--
-- SMART_EVENT_GOSSIP_SELECT (62) menerima menuId dan gossipListId; menu ini
-- cuma punya satu pilihan, jadi list id-nya 0. Baris pertama menutup jendela
-- gossip, baris kedua (SMART_EVENT_LINK, 61) memindahkan si penekan tombol:
-- SMART_ACTION_TELEPORT (62) memakai action_param1 sebagai map dan
-- target_x/y/z/o sebagai tujuan, dengan SMART_TARGET_ACTION_INVOKER (7) supaya
-- yang pindah pemainnya, bukan NPC-nya.
-- ---------------------------------------------------------------------------

DELETE FROM `smart_scripts` WHERE `source_type` = 0 AND `entryorguid` IN (@EMISSARY_A, @EMISSARY_H);

INSERT INTO `smart_scripts`
    (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
     `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`,
     `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
     `target_type`, `target_param1`, `target_param2`, `target_param3`,
     `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
    (@EMISSARY_A, 0, 0, 1, 62, 0, 100, 0, @MENU_A, 0, 0, 0, 0,
     72, 0, 0, 0, 0, 0, 0,
     1, 0, 0, 0, 0, 0, 0, 0,
     'Pandaria Emissary (A) - On gossip select - Close gossip'),
    (@EMISSARY_A, 0, 1, 0, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     62, @JF_A_MAP, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @JF_A_X, @JF_A_Y, @JF_A_Z, @JF_A_O,
     'Pandaria Emissary (A) - Linked - Teleport player to The Jade Forest'),
    (@EMISSARY_H, 0, 0, 1, 62, 0, 100, 0, @MENU_H, 0, 0, 0, 0,
     72, 0, 0, 0, 0, 0, 0,
     1, 0, 0, 0, 0, 0, 0, 0,
     'Pandaria Emissary (H) - On gossip select - Close gossip'),
    (@EMISSARY_H, 0, 1, 0, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     62, @JF_H_MAP, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @JF_H_X, @JF_H_Y, @JF_H_Z, @JF_H_O,
     'Pandaria Emissary (H) - Linked - Teleport player to The Jade Forest');

-- ---------------------------------------------------------------------------
-- 7. Titik .tele untuk GM
-- ---------------------------------------------------------------------------

SET @TELE_ID := (SELECT COALESCE(MAX(`id`), 0) + 1 FROM `game_tele`);
INSERT INTO `game_tele` (`id`, `position_x`, `position_y`, `position_z`, `orientation`, `map`, `name`)
SELECT @TELE_ID, @JF_A_X, @JF_A_Y, @JF_A_Z, @JF_A_O, @JF_A_MAP, 'JadeForestA'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `game_tele` `t` WHERE `t`.`name` = 'JadeForestA');

SET @TELE_ID := (SELECT COALESCE(MAX(`id`), 0) + 1 FROM `game_tele`);
INSERT INTO `game_tele` (`id`, `position_x`, `position_y`, `position_z`, `orientation`, `map`, `name`)
SELECT @TELE_ID, @JF_H_X, @JF_H_Y, @JF_H_Z, @JF_H_O, @JF_H_MAP, 'JadeForestH'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `game_tele` `t` WHERE `t`.`name` = 'JadeForestH');

-- ---------------------------------------------------------------------------
-- 8. Laporan, dibaca di keluaran impor
--
-- `papan` harus bukan nol untuk kedua faksi, dan `emissary` harus sama dengan
-- jumlah papan. Kalau `papan` nol, papannya tidak terspawn di DB ini dan seluruh
-- perbaikan ini tidak akan terlihat oleh siapa pun -- jalankan
-- tools/dev/audit_pandaria_intro.sql bagian 1 untuk tahu kenapa.
-- ---------------------------------------------------------------------------

SELECT 'Hero''s Call Board' AS `papan`, COUNT(*) AS `entry_terpasang`
FROM `gameobject_queststarter` WHERE `quest` = @Q_KINGS_COMMAND
UNION ALL
SELECT 'Warchief''s Command Board', COUNT(*)
FROM `gameobject_queststarter` WHERE `quest` = @Q_ART_OF_WAR;

SELECT `gt`.`name` AS `papan`, COUNT(DISTINCT `g`.`guid`) AS `papan_terspawn`
FROM `gameobject` `g`
JOIN `gameobject_template` `gt` ON `gt`.`entry` = `g`.`id`
WHERE `gt`.`type` = 2
  AND `gt`.`name` IN ('Hero''s Call Board', 'Warchief''s Command Board')
GROUP BY `gt`.`name`;

SELECT `id` AS `emissary`, COUNT(*) AS `emissary_terspawn`
FROM `creature`
WHERE `id` IN (@EMISSARY_A, @EMISSARY_H)
GROUP BY `id`;

SELECT @JF_A_MAP AS `jade_forest_a_map`, @JF_A_X AS `x`, @JF_A_Y AS `y`, @JF_A_Z AS `z`,
       @JF_H_MAP AS `jade_forest_h_map`, @JF_H_X AS `hx`, @JF_H_Y AS `hy`, @JF_H_Z AS `hz`;
