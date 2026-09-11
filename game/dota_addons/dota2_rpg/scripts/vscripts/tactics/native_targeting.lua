-- Native CUSTOM masks describe a skill-owned filter, not a generic UnitFilter
-- team/type. Keep reviewed fallbacks shared by selection and order validation.
local Context = require("tactics/condition_context")
local NativeTargeting = {}

function NativeTargeting.IsPhantomStrike(ability)
    return Context.Call(ability, "GetAbilityName") == "phantom_assassin_phantom_strike"
end

function NativeTargeting.ResolveMasks(ability, team, types)
    if NativeTargeting.IsPhantomStrike(ability)
        or Context.Call(ability, "GetAbilityName") == "tiny_toss"
        or Context.Call(ability, "GetAbilityName") == "undying_soul_rip"
        or Context.Call(ability, "GetAbilityName") == "item_cyclone"
        or Context.Call(ability, "GetAbilityName") == "item_wind_waker" then
        -- Reviewed CUSTOM skills accept allied/enemy heroes and basic units.
        -- Toss landing targets are independent of its nearest grabbed unit.
        -- Soul Rip includes self healing; special Tombstone targeting is not
        -- covered by these ordinary unit masks.
        -- Cyclone items additionally restrict friendly targets in RejectsTarget.
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

function NativeTargeting.RejectsAllies(ability)
    return Context.Call(ability, "GetAbilityName") == "item_cyclone"
end

function NativeTargeting.RejectsTarget(ability, caster, target)
    if NativeTargeting.RejectsSelf(ability, caster, target) then return true end
    local name = Context.Call(ability, "GetAbilityName")
    if name ~= "item_cyclone" and name ~= "item_wind_waker" then return false end
    if caster == target then return false end
    local casterTeam = Context.Call(caster, "GetTeamNumber")
    local targetTeam = Context.Call(target, "GetTeamNumber")
    -- Valve handles may expose no CastFilterResultTarget. Fail closed if the
    -- friendly restriction cannot be verified, even with translated masks.
    if casterTeam == nil or targetTeam == nil then return true end
    if casterTeam ~= targetTeam then return false end
    if NativeTargeting.RejectsAllies(ability) then return true end
    -- Wind Waker permits allied heroes; friendly basics remain conservative.
    return Context.Call(target, "IsHero") ~= true
end

return NativeTargeting
