-- Native metadata and logged wire rule reproduced with mocked units/orders.
local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1;DOTA_UNIT_TARGET_TEAM_ENEMY=2
DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_TEAM_CUSTOM=4
DOTA_UNIT_TARGET_HERO=1;DOTA_UNIT_TARGET_BASIC=2;DOTA_UNIT_TARGET_CUSTOM=128
DOTA_UNIT_ORDER_CAST_TARGET=101;UF_SUCCESS=0
local mt={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},mt) end
mt.__sub=function(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
mt.__index={Length2D=function(v)return math.sqrt(v.x*v.x+v.y*v.y)end}
local function unit(id,x,team,kind)
    local u={id=id,x=x,team=team,kind=kind or 1}
    function u:entindex()return self.id end
    function u:GetAbsOrigin()return Vector(self.x)end
    function u:GetTeamNumber()return self.team end
    function u:IsNull()return self.invalid or false end
    function u:IsAlive()return not self.dead end
    function u:IsHero()return self.kind==1 end
    function u:IsCreep()return self.kind==2 end
    function u:IsBuilding()return self.kind==4 end
    function u:IsAncient()return self.ancient or false end
    function u:IsInvulnerable()return self.invulnerable or false end
    function u:IsOutOfGame()return self.outOfGame or false end
    function u:GetHealth()return 100 end
    function u:GetMaxHealth()return 100 end
    function u:GetHullRadius()return 0 end
    return u
end
local tiny,enemy,ally,landing=unit(1,0,2),unit(2,190,3,2),unit(3,400,2),unit(4,700,3)
local spell={name="tiny_toss",team=4,types=128,flags=0,level=4,ready=true}
function spell:IsNull()return false end
function spell:GetAbilityName()return self.name end
function spell:GetBehaviorInt()return 268435496 end
function spell:GetLevel()return self.level end
function spell:GetCastRange()return 1000 end
function spell:GetSpecialValueFor(key)return key=="grab_radius" and 300 or 0 end
function spell:GetAbilityTargetTeam()return self.team end
function spell:GetAbilityTargetType()return self.types end
function spell:GetAbilityTargetFlags()return self.flags end
function spell:IsCooldownReady()return self.ready end
function spell:IsFullyCastable()return self.ready end
function spell:entindex()return 99 end
function tiny:FindAbilityByName(name)return name==spell.name and spell or nil end
local nativeMasks
UnitFilter=function(t,team,types,flags,casterTeam)
    nativeMasks={team=team,types=types,flags=flags}
    local friendly=t.team==casterTeam
    if team==4 then return friendly and 1 or 2 end -- observed native failures
    if friendly and team==2 or not friendly and team==1 then return friendly and 1 or 2 end
    if types~=3 and types~=t.kind or t.kind>2 then return 3 end
    if t.invulnerable or t.outOfGame then return 18 end
    return 0
end
assert(UnitFilter(enemy,4,128,0,2)==2 and UnitFilter(enemy,3,3,0,2)==0)
local nearby={tiny,enemy,ally,landing}
FindUnitsInRadius=function()return nearby end
GameRules={GetGameTime=function()return 1 end}
local orders={}
local gate={Execute=function(_,order)orders[#orders+1]=order;return true end}
local Service=require("tactics/rule_service")
local Engine=require("tactics/tactic_engine")
local service=Service.new({get_phase=function()return "PREPARE"end,is_roster_hero=function()return true end,
    is_action_allowed=function()return true end,state={rules={}}})
local rule=service:DecodeFlat({action_kind="ability",action_id="tiny_toss",action_name="tiny_toss",enabled=1,
    target_team="enemy",target_types="hero,monster,summon",approach="range_only",
    use_condition_4_type="tiny_grab_is_enemy",target_priority_1_type="nearest"})
local candidates={enemy,landing}
local engine=Engine.new({order_gate=gate,get_phase=function()return "FIGHT"end,
    get_battle_units=function()return {tiny}end,get_rules=function()return {rule}end,
    build_context=function()return {get_candidates=function()return candidates end}end})
local function attempt(expectedTarget,expectedReason)
    orders={};engine:Reset()
    local ok,reason=engine:TryRule(tiny,engine:GetState(tiny),engine:BuildContext(tiny,1),rule,1)
    if expectedTarget then
        assert(ok,tostring(reason))
        assert(#orders==1 and orders[1].OrderType==101 and orders[1].AbilityIndex==99)
        assert(orders[1].UnitIndex==1 and orders[1].TargetIndex==expectedTarget.id and orders[1].Queue==false)
        assert(nativeMasks.team==3 and nativeMasks.types==3 and nativeMasks.flags==spell.flags)
    else
        assert(not ok and #orders==0,"rejected rule must not issue orders")
        if expectedReason then assert(reason==expectedReason,tostring(reason))end
    end
end
attempt(enemy) -- no invented distinct-unit requirement; actual native cast remains unverified
rule.target_priorities={{type="farthest"}};attempt(landing)
-- Grab condition cannot choose a farther enemy over the actual nearest ally.
ally.x=100;attempt(nil,"use_condition_failed:tiny_grab_is_enemy")
rule.use_conditions={{type="tiny_grab_is_ally"}};attempt(landing)
ally.x=400;rule.use_conditions={{type="tiny_grab_is_enemy"}}
-- Landing selection may independently point at an allied unit.
candidates={ally};rule.target.team="ally";attempt(ally)
candidates={enemy,landing};rule.target.team="enemy";rule.target_priorities={{type="nearest"}}
-- No grab, ambiguous nearest and protected grab candidates stay blocked.
enemy.x=350;attempt(nil,"use_condition_failed:tiny_grab_is_enemy");enemy.x=190
ally.x=190;attempt(nil,"use_condition_failed:tiny_grab_is_enemy");ally.x=400
enemy.ancient=true;attempt(nil,"use_condition_failed:tiny_grab_is_enemy");enemy.ancient=false
-- Landing filters and range remain independent of the valid grab.
candidates={landing};landing.x=1100;attempt(nil,"no_target_in_range");landing.x=700
for _,field in ipairs({"invalid","dead","invulnerable","outOfGame"})do
    landing[field]=true;attempt(nil,"no_legal_target");landing[field]=nil
end
landing.kind=4;attempt(nil,"no_legal_target");landing.kind=1
spell.CastFilterResultTarget=function()return 2 end;attempt(nil,"no_legal_target")
spell.CastFilterResultTarget=function()error("native filter failed")end;attempt(nil,"no_legal_target")
spell.CastFilterResultTarget=function()return 0 end;attempt(landing);spell.CastFilterResultTarget=nil
rule.target_filters={{type="hp_pct_lte",value=.5}};attempt(nil);rule.target_filters={}
spell.ready=false;attempt(nil);spell.ready=true
spell.level=0;attempt(nil);spell.level=4
spell.flags=8;attempt(landing);spell.flags=0
-- Only CUSTOM fields of the reviewed action are translated.
local adapter=engine.actions
local spec=assert(adapter:Resolve(tiny,{kind="ability",name=spell.name},{}))
spell.team=2
assert(not adapter:IsValidTarget(tiny,spec,ally) and adapter:IsValidTarget(tiny,spec,enemy))
spell.team=4;spell.types=1
assert(not adapter:IsValidTarget(tiny,spec,enemy) and adapter:IsValidTarget(tiny,spec,landing))
spell.types=128;spell.name="unreviewed_custom_skill"
assert(not adapter:IsValidTarget(tiny,spec,enemy) and nativeMasks.team==4 and nativeMasks.types==128)
print("PASS: Tiny Toss real wire/engine CUSTOM masks, grab/landing separation, nearest ally, tie, range, native guards and captured orders (mocked)")
