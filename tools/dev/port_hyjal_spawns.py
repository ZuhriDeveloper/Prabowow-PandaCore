#!/usr/bin/env python3
"""Generate the Mount Hyjal spawn port SQL from a TrinityCore 4.3.4 world dump.

SFDB tidak punya isi zona Mount Hyjal (zone 616): tidak ada creature, tidak ada
gameobject, jadi rantai quest-nya buntu begitu pemain sampai di sana. Konten
Hyjal di client MoP 5.4.8 pada dasarnya sama dengan Cataclysm, jadi data spawn
diambil dari dump world TDB 4.3.4 lalu diterjemahkan ke skema SkyFire 5.4.8.

Kenapa Python, padahal skrip lain di tools/dev PowerShell: masukannya mysqldump
~292 MB yang harus dibaca sambil jalan dan dipecah per tuple. PowerShell tidak
cocok untuk itu.

Yang dihasilkan satu file SQL idempotent untuk sql/pending_updates/world/.

Pemakaian:

    python tools/dev/port_hyjal_spawns.py \
        --dump path/ke/TDB_full_world_434.sql \
        --out  sql/pending_updates/world/prabowow_hyjal_zone_spawns.sql

Keputusan yang dibuat skrip ini, semuanya sengaja:

* Semua spawn diratakan ke `phaseid = 0` supaya terlihat oleh semua pemain.
  Phasing asli Hyjal digerakkan script C++ yang tidak ada di SkyFire, jadi kalau
  phaseid disalin apa adanya zonanya tetap terlihat kosong. Konsekuensinya versi
  berbeda dari area yang sama tampil bersamaan.
* Karena itu spawn di-dedupe: entry yang sama pada posisi yang sama (dibulatkan
  DEDUPE_YARDS yard) hanya diambil satu, dan baris fase dasar (169) menang.
* `MovementType = 2` (waypoint) diturunkan ke 0 karena `waypoint_data` tidak
  ikut diport; NPC-nya diam, bukan berjalan ke path yang tidak ada.
* `AIName` dan `ScriptName` dikosongkan pada template hasil port: SkyFire tidak
  punya baris smart_scripts maupun script C++ yang dirujuk nama-nama itu.
* Template hanya diisi untuk entry yang belum ada (INSERT IGNORE). Data SFDB
  yang sudah benar tidak pernah ditimpa.
* `mindmg`/`maxdmg`/`attackpower` tidak ada di skema 4.3.4 (di sana damage
  dihitung dari BaseVariance/DamageModifier), sementara SkyFire memakainya apa
  adanya lewat Creature::SelectLevel. Jadi kolom itu diisi 0 dulu, lalu satu
  UPDATE di akhir file mengambil rata-rata dari template yang sudah ada di DB
  pada minlevel dan rank yang sama.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

ZONE_HYJAL = 616
BASE_PHASE = 169
DEDUPE_YARDS = 3.0

CREATURE_GUID_FIRST = 8400001
CREATURE_GUID_LAST = 8404000
GAMEOBJECT_GUID_FIRST = 8400001
GAMEOBJECT_GUID_LAST = 8401000

ROWS_PER_INSERT = 500

CREATE_RE = re.compile(rb"^CREATE TABLE `([A-Za-z_0-9]+)`")
INSERT_RE = re.compile(rb"^INSERT INTO `([A-Za-z_0-9]+)`")
COLUMN_RE = re.compile(rb"^\s+`([A-Za-z_0-9]+)`")
BACKSLASH = chr(92)


# ---------------------------------------------------------------------------
# Membaca dump
# ---------------------------------------------------------------------------

def split_tuples(statement: str):
    """Pecah bagian VALUES sebuah INSERT jadi tuple-tuple, sadar tanda kutip."""
    start = statement.find("VALUES")
    if start < 0:
        return
    body = statement[start + len("VALUES"):]

    depth = 0
    begin = None
    in_quote = False
    escaped = False
    for index, char in enumerate(body):
        if escaped:
            escaped = False
            continue
        if char == BACKSLASH:
            escaped = True
            continue
        if char == "'":
            in_quote = not in_quote
            continue
        if in_quote:
            continue
        if char == "(":
            if depth == 0:
                begin = index
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0 and begin is not None:
                yield body[begin + 1:index]
                begin = None


def split_fields(tuple_body: str):
    """Pecah satu tuple jadi literal SQL mentah (tetap ter-escape apa adanya)."""
    fields = []
    current = ""
    in_quote = False
    escaped = False
    for char in tuple_body:
        if escaped:
            current += char
            escaped = False
            continue
        if char == BACKSLASH:
            current += char
            escaped = True
            continue
        if char == "'":
            in_quote = not in_quote
            current += char
            continue
        if char == "," and not in_quote:
            fields.append(current.strip())
            current = ""
            continue
        current += char
    fields.append(current.strip())
    return fields


def scan(dump: Path, wanted: set):
    """Baca dump sekali, hasilkan (nama tabel, dict kolom -> literal SQL).

    Nama kolom diambil dari CREATE TABLE di dump yang sama, jadi skrip ini tidak
    bergantung pada urutan kolom yang di-hardcode.
    """
    schema: dict[str, list[str]] = {}
    columns: list[str] = []
    creating = None
    current_table = None

    with dump.open("rb") as handle:
        for raw in handle:
            create = CREATE_RE.match(raw)
            if create:
                creating = create.group(1).decode()
                columns = []
                continue

            if creating is not None:
                if raw.startswith(b")") or raw.lstrip().startswith((b"PRIMARY KEY", b"KEY", b"UNIQUE", b"CONSTRAINT")):
                    if raw.startswith(b")"):
                        schema[creating] = columns
                        creating = None
                    continue
                column = COLUMN_RE.match(raw)
                if column:
                    columns.append(column.group(1).decode())
                continue

            insert = INSERT_RE.match(raw)
            if insert:
                current_table = insert.group(1).decode()
            if current_table not in wanted:
                continue

            names = schema.get(current_table)
            if not names:
                continue

            statement = raw.decode("utf8", "replace")
            for body in split_tuples(statement):
                values = split_fields(body)
                if len(values) != len(names):
                    continue
                yield current_table, dict(zip(names, values))


# ---------------------------------------------------------------------------
# Menulis SQL
# ---------------------------------------------------------------------------

def write_insert(out, table: str, columns: list[str], rows: list[list[str]], ignore: bool = False):
    if not rows:
        return
    keyword = "INSERT IGNORE INTO" if ignore else "INSERT INTO"
    column_list = ", ".join("`%s`" % name for name in columns)
    for start in range(0, len(rows), ROWS_PER_INSERT):
        chunk = rows[start:start + ROWS_PER_INSERT]
        out.write("%s `%s` (%s) VALUES\n" % (keyword, table, column_list))
        out.write(",\n".join("(%s)" % ", ".join(row) for row in chunk))
        out.write(";\n\n")


def number(value: str, fallback: str = "0") -> str:
    """Literal angka apa adanya; NULL dan teks kosong jadi fallback."""
    if value is None:
        return fallback
    value = value.strip()
    if value == "" or value.upper() == "NULL":
        return fallback
    return value


def text(value: str) -> str:
    if value is None or value.strip().upper() == "NULL":
        return "''"
    return value.strip()


# ---------------------------------------------------------------------------
# Pemetaan kolom 4.3.4 -> 5.4.8
# ---------------------------------------------------------------------------

CREATURE_COLUMNS = [
    "guid", "id", "map", "modelid", "equipment_id",
    "position_x", "position_y", "position_z", "orientation",
    "spawntimesecs", "spawndist", "currentwaypoint", "curhealth", "curmana",
    "MovementType", "spawnMask", "phaseid", "phasegroup",
    "npcflag", "unit_flags", "dynamicflags",
]

GAMEOBJECT_COLUMNS = [
    "guid", "id", "map",
    "position_x", "position_y", "position_z", "orientation",
    "rotation0", "rotation1", "rotation2", "rotation3",
    "spawntimesecs", "animprogress", "state", "spawnMask", "phaseid", "phasegroup",
]

CREATURE_TEMPLATE_COLUMNS = [
    "entry", "difficulty_entry_1", "difficulty_entry_2", "difficulty_entry_3",
    "KillCredit1", "KillCredit2", "modelid1", "modelid2", "modelid3", "modelid4",
    "name", "subname", "IconName", "gossip_menu_id", "minlevel", "maxlevel",
    "exp", "exp_unk", "faction_A", "faction_H", "npcflag", "speed_walk", "speed_run",
    "scale", "npc_rank", "mindmg", "maxdmg", "dmgschool", "attackpower",
    "dmg_multiplier", "baseattacktime", "rangeattacktime", "unit_class",
    "unit_flags", "unit_flags2", "dynamicflags", "family", "trainer_type",
    "trainer_class", "trainer_race", "minrangedmg", "maxrangedmg",
    "rangedattackpower", "type", "type_flags", "type_flags2", "lootid",
    "pickpocketloot", "skinloot", "resistance1", "resistance2", "resistance3",
    "resistance4", "resistance5", "resistance6", "spell1", "spell2", "spell3",
    "spell4", "spell5", "spell6", "spell7", "spell8", "PetSpellDataId",
    "VehicleId", "mingold", "maxgold", "AIName", "MovementType", "InhabitType",
    "HoverHeight", "Health_mod", "Mana_mod", "Mana_mod_extra", "Armor_mod",
    "RacialLeader", "questItem1", "questItem2", "questItem3", "questItem4",
    "questItem5", "questItem6", "movementId", "RegenHealth",
    "mechanic_immune_mask", "flags_extra", "ScriptName", "ModLevel",
    "detection_range",
]

GAMEOBJECT_TEMPLATE_COLUMNS = (
    ["entry", "type", "displayId", "name", "IconName", "castBarCaption", "unk1",
     "faction", "flags", "size"]
    + ["questItem%d" % index for index in range(1, 7)]
    + ["data%d" % index for index in range(0, 32)]
    + ["unkInt32", "AIName", "ScriptName"]
)


def creature_row(source: dict, guid: int) -> list[str]:
    movement = number(source["MovementType"])
    # Waypoint movement tanpa waypoint_data bikin core menulis error dan NPC-nya
    # tetap diam. Turunkan ke idle sekalian.
    if movement == "2":
        movement = "0"
    return [
        str(guid), number(source["id"]), number(source["map"]),
        number(source["modelid"]), number(source["equipment_id"]),
        number(source["position_x"]), number(source["position_y"]),
        number(source["position_z"]), number(source["orientation"]),
        number(source["spawntimesecs"], "120"), number(source["spawndist"]),
        number(source["currentwaypoint"]), number(source["curhealth"], "1"),
        number(source["curmana"]), movement, number(source["spawnMask"], "1"),
        "0", "0",
        number(source["npcflag"]), number(source["unit_flags"]),
        number(source["dynamicflags"]),
    ]


def gameobject_row(source: dict, guid: int) -> list[str]:
    return [
        str(guid), number(source["id"]), number(source["map"]),
        number(source["position_x"]), number(source["position_y"]),
        number(source["position_z"]), number(source["orientation"]),
        number(source["rotation0"]), number(source["rotation1"]),
        number(source["rotation2"]), number(source["rotation3"]),
        number(source["spawntimesecs"], "120"), number(source["animprogress"], "100"),
        number(source["state"]), number(source["spawnMask"], "1"), "0", "0",
    ]


def creature_template_row(source: dict) -> list[str]:
    movement = number(source["MovementType"])
    if movement == "2":
        movement = "0"
    faction = number(source["faction"])
    return [
        number(source["entry"]),
        number(source["difficulty_entry_1"]), number(source["difficulty_entry_2"]),
        number(source["difficulty_entry_3"]),
        number(source["KillCredit1"]), number(source["KillCredit2"]),
        number(source["modelid1"]), number(source["modelid2"]),
        number(source["modelid3"]), number(source["modelid4"]),
        text(source["name"]), text(source["subname"]), text(source["IconName"]),
        number(source["gossip_menu_id"]),
        number(source["minlevel"], "1"), number(source["maxlevel"], "1"),
        number(source["exp"]), number(source["exp_unk"]),
        faction, faction,
        number(source["npcflag"]),
        number(source["speed_walk"], "1"), number(source["speed_run"], "1.14286"),
        number(source["scale"], "1"), number(source["rank"]),
        # mindmg / maxdmg -- diisi UPDATE di akhir file
        "0", "0",
        number(source["dmgschool"]),
        # attackpower
        "0",
        # dmg_multiplier
        "1",
        number(source["BaseAttackTime"], "2000"), number(source["RangeAttackTime"], "2000"),
        number(source["unit_class"], "1"), number(source["unit_flags"]),
        number(source["unit_flags2"]), number(source["dynamicflags"]),
        number(source["family"]), number(source["trainer_type"]),
        number(source["trainer_class"]), number(source["trainer_race"]),
        # minrangedmg / maxrangedmg / rangedattackpower
        "0", "0", "0",
        number(source["type"]), number(source["type_flags"]), number(source["type_flags2"]),
        number(source["lootid"]), number(source["pickpocketloot"]), number(source["skinloot"]),
        number(source["resistance1"]), number(source["resistance2"]),
        number(source["resistance3"]), number(source["resistance4"]),
        number(source["resistance5"]), number(source["resistance6"]),
        number(source["spell1"]), number(source["spell2"]), number(source["spell3"]),
        number(source["spell4"]), number(source["spell5"]), number(source["spell6"]),
        number(source["spell7"]), number(source["spell8"]),
        number(source["PetSpellDataId"]), number(source["VehicleId"]),
        number(source["mingold"]), number(source["maxgold"]),
        # AIName dikosongkan: smart_scripts Hyjal tidak ikut diport
        "''",
        movement,
        # InhabitType tidak ada di 4.3.4; 3 = darat + air, default lama TrinityCore
        "3",
        number(source["HoverHeight"], "1"),
        number(source["HealthModifier"], "1"), number(source["ManaModifier"], "1"),
        number(source["ManaModifierExtra"], "0"), number(source["ArmorModifier"], "1"),
        number(source["RacialLeader"]),
        "0", "0", "0", "0", "0", "0",
        number(source["movementId"]), number(source["RegenHealth"], "1"),
        number(source["mechanic_immune_mask"]), number(source["flags_extra"]),
        # ScriptName dikosongkan: script C++ Hyjal tidak ada di SkyFire
        "''",
        # ModLevel = 0. Kalau 1, core memaksa level creature jadi 90.
        "0",
        # detection_range: DEFAULT_DETECTION_RANGE di Creature.h
        "20",
    ]


def gameobject_template_row(source: dict, addon: dict | None) -> list[str]:
    row = [
        number(source["entry"]), number(source["type"]), number(source["displayId"]),
        text(source["name"]), text(source["IconName"]), text(source["castBarCaption"]),
        text(source["unk1"]),
        # faction dan flags pindah ke gameobject_template_addon di 4.3.4
        number(addon["faction"]) if addon else "0",
        number(addon["flags"]) if addon else "0",
        number(source["size"], "1"),
    ]
    row += ["0"] * 6
    row += [number(source["Data%d" % index]) for index in range(0, 32)]
    row += ["0", "''", "''"]
    return row


# ---------------------------------------------------------------------------

def dedupe_key(source: dict) -> tuple:
    keys = [source["id"]]
    for axis in ("position_x", "position_y", "position_z"):
        try:
            keys.append(round(float(source[axis]) / DEDUPE_YARDS))
        except (TypeError, ValueError):
            keys.append(0)
    return tuple(keys)


def collect(dump: Path):
    """Lewat satu: spawn zona 616. Lewat dua: template dan tabel pendukungnya."""
    creatures: dict[tuple, dict] = {}
    gameobjects: dict[tuple, dict] = {}

    for table, row in scan(dump, {"creature", "gameobject"}):
        if row.get("zoneId") != str(ZONE_HYJAL):
            continue
        target = creatures if table == "creature" else gameobjects
        key = dedupe_key(row)
        existing = target.get(key)
        if existing is None or (row.get("PhaseId") == str(BASE_PHASE)
                                and existing.get("PhaseId") != str(BASE_PHASE)):
            target[key] = row

    creature_entries = {row["id"] for row in creatures.values()}
    gameobject_entries = {row["id"] for row in gameobjects.values()}

    templates: dict[str, dict] = {}
    go_templates: dict[str, dict] = {}
    go_addons: dict[str, dict] = {}
    equipment: list[dict] = []
    quest_ids: set[str] = set()
    relations: dict[str, list[tuple[str, str]]] = defaultdict(list)

    second_pass = {
        "creature_template", "gameobject_template", "gameobject_template_addon",
        "creature_equip_template", "quest_template",
        "creature_queststarter", "creature_questender",
        "gameobject_queststarter", "gameobject_questender",
    }

    for table, row in scan(dump, second_pass):
        if table == "creature_template" and row["entry"] in creature_entries:
            templates[row["entry"]] = row
        elif table == "gameobject_template" and row["entry"] in gameobject_entries:
            go_templates[row["entry"]] = row
        elif table == "gameobject_template_addon" and row["entry"] in gameobject_entries:
            go_addons[row["entry"]] = row
        elif table == "creature_equip_template" and row["CreatureID"] in creature_entries:
            # Semua baris equip milik entry yang di-spawn ikut diport, bukan
            # cuma yang ditunjuk eksplisit: `creature.equipment_id` = -1 berarti
            # "pilih acak dari tabel ini", dan kalau tabelnya kosong core menulis
            # error lalu melucuti senjata NPC-nya.
            equipment.append(row)
        elif table == "quest_template" and row["QuestSortID"] == str(ZONE_HYJAL):
            # 4.3.4 menamainya QuestSortID; di SkyFire kolom yang sama bernama
            # ZoneOrSort. Nilainya sama: id zona untuk quest yang terikat zona.
            quest_ids.add(row["ID"])
        elif table in ("creature_queststarter", "creature_questender",
                       "gameobject_queststarter", "gameobject_questender"):
            relations[table].append((row["id"], row["quest"]))

    for table in list(relations):
        relations[table] = [pair for pair in relations[table] if pair[1] in quest_ids]

    # Entry yang di-spawn tapi templatenya tidak ada di dump tetap dibiarkan:
    # SFDB mungkin sudah punya. Kalau ternyata tidak, core membuang spawn-nya
    # sambil menulis error, dan error itu yang kita cari saat verifikasi.
    for label, spawned, found in (("creature", creature_entries, templates),
                                  ("gameobject", gameobject_entries, go_templates)):
        missing = sorted(spawned - set(found), key=int)
        if missing:
            print("peringatan: %d entry %s tanpa template di dump: %s"
                  % (len(missing), label, ", ".join(missing[:10])), file=sys.stderr)

    return {
        "creatures": list(creatures.values()),
        "gameobjects": list(gameobjects.values()),
        "templates": templates,
        "go_templates": go_templates,
        "go_addons": go_addons,
        "equipment": equipment,
        "quests": quest_ids,
        "relations": relations,
    }


HEADER = """-- Mount Hyjal: isi zona 616 yang tidak ada di dump SFDB.
--
-- Latar belakang
--   Rantai quest Hyjal buntu bukan karena bug core, tapi karena world DB kita
--   berasal dari dump SFDB yang tidak punya satu pun spawn di zona itu. Pemain
--   yang sampai ke Nordrassil menemukan zona kosong. File ini mengisinya
--   dengan data spawn dari dump world TrinityCore 4.3.4, diterjemahkan ke
--   skema SkyFire 5.4.8. Konten Hyjal di client 5.4.8 sama dengan Cataclysm,
--   jadi entry, koordinat dan quest-nya cocok.
--
-- Dibuat oleh tools/dev/port_hyjal_spawns.py -- jangan diedit tangan, ubah
-- skripnya lalu bangkitkan ulang.
--
-- Keputusan yang perlu diketahui saat membaca file ini
--   * Semua spawn dipasang di `phaseid` 0 supaya terlihat semua pemain. Phasing
--     asli Hyjal digerakkan script C++ yang tidak ada di SkyFire; kalau phaseid
--     disalin apa adanya, zonanya tetap kosong di mata pemain. Harganya: versi
--     berbeda dari area yang sama tampil bersamaan.
--   * Karena itu spawn di-dedupe pada radius {dedupe} yard per entry, dan baris
--     fase dasar ({base_phase}) yang dimenangkan.
--   * Template hanya diisi untuk entry yang belum ada (INSERT IGNORE). Baris
--     SFDB yang sudah benar tidak pernah ditimpa.
--   * `AIName` dan `ScriptName` dikosongkan pada template hasil port: baris
--     smart_scripts dan script C++ yang dirujuk nama-nama itu tidak ada di sini.
--   * `MovementType` 2 (waypoint) diturunkan ke 0 karena `waypoint_data` tidak
--     ikut diport.
--
-- Idempotent: rentang guid milik file ini dihapus dulu, lalu diisi ulang.
--   creature   {cre_first}-{cre_last}
--   gameobject {go_first}-{go_last}
"""


def generate(data: dict, out_path: Path, dump_name: str):
    creatures = sorted(data["creatures"], key=lambda row: (int(row["id"]), row["guid"]))
    gameobjects = sorted(data["gameobjects"], key=lambda row: (int(row["id"]), row["guid"]))

    if len(creatures) > CREATURE_GUID_LAST - CREATURE_GUID_FIRST + 1:
        raise SystemExit("creature spawn (%d) melebihi rentang guid yang dicadangkan" % len(creatures))
    if len(gameobjects) > GAMEOBJECT_GUID_LAST - GAMEOBJECT_GUID_FIRST + 1:
        raise SystemExit("gameobject spawn (%d) melebihi rentang guid yang dicadangkan" % len(gameobjects))

    template_entries = sorted(data["templates"], key=int)

    with out_path.open("w", encoding="utf8", newline="\n") as out:
        out.write(HEADER.format(
            dedupe=DEDUPE_YARDS, base_phase=BASE_PHASE,
            cre_first=CREATURE_GUID_FIRST, cre_last=CREATURE_GUID_LAST,
            go_first=GAMEOBJECT_GUID_FIRST, go_last=GAMEOBJECT_GUID_LAST,
        ))
        out.write("--\n-- Sumber: %s\n" % dump_name)
        out.write("-- Isi: %d creature, %d gameobject, %d creature_template, %d gameobject_template.\n\n"
                  % (len(creatures), len(gameobjects), len(template_entries), len(data["go_templates"])))

        out.write("DELETE FROM `creature` WHERE `guid` BETWEEN %d AND %d;\n"
                  % (CREATURE_GUID_FIRST, CREATURE_GUID_LAST))
        out.write("DELETE FROM `gameobject` WHERE `guid` BETWEEN %d AND %d;\n\n"
                  % (GAMEOBJECT_GUID_FIRST, GAMEOBJECT_GUID_LAST))

        out.write("-- ---------------------------------------------------------------------------\n")
        out.write("-- Template yang belum ada di SFDB\n")
        out.write("-- ---------------------------------------------------------------------------\n\n")

        out.write("-- Daftar entry yang benar-benar baru dicatat dulu, sebelum INSERT IGNORE di\n"
                  "-- bawah menutup bedanya. Backfill damage nanti hanya boleh menyentuh entry\n"
                  "-- di daftar ini, jangan sampai baris SFDB yang kebetulan bermindmg 0 ikut\n"
                  "-- tertimpa.\n")
        out.write("DROP TABLE IF EXISTS `prabowow_hyjal_new_templates`;\n")
        out.write("CREATE TABLE `prabowow_hyjal_new_templates` (`entry` INT UNSIGNED NOT NULL PRIMARY KEY);\n")
        write_insert(out, "prabowow_hyjal_new_templates", ["entry"],
                     [[entry] for entry in template_entries])
        out.write("DELETE FROM `prabowow_hyjal_new_templates`\n"
                  "WHERE `entry` IN (SELECT `entry` FROM `creature_template`);\n\n")

        write_insert(out, "creature_template", CREATURE_TEMPLATE_COLUMNS,
                     [creature_template_row(data["templates"][entry]) for entry in template_entries],
                     ignore=True)

        out.write("-- Damage: kolom mindmg/maxdmg/attackpower tidak ada di skema 4.3.4, tapi\n")
        out.write("-- Creature::SelectLevel memakainya apa adanya. Template baru di atas masuk\n")
        out.write("-- dengan nilai 0, lalu diisi rata-rata template yang sudah ada di DB pada\n")
        out.write("-- minlevel dan rank yang sama. Kalau tidak ada pembanding, dipakai rata-rata\n")
        out.write("-- level terdekat.\n")
        # Tabel bantu ini sengaja BUKAN TEMPORARY: MySQL melarang satu query
        # menyebut tabel temporary lebih dari sekali, dan UPDATE cadangan di
        # bawah menyebutnya di dalam subquery. Dihapus lagi di akhir blok.
        out.write("DROP TABLE IF EXISTS `prabowow_hyjal_dmg_ref`;\n")
        out.write("CREATE TABLE `prabowow_hyjal_dmg_ref` AS\n"
                  "    SELECT `minlevel`, `npc_rank`, AVG(`mindmg`) AS `mindmg`,\n"
                  "           AVG(`maxdmg`) AS `maxdmg`, AVG(`attackpower`) AS `attackpower`\n"
                  "    FROM `creature_template`\n"
                  "    WHERE `mindmg` > 0\n"
                  "      AND `entry` NOT IN (SELECT `entry` FROM `prabowow_hyjal_new_templates`)\n"
                  "    GROUP BY `minlevel`, `npc_rank`;\n\n")
        out.write("UPDATE `creature_template` `ct`\n"
                  "JOIN `prabowow_hyjal_new_templates` `new` ON `new`.`entry` = `ct`.`entry`\n"
                  "JOIN `prabowow_hyjal_dmg_ref` `ref`\n"
                  "  ON `ref`.`minlevel` = `ct`.`minlevel` AND `ref`.`npc_rank` = `ct`.`npc_rank`\n"
                  "SET `ct`.`mindmg` = `ref`.`mindmg`,\n"
                  "    `ct`.`maxdmg` = `ref`.`maxdmg`,\n"
                  "    `ct`.`attackpower` = `ref`.`attackpower`;\n\n")
        out.write("-- Sisanya (kombinasi level/rank tanpa pembanding persis) memakai level\n"
                  "-- terdekat. Satu UPDATE per kolom karena MySQL cuma boleh menyebut tabel\n"
                  "-- bantu sekali per query, dan mindmg terakhir karena syaratnya membacanya.\n")
        for column in ("attackpower", "maxdmg", "mindmg"):
            out.write("UPDATE `creature_template` `ct`\n"
                      "JOIN `prabowow_hyjal_new_templates` `new` ON `new`.`entry` = `ct`.`entry`\n"
                      "SET `ct`.`%s` = COALESCE((\n"
                      "        SELECT `ref`.`%s` FROM `prabowow_hyjal_dmg_ref` `ref`\n"
                      "        ORDER BY ABS(`ref`.`minlevel` - `ct`.`minlevel`),\n"
                      "                 `ref`.`npc_rank` = `ct`.`npc_rank` DESC\n"
                      "        LIMIT 1), 1)\n"
                      "WHERE `ct`.`%s` = 0;\n\n" % (column, column, column))
        out.write("DROP TABLE IF EXISTS `prabowow_hyjal_dmg_ref`;\n")
        out.write("DROP TABLE IF EXISTS `prabowow_hyjal_new_templates`;\n\n")

        equipment_rows = [[number(row["CreatureID"]), number(row["ID"]),
                           number(row["ItemID1"]), number(row["ItemID2"]), number(row["ItemID3"])]
                          for row in data["equipment"]]
        if equipment_rows:
            out.write("-- Senjata yang dipegang NPC hasil port.\n")
            write_insert(out, "creature_equip_template",
                         ["entry", "id", "itemEntry1", "itemEntry2", "itemEntry3"],
                         equipment_rows, ignore=True)

        go_entries = sorted(data["go_templates"], key=int)
        write_insert(out, "gameobject_template", GAMEOBJECT_TEMPLATE_COLUMNS,
                     [gameobject_template_row(data["go_templates"][entry], data["go_addons"].get(entry))
                      for entry in go_entries],
                     ignore=True)

        out.write("-- ---------------------------------------------------------------------------\n")
        out.write("-- Spawn\n")
        out.write("-- ---------------------------------------------------------------------------\n\n")
        write_insert(out, "creature", CREATURE_COLUMNS,
                     [creature_row(row, CREATURE_GUID_FIRST + index)
                      for index, row in enumerate(creatures)])
        write_insert(out, "gameobject", GAMEOBJECT_COLUMNS,
                     [gameobject_row(row, GAMEOBJECT_GUID_FIRST + index)
                      for index, row in enumerate(gameobjects)])

        out.write("-- ---------------------------------------------------------------------------\n")
        out.write("-- Siapa memberi dan menutup quest zona 616\n")
        out.write("-- ---------------------------------------------------------------------------\n\n")
        for table in ("creature_queststarter", "creature_questender",
                      "gameobject_queststarter", "gameobject_questender"):
            pairs = sorted(set(data["relations"].get(table, [])), key=lambda pair: (int(pair[0]), int(pair[1])))
            write_insert(out, table, ["id", "quest"],
                         [[entry, quest] for entry, quest in pairs], ignore=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dump", required=True, type=Path,
                        help="dump world TrinityCore 4.3.4 (mysqldump .sql)")
    parser.add_argument("--out", required=True, type=Path,
                        help="file SQL yang dihasilkan")
    args = parser.parse_args(argv)

    if not args.dump.is_file():
        raise SystemExit("dump tidak ditemukan: %s" % args.dump)

    print("membaca %s ..." % args.dump, file=sys.stderr)
    data = collect(args.dump)
    print("creature %d, gameobject %d, template %d/%d"
          % (len(data["creatures"]), len(data["gameobjects"]),
             len(data["templates"]), len(data["go_templates"])), file=sys.stderr)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    generate(data, args.out, args.dump.name)
    print("ditulis: %s" % args.out, file=sys.stderr)


if __name__ == "__main__":
    main()
