-- Reproduces readonly 20260910 native metadata; all orders and UnitFilter are mocks.
local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES=524288
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1; DOTA_UNIT_TARGET_TEAM_ENEMY=2
DOTA_UNIT_TARGET_TEAM_BOTH=3; DOTA_UNIT_TARGET_TEAM_CUSTOM=4
DOTA_UNIT_TARGET_HERO=1; DOTA_UNIT_TARGET_BASIC=2; DOTA_UNIT_TARGET_CUSTOM=128
DOTA_UNIT_ORDER_CAST_TARGET=101; UF_SUCCESS=0
local mt={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},mt) end
mt.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local function unit(id,x,team,kind)
    local u={id=id,x=x,team=team,kind=kind or 1}
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return Vector(self.x) end
    function u:IsNull() return self.invalid or false end
    function u:IsAlive() return not self.dead end
    function u:GetTeamNumber() return self.team end
    function u:GetHullRadius() return 0 end
    function u:IsHero() return self.kind==1 end
    function u:IsRealHero() return self.kind==1 end
    function u:IsRooted() return self.rooted or false end
    function u:GetHealth() return 100 end
    function u:GetMaxHealth() return 100 end
    return u
end
local caster,ally,enemy=unit(1,0,2),unit(2,300,2),unit(3,350,3)
local spell={name="phantom_assassin_phantom_strike",team=4,types=128,flags=0,charges=2,castable=true}
function spell:IsNull() return false end
function spell:GetAbilityName() return self.name end
function spell:GetBehaviorInt() return 524296 end
function spell:GetLevel() return 2 end
function spell:GetCastRange() return 750 end
function spell:GetAbilityTargetTeam() return self.team end
function spell:GetAbilityTargetType() return self.types end
function spell:GetAbilityTargetFlags() return self.flags end
function spell:GetMaxAbilityCharges() return 2 end
function spell:GetCurrentAbilityCharges() return self.charges end
function spell:IsCooldownReady() return false end -- charge restoration is running
function spell:IsFullyCastable() return self.castable end
function spell:entindex() return 99 end
caster.FindAbilityByName=function(_,name) return name==spell.name and spell or nil end
local last
UnitFilter=function(t,team,types,flags,casterTeam)
    last={team=team,types=types,flags=flags}
    local friendly=t.team==casterTeam
    -- Observed CUSTOM masks reject allies with UF_FAIL_FRIENDLY and enemies
    -- with UF_FAIL_ENEMY before type filtering can succeed.
    if team==4 then return friendly and 1 or 2 end
    if (friendly and team==2) or (not friendly and team==1) then return friendly and 1 or 2 end
    if types~=3 and types~=t.kind or t.kind>2 then return 3 end
    if t.invulnerable and flags~=8 or t.outOfGame or t.magicImmune then return 4 end
    return 0
end
assert(UnitFilter(enemy,4,128,0,2)==2 and UnitFilter(ally,4,128,0,2)==1)
assert(UnitFilter(enemy,3,3,0,2)==0)
GameRules={GetGameTime=function() return 1 end}
local orders={}
local gate={Execute=function(_,o) orders[#orders+1]=o; return true end}
local Adapter=require("tactics/action_adapter")
local adapter=Adapter.new(gate)
local function spec() return assert(adapter:Resolve(caster,{kind="ability",name=spell.name},{})) end
local s=spec()
assert(s.cast_type=="unit" and s.cast_range==750)
for _,t in ipairs({ally,enemy,unit(4,100,2,2),unit(5,100,3,2)}) do
    assert(adapter:IsValidTarget(caster,s,t))
    assert(last.team==3 and last.types==3 and last.flags==0)
end
assert(not adapter:IsValidTarget(caster,s,caster),"PA cannot jump to itself")
assert(not adapter:IsValidTarget(caster,s,unit(6,100,3,4)),"buildings excluded")
for _,state in ipairs({"dead","invalid","invulnerable","outOfGame","magicImmune"}) do
    enemy[state]=true
    assert(not adapter:IsValidTarget(caster,s,enemy),state)
    enemy[state]=nil
end
spell.flags=8; enemy.invulnerable=true
assert(adapter:IsValidTarget(caster,s,enemy) and last.flags==8,"native flags passed through")
spell.flags=0; enemy.invulnerable=nil
spell.CastFilterResultTarget=function() return 1 end
assert(not adapter:IsValidTarget(caster,s,enemy),"native custom filter can reject")
spell.CastFilterResultTarget=function() error("native filter failed") end
assert(not adapter:IsValidTarget(caster,s,enemy))
spell.CastFilterResultTarget=function() return 0 end
assert(adapter:IsValidTarget(caster,s,enemy))
spell.CastFilterResultTarget=nil
-- Ordinary PA metadata remains authoritative, independently per field.
spell.team=2; assert(not adapter:IsValidTarget(caster,s,ally)); assert(adapter:IsValidTarget(caster,s,enemy))
spell.team=4; spell.types=1
assert(not adapter:IsValidTarget(caster,s,unit(7,100,3,2)))
spell.types=128
spell.name="unreviewed_custom_skill"
assert(not adapter:IsValidTarget(caster,s,enemy) and last.team==4 and last.types==128)
spell.name="ordinary_skill"; spell.team=1; spell.types=1
assert(adapter:IsValidTarget(caster,s,ally) and not adapter:IsValidTarget(caster,s,enemy))
assert(adapter:IsValidTarget(caster,s,caster),"self policy must not be global")
spell.name="phantom_assassin_phantom_strike"; spell.team=4; spell.types=128
-- Exercise the full engine, including candidate filtering before order validation.
local Engine=require("tactics/tactic_engine")
local rule={action={kind="ability",logical_id=spell.name,name=spell.name},
    target={team="enemy",types={"hero","monster","summon"}},target_filters={},
    target_priorities={{type="nearest"}},use_conditions={},approach="range_only"}
local engine=Engine.new({order_gate=gate,get_phase=function() return "FIGHT" end,
    get_battle_units=function() return {caster} end,get_rules=function() return {rule} end,
    build_context=function() return {get_candidates=function(_,_,target)
        return target.team=="ally" and {caster,ally} or {enemy}
    end} end})
local function attempt(expected)
    orders={}; engine:Reset()
    rule.action.logical_id=spell.name; rule.action.name=spell.name
    local ok,reason=engine:TryRule(caster,engine:GetState(caster),engine:BuildContext(caster,1),rule,1)
    assert((ok==true)==expected,tostring(reason))
    if expected then
        assert(#orders==1 and orders[1].OrderType==101 and orders[1].AbilityIndex==99)
        assert(orders[1].UnitIndex==1 and orders[1].Queue==false)
        assert(orders[1].TargetIndex==(rule.target.team=="ally" and 2 or 3))
    else assert(#orders==0,"rejection must not issue an order") end
end
attempt(true) -- two available charges despite restoration cooldown
rule.target.team="ally"; attempt(true); rule.target.team="enemy"
enemy.x=1000; attempt(false); enemy.x=750; attempt(true); enemy.x=350
caster.rooted=true; attempt(false)
local ok,reason=adapter:Issue(caster,s,enemy,{})
assert(not ok and reason=="caster_rooted")
caster.rooted=false
spell.charges=0; attempt(false)
ok,reason=adapter:CanExecute(caster,s,{})
assert(not ok and reason=="no_charges")
spell.charges=1; attempt(true)
spell.castable=false; attempt(false); spell.castable=true
spell.CastFilterResultTarget=function() return 1 end; attempt(false)
spell.CastFilterResultTarget=nil
spell.name="unreviewed_custom_skill"; attempt(false)
print("PASS: Phantom Strike full-engine CUSTOM masks, native mock orders, teams/types/self/flags/filter/range/root/charges")
