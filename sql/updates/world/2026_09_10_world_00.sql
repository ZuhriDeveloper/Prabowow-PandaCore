-- Zona Cataclysm hasil port: bikin mayat mob bisa di-loot lagi.
--
-- Gejala
--   Mob level 80+ di Mount Hyjal tidak menjatuhkan apa pun. Bukan "loot-nya
--   jelek" -- mayatnya tidak berkilau, tidak bisa diklik, dan uang pun tidak
--   keluar. Gejala yang sama ada di Deepholm, Uldum, dan Twilight Highlands.
--
-- Sebabnya
--   Unit.cpp:6688 hanya memasang UNIT_DYNFLAG_LOOTABLE kalau salah satu dari dua
--   syarat terpenuhi:
--
--       if (cInfo && (cInfo->lootid || cInfo->maxgold > 0))
--           creature->SetFlag(OBJECT_FIELD_DYNAMIC_FLAGS, UNIT_DYNFLAG_LOOTABLE);
--
--   `lootid` = 0 DAN `maxgold` = 0 berarti flag itu tidak pernah dipasang sama
--   sekali. Pengisian loot dan uangnya sendiri ada di Unit.cpp:6581-6584, tapi
--   pengisian itu tidak pernah sempat berarti apa-apa karena mayatnya sudah
--   tidak bisa diklik lebih dulu.
--
--   tools/dev/port_zone_spawns.py:405-411 menyalin `lootid`, `mingold`, dan
--   `maxgold` apa adanya dari dump TrinityCore 4.3.4, dan di dump itu ketiganya
--   nol untuk mayoritas creature keempat zona ini. Jadi ini bukan kerusakan yang
--   dibuat port -- port cuma memindahkan lubang yang memang sudah ada di
--   sumbernya. Yang ikut diport dengan benar hanya ke-73 (Hyjal) sampai ke-127
--   (Twilight Highlands) loot table yang di dump-nya memang berisi.
--
-- Perbaikannya: pinjam lootid milik donor, jangan salin barisnya
--   Setiap mob rusak diberi `lootid` milik mob lain yang paling mirip di blok
--   guid yang sama dan tabel loot-nya benar-benar berisi. Empat alasan memilih
--   meminjam ketimbang menyalin ~70 ribu baris:
--
--     - Tidak menambah satu pun error sql.sql baru. LootMgr.cpp:1636-1652 hanya
--       mengeluh soal lootid tanpa baris (ReportNotExistedId) dan lootid yang
--       tidak terpakai (ReportUnusedIds). Menunjuk ke id yang sudah ada dan
--       sudah berisi tidak menambah keduanya -- justru mengurangi yang kedua.
--     - Menyalin butuh namespace lootid baru, dan rentang 39000-56000 sudah
--       padat dipakai creature lain. Satu tabrakan berarti loot dua mob melebur
--       diam-diam: kegagalan yang jauh lebih buruk daripada loot yang mirip.
--     - Ukuran. Ratusan UPDATE versus puluhan ribu INSERT yang akan dijalankan
--       ulang setiap kali DB dibangun dari nol, selamanya.
--     - Pembatalannya satu perintah (lihat di bawah).
--
--   Harganya, dan ini disengaja: dragonkin Twilight Highlands akan menjatuhkan
--   grey dan kain yang sama dengan donornya. Untuk mob pengisi koridor leveling
--   yang tidak difarm siapa pun, itu pertukaran yang benar.
--
-- Kalau nanti satu mob butuh drop quest sendiri
--   Tabelnya harus dipecah dulu, kalau tidak drop itu akan muncul di semua mob
--   yang ikut meminjam:
--
--     SET @MOB := <entry>;
--     -- pastikan @MOB belum dipakai sebagai lootid oleh siapa pun; harus 0
--     SELECT COUNT(*) FROM `creature_template` WHERE `lootid` = @MOB AND `entry` <> @MOB;
--     DELETE FROM `creature_loot_template` WHERE `entry` = @MOB;
--     INSERT INTO `creature_loot_template`
--         (`entry`, `item`, `ChanceOrQuestChance`, `lootmode`, `groupid`, `mincountOrRef`, `maxcount`)
--     SELECT @MOB, `item`, `ChanceOrQuestChance`, `lootmode`, `groupid`, `mincountOrRef`, `maxcount`
--     FROM `creature_loot_template`
--     WHERE `entry` = (SELECT `lootid` FROM `creature_template` WHERE `entry` = @MOB);
--     UPDATE `creature_template` SET `lootid` = @MOB WHERE `entry` = @MOB;
--     -- baru tambahkan baris item quest-nya ke @MOB.
--
-- Idempotent
--   Lingkupnya `lootid` = 0 AND `maxgold` = 0 -- persis negasi syarat di
--   Unit.cpp:6688, jadi mustahil menyentuh mob yang sudah punya loot ATAU sudah
--   punya uang. Sesudah run pertama lingkupnya kosong dan file ini tidak
--   melakukan apa-apa. Kedua UPDATE berjalan atas tabel lingkup yang sama yang
--   dibuat sekali di awal, supaya tidak mungkin ada keadaan setengah jadi di
--   mana mob sudah bisa di-loot tapi uangnya tetap nol.
--
-- Yang TIDAK dicakup, sengaja, dan jangan dilaporkan sebagai regresi
--   `skinloot` (beast di blok ini masih belum bisa dikuliti),
--   `gameobject_loot_template` untuk peti hasil port, dan `npc_vendor` untuk
--   vendor hasil port. Ketiganya lubang tersendiri dari port yang sama;
--   tools/dev/audit_loot_coverage.sql bagian 2, 3, dan 4 mengukurnya, dan
--   masing-masing pantas dapat file sendiri.
--
-- Membatalkannya
--   UPDATE `creature_template` `ct`
--   JOIN `creature` `c` ON `c`.`id` = `ct`.`entry`
--   SET `ct`.`lootid` = 0, `ct`.`mingold` = 0, `ct`.`maxgold` = 0
--   WHERE `c`.`guid` BETWEEN 8400001 AND 8449999;
--
--   Perintah itu merusak kalau sementara ini ada yang menyunting baris yang sama
--   dengan tangan -- ia tidak bisa membedakan mana hasil file ini dan mana bukan.

-- ---------------------------------------------------------------------------
-- 1. Lingkup: mob yang MASIH rusak, sekarang, di DB ini
--
-- Dipilih lewat blok guid hasil port, bukan lewat zona: tabel `creature` di
-- SkyFire 5.4.8 tidak punya kolom zoneId, dan blok guid justru lebih tepat --
-- ia persis himpunan baris yang dibuat port, tidak lebih.
--
-- Filter "bisa dibunuh":
--   type NOT IN (8,11,12,13,14)  critter, totem, non-combat pet, gas cloud, wild pet
--   npcflag = 0                  bukan quest giver / vendor / trainer
--   unit_flags & 0x2             UNIT_FLAG_NON_ATTACKABLE    (Unit.h:626)
--   unit_flags & 0x100           UNIT_FLAG_IMMUNE_TO_PC      (Unit.h:633)
--   unit_flags & 0x2000000       UNIT_FLAG_NOT_SELECTABLE    (Unit.h:650)
--   flags_extra & 0x80           CREATURE_FLAG_EXTRA_TRIGGER (Creature.h:36)
--   minlevel >= 10               menyaring sisa NPC dekoratif level 1
--
-- NPC ramah yang kebetulan lolos saringan ini akan ikut kebagian tabel loot yang
-- tidak pernah dipakai, karena pemain tidak bisa membunuhnya. Itu kotor tapi
-- tidak berbahaya, dan jauh lebih baik daripada menebak-nebak permusuhan faction
-- dari SQL: hostility ada di FactionTemplate.dbc, bukan di DB.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_loot_scope`;
CREATE TABLE `prabowow_loot_scope` (
    `entry`    INT UNSIGNED      NOT NULL PRIMARY KEY,
    `zona`     VARCHAR(24)       NOT NULL,
    `type`     TINYINT UNSIGNED  NOT NULL,
    `npc_rank` TINYINT UNSIGNED  NOT NULL,
    `minlevel` SMALLINT UNSIGNED NOT NULL,
    KEY (`zona`, `type`)
);

INSERT INTO `prabowow_loot_scope` (`entry`, `zona`, `type`, `npc_rank`, `minlevel`)
SELECT DISTINCT `ct`.`entry`, `b`.`zona`, `ct`.`type`, `ct`.`npc_rank`, `ct`.`minlevel`
FROM `creature` `c`
JOIN (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8404000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8419999
    UNION ALL SELECT 'Uldum',                        8420001,          8429999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8439999
) `b` ON `c`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE `ct`.`lootid`  = 0
  AND `ct`.`maxgold` = 0
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10;

-- ---------------------------------------------------------------------------
-- 2. Kolam donor: HANYA yang lootid-nya benar-benar punya baris
--
-- `lootid` > 0 saja tidak cukup. Kalau tabelnya ternyata kosong, meminjamnya
-- berarti memindahkan penyakit yang sama sambil menambah satu baris
-- ReportNotExistedId di log.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_loot_donor`;
CREATE TABLE `prabowow_loot_donor` (
    `entry`    INT UNSIGNED      NOT NULL PRIMARY KEY,
    `zona`     VARCHAR(24)       NOT NULL,
    `lootid`   INT UNSIGNED      NOT NULL,
    `type`     TINYINT UNSIGNED  NOT NULL,
    `npc_rank` TINYINT UNSIGNED  NOT NULL,
    `minlevel` SMALLINT UNSIGNED NOT NULL,
    KEY (`zona`, `type`)
);

INSERT INTO `prabowow_loot_donor` (`entry`, `zona`, `lootid`, `type`, `npc_rank`, `minlevel`)
SELECT DISTINCT `ct`.`entry`, `b`.`zona`, `ct`.`lootid`, `ct`.`type`, `ct`.`npc_rank`, `ct`.`minlevel`
FROM `creature` `c`
JOIN (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8404000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8419999
    UNION ALL SELECT 'Uldum',                        8420001,          8429999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8439999
) `b` ON `c`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE `ct`.`lootid` > 0
  AND EXISTS (SELECT 1 FROM `creature_loot_template` `l` WHERE `l`.`entry` = `ct`.`lootid`)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10;

-- ---------------------------------------------------------------------------
-- 3. Tangga donor
--
--   tier 1  zona sama + type sama   paling mirip: tema dan level yang sama
--   tier 2  type sama, zona bebas   elemental Deepholm boleh menumpang
--                                   elemental Twilight Highlands
--   tier 3  zona sama, type bebas   setidaknya loot-nya selevel dan setema zona
--   tier 4  apa saja                jaring pengaman; laporan di bagian 6 harus
--                                   menunjukkan tier ini tidak terpakai
--
-- Di dalam satu tier: rank yang sama menang, lalu selisih level terkecil, lalu
-- entry terkecil supaya hasilnya deterministik dan file ini bisa diulang.
--
-- CAST ke SIGNED bukan hiasan. `minlevel` itu SMALLINT UNSIGNED dan sql_mode
-- server ini STRICT_TRANS_TABLES tanpa NO_UNSIGNED_SUBTRACTION
-- (deploy/docker-compose.prod.yml:39), jadi pengurangan unsigned yang hasilnya
-- negatif melempar "BIGINT UNSIGNED value is out of range" begitu ada donor yang
-- levelnya lebih rendah dari targetnya.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_loot_pick`;
CREATE TABLE `prabowow_loot_pick` (
    `entry`  INT UNSIGNED     NOT NULL PRIMARY KEY,
    `lootid` INT UNSIGNED     NOT NULL,
    `donor`  INT UNSIGNED     NOT NULL,
    `tier`   TINYINT UNSIGNED NOT NULL
);

INSERT INTO `prabowow_loot_pick` (`entry`, `lootid`, `donor`, `tier`)
SELECT `entry`, `lootid`, `donor`, `tier`
FROM (
    SELECT `s`.`entry`,
           `d`.`lootid`,
           `d`.`entry` AS `donor`,
           CASE WHEN `d`.`zona` = `s`.`zona` AND `d`.`type` = `s`.`type` THEN 1
                WHEN `d`.`type` = `s`.`type`                             THEN 2
                WHEN `d`.`zona` = `s`.`zona`                             THEN 3
                ELSE                                                          4
           END AS `tier`,
           ROW_NUMBER() OVER (
               PARTITION BY `s`.`entry`
               ORDER BY
                   CASE WHEN `d`.`zona` = `s`.`zona` AND `d`.`type` = `s`.`type` THEN 1
                        WHEN `d`.`type` = `s`.`type`                             THEN 2
                        WHEN `d`.`zona` = `s`.`zona`                             THEN 3
                        ELSE                                                          4
                   END,
                   (`d`.`npc_rank` <> `s`.`npc_rank`),
                   ABS(CAST(`d`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED)),
                   `d`.`entry`
           ) AS `rn`
    FROM `prabowow_loot_scope` `s`
    JOIN `prabowow_loot_donor` `d` ON `d`.`entry` <> `s`.`entry`
) `ranked`
WHERE `rn` = 1;

-- ---------------------------------------------------------------------------
-- 4. Kurva gold
--
-- Acuannya diambil dari populasi `creature_template` DB ini sendiri yang memang
-- sehat, bukan dari data hasil port. Data hasil port tidak layak jadi kurva:
-- dari keempat zona hanya level 80 rank 0 yang punya sampel memadai (n=12,
-- rata-rata 1415/3212 tembaga), sedangkan level 82 dan 84 isinya 15/33 tembaga
-- -- placeholder, bukan angka sungguhan. Dua saringan HAVING di bawah membuang
-- bucket semacam itu.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_gold_ref`;
CREATE TABLE `prabowow_gold_ref` (
    `minlevel` SMALLINT UNSIGNED NOT NULL,
    `npc_rank` TINYINT UNSIGNED  NOT NULL,
    `mingold`  INT UNSIGNED      NOT NULL,
    `maxgold`  INT UNSIGNED      NOT NULL,
    `sampel`   INT UNSIGNED      NOT NULL,
    PRIMARY KEY (`minlevel`, `npc_rank`)
);

INSERT INTO `prabowow_gold_ref` (`minlevel`, `npc_rank`, `mingold`, `maxgold`, `sampel`)
SELECT `minlevel`, `npc_rank`,
       ROUND(AVG(`mingold`)), ROUND(AVG(`maxgold`)), COUNT(*)
FROM `creature_template`
WHERE `maxgold` > 0
  AND `mingold` > 0
  AND `minlevel` BETWEEN 60 AND 92
  AND `npc_rank` <= 4
  AND `type` NOT IN (8, 11, 12, 13, 14)
  AND (`flags_extra` & 0x80) = 0
GROUP BY `minlevel`, `npc_rank`
HAVING COUNT(*) >= 5
   AND AVG(`maxgold`) >= 100;

DROP TABLE IF EXISTS `prabowow_gold_pick`;
CREATE TABLE `prabowow_gold_pick` (
    `entry`   INT UNSIGNED NOT NULL PRIMARY KEY,
    `mingold` INT UNSIGNED NOT NULL,
    `maxgold` INT UNSIGNED NOT NULL,
    `asal`    VARCHAR(16)  NOT NULL
);

-- Langkah 1: rank sama, level terdekat dalam +-5.
INSERT INTO `prabowow_gold_pick` (`entry`, `mingold`, `maxgold`, `asal`)
SELECT `entry`, `mingold`, `maxgold`, `asal`
FROM (
    SELECT `s`.`entry`, `r`.`mingold`, `r`.`maxgold`,
           CONCAT('db +-', ABS(CAST(`r`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED))) AS `asal`,
           ROW_NUMBER() OVER (
               PARTITION BY `s`.`entry`
               ORDER BY ABS(CAST(`r`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED)),
                        `r`.`sampel` DESC
           ) AS `rn`
    FROM `prabowow_loot_scope` `s`
    JOIN `prabowow_gold_ref` `r`
      ON `r`.`npc_rank` = `s`.`npc_rank`
     AND ABS(CAST(`r`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED)) <= 5
) `ranked`
WHERE `rn` = 1;

-- Langkah 2: rumus, hanya untuk (level, rank) yang di DB benar-benar tidak ada
-- acuannya. 18 dan 39 tembaga per level diambil dari satu-satunya bucket hasil
-- port yang sampelnya layak: level 80 rank 0, n=12, rata-rata 1415/3212, yaitu
-- 17.7 dan 40.2 per level. Pengali rank adalah keputusan, bukan pengukuran --
-- satu-satunya elite hasil port (level 81 rank 1) memberi 9892/9892, sekitar 6x
-- mingold dan 2.6x maxgold pada level yang sama; diambil 5x rata untuk kedua
-- kolom supaya rentangnya tetap masuk akal. Kalau bagian 5 audit menunjukkan DB
-- punya cukup data, langkah ini tidak akan pernah jalan.
--
-- Ditulis lewat meja perantara, bukan langsung dengan
-- NOT EXISTS (SELECT ... FROM prabowow_gold_pick): MySQL melarang membaca tabel
-- yang sedang jadi sasaran INSERT di dalam subquery-nya sendiri (error 1093).
DROP TABLE IF EXISTS `prabowow_gold_gap`;
CREATE TABLE `prabowow_gold_gap` (
    `entry`   INT UNSIGNED NOT NULL PRIMARY KEY,
    `mingold` INT UNSIGNED NOT NULL,
    `maxgold` INT UNSIGNED NOT NULL
);

INSERT INTO `prabowow_gold_gap` (`entry`, `mingold`, `maxgold`)
SELECT `s`.`entry`,
       ROUND(18 * `s`.`minlevel` * `m`.`mult`),
       ROUND(39 * `s`.`minlevel` * `m`.`mult`)
FROM `prabowow_loot_scope` `s`
JOIN (
              SELECT 0 AS `npc_rank`, 1.0 AS `mult`   -- normal
    UNION ALL SELECT 1,                5.0            -- elite
    UNION ALL SELECT 2,                8.0            -- rare elite
    UNION ALL SELECT 3,               12.0            -- world boss
    UNION ALL SELECT 4,                3.0            -- rare
) `m` ON `m`.`npc_rank` = `s`.`npc_rank`
LEFT JOIN `prabowow_gold_pick` `p` ON `p`.`entry` = `s`.`entry`
WHERE `p`.`entry` IS NULL;

INSERT INTO `prabowow_gold_pick` (`entry`, `mingold`, `maxgold`, `asal`)
SELECT `entry`, `mingold`, `maxgold`, 'rumus' FROM `prabowow_gold_gap`;

-- ---------------------------------------------------------------------------
-- 5. Terapkan
--
-- Syarat pada WHERE sengaja diulang meski lingkupnya sudah disaring: kalau file
-- ini dijalankan dua kali di sesi yang sama, ia tetap tidak menimpa apa pun.
-- ---------------------------------------------------------------------------

UPDATE `creature_template` `ct`
JOIN `prabowow_loot_pick` `p` ON `p`.`entry` = `ct`.`entry`
SET `ct`.`lootid` = `p`.`lootid`
WHERE `ct`.`lootid` = 0;

UPDATE `creature_template` `ct`
JOIN `prabowow_gold_pick` `g` ON `g`.`entry` = `ct`.`entry`
SET `ct`.`mingold` = `g`.`mingold`,
    `ct`.`maxgold` = `g`.`maxgold`
WHERE `ct`.`maxgold` = 0;

-- ---------------------------------------------------------------------------
-- 6. Laporan, lalu semua meja kerja dibuang
--
-- Dibaca di keluaran impor. Yang harus benar: tier 4 kosong dan
-- `belum_dapat_donor` nol. Kalau `asal` = 'rumus' mendominasi, populasi gold DB
-- ini lebih miskin dari dugaan dan angkanya pantas ditinjau lagi.
-- ---------------------------------------------------------------------------

SELECT `tier`, COUNT(*) AS `entry` FROM `prabowow_loot_pick` GROUP BY `tier` ORDER BY `tier`;

SELECT `asal`, COUNT(*) AS `entry` FROM `prabowow_gold_pick` GROUP BY `asal` ORDER BY `asal`;

SELECT COUNT(*) AS `belum_dapat_donor`
FROM `prabowow_loot_scope` `s`
WHERE NOT EXISTS (SELECT 1 FROM `prabowow_loot_pick` `p` WHERE `p`.`entry` = `s`.`entry`);

DROP TABLE IF EXISTS `prabowow_loot_pick`;
DROP TABLE IF EXISTS `prabowow_gold_gap`;
DROP TABLE IF EXISTS `prabowow_gold_pick`;
DROP TABLE IF EXISTS `prabowow_gold_ref`;
DROP TABLE IF EXISTS `prabowow_loot_donor`;
DROP TABLE IF EXISTS `prabowow_loot_scope`;
