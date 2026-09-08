local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Adapter = require("tactics/action_adapter")
DOTA_ABILITY_BEHAVIOR_POINT = 16
bit = { band = function(value, flag) return value == flag and flag or 0 end }
local vectorMeta = { __sub = function(a, b)
    return { Length2D = function() return math.abs(a.x - b.x) end }
end }
local origin = setmetatable({ x = 0 }, vectorMeta)
local point = { x = 600 }
local caster = {
    GetAbsOrigin = function() return origin end,
    IsAlive = function() return true end,
    entindex = function() return 1 end,
}
local chargeCount, maxCharges, cooldown, castable = 1, 3, false, true
local source = {
    GetBehaviorInt = function() return DOTA_ABILITY_BEHAVIOR_POINT end,
    GetLevel = function() return 1 end,
    GetMaxAbilityCharges = function() return maxCharges end,
    GetCurrentAbilityCharges = function() return chargeCount end,
    IsCooldownReady = function() return cooldown end,
    IsFullyCastable = function() return castable end,
    GetCastRange = function(_, _, target)
        assert(target == nil or target.GetAbsOrigin ~= nil, "Vector passed as target entity")
        return 700
    end,
    entindex = function() return 2 end,
}
caster.FindAbilityByName = function() return source end
local order
local adapter = Adapter.new({ Execute = function(_, value) order = value end })
local spec = assert(adapter:Resolve(caster, {
    kind = "ability", logical_id = "sniper_shrapnel",
}, { resolve_action_name = function(_, id) return id end }))
assert(spec.cast_type == "point" and spec.target_mode == "point", "legacy action resolves native point behavior")
assert(adapter:IsInRange(caster, spec, point), "point range must not collapse to zero")
assert(adapter:CanExecute(caster, spec, {}), "remaining charge usable while restoring")
chargeCount = 0
local ok, reason = adapter:CanExecute(caster, spec, {})
assert(not ok and reason == "no_charges")
chargeCount, castable = 1, false
assert(not adapter:CanExecute(caster, spec, {}), "charge does not bypass mana/castability")
maxCharges, chargeCount, castable, cooldown = 0, 0, true, true
spec.logical_id = "sandking_burrowstrike"
assert(adapter:CanExecute(caster, spec, {}), "ordinary abilities may expose zero charges")
cooldown = false
ok, reason = adapter:CanExecute(caster, spec, {})
assert(not ok and reason == "cooldown")
spec.cast_range_override = 300
assert(not adapter:IsInRange(caster, spec, point), "explicit range override respected")
spec.cast_range_override = nil
DOTA_UNIT_ORDER_CAST_POSITION = 5
adapter:Issue(caster, spec, { GetAbsOrigin = function() return point end }, {})
assert(order.Position == point and order.OrderType == 5, "point casts normalize entity selection")
-- Shipped scripts/npc/heroes/npc_dota_hero_sand_king.txt declares the
-- level-one range as AbilityValues.AbilityCastRange.value = 550 (no top-level field).
source.GetCastRange = function() return 0 end
source.GetSpecialValueFor = function(_, key)
    assert(key == "AbilityCastRange")
    return 550
end
assert(adapter:GetRequiredRange(caster, spec, point) == 550, "native AbilityValues range survives zero legacy accessor")
assert(adapter:IsInRange(caster, spec, {x=500}), "Burrowstrike may cast inside its native range")
assert(not adapter:IsInRange(caster, spec, {x=600}), "Burrowstrike does not invent global range")
source.GetEffectiveCastRange = function(_, _, target)
    assert(target == nil, "effective range also receives an entity or nil")
    return 750
end
assert(adapter:GetRequiredRange(caster, spec, point) == 750, "effective native range including upgrades wins")
source.GetEffectiveCastRange = function() return 0 end
source.GetCastRange = function() return 625 end
assert(adapter:GetRequiredRange(caster, spec, point) == 625, "zero effective accessor falls back to positive native range")
-- Time Walk's native cast-range APIs return zero; its travel range is level-dependent.
local abilityName, abilityLevel, rangeBonus = "faceless_void_time_walk", 1, 0
source.GetAbilityName = function() return abilityName end
source.GetLevel = function() return abilityLevel end
source.GetCastRange = function() return 0 end
local rangeReads = 0
source.GetSpecialValueFor = function(_, key)
    if key == "AbilityCastRange" then return 0 end
    assert(key == "range", "unexpected native special")
    rangeReads = rangeReads + 1
    return ({650, 700, 750, 800})[abilityLevel]
end
caster.GetCastRangeBonus = function() return rangeBonus end
local timeWalk = assert(adapter:Resolve(caster, {kind="ability", name=abilityName}, {}))
assert(timeWalk.cast_type == "point" and timeWalk.cast_range == 650, "learned Time Walk resolves native range")
assert(adapter:GetRequiredRange(caster, timeWalk, point) == 650, "zero APIs use Time Walk range special")
assert(adapter:IsInRange(caster, timeWalk, {x=650}), "Time Walk reaches native range")
assert(not adapter:IsInRange(caster, timeWalk, {x=675}), "Time Walk rejects points beyond range and existing tolerance")
abilityLevel = 2
assert(adapter:GetRequiredRange(caster, timeWalk, point) == 700, "existing action reads upgraded Time Walk range dynamically")
assert(adapter:IsInRange(caster, timeWalk, {x=700}), "upgraded Time Walk reaches new range")
assert(not adapter:IsInRange(caster, timeWalk, {x=725}), "upgraded Time Walk remains range restricted")
rangeBonus = 125
assert(adapter:GetRequiredRange(caster, timeWalk, point) == 825, "native special fallback adds caster range bonus")
timeWalk.cast_range_override = 300
assert(adapter:GetRequiredRange(caster, timeWalk, point) == 300, "explicit override still wins for Time Walk")
assert(not adapter:IsInRange(caster, timeWalk, point), "Time Walk respects explicit range restriction")
timeWalk.cast_range_override = nil
source.GetCastRange = function() return 900 end
assert(adapter:GetRequiredRange(caster, timeWalk, point) == 900, "positive normal API wins without adding bonus twice")
source.GetEffectiveCastRange = function() return 1000 end
assert(adapter:GetRequiredRange(caster, timeWalk, point) == 1000, "positive effective API wins over normal API and special")
source.GetCastRange = function() return 0 end
source.GetEffectiveCastRange = function() return 0 end
abilityName = "unreviewed_ability_with_range"
local previousRangeReads = rangeReads
assert(adapter:GetRequiredRange(caster, timeWalk, point) == 0, "other abilities do not infer cast range from range specials")
assert(rangeReads == previousRangeReads, "other abilities never query the Time Walk range fallback")
rangeBonus = 0
-- Live Dota: learned Hammer of Purity includes an upper behavior flag. Its
-- 32-bit accessor overflows, but the full mask still includes UNIT_TARGET (8).
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 8
DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING = 1073741824
source.GetBehavior = function() return 137439088648 end
source.GetBehaviorInt = function() return -2147483648 end
local hammer = assert(adapter:Resolve(caster, {kind="ability", name="omniknight_hammer_of_purity"}, {}))
assert(hammer.cast_type == "unit", "high behavior flags must not hide unit-target casting")
source.GetBehavior = function() return 137438953472 + 1073741824 + 16 end
local vector = assert(adapter:Resolve(caster, {kind="ability", name="native_vector"}, {}))
assert(vector.cast_type == "vector", "vector flags survive the same 32-bit overflow")
source.GetBehavior = function() return 137438953472 + 8 end
local preference, preferenceReason = adapter:Resolve(caster, {
    kind="ability", name="omniknight_hammer_of_purity", cast_preference="point",
}, {})
assert(preference == nil and preferenceReason == "unsupported_cast_preference",
    "overflow fix must still reject cast modes absent from native behavior")
print("action-adapter tests passed")
