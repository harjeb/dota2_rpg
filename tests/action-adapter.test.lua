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
-- Values below come from the installed native hero definitions in the snapshot.
local reviewed = {
    {"dawnbreaker_fire_wreath", "swipe_radius", {300, 300}, false},
    {"dawnbreaker_celestial_hammer", "range", {700, 900}, true},
    {"puck_waning_rift", "max_distance", {350, 350}, true},
    {"magnataur_skewer", "range", {800, 900}, true},
    {"void_spirit_astral_step", "max_travel_distance", {800, 900}, true},
    {"monkey_king_wukongs_command", "cast_range", {625, 625}, true},
    {"mars_gods_rebuke", "radius", {500, 500}, false},
    {"mars_spear", "spear_range", {900, 1000}, false},
    {"clinkz_burning_barrage", "range", {850, 850}, false},
    {"phoenix_icarus_dive", "dash_length", {1100, 1200}, false},
}
for _, entry in ipairs(reviewed) do
    abilityName, abilityLevel, rangeBonus = entry[1], 1, 125
    source.GetSpecialValueFor = function(_, key)
        if key == entry[2] then return entry[3][abilityLevel] end
        return 0
    end
    local action = assert(adapter:Resolve(caster, {kind="ability",name=abilityName}, {}))
    for level=1,2 do
        abilityLevel = level
        local expected = entry[3][level] + (entry[4] and 125 or 0)
        assert(adapter:GetRequiredRange(caster,action,point) == expected, abilityName .. " native dynamic reach")
        assert(adapter:IsInRange(caster,action,{x=expected}), abilityName .. " legal edge")
        assert(not adapter:IsInRange(caster,action,{x=expected+25}), abilityName .. " rejects beyond native reach")
    end
    source.GetEffectiveCastRange = function() return 125 end
    assert(adapter:GetRequiredRange(caster,action,point) == entry[3][2] + (entry[4] and 125 or 0),
        abilityName .. " bonus-only native effective range must not hide its special reach")
    source.GetEffectiveCastRange = function() return 777 end
    assert(adapter:GetRequiredRange(caster,action,point) == 777, "positive native API retains authority for " .. abilityName)
    source.GetEffectiveCastRange = function() return 0 end
end
abilityName, rangeBonus = "drow_ranger_multishot", 125
local attackRange = 625
caster.Script_GetAttackRange = function() return attackRange end
source.GetSpecialValueFor = function(_, key) return key == "arrow_range_base" and 475 or 0 end
local multishot = assert(adapter:Resolve(caster,{kind="ability",name=abilityName},{}))
assert(adapter:GetRequiredRange(caster,multishot,point)==1100, "Multishot follows native attack range + 475, not cast bonus")
attackRange = 775
assert(adapter:GetRequiredRange(caster,multishot,point)==1250, "attack range equipment updates existing Multishot action")
abilityName = "monkey_king_wukongs_command"
caster.HasScepter = function() return true end
source.GetSpecialValueFor = function(_, key) return ({cast_range=625,cast_range_scepter=1550})[key] or 0 end
assert(adapter:GetRequiredRange(caster,multishot,point)==1675, "Wukong's Command reads native Scepter cast range")
caster.HasScepter, caster.Script_GetAttackRange = nil, nil
source.GetSpecialValueFor = function() return 0 end
source.GetEffectiveCastRange = function() return 125 end
for _, name in ipairs({"rattletrap_rocket_flare","furion_wrath_of_nature","treant_living_armor","storm_spirit_ball_lightning"}) do
    abilityName = name
    assert(adapter:GetRequiredRange(caster,timeWalk,point)==math.huge, name .. " native global zero is not a 125-unit spell")
    assert(adapter:IsInRange(caster,timeWalk,{x=5000}), name .. " reaches a distant battlefield target")
end
source.GetEffectiveCastRange = function() return 0 end
abilityName, rangeBonus = "unreviewed_ability_with_range", 0
assert(adapter:GetRequiredRange(caster,timeWalk,point)==0, "unreviewed zero-range spell is never global")
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
-- Native control must be checked again when issuing, including custom adapters.
local controlled = {}
for _, method in ipairs({"IsStunned", "IsFrozen", "IsCommandRestricted", "IsOutOfGame",
    "IsDisarmed", "IsRooted", "IsSilenced", "IsMuted"}) do
    caster[method] = function() return controlled[method] == true end
end
source.GetBehavior = function() return 16 end
cooldown = true
local attack = {kind="attack", logical_id="attack"}
local move = {kind="move", logical_id="move"}
local item = {kind="item", logical_id="item", source=source, cast_type="none"}
local target = {IsAlive=function() return true end, entindex=function() return 3 end}
local customCalls = 0
adapter:Register("custom", {
    CanExecute=function() customCalls=customCalls+1; return true end,
    Issue=function() customCalls=customCalls+1; return true end,
})
local custom = {kind="ability", logical_id="custom", source=source, cast_type="none"}
for _, method in ipairs({"IsStunned", "IsFrozen", "IsCommandRestricted", "IsOutOfGame"}) do
    controlled[method] = true
    for _, action in ipairs({attack, move, spec, item, custom, vector}) do
        order = nil
        assert(not adapter:CanExecute(caster, action, {}), method .. " blocks eligibility")
        assert(not adapter:Issue(caster, action, target, {}), method .. " blocks direct issue")
        assert(not adapter:IssueApproach(caster, action, target), method .. " blocks approach")
        assert(order == nil, "disabled unit must not emit orders")
    end
    assert(adapter:Issue(caster, {kind="wait"}, nil, {}), "wait does not issue an order")
    controlled[method] = false
end
assert(customCalls == 0, "custom callbacks cannot bypass native control")
controlled.IsRooted = true
assert(adapter:CanExecute(caster, attack, {}), "root permits attacks in range")
assert(adapter:Issue(caster, attack, target, {}), "root permits native attack orders")
assert(not adapter:IssueApproach(caster, attack, target), "root prevents chasing targets")
assert(not adapter:CanExecute(caster, move, {}), "root prevents movement")
assert(adapter:CanExecute(caster, spec, {}), "root does not silence ordinary spells")
DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES = 2048
source.GetBehavior = function() return 16 + 2048 end
assert(not adapter:CanExecute(caster, spec, {}), "native ROOT_DISABLES blocks mobility spells")
assert(not adapter:Issue(caster, spec, point, {}), "direct issue honors ROOT_DISABLES")
source.GetBehavior = function() return 16 end
controlled.IsRooted = false
controlled.IsDisarmed = true
assert(not adapter:CanExecute(caster, attack, {}))
assert(adapter:CanExecute(caster, spec, {}), "disarm permits spells")
assert(adapter:CanExecute(caster, item, {}), "disarm permits items")
controlled.IsDisarmed = false
controlled.IsSilenced = true
assert(not adapter:Issue(caster, spec, point, {}))
assert(adapter:CanExecute(caster, item, {}), "silence permits items")
assert(adapter:CanExecute(caster, attack, {}), "silence permits attacks")
controlled.IsSilenced = false
controlled.IsMuted = true
assert(not adapter:Issue(caster, item, nil, {}))
assert(adapter:CanExecute(caster, spec, {}), "mute permits spells")
controlled.IsMuted = false
for _, name in ipairs({"npc_dota_hero_faceless_void", "npc_dota_hero_axe"}) do
    caster.GetUnitName = function() return name end
    caster.HasModifier = function(_, modifier) return modifier == "modifier_faceless_void_chronosphere_freeze" end
    assert(adapter:CanExecute(caster, spec, {}), "Chronosphere modifier alone never synthesizes a native stun")
    controlled.IsStunned = true
    assert(not adapter:CanExecute(caster, spec, {}), "Void is not immune to unrelated native stuns")
    controlled.IsStunned = false
end
print("action-adapter tests passed")
