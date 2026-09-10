-- Native APIs are mocked; verifies the authored team reaches the native order.
local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING=16
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1; DOTA_UNIT_TARGET_TEAM_ENEMY=2
DOTA_UNIT_TARGET_HERO=1; DOTA_UNIT_TARGET_CREEP=2
DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION=100; DOTA_UNIT_ORDER_CAST_TARGET=101
local mt={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},mt) end
mt.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local function unit(id,x,team)
    return {entindex=function() return id end,GetAbsOrigin=function() return Vector(x,0,0) end,
        IsNull=function() return false end,IsAlive=function() return true end,
        IsHero=function() return true end,IsRealHero=function() return true end,
        GetTeamNumber=function() return team end,GetHealth=function() return 100 end,
        GetMaxHealth=function() return 100 end,GetHullRadius=function() return 0 end}
end
local caster,ally,enemy=unit(1,0,2),unit(2,300,2),unit(3,350,3)
local spell={}
function spell:IsNull() return false end
function spell:GetAbilityName() return self.name end
function spell:GetBehaviorInt() return self.behavior end
function spell:GetLevel() return 1 end
function spell:GetCastRange() return self.range end
function spell:GetAbilityTargetTeam() return 1 end
function spell:GetAbilityTargetType() return 1 end
function spell:GetAbilityTargetFlags() return 0 end
function spell:IsHidden() return false end
function spell:IsPassive() return false end
function spell:IsActivated() return true end
function spell:CastFilterResultTarget(t) return t==ally and 0 or 1 end
function spell:CastFilterResultLocation() return 0 end
function spell:entindex() return 99 end
caster.FindAbilityByName=function(_,name) return name==spell.name and spell or nil end
caster.GetAbilityCount=function() return 1 end
caster.GetAbilityByIndex=function() return spell end
UnitFilter=function(t,team,types,flags,casterTeam) return t:GetTeamNumber()==casterTeam and 0 or 1 end
GameRules={GetGameTime=function() return 1 end}
local Service=require("tactics/rule_service")
local Engine=require("tactics/tactic_engine")
local Defaults=require("issue_fixes/default_rules")
local service=Service.new({state={rules={}},get_phase=function() return "PREPARE" end,
    is_roster_hero=function() return true end,is_action_allowed=function() return true end})
local orders,rule={},nil
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o; return true end},
    get_phase=function() return "FIGHT" end,get_rules=function() return {rule} end,
    get_battle_units=function() return {caster} end,
    build_context=function() return {resolve_action_name=function(_,name) return name end,get_candidates=function(_,_,target)
        if target.team=="self" then return {caster} end
        return target.team=="ally" and {caster,ally} or {enemy}
    end} end})
for _,name in ipairs({"marci_companion_run","marci_bodyguard","marci_guardian"}) do
    spell.name=name; spell.behavior=name=="marci_companion_run" and 24 or 8
    spell.range=name=="marci_companion_run" and 450 or 600
    assert(Defaults.CreateForHero(caster)[1].target.team=="ally","native Marci defaults must select allies")
    for _,team in ipairs({"enemy","self","ally"}) do
        rule=service:DecodeFlat({action_kind="ability",action_id=name,target_team=team,target_types="hero"})
        assert(service:ValidateRule(0,caster,rule))
        orders={}; engine:Reset()
        local ok,reason=engine:TryRule(caster,engine:GetState(caster),engine:BuildContext(caster,1),rule,1)
        if team=="ally" then
            assert(ok and orders[#orders].TargetIndex==2,"Marci must cast on another allied hero: "..name.." "..tostring(reason))
            if name=="marci_companion_run" then
                assert(#orders==2 and orders[1].OrderType==100 and orders[1].Position.x==450,
                    "Rebound preserves native unit/vector order pair")
            else assert(#orders==1,"buff uses ordinary native target order") end
        else assert(not ok and #orders==0,"illegal team or self must fail native targeting") end
    end
end
-- Exercise the real generated rules with self accepted by native targeting,
-- then with no custom CastFilter (the engine's UnitFilter-only fallback).
-- The earlier authored-rule checks deliberately reject self in their mock and
-- cannot expose nearest selecting the caster from an otherwise friendly pool.
for _, customFilter in ipairs({true, false}) do
    spell.CastFilterResultTarget = customFilter and function(_, t)
        return t:GetTeamNumber() == caster:GetTeamNumber() and 0 or 1
    end or nil
    for _, name in ipairs({"magnataur_empower", "marci_bodyguard", "marci_guardian"}) do
        spell.name=name; spell.behavior=8; spell.range=600
        rule=Defaults.CreateForHero(caster)[1]
        orders={}; engine:Reset()
        local ctx=engine:BuildContext(caster,1)
        local ok,reason=engine:TryRule(caster,engine:GetState(caster),ctx,rule,1)
        assert(ok and #orders==1 and orders[1].TargetIndex==2,
            "generated partner buff must select teammate even when self is legal: "..name.." "..tostring(reason))
        orders={}; engine:Reset()
        ctx.get_candidates=function() return {caster} end
        assert(not engine:TryRule(caster,engine:GetState(caster),ctx,rule,1) and #orders==0,
            "partner default must not fall back to self without a teammate")
        orders={}; engine:Reset()
        ctx.get_candidates=function() return {caster,ally} end
        spell.range=100
        assert(not engine:TryRule(caster,engine:GetState(caster),ctx,rule,1) and #orders==0,
            "partner default must retain native range limits")
        local authored={action={kind="ability",logical_id=name},target={team="self"}}
        assert(Defaults.Normalize({authored},caster)[1]==authored,
            "partner default policy must preserve authored rules")
    end
end
print("PASS: Marci native target/vector mocks and Marci/Magnus generated teammate defaults (self legal, UnitFilter fallback, solo, range, authored preservation)")
