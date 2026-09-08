/*
* This file is part of Project SkyFire https://www.projectskyfire.org.
* See LICENSE.md file for Copyright information
*/

#ifndef SKYFIRE_CREATURE_BASE_HEALTH_SELECTION_H
#define SKYFIRE_CREATURE_BASE_HEALTH_SELECTION_H

#include "Define.h"

namespace Skyfire
{
namespace Creatures
{
    // The last level each expansion's content reached: its level cap plus the
    // three levels raid bosses sat above it.
    inline constexpr uint32 EXPANSION_LEVEL_CEILING[] = { 63, 73, 83, 88, 95 };
    inline constexpr uint32 EXPANSION_COUNT = sizeof(EXPANSION_LEVEL_CEILING) / sizeof(EXPANSION_LEVEL_CEILING[0]);

    // creature_classlevelstats carries one health curve per expansion, basehp0
    // through basehp4, and creature_template.exp says which content a creature
    // belongs to. A 5.4.8 client shows a Northrend mob the Northrend curve --
    // old content was never rescaled onto the Pandaria one -- so the expansion
    // picks the column. Reading basehp4 for everything instead leaves a level
    // 76 Borean Tundra mob on 28286 health where the client expects 11001.
    //
    // Two things stop the expansion from being taken at face value.
    //
    // A creature above its expansion's ceiling was re-levelled by later
    // content and never had its tag updated: city guards bumped to level 90
    // still carry exp 1 or 2. Their tag no longer says anything about the
    // curve the client expects, so they stay on the current-content one -- a
    // level 90 guard reads 393941, not the 17672 the Outland curve happens to
    // hold that far past its own content.
    //
    // And not every (level, expansion) pair exists. The table only carries a
    // curve where that expansion actually had creatures at that level, and the
    // rest hold the 1 placeholder: there is no basehp3 for levels 74, 75, 78
    // and 79, and no basehp0 for levels 86 and 87. Those fall back to basehp4,
    // the one column filled in for every level.
    //
    // Both fallbacks land on what the creature already resolved to before the
    // expansion picked a column, so they cannot make anything heavier than it
    // is today.
    inline uint32 SelectBaseHealth(uint32 const* baseHealth, uint32 columnCount, uint32 expansion, uint32 level, uint32 currentContentExpansion)
    {
        if (columnCount > EXPANSION_COUNT)
            columnCount = EXPANSION_COUNT;

        if (expansion >= columnCount || level > EXPANSION_LEVEL_CEILING[expansion])
            expansion = currentContentExpansion;

        uint32 health = baseHealth[expansion];
        if (health <= 1)
            health = baseHealth[currentContentExpansion];

        return health;
    }
}
}

#endif
