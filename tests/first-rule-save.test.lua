-- First single-row saves must retain the effective defaults shown by the HUD.
-- Native APIs are mocked; bridge, defaults, storage, snapshots and engine are real.
local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS=2; DOTA_TEAM_BADGUYS=3
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_ABILITY_BEHAVIOR_NO_TARGET=4
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1; DOTA_UNIT_TARGET_TEAM_ENEMY=2
DOTA_UNIT_ORDER_CAST_NO_TARGET=8
local vm={__index={Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
local nativeMode={SetExecuteOrderFilter=function() end}
GameRules={GetGameTime=function() return 10 end,GetGameModeEntity=function() return nativeMode end}
Dynamic_Wrap=function(t,k) return t[k] end
CustomGameEventManager={RegisterListener=function() end}
local net,orders={},{}
CustomNetTables={SetTableValue=function(_,_,key,value) net[key]=value end}
ExecuteOrderFromTable=function(order) orders[#orders+1]=order end
require("tactics/tactic_bridge")
local Snapshot=require("tactics/rule_snapshot")
local function ability(name,level,behavior,id)
    return {GetAbilityName=function() return name end,GetLevel=function() return level end,
        GetBehavior=function() return behavior end,IsNull=function() return false end,
        IsPassive=function() return false end,IsHidden=function() return false end,
        IsActivated=function() return true end,GetAbilityTargetTeam=function() return behavior==4 and 1 or 2 end,
        GetCastRange=function() return 750 end,IsFullyCastable=function() return true end,
        IsCooldownReady=function() return true end,entindex=function() return id end}
end
local function newGame()
    net={}; orders={}
    local spells={ability("phantom_assassin_stifling_dagger",0,8,11),
        ability("phantom_assassin_phantom_strike",2,8,12),ability("phantom_assassin_blur",1,4,13)}
    local pa={IsNull=function() return false end,IsAlive=function() return true end,
        entindex=function() return 354 end,GetTeamNumber=function() return 2 end,
        GetUnitName=function() return "npc_dota_hero_phantom_assassin" end,
        GetAbilityCount=function() return #spells end,GetAbilityByIndex=function(_,i) return spells[i+1] end,
        GetItemInSlot=function() return nil end,GetAbsOrigin=function() return Vector(0,0,0) end,
        GetHealth=function() return 626 end,GetMaxHealth=function() return 626 end}
    pa.FindAbilityByName=function(_,name)
        for _,a in ipairs(spells) do if a:GetAbilityName()==name then return a end end
    end
    EntIndexToHScript=function(id) return id==354 and pa or nil end
    local g={phase="setup",playerId=0,heroData={[pa:GetUnitName()]={}},heroRulesByName={},
        battleManager={teamHeroes={[2]={pa},[3]={}},teamRules={[3]={}}}}
    local bridge=TacticBridge.new({game_mode=g}); bridge:Install()
    return g,pa,bridge
end
local function payload(action,count)
    return {action_kind="ability",action_id=action,target_team=action=="phantom_assassin_blur" and "self" or "enemy",
        target_types="hero,monster,summon",target_priority_1_type="nearest",approach="range_only",rule_count=count}
end
local g,pa,bridge=newGame()
local before=bridge.getRules(pa)
assert(#before==3 and before[2].action.logical_id=="phantom_assassin_blur")
-- This is the actual HUD's one-row Apply payload, while three rows are visible.
local edit=payload("phantom_assassin_phantom_strike",3)
assert(bridge.ruleService:UpdateRule(0,354,1,edit))
local effective=bridge.getRules(pa)
assert(#effective==3,"first Apply must not replace three visible rules with only the edited row")
assert(effective[2].action.logical_id=="phantom_assassin_blur" and effective[3].action.kind=="attack")
assert(effective[2]~=before[2] and effective[2].action~=before[2].action,"seeded defaults must be independent copies")
local key=pa:GetUnitName()
assert(net[key..":2"].action_id=="phantom_assassin_blur" and net[key..":3"].action_kind=="attack")
local snapshot=Snapshot.ForHero(bridge,pa)
assert(#snapshot==3 and snapshot[2].action=="phantom_assassin_blur","next HUD snapshot retains untouched Blur")
-- An untouched Blur rule actually reaches the real engine and native-order path.
g.phase="fight"
local engine=bridge.tacticEngine
local ok,reason=engine:TryRule(pa,engine:GetState(pa),{caster=pa,now=10,
    get_candidates=function() return {pa} end,resolve_action_name=function(_,name) return name end},effective[2],2)
assert(ok and #orders==1 and orders[1].OrderType==8 and orders[1].AbilityIndex==13,tostring(reason))
g.phase="setup"
-- Later edits preserve saved data; the same stable hero key survives entity replacement.
local blur=payload("phantom_assassin_blur",3); blur.enabled=false
assert(bridge.ruleService:UpdateRule(0,354,2,blur))
assert(bridge.getRules(pa)[2].enabled==false and before[2].enabled==true)
bridge:ResetState()
assert(#bridge.getRules(pa)==3 and not bridge.getRules(pa)[2].enabled)
-- First edit of the second row must fill the earlier row instead of leaving an ipairs hole.
g,pa,bridge=newGame()
assert(bridge.ruleService:UpdateRule(0,354,2,payload("phantom_assassin_blur",3)))
assert(#bridge.getRules(pa)==3 and bridge.getRules(pa)[1].action.logical_id=="phantom_assassin_phantom_strike")
-- A rejected edit must not establish authored state or seed any defaults.
g,pa,bridge=newGame()
assert(not bridge.ruleService:UpdateRule(0,354,1,payload("not_owned",3)))
assert(next(bridge.ruleService.state.rules)==nil)
assert(#bridge.getRules(pa)==3)
-- Explicit deletion wins, including a first save with a reduced row count.
assert(bridge.ruleService:UpdateRule(0,354,1,payload("phantom_assassin_phantom_strike",1)))
assert(#bridge.getRules(pa)==1)
assert(bridge.ruleService:UpdateRule(0,354,1,payload("phantom_assassin_phantom_strike",3)))
assert(#bridge.getRules(pa)==1,"later updates must not resurrect deliberately deleted rules")
assert(net[pa:GetUnitName()..":2"].action_id==nil)
print("PASS: real bridge first-row save retains Blur/attack, untouched Blur executes, later saves/deletion and rejection preserve intent")
