local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Adapter = require("tactics/action_adapter")
local Engine = require("tactics/tactic_engine")
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 1
DOTA_ABILITY_BEHAVIOR_POINT = 2
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
DOTA_ABILITY_BEHAVIOR_TOGGLE = 8
DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING = 16
DOTA_UNIT_TARGET_TREE = 32
DOTA_UNIT_ORDER_CAST_TARGET = 905
DOTA_UNIT_ORDER_CAST_POSITION = 904
DOTA_UNIT_ORDER_CAST_NO_TARGET = 903
DOTA_UNIT_ORDER_CAST_TOGGLE = 906
bit = {band = function(a,b) return math.floor(a/b)%2 == 1 and b or 0 end}
local behavior, target_type = 1, 32
local source = {
    GetBehaviorInt=function() return behavior end,
    GetAbilityTargetType=function() return target_type end,
    GetCastRange=function() return 300 end,
    GetLevel=function() return 1 end,
    GetToggleState=function() return false end,
    entindex=function() return 99 end,
}
local caster = {
    FindAbilityByName=function() return source end,
    GetAbsOrigin=function() return {x=0,y=0,z=0} end,
    IsAlive=function() return true end,
    entindex=function() return 1 end,
}
local orders = {}
local adapter = Adapter.new({Execute=function(_,order) orders[#orders+1]=order end})
local function resolve(extra)
    local action=extra or {}
    action.kind,action.name="ability","generic_spell"
    return adapter:Resolve(caster,action,{})
end
for _, flags in ipairs({1,4,8}) do
    behavior=flags
    local spec,reason=resolve()
    assert(spec==nil and reason=="special_adapter_required","exclusive tree behavior fails closed")
end
behavior=3
local spec=assert(resolve())
assert(spec.cast_type=="point","tree-capable point casts retain native point behavior")
assert(adapter:Issue(caster,spec,{x=100,y=0,z=0},{}))
assert(orders[#orders].OrderType==904)
assert(not resolve({cast_preference="unit"}),"tree-only target type cannot be forced into a unit cast")
target_type=0
for _, flags in ipairs({16,20,24}) do
    behavior=flags
    assert(not resolve(),"vector without a native primary order fails closed")
end
for _, flags in ipairs({17,18,19}) do
    behavior=flags
    local vector=assert(resolve())
    assert(vector.cast_type=="vector" and vector.target_mode=="vector")
    assert(vector.vector_mode==(flags==17 and "unit" or "point"))
    assert(not resolve({cast_type="point",cast_preference="point"}),"overrides cannot bypass vector pairing")
end
behavior=4
for _,mode in ipairs({"tree","vector","facing"}) do
    assert(not resolve({target_mode=mode}))
    assert(not resolve({cast_type=mode}))
    local unsupported={kind="ability",logical_id="unsupported",source=source,cast_type=mode,target_mode=mode}
    local count=#orders
    assert(not adapter:Issue(caster,unsupported,{},{}))
    assert(not adapter:IssueApproach(caster,unsupported,{}))
    assert(#orders==count,"unsupported geometry cannot issue a cast or chase")
end
for _,case in ipairs({{4,"none",903},{8,"toggle",906},{2,"point",904},{1,"unit",905}}) do
    behavior=case[1]
    spec=assert(resolve())
    assert(spec.cast_type==case[2])
    local target={entindex=function() return 20 end,IsAlive=function() return true end}
    assert(adapter:Issue(caster,spec,target,{}))
    assert(orders[#orders].OrderType==case[3])
end
local engine=Engine.new({order_gate={},get_phase=function() return "FIGHT" end,
    get_battle_units=function() return {} end,get_rules=function() return {} end,build_context=function() return {} end})
for _,mode in ipairs({"tree","vector","facing"}) do
    local target,_,reason=engine:ResolveRuleTarget({}, {target_mode=mode}, {caster=caster})
    assert(target==nil and reason=="unsupported_target_mode","unsupported modes never enter native unit selection")
end
print("condition-native-targets tests passed")
