local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local Rules=require("tactics/rule_service")
local Snapshot=require("tactics/rule_snapshot")
require("tactics/tactic_bridge")
local hero={IsNull=function() return false end,GetUnitName=function() return "npc_dota_hero_test" end}
EntIndexToHScript=function() return hero end
local state={rules={}}
local service=Rules.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function() return true end,state=state})
local published
CustomNetTables={SetTableValue=function(_,_,_,payload) published=payload end}
local function flat(extra)
    local value={action_kind="ability",action_id="windrunner_powershot",target_team="enemy",target_types="hero"}
    for k,v in pairs(extra or {}) do value[k]=v end
    return value
end
local function validate(extra)
    local rule=service:DecodeFlat(flat(extra))
    local ok,reason=service:ValidateRule(0,hero,rule)
    return ok,reason,rule
end
local ids={"windrunner_powershot","keeper_of_the_light_illuminate","monkey_king_primal_spring","ringmaster_tame_the_beasts",
    "primal_beast_onslaught","hoodwink_sharpshooter","alchemist_unstable_concoction","oracle_fortunes_end"}
for _,id in ipairs(ids) do
    for _,seconds in ipairs({0,1.25,120}) do
        for _,mode in ipairs({"time","max"}) do
            assert(service:UpdateRule(0,1,1,flat({action_id=id,charge_mode=mode,charge_time=tostring(seconds)})))
            local stored=state.rules.npc_dota_hero_test[1]
            assert(stored.action.charge_mode==mode and published.charge_mode==mode)
            local expected=mode=="time" and seconds or nil
            assert(stored.action.charge_time==expected and published.charge_time==expected)
            local decoded=service:DecodeFlat(published)
            assert(service:ValidateRule(0,hero,decoded))
            assert(decoded.action.charge_mode==mode and decoded.action.charge_time==expected)
            local saved=Snapshot.ForHero({getRules=function() return {stored} end},hero)[1]
            assert(saved.charge_mode==mode and saved.charge_time==expected)
            local restored=TacticBridge.ConvertLegacyRule(1,saved)
            assert(restored.action.charge_mode==mode and restored.action.charge_time==expected)
            assert(service:ValidateRule(0,hero,restored))
        end
    end
end
for _,extra in ipairs({{}, {charge_mode="",charge_time=""}}) do
    local ok,why,rule=validate(extra); assert(ok,why)
    assert(rule.action.charge_mode==nil and rule.action.charge_time==nil)
    service:SyncRule(0,hero,1,rule)
    assert(published.charge_mode==nil and published.charge_time==nil)
end
local function rejects(extra,expected)
    local ok,why=validate(extra); assert(not ok and why==expected,tostring(why).." expected "..expected)
end
for _,mode in ipairs({"wrong",false,1,{}}) do rejects({charge_mode=mode},"invalid_charge_mode") end
for _,seconds in ipairs({-1,121,math.huge,-math.huge,0/0,"nan","abc",false,{}}) do
    rejects({charge_mode="time",charge_time=seconds},"invalid_charge_time")
end
rejects({charge_mode="time"},"invalid_charge_time")
rejects({charge_time=1},"charge_mode_required")
for _,id in ipairs({"pudge_dismember","bane_fiends_grip","crystal_maiden_freezing_field","keeper_of_the_light_illuminate_end","alchemist_unstable_concoction_throw","basic_attack"}) do
    rejects({action_id=id,charge_mode="max"},"charge_requires_charging_ability")
    assert(validate({action_id=id}),"ordinary unconfigured actions retain behavior")
end
rejects({action_kind="item",charge_mode="max"},"charge_requires_charging_ability")
rejects({action_name="pudge_dismember",charge_mode="max"},"charge_requires_charging_ability")
assert(validate({action_name="windrunner_powershot",charge_mode="max"}))
assert(service:UpdateRule(0,1,1,flat({charge_mode="time",charge_time=2})))
local previous,previousPayload=state.rules.npc_dota_hero_test[1],published
assert(not service:UpdateRule(0,1,1,flat({charge_mode="time",charge_time=121})))
assert(previous==state.rules.npc_dota_hero_test[1] and previousPayload==published,"invalid save remains atomic")
print("PASS: charge configuration decode/save/snapshot/restore, reviewed scope, numeric rejection and legacy defaults")
