local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local options
package.loaded["tactics/order_filter"]={OrderGate={new=function() return {} end},
    OrderFilter={new=function() return {Install=function() end} end}}
package.loaded["tactics/tactic_engine"]={new=function(o) options=o; return {Reset=function() end} end}
require("tactics/tactic_bridge")
local Conditions=require("tactics/condition_registry")
DOTA_TEAM_GOODGUYS=2; DOTA_TEAM_BADGUYS=3
local now=10
GameRules={GetGameTime=function() return now end,GetGameModeEntity=function() return {} end}
CustomGameEventManager={RegisterListener=function() end}
CustomNetTables={SetTableValue=function() end}
local entities={}
local function unit(id,team)
    local u={alive=true}
    function u:entindex() return id end
    function u:GetEntityIndex() return id end
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:IsRealHero() return true end
    function u:GetTeamNumber() return team end
    function u:GetUnitName() return "hero_"..id end
    entities[id]=u
    return u
end
local caster,ally,enemy=unit(1,2),unit(2,2),unit(3,3)
EntIndexToHScript=function(id) return entities[id] end
local gm={phase="fight",playerId=0,heroData={},heroRulesByName={},battleManager={
    teamHeroes={[2]={caster,ally},[3]={enemy}},teamRules={[3]={}},
    GetEnemyTeam=function(_,team) return team==2 and 3 or 2 end,
    GetBattleTime=function() return now end}}
local bridge=TacticBridge.new({game_mode=gm}); bridge:Install()
local function condition(kind,seconds,target)
    local ctx=options.build_context(caster); ctx.condition_trace={}
    local payload={action_kind="attack",action_id="attack",target_team="enemy"}
    payload[(target and "target_filter_1_" or "use_condition_1_").."type"]=kind
    payload[(target and "target_filter_1_" or "use_condition_1_").."value"]=seconds
    local rule=bridge.ruleService:DecodeFlat(payload)
    local passed
    if target then passed=Conditions:EvaluateTargetFilters(rule.target_filters,ctx,target)
    else passed=Conditions:EvaluateUseConditions(rule.use_conditions,ctx) end
    local trace=ctx.condition_trace[1]
    assert(trace.actual==(passed and "true" or "false"),"HUD diagnostic reports actual condition truth")
    assert(trace.expected==seconds,"saved seconds survive observation")
    return passed
end
local function hurt(id,damage) return bridge:OnEntityHurt({entindex_killed=id,damage=damage}) end
assert(not condition("self_recently_damaged",2))
assert(not condition("any_ally_recently_damaged",2))
assert(hurt(1,"15"))
assert(condition("self_recently_damaged",2),"U15 receives engine damage")
assert(not condition("any_ally_recently_damaged",2),"U16 excludes caster")
assert(hurt(3,20))
assert(not condition("any_ally_recently_damaged",2),"enemy damage cannot satisfy U16")
assert(condition("recently_damaged",2,enemy),"target filter shares event memory")
now=12
assert(condition("self_recently_damaged",2),"inclusive N-second boundary")
now=12.01
assert(not condition("self_recently_damaged",2),"expires after N seconds")
assert(not condition("recently_damaged",2,enemy))
assert(hurt(2,7))
assert(condition("any_ally_recently_damaged",2),"other ally damage enables U16")
ally.alive=false; now=12.02
assert(not condition("any_ally_recently_damaged",2),"dead allies are not active allies")
ally.alive=true
bridge:ResetState()
assert(not condition("any_ally_recently_damaged",2),"next battle clears damage memory")
for _,damage in ipairs({0,-1,"invalid",math.huge,0/0}) do assert(not hurt(1,damage)) end
assert(not hurt(99,10)); assert(not hurt(-1,10)); assert(not hurt(1.5,10))
gm.phase="setup"; assert(not hurt(1,10)); gm.phase="fight"
assert(not condition("self_recently_damaged",2),"invalid and preparation events leave no history")
-- The production game event must call this bridge; a disconnected collector
-- reproduced the original always-false U15/U16 failure despite scoreboard damage.
local file=assert(io.open(root.."/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua","r"))
local source=file:read("*a"); file:close()
local handler=assert(source:match("function CDota2RpgDemo:OnEntityHurt%(event%)(.-)\nfunction CDota2RpgDemo:"))
assert(handler:find("self.tacticBridge:OnEntityHurt(event)",1,true),"entity_hurt must feed tactics combat memory")
print("PASS: U15/U16 event -> bridge -> decoded condition -> observation; boundaries, teams, expiry, reset, invalid damage")
