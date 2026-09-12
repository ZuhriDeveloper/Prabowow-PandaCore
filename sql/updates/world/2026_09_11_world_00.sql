-- Portal ke The Jade Forest di Stormwind dan Orgrimmar.
--
-- Gejala
--   Tidak ada portal ke Pandaria di kedua ibu kota. Pemain level 85 tidak punya
--   jalan masuk ke map 870 selain lewat GM .tele.
--
-- Sebabnya: portalnya SUDAH ADA, tujuannya yang tidak ada
--   Ini bukan konten yang hilang. SFDB sudah memasang dua portal Pandaria,
--   lengkap dengan model dan spawn-nya, sejak rilis 10_to_11:
--
--     sql/old/5.4.8/world/SFDB_release_10_to_11/2015_07_16_00_some_spawn_orgrimmar_&_stormwind.sql
--       215424  'Portal to Honydew Village'  type 22, display 12658, faction 1735
--       215457  'Portal to Paw don Village'  type 22, display 12658, faction 1819
--       spawn   215424 -> map 1 (Orgrimmar)  2014.819, -4700.274, 28.62439, o 5.751331
--       spawn   215457 -> map 0 (Stormwind) -8194.479,  528.1129, 117.2901,  o 0
--
--   Honeydew Village dan Paw'don Village adalah pangkalan pertama Horde dan
--   Alliance di The Jade Forest, jadi pasangan kota-ke-faksinya memang sudah
--   benar sejak awal.
--
--   type 22 = GAMEOBJECT_TYPE_SPELLCASTER. GameObject.cpp:1853 mengambil
--   `data0` sebagai spellId, lalu GameObject.cpp:1447 dan :2041 membuat PEMAIN
--   yang merapalnya ke dirinya sendiri. Jadi seluruh mekanismenya bergantung
--   pada satu hal: spell di `data0` harus punya tujuan.
--
--   Dan di situlah lubangnya. `data0` kedua portal ini adalah 130698 (Honeydew)
--   dan 130703 (Paw'don) -- dikonfirmasi pada skema modern di
--   sql/old/5.4.8/world/SFDB_release_14_to_15/2017_03_09_00_gameobject_template.sql:1979-1980,
--   di mana entry kembarannya 216057/216058 memakai display dan spell yang sama
--   persis dengan kolom lengkap, sehingga posisi `data0` tidak perlu ditebak.
--
--   Kedua spell itu TIDAK punya satu pun baris `spell_target_position` di
--   seluruh sql/old. Tanpa baris itu SpellMgr.cpp:1520 tidak pernah memuat
--   tujuan apa pun untuk keduanya, jadi efek teleportnya mendarat di
--   ketiadaan: portalnya berdiri, animasinya jalan, pemainnya tidak pindah.
--
-- Perbaikannya
--   Arahkan `data0` ke dua spell teleport Jade Forest yang tujuannya MEMANG
--   sudah ada di DB:
--
--     130321  Alliance  spell_target_position effIndex 0
--             sql/old/5.4.8/world/SFDB_Release_20.2_to_20.3/2020_02_22_02_world.sql
--             870, -668.56, -1482.19, 130.2, 5.97
--     125060  Horde     spell_target_position effIndex 1
--             sql/old/5.4.8/world/SFDB_Release_20.2_to_20.3/2020_02_21_01_world.sql
--             870, 3138.64, -721.332, 324.9845, 0.38
--
--   Keduanya dipakai SFDB sendiri untuk gossip kapal Sky Admiral Rogers (66292)
--   dan General Nazgrim (55054), jadi keduanya sudah terbukti punya
--   TARGET_DEST_DB -- SpellMgr.cpp:1578 membuang baris yang tidak punya itu,
--   dan baris keduanya bertahan. Ini juga titik mendarat yang sama dengan yang
--   dipakai Pandaria Emissary, jadi portal dan emissary mengantar ke tempat yang
--   sama persis.
--
-- Kenapa tidak menambah baris spell_target_position untuk 130698/130703 saja
--   Karena effIndex-nya tidak bisa diketahui dari SQL. SpellMgr.cpp:1570 hanya
--   menerima baris yang effIndex-nya benar-benar ber-TARGET_DEST_DB, dan indeks
--   itu ada di Spell.dbc, bukan di DB -- 130321 memakai 0 sementara 125060
--   memakai 1, jadi menebak bukan pilihan. Menulis dua-duanya untuk berjaga
--   berarti satu di antaranya pasti jadi baris error sql.sql di setiap boot.
--   Menunjuk ke spell yang tujuannya sudah terpasang tidak menambah satu pun
--   baris baru ke tabel mana pun.
--
-- Yang SENGAJA tidak ada di file ini
--   Kunci level. Emissary punya kunci level 85 karena kuncinya menempel di
--   `gossip_menu_option` miliknya sendiri. Portal tidak punya gossip, jadi
--   kuncinya harus lewat CONDITION_SOURCE_TYPE_SPELL (17, ConditionMgr.h:122)
--   pada spell-nya -- dan spell itu dipakai bersama gossip kapal SFDB, sehingga
--   kuncinya akan ikut mengunci konten yang tidak diminta siapa pun. Portal
--   retail juga tidak pernah mengunci level. Kalau nanti tetap diinginkan:
--
--     INSERT INTO `conditions`
--         (`SourceTypeOrReferenceId`, `SourceGroup`, `SourceEntry`, `SourceId`, `ElseGroup`,
--          `ConditionTypeOrReference`, `ConditionTarget`,
--          `ConditionValue1`, `ConditionValue2`, `ConditionValue3`,
--          `NegativeCondition`, `ErrorType`, `ErrorTextId`, `ScriptName`)
--     VALUES (17, 0, 130321, 0, 0, 27, 0, 85, 3, 0, 0, 0, 0, ''),
--            (17, 0, 125060, 0, 0, 27, 0, 85, 3, 0, 0, 0, 0, '');
--
-- Idempotent
--   Template hanya di-UPDATE, tidak pernah dibuat ulang, jadi nama, model dan
--   faction milik SFDB tetap utuh. Baris template hanya di-INSERT kalau memang
--   tidak ada. Spawn hanya ditambahkan kalau entry itu belum berdiri di peta
--   yang bersangkutan, dan spawn milik file ini tinggal di blok guid sendiri.
--
-- Membatalkannya
--   UPDATE `gameobject_template` SET `data0` = 130703 WHERE `entry` = 215457;
--   UPDATE `gameobject_template` SET `data0` = 130698 WHERE `entry` = 215424;
--   DELETE FROM `gameobject` WHERE `guid` BETWEEN 8460001 AND 8460099;
--
-- Catatan untuk rilis SFDB berikutnya
--   Kalau rilis baru menulis ulang baris 215424/215457, `data0` kembali ke
--   130698/130703 dan portalnya mati lagi. Jalankan ulang file ini setelah
--   base DB diganti.

SET @GO_PORTAL_SW := 215457;      -- 'Portal to Paw don Village', Alliance
SET @GO_PORTAL_ORG := 215424;     -- 'Portal to Honydew Village', Horde

SET @SPELL_JF_A := 130321;        -- teleport Jade Forest, Alliance
SET @SPELL_JF_H := 125060;        -- teleport Jade Forest, Horde

-- 8450001-8450100 dipakai Pandaria Emissary, 8440001-8449999 dicadangkan
-- Vashj'ir, 84[0-3]xxxx dipakai port zona Cataclysm.
SET @GUID_BASE := 8460000;
SET @GUID_LAST := 8460099;

-- ---------------------------------------------------------------------------
-- 1. Pastikan template portalnya ada
--
-- Di DB yang dibangun dari base SFDB keduanya sudah ada dan bagian ini tidak
-- melakukan apa-apa. Ia baru berarti kalau base-nya lebih tua dari rilis
-- 10_to_11, dan tanpa baris template ObjectMgr.cpp menolak spawn-nya dengan
-- "gameobject entry not existed".
--
-- Nilai yang ditulis di sini disalin apa adanya dari baris SFDB, kecuali
-- `data0` yang memang jadi pokok perbaikan ini. Kolom yang tidak disebut
-- dibiarkan memakai default tabelnya.
-- ---------------------------------------------------------------------------

INSERT INTO `gameobject_template`
    (`entry`, `type`, `displayId`, `name`, `faction`, `flags`, `size`, `data0`, `data3`)
SELECT @GO_PORTAL_ORG, 22, 12658, 'Portal to Honydew Village', 1735, 0, 1, @SPELL_JF_H, 1
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `gameobject_template` `g` WHERE `g`.`entry` = @GO_PORTAL_ORG);

INSERT INTO `gameobject_template`
    (`entry`, `type`, `displayId`, `name`, `faction`, `flags`, `size`, `data0`, `data3`)
SELECT @GO_PORTAL_SW, 22, 12658, 'Portal to Paw don Village', 1819, 0, 1, @SPELL_JF_A, 1
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `gameobject_template` `g` WHERE `g`.`entry` = @GO_PORTAL_SW);

-- ---------------------------------------------------------------------------
-- 2. Inti perbaikannya: arahkan portal ke spell yang punya tujuan
--
-- `data3` = allowMounted (GameObject.h:253, spellcaster.allowMounted). SFDB
-- menyalakannya untuk portal Stormwind tapi tidak untuk yang Orgrimmar; tanpa
-- itu pemain berkuda harus turun dulu. Disamakan menyala untuk keduanya.
--
-- `type` = 22 ikut jadi syarat supaya file ini tidak pernah menulis ke baris
-- yang ternyata bukan portal lagi di rilis SFDB yang berbeda.
-- ---------------------------------------------------------------------------

UPDATE `gameobject_template`
SET `data0` = @SPELL_JF_A,
    `data3` = 1
WHERE `entry` = @GO_PORTAL_SW
  AND `type` = 22;

UPDATE `gameobject_template`
SET `data0` = @SPELL_JF_H,
    `data3` = 1
WHERE `entry` = @GO_PORTAL_ORG
  AND `type` = 22;

-- ---------------------------------------------------------------------------
-- 3. Pastikan portalnya benar-benar berdiri
--
-- Koordinatnya milik SFDB, bukan karangan: Orgrimmar di Valley of Strength dan
-- Stormwind di dekat Eastern Earthshrine, persis di baris spawn rilis
-- 10_to_11. rotation 0,0,0,1 juga disalin apa adanya dari sana.
--
-- Syaratnya "belum ada spawn entry ini di peta itu", bukan "belum ada spawn di
-- blok guid saya". Dengan begitu di DB yang sudah punya spawn SFDB-nya bagian
-- ini tidak melakukan apa-apa, dan tidak akan pernah ada dua portal berdiri
-- bertumpuk di titik yang sama.
-- ---------------------------------------------------------------------------

DELETE FROM `gameobject` WHERE `guid` BETWEEN @GUID_BASE + 1 AND @GUID_LAST;

INSERT INTO `gameobject`
    (`guid`, `id`, `map`, `position_x`, `position_y`, `position_z`, `orientation`,
     `rotation0`, `rotation1`, `rotation2`, `rotation3`,
     `spawntimesecs`, `animprogress`, `state`, `spawnMask`, `phaseid`, `phasegroup`)
SELECT @GUID_BASE + 1, @GO_PORTAL_ORG, 1, 2014.819, -4700.274, 28.62439, 5.751331,
       0, 0, 0, 1, 120, 255, 1, 1, 0, 0
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM `gameobject` `g` WHERE `g`.`id` = @GO_PORTAL_ORG AND `g`.`map` = 1);

INSERT INTO `gameobject`
    (`guid`, `id`, `map`, `position_x`, `position_y`, `position_z`, `orientation`,
     `rotation0`, `rotation1`, `rotation2`, `rotation3`,
     `spawntimesecs`, `animprogress`, `state`, `spawnMask`, `phaseid`, `phasegroup`)
SELECT @GUID_BASE + 2, @GO_PORTAL_SW, 0, -8194.479, 528.1129, 117.2901, 0,
       0, 0, 0, 1, 120, 255, 1, 1, 0, 0
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM `gameobject` `g` WHERE `g`.`id` = @GO_PORTAL_SW AND `g`.`map` = 0);

-- ---------------------------------------------------------------------------
-- 4. Laporan, dibaca di keluaran impor
--
-- `spell_punya_tujuan` harus 1 untuk kedua baris. Kalau 0, spell itu tidak
-- punya baris `spell_target_position` di DB ini dan portalnya tetap tidak akan
-- memindahkan siapa pun -- jalankan bagian 8 tools/dev/audit_pandaria_intro.sql
-- untuk melihat titik mendarat apa saja yang benar-benar ada.
--
-- `spawn` harus minimal 1 untuk masing-masing. Kalau 0 di salah satunya,
-- portalnya tidak berdiri di mana pun dan bagian 3 gagal menambahkannya.
-- ---------------------------------------------------------------------------

SELECT `gt`.`entry`,
       `gt`.`name`,
       `gt`.`type`,
       `gt`.`data0` AS `spell`,
       (SELECT COUNT(*) FROM `spell_target_position` `p` WHERE `p`.`id` = `gt`.`data0`) AS `spell_punya_tujuan`,
       (SELECT COUNT(*) FROM `gameobject` `g` WHERE `g`.`id` = `gt`.`entry`) AS `spawn`
FROM `gameobject_template` `gt`
WHERE `gt`.`entry` IN (@GO_PORTAL_SW, @GO_PORTAL_ORG);

SELECT `p`.`id` AS `spell`,
       `p`.`effIndex`,
       `p`.`target_map` AS `map`,
       `p`.`target_position_x` AS `x`,
       `p`.`target_position_y` AS `y`,
       `p`.`target_position_z` AS `z`
FROM `spell_target_position` `p`
WHERE `p`.`id` IN (@SPELL_JF_A, @SPELL_JF_H);
