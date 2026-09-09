/*
* This file is part of Project SkyFire https://www.projectskyfire.org.
* See LICENSE.md file for Copyright information
*/

#ifndef SKYFIRE_PET_SPECIALIZATION_SUPPORT_H
#define SKYFIRE_PET_SPECIALIZATION_SUPPORT_H

#include "Define.h"

namespace Skyfire
{
namespace Pets
{
    // The ChrSpecialization.dbc columns the pet code reads. Pet specializations are
    // the rows that belong to no class -- ClassId 0 -- and PetTalentType carries the
    // talent tab the client asks for: 0 Ferocity, 1 Tenacity, 2 Cunning. Player
    // specializations sit in the same file with a real ClassId and PetTalentType -1.
    struct SpecializationRow
    {
        uint32 Id;
        uint32 ClassId;
        int32 PetTalentType;
    };

    int32 const PET_TALENT_TYPE_NONE = -1;

    inline bool IsPetSpecialization(SpecializationRow const& row)
    {
        return row.ClassId == 0 && row.PetTalentType != PET_TALENT_TYPE_NONE;
    }

    // CMSG_SET_PET_TALENT_TREE carries the tab, not the specialization id, so the tab
    // has to be mapped back onto the row holding it. Returns 0 when no pet
    // specialization carries that tab; the caller must treat that as a rejected
    // request and leave the pet on the specialization it already has.
    //
    // Nothing here may look at the pet's current specialization. An older workaround
    // skipped the row the pet already had, which turned re-picking the current
    // specialization into a 0 and made Pet::SetSpec wipe it instead.
    inline uint32 ResolvePetSpecializationByTalentTab(SpecializationRow const* rows, uint32 rowCount, int32 talentTab)
    {
        if (!rows || talentTab == PET_TALENT_TYPE_NONE)
            return 0;

        for (uint32 i = 0; i < rowCount; ++i)
            if (IsPetSpecialization(rows[i]) && rows[i].PetTalentType == talentTab)
                return rows[i].Id;

        return 0;
    }
}
}

#endif
