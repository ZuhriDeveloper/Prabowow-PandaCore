-- Audit kelengkapan loot pada zona Cataclysm hasil port, di world DB yang jalan.
--
-- Kenapa ada file ini
--   Dump dasar SFDB tidak ada di repo mana pun -- ia diunduh sekali ke volume
--   Docker saat deploy. Angka apa pun yang dihitung dari file SQL di repo cuma
--   perkiraan: port zona memakai `INSERT IGNORE` pada `creature_template`, jadi
--   untuk entry yang sudah dikenal SFDB baris hasil port dibuang dan nilai yang
--   hidup adalah milik SFDB. Satu-satunya patokan yang sah adalah DB itu
--   sendiri. Semua yang di bawah SELECT saja, aman dijalankan kapan pun.
--
-- Gejala yang dicari
--   `creature_template`.`lootid` = 0 DAN `maxgold` = 0 berarti mayatnya tidak
--   bisa di-loot sama sekali -- bukan "loot-nya kosong", tapi tidak berkilau dan
--   tidak bisa diklik. Lihat Unit.cpp:6688:
--
--       if (cInfo && (cInfo->lootid || cInfo->maxgold > 0))
--           creature->SetFlag(OBJECT_FIELD_DYNAMIC_FLAGS, UNIT_DYNFLAG_LOOTABLE);
--
--   Pengisian loot dan uangnya sendiri ada di Unit.cpp:6581-6584.
--
-- Cara jalan di VPS
--   PW='-f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env'
--   docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
--       < audit_loot_coverage.sql
--
-- Cara membaca hasilnya
--   Bagian 1 adalah keluhan pemain, diterjemahkan ke angka. Bagian 1b dan 1c
--   menentukan seberapa dalam tangga donor perlu turun saat perbaikannya
--   dijalankan. Bagian 2, 3, dan 4 adalah lubang lain dari port yang sama;
--   kalau isinya bukan nol, itu perbaikan tersendiri dengan file tersendiri.
--
-- Kenapa terpisah dari audit_leveling_coverage.sql
--   File itu pemeriksaan kesehatan sekujur realm yang sering diulang. Yang ini
--   dilingkupi blok guid dan menjalankan EXISTS berkorelasi berkali-kali.
--   Beda irama, beda pembaca.

SELECT '=== 1. Mob yang tidak bisa di-loot sama sekali, per blok guid ===' AS `bagian`;

-- Filter "bisa dibunuh" di bawah dipakai ulang persis oleh file perbaikannya:
--   type NOT IN (8,11,12,13,14)  critter, totem, non-combat pet, gas cloud, wild pet
--   npcflag = 0                  bukan quest giver / vendor / trainer
--   unit_flags & 0x2             UNIT_FLAG_NON_ATTACKABLE    (Unit.h:626)
--   unit_flags & 0x100           UNIT_FLAG_IMMUNE_TO_PC      (Unit.h:633)
--   unit_flags & 0x2000000       UNIT_FLAG_NOT_SELECTABLE    (Unit.h:650)
--   flags_extra & 0x80           CREATURE_FLAG_EXTRA_TRIGGER (Creature.h:36)
WITH `blok` AS (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8404000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8419999
    UNION ALL SELECT 'Uldum',                        8420001,          8429999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8439999
    UNION ALL SELECT 'Vashjir (cadangan)',           8440001,          8449999
)
SELECT `b`.`zona`,
       COUNT(DISTINCT `ct`.`entry`) AS `entry_rusak`,
       COUNT(*)                     AS `spawn_rusak`,
       MIN(`ct`.`minlevel`)         AS `lvl_min`,
       MAX(`ct`.`maxlevel`)         AS `lvl_max`
FROM `creature` `c`
JOIN `blok` `b` ON `c`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE `ct`.`lootid`  = 0
  AND `ct`.`maxgold` = 0
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10
GROUP BY `b`.`zona`
ORDER BY `b`.`zona`;

SELECT '=== 1b. Donor yang tersedia per blok, dipecah per type dan rank ===' AS `bagian`;

-- Donor = mob di blok yang sama yang lootid-nya BENAR-BENAR punya baris.
WITH `blok` AS (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8404000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8419999
    UNION ALL SELECT 'Uldum',                        8420001,          8429999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8439999
    UNION ALL SELECT 'Vashjir (cadangan)',           8440001,          8449999
)
SELECT `b`.`zona`, `ct`.`type`, `ct`.`npc_rank`,
       COUNT(DISTINCT `ct`.`entry`) AS `donor`,
       MIN(`ct`.`minlevel`)         AS `lvl_min`,
       MAX(`ct`.`minlevel`)         AS `lvl_max`
FROM `creature` `c`
JOIN `blok` `b` ON `c`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE `ct`.`lootid` > 0
  AND EXISTS (SELECT 1 FROM `creature_loot_template` `l` WHERE `l`.`entry` = `ct`.`lootid`)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10
GROUP BY `b`.`zona`, `ct`.`type`, `ct`.`npc_rank`
ORDER BY `b`.`zona`, `ct`.`type`, `ct`.`npc_rank`;

SELECT '=== 1c. Kombinasi rusak per (zona, type, rank), untuk dijodohkan dengan 1b ===' AS `bagian`;

-- Kalau sebuah baris di sini tidak punya pasangan di bagian 1b, tangga donor
-- harus turun ke tier lintas-zona atau lintas-type.
WITH `blok` AS (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8404000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8419999
    UNION ALL SELECT 'Uldum',                        8420001,          8429999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8439999
    UNION ALL SELECT 'Vashjir (cadangan)',           8440001,          8449999
)
SELECT `b`.`zona`, `ct`.`type`, `ct`.`npc_rank`,
       COUNT(DISTINCT `ct`.`entry`) AS `entry_rusak`
FROM `creature` `c`
JOIN `blok` `b` ON `c`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE `ct`.`lootid`  = 0
  AND `ct`.`maxgold` = 0
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10
GROUP BY `b`.`zona`, `ct`.`type`, `ct`.`npc_rank`
ORDER BY `b`.`zona`, `ct`.`type`, `ct`.`npc_rank`;

SELECT '=== 2. lootid menggantung: janji loot tanpa tabelnya ===' AS `bagian`;

-- Ini persis yang dilaporkan core ke log sql.sql lewat LootMgr.cpp:1642
-- (ReportNotExistedId). Kalau nol, log-nya bersih dari sisi ini.
WITH `blok` AS (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8404000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8419999
    UNION ALL SELECT 'Uldum',                        8420001,          8429999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8439999
    UNION ALL SELECT 'Vashjir (cadangan)',           8440001,          8449999
)
SELECT `b`.`zona`,
       COUNT(DISTINCT `ct`.`entry`)  AS `entry`,
       COUNT(DISTINCT `ct`.`lootid`) AS `lootid_hilang`
FROM `creature` `c`
JOIN `blok` `b` ON `c`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE `ct`.`lootid` > 0
  AND NOT EXISTS (SELECT 1 FROM `creature_loot_template` `l` WHERE `l`.`entry` = `ct`.`lootid`)
GROUP BY `b`.`zona`
ORDER BY `b`.`zona`;

SELECT '=== 3. Peti hasil port yang isinya tidak ikut ===' AS `bagian`;

-- gameobject_template.data1 = chest.lootId untuk type 3 (GameObject.h:81).
-- port_zone_spawns.py tidak pernah membawa gameobject_loot_template.
WITH `blok` AS (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8401000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8412999
    UNION ALL SELECT 'Uldum',                        8420001,          8422999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8434999
    UNION ALL SELECT 'Vashjir (cadangan)',           8440001,          8442999
)
SELECT `b`.`zona`,
       COUNT(DISTINCT `gt`.`entry`) AS `peti_kosong`,
       COUNT(*)                     AS `spawn`
FROM `gameobject` `g`
JOIN `blok` `b` ON `g`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `gameobject_template` `gt` ON `gt`.`entry` = `g`.`id`
WHERE `gt`.`type` = 3
  AND `gt`.`data1` > 0
  AND NOT EXISTS (SELECT 1 FROM `gameobject_loot_template` `l` WHERE `l`.`entry` = `gt`.`data1`)
GROUP BY `b`.`zona`
ORDER BY `b`.`zona`;

SELECT '=== 4. Vendor hasil port yang dagangannya tidak ikut ===' AS `bagian`;

-- npcflag bit 0x80 = UNIT_NPC_FLAG_VENDOR. Tanpa baris npc_vendor jendela
-- dagangnya terbuka kosong.
WITH `blok` AS (
              SELECT 'Mount Hyjal'        AS `zona`, 8400001 AS `lo`, 8404000 AS `hi`
    UNION ALL SELECT 'Deepholm',                     8410001,          8419999
    UNION ALL SELECT 'Uldum',                        8420001,          8429999
    UNION ALL SELECT 'Twilight Highlands',           8430001,          8439999
    UNION ALL SELECT 'Vashjir (cadangan)',           8440001,          8449999
)
SELECT `b`.`zona`, `ct`.`entry`, `ct`.`name`
FROM `creature` `c`
JOIN `blok` `b` ON `c`.`guid` BETWEEN `b`.`lo` AND `b`.`hi`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE (`ct`.`npcflag` & 0x80) <> 0
  AND NOT EXISTS (SELECT 1 FROM `npc_vendor` `v` WHERE `v`.`entry` = `ct`.`entry`)
GROUP BY `b`.`zona`, `ct`.`entry`, `ct`.`name`
ORDER BY `b`.`zona`, `ct`.`entry`;

SELECT '=== 5. Populasi gold sehat yang bisa dipakai jadi acuan ===' AS `bagian`;

-- Ini yang menentukan apakah backfill gold boleh bersandar pada DB hidup atau
-- harus jatuh ke rumus. Data hasil port sendiri tidak layak jadi kurva: dari
-- empat zona hanya level 80 rank 0 yang punya sampel memadai (n=12, rata-rata
-- 1415/3212 tembaga), sedangkan level 82 dan 84 isinya 15/33 tembaga --
-- placeholder, bukan angka sungguhan.
SELECT `minlevel`, `npc_rank`,
       COUNT(*)              AS `sampel`,
       ROUND(AVG(`mingold`)) AS `mingold_avg`,
       ROUND(AVG(`maxgold`)) AS `maxgold_avg`
FROM `creature_template`
WHERE `maxgold` > 0
  AND `mingold` > 0
  AND `minlevel` BETWEEN 75 AND 92
  AND `npc_rank` <= 4
  AND `type` NOT IN (8, 11, 12, 13, 14)
  AND (`flags_extra` & 0x80) = 0
GROUP BY `minlevel`, `npc_rank`
ORDER BY `minlevel`, `npc_rank`;
