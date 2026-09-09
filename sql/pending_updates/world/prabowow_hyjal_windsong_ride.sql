-- Mount Hyjal: tumpangan dari Moonglade ke Nordrassil.
--
-- Latar belakang
--   Rantai Hyjal punya dua lompatan. Yang pertama sudah dipasang di
--   sql/updates/world/2026_09_08_world_01.sql: Cenarion Emissary Jademoon
--   (15187) / Blackhoof (15188) memindahkan pemain dari ibu kota ke Moonglade,
--   tempat Emissary Windsong (39865) menerima breadcrumb 27726/27721 dan
--   memberi "As Hyjal Burns" (25316).
--
--   Lompatan kedua tidak pernah ada di sini, jadi rantainya berhenti di
--   Moonglade. Di retail objective 25316 berbunyi "Fly to Hyjal using Aronus
--   and speak to Ysera once you're there": Aronus menerbangkan pemain ke
--   Nordrassil. Yang itu tidak bisa ditiru lewat data. Di dump 4.3.4 Aronus
--   (39128) tidak punya baris `creature` sama sekali -- ia dipanggil oleh
--   script C++ `npc_mh_aronus`, yang lalu mendudukkan pemain di vehicle 39140
--   dan menjalankan spline-nya. Tidak ada satu pun baris smart_scripts untuk
--   39128, gossip_menu_id-nya 0, dan waypoint vehicle-nya bukan data world DB.
--
--   SkyFire tidak punya script itu: src/server/scripts/Kalimdor tidak punya
--   folder MountHyjal sama sekali. Jadi Aronus tidak dipasang; sebagai
--   gantinya Windsong yang memindahkan pemain begitu quest-nya diterima.
--
-- Kenapa lewat quest accept, bukan gossip
--   Gossip butuh baris `gossip_menu` yang menunjuk `npc_text`, dan teks Aronus
--   tidak ada di data retail (menu-nya dibuat oleh script C++ tadi). Membuat
--   npc_text baru berarti menebak skema tabel itu di SFDB. SMART_EVENT_ACCEPTED_QUEST
--   tidak butuh teks apa pun: pemain menerima 25316 dari Windsong, lalu langsung
--   berdiri di Nordrassil, di samping Ysera yang menutup quest itu.
--
-- Untuk pemain yang sudah terlanjur memegang 25316
--   Event ini hanya menyala saat quest diterima. Yang quest-nya sudah ada di
--   log sebelum file ini masuk cukup membatalkan lalu mengambilnya lagi dari
--   Windsong.
--
-- Perjalanan balik
--   Tidak perlu diurus di sini: PraboWoW.AllFlightPaths.Enable menandai semua
--   titik terbang sebagai dikenal, jadi Nordrassil bisa dituju dari flight
--   master Nighthaven begitu pemain pernah sampai.
--
-- Idempotent: baris smart_scripts milik file ini dihapus dulu, lalu diisi ulang.

SET @WINDSONG   := 39865;   -- Emissary Windsong, Nighthaven
SET @QUEST_HYJAL := 25316;  -- As Hyjal Burns

-- ---------------------------------------------------------------------------
-- 1. Windsong harus benar-benar menawarkan quest, dan harus jalan dengan SmartAI
--
-- 2026_09_08_world_01.sql memasang templatenya lewat INSERT IGNORE, jadi kalau
-- SFDB sudah punya entry 39865 lebih dulu, npcflag dan AIName di sana yang
-- dipakai -- dan keduanya belum tentu benar. Dua UPDATE ini menegaskan
-- keduanya tanpa menyentuh kolom lain. QUESTGIVER = 0x2; SmartAI wajib supaya
-- SmartAI::sQuestAccept (SmartAI.cpp:746) terpanggil.
-- ---------------------------------------------------------------------------

UPDATE `creature_template`
SET `npcflag` = `npcflag` | 2,
    `AIName`  = 'SmartAI',
    `ScriptName` = ''
WHERE `entry` = @WINDSONG;

-- ---------------------------------------------------------------------------
-- 2. Titik mendarat di Nordrassil
--
-- Diambil dari sekitar Ysera (40289), penutup quest 25316, yang di-spawn oleh
-- sql/updates/world/2026_09_08_world_03.sql pada 5490.67 -3563.56 1569.33.
-- Titik di bawah berjarak ~6 yard darinya dan sejajar dengan tiga NPC lain di
-- sana (40863/40864/40865 pada z 1571.1-1571.5), jadi tanahnya terbukti ada.
-- Orientasinya menghadap Ysera.
--
-- Bukan game_tele 'MountHyjal' (5075.76 -3201.27 1889.44): titik itu untuk
-- .tele GM dan berdiri jauh dari Ysera.
-- ---------------------------------------------------------------------------

SET @LAND_MAP := 1;
SET @LAND_X   := 5487.0;
SET @LAND_Y   := -3558.5;
SET @LAND_Z   := 1570.0;
SET @LAND_O   := 5.34;

-- ---------------------------------------------------------------------------
-- 3. Aksinya
--
-- SMART_EVENT_ACCEPTED_QUEST (19) menerima QuestID di event_param1; 0 berarti
-- quest apa pun, jadi id-nya diisi supaya quest lain milik Windsong tidak ikut
-- memindahkan pemain. SMART_ACTION_TELEPORT (62) memakai action_param1 sebagai
-- map dan target_x/y/z/o sebagai tujuan, dengan SMART_TARGET_ACTION_INVOKER (7)
-- supaya yang pindah pemainnya, bukan NPC-nya.
-- ---------------------------------------------------------------------------

DELETE FROM `smart_scripts` WHERE `source_type` = 0 AND `entryorguid` = @WINDSONG;

INSERT INTO `smart_scripts`
    (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
     `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`,
     `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
     `target_type`, `target_param1`, `target_param2`, `target_param3`,
     `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
    (@WINDSONG, 0, 0, 0, 19, 0, 100, 0, @QUEST_HYJAL, 0, 0, 0, 0,
     62, @LAND_MAP, 0, 0, 0, 0, 0,
     7, 0, 0, 0, @LAND_X, @LAND_Y, @LAND_Z, @LAND_O,
     'Emissary Windsong - On quest As Hyjal Burns accepted - Teleport player to Nordrassil');
