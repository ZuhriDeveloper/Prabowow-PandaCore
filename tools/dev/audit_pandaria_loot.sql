-- Audit loot, gold, dan HP mob Pandaria (map 870), di world DB yang jalan.
--
-- Kenapa ada file ini
--   Dump dasar SFDB tidak ada di repo mana pun -- ia diunduh sekali ke volume
--   Docker saat deploy, lalu sql/updates/world/* menumpuk di atasnya. Angka apa
--   pun yang dihitung dari file SQL di repo cuma perkiraan. Satu-satunya patokan
--   yang sah adalah DB itu sendiri. Semua yang di bawah SELECT saja, aman
--   dijalankan kapan pun.
--
-- Dipakai untuk apa
--   Menjawab satu pertanyaan sebelum
--   sql/pending_updates/world/prabowow_pandaria_mob_loot_and_gold.sql dijalankan:
--   apakah loot Pandaria benar-benar rusak?
--
--   Ini bukan pertanyaan retoris. Zona Cataclysm rusak karena diport dari dump
--   TrinityCore 4.3.4 yang `lootid`-nya nol. Pandaria tidak pernah diport -- ia
--   konten asli SFDB 5.4.8, dan tools/dev/port_zone_spawns.py tidak bisa
--   menyentuhnya karena dump 4.3.4 tidak punya map 870 sama sekali. Jadi sangat
--   mungkin jawabannya "tidak rusak", dan keluhan pemain punya sebab lain.
--
-- Gejala yang dicari
--   `creature_template`.`lootid` = 0 DAN `maxgold` = 0 berarti mayatnya tidak
--   bisa di-loot sama sekali -- tidak berkilau, tidak bisa diklik. `lootid` = 0
--   sementara `maxgold` > 0 adalah gejala yang lain: mayatnya berkilau, uangnya
--   keluar, itemnya tidak pernah ada. Lihat Unit.cpp:6688:
--
--       if (cInfo && (cInfo->lootid || cInfo->maxgold > 0))
--           creature->SetFlag(OBJECT_FIELD_DYNAMIC_FLAGS, UNIT_DYNFLAG_LOOTABLE);
--
-- Cara jalan di VPS
--   PW='-f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env'
--   docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
--       < audit_pandaria_loot.sql
--
-- Cara membaca hasilnya
--   Bagian 1 adalah vonisnya. Kalau `tanpa_loot_dan_uang` dan
--   `uang_saja_tanpa_loot` dua-duanya nol, loot Pandaria TIDAK rusak dan file
--   perbaikannya tidak perlu dijalankan -- keluhannya harus dicari dari arah
--   lain (Rate.Drop.* di config, atau yang dibunuh ternyata critter).
--
--   Bagian 3 menentukan apakah perbaikannya punya bahan. Kalau `lingkup` di
--   bagian 1 besar tapi `donor` di bagian 3 nol, langkah pinjam-meminjam tidak
--   akan menghasilkan apa pun dan perbaikannya harus dipikirkan ulang.
--
-- Kenapa terpisah dari audit_loot_coverage.sql
--   File itu dilingkupi blok guid hasil port (84xxxxx) -- himpunan baris yang
--   dibuat port_zone_spawns.py, bukan lebih. Pandaria tidak punya blok guid
--   seperti itu: spawn-nya milik SFDB sendiri dan tersebar. Lingkupnya map,
--   bukan guid, jadi kueri-nya memang beda.

SET @MAP_PANDARIA := 870;

SELECT '=== 1. Vonis: berapa banyak mob map 870 yang lubang lootnya ===' AS `bagian`;

-- Saringan "bisa dibunuh" sama persis dengan yang dipakai file perbaikannya:
--   type NOT IN (8,11,12,13,14)  critter, totem, non-combat pet, gas cloud, wild pet
--   npcflag = 0                  bukan quest giver / vendor / trainer
--   unit_flags & 0x2             UNIT_FLAG_NON_ATTACKABLE    (Unit.h:626)
--   unit_flags & 0x100           UNIT_FLAG_IMMUNE_TO_PC      (Unit.h:633)
--   unit_flags & 0x2000000       UNIT_FLAG_NOT_SELECTABLE    (Unit.h:650)
--   flags_extra & 0x80           CREATURE_FLAG_EXTRA_TRIGGER (Creature.h:36)
--   minlevel >= 10               menyaring sisa NPC dekoratif level 1
--
-- `hanya_map_870` adalah lingkup yang benar-benar akan disentuh file perbaikan;
-- `semua_map_870` termasuk entry yang juga terspawn di luar Pandaria dan karena
-- itu sengaja dilewat. Selisih keduanya adalah harga dari lingkup yang aman.

SELECT SUM(`ct`.`lootid` = 0 AND `ct`.`maxgold` = 0) AS `tanpa_loot_dan_uang`,
       SUM(`ct`.`lootid` = 0 AND `ct`.`maxgold` > 0) AS `uang_saja_tanpa_loot`,
       SUM(`ct`.`lootid` > 0 AND `ct`.`maxgold` = 0) AS `loot_saja_tanpa_uang`,
       SUM(`ct`.`lootid` > 0 AND `ct`.`maxgold` > 0) AS `sehat`,
       COUNT(*)                                      AS `semua_map_870`,
       SUM(NOT EXISTS (SELECT 1 FROM `creature` `c2`
                       WHERE `c2`.`id` = `ct`.`entry` AND `c2`.`map` <> @MAP_PANDARIA))
                                                     AS `hanya_map_870`
FROM `creature_template` `ct`
WHERE EXISTS (SELECT 1 FROM `creature` `c`
              WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10;

SELECT '=== 1b. Apakah lootid yang terpasang benar-benar punya baris ===' AS `bagian`;

-- Lubang yang tidak terlihat di bagian 1: `lootid` > 0 tapi menunjuk ke id yang
-- `creature_loot_template`-nya kosong. Mayatnya berkilau, itemnya tetap tidak
-- pernah ada. LootMgr.cpp mengeluhkan ini sebagai ReportNotExistedId saat boot.

SELECT SUM(EXISTS (SELECT 1 FROM `creature_loot_template` `l`
                   WHERE `l`.`entry` = `ct`.`lootid`)) AS `lootid_berisi`,
       SUM(NOT EXISTS (SELECT 1 FROM `creature_loot_template` `l`
                       WHERE `l`.`entry` = `ct`.`lootid`)) AS `lootid_kosong`
FROM `creature_template` `ct`
WHERE EXISTS (SELECT 1 FROM `creature` `c`
              WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND `ct`.`lootid` > 0
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND `ct`.`minlevel` >= 10;

SELECT '=== 2. Mob rusak yang paling banyak terspawn ===' AS `bagian`;

-- Dipakai untuk mencocokkan dengan apa yang benar-benar dibunuh pemain saat
-- mengeluh. Kalau nama-nama di sini tidak pernah ditemui pemain, keluhannya
-- bukan tentang baris-baris ini.

SELECT `ct`.`entry`,
       `ct`.`name`,
       `ct`.`minlevel`,
       `ct`.`npc_rank`,
       `ct`.`type`,
       `ct`.`lootid`,
       `ct`.`maxgold`,
       COUNT(`c`.`guid`) AS `spawn`
FROM `creature_template` `ct`
JOIN `creature` `c` ON `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA
WHERE `ct`.`lootid` = 0
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10
GROUP BY `ct`.`entry`, `ct`.`name`, `ct`.`minlevel`, `ct`.`npc_rank`, `ct`.`type`,
         `ct`.`lootid`, `ct`.`maxgold`
ORDER BY `spawn` DESC
LIMIT 25;

SELECT '=== 3. Donor yang tersedia, dipecah per type dan rank ===' AS `bagian`;

-- Donor = mob map 870 yang `lootid`-nya BENAR-BENAR punya baris. Ini bahan
-- untuk langkah 2 file perbaikan. Cocokkan dengan bagian 4: kombinasi (type,
-- rank) yang rusak tapi tidak punya donor sepadan akan turun ke tier yang lebih
-- longgar.

SELECT `ct`.`type`,
       `ct`.`npc_rank`,
       COUNT(DISTINCT `ct`.`entry`) AS `donor`,
       MIN(`ct`.`minlevel`)         AS `level_min`,
       MAX(`ct`.`minlevel`)         AS `level_max`
FROM `creature_template` `ct`
WHERE EXISTS (SELECT 1 FROM `creature` `c`
              WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND `ct`.`lootid` > 0
  AND EXISTS (SELECT 1 FROM `creature_loot_template` `l`
              WHERE `l`.`entry` = `ct`.`lootid`)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10
GROUP BY `ct`.`type`, `ct`.`npc_rank`
ORDER BY `donor` DESC;

SELECT '=== 4. Kombinasi rusak per (type, rank), untuk dijodohkan dengan 3 ===' AS `bagian`;

SELECT `ct`.`type`,
       `ct`.`npc_rank`,
       COUNT(DISTINCT `ct`.`entry`) AS `rusak`,
       MIN(`ct`.`minlevel`)         AS `level_min`,
       MAX(`ct`.`minlevel`)         AS `level_max`
FROM `creature_template` `ct`
WHERE EXISTS (SELECT 1 FROM `creature` `c`
              WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND NOT EXISTS (SELECT 1 FROM `creature` `c`
                  WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` <> @MAP_PANDARIA)
  AND `ct`.`lootid` = 0
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10
GROUP BY `ct`.`type`, `ct`.`npc_rank`
ORDER BY `rusak` DESC;

SELECT '=== 5. Keadaan HP mob map 870 sekarang ===' AS `bagian`;

-- Dibaca sebelum dan sesudah prabowow_pandaria_mob_health.sql. HP-nya sendiri
-- lahir di Creature.cpp:1059-1062 dari `Health_mod` dikali rate per-rank dari
-- config, jadi kolom inilah satu-satunya bagian yang bisa dilingkupi per-map.
--
-- Sesudah file itu jalan dengan faktor 0.3, `rata_health_mod` untuk baris
-- `hanya_map_870` harus turun jadi kira-kira 0.3 kali angka sebelumnya.

SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM `creature` `c2`
                             WHERE `c2`.`id` = `ct`.`entry` AND `c2`.`map` <> @MAP_PANDARIA)
            THEN 'hanya_map_870' ELSE 'juga_peta_lain' END AS `lingkup`,
       `ct`.`npc_rank`,
       COUNT(*)                            AS `entry`,
       ROUND(AVG(`ct`.`Health_mod`), 3)     AS `rata_health_mod`,
       ROUND(MIN(`ct`.`Health_mod`), 3)     AS `min_health_mod`,
       ROUND(MAX(`ct`.`Health_mod`), 3)     AS `max_health_mod`
FROM `creature_template` `ct`
WHERE EXISTS (SELECT 1 FROM `creature` `c`
              WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10
GROUP BY `lingkup`, `ct`.`npc_rank`
ORDER BY `lingkup`, `ct`.`npc_rank`;

SELECT '=== 6. Apakah catatan HP asli sudah ada ===' AS `bagian`;

-- `prabowow_pandaria_health_backup` dibuat prabowow_pandaria_mob_health.sql dan
-- sengaja tidak pernah dibuang: ia satu-satunya jalan pulang ke nilai asli.
-- `ada` = 0 berarti file itu belum pernah jalan di DB ini.

SELECT COUNT(*) AS `ada`
FROM `information_schema`.`TABLES`
WHERE `TABLE_SCHEMA` = DATABASE()
  AND `TABLE_NAME` = 'prabowow_pandaria_health_backup';

SELECT '=== 7. Portal Pandaria di ibu kota ===' AS `bagian`;

-- `spell_punya_tujuan` harus 1 untuk kedua baris. Nol berarti spell di `data0`
-- tidak punya baris `spell_target_position`, dan portalnya berdiri tanpa bisa
-- memindahkan siapa pun -- keadaan bawaan SFDB yang diperbaiki
-- prabowow_pandaria_city_portals.sql.

SELECT `gt`.`entry`,
       `gt`.`name`,
       `gt`.`type`,
       `gt`.`data0` AS `spell`,
       (SELECT COUNT(*) FROM `spell_target_position` `p`
        WHERE `p`.`id` = `gt`.`data0`) AS `spell_punya_tujuan`,
       (SELECT COUNT(*) FROM `gameobject` `g`
        WHERE `g`.`id` = `gt`.`entry`) AS `spawn`
FROM `gameobject_template` `gt`
WHERE `gt`.`entry` IN (215424, 215457);
