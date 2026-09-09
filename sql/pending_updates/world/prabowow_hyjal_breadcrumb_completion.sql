-- Mount Hyjal: breadcrumb-nya harus selesai saat emissary memindahkan pemain.
--
-- Gejala
--   "Hero's Call: Mount Hyjal!" (27726) / "Warchief's Command: Mount Hyjal!"
--   (27721) tetap belum selesai setelah Cenarion Emissary Jademoon (15187) /
--   Blackhoof (15188) memindahkan pemain ke Moonglade. Emissary Windsong di
--   Nighthaven lalu tidak mau menerimanya, dan "As Hyjal Burns" (25316) tidak
--   pernah ditawarkan.
--
-- Sebabnya
--   Kedua quest itu tidak punya objective bunuh/kumpul. Objective-nya sebuah
--   event -- "Transportation to Moonglade Secured" -- dan core menahannya
--   sampai ada yang memanggil Player::AreaExploredOrEventHappens untuk quest
--   itu: CanCompleteQuest menolak quest ber-SpecialFlags 2 yang belum
--   Explored, dan objective DUMMY (cara MoP memodelkan event) dihitung sebagai
--   counter yang hanya diisi fungsi yang sama (PlayerQuestState.cpp:307 dan
--   :1662).
--
--   Di data retail 4.3.4 kedua emissary hanya punya SATU baris smart_scripts:
--   cast spell 86587 (Alliance) / 86565 (Horde), "Teleport: Moonglade", ke
--   pemain. Penyelesaian quest-nya menumpang pada efek spell itu. Ketika
--   sql/updates/world/2026_09_08_world_01.sql mengganti spell dengan
--   SMART_ACTION_TELEPORT -- supaya tidak bergantung pada DBC yang tidak bisa
--   diperiksa lewat SQL -- efek sampingan itu ikut hilang.
--
-- Perbaikannya
--   Rantai gossip kedua emissary didefinisikan ulang lengkap, karena file yang
--   memasangnya sudah dipromosikan dan tidak boleh diubah. Tiga langkah yang
--   saling terhubung: tutup gossip, tandai event quest-nya selesai untuk si
--   penekan tombol (SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS, di SkyFire
--   bernomor 15 -- bukan 33 seperti TrinityCore), baru teleport. Penyelesaian
--   diletakkan SEBELUM teleport supaya terjadi saat pemain masih berdiri
--   tenang di depan NPC-nya. Aksi 15 tidak melakukan apa-apa kalau pemain
--   tidak memegang quest-nya, jadi aman untuk siapa pun yang cuma numpang
--   teleport.
--
--   Pemain yang sudah terlanjur di Moonglade dengan quest yang menggantung
--   ditolong di sql/pending_updates/world/prabowow_hyjal_windsong_ride.sql:
--   Windsong menyelesaikan event yang sama begitu jendelanya dibuka.
--
-- Idempotent: baris smart_scripts kedua emissary dihapus dulu, lalu diisi ulang
-- sebagai keadaan akhir yang utuh -- apa pun versi file sebelumnya yang sudah
-- sampai ke DB ini.

SET @JADEMOON  := 15187;    -- Cenarion Emissary Jademoon, Stormwind Keep
SET @BLACKHOOF := 15188;    -- Cenarion Emissary Blackhoof, Orgrimmar
SET @MENU_ALLIANCE := 12129;
SET @MENU_HORDE    := 12125;
SET @BREADCRUMB_A  := 27726;  -- Hero's Call: Mount Hyjal!
SET @BREADCRUMB_H  := 27721;  -- Warchief's Command: Mount Hyjal!

-- ---------------------------------------------------------------------------
-- Titik mendarat di Moonglade, sama persis dengan 2026_09_08_world_01.sql:
-- dibaca dari spell_target_position kedua spell aslinya kalau ada, jatuh ke
-- angka yang sama sebagai literal kalau tidak. Map 1, Nighthaven.
-- ---------------------------------------------------------------------------

SET @LAND_X := COALESCE((SELECT `target_position_x`  FROM `spell_target_position`
                         WHERE `id` IN (86587, 86565) LIMIT 1),  7827.41);
SET @LAND_Y := COALESCE((SELECT `target_position_y`  FROM `spell_target_position`
                         WHERE `id` IN (86587, 86565) LIMIT 1), -2423.57);
SET @LAND_Z := COALESCE((SELECT `target_position_z`  FROM `spell_target_position`
                         WHERE `id` IN (86587, 86565) LIMIT 1),  488.806);
SET @LAND_O := COALESCE((SELECT `target_orientation` FROM `spell_target_position`
                         WHERE `id` IN (86587, 86565) LIMIT 1),  3.38425);

-- ---------------------------------------------------------------------------
-- Rantainya
--
-- SMART_EVENT_GOSSIP_SELECT (62): menuId, gossipListId. Menu ini satu pilihan,
-- list id 0. SMART_EVENT_LINK (61) meneruskan invoker yang sama ke baris
-- berikutnya. SMART_ACTION_CLOSE_GOSSIP = 72, SMART_ACTION_CALL_AREAEXPLORED-
-- OREVENTHAPPENS = 15 (QuestID di action_param1), SMART_ACTION_TELEPORT = 62
-- (map di action_param1, tujuan di target_x/y/z/o). SMART_TARGET_ACTION_INVOKER
-- = 7 supaya yang ditandai dan yang pindah pemainnya, bukan NPC-nya.
-- ---------------------------------------------------------------------------

DELETE FROM `smart_scripts` WHERE `source_type` = 0 AND `entryorguid` IN (@JADEMOON, @BLACKHOOF);

INSERT INTO `smart_scripts`
    (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
     `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`,
     `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
     `target_type`, `target_param1`, `target_param2`, `target_param3`,
     `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
    (@JADEMOON, 0, 0, 1, 62, 0, 100, 0, @MENU_ALLIANCE, 0, 0, 0, 0,
     72, 0, 0, 0, 0, 0, 0,
     1, 0, 0, 0, 0, 0, 0, 0,
     'Cenarion Emissary Jademoon - On gossip select - Close gossip'),
    (@JADEMOON, 0, 1, 2, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     15, @BREADCRUMB_A, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'Cenarion Emissary Jademoon - Linked - Complete Hero''s Call: Mount Hyjal! for player'),
    (@JADEMOON, 0, 2, 0, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     62, 1, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @LAND_X, @LAND_Y, @LAND_Z, @LAND_O,
     'Cenarion Emissary Jademoon - Linked - Teleport player to Moonglade'),
    (@BLACKHOOF, 0, 0, 1, 62, 0, 100, 0, @MENU_HORDE, 0, 0, 0, 0,
     72, 0, 0, 0, 0, 0, 0,
     1, 0, 0, 0, 0, 0, 0, 0,
     'Cenarion Emissary Blackhoof - On gossip select - Close gossip'),
    (@BLACKHOOF, 0, 1, 2, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     15, @BREADCRUMB_H, 0, 0, 0, 0, 0,
     7, 0, 0, 0, 0, 0, 0, 0,
     'Cenarion Emissary Blackhoof - Linked - Complete Warchief''s Command: Mount Hyjal! for player'),
    (@BLACKHOOF, 0, 2, 0, 61, 0, 100, 0, 0, 0, 0, 0, 0,
     62, 1, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @LAND_X, @LAND_Y, @LAND_Z, @LAND_O,
     'Cenarion Emissary Blackhoof - Linked - Teleport player to Moonglade');
