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
print("action-adapter tests passed")
