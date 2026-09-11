-- Pandaria (map 870): pastikan mobnya menjatuhkan sesuatu.
--
-- Gejala yang dilaporkan
--   Mob Pandaria tidak memberi loot. Sama seperti di zona Cataclysm hasil port,
--   keluhan ini punya dua bentuk yang berbeda dan file ini menangani keduanya:
--
--     (A) `lootid` = 0 DAN `maxgold` = 0 -- mayatnya tidak berkilau sama sekali
--         dan tidak bisa diklik.
--     (B) `lootid` = 0 tapi `maxgold` > 0 -- mayatnya berkilau, uangnya keluar,
--         tapi tidak pernah ada satu item pun.
--
--   Unit.cpp:6688 yang memisahkan keduanya:
--
--       if (cInfo && (cInfo->lootid || cInfo->maxgold > 0))
--           creature->SetFlag(OBJECT_FIELD_DYNAMIC_FLAGS, UNIT_DYNFLAG_LOOTABLE);
--
-- PERINGATAN: file ini belum pernah diukur ke DB yang jalan
--   Ini beda penting dari prabowow_cataclysm_zone_loot_and_gold.sql, yang
--   angkanya diambil dari DB hidup lebih dulu. Di sini tidak.
--
--   Dan Pandaria punya alasan kuat untuk BERBEDA dari zona Cataclysm. Zona
--   Cataclysm rusak karena diport dari dump TrinityCore 4.3.4 yang `lootid`-nya
--   memang nol; Pandaria tidak pernah diport -- ia konten asli SFDB 5.4.8, dan
--   tools/dev/port_zone_spawns.py tidak pernah menyentuhnya karena dump 4.3.4
--   tidak punya map 870 sama sekali. Jadi sangat mungkin loot Pandaria
--   sebenarnya utuh, dan penyebab keluhannya ada di tempat lain.
--
--   Karena itu file ini dibuat SELF-SCOPING: lingkupnya dihitung dari DB tempat
--   ia dijalankan, dan kalau di sana tidak ada yang rusak ia tidak menyentuh
--   satu baris pun. Laporan di bagian 7 yang memberi tahu mana yang terjadi.
--
--   Ukur dulu sebelum menjalankannya, dengan bagian 1 dan 1b
--   tools/dev/audit_pandaria_loot.sql. Kalau `tanpa_loot_dan_uang` dan
--   `uang_saja_tanpa_loot` dua-duanya nol, loot Pandaria tidak rusak dan
--   keluhannya perlu dicari dari arah lain -- misalnya Rate.Drop.* di
--   config/worldserver.overrides.conf, atau mob yang dibunuh ternyata critter.
--
-- Perbaikannya, dua langkah, sama seperti file Cataclysm
--   Langkah 1 -- sambungkan mob ke tabel loot MILIKNYA SENDIRI. Kalau
--   `creature_loot_template` sudah punya baris atas nama entry itu sementara
--   `creature_template`.`lootid` masih 0, tabelnya cuma tidak pernah ditunjuk.
--   Mengisi `lootid` = `entry` mengembalikan loot aslinya persis, tanpa satu pun
--   tebakan. Di Pandaria langkah inilah yang diharapkan menanggung hampir
--   semuanya, kalau memang ada yang perlu ditanggung.
--
--   Langkah 2 -- sisanya meminjam `lootid` mob lain yang paling mirip di map
--   yang sama. Kolam donornya dibangun SESUDAH langkah 1, jadi mob yang baru
--   tersambung itu ikut jadi donor.
--
-- Tangga donornya lebih pendek dari file Cataclysm
--   File itu punya empat tier karena punya kolom zona: spawn-nya lahir dari
--   blok guid per-zona hasil port. Pandaria tidak punya padanannya -- tabel
--   `creature` SkyFire 5.4.8 tidak punya kolom zona, dan spawn Pandaria milik
--   SFDB tidak dikelompokkan per blok guid. Yang tersisa dan memang bermakna:
--
--     tier 1  type sama + rank sama    paling mirip
--     tier 2  type sama                beast menumpang beast
--     tier 3  apa saja                 jaring pengaman; laporan bagian 7 harus
--                                      menunjukkan tier ini tidak terpakai
--
--   Di dalam satu tier: selisih level terkecil menang, lalu entry terkecil
--   supaya hasilnya deterministik dan file ini bisa diulang.
--
-- Lingkupnya: entry yang HANYA hidup di map 870
--   Alasannya sama dengan prabowow_pandaria_mob_health.sql: `creature_template`
--   dipakai bersama semua peta, jadi entry yang juga terspawn di luar Pandaria
--   sengaja dilewat supaya file ini tidak diam-diam mengubah loot mob di
--   Azeroth. Jumlah yang dilewat dilaporkan di bagian 7.
--
-- Idempotent
--   Semua UPDATE-nya bersyarat `lootid` = 0 atau `maxgold` = 0, jadi tidak ada
--   yang pernah ditimpa dua kali. Meja kerjanya dibuang di akhir.
--
-- Membatalkannya
--   Tidak ada catatan nilai lama, karena nilai lamanya memang nol -- itu
--   seluruh pokok perbaikan ini. Yang bisa dikembalikan cuma seluruhnya:
--
--     UPDATE `creature_template` `ct`
--     JOIN `creature` `c` ON `c`.`id` = `ct`.`entry` AND `c`.`map` = 870
--     SET `ct`.`lootid` = 0, `ct`.`mingold` = 0, `ct`.`maxgold` = 0;
--
--   Jangan jalankan itu kalau file ini sudah pernah dipromosikan ke
--   sql/updates/world/ -- ia akan menghapus loot yang memang milik SFDB juga.

SET @MAP_PANDARIA := 870;

-- ---------------------------------------------------------------------------
-- 1. Lingkup: mob map 870 yang MASIH rusak, sekarang, di DB ini
--
-- Saringan "bisa dibunuh" sama persis dengan
-- prabowow_cataclysm_zone_loot_and_gold.sql dan audit_loot_coverage.sql:
--   type NOT IN (8,11,12,13,14)  critter, totem, non-combat pet, gas cloud, wild pet
--   npcflag = 0                  bukan quest giver / vendor / trainer
--   unit_flags & 0x2             UNIT_FLAG_NON_ATTACKABLE    (Unit.h:626)
--   unit_flags & 0x100           UNIT_FLAG_IMMUNE_TO_PC      (Unit.h:633)
--   unit_flags & 0x2000000       UNIT_FLAG_NOT_SELECTABLE    (Unit.h:650)
--   flags_extra & 0x80           CREATURE_FLAG_EXTRA_TRIGGER (Creature.h:36)
--   minlevel >= 10               menyaring sisa NPC dekoratif level 1
--
-- Lingkupnya `lootid` = 0 OR `maxgold` = 0 -- bukan AND. Dua lubang yang
-- berdiri sendiri, dan `perlu_loot` / `perlu_gold` yang menentukan mob mana
-- ikut bagian mana.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_pandaria_loot_scope`;
CREATE TABLE `prabowow_pandaria_loot_scope` (
    `entry`      INT UNSIGNED      NOT NULL PRIMARY KEY,
    `type`       TINYINT UNSIGNED  NOT NULL,
    `npc_rank`   TINYINT UNSIGNED  NOT NULL,
    `minlevel`   SMALLINT UNSIGNED NOT NULL,
    `perlu_loot` TINYINT UNSIGNED  NOT NULL,
    `perlu_gold` TINYINT UNSIGNED  NOT NULL,
    KEY (`type`, `npc_rank`)
);

INSERT INTO `prabowow_pandaria_loot_scope`
    (`entry`, `type`, `npc_rank`, `minlevel`, `perlu_loot`, `perlu_gold`)
SELECT `ct`.`entry`, `ct`.`type`, `ct`.`npc_rank`, `ct`.`minlevel`,
       (`ct`.`lootid` = 0), (`ct`.`maxgold` = 0)
FROM `creature_template` `ct`
WHERE EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND NOT EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` <> @MAP_PANDARIA)
  AND (`ct`.`lootid` = 0 OR `ct`.`maxgold` = 0)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10;

-- ---------------------------------------------------------------------------
-- 2. Langkah 1: sambungkan mob ke tabel loot miliknya sendiri
--
-- `EXISTS` menunjuk ke `entry`, bukan ke `lootid`: yang ditanya adalah "apakah
-- ada tabel loot atas nama mob ini", dan `lootid`-nya justru masih nol.
--
-- Harus jalan sebelum kolam donor dibangun, karena kolam itu mensyaratkan
-- `lootid` > 0.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_pandaria_loot_self`;
CREATE TABLE `prabowow_pandaria_loot_self` (
    `entry` INT UNSIGNED NOT NULL PRIMARY KEY
);

INSERT INTO `prabowow_pandaria_loot_self` (`entry`)
SELECT `s`.`entry`
FROM `prabowow_pandaria_loot_scope` `s`
JOIN `creature_template` `ct` ON `ct`.`entry` = `s`.`entry`
WHERE `s`.`perlu_loot` = 1
  AND `ct`.`lootid` = 0
  AND EXISTS (SELECT 1 FROM `creature_loot_template` `l` WHERE `l`.`entry` = `s`.`entry`);

UPDATE `creature_template` `ct`
JOIN `prabowow_pandaria_loot_self` `f` ON `f`.`entry` = `ct`.`entry`
SET `ct`.`lootid` = `ct`.`entry`
WHERE `ct`.`lootid` = 0;

-- ---------------------------------------------------------------------------
-- 3. Kolam donor: HANYA yang lootid-nya benar-benar punya baris
--
-- Donor tidak dibatasi "hanya map 870" seperti lingkupnya. Yang dipinjam cuma
-- nomor `lootid`-nya, dan meminjam dari mob Pandaria yang juga berdiri di peta
-- lain tidak mengubah apa pun pada mob itu sendiri. Batasnya tetap map 870
-- supaya loot yang dipinjam setema dan selevel.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_pandaria_loot_donor`;
CREATE TABLE `prabowow_pandaria_loot_donor` (
    `entry`    INT UNSIGNED      NOT NULL PRIMARY KEY,
    `lootid`   INT UNSIGNED      NOT NULL,
    `type`     TINYINT UNSIGNED  NOT NULL,
    `npc_rank` TINYINT UNSIGNED  NOT NULL,
    `minlevel` SMALLINT UNSIGNED NOT NULL,
    KEY (`type`, `npc_rank`)
);

INSERT INTO `prabowow_pandaria_loot_donor` (`entry`, `lootid`, `type`, `npc_rank`, `minlevel`)
SELECT DISTINCT `ct`.`entry`, `ct`.`lootid`, `ct`.`type`, `ct`.`npc_rank`, `ct`.`minlevel`
FROM `creature_template` `ct`
WHERE EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND `ct`.`lootid` > 0
  AND EXISTS (SELECT 1 FROM `creature_loot_template` `l` WHERE `l`.`entry` = `ct`.`lootid`)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10;

-- ---------------------------------------------------------------------------
-- 4. Langkah 2: tangga donor untuk sisanya
--
-- Hanya mob yang SESUDAH bagian 2 masih ber-`lootid` 0 yang masuk sini -- itu
-- sebabnya `creature_template` ikut di-JOIN lagi, bukan cukup membaca
-- `perlu_loot` dari tabel lingkup yang dibuat sebelum bagian 2 jalan.
--
-- CAST ke SIGNED bukan hiasan. `minlevel` itu SMALLINT UNSIGNED dan sql_mode
-- server ini STRICT_TRANS_TABLES tanpa NO_UNSIGNED_SUBTRACTION
-- (deploy/docker-compose.prod.yml:39), jadi pengurangan unsigned yang hasilnya
-- negatif melempar "BIGINT UNSIGNED value is out of range".
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_pandaria_loot_pick`;
CREATE TABLE `prabowow_pandaria_loot_pick` (
    `entry`  INT UNSIGNED     NOT NULL PRIMARY KEY,
    `lootid` INT UNSIGNED     NOT NULL,
    `donor`  INT UNSIGNED     NOT NULL,
    `tier`   TINYINT UNSIGNED NOT NULL
);

INSERT INTO `prabowow_pandaria_loot_pick` (`entry`, `lootid`, `donor`, `tier`)
SELECT `entry`, `lootid`, `donor`, `tier`
FROM (
    SELECT `s`.`entry`,
           `d`.`lootid`,
           `d`.`entry` AS `donor`,
           CASE WHEN `d`.`type` = `s`.`type` AND `d`.`npc_rank` = `s`.`npc_rank` THEN 1
                WHEN `d`.`type` = `s`.`type`                                     THEN 2
                ELSE                                                                  3
           END AS `tier`,
           ROW_NUMBER() OVER (
               PARTITION BY `s`.`entry`
               ORDER BY
                   CASE WHEN `d`.`type` = `s`.`type` AND `d`.`npc_rank` = `s`.`npc_rank` THEN 1
                        WHEN `d`.`type` = `s`.`type`                                     THEN 2
                        ELSE                                                                  3
                   END,
                   ABS(CAST(`d`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED)),
                   `d`.`entry`
           ) AS `rn`
    FROM `prabowow_pandaria_loot_scope` `s`
    JOIN `creature_template` `ct` ON `ct`.`entry` = `s`.`entry` AND `ct`.`lootid` = 0
    JOIN `prabowow_pandaria_loot_donor` `d` ON `d`.`entry` <> `s`.`entry`
    WHERE `s`.`perlu_loot` = 1
) `ranked`
WHERE `rn` = 1;

-- ---------------------------------------------------------------------------
-- 5. Kurva gold
--
-- Acuannya diambil dari populasi `creature_template` DB ini sendiri yang memang
-- sehat, bukan dari mob Pandaria yang sedang diperbaiki. Dua saringan HAVING
-- membuang bucket yang isinya placeholder.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_pandaria_gold_ref`;
CREATE TABLE `prabowow_pandaria_gold_ref` (
    `minlevel` SMALLINT UNSIGNED NOT NULL,
    `npc_rank` TINYINT UNSIGNED  NOT NULL,
    `mingold`  INT UNSIGNED      NOT NULL,
    `maxgold`  INT UNSIGNED      NOT NULL,
    `sampel`   INT UNSIGNED      NOT NULL,
    PRIMARY KEY (`minlevel`, `npc_rank`)
);

INSERT INTO `prabowow_pandaria_gold_ref` (`minlevel`, `npc_rank`, `mingold`, `maxgold`, `sampel`)
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

DROP TABLE IF EXISTS `prabowow_pandaria_gold_pick`;
CREATE TABLE `prabowow_pandaria_gold_pick` (
    `entry`   INT UNSIGNED NOT NULL PRIMARY KEY,
    `mingold` INT UNSIGNED NOT NULL,
    `maxgold` INT UNSIGNED NOT NULL,
    `asal`    VARCHAR(16)  NOT NULL
);

-- Langkah 1: rank sama, level terdekat dalam +-5.
INSERT INTO `prabowow_pandaria_gold_pick` (`entry`, `mingold`, `maxgold`, `asal`)
SELECT `entry`, `mingold`, `maxgold`, `asal`
FROM (
    SELECT `s`.`entry`, `r`.`mingold`, `r`.`maxgold`,
           CONCAT('db +-', ABS(CAST(`r`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED))) AS `asal`,
           ROW_NUMBER() OVER (
               PARTITION BY `s`.`entry`
               ORDER BY ABS(CAST(`r`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED)),
                        `r`.`sampel` DESC
           ) AS `rn`
    FROM `prabowow_pandaria_loot_scope` `s`
    JOIN `prabowow_pandaria_gold_ref` `r`
      ON `r`.`npc_rank` = `s`.`npc_rank`
     AND ABS(CAST(`r`.`minlevel` AS SIGNED) - CAST(`s`.`minlevel` AS SIGNED)) <= 5
    WHERE `s`.`perlu_gold` = 1
) `ranked`
WHERE `rn` = 1;

-- Langkah 2: rumus, hanya untuk (level, rank) yang di DB benar-benar tidak ada
-- acuannya. 18 dan 39 tembaga per level dan pengali rank-nya disalin dari
-- prabowow_cataclysm_zone_loot_and_gold.sql supaya kedua file memberi angka
-- yang sebanding pada level yang sama.
--
-- Ditulis lewat meja perantara, bukan langsung dengan NOT EXISTS pada tabel
-- sasaran: MySQL melarang membaca tabel yang sedang jadi sasaran INSERT di
-- dalam subquery-nya sendiri (error 1093).
DROP TABLE IF EXISTS `prabowow_pandaria_gold_gap`;
CREATE TABLE `prabowow_pandaria_gold_gap` (
    `entry`   INT UNSIGNED NOT NULL PRIMARY KEY,
    `mingold` INT UNSIGNED NOT NULL,
    `maxgold` INT UNSIGNED NOT NULL
);

INSERT INTO `prabowow_pandaria_gold_gap` (`entry`, `mingold`, `maxgold`)
SELECT `s`.`entry`,
       ROUND(18 * `s`.`minlevel` * `m`.`mult`),
       ROUND(39 * `s`.`minlevel` * `m`.`mult`)
FROM `prabowow_pandaria_loot_scope` `s`
JOIN (
              SELECT 0 AS `npc_rank`, 1.0 AS `mult`   -- normal
    UNION ALL SELECT 1,                5.0            -- elite
    UNION ALL SELECT 2,                8.0            -- rare elite
    UNION ALL SELECT 3,               12.0            -- world boss
    UNION ALL SELECT 4,                3.0            -- rare
) `m` ON `m`.`npc_rank` = `s`.`npc_rank`
LEFT JOIN `prabowow_pandaria_gold_pick` `p` ON `p`.`entry` = `s`.`entry`
WHERE `p`.`entry` IS NULL
  AND `s`.`perlu_gold` = 1;

INSERT INTO `prabowow_pandaria_gold_pick` (`entry`, `mingold`, `maxgold`, `asal`)
SELECT `entry`, `mingold`, `maxgold`, 'rumus' FROM `prabowow_pandaria_gold_gap`;

-- ---------------------------------------------------------------------------
-- 6. Terapkan
--
-- Loot milik sendiri sudah dipasang di bagian 2 karena kolam donor bergantung
-- padanya. Yang tersisa di sini loot pinjaman dan uangnya.
-- ---------------------------------------------------------------------------

UPDATE `creature_template` `ct`
JOIN `prabowow_pandaria_loot_pick` `p` ON `p`.`entry` = `ct`.`entry`
SET `ct`.`lootid` = `p`.`lootid`
WHERE `ct`.`lootid` = 0;

UPDATE `creature_template` `ct`
JOIN `prabowow_pandaria_gold_pick` `g` ON `g`.`entry` = `ct`.`entry`
SET `ct`.`mingold` = `g`.`mingold`,
    `ct`.`maxgold` = `g`.`maxgold`
WHERE `ct`.`maxgold` = 0;

-- ---------------------------------------------------------------------------
-- 7. Laporan, lalu semua meja kerja dibuang
--
-- Yang dibaca duluan: kalau `lingkup` nol, loot Pandaria memang tidak rusak dan
-- file ini tidak mengubah apa pun. Itu hasil yang sah, bukan kegagalan -- lihat
-- PERINGATAN di kepala file.
--
-- Kalau `lingkup` bukan nol: `pakai_tabel_sendiri` yang diharapkan mendominasi,
-- tier 3 harus kosong, dan `masih_tanpa_loot` harus nol.
-- ---------------------------------------------------------------------------

SELECT (SELECT COUNT(*) FROM `prabowow_pandaria_loot_scope`) AS `lingkup`,
       (SELECT COUNT(*) FROM `prabowow_pandaria_loot_self`)  AS `pakai_tabel_sendiri`,
       (SELECT COUNT(*) FROM `prabowow_pandaria_loot_pick`)  AS `pinjam_donor`,
       (SELECT COUNT(*) FROM `prabowow_pandaria_loot_donor`) AS `donor_tersedia`;

SELECT SUM(`perlu_loot` = 1 AND `perlu_gold` = 1) AS `tanpa_loot_dan_uang`,
       SUM(`perlu_loot` = 1 AND `perlu_gold` = 0) AS `uang_saja_tanpa_loot`,
       SUM(`perlu_loot` = 0 AND `perlu_gold` = 1) AS `loot_saja_tanpa_uang`
FROM `prabowow_pandaria_loot_scope`;

SELECT `tier`, COUNT(*) AS `entry`
FROM `prabowow_pandaria_loot_pick` GROUP BY `tier` ORDER BY `tier`;

SELECT `asal`, COUNT(*) AS `entry`
FROM `prabowow_pandaria_gold_pick` GROUP BY `asal` ORDER BY `asal`;

SELECT COUNT(*) AS `masih_tanpa_loot`
FROM `prabowow_pandaria_loot_scope` `s`
JOIN `creature_template` `ct` ON `ct`.`entry` = `s`.`entry`
WHERE `s`.`perlu_loot` = 1
  AND `ct`.`lootid` = 0;

SELECT COUNT(*) AS `dipakai_peta_lain`
FROM `creature_template` `ct`
WHERE EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` <> @MAP_PANDARIA);

DROP TABLE IF EXISTS `prabowow_pandaria_loot_self`;
DROP TABLE IF EXISTS `prabowow_pandaria_loot_pick`;
DROP TABLE IF EXISTS `prabowow_pandaria_gold_gap`;
DROP TABLE IF EXISTS `prabowow_pandaria_gold_pick`;
DROP TABLE IF EXISTS `prabowow_pandaria_gold_ref`;
DROP TABLE IF EXISTS `prabowow_pandaria_loot_donor`;
DROP TABLE IF EXISTS `prabowow_pandaria_loot_scope`;
