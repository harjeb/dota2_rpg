-- Reproduce logged Soul Rip rules through the real decoder/engine. Native
-- metadata/UnitFilter outcomes come from read-only queries; orders are mocks.
local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1;DOTA_UNIT_TARGET_TEAM_ENEMY=2
DOTA_UNIT_TARGET_TEAM_BOTH=3;DOTA_UNIT_TARGET_TEAM_CUSTOM=4
DOTA_UNIT_TARGET_HERO=1;DOTA_UNIT_TARGET_BASIC=2;DOTA_UNIT_TARGET_CUSTOM=128
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=8;DOTA_UNIT_ORDER_CAST_TARGET=101;UF_SUCCESS=0
local mt={}
function Vector(x,y,z)return setmetatable({x=x,y=y or 0,z=z or 0},mt)end
mt.__sub=function(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
mt.__index={Length2D=function(v)return math.sqrt(v.x*v.x+v.y*v.y)end}
local function unit(id,x,team,kind)
    local u={id=id,x=x,team=team,kind=kind or 1,hp=100}
    function u:entindex()return self.id end
    function u:GetAbsOrigin()return Vector(self.x)end
    function u:GetTeamNumber()return self.team end
    function u:IsNull()return self.invalid or false end
    function u:IsAlive()return not self.dead end
    function u:IsHero()return self.kind==1 end
    function u:IsRealHero()return self.kind==1 end
    function u:GetHealth()return self.hp end
    function u:GetMaxHealth()return 100 end
    function u:GetHullRadius()return 0 end
    return u
end
local caster,ally,enemy=unit(1,0,2),unit(2,300,2),unit(3,350,3)
local spell={name="undying_soul_rip",team=4,types=128,flags=0,ready=true,level=4}
function spell:IsNull()return false end
function spell:GetAbilityName()return self.name end
function spell:GetBehaviorInt()return 8 end
function spell:GetLevel()return self.level end
function spell:GetCastRange()return 750 end
function spell:GetAbilityTargetTeam()return self.team end
function spell:GetAbilityTargetType()return self.types end
function spell:GetAbilityTargetFlags()return self.flags end
function spell:IsCooldownReady()return self.ready end
function spell:IsFullyCastable()return self.castable~=false end
function spell:entindex()return 99 end
function caster:FindAbilityByName(name)return name==spell.name and spell or nil end
local masks
UnitFilter=function(target,team,types,flags,casterTeam)
    masks={team=team,types=types,flags=flags}
    local friendly=target.team==casterTeam
    if team==4 or friendly and team==2 or not friendly and team==1 then return friendly and 1 or 2 end
    if types~=3 and types~=target.kind or target.kind>2 then return 3 end
    if target.invulnerable and flags~=8 then return 18 end
    if target.outOfGame then return 20 end
    return 0
end
assert(UnitFilter(caster,4,128,0,2)==1 and UnitFilter(caster,3,3,0,2)==0)
GameRules={GetGameTime=function()return 1 end}
local orders={}
local gate={Execute=function(_,order)orders[#orders+1]=order;return true end}
local service=require("tactics/rule_service").new({get_phase=function()return "PREPARE"end,
    is_roster_hero=function()return true end,is_action_allowed=function()return true end,state={rules={}}})
local rule=service:DecodeFlat({enabled=1,action_kind="ability",action_id=spell.name,action_name=spell.name,
    target_team="self",target_types="hero",approach="range_only",use_condition_1_type="self_hp_pct_lte",
    use_condition_1_value=.8,target_priority_1_type="nearest"})
local allies,enemies={caster,ally},{enemy}
local engine=require("tactics/tactic_engine").new({order_gate=gate,get_phase=function()return "FIGHT"end,
    get_battle_units=function()return {caster}end,get_rules=function()return {rule}end,
    build_context=function()return {get_candidates=function(_,_,target)
        if target.team=="self" then return {caster}end
        return target.team=="ally" and allies or enemies
    end}end})
local function attempt(target,expectedReason)
    orders={};engine:Reset()
    local ok,reason=engine:TryRule(caster,engine:GetState(caster),engine:BuildContext(caster,1),rule,2)
    if target then
        assert(ok,tostring(reason))
        assert(#orders==1 and orders[1].OrderType==101 and orders[1].AbilityIndex==99)
        assert(orders[1].UnitIndex==1 and orders[1].TargetIndex==target.id and orders[1].Queue==false)
        assert(masks.team==3 and masks.types==3 and masks.flags==spell.flags)
    else
        assert(not ok and #orders==0,"rejected rule must not issue orders")
        if expectedReason then assert(reason==expectedReason,tostring(reason))end
    end
end
attempt(nil,"use_condition_failed:self_hp_pct_lte")
caster.hp=80;attempt(caster) -- exact threshold; before fix: no_legal_target
caster.hp=50;attempt(caster)
rule.target.team="ally";attempt(caster) -- nearest ally includes self
rule.target_filters={{type="exclude_self"}};attempt(ally)
caster.hp=81;ally.hp=10;attempt(nil,"use_condition_failed:self_hp_pct_lte") -- condition measures caster
caster.hp=80;rule.target_filters={};rule.target.team="enemy";attempt(enemy)
for _,target in ipairs({ally,enemy,unit(4,100,2,2),unit(5,100,3,2)})do
    rule.target.team=target.team==2 and "ally" or "enemy";allies={target};enemies={target};attempt(target)
end
rule.target.team="enemy";enemies={enemy}
for _,state in ipairs({"invalid","dead","invulnerable","outOfGame"})do
    enemy[state]=true;attempt(nil,"no_legal_target");enemy[state]=nil
end
enemy.kind=4;attempt(nil,"no_legal_target");enemy.kind=1 -- no broad building/Tombstone fallback
spell.flags=8;enemy.invulnerable=true;attempt(enemy);spell.flags=0;enemy.invulnerable=nil
enemy.x=1000;attempt(nil,"no_target_in_range");enemy.x=750;attempt(enemy);enemy.x=350
spell.ready=false;attempt(nil,"cooldown");spell.ready=true
spell.castable=false;attempt(nil);spell.castable=true
spell.level=0;attempt(nil,"ability_unlearned");spell.level=4
spell.CastFilterResultTarget=function()return 1 end;attempt(nil,"no_legal_target")
spell.CastFilterResultTarget=function()error("filter error")end;attempt(nil,"no_legal_target")
spell.CastFilterResultTarget=function()return 0 end;attempt(enemy);spell.CastFilterResultTarget=nil
-- Final adapter and editor use the same mapping; ordinary fields remain authoritative.
local adapter=engine.actions
local spec=assert(adapter:Resolve(caster,{kind="ability",name=spell.name},{}))
assert(adapter:IsValidTarget(caster,spec,caster))
spell.team=2;assert(not adapter:IsValidTarget(caster,spec,ally))
spell.team=4;spell.types=1;assert(not adapter:IsValidTarget(caster,spec,unit(6,100,3,2)))
spell.types=128
local cap=require("tactics/ability_capability").Describe(caster,spell,rule.action,{runtime=true})
assert(cap.teams.self==1 and cap.teams.ally==1 and cap.teams.enemy==1 and cap.types.hero==1 and cap.types.monster==1)
spell.name="unreviewed_custom_skill"
assert(not adapter:IsValidTarget(caster,spec,caster) and masks.team==4 and masks.types==128)
spell.name="phantom_assassin_phantom_strike";assert(not adapter:IsValidTarget(caster,spec,caster))
print("PASS: Soul Rip logged HP/ally/self rules, full-engine orders, native legality, flags, range, readiness and shared capabilities (mocked)")
