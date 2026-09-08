/*
* This file is part of Project SkyFire https://www.projectskyfire.org.
* See LICENSE.md file for Copyright information
*
* mod-prabowow: skip the Death Knight, Worgen and Goblin starting zones.
*
* Those three chains are too broken to play through, so a matching character is
* treated as if they had already finished one: every quest of the configured start
* zones is marked rewarded, the level the chain would have left them at is granted,
* the spells it teaches are learned, and they are moved to their faction capital
* with their hearthstone set there.
*
* Quests are found by zone rather than by a hard-coded id list, so the config keeps
* working when the world database changes: at startup every quest_template whose
* ZoneOrSort matches PraboWoW.StartZoneSkip.<Profile>.Zones is collected, minus the
* repeatable and seasonal ones.
*
* Nothing here hands out the quests' item or money rewards -- dozens of chains worth
* of loot would only fill the bags.
*
* This is temporary. PraboWoW.StartZoneSkip.Enable turns the lot off and each profile
* has its own toggle, so they can be retired one at a time as the chains get fixed.
*/

#include "PraboWoWConfig.h"

#include "DatabaseEnv.h"
#include "Log.h"
#include "MapManager.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "SpellMgr.h"
#include "World.h"

#include <algorithm>
#include <cstdlib>
#include <sstream>
#include <string>
#include <unordered_set>
#include <vector>

namespace
{
    enum Profile : uint8
    {
        PROFILE_DEATH_KNIGHT = 0,
        PROFILE_WORGEN       = 1,
        PROFILE_GOBLIN       = 2,
        PROFILE_COUNT        = 3
    };

    char const* const g_profileName[PROFILE_COUNT] = { "DeathKnight", "Worgen", "Goblin" };

    struct ProfileData
    {
        bool enabled;
        uint8 level;
        std::unordered_set<uint32> zones;   // quest_template.ZoneOrSort, also matched against GetZoneId()
        std::vector<uint32> quests;         // resolved from the zones at startup
        std::vector<uint32> spells;         // configured, existence-checked at startup

        ProfileData() : enabled(false), level(0) { }
    };

    struct Destination
    {
        bool valid;
        uint32 map;
        float x, y, z, o;
        uint32 areaId;

        Destination() : valid(false), map(0), x(0.0f), y(0.0f), z(0.0f), o(0.0f), areaId(0) { }
    };

    // OnStartup fills these once, before any player exists, and nothing writes to them
    // afterwards, so logins read them without locking.
    ProfileData g_profile[PROFILE_COUNT];
    Destination g_destination[2];           // [0] Alliance, [1] Horde
    bool g_loaded = false;

    bool Enabled()
    {
        return g_loaded && PraboWoW::GetBool("PraboWoW.StartZoneSkip.Enable", true);
    }

    std::string ProfileKey(uint8 profile, char const* setting)
    {
        std::ostringstream key;
        key << "PraboWoW.StartZoneSkip." << g_profileName[profile] << "." << setting;
        return key.str();
    }

    // "4714, 4755" -> { 4714, 4755 }. Anything that is not a positive number is dropped
    // and reported, so a typo in the config is loud instead of silently doing nothing.
    std::vector<uint32> ParseIdList(std::string const& raw, char const* what, char const* key)
    {
        std::vector<uint32> out;
        std::istringstream stream(raw);
        std::string token;

        while (std::getline(stream, token, ','))
        {
            size_t const first = token.find_first_not_of(" \t");
            if (first == std::string::npos)
                continue;

            size_t const last = token.find_last_not_of(" \t");
            token = token.substr(first, last - first + 1);

            long const value = strtol(token.c_str(), NULL, 10);
            if (value <= 0)
            {
                SF_LOG_ERROR(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: '%s' is not a valid %s id in %s; ignored.",
                    token.c_str(), what, key);
                continue;
            }

            out.push_back(uint32(value));
        }

        return out;
    }

    // "map,x,y,z,o,areaId"
    Destination ParseDestination(char const* key, char const* fallback)
    {
        Destination dest;
        std::string const raw = PraboWoW::GetString(key, fallback);

        std::istringstream stream(raw);
        std::string token;
        float parts[5] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
        uint32 areaId = 0;
        uint8 count = 0;

        while (std::getline(stream, token, ',') && count < 6)
        {
            double const value = strtod(token.c_str(), NULL);
            if (count < 5)
                parts[count] = float(value);
            else
                areaId = uint32(value);
            ++count;
        }

        if (count < 6)
        {
            SF_LOG_ERROR(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: %s needs six comma separated values (map,x,y,z,o,areaId) but got '%s'; nobody will be teleported.",
                key, raw.c_str());
            return dest;
        }

        dest.map = uint32(parts[0]);
        dest.x = parts[1];
        dest.y = parts[2];
        dest.z = parts[3];
        dest.o = parts[4];
        dest.areaId = areaId;

        if (!MapManager::IsValidMapCoord(dest.map, dest.x, dest.y, dest.z, dest.o))
        {
            SF_LOG_ERROR(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: %s = '%s' is not a valid map coordinate; nobody will be teleported.",
                key, raw.c_str());
            return dest;
        }

        dest.valid = true;
        return dest;
    }

    void LoadProfile(uint8 profile, uint8 levelDefault, char const* zonesDefault, char const* spellsDefault)
    {
        ProfileData& data = g_profile[profile];

        data.enabled = PraboWoW::GetBool(ProfileKey(profile, "Enable").c_str(), true);
        if (!data.enabled)
        {
            SF_LOG_INFO(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: %s disabled.", g_profileName[profile]);
            return;
        }

        // Never past the realm cap: MaxPlayerLevel is what the client and the XP tables
        // are built for, and GiveLevel above it corrupts the character.
        int32 const maxLevel = int32(sWorld->getIntConfig(WorldIntConfigs::CONFIG_MAX_PLAYER_LEVEL));
        int32 const level = PraboWoW::GetInt(ProfileKey(profile, "Level").c_str(), levelDefault);
        data.level = uint8(std::clamp<int32>(level, 0, maxLevel));

        std::string const zonesKey = ProfileKey(profile, "Zones");
        std::vector<uint32> const zones = ParseIdList(PraboWoW::GetString(zonesKey.c_str(), zonesDefault), "zone", zonesKey.c_str());
        data.zones.insert(zones.begin(), zones.end());

        // Sweep the whole zone rather than one chain: these zones are being written off,
        // so their side quests count as skipped too.
        for (auto const& pair : sObjectMgr->GetQuestTemplates())
        {
            Quest const* quest = pair.second;
            if (!quest || quest->IsRepeatable() || quest->IsDailyOrWeekly() || quest->IsSeasonal())
                continue;

            int32 const sort = quest->GetZoneOrSort();
            if (sort > 0 && data.zones.find(uint32(sort)) != data.zones.end())
                data.quests.push_back(quest->GetQuestId());
        }

        std::string const spellsKey = ProfileKey(profile, "Spells");
        for (uint32 spellId : ParseIdList(PraboWoW::GetString(spellsKey.c_str(), spellsDefault), "spell", spellsKey.c_str()))
        {
            if (!sSpellMgr->GetSpellInfo(spellId))
            {
                SF_LOG_ERROR(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: spell %u in %s does not exist; skipped.", spellId, spellsKey.c_str());
                continue;
            }

            data.spells.push_back(spellId);
        }

        if (data.quests.empty())
            SF_LOG_ERROR(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: %s is enabled but %s matched no quest at all -- check the zone ids against quest_template.ZoneOrSort.",
                g_profileName[profile], zonesKey.c_str());

        SF_LOG_INFO(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: %s enabled -- %u zone(s), %u quest(s) marked rewarded, %u spell(s) taught, level %u.",
            g_profileName[profile], uint32(data.zones.size()), uint32(data.quests.size()), uint32(data.spells.size()), uint32(data.level));
    }

    // A Worgen or Goblin Death Knight matches two profiles. The class profile owns the
    // quest sweep, the level and the teleport -- a Worgen DK started in Ebon Hold, never
    // in Gilneas -- but the race profile still has racials worth handing over, so its
    // spell list is applied on top.
    bool GetProfile(Player const* player, uint8& primary, uint8& extraSpells)
    {
        extraSpells = PROFILE_COUNT;

        uint8 racial = PROFILE_COUNT;
        switch (player->getRace())
        {
            case RACE_WORGEN: racial = PROFILE_WORGEN; break;
            case RACE_GOBLIN: racial = PROFILE_GOBLIN; break;
            default: break;
        }

        if (player->getClass() == CLASS_DEATH_KNIGHT)
        {
            if (!g_profile[PROFILE_DEATH_KNIGHT].enabled)
                return false;

            primary = PROFILE_DEATH_KNIGHT;
            if (racial != PROFILE_COUNT && g_profile[racial].enabled)
                extraSpells = racial;
            return true;
        }

        if (racial == PROFILE_COUNT || !g_profile[racial].enabled)
            return false;

        primary = racial;
        return true;
    }

    bool AlreadyApplied(uint32 guidLow)
    {
        QueryResult result = CharacterDatabase.PQuery("SELECT 1 FROM character_startzone_skip WHERE guid = %u", guidLow);
        return bool(result);
    }

    void TeachSpells(Player* player, ProfileData const& data, uint32& taught)
    {
        for (uint32 spellId : data.spells)
        {
            if (player->HasSpell(spellId))
                continue;

            player->learnSpell(spellId, false);
            ++taught;
        }
    }
}

class prabowow_startzone_skip_world : public WorldScript
{
public:
    prabowow_startzone_skip_world() : WorldScript("prabowow_startzone_skip_world") { }

    // Quest templates are loaded by the time the world is up, so the zone sweep runs
    // here once instead of on every login.
    void OnStartup() override
    {
        if (!PraboWoW::GetBool("PraboWoW.StartZoneSkip.Enable", true))
        {
            SF_LOG_INFO(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip disabled.");
            return;
        }

        LoadProfile(PROFILE_DEATH_KNIGHT, 58, "4298", "53428,50977,48778");
        LoadProfile(PROFILE_WORGEN, 12, "4714,4755", "68996,87840,68992,68975,68976,68978");
        LoadProfile(PROFILE_GOBLIN, 12, "4737,4720", "69070,69041,69045,69044,69043,69046");

        g_destination[0] = ParseDestination("PraboWoW.StartZoneSkip.Alliance.Destination", "0,-8842.09,626.96,94.14,3.66,1519");
        g_destination[1] = ParseDestination("PraboWoW.StartZoneSkip.Horde.Destination", "1,1629.36,-4373.39,31.27,0.09,1637");

        g_loaded = true;
    }
};

class prabowow_startzone_skip : public PlayerScript
{
public:
    prabowow_startzone_skip() : PlayerScript("prabowow_startzone_skip") { }

    // OnPlayerLogin fires at the very end of HandlePlayerLogin, after the player is in
    // the map and m_playerLoading is cleared, so the zone is known and a far teleport
    // behaves like any other.
    void OnLogin(Player* player, bool firstLogin) override
    {
        if (!Enabled())
            return;

        uint8 primary = PROFILE_COUNT;
        uint8 extraSpells = PROFILE_COUNT;
        if (!GetProfile(player, primary, extraSpells))
            return;

        uint32 const guidLow = player->GetGUIDLow();
        if (AlreadyApplied(guidLow))
            return;

        ProfileData const& data = g_profile[primary];

        for (uint32 questId : data.quests)
            player->AddRewardedQuest(questId);

        // Raise only. Someone who did the chain for real before this feature existed must
        // not be knocked back down to the profile level.
        bool levelled = false;
        if (data.level && player->getLevel() < data.level)
        {
            player->GiveLevel(data.level);
            player->SetUInt32Value(PLAYER_FIELD_XP, 0);
            levelled = true;
        }

        uint32 taught = 0;
        TeachSpells(player, data, taught);
        if (extraSpells != PROFILE_COUNT)
            TeachSpells(player, g_profile[extraSpells], taught);

        // Only move players who are actually still in the start zone. Someone who got out
        // on their own -- or finished the chain back when it worked -- keeps their spot.
        bool const inStartZone = firstLogin || data.zones.find(player->GetZoneId()) != data.zones.end();
        bool teleported = false;
        if (inStartZone)
        {
            Destination const& dest = g_destination[player->GetTeam() == ALLIANCE ? 0 : 1];
            if (dest.valid)
            {
                // Ebon Hold, Gilneas and Kezan drop new characters into zone phases, and
                // UpdateAreaPhase only ever removes phases declared for the area the player
                // is standing in -- one set by a script back there would follow them out and
                // leave the capital looking empty. Drop the lot before moving; arriving runs
                // UpdateAreaPhase again and re-applies whatever the destination declares.
                player->ClearPhases(false);
                player->UpdatePhasing();

                player->SetHomebind(WorldLocation(dest.map, dest.x, dest.y, dest.z, dest.o), dest.areaId);
                teleported = player->TeleportTo(dest.map, dest.x, dest.y, dest.z, dest.o);
                if (!teleported)
                    SF_LOG_ERROR(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: could not teleport %s (guid %u) to map %u; they are still in the start zone.",
                        player->GetName().c_str(), guidLow, dest.map);
            }
        }

        // Leaving someone in a start zone we meant to lift them out of -- a bad destination
        // in the config, say -- must not be recorded as done, or fixing the config would
        // never reach them. Everything above is idempotent, so retrying next login is safe.
        if (!inStartZone || teleported)
            CharacterDatabase.PExecute("INSERT INTO character_startzone_skip (guid, profile) VALUES (%u, %u) ON DUPLICATE KEY UPDATE profile = VALUES(profile)",
                guidLow, uint32(primary));

        SF_LOG_INFO(PraboWoW::LOG, "[mod-prabowow] StartZoneSkip: %s applied to %s (guid %u) -- %u quest(s) rewarded, %u spell(s) taught, now level %u (%s), %s.",
            g_profileName[primary], player->GetName().c_str(), guidLow, uint32(data.quests.size()), taught,
            uint32(player->getLevel()), levelled ? "raised" : "unchanged",
            teleported ? "teleported" : "left in place");
    }
};

void AddSC_prabowow_startzone_skip()
{
    new prabowow_startzone_skip_world();
    new prabowow_startzone_skip();
}
