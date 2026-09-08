/*
* This file is part of Project SkyFire https://www.projectskyfire.org.
* See LICENSE.md file for Copyright information
*/

#include "CreatureBaseHealthSelection.h"

#include <iostream>

namespace
{
    uint32 const MAX_BASE_HP = 5;
    uint32 const CURRENT_EXP = 4;

    bool Expect(bool condition, char const* message)
    {
        if (!condition)
            std::cerr << message << '\n';

        return condition;
    }

    uint32 Select(uint32 const (&baseHealth)[MAX_BASE_HP], uint32 expansion, uint32 level)
    {
        return Skyfire::Creatures::SelectBaseHealth(baseHealth, MAX_BASE_HP, expansion, level, CURRENT_EXP);
    }

    // Rows straight out of creature_classlevelstats, class 1 unless noted.
    uint32 const LEVEL_10[MAX_BASE_HP] = { 198, 1, 1, 1, 396 };
    uint32 const LEVEL_74[MAX_BASE_HP] = { 4524, 7804, 10282, 1, 19298 };
    uint32 const LEVEL_76[MAX_BASE_HP] = { 4781, 8247, 11001, 22002, 28286 };
    uint32 const LEVEL_90[MAX_BASE_HP] = { 1, 17672, 17672, 107596, 393941 };
    uint32 const LEVEL_3_CLASS_2[MAX_BASE_HP] = { 69, 1, 1, 1, 142 };

    // Stranded Thresher (entry 28010) is a level 75-76 Borean Tundra beast with
    // exp 2 and Health_mod 1. The client shows it around 11k, not the 28k the
    // Pandaria curve carries at that level.
    bool TestWrathCreatureUsesTheWrathCurve()
    {
        return Expect(Select(LEVEL_76, 2, 76) == 11001,
            "A level 76 Wrath creature should read basehp2, not the current-content curve");
    }

    bool TestClassicCreatureUsesTheClassicCurve()
    {
        return Expect(Select(LEVEL_10, 0, 10) == 198,
            "A level 10 classic creature should read basehp0");
    }

    bool TestPandariaCreatureKeepsTheCurrentCurve()
    {
        return Expect(Select(LEVEL_76, 4, 76) == 28286,
            "A Pandaria creature should still read basehp4");
    }

    // Northshire Guard is level 90 but still tagged exp 2, like every other
    // capital guard that was re-levelled without its expansion being updated.
    // basehp2 is filled in that far up the table (17672), so nothing but the
    // ceiling stops a guard from reading a curve meant for level 80 content.
    bool TestCreatureAboveItsExpansionCeilingKeepsTheCurrentCurve()
    {
        bool passed = Expect(Select(LEVEL_90, 2, 90) == 393941,
            "A level 90 creature tagged as Wrath content is past that ceiling and should read basehp4");
        passed &= Expect(Select(LEVEL_90, 1, 90) == 393941,
            "A level 90 creature tagged as Outland content should read basehp4");
        passed &= Expect(Select(LEVEL_76, 0, 76) == 28286,
            "A level 76 creature tagged as classic content should read basehp4");
        return passed;
    }

    // A raid boss sits three levels above its expansion's cap and is still that
    // expansion's content.
    bool TestBossAtTheCeilingKeepsItsOwnCurve()
    {
        return Expect(Select(LEVEL_76, 2, 76) == 11001 && Select(LEVEL_74, 2, 74) == 10282,
            "Levels within the expansion ceiling should keep that expansion's curve");
    }

    // creature_classlevelstats has no basehp3 for levels 74, 75, 78 and 79.
    bool TestEmptyColumnFallsBackToCurrentContent()
    {
        return Expect(Select(LEVEL_74, 3, 74) == 19298,
            "A level with no curve for its expansion should fall back to basehp4");
    }

    // Faction leaders sit at level 3 tagged as Cataclysm content.
    bool TestExpansionFarBelowItsLevelFallsBack()
    {
        return Expect(Select(LEVEL_3_CLASS_2, 3, 3) == 142,
            "A level 3 creature tagged as Cataclysm content should fall back to basehp4");
    }

    // creature_template.exp is validated on load, but the helper is the only
    // thing standing between a bad row and a read past the end of the array.
    bool TestExpansionOutOfRangeFallsBack()
    {
        return Expect(Select(LEVEL_76, 9, 76) == 28286,
            "An expansion outside the table should fall back to basehp4 instead of reading past the row");
    }

    // Neither fallback may hand back more health than the creature already had.
    bool TestSelectionNeverRaisesHealth()
    {
        bool passed = true;
        uint32 const* const rows[] = { LEVEL_10, LEVEL_74, LEVEL_76, LEVEL_90, LEVEL_3_CLASS_2 };
        uint32 const levels[] = { 10, 74, 76, 90, 3 };

        for (uint32 i = 0; i < sizeof(rows) / sizeof(rows[0]); ++i)
            for (uint32 exp = 0; exp < MAX_BASE_HP; ++exp)
            {
                uint32 const health = Skyfire::Creatures::SelectBaseHealth(rows[i], MAX_BASE_HP, exp,
                    levels[i], CURRENT_EXP);

                passed &= Expect(health <= rows[i][CURRENT_EXP],
                    "Selecting a curve should never return more health than the current-content column");
            }

        return passed;
    }
}

int main()
{
    bool passed = true;

    passed &= TestWrathCreatureUsesTheWrathCurve();
    passed &= TestClassicCreatureUsesTheClassicCurve();
    passed &= TestPandariaCreatureKeepsTheCurrentCurve();
    passed &= TestCreatureAboveItsExpansionCeilingKeepsTheCurrentCurve();
    passed &= TestBossAtTheCeilingKeepsItsOwnCurve();
    passed &= TestEmptyColumnFallsBackToCurrentContent();
    passed &= TestExpansionFarBelowItsLevelFallsBack();
    passed &= TestExpansionOutOfRangeFallsBack();
    passed &= TestSelectionNeverRaisesHealth();

    return passed ? 0 : 1;
}
