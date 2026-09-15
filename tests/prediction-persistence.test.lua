local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local Rules=require("tactics/rule_service")
local Snapshot=require("tactics/rule_snapshot")
local Compatibility=require("tactics/rule_compatibility")
require("tactics/tactic_bridge")
DOTA_ABILITY_BEHAVIOR_POINT=16
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4
DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING=64
local mask=16
local spell={IsNull=function() return false end,GetAbilityName=function() return "test_point" end,GetBehaviorInt=function() return mask end}
local hero={IsNull=function() return false end,GetUnitName=function() return "npc_dota_hero_test" end,
    FindAbilityByName=function() return spell end,GetItemInSlot=function(_,slot) if slot==0 then return spell end end}
EntIndexToHScript=function() return hero end
local state={rules={}}
local service=Rules.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function() return true end,state=state})
local published
CustomNetTables={SetTableValue=function(_,_,_,payload) published=payload end}
local function flat(extra)
    local value={action_kind="ability",action_id="test_point",target_team="enemy",target_types="hero"}
    for k,v in pairs(extra or {}) do value[k]=v end
    return value
end
local function validate(extra)
    local rule=service:DecodeFlat(flat(extra))
    local ok,reason=service:ValidateRule(0,hero,rule)
    return ok,reason,rule
end
for _,direction in ipairs({"forward","backward"}) do
    for _,distance in ipairs({0,200,3000,12.5}) do
        assert(service:UpdateRule(0,1,1,flat({prediction_direction=direction,prediction_distance=tostring(distance)})))
        local stored=state.rules.npc_dota_hero_test[1]
        assert(stored.target.prediction_direction==direction and stored.target.prediction_distance==distance)
        assert(published.prediction_direction==direction and published.prediction_distance==distance)
        local decoded=service:DecodeFlat(published)
        assert(service:ValidateRule(0,hero,decoded))
        assert(decoded.target.prediction_direction==direction and decoded.target.prediction_distance==distance)
        local saved=Snapshot.ForHero({getRules=function() return {stored} end},hero)[1]
        assert(saved.prediction_direction==direction and saved.prediction_distance==distance,"snapshot preserves prediction")
        local restored=TacticBridge.ConvertLegacyRule(1,saved)
        assert(restored.target.prediction_direction==direction and restored.target.prediction_distance==distance,
            "persisted snapshot restores nested prediction")
        assert(service:ValidateRule(0,hero,restored))
    end
end
local ok,reason,rule=validate({prediction_direction="forward"})
assert(ok and rule.target.prediction_distance==200,"enabled default")
for _,extra in ipairs({{}, {prediction_direction="",prediction_distance=""}, {prediction_distance=123}}) do
    ok,reason,rule=validate(extra); assert(ok,reason)
    assert(rule.target.prediction_direction==nil and rule.target.prediction_distance==nil,"disabled remains absent")
    service:SyncRule(0,hero,1,rule)
    assert(published.prediction_direction==nil and published.prediction_distance==nil)
    local saved=Snapshot.ForHero({getRules=function() return {rule} end},hero)[1]
    assert(saved.prediction_direction==nil and saved.prediction_distance==nil,"legacy snapshot remains absent")
end
for _,direction in ipairs({"sideways","disabled",false,1,{}}) do
    ok,reason=validate({prediction_direction=direction})
    assert(not ok and reason=="invalid_prediction_direction")
end
for _,distance in ipairs({-1,3001,math.huge,-math.huge,0/0,"nan","abc",false,{}}) do
    ok,reason=validate({prediction_direction="forward",prediction_distance=distance})
    assert(not ok and reason=="invalid_prediction_distance",tostring(distance)..":"..tostring(reason))
end
-- Invalid updates cannot replace the previously persisted rule or publication.
assert(service:UpdateRule(0,1,1,flat({prediction_direction="backward",prediction_distance=100})))
local previous,previousPayload=state.rules.npc_dota_hero_test[1],published
assert(not service:UpdateRule(0,1,1,flat({prediction_direction="forward",prediction_distance=3001})))
assert(state.rules.npc_dota_hero_test[1]==previous and published==previousPayload)
-- Native behavior, including hybrid preference, determines applicability.
for _,behavior in ipairs({4,8,64+16}) do
    mask=behavior
    ok,reason=validate({prediction_direction="forward"})
    assert(not ok and reason=="prediction_requires_point_action",tostring(behavior)..":"..tostring(reason))
    assert(validate({}),"legacy rules remain valid")
end
mask=16+8
assert(validate({prediction_direction="forward",cast_preference="point"}))
ok,reason=validate({prediction_direction="forward",cast_preference="unit"})
assert(not ok and reason=="prediction_requires_point_action")
mask=16
assert(validate({action_kind="item",prediction_direction="backward"}))
for _,kind in ipairs({"attack","move","wait"}) do
    ok,reason=validate({action_kind=kind,prediction_direction="forward"})
    assert(not ok and reason=="prediction_requires_point_action")
end
local custom=service:DecodeFlat(flat({prediction_direction="forward"}))
custom.action.destination="retreat"
ok,reason=Compatibility.Validate(hero,custom)
assert(not ok and reason=="prediction_requires_point_action")
print("PASS: prediction persistence, defaults, atomic rejection, numeric validation and native cast compatibility")
