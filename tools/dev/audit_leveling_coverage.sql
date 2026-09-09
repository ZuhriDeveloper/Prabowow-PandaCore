-- Audit isi konten leveling 80-90 pada world DB yang sedang jalan.
--
-- Kenapa ada file ini
--   Dump dasar SFDB tidak ada di repo -- ia diunduh sekali ke volume Docker
--   saat deploy (deploy/docker-compose.prod.yml, WORLD_DB_URL). Jadi satu-
--   satunya cara tahu zona mana yang benar-benar kosong adalah bertanya ke DB
--   yang hidup. Semua yang di bawah SELECT saja, tidak mengubah apa pun.
--
-- Cara jalan di VPS
--   PW='-f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env'
--   docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
--       < audit_leveling_coverage.sql
--
-- Cara membaca hasilnya
--   Bagian 2 yang paling penting. Sebuah zona baru bisa dimainkan kalau
--   `pemberi_terspawn` dan `penutup_terspawn` mendekati `quest`. Kalau `quest`
--   besar tapi keduanya 0, quest-nya ada di DB tapi tidak ada NPC-nya sama
--   sekali -- itu persis kondisi Mount Hyjal sebelum diport.

SELECT '=== 1. Jumlah spawn per map ===' AS `bagian`;

SELECT `map`,
       COUNT(*)                                   AS creature,
       (SELECT COUNT(*) FROM `gameobject` `g` WHERE `g`.`map` = `c`.`map`) AS gameobject
FROM `creature` `c`
GROUP BY `map`
ORDER BY `map`;

SELECT '=== 2. Kelengkapan quest per zona leveling 80-90 ===' AS `bagian`;

SELECT `z`.`band`,
       `z`.`label`,
       `z`.`id`,
       (SELECT COUNT(*) FROM `quest_template` `q`
         WHERE `q`.`ZoneOrSort` = `z`.`id`)                        AS `quest`,
       (SELECT COUNT(*) FROM `quest_template` `q`
         WHERE `q`.`ZoneOrSort` = `z`.`id`
           AND EXISTS (SELECT 1 FROM `creature_queststarter` `s`
                        WHERE `s`.`quest` = `q`.`Id`))             AS `ada_pemberi`,
       (SELECT COUNT(*) FROM `quest_template` `q`
         WHERE `q`.`ZoneOrSort` = `z`.`id`
           AND EXISTS (SELECT 1 FROM `creature_queststarter` `s`
                       JOIN `creature` `c` ON `c`.`id` = `s`.`id`
                        WHERE `s`.`quest` = `q`.`Id`))             AS `pemberi_terspawn`,
       (SELECT COUNT(*) FROM `quest_template` `q`
         WHERE `q`.`ZoneOrSort` = `z`.`id`
           AND EXISTS (SELECT 1 FROM `creature_questender` `e`
                       JOIN `creature` `c` ON `c`.`id` = `e`.`id`
                        WHERE `e`.`quest` = `q`.`Id`))             AS `penutup_terspawn`
FROM (
    SELECT  616 AS `id`, 'Mount Hyjal'                AS `label`, '80-82' AS `band`
    UNION ALL SELECT 4815, 'Vashjir: Kelpthar Forest',      '80-82'
    UNION ALL SELECT 5144, 'Vashjir: Shimmering Expanse',   '81-83'
    UNION ALL SELECT 5145, 'Vashjir: Abyssal Depths',       '82-83'
    UNION ALL SELECT 5042, 'Deepholm',                      '82-83'
    UNION ALL SELECT 5034, 'Uldum',                         '83-84'
    UNION ALL SELECT 4922, 'Twilight Highlands',            '84-85'
    UNION ALL SELECT 5785, 'The Jade Forest',               '85-86'
    UNION ALL SELECT 5805, 'Valley of the Four Winds',      '86-87'
    UNION ALL SELECT 5842, 'Krasarang Wilds',               '86-87'
    UNION ALL SELECT 5841, 'Kun-Lai Summit',                '87-88'
    UNION ALL SELECT 6138, 'Townlong Steppes',              '88-89'
    UNION ALL SELECT 6134, 'Dread Wastes',                  '89-90'
    UNION ALL SELECT 5840, 'Vale of Eternal Blossoms',      '90'
) `z`
ORDER BY `z`.`band`, `z`.`label`;

SELECT '=== 3. Loot table kosong pada creature yang benar-benar di-spawn ===' AS `bagian`;

-- lootid > 0 berarti template menjanjikan loot. Kalau tabelnya tidak ada,
-- mob-nya tidak menjatuhkan apa pun -- termasuk uang dan drop quest. Ini
-- lubang yang sama seperti 73 loot table Hyjal.
SELECT `c`.`map`,
       COUNT(DISTINCT `ct`.`entry`) AS `entry_tanpa_loot`
FROM `creature` `c`
JOIN `creature_template` `ct` ON `ct`.`entry` = `c`.`id`
WHERE `ct`.`lootid` > 0
  AND NOT EXISTS (SELECT 1 FROM `creature_loot_template` `l`
                   WHERE `l`.`entry` = `ct`.`lootid`)
GROUP BY `c`.`map`
ORDER BY `entry_tanpa_loot` DESC;

SELECT '=== 4. Rentang guid custom yang sudah terpakai ===' AS `bagian`;

-- Supaya port zona berikutnya tidak menabrak blok yang sudah dipakai.
SELECT 'creature' AS `tabel`, FLOOR(`guid` / 10000) * 10000 AS `blok`, COUNT(*) AS `baris`
FROM `creature` WHERE `guid` >= 8300000 GROUP BY FLOOR(`guid` / 10000) * 10000
UNION ALL
SELECT 'gameobject', FLOOR(`guid` / 10000) * 10000, COUNT(*)
FROM `gameobject` WHERE `guid` >= 8300000 GROUP BY FLOOR(`guid` / 10000) * 10000
ORDER BY `tabel`, `blok`;
