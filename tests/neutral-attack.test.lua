local root=arg and arg[1] or 'game/dota_addons/dota2_rpg/scripts/vscripts'
package.path=root..'/?.lua;'..package.path
local Engine=require('tactics/tactic_engine')
local Runtime=require('issue_fixes/enemy_runtime')
local Compat=require('issue_fixes/compat')
local Attack=require('tactics/neutral_attack')
DOTA_UNIT_ORDER_ATTACK_TARGET=4;DOTA_UNIT_ORDER_MOVE_TO_POSITION=1;DOTA_UNIT_ORDER_ATTACK_MOVE=3
DOTA_UNIT_ORDER_MOVE_TO_TARGET=2;DOTA_UNIT_TARGET_TEAM_ENEMY=2
local vm={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local time=0
GameRules={GetGameTime=function() return time end}
local entities={}
local function unit(id,team,x,hp)
    local u={id=id,team=team,x=x,y=0,hp=hp or 100,alive=true,idle=false}
    function u:entindex() return self.id end
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:GetUnitName() return self.name or 'npc_dota_hero_axe' end
    function u:GetTeamNumber() return self.team end
    function u:GetAbsOrigin() return Vector(self.x,self.y,0) end
    function u:IsRealHero() return self.name==nil end
    function u:IsHero() return self:IsRealHero() end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return 100 end
    function u:GetAttackCapability() return 1 end
    function u:Script_GetAttackRange() return 150 end
    function u:GetSecondsPerAttack() return 1 end
    function u:GetAttackTarget() return self.target end
    function u:GetForceAttackTarget() return self.forced end
    function u:SetForceAttackTarget(t) self.forced=t end
    function u:IsIdle() return self.idle end
    function u:IsStunned() return self.stunned or false end
    function u:IsRooted() return self.rooted or false end
    function u:IsCommandRestricted() return self.restricted or false end
    entities[id]=u
    return u
end
EntIndexToHScript=function(id) return entities[id] end
local creep=unit(1,3,0);creep.name='npc_dota_neutral_centaur_khan'
local a,b=unit(2,2,1000,10),unit(3,2,100,100)
local orders={};local accepted=true
local gate={Execute=function(_,order)
    orders[#orders+1]={order=order,time=time}
    if accepted then creep.idle=false end
    return accepted
end}
local phase='FIGHT'
local attackRule={action={kind='attack'},target={team='enemy'},use_conditions={},target_filters={},
    target_priorities={{type='lowest_hp_pct'}},approach='allow_approach'}
local rules={attackRule}
local engine=Engine.new({order_gate=gate,get_phase=function() return phase end,
    get_battle_units=function() return {creep} end,get_rules=function() return rules end,
    build_context=function() return {get_candidates=function() return {a,b} end} end})
local game={phase='fight',tacticBridge={tacticEngine=engine}}
local compat=Compat.new(game)
local runtime=Runtime.new({get_phase=function() return phase end,
    has_tactic_order=function(u) return compat:HasTacticOrder(u) end,
    execute_order=function(o) return gate:Execute(o) end})
runtime:RegisterStage({}, {creep});runtime:Start({a,b},Vector(0,0,0))
assert(#orders==1 and creep.forced==b,'fallback starts with nearest B')
local function tick(dt,dx,dy)
    time=time+(dt or .2);creep.x=creep.x+(dx or 0);creep.y=creep.y+(dy or 0)
    engine:EvaluateUnit(creep,engine:GetState(creep),time)
    runtime:Think()
end
tick()
assert(#orders==2 and creep.forced==a and creep.rpg_fallback_force_target==nil,'tactic A atomically replaces fallback B')
for _=1,20 do tick(.2,20) end
assert(#orders==2,'real engine and runtime preserve a progressing attack approach across chase deadlines')
creep.x=900;b.x=920
for _=1,15 do creep.target=a;tick() end
assert(#orders==2 and creep.forced==a,'in-range attack remains owned after chase is cleared; nearer B cannot steal it')
assert(compat:HasTacticOrder(creep),'compat recognizes persistent tactic attacks')

-- GetAttackTarget=nil and non-idle is also a real return/lost-intent state.
creep.target=nil
local before=#orders
for _=1,9 do tick(.25,-20) end
assert(#orders==before+1 and creep.forced==a,'sustained retreat recovers once after a grace interval, preserving tactic A')
assert(orders[#orders].time-orders[#orders-1].time>=1.5,'recovery does not repeat every evaluation tick')

-- Native control pauses recovery, then ordinary progress resumes.
creep.stunned=true;before=#orders
for _=1,10 do tick(.25,-5) end
assert(#orders==before,'stun is never countered with attack spam')
creep.stunned=false;tick(.25,20)
assert(creep.forced==a,'tactic target remains available after stun')
-- Source advances even as the target flees faster; growing distance alone is not retreat.
before=#orders
for _=1,12 do a.x=a.x+40;tick(.2,20) end
assert(#orders==before,'a faster fleeing target does not trigger recovery')
-- A lateral obstacle detour still progresses.
for _=1,8 do tick(.2,0,10) end
assert(#orders<=before+1,'detours do not create per-tick order spam')

-- Deliberate move/wait releases the force target and owns its bounded interval.
creep.x=a.x-100;creep.y=0;creep.target=a
local state=engine:GetState(creep)
state.chase=nil
state.events.attack={time=time-.1,target=a};state.attack_order_time=nil
attackRule.action.positioning_mode='fixed_distance';attackRule.action.positioning_distance=300
attackRule.action.positioning_tolerance=10
before=#orders;tick(.05)
assert(#orders==before+1 and orders[#orders].order.OrderType==1 and creep.forced==nil,'positioning releases forced attack before moving')
assert(compat:HasTacticOrder(creep),'bounded positioning blocks fallback')
attackRule.action.positioning_mode=nil
rules={{action={kind='wait',duration=.8},use_conditions={},target_filters={}},attackRule}
tick(.2);before=#orders
assert(creep.forced==nil and compat:HasTacticOrder(creep),'wait owns its interval without fallback')
tick(.2);assert(#orders==before,'waiting unit receives no fallback order')
rules={attackRule};tick(.9)
assert(creep.forced==a,'attack resumes after wait expires')

-- Submission failure releases ownership and retries; successful submission is
-- still monitored for subsequent native loss (tested above), not treated as ACK.
Attack.Release(creep);engine:Reset();accepted=false
before=#orders;tick(.3)
assert(#orders>before and creep.forced==nil and creep.rpg_tactic_force_target==nil,'gate rejection rolls back ownership')
accepted=true;tick(.3);assert(creep.forced==a,'a later accepted order recovers')
a.alive=false;tick(.3)
assert(creep.forced==b and creep.rpg_fallback_force_target==nil,'target death reselects without dual ownership')
local original=engine.states[creep.id].unit
engine.states[creep.id].unit=a
assert(not compat:HasTacticOrder(creep),'reused entity index does not inherit busy state')
engine.states[creep.id].unit=original
phase='PREPARE';engine:Think();runtime:Stop()
assert(creep.forced==nil and creep.rpg_neutral_attack_intent==nil,'reset releases native and Lua attack ownership')
assert(not compat:HasTacticOrder(creep),'preparation never retains attack ownership')

-- A permanently lost attack gets a finite retry burst and a re-evaluation gap.
phase='FIGHT';a.alive=true;creep.x=0;creep.target=nil
local submits=0;local blocked=false
for i=0,40 do
    time=30+i*.25;creep.x=-i*10
    local ok,reason=Attack.Submit(creep,a,'tactic',function() submits=submits+1;return true end)
    if reason=='attack_stalled' or reason=='attack_recovery_wait' then blocked=true end
end
assert(blocked and submits<=7,'stalled intent has bounded retries and yields for target re-evaluation')
Attack.Release(creep)
print('PASS: interleaved real engine/adapter/compat/runtime, stable neutral attacks, single ownership and bounded non-idle recovery')
