-- Geometri spawn portal Pandaria di Stormwind dan Orgrimmar.
--
-- Lanjutan dari sql/updates/world/2026_09_11_world_00.sql, yang sudah
-- dipromosikan dan sudah tercatat di `skyfire_db_updates`. File itu tidak boleh
-- disentuh lagi -- hash isinya sudah terkunci di DB, dan mengubahnya membuat
-- worldserver berhenti di "was already applied with a different hash". Jadi
-- perbaikan susulan masuk ke file baru seperti ini.
--
-- Gejala
--   Sesudah portalnya punya tujuan dan mulai dipakai, dua cacat lain di baris
--   spawn yang sama baru kelihatan: keduanya tenggelam separuh ke dalam tanah,
--   dan yang di Orgrimmar menghadap ke arah yang salah. Selama portal itu
--   memang tidak memindahkan siapa pun, tidak ada yang pernah menyadarinya.
--
-- Dua cacat yang berdiri sendiri, dua-duanya ada di baris spawn rilis 10_to_11
--
--   (1) Tenggelam. GameObject.cpp:179 memanggil Relocate(x, y, z, ang) apa
--       adanya -- tidak ada penyesuaian ke tinggi tanah di mana pun. Dan Z
--       portalnya persis setinggi tanah: 28.62439 di Orgrimmar sementara NPC
--       yang dipasang file yang sama berdiri di 28.42856-28.90924, dan 117.2901
--       di Stormwind sementara tetangganya di 117.1907-117.9804. Jadi titik
--       pusat modelnya duduk tepat di permukaan, dan separuh bawahnya masuk
--       tanah.
--
--   (2) Salah hadap. Baris SFDB menyimpan rotation2 = 0, rotation3 = 1.
--       UpdateRotationFields (GameObject.cpp:2192) baru menurunkan rotasi dari
--       `orientation` kalau KEDUANYA nol:
--
--           if (rotation2 == 0.0f && rotation3 == 0.0f)
--
--       rotation3 = 1 membuat syarat itu gagal, jadi (0, 1) dipakai apa adanya
--       -- dan itu berarti sin(o/2) = 0, cos(o/2) = 1, yaitu orientasi 0.
--       `orientation` 5.751331 milik portal Orgrimmar tidak pernah terpakai.
--       Menolkan keduanya menyerahkan perhitungannya ke core, yang akan memakai
--       `orientation` yang memang sudah benar di baris itu.
--
--   Catatan: dari kedua portal hanya ORGRIMMAR yang benar-benar salah hadap.
--   Stormwind `orientation`-nya 0, dan (0, 1) memang sin(0/2)=0, cos(0/2)=1 --
--   nilainya kebetulan sudah benar di sana. Menolkannya tetap dilakukan supaya
--   kedua baris punya bentuk yang sama dan core yang memegang perhitungannya.
--
-- @Z_LIFT = 2.0 adalah PERKIRAAN, bukan ukuran
--   Tinggi pivot model 12658 ada di GameObjectDisplayInfo.dbc dan tidak bisa
--   dibaca dari SQL. Angka pastinya cuma bisa didapat di client. Caranya, satu
--   menit, dan hasilnya langsung tersimpan ke DB sendiri:
--
--     .gobject near 30            -- cari guid portalnya
--     .gobject move <guid> <x> <y> <z>
--
--   HandleGameObjectMoveCommand memanggil SaveToDB() di akhir, jadi begitu
--   posisinya pas, angkanya sudah ada di tabel `gameobject`. Baca balik dengan
--   laporan di bagian bawah, kurangi dengan Z tanah, lalu tulis selisihnya ke
--   @Z_LIFT supaya DB yang dibangun dari nol nanti ikut benar.
--
--   Pada realm ini guid-nya 263127 (Orgrimmar) dan 263128 (Stormwind). Angka
--   itu milik DB tersebut, bukan tetapan -- ia lahir dari @OGUID milik SFDB dan
--   bisa berbeda di DB yang dibangun ulang, jadi jangan ditulis ke file ini.
--
--   .gobject move TIDAK memperbaiki arah hadap. Ia menyimpan ulang rotasi yang
--   sedang berlaku, termasuk (0, 1) yang keliru itu. Yang memperbaikinya
--   .gobject turn, atau UPDATE rotasi di bawah -- dan UPDATE itu memang
--   dirancang tetap aman dijalankan sesudah portalnya dipindahkan tangan.
--
-- Dua UPDATE terpisah, dan penjaganya BUKAN rotasi
--   Versi pertama perbaikan ini menjaga keduanya dengan sidik jari
--   rotation2 = 0 AND rotation3 = 1, dengan anggapan .gobject move akan
--   menghapus sidik jari itu sehingga posisi yang disetel tangan aman. Anggapan
--   itu salah: SaveToDB (GameObject.cpp:742-743) menulis rotasi dari
--   GAMEOBJECT_FIELD_PARENT_ROTATION+2/3, yang saat Create diisi (0, 1) apa
--   adanya -- jadi .gobject move menyimpannya kembali sebagai (0, 1), sidik
--   jarinya bertahan, dan file ini akan menaikkan Z sekali lagi DI ATAS posisi
--   yang sudah benar.
--
--   Karena itu keduanya dipisah, dengan penjaga yang cocok untuk masing-masing.
--
--   Rotasi: dijaga "belum nol", jadi ia selalu benar dan boleh diulang. Aman
--   juga sesudah .gobject turn, yang memang sudah memanggil
--   UpdateRotationFields() tanpa argumen (cs_gobject.cpp:406) sehingga nilainya
--   sudah diturunkan dari `orientation`; menolkannya cuma membuat core
--   menghitung ulang angka yang sama.
--
--   Tinggi: dijaga nilai Z ASLI milik SFDB, dengan toleransi. Sesudah dinaikkan
--   sekali, Z-nya tidak lagi cocok dan UPDATE-nya tidak akan pernah jalan lagi.
--   Dan kalau portalnya sudah dipindahkan dengan tangan, Z-nya juga sudah tidak
--   cocok, jadi posisi pilihanmu tidak akan ditimpa.
--
--   Penjaga itu juga yang membuat file ini benar di DB yang dibangun dari nol.
--   Di sana 2026_09_11_world_00.sql baru saja memasang spawn-nya dengan angka
--   SFDB apa adanya, jadi kedua UPDATE ini cocok dan langsung membetulkannya.
--
-- Membatalkannya
--   Geometrinya dikembalikan ke angka SFDB secara mutlak, bukan dengan
--   mengurangi @Z_LIFT -- supaya benar berapa kali pun file ini sempat jalan:
--
--   UPDATE `gameobject` SET `position_z` = 28.62439,
--          `rotation2` = 0, `rotation3` = 1 WHERE `id` = 215424;
--   UPDATE `gameobject` SET `position_z` = 117.2901,
--          `rotation2` = 0, `rotation3` = 1 WHERE `id` = 215457;
-- ---------------------------------------------------------------------------

SET @GO_PORTAL_SW  := 215457;     -- 'Portal to Paw don Village', Alliance
SET @GO_PORTAL_ORG := 215424;     -- 'Portal to Honydew Village', Horde

-- Tinggi yang ditambahkan ke posisi portal, dalam yard. Angka ini PERKIRAAN
-- dan minta dicek di client -- lihat catatan @Z_LIFT di atas.
SET @Z_LIFT := 2.0;

-- ---------------------------------------------------------------------------
-- 1. Serahkan arah hadapnya ke core
-- ---------------------------------------------------------------------------

UPDATE `gameobject`
SET `rotation2` = 0,
    `rotation3` = 0
WHERE `id` IN (@GO_PORTAL_SW, @GO_PORTAL_ORG)
  AND (`rotation2` <> 0 OR `rotation3` <> 0);

-- ---------------------------------------------------------------------------
-- 2. Angkat keluar dari tanah, sekali saja
-- ---------------------------------------------------------------------------

UPDATE `gameobject`
SET `position_z` = `position_z` + @Z_LIFT
WHERE `id` = @GO_PORTAL_ORG
  AND ABS(`position_z` - 28.62439) < 0.05;

UPDATE `gameobject`
SET `position_z` = `position_z` + @Z_LIFT
WHERE `id` = @GO_PORTAL_SW
  AND ABS(`position_z` - 117.2901) < 0.05;

-- ---------------------------------------------------------------------------
-- 3. Laporan, dibaca di keluaran impor
--
-- Geometri tiap portal yang berdiri. `rotation3` harus 0 di kedua baris -- itu
-- yang membuat core menghitung arah hadapnya dari `orientation`. Kalau masih 1,
-- file ini tidak jalan dan portalnya tetap menghadap timur.
--
-- `position_z` inilah angka yang dicocokkan di client. Sesudah dipindahkan
-- dengan .gobject move, jalankan ulang laporan ini, kurangi dengan Z tanah
-- (28.62439 di Orgrimmar, 117.2901 di Stormwind), dan selisihnya adalah
-- @Z_LIFT yang benar.
-- ---------------------------------------------------------------------------

SELECT `g`.`guid`,
       `gt`.`name`,
       `g`.`map`,
       `g`.`position_x` AS `x`,
       `g`.`position_y` AS `y`,
       `g`.`position_z` AS `z`,
       `g`.`orientation`,
       `g`.`rotation2`,
       `g`.`rotation3`
FROM `gameobject` `g`
JOIN `gameobject_template` `gt` ON `gt`.`entry` = `g`.`id`
WHERE `g`.`id` IN (@GO_PORTAL_SW, @GO_PORTAL_ORG);
