# mod-prabowow

Quality-of-life features for every player on PraboWoW Pandaria (SkyFire 5.4.8).
Compiled into the worldserver through the module system in `modules/`.

| Feature | How | Config keys |
|---|---|---|
| Per-character XP rate | `.xp` shows the current multiplier, `.xp rate <1-5>` changes it. Applied in `OnGiveXP` on top of `Rate.XP.*`, stored in `characters.character_xp_rate`. | `PraboWoW.XpRate.Max` |
| Realm-wide chat | `.chat <message>` broadcasts a system message to everyone online, both factions. Respects mutes, a minimum level and a per-player cooldown; `\|` is escaped so nobody can forge links. | `PraboWoW.WorldChat.*` |
| Auto-sell grey loot | Poor-quality items are sold the moment they are looted (only the looted count, greys already in the bags are kept). | `PraboWoW.AutoSellGrey.Enable` |
| All flight paths | Every taxi node of the player's faction is marked known on each login, and again on the next zone change for a Pandaren, who only gets a faction partway through their first session. | `PraboWoW.AllFlightPaths.Enable` |
| Heirloom vendor | NPC 900001 spawned at every distinct `playercreateinfo` start position, visible in every phase. Its list is built at startup from heirloom-quality **equipment** in `Item-sparse.db2` (weapons and armour with a real equip slot; honour tokens, profession items and placeholders are skipped). Price is forced to a flat gold amount, and SellPrice is zeroed so a free heirloom cannot be resold for gold. | `PraboWoW.HeirloomVendor.*` |
| Starter mail | Every new character receives item 23162 (36-slot bag) by mail. | `PraboWoW.StarterMail.*` |
| Skip broken starting zones | **Temporary.** Death Knights, Worgen and Goblins are treated as having finished their starting chain: every quest of the configured zones is marked rewarded, they are raised to the level the chain would have left them at (58/12/12), taught their racials and the spells the chain grants, and moved to Stormwind or Orgrimmar with their hearthstone set there. Runs once per character, tracked in `characters.character_startzone_skip`. Retire each profile as its chain gets fixed. | `PraboWoW.StartZoneSkip.*` |

See [conf/prabowow.conf.dist](conf/prabowow.conf.dist) for every key and its
default. The core does not load module `.conf` files itself; put the keys into
`worldserver.conf` (PraboWoW deployment: `config/worldserver.overrides.conf`).

## Core changes this module relies on

Three small additions to the core, all kept generic:

* `PlayerScript::OnLootItem(Player*, Item*, uint32 count, uint64 lootGuid)` —
  fired from `Player::StoreLootItem` after the item is in the bags. Used by the
  auto-sell script.
* `CREATURE_FLAG_EXTRA_ALL_PHASES` (`creature_template.flags_extra` 0x200000) —
  `WorldObject::IsPhased` treats such creatures as visible in every phase. Needed
  because Kezan, Gilneas, the Wandering Isle and Ebon Hold put brand-new
  characters into zone phases that a plain spawn would never share.
* `Player::AddRewardedQuest(uint32)` — the counterpart of the existing
  `RemoveRewardedQuest`. `RewardQuest()` is otherwise the only writer of the
  rewarded set and it also hands out XP, money and items; the starting-zone skip
  needs a quest to count as done without any of that.

## SQL

Applied automatically by `DatabaseSetup` once promoted from `sql/pending_updates/`:

| Database | File | Purpose |
|---|---|---|
| auth | `prabowow_player_commands.sql` | RBAC permissions 1100-1102 linked to role 199 (Player Commands) |
| characters | `prabowow_xp_rate.sql` | `character_xp_rate` table |
| world | `prabowow_heirloom_vendor.sql` | vendor `creature_template` 900001 + one spawn per start position |
| characters | `prabowow_startzone_skip.sql` | `character_startzone_skip` table (one row = skip already applied) |

RBAC ids are also hard-coded in `src/PraboWoWConfig.h`; keep both in sync.
