-- Titik tujuan yang hilang untuk spell Teleport milik Mage.
--
-- Gejala
--   Mage Alliance hanya bisa Teleport ke Stormwind dan Exodar. Tujuan lain
--   "berhasil": cast selesai, animasinya jalan, cooldown jalan -- tapi pemain
--   tetap berdiri di tempat yang sama. Tidak ada pesan salah di mana pun, baik
--   di client maupun di log server.
--
-- Sebab
--   Spell Teleport memakai target TARGET_DEST_DB (17): koordinat tujuannya
--   bukan di DBC, melainkan dibaca dari tabel `spell_target_position`.
--   Spell::SelectImplicitCasterDestTargets (src/server/game/Spells/Spell.cpp:1400-1416)
--   mencari barisnya, dan kalau tidak ketemu ia TIDAK menggagalkan cast:
--
--       m_targets.SetDst(target ? *target : *m_caster);
--
--   yaitu tujuannya jadi posisi si pemain sendiri. EffectTeleportUnits
--   (src/server/game/Spells/SpellEffectsMovement.cpp:153) lalu memindahkan
--   pemain ke tempat dia sudah berdiri. Itulah "tidak terjadi apa-apa" yang
--   terlihat di game.
--
--   Diamnya total, dan itu yang membuat cacat ini bertahan lama:
--     * pengecekan kelengkapan saat boot dikomentari di SpellMgr.cpp:1585-1616;
--     * miss saat cast cuma SF_LOG_DEBUG (Spell.cpp:1411), tidak pernah muncul
--       di log dengan setelan bawaan.
--   Yang berisik justru baris yang ADA tapi salah (SpellMgr.cpp:1566 dan :1578),
--   bukan baris yang hilang.
--
--   Dump dasar SFDB memang tidak lengkap. Yang sudah punya baris: 3561
--   Stormwind, 3563 Undercity, 3567 Orgrimmar, 32271 Exodar, 32272 Silvermoon,
--   33690 Shattrath (A), 35715 Shattrath (H), 49358 Stonard, 53140 Dalaran,
--   89597 Tol Barad. Enam yang ada di file ini tidak punya, dan tidak ada satu
--   pun file di sql/updates/world/ atau sql/old/5.4.8/ yang menambahkannya.
--   Untuk mage Alliance yang belum sampai Shattrath/Dalaran, yang tersisa
--   memang persis Stormwind dan Exodar.
--
-- Dari mana koordinatnya -- ini bukan tebakan
--   Dua sumber yang tidak berhubungan memberi angka yang sama persis, sampai
--   digit terakhir, termasuk effIndex-nya:
--
--     (1) Tabel `spell_target_position` di dump world TrinityCore 4.3.4
--         (TDB_full_world_434.22011). Di sana keenam spell ini lengkap dan
--         semuanya effIndex 0.
--
--     (2) Baris "Portal Effect" MoP milik dump SFDB ini sendiri, yaitu titik
--         mendarat portal grup yang SEKARANG sudah jalan:
--           121849 Darnassus     = 3565
--           121851 Ironforge     = 3562
--           121858 Theramore     = 49359
--           121859 Thunder Bluff = 3566
--           121860 Tol Barad (A) = 88342
--           121861 Tol Barad (H) = 88344
--         Masuk akal: Teleport dan Portal ke kota yang sama memang mendarat di
--         titik yang sama.
--
--   Karena itu masalah effIndex yang dulu membuat
--   sql/updates/world/2026_09_11_world_00.sql MENOLAK menambah baris
--   spell_target_position tidak berlaku di sini. Di sana effIndex-nya harus
--   ditebak (130321 memakai 0, 125060 memakai 1, dan Spell.dbc tidak bisa
--   dibaca dari SQL); di sini angkanya terbaca dari data.
--
--   Kalaupun ternyata salah, kesalahannya berisik, bukan diam: worldserver akan
--   menulis "does not have target TARGET_DEST_DB (17)" (SpellMgr.cpp:1578) ke
--   sql.sql setiap boot untuk baris yang effIndex-nya keliru.
--
-- Yang sengaja TIDAK dikerjakan
--   * Spell Portal grup (10059, 11416, 11419, 32266, 49360, 88345, 11417,
--     11418, 11420, 32267, 49361, 88346, 53142) tidak disentuh. Rantai portal
--     MoP tidak lewat spell itu: GO portalnya bertipe SPELLCASTER dan meng-cast
--     spell "Portal Effect" 121847-121862, yang barisnya sudah lengkap di SFDB.
--   * Teleport/Portal ke Shrine of Two Moons dan Shrine of Seven Stars tidak
--     ada di sini. Id spell-nya tidak muncul di tabel mana pun di dump SFDB,
--     jadi harus dibaca dulu dari Spell.dbc dengan `.lookup spell Shrine ...`
--     di dalam game. Itu file terpisah.
--   * Jumlah charge, cooldown, dan reagen tidak disentuh -- semuanya di DBC.
--
-- Idempotensi
--   DELETE lalu INSERT untuk keenam id. Aman dijalankan berulang kali, dan aman
--   juga kalau rilis SFDB berikutnya ternyata sudah membawa barisnya sendiri:
--   isi file ini yang menang, dan isinya sama dengan yang dibawa TDB.
--
-- Sebelum menjalankan, lihat dulu apa yang sudah ada di DB yang berjalan:
--
--   SELECT `id`, `effIndex`, `target_map`, `target_position_x`,
--          `target_position_y`, `target_position_z`, `target_orientation`
--   FROM `spell_target_position`
--   WHERE `id` IN (3561, 3562, 3563, 3565, 3566, 3567, 32271, 32272, 33690,
--                  35715, 49358, 49359, 53140, 88342, 88344, 89597)
--   ORDER BY `id`;
--
-- Rollback
--   DELETE FROM `spell_target_position`
--   WHERE `id` IN (3562, 3565, 3566, 49359, 88342, 88344);
--
--   Sesudah itu restart worldserver (atau `.reload spell_target_position`,
--   cs_reload.cpp:914). Teleport-nya kembali diam seperti semula.

-- ---------------------------------------------------------------------------
-- 1. Enam tujuan Teleport yang hilang
-- ---------------------------------------------------------------------------

DELETE FROM `spell_target_position`
WHERE `id` IN (3562, 3565, 3566, 49359, 88342, 88344);

INSERT INTO `spell_target_position`
    (`id`, `effIndex`, `target_map`, `target_position_x`, `target_position_y`, `target_position_z`, `target_orientation`)
VALUES
    (3562,  0,   0, -4613.71,  -915.287,  501.062,  0),        -- Teleport: Ironforge
    (3565,  0,   1,  9656.54,  2518.26,  1331.66,   0),        -- Teleport: Darnassus
    (3566,  0,   1,  -967.375,  284.82,   110.773,  3.19999),  -- Teleport: Thunder Bluff
    (49359, 0,   1, -3748.11, -4440.21,    30.5688, 3.95172),  -- Teleport: Theramore
    (88342, 0, 732,  -369.208, 1058.73,    21.7719, 0.634577), -- Teleport: Tol Barad (Alliance)
    (88344, 0, 732,  -603.724, 1387.62,    22.0498, 0.469644); -- Teleport: Tol Barad (Horde)

-- ---------------------------------------------------------------------------
-- 2. Laporan, dibaca di keluaran impor
--
-- Enam belas spell Teleport yang dikenal, berdampingan. Kolom `status` menandai
-- mana yang punya tujuan: sesudah file ini jalan tidak boleh ada satu pun yang
-- "HILANG".
--
-- `target_map` yang tidak masuk akal (map instance, atau benua yang salah untuk
-- kota itu) adalah tanda baris lama yang keliru, bukan hasil file ini.
-- ---------------------------------------------------------------------------

SELECT `t`.`id`,
       `t`.`nama`,
       CASE WHEN `s`.`id` IS NULL THEN 'HILANG' ELSE 'ADA' END AS `status`,
       `s`.`effIndex`,
       `s`.`target_map`,
       `s`.`target_position_x` AS `x`,
       `s`.`target_position_y` AS `y`,
       `s`.`target_position_z` AS `z`,
       `s`.`target_orientation` AS `o`
FROM (
    SELECT  3561 AS `id`, 'Teleport: Stormwind'          AS `nama` UNION ALL
    SELECT  3562,         'Teleport: Ironforge'                    UNION ALL
    SELECT  3563,         'Teleport: Undercity'                    UNION ALL
    SELECT  3565,         'Teleport: Darnassus'                    UNION ALL
    SELECT  3566,         'Teleport: Thunder Bluff'                UNION ALL
    SELECT  3567,         'Teleport: Orgrimmar'                    UNION ALL
    SELECT 32271,         'Teleport: Exodar'                       UNION ALL
    SELECT 32272,         'Teleport: Silvermoon'                   UNION ALL
    SELECT 33690,         'Teleport: Shattrath (A)'                UNION ALL
    SELECT 35715,         'Teleport: Shattrath (H)'                UNION ALL
    SELECT 49358,         'Teleport: Stonard'                      UNION ALL
    SELECT 49359,         'Teleport: Theramore'                    UNION ALL
    SELECT 53140,         'Teleport: Dalaran'                      UNION ALL
    SELECT 88342,         'Teleport: Tol Barad (A)'                UNION ALL
    SELECT 88344,         'Teleport: Tol Barad (H)'                UNION ALL
    SELECT 89597,         'Teleport: Tol Barad'
) AS `t`
LEFT JOIN `spell_target_position` `s` ON `s`.`id` = `t`.`id`
ORDER BY `t`.`id`;
