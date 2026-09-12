-- Pandaria (map 870): turunkan HP mobnya jadi 30% dari aslinya.
--
-- Yang diminta
--   Monster di Pandaria terlalu tebal untuk realm yang dimainkan sedikit orang.
--   Sisakan 30% HP, tanpa pengecualian rank -- elite, rare, dan world boss ikut.
--
-- Kenapa lewat `creature_template`.`Health_mod`, bukan lewat config
--   Core menghitung HP di Creature.cpp:1059-1062:
--
--       float healthmod = _GetHealthMod(rank);
--       uint32 basehp   = stats->GenerateHealth(cinfo, level);
--       uint32 health   = uint32(basehp * healthmod);
--
--   dan `GenerateHealth` sendiri (Creature.cpp:124-130) sudah mengalikan
--   `info->ModHealth`, yaitu kolom `Health_mod` (ObjectMgr.cpp:454, :545).
--   Jadi ada dua pengali: satu per-entry di DB, satu per-rank dari config.
--
--   Yang dari config -- Rate.Creature.Normal.HP dan saudara-saudaranya -- tidak
--   bisa dipakai di sini: ia berlaku untuk SELURUH realm, tidak punya varian
--   per-map, sehingga menurunkannya untuk Pandaria berarti ikut menurunkan
--   seluruh Azeroth. `Health_mod` satu-satunya tuas yang bisa dilingkupi.
--
-- Lingkupnya: entry yang HANYA hidup di map 870
--   `creature_template` dipakai bersama semua peta. Kalau satu entry juga
--   terspawn di Kalimdor, menurunkan `Health_mod`-nya ikut menurunkan mob yang
--   sama di sana. Karena itu syaratnya dua arah: punya spawn di map 870, DAN
--   tidak punya spawn di peta mana pun selain 870.
--
--   Entry yang dibuang saringan ini dilaporkan di bagian 4 sebagai
--   `dipakai_peta_lain`. Kalau angkanya besar dan mengganggu, jalan keluarnya
--   bukan melonggarkan saringan melainkan memberi mobnya entry sendiri -- dan
--   itu pekerjaan lain.
--
--   Saringan "bisa dibunuh" sama persis dengan yang dipakai
--   prabowow_cataclysm_zone_loot_and_gold.sql dan tools/dev/audit_loot_coverage.sql:
--     type NOT IN (8,11,12,13,14)  critter, totem, non-combat pet, gas cloud, wild pet
--     npcflag = 0                  bukan quest giver / vendor / trainer
--     unit_flags & 0x2             UNIT_FLAG_NON_ATTACKABLE    (Unit.h:626)
--     unit_flags & 0x100           UNIT_FLAG_IMMUNE_TO_PC      (Unit.h:633)
--     unit_flags & 0x2000000       UNIT_FLAG_NOT_SELECTABLE    (Unit.h:650)
--     flags_extra & 0x80           CREATURE_FLAG_EXTRA_TRIGGER (Creature.h:36)
--     minlevel >= 10               menyaring sisa NPC dekoratif level 1
--
--   `npcflag` = 0 sengaja ada: vendor dan quest giver bukan "monster", dan
--   menipiskan HP mereka tidak pernah diminta. Harganya, dan ini disadari: NPC
--   escort ber-npcflag 0 ikut kena, jadi kalau ada quest kawal yang mendadak
--   sering gagal karena yang dikawal mati terlalu cepat, entry-nya dikeluarkan
--   dengan menambahkannya ke bagian 1.
--
-- Yang TIDAK tersentuh
--   Mob yang lahir dari summon murni tanpa baris `creature`. Lingkup file ini
--   dibangun dari tabel `creature`, jadi add yang dipanggil script di tengah
--   encounter tidak punya wakil di sana. Ini disengaja -- summon semacam itu
--   biasanya bagian dari encounter yang sudah diatur script.
--
--   Dungeon dan raid Pandaria juga tidak tersentuh: semuanya map tersendiri,
--   bukan 870. Yang ada di 870 hanya konten dunia terbuka.
--
-- Idempotent, dan ini bagian yang paling penting
--   Perkalian tidak idempotent. Dijalankan dua kali, 0.3 jadi 0.09.
--
--   Karena itu nilai asli setiap entry disimpan lebih dulu di
--   `prabowow_pandaria_health_backup`, dan UPDATE-nya selalu dihitung dari
--   nilai asli itu -- bukan dari nilai yang sedang berlaku. Berapa kali pun
--   file ini dijalankan, hasilnya sama.
--
--   Tabel itu sengaja TIDAK dibuang di akhir, beda dengan meja kerja di
--   prabowow_cataclysm_zone_loot_and_gold.sql. Ia bukan meja kerja, ia satu-
--   satunya catatan nilai asli yang tersisa setelah `creature_template` ditimpa.
--   INSERT IGNORE-nya memastikan catatan itu tidak pernah tertimpa nilai yang
--   sudah diturunkan.
--
-- Membatalkannya
--   UPDATE `creature_template` `ct`
--   JOIN `prabowow_pandaria_health_backup` `b` ON `b`.`entry` = `ct`.`entry`
--   SET `ct`.`Health_mod` = `b`.`health_mod_asli`;
--   DROP TABLE `prabowow_pandaria_health_backup`;
--
-- Kapan terasa di game
--   HP dipasang saat creature di-spawn (Creature.cpp:1059), jadi mob yang sudah
--   berdiri tetap tebal sampai ia mati dan respawn, atau sampai world restart.

SET @MAP_PANDARIA := 870;

-- Sisa HP yang diinginkan. 0.3 = 30% dari aslinya.
SET @FAKTOR_HP := 0.3;

-- ---------------------------------------------------------------------------
-- 1. Lingkup
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS `prabowow_hp_scope`;
CREATE TABLE `prabowow_hp_scope` (
    `entry`    INT UNSIGNED      NOT NULL PRIMARY KEY,
    `npc_rank` TINYINT UNSIGNED  NOT NULL,
    `minlevel` SMALLINT UNSIGNED NOT NULL,
    `spawn`    INT UNSIGNED      NOT NULL,
    KEY (`npc_rank`)
);

INSERT INTO `prabowow_hp_scope` (`entry`, `npc_rank`, `minlevel`, `spawn`)
SELECT `ct`.`entry`, `ct`.`npc_rank`, `ct`.`minlevel`,
       (SELECT COUNT(*) FROM `creature` `c` WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
FROM `creature_template` `ct`
WHERE EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND NOT EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` <> @MAP_PANDARIA)
  AND `ct`.`type` NOT IN (8, 11, 12, 13, 14)
  AND `ct`.`npcflag` = 0
  AND (`ct`.`unit_flags` & (0x2 | 0x100 | 0x2000000)) = 0
  AND (`ct`.`flags_extra` & 0x80) = 0
  AND `ct`.`minlevel` >= 10;

-- ---------------------------------------------------------------------------
-- 2. Simpan nilai asli sebelum apa pun ditimpa
--
-- INSERT IGNORE, bukan REPLACE: kalau file ini sudah pernah jalan, nilai yang
-- ada di `creature_template` sekarang SUDAH diturunkan, dan menyimpannya lagi
-- akan menjadikan nilai turunan itu sebagai "asli". Baris yang sudah tercatat
-- harus dibiarkan apa adanya.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `prabowow_pandaria_health_backup` (
    `entry`           INT UNSIGNED NOT NULL PRIMARY KEY,
    `health_mod_asli` FLOAT        NOT NULL,
    `dicatat_pada`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO `prabowow_pandaria_health_backup` (`entry`, `health_mod_asli`)
SELECT `s`.`entry`, `ct`.`Health_mod`
FROM `prabowow_hp_scope` `s`
JOIN `creature_template` `ct` ON `ct`.`entry` = `s`.`entry`;

-- ---------------------------------------------------------------------------
-- 3. Terapkan, selalu dihitung dari nilai asli
-- ---------------------------------------------------------------------------

UPDATE `creature_template` `ct`
JOIN `prabowow_hp_scope` `s` ON `s`.`entry` = `ct`.`entry`
JOIN `prabowow_pandaria_health_backup` `b` ON `b`.`entry` = `ct`.`entry`
SET `ct`.`Health_mod` = `b`.`health_mod_asli` * @FAKTOR_HP;

-- ---------------------------------------------------------------------------
-- 4. Laporan, dibaca di keluaran impor
--
-- `entry` dan `spawn` menunjukkan seberapa luas perubahannya. `rata_asli` dan
-- `rata_sekarang` harus berbanding @FAKTOR_HP; kalau tidak, ada entry yang
-- nilai aslinya tercatat setelah sempat diturunkan.
--
-- `dipakai_peta_lain` adalah entry map 870 yang SENGAJA dilewat karena juga
-- terspawn di peta lain. Ia bukan kegagalan, ia harga dari lingkup yang aman.
-- ---------------------------------------------------------------------------

SELECT COUNT(*)      AS `entry`,
       SUM(`spawn`)  AS `spawn_terpengaruh`
FROM `prabowow_hp_scope`;

SELECT `s`.`npc_rank`,
       COUNT(*)                        AS `entry`,
       ROUND(AVG(`b`.`health_mod_asli`), 3) AS `rata_asli`,
       ROUND(AVG(`ct`.`Health_mod`), 3)     AS `rata_sekarang`
FROM `prabowow_hp_scope` `s`
JOIN `prabowow_pandaria_health_backup` `b` ON `b`.`entry` = `s`.`entry`
JOIN `creature_template` `ct` ON `ct`.`entry` = `s`.`entry`
GROUP BY `s`.`npc_rank`
ORDER BY `s`.`npc_rank`;

SELECT COUNT(*) AS `dipakai_peta_lain`
FROM `creature_template` `ct`
WHERE EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` = @MAP_PANDARIA)
  AND EXISTS (
        SELECT 1 FROM `creature` `c`
        WHERE `c`.`id` = `ct`.`entry` AND `c`.`map` <> @MAP_PANDARIA);

DROP TABLE IF EXISTS `prabowow_hp_scope`;
