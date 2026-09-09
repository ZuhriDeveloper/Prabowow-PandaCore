/*
* This file is part of Project SkyFire https://www.projectskyfire.org.
* See LICENSE.md file for Copyright information
*/

#include "PetSpecializationSupport.h"

#include <iostream>

namespace
{
    using Skyfire::Pets::SpecializationRow;
    using Skyfire::Pets::PET_TALENT_TYPE_NONE;

    bool Expect(bool condition, char const* message)
    {
        if (!condition)
            std::cerr << message << '\n';

        return condition;
    }

    // Shaped like ChrSpecialization.dbc: the three ClassId 0 rows are the pet
    // specializations, one per talent tab, and every player specialization sits in the
    // same file with a real ClassId and no pet talent tab. The ids stand in for the
    // real rows -- what is being tested is which row a tab picks out.
    uint32 const SPEC_FOR_TAB_0 = 74;
    uint32 const SPEC_FOR_TAB_1 = 79;
    uint32 const SPEC_FOR_TAB_2 = 81;

    uint32 const HUNTER_CLASS_ID = 3;
    uint32 const DEATH_KNIGHT_CLASS_ID = 6;
    uint32 const MAGE_CLASS_ID = 8;

    SpecializationRow const STORE[] =
    {
        { 62,             MAGE_CLASS_ID,   PET_TALENT_TYPE_NONE },
        { SPEC_FOR_TAB_0, 0,               0 },
        { 253,            HUNTER_CLASS_ID, PET_TALENT_TYPE_NONE },
        { SPEC_FOR_TAB_1, 0,               1 },
        { SPEC_FOR_TAB_2, 0,               2 }
    };

    uint32 const STORE_SIZE = sizeof(STORE) / sizeof(STORE[0]);

    uint32 Resolve(int32 talentTab)
    {
        return Skyfire::Pets::ResolvePetSpecializationByTalentTab(STORE, STORE_SIZE, talentTab);
    }

    bool TestEachTabResolvesToItsOwnSpecialization()
    {
        bool passed = true;
        passed &= Expect(Resolve(0) == SPEC_FOR_TAB_0, "Talent tab 0 should resolve to the pet specialization carrying it");
        passed &= Expect(Resolve(1) == SPEC_FOR_TAB_1, "Talent tab 1 should resolve to the pet specialization carrying it");
        passed &= Expect(Resolve(2) == SPEC_FOR_TAB_2, "Talent tab 2 should resolve to the pet specialization carrying it");
        return passed;
    }

    // Regression: an older workaround skipped the row the pet already had, so asking
    // for the specialization the pet was already on returned 0, and the caller then
    // wiped the specialization instead of leaving it alone.
    bool TestResolvingTheSameTabTwiceIsStable()
    {
        return Expect(Resolve(1) == Resolve(1) && Resolve(1) == SPEC_FOR_TAB_1,
            "Re-picking a specialization the pet already has should resolve to that same specialization");
    }

    bool TestPlayerSpecializationsAreNeverReturned()
    {
        SpecializationRow const playerRows[] =
        {
            { 250, DEATH_KNIGHT_CLASS_ID, 1 },  // a class row that happens to carry a pet tab value
            { 251, DEATH_KNIGHT_CLASS_ID, PET_TALENT_TYPE_NONE }
        };

        return Expect(Skyfire::Pets::ResolvePetSpecializationByTalentTab(playerRows, 2, 1) == 0,
            "A specialization belonging to a class is not a pet specialization, whatever tab it carries");
    }

    bool TestUnknownTabResolvesToNothing()
    {
        bool passed = true;
        passed &= Expect(Resolve(3) == 0, "A tab no pet specialization carries should resolve to nothing");
        passed &= Expect(Resolve(PET_TALENT_TYPE_NONE) == 0, "The absent tab should resolve to nothing");
        passed &= Expect(Resolve(-2) == 0, "A negative tab should resolve to nothing");
        return passed;
    }

    bool TestEmptyStoreResolvesToNothing()
    {
        bool passed = true;
        passed &= Expect(Skyfire::Pets::ResolvePetSpecializationByTalentTab(STORE, 0, 0) == 0,
            "An empty specialization store should resolve to nothing");
        passed &= Expect(Skyfire::Pets::ResolvePetSpecializationByTalentTab(NULL, STORE_SIZE, 0) == 0,
            "A missing specialization store should resolve to nothing");
        return passed;
    }

    bool TestOnlyClasslessRowsWithATabArePetSpecializations()
    {
        bool passed = true;
        SpecializationRow const petRow = { SPEC_FOR_TAB_0, 0, 0 };
        SpecializationRow const classRow = { 253, HUNTER_CLASS_ID, PET_TALENT_TYPE_NONE };
        SpecializationRow const classlessWithoutTab = { 1, 0, PET_TALENT_TYPE_NONE };

        passed &= Expect(Skyfire::Pets::IsPetSpecialization(petRow), "A classless row carrying a tab is a pet specialization");
        passed &= Expect(!Skyfire::Pets::IsPetSpecialization(classRow), "A row belonging to a class is not a pet specialization");
        passed &= Expect(!Skyfire::Pets::IsPetSpecialization(classlessWithoutTab), "A classless row without a tab is not a pet specialization");
        return passed;
    }
}

int main()
{
    bool passed = true;

    passed &= TestEachTabResolvesToItsOwnSpecialization();
    passed &= TestResolvingTheSameTabTwiceIsStable();
    passed &= TestPlayerSpecializationsAreNeverReturned();
    passed &= TestUnknownTabResolvesToNothing();
    passed &= TestEmptyStoreResolvesToNothing();
    passed &= TestOnlyClasslessRowsWithATabArePetSpecializations();

    return passed ? 0 : 1;
}
