-- Native CUSTOM masks describe a skill-owned filter, not a generic UnitFilter
-- team/type. Keep reviewed fallbacks shared by selection and order validation.
local Context = require("tactics/condition_context")
local NativeTargeting = {}

function NativeTargeting.IsPhantomStrike(ability)
    return Context.Call(ability, "GetAbilityName") == "phantom_assassin_phantom_strike"
end

function NativeTargeting.ResolveMasks(ability, team, types)
    if NativeTargeting.IsPhantomStrike(ability)
        or Context.Call(ability, "GetAbilityName") == "tiny_toss" then
        -- Reviewed CUSTOM skills accept allied/enemy heroes and basic units.
        -- Toss landing targets are independent of its nearest grabbed unit.
        -- Translate only CUSTOM fields; retain ordinary masks and native flags.
        if team == (DOTA_UNIT_TARGET_TEAM_CUSTOM or 4) then
            team = DOTA_UNIT_TARGET_TEAM_BOTH or 3
        end
        if types == (DOTA_UNIT_TARGET_CUSTOM or 128) then
            types = (DOTA_UNIT_TARGET_HERO or 1) + (DOTA_UNIT_TARGET_BASIC or 2)
        end
    end
    return team, types
end

function NativeTargeting.RejectsSelf(ability, caster, target)
    return caster == target and NativeTargeting.IsPhantomStrike(ability)
end

return NativeTargeting
