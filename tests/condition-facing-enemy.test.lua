local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local H = require("capability_test_helpers")
local C = require("tactics/condition_registry")
local S = require("tactics/target_selector").new()
local Service = require("tactics/rule_service").new({get_phase=function() return "PREP" end,
    is_roster_hero=function() return true end, is_action_allowed=function() return true end, state={}})
local caster, enemy = H.unit(2, 120, -40), H.unit(3)
caster.forward = Vector(7, 0, 999)
function caster:GetForwardVector() return self.forward end
local ctx = {caster=caster}
local filters = {{type="facing_enemy"}}
local function facing(target)
    local passed, reason = C:EvaluateTargetFilters(filters, ctx, target)
    assert(reason == nil or reason == "target_filter_failed:facing_enemy", tostring(reason))
    return passed
end
local function aim(angle, distance)
    local a = math.rad(angle)
    enemy.position = Vector(120 + math.cos(a)*distance, -40 + math.sin(a)*distance, -500)
end
for _, angle in ipairs({0, 14.9999, -14.9999, 15, -15}) do
    aim(angle, 300)
    assert(facing(enemy), "inside/inclusive boundary " .. angle)
end
for _, angle in ipairs({15.0001, -15.0001, 45, 90, 180}) do
    aim(angle, 300)
    assert(not facing(enemy), "outside " .. angle)
end
caster.forward = Vector(0, 3, -800)
aim(90, 20); assert(facing(enemy), "rotated caster and translated origin")
aim(0, 20); assert(not facing(enemy))
caster.forward = Vector(1e200, 0, 0)
aim(0, 300); assert(facing(enemy), "large non-unit forward")
caster.forward = Vector(1e-200, 0, 0); assert(facing(enemy), "tiny nonzero forward")
local ally = H.unit(2, 200, -40)
assert(not facing(ally) and not facing(caster), "ally/self rejected")
assert(not facing(nil) and not facing(false) and not facing({}), "invalid entities")
local original = enemy.IsNull
enemy.IsNull = function() return true end; assert(not facing(enemy))
enemy.IsNull = function() error("stale handle") end; assert(not facing(enemy))
enemy.IsNull = original
local team = enemy.team
enemy.team = nil; assert(not facing(enemy)); enemy.team = team
for _, bad in ipairs({{}, false, Vector(0,0,1), Vector(0/0,0,0), Vector(math.huge,0,0)}) do
    caster.forward = bad; assert(not facing(enemy), "invalid forward")
end
caster.forward = Vector(1,0,0)
for _, bad in ipairs({{}, false, Vector(0/0,0,0), Vector(math.huge,0,0), Vector(120,-40,900)}) do
    enemy.position = bad; assert(not facing(enemy), "invalid or zero displacement")
end
local getOrigin = enemy.GetAbsOrigin
enemy.GetAbsOrigin = function() error("unavailable") end; assert(not facing(enemy))
enemy.GetAbsOrigin = getOrigin
ctx.caster = nil; assert(not facing(enemy))
ctx.caster = false; assert(not facing(enemy)); ctx.caster = caster
local casterOrigin = caster.GetAbsOrigin
caster.GetAbsOrigin = function() return {x=0/0,y=0} end; assert(not facing(enemy))
caster.GetAbsOrigin = casterOrigin
caster.GetForwardVector = function() error("unavailable") end; assert(not facing(enemy))
caster.GetForwardVector = function(self) return self.forward end

-- Exercise the production selectors with native ability metadata, ranking and
-- point cast filters. An off-axis nearer candidate cannot bypass the condition.
local ability = H.ability(caster, "facing_test", DOTA_ABILITY_BEHAVIOR_UNIT_TARGET)
local rule = H.rule(ability.name)
rule.target_filters = filters
rule.target_priorities = {{type="nearest"}}
local side = H.unit(3, 120, -30)
aim(0, 300)
local candidates = {side, ally, enemy}
ctx.get_candidates = function() return candidates end
local adapter = require("tactics/action_adapter").new({})
local spec = assert(adapter:Resolve(caster, rule.action, ctx))
assert(S:SelectUnit(rule, spec, ctx) == enemy)
ability.behavior = DOTA_ABILITY_BEHAVIOR_POINT
spec = assert(adapter:Resolve(caster, rule.action, ctx))
local point, anchor = S:SelectPoint(rule, spec, ctx)
assert(point == enemy.position and anchor == enemy)
ability.behavior = DOTA_ABILITY_BEHAVIOR_NO_TARGET
spec = assert(adapter:Resolve(caster, rule.action, ctx))
assert(S:CheckNoTarget(rule, spec, ctx))
candidates = {side, ally}
assert(not S:CheckNoTarget(rule, spec, ctx))
assert(not S:SelectUnit(rule, spec, ctx))
assert(not S:SelectPoint(rule, spec, ctx))
candidates = {}; assert(not S:CheckNoTarget(rule, spec, ctx))
rule.target_filters = {}; assert(S:CheckNoTarget(rule, spec, ctx), "optional filter")

local decoded = Service:DecodeFlat({action_kind="ability", action_name=ability.name,
    target_team="enemy", target_filter_1_type="facing_enemy", target_filter_1_value=""})
assert(Service:ValidateCondition(decoded.target_filters[1], C.target_filters))
assert(not Service:ValidateCondition({type="facing_enemy"}, C.use_conditions), "target only")
for _, parameter in ipairs({"value", "radius", "seconds", "angle", "modifier", "action_id", "target_actor"}) do
    local condition = {type="facing_enemy"}
    condition[parameter] = 30
    assert(not Service:ValidateCondition(condition, C.target_filters), "fixed parameter-free condition: " .. parameter)
end
rule.target_filters = filters
assert(Service:ValidateRule(0, caster, rule), "canonical rule schema")
local snapshot = require("tactics/rule_snapshot").ForHero({getRules=function() return {rule} end}, caster)[1]
assert(snapshot.target_filters[1].type == "facing_enemy" and snapshot.target_filters[1].value == nil)
local wire
CustomNetTables = {SetTableValue=function(_, _, _, payload) wire=payload end}
Service:SyncRule(0, caster, 1, rule)
local restored = Service:DecodeFlat(wire)
assert(restored.target_filters[1].type == "facing_enemy")
assert(Service:ValidateRule(0, caster, restored), "wire round trip")
print("PASS facing_enemy: geometry, inclusive boundaries, invalid observations, enemies only, native unit/point/no-target selectors, fixed schema")
