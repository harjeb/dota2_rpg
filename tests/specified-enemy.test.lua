package.path = "game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Snapshot = require("tactics/rule_snapshot")
local Rules = require("tactics/rule_service")
local Conditions = require("tactics/condition_registry")
local Engine = require("tactics/tactic_engine")
DOTA_TEAM_GOODGUYS=2; DOTA_TEAM_BADGUYS=3
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_UNIT_ORDER_CAST_TARGET=6
bit={band=function(a,b) return a==b and b or 0 end}
local vm={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local function unit(id,team,occurrence)
    local u={id=id,team=team,hp=100,ruleSnapshotKey=occurrence and ("enemy:npc_dota_hero_axe:"..occurrence)}
    function u:entindex() return self.id end
    function u:GetUnitName() return "npc_dota_hero_axe" end
    function u:GetTeamNumber() return self.team end
    function u:IsNull() return self.missing == true end
    function u:IsAlive() return self.hp>0 end
    function u:GetAbsOrigin() return Vector(self.id*10,0,0) end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return 100 end
    function u:IsInvulnerable() return false end
    function u:IsMagicImmune() return false end
    return u
end
local caster,first,second,bench=unit(1,2),unit(2,3,0),unit(3,3,1),unit(4,3,2)
local manager={teamHeroes={[2]={caster},[3]={first,second}}}
local chapter="ch05"
local key="ch05:enemy:npc_dota_hero_axe:1"
local function resolve(k) return Snapshot.ResolveTargetActor(manager,chapter,caster,k) end
assert(Snapshot.TargetActor(manager,chapter,second)==key)
assert(Snapshot.TargetActor(manager,chapter,bench)==nil)
assert(resolve(key)==second and resolve("ch05:enemy:npc_dota_hero_axe:0")==first)
local service=Rules.new({get_phase=function() return "PREPARE" end,
    is_roster_hero=function() return true end,is_action_allowed=function() return true end,
    is_target_actor_allowed=function(_,_,k) return resolve(k)~=nil end,
    get_hero_key=function() return "caster" end,state={rules={}}})
local flat={action_kind="ability",action_id="spell",action_name="spell",target_team="enemy",
    target_filter_1_type="specified_enemy",target_filter_1_target_actor=key}
local rule=service:DecodeFlat(flat)
assert(rule.target_filters[1].target_actor==key and service:ValidateRule(0,caster,rule))
for _,bad in ipairs({"", "enemy:npc_dota_hero_axe:1", "ch05:ally:npc_dota_hero_axe:1",
    "ch05:enemy:npc_dota_hero_axe:-1", "ch05:enemy:npc_dota_hero_axe:01",
    "ch05:enemy:npc_dota_hero_axe:1:extra", "ch05:enemy:npc.dota:1", 123, {}}) do
    assert(not service:ValidateCondition({type="specified_enemy",target_actor=bad},Conditions.target_filters))
end
assert(not service:ValidateCondition({type="always",target_actor=key},Conditions.use_conditions))
rule.target.team="ally"; assert(not service:ValidateRule(0,caster,rule)); rule.target.team="enemy"
second.team=2; assert(resolve(key)==nil and not service:ValidateRule(0,caster,rule)); second.team=3
rule.target_filters[1].target_actor="ch05:enemy:npc_dota_hero_axe:2"
assert(not service:ValidateRule(0,caster,rule)); rule.target_filters[1].target_actor=key
local payload
CustomNetTables={SetTableValue=function(_,_,_,data) payload=data end}
service:SyncRule(0,caster,1,rule)
assert(payload.target_filter_1_target_actor==key)
assert(service:DecodeFlat(payload).target_filters[1].target_actor==key)
manager.getRules=function() return {rule} end
assert(Snapshot.ForHero(manager,caster)[1].target_filters[1].target_actor==key)
require("tactics/tactic_bridge")
assert(TacticBridge.ConvertLegacyRule(1,flat).target_filters[1].target_actor==key)
assert(TacticBridge.ConvertLegacyRule(1,Snapshot.ForHero(manager,caster)[1]).target_filters[1].target_actor==key)
assert(not Conditions:EvaluateTargetFilters(rule.target_filters,{caster=caster},second))

-- Exercise actual engine rule ordering, native target selection and order emission.
local spell={}
function spell:GetLevel() return 1 end
function spell:GetBehaviorInt() return 8 end
function spell:GetCastRange() return 600 end
function spell:GetAOERadius() return 0 end
function spell:IsFullyCastable() return true end
function spell:IsCooldownReady() return true end
function spell:entindex() return 99 end
function spell:CastFilterResultTarget(target) return target.team==3 and 0 or 1 end
caster.FindAbilityByName=function() return spell end
GameRules={GetGameTime=function() return 10 end}
local fallback=service:DecodeFlat({action_kind="ability",action_id="spell",action_name="spell",target_team="enemy"})
local orders={}
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o end},
    get_phase=function() return "FIGHT" end,get_battle_units=function() return {caster} end,
    get_rules=function() return {rule,fallback} end,build_context=function()
        return {get_candidates=function() return manager.teamHeroes[3] end,get_target_actor=resolve}
    end})
local function tick(expected)
    orders={}; engine:Reset(); engine:GetState(caster).next_eval=0; engine:Think()
    assert(#orders==1 and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_TARGET and orders[1].TargetIndex==expected,
        "actual engine must select designated enemy or continue to the next authored rule")
end
tick(second.id)
second.hp=0; tick(first.id); second.hp=100
second.missing=true; tick(first.id); second.missing=false
manager.teamHeroes[3]={first}; tick(first.id)
-- Same chapter retry replaces entities, not authored occurrence identities.
first,second=unit(12,3,0),unit(13,3,1); manager.teamHeroes[3]={first,second}
assert(resolve(key)==second); tick(second.id)
first.missing=true; assert(resolve(key)==second); tick(second.id); first.missing=false
service.state.rules.caster={rule}
chapter="ch06"
assert(resolve(key)==nil and not service:ValidateRule(0,caster,rule))
assert(service:GetHeroRules(caster)[1].target_filters[1].target_actor==key,"chapter change preserves authored stale filter")
tick(first.id)
chapter="ch05"; second.team=2; tick(first.id)
-- Run the actual addon broadcast method with only its engine dependencies stubbed.
local file=assert(io.open("game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua","r"))
local source=file:read("*a"); file:close()
local body=assert(source:match("function CDota2RpgDemo:BroadcastHeroInfo%(%)\n.-\nend"))
local events={}
local addon={battleManager=manager,currentLevelId="ch05"}
local compile=loadstring or load
local install=assert(compile("return function(RuleSnapshot, AbilityCatalog, TacticEngine, BuildHeroActionSlots, DescribeAction, CDota2RpgDemo, CustomGameEventManager) "..body.." end"))()
install(Snapshot,{ListAbilities=function() return {} end,PublishCapabilities=function() return 1 end},{IsValidUnit=function(u) return not u:IsNull() end},
    function() return {} end,function() return "","" end,addon,
    {Send_ServerToAllClients=function(_,event,data) events[#events+1]={event=event,data=data} end})
second.team=3
addon:BroadcastHeroInfo()
local enemySlots=0
for _,event in ipairs(events) do
    if event.event=="rpg_hero_slots" then
        if event.data.slot_key:match("^dire_") then
            enemySlots=enemySlots+1
            assert(event.data.target_actor=="ch05:"..event.data.rule_key,"live enemy slot payload uses exact protocol")
        else assert(event.data.target_actor=="","ally slots cannot become enemy picker selections") end
    elseif event.event=="rpg_enemy_roster" then
        assert(event.data.units[2].target_actor==key,"enemy roster also publishes qualified identity")
    end
end
assert(enemySlots==2)
print("PASS: specified enemy protocol, validation, snapshots/legacy, broadcasts, duplicate occurrences, retry, dead/missing fallthrough and next-chapter fail-closed")
