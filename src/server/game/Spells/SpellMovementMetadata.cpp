/*
* This file is part of Project SkyFire https://www.projectskyfire.org.
* See LICENSE.md file for Copyright information
*/

#include "SpellMovementMetadata.h"
#include "SharedDefines.h"

namespace Skyfire
{
namespace Spells
{
    namespace
    {
        JumpDestOverride const JumpDestOverrides[] =
        {
            { 108938, 10.0f, 20.0f, 20.0f },
            // Heroic Leap: keep a clear arc, but faster than the generic run-speed jump formula.
            { 6544, 0.0f, 48.0f, 16.0f }
        };

        // Monk Roll carries no movement effect this core acts on, so its travel
        // is driven from the spell script instead. 15 yards is the MoP 5.4.8
        // range; SpeedZ stays near zero because this is a ground slide, not a
        // jump.
        //
        // Chi Torpedo (115008 / 121828) has the same shape - its script moves
        // nothing either - but it is deliberately not listed here until it has
        // been confirmed broken in game. Listing a spell that already travels
        // would move the caster twice.
        ScriptedDash const ScriptedDashes[] =
        {
            { 109132, 15.0f, 25.0f, 1.0f } // Roll
        };

        // Mirrors MovementFlags in Entities/Unit/Unit.h:720-726. Copied rather
        // than included so this file stays free of the entity headers and can be
        // unit tested on its own.
        uint32 const DashMovementFlagBackward = 0x00000002;
        uint32 const DashMovementFlagStrafeLeft = 0x00000004;
        uint32 const DashMovementFlagStrafeRight = 0x00000008;

        float const DashPi = 3.14159265358979323846f;

        struct JumpArrivalSpell
        {
            uint32 SpellId;
            uint32 ArrivalSpellId;
        };

        JumpArrivalSpell const JumpArrivalSpells[] =
        {
            { 6544, 52174 } // Heroic Leap -> Heroic Leap (damage)
        };

        TeleportPostEffect const TeleportPostEffects[] =
        {
            { 23442, TELEPORT_POST_EFFECT_EVERLOOK_RIPPER,          0, 119 },
            { 36941, TELEPORT_POST_EFFECT_TOSHLEYS_TRANSPORTER,    50,   7 },
            { 36890, TELEPORT_POST_EFFECT_AREA52_RIPPER,           50,   4 }
        };

        uint32 GetTeamTransformSpellId(uint32 team)
        {
            return team == ALLIANCE ? 36897 : 36899;
        }
    }

    JumpDestOverride const* GetJumpDestOverride(uint32 spellId)
    {
        for (JumpDestOverride const& jumpDestOverride : JumpDestOverrides)
            if (jumpDestOverride.SpellId == spellId)
                return &jumpDestOverride;

        return nullptr;
    }

    ScriptedDash const* GetScriptedDash(uint32 spellId)
    {
        for (ScriptedDash const& scriptedDash : ScriptedDashes)
            if (scriptedDash.SpellId == spellId)
                return &scriptedDash;

        return nullptr;
    }

    float GetScriptedDashRelativeAngle(uint32 movementFlags)
    {
        // Holding back beats strafing: that is what the client shows when both
        // keys are down, and it keeps diagonal input from rolling sideways.
        if (movementFlags & DashMovementFlagBackward)
            return DashPi;

        if (movementFlags & DashMovementFlagStrafeLeft)
            return DashPi / 2.0f;

        if (movementFlags & DashMovementFlagStrafeRight)
            return -DashPi / 2.0f;

        return 0.0f;
    }

    uint32 GetJumpArrivalSpellId(uint32 spellId)
    {
        for (JumpArrivalSpell const& jumpArrival : JumpArrivalSpells)
            if (jumpArrival.SpellId == spellId)
                return jumpArrival.ArrivalSpellId;

        return 0;
    }

    TeleportPostEffect const* GetTeleportPostEffect(uint32 spellId)
    {
        for (TeleportPostEffect const& teleportPostEffect : TeleportPostEffects)
            if (teleportPostEffect.SpellId == spellId)
                return &teleportPostEffect;

        return nullptr;
    }

    uint32 GetEverlookRipperPostEffectSpellId(uint32 roll)
    {
        if (roll < 70)
            return 0;

        if (roll < 100)
            return 23445;

        return 23449;
    }

    uint32 GetToshleysTransporterPostEffectSpellId(uint32 randomEffect, uint32 team)
    {
        switch (randomEffect)
        {
            case 1:
                return 36900;
            case 2:
                return 36901;
            case 3:
                return 36895;
            case 4:
                return 36893;
            case 5:
                return GetTeamTransformSpellId(team);
            case 6:
                return 36940;
            case 7:
                return 23445;
            default:
                break;
        }

        return 0;
    }

    uint32 GetArea52RipperPostEffectSpellId(uint32 randomEffect, uint32 team)
    {
        switch (randomEffect)
        {
            case 1:
                return 36900;
            case 2:
                return 36901;
            case 3:
                return 36895;
            case 4:
                return GetTeamTransformSpellId(team);
            default:
                break;
        }

        return 0;
    }

    uint32 GetStuckHearthstoneCooldownSpellId()
    {
        return 8690;
    }
}
}
