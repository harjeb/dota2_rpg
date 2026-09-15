local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Service = require("tactics/rule_service")
local Snapshot = require("tactics/rule_snapshot")
local Catalog = require("tactics/ability_catalog")
local Capability = require("tactics/ability_capability")
local hero = {lineupHeroName="npc_dota_hero_axe",IsNull=function() return false end,
    GetUnitName=function() return "npc_dota_hero_axe" end,GetAbilityCount=function() return 0 end,
    entindex=function() return 42 end}
EntIndexToHScript=function(id) return id==42 and hero end
local net={}
CustomNetTables={SetTableValue=function(_,_,key,payload) net[key]=payload end}
local allowed=true
local state={rules={}}
local service=Service.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function(_,_,action) return allowed and action.kind=="buyback" end,state=state})
local flat={action_kind="buyback",action_id="buyback",action_name="axe_berserkers_call",enabled=1,
    target_team="enemy",target_types="monster",target_mode="unit",approach="allow_approach",
    use_condition_1_type="self_hp_pct_lte",use_condition_1_value=0.2,target_filter_1_type="is_casting",
    target_priority_1_type="farthest",desired_toggle_state="1",destination="target_behind",cast_preference="point",
    positioning_mode="fixed",positioning_distance=300,movement_mode="follow",chase_timeout=3,
    state_policy="mana_hysteresis",state_mana_on=0.8,state_mana_off=0.2}
assert(service:UpdateRule(0,42,1,flat))
local rule=service:GetHeroRules(hero)[1]
assert(rule.action.kind=="buyback" and rule.action.logical_id=="buyback")
assert(rule.target.team=="self" and #rule.target.types==1 and rule.target.types[1]=="hero")
assert(rule.action.target_mode=="self" and rule.approach=="range_only")
assert(#rule.use_conditions==0 and #rule.target_filters==0 and #rule.target_priorities==0)
assert(rule.action.name==nil and rule.action.positioning_mode==nil and rule.action.movement_mode==nil)
assert(rule.action.desired_toggle_state==nil and rule.action.destination==nil and rule.action.state_policy==nil)
local synced=net[hero.lineupHeroName..":1"]
assert(synced.action_kind=="buyback" and synced.action_id=="buyback" and synced.target_team=="self")
local snapshot=Snapshot.ForHero({getRules=function() return service:GetHeroRules(hero) end},hero)
assert(snapshot[1].action=="buyback" and snapshot[1].enabled==1 and snapshot[1].target_team=="self")
assert(#snapshot[1].use_conditions==0 and snapshot[1].positioning_mode==nil)
flat.enabled=0
assert(service:UpdateRule(0,42,1,flat))
assert(service:GetHeroRules(hero)[1].enabled==false)
assert(Snapshot.ForHero({getRules=function() return service:GetHeroRules(hero) end},hero)[1].enabled==0)
allowed=false
local ok,why=service:UpdateRule(0,42,1,flat)
assert(not ok and why=="action_not_allowed_for_hero","campaign ownership callback remains authoritative")
allowed=true
flat.action_id="axe_berserkers_call"
ok,why=service:UpdateRule(0,42,1,flat)
assert(not ok and why=="invalid_buyback_action")
flat.action_id="buyback"; flat.action_kind="ability"
ok,why=service:UpdateRule(0,42,1,flat)
assert(not ok and why=="invalid_buyback_action","buyback cannot masquerade as a cast")
local function contains(list,value) for _,v in ipairs(list) do if v==value then return true end end return false end
assert(not contains(Catalog.ListActions(hero),"buyback"),"shared enemy/default catalog must not opt in")
assert(contains(Catalog.ListActions(hero,true),"buyback"),"eligible campaign picker exposes buyback")
local kind,name=Catalog.DescribeAction(hero,"buyback")
assert(kind=="buyback" and name=="")
local cap=Capability.ForAction(hero,rule.action)
assert(cap.mode=="buyback" and cap.role=="death_policy" and cap.teams.self==1 and cap.teams.enemy==0 and cap.types.monster==0)
print("PASS buyback canonical decode, validation, save/snapshot, disable, ownership gate and opt-in catalog")
