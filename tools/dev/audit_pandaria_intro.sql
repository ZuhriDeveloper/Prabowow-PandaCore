-- Audit jalan masuk quest Pandaria di world DB yang sedang jalan.
--
-- Gejala
--   Pemain level 85 membuka Hero's Call Board (Alliance) atau Warchief's
--   Command Board (Horde) dan tidak melihat satu pun quest yang mengarah ke
--   Pandaria (map 870).
--
-- Yang sudah dipastikan dari kode, jadi tidak perlu diaudit lagi
--   Bukan gerbang expansion. Core ini tidak punya SatisfyQuestExpansion sama
--   sekali (PlayerQuestState.cpp:248-259), `quest_template` tidak punya kolom
--   expansion, Expansion = 4 (worldserver.conf.dist:800), MaxPlayerLevel = 90,
--   `account`.`expansion` default 4, gamebuild 18414.
--
--   Papan tugas itu GAMEOBJECT_TYPE_QUESTGIVER polos tanpa script C++:
--   GameObject.cpp:1480-1490 -> Player::PrepareGossipMenu -> PrepareQuestMenu
--   (PlayerQuestState.cpp:29-87), dan untuk GO fungsi itu HANYA membaca
--   `gameobject_queststarter` / `gameobject_questender`. Jadi kalau papannya
--   kosong, tidak ada baris di kedua tabel itu -- bukan yang lain.
--
--   Papannya sendiri terbukti berfungsi di realm ini: pemain memang menerima
--   "Hero's Call: Mount Hyjal!" (27726) dari papan yang sama (lihat
--   sql/updates/world/2026_09_08_world_01.sql).
--
-- Yang belum bisa dijawab tanpa DB hidup, dan itulah isi file ini
--   Entry papan mana yang benar-benar terspawn dan di kota mana; relasi quest
--   intro apa yang sudah ada; apakah NPC kuncinya punya spawn; bentuk objective
--   quest-nya di skema DB ini; dan yang paling menentukan -- apakah zona
--   Pandaria punya NPC sama sekali. Semua SELECT, aman dijalankan kapan pun.
--
-- Cara jalan di VPS
--   PW='-f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env'
--   docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
--       < audit_pandaria_intro.sql
--
-- Quest yang dilacak
--   29547 The King's Command   (A) MinLevel 85, zona 1519, NextQuestIdChain 29548
--   29548 The Mission          (A) MinLevel 85, zona 1519, NextQuestIdChain 31732
--   29611 The Art of War       (H) MinLevel 85, zona 1637, NextQuestIdChain 31853
--   29612 The Art of War (alt) (H) MinLevel 85, zona 1637, NextQuestIdChain 31853
--   31732 / 31853              lanjutan rantainya di Pandaria

SELECT '=== 1. Papan tugas: template, type, dan jumlah spawn-nya ===' AS `bagian`;

-- Entry di bawah diambil dari gameobject_template dump TrinityCore 4.3.4; nama
-- ikut dicocokkan supaya papan yang hanya ada di SFDB tetap kelihatan.
-- data3 = questgiver.gossipID, data1 = questgiver.questList (GameObject.h:62-76).
-- Kalau gossipID nol, papan itu tidak punya menu gossip sendiri dan daftar quest
-- adalah satu-satunya isinya.
SELECT `gt`.`entry`, `gt`.`type`, `gt`.`name`,
       `gt`.`data1`   AS `questList`, `gt`.`data3` AS `gossipID`,
       `gt`.`AIName`, `gt`.`ScriptName`,
       (SELECT COUNT(*) FROM `gameobject` `g` WHERE `g`.`id` = `gt`.`entry`) AS `spawn`
FROM `gameobject_template` `gt`
WHERE `gt`.`entry` IN (206109, 206111, 206116, 206294, 207279,
                       207320, 207321, 207322, 207323, 207324, 207325,
                       208316, 208317)
   OR `gt`.`name` IN ('Hero''s Call Board', 'Warchief''s Command Board')
ORDER BY `gt`.`name`, `gt`.`entry`;

SELECT '=== 1b. Di kota mana saja papannya benar-benar berdiri ===' AS `bagian`;

SELECT `gt`.`name`, `g`.`id`, `g`.`guid`, `g`.`map`,
       ROUND(`g`.`position_x`, 2) AS `x`,
       ROUND(`g`.`position_y`, 2) AS `y`,
       ROUND(`g`.`position_z`, 2) AS `z`,
       ROUND(`g`.`orientation`, 3) AS `o`,
       `g`.`phaseid`, `g`.`spawnMask`
FROM `gameobject` `g`
JOIN `gameobject_template` `gt` ON `gt`.`entry` = `g`.`id`
WHERE `gt`.`name` IN ('Hero''s Call Board', 'Warchief''s Command Board')
ORDER BY `gt`.`name`, `g`.`map`, `g`.`guid`;

SELECT '=== 2. Quest apa saja yang sudah menempel di papan ===' AS `bagian`;

SELECT `s`.`id` AS `go_entry`, `gt`.`name`, `s`.`quest`, `q`.`Title`,
       `q`.`MinLevel`, `q`.`Level`, `q`.`ZoneOrSort`
FROM `gameobject_queststarter` `s`
JOIN `gameobject_template` `gt` ON `gt`.`entry` = `s`.`id`
LEFT JOIN `quest_template` `q` ON `q`.`Id` = `s`.`quest`
WHERE `gt`.`name` IN ('Hero''s Call Board', 'Warchief''s Command Board')
ORDER BY `gt`.`name`, `s`.`id`, `q`.`MinLevel`, `s`.`quest`;

SELECT '=== 3. Relasi quest intro Pandaria, lengkap dengan spawn NPC-nya ===' AS `bagian`;

SELECT 'creature_queststarter' AS `tabel`, `s`.`quest`, `s`.`id` AS `pemberi`,
       `ct`.`name`,
       (SELECT COUNT(*) FROM `creature` `c` WHERE `c`.`id` = `s`.`id`) AS `spawn`
FROM `creature_queststarter` `s`
LEFT JOIN `creature_template` `ct` ON `ct`.`entry` = `s`.`id`
WHERE `s`.`quest` IN (29547, 29548, 29611, 29612, 31732, 31853)
UNION ALL
SELECT 'creature_questender', `e`.`quest`, `e`.`id`, `ct`.`name`,
       (SELECT COUNT(*) FROM `creature` `c` WHERE `c`.`id` = `e`.`id`)
FROM `creature_questender` `e`
LEFT JOIN `creature_template` `ct` ON `ct`.`entry` = `e`.`id`
WHERE `e`.`quest` IN (29547, 29548, 29611, 29612, 31732, 31853)
UNION ALL
SELECT 'gameobject_queststarter', `s`.`quest`, `s`.`id`, `gt`.`name`,
       (SELECT COUNT(*) FROM `gameobject` `g` WHERE `g`.`id` = `s`.`id`)
FROM `gameobject_queststarter` `s`
LEFT JOIN `gameobject_template` `gt` ON `gt`.`entry` = `s`.`id`
WHERE `s`.`quest` IN (29547, 29548, 29611, 29612, 31732, 31853)
UNION ALL
SELECT 'gameobject_questender', `e`.`quest`, `e`.`id`, `gt`.`name`,
       (SELECT COUNT(*) FROM `gameobject` `g` WHERE `g`.`id` = `e`.`id`)
FROM `gameobject_questender` `e`
LEFT JOIN `gameobject_template` `gt` ON `gt`.`entry` = `e`.`id`
WHERE `e`.`quest` IN (29547, 29548, 29611, 29612, 31732, 31853)
ORDER BY `quest`, `tabel`, `pemberi`;

SELECT '=== 4. NPC kunci: ada template-nya, ada spawn-nya, bisa diajak bicara? ===' AS `bagian`;

-- npcflag bit 1 = GOSSIP. Bit itu menentukan lebih dari sekadar menu: tanpa
-- GOSSIP client mengirim CMSG_QUESTGIVER_HELLO, dan jalur itu TIDAK pernah
-- memanggil Player::TalkedToCreature -- hanya NPCHandler.cpp:341 yang
-- memanggilnya. Objective bertipe NPC_INTERACT tidak akan pernah selesai di NPC
-- yang cuma punya bit QUESTGIVER.
--
--   55567 dicurigai bukan Jes-Tereth melainkan bunny kill-credit; ini yang
--         memastikannya
--   54870 General Nazgrim, penutup 29611/29612
--   55054 General Nazgrim versi lain, pemilik gossip kapal (menu 14988)
--   66292 Sky Admiral Rogers, penutup 29548, pemilik gossip kapal (menu 14971)
SELECT `ct`.`entry`, `ct`.`name`, `ct`.`npcflag`,
       (`ct`.`npcflag` & 1) AS `punya_gossip`,
       `ct`.`gossip_menu_id`, `ct`.`AIName`, `ct`.`ScriptName`,
       `ct`.`unit_flags`, `ct`.`faction_A`, `ct`.`faction_H`, `ct`.`minlevel`,
       (SELECT COUNT(*) FROM `creature` `c` WHERE `c`.`id` = `ct`.`entry`) AS `spawn`,
       (SELECT CONCAT(`c`.`map`, ' @ ', ROUND(`c`.`position_x`, 1), ' ',
                      ROUND(`c`.`position_y`, 1), ' ', ROUND(`c`.`position_z`, 1))
          FROM `creature` `c` WHERE `c`.`id` = `ct`.`entry` LIMIT 1) AS `contoh_posisi`
FROM `creature_template` `ct`
WHERE `ct`.`entry` IN (54870, 55054, 55567, 66292)
   OR `ct`.`name` LIKE '%Jes-Tereth%'
ORDER BY `ct`.`entry`;

SELECT '=== 5. quest_template intro, apa adanya di skema DB ini ===' AS `bagian`;

-- Core ini TIDAK punya kolom RequiredNpcOrGo*; ObjectMgr.cpp:3709 memuat kolom
-- di bawah dan objective-nya ada di tabel terpisah (bagian 6).
SELECT `Id`, `Title`, `Method`, `Level`, `MinLevel`, `MaxLevel`, `ZoneOrSort`, `Type`,
       `RequiredClasses`, `RequiredRaces`,
       `PrevQuestId`, `NextQuestId`, `ExclusiveGroup`, `NextQuestIdChain`,
       `Flags`, `Flags2`, `SpecialFlags`, `SourceItemId`
FROM `quest_template`
WHERE `Id` IN (29547, 29548, 29611, 29612, 31732, 31853)
ORDER BY `Id`;

SELECT '=== 6. Objective-nya, dan siapa objectId-nya ===' AS `bagian`;

-- Ini yang menentukan bagaimana breadcrumb-nya ditandai selesai:
--   type 0  NPC          -> SMART_ACTION_CALL_KILLEDMONSTER (33)
--   type 3  NPC_INTERACT -> tidak ada aksi smart-nya; hanya TalkedToCreature
--                           lewat CMSG_GOSSIP_HELLO pada NPC objectId itu
--   type 10 DUMMY        -> SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS (15)
SELECT `o`.`questId`, `o`.`id`, `o`.`index`, `o`.`type`, `o`.`objectId`,
       `o`.`amount`, `o`.`flags`, `o`.`description`,
       `ct`.`name` AS `nama_objectId`,
       (SELECT COUNT(*) FROM `creature` `c` WHERE `c`.`id` = `o`.`objectId`) AS `objectId_terspawn`
FROM `quest_objective` `o`
LEFT JOIN `creature_template` `ct` ON `ct`.`entry` = `o`.`objectId`
WHERE `o`.`questId` IN (29547, 29548, 29611, 29612, 31732, 31853)
ORDER BY `o`.`questId`, `o`.`index`;

SELECT '=== 7. Ada quest yang di-disable? ===' AS `bagian`;

-- DISABLE_TYPE_QUEST = 1, diperiksa paling awal di CanTakeQuest
-- (PlayerQuestState.cpp:250). Satu baris di sini menjelaskan segalanya.
SELECT * FROM `disables`
WHERE `sourceType` = 1
  AND `entry` IN (29547, 29548, 29611, 29612, 31732, 31853);

SELECT '=== 8. Titik mendarat Jade Forest yang sudah ada di DB ===' AS `bagian`;

-- 130321 Alliance, 125060 Horde -- dua spell teleport yang dipakai gossip kapal
-- Sky Admiral Rogers (66292) dan General Nazgrim (55054) di data SFDB sendiri.
SELECT * FROM `spell_target_position` WHERE `id` IN (125060, 130321);
SELECT * FROM `game_tele` WHERE `map` = 870 ORDER BY `name`;

SELECT '=== 9. Gossip kapal yang sudah dipasang SFDB ===' AS `bagian`;

SELECT * FROM `smart_scripts`
WHERE `source_type` = 0 AND `entryorguid` IN (54870, 55054, 66292)
ORDER BY `entryorguid`, `id`;

SELECT `MenuID`, `OptionID`, `OptionIcon`, `OptionText`, `OptionType`, `ActionMenuID`
FROM `gossip_menu_option`
WHERE `MenuID` IN (14971, 14988)
ORDER BY `MenuID`, `OptionID`;

SELECT '=== 10. Cakupan quest zona Pandaria, termasuk relasi gameobject ===' AS `bagian`;

-- audit_leveling_coverage.sql bagian 2 hanya melihat creature_queststarter /
-- creature_questender. Papan tugas adalah GAMEOBJECT, jadi seluruh jalur masuk
-- lewat papan tidak pernah terlihat di sana. Blok ini menutup lubang itu.
SELECT `z`.`label`, `z`.`id`,
       (SELECT COUNT(*) FROM `quest_template` `q` WHERE `q`.`ZoneOrSort` = `z`.`id`) AS `quest`,
       (SELECT COUNT(*) FROM `quest_template` `q`
         WHERE `q`.`ZoneOrSort` = `z`.`id`
           AND (EXISTS (SELECT 1 FROM `creature_queststarter` `s`
                         JOIN `creature` `c` ON `c`.`id` = `s`.`id`
                        WHERE `s`.`quest` = `q`.`Id`)
             OR EXISTS (SELECT 1 FROM `gameobject_queststarter` `s`
                         JOIN `gameobject` `g` ON `g`.`id` = `s`.`id`
                        WHERE `s`.`quest` = `q`.`Id`)))          AS `pemberi_terspawn`,
       (SELECT COUNT(*) FROM `quest_template` `q`
         WHERE `q`.`ZoneOrSort` = `z`.`id`
           AND (EXISTS (SELECT 1 FROM `creature_questender` `e`
                         JOIN `creature` `c` ON `c`.`id` = `e`.`id`
                        WHERE `e`.`quest` = `q`.`Id`)
             OR EXISTS (SELECT 1 FROM `gameobject_questender` `e`
                         JOIN `gameobject` `g` ON `g`.`id` = `e`.`id`
                        WHERE `e`.`quest` = `q`.`Id`)))          AS `penutup_terspawn`
FROM (
              SELECT 5785 AS `id`, 'The Jade Forest'          AS `label`
    UNION ALL SELECT 5805,         'Valley of the Four Winds'
    UNION ALL SELECT 5842,         'Krasarang Wilds'
    UNION ALL SELECT 5841,         'Kun-Lai Summit'
    UNION ALL SELECT 6138,         'Townlong Steppes'
    UNION ALL SELECT 6134,         'Dread Wastes'
    UNION ALL SELECT 5840,         'Vale of Eternal Blossoms'
) `z`
ORDER BY `z`.`id`;

SELECT '=== 11. Berapa banyak yang benar-benar berdiri di map 870 ===' AS `bagian`;

-- Kalau angka ini mendekati nol, mengantar pemain ke Jade Forest sama saja
-- membuang mereka ke zona kosong. Itu kondisi Mount Hyjal sebelum diport, dan
-- dump 4.3.4 tidak bisa menolong: dump itu tidak punya map 870 sama sekali.
SELECT (SELECT COUNT(*) FROM `creature`   WHERE `map` = 870) AS `creature_spawn`,
       (SELECT COUNT(*) FROM `gameobject` WHERE `map` = 870) AS `gameobject_spawn`,
       (SELECT COUNT(DISTINCT `ct`.`entry`)
          FROM `quest_template` `q`
          JOIN `creature_queststarter` `s` ON `s`.`quest` = `q`.`Id`
          JOIN `creature_template` `ct` ON `ct`.`entry` = `s`.`id`
          JOIN `creature` `c` ON `c`.`id` = `ct`.`entry`
         WHERE `q`.`ZoneOrSort` = 5785 AND `c`.`map` = 870) AS `pemberi_jade_forest`;
