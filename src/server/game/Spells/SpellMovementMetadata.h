/*
* This file is part of Project SkyFire https://www.projectskyfire.org.
* See LICENSE.md file for Copyright information
*/

#ifndef SF_SPELL_MOVEMENT_METADATA_H
#define SF_SPELL_MOVEMENT_METADATA_H

#include "Define.h"

namespace Skyfire
{
namespace Spells
{
    struct JumpDestOverride
    {
        uint32 SpellId;
        float ZOffset;
        float SpeedXY;
        float SpeedZ;
    };

    // Abilities that slide the caster along the ground under script control,
    // because the DBC effect does not move them at all (monk Roll).
    struct ScriptedDash
    {
        uint32 SpellId;
        float Distance;
        float SpeedXY;
        float SpeedZ;   // small on purpose: a flat arc reads as a slide, not a leap
    };

    enum TeleportPostEffectKind
    {
        TELEPORT_POST_EFFECT_NONE,
        TELEPORT_POST_EFFECT_EVERLOOK_RIPPER,
        TELEPORT_POST_EFFECT_TOSHLEYS_TRANSPORTER,
        TELEPORT_POST_EFFECT_AREA52_RIPPER
    };

    struct TeleportPostEffect
    {
        uint32 SpellId;
        TeleportPostEffectKind Kind;
        uint8 SuccessChancePct;
        uint8 RandomEffectCount;
    };

    JumpDestOverride const* GetJumpDestOverride(uint32 spellId);
    ScriptedDash const* GetScriptedDash(uint32 spellId);
    // Relative to the caster's own orientation: 0 forward, PI backward,
    // +PI/2 strafing left, -PI/2 strafing right. Backward wins over strafing.
    float GetScriptedDashRelativeAngle(uint32 movementFlags);
    // Spell to cast when a JUMP/JUMP_DEST spline finishes (e.g. Heroic Leap -> 52174).
    // Used when SpellEffect.TriggerSpell is 0 in DBC.
    uint32 GetJumpArrivalSpellId(uint32 spellId);
    TeleportPostEffect const* GetTeleportPostEffect(uint32 spellId);
    uint32 GetEverlookRipperPostEffectSpellId(uint32 roll);
    uint32 GetToshleysTransporterPostEffectSpellId(uint32 randomEffect, uint32 team);
    uint32 GetArea52RipperPostEffectSpellId(uint32 randomEffect, uint32 team);
    uint32 GetStuckHearthstoneCooldownSpellId();
}
}

#endif
