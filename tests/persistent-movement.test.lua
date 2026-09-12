local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local Engine=require("tactics/tactic_engine")
local Rules=require("tactics/rule_service")
local Contract=require("tactics/movement_contract")
local Snapshot=require("tactics/rule_snapshot")
require("tactics/tactic_bridge")
local Bridge=TacticBridge
local time,phase=0,"FIGHT"
GameRules={GetGameTime=function() return time end}
DOTA_UNIT_ORDER_MOVE_TO_POSITION=1; DOTA_UNIT_ORDER_ATTACK_TARGET=4; DOTA_UNIT_ORDER_STOP=21
DOTA_UNIT_ORDER_CAST_TARGET=6; DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
MODIFIER_EVENT_ON_ATTACK=1; MODIFIER_EVENT_ON_ATTACK_START=2; MODIFIER_EVENT_ON_ABILITY_EXECUTED=3
LUA_MODIFIER_MOTION_NONE=0
bit={band=function(a,b) return a==b and b or 0 end}
function class(t) return t end
function IsServer() return true end
function LinkLuaModifier() end
require("modifiers/modifier_rpg_tactics_events")
local vm={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local function unit(id,x)
    local u={id=id,p=Vector(x,0,0),hp=100,mods={},range=600,interval=1}
    function u:GetAcquisitionRange() return self.acquisition end
    function u:GetIdleAcquire() return self.idle end
    function u:SetIdleAcquire(value) self.idle=value end
    function u:SetAcquisitionRange(value) self.acquisition=value end
    function u:entindex() return self.id end
    function u:IsNull() return false end
    function u:IsAlive() return self.hp>0 end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return 100 end
    function u:GetUnitName() return "npc_dota_hero_weaver" end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return self.hull or 24 end
    function u:GetTeamNumber() return self.id==1 and 2 or 3 end
    function u:HasModifier(n) return self.mods[n] == true end
    function u:IsRooted() return self.root end
    function u:IsStunned() return self.stun end
    function u:IsCommandRestricted() return self.restricted end
    function u:IsCurrentlyHorizontalMotionControlled() return self.motion end
    function u:IsTaunted() return self.taunted end
    function u:IsFeared() return self.feared end
    function u:IsChanneling() return self.channel end
    function u:GetCurrentActiveAbility() return self.active end
    function u:Script_GetAttackRange() return self.range end
    function u:GetSecondsPerAttack(ignoreTemporary)
        assert(ignoreTemporary==false,"native interval includes current temporary attack speed")
        return self.interval
    end
    function u:AddNewModifier(_,_,name)
        self.observer=setmetatable({GetParent=function() return self end},{__index=modifier_rpg_tactics_events})
        self.mods[name]=true
    end
    function u:RemoveModifierByName(name) self.mods[name]=nil; self.observer=nil end
    return u
end
local caster,enemy,other=unit(1,0),unit(2,400),unit(3,900)
local spell={}
function spell:GetAbilityName() return "weaver_shukuchi" end
function spell:GetBehaviorInt() return 8 end
function spell:GetLevel() return 1 end
function spell:GetCastRange() return 600 end
function spell:IsFullyCastable() return true end
function spell:IsCooldownReady() return true end
function spell:entindex() return 99 end
function spell:CastFilterResultTarget() return 0 end
function caster:FindAbilityByName() return spell end
local service=Rules.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function() return true end,state={rules={}},get_hero_key=function() return "weaver" end})
local function movement(extra)
    local payload={rule_id="move",action_kind="move",action_id="sustained_move",target_team="enemy",target_types="hero",
        movement_mode="follow",movement_buff="modifier_weaver_shukuchi",movement_duration="8",movement_distance="200",
        movement_retarget="0",movement_loop="0",movement_interruptible="0",movement_direction="auto",
        target_priority_1_type="nearest"}
    for k,v in pairs(extra or {}) do payload[k]=v end
    local r=service:DecodeFlat(payload); assert(service:ValidateRule(0,caster,r)); return r
end
local attack=service:DecodeFlat({rule_id="attack",action_kind="attack",action_id="basic_attack",target_team="enemy",target_types="hero",target_priority_1_type="nearest"})
local ability=service:DecodeFlat({rule_id="spell",action_kind="ability",action_id="weaver_shukuchi",action_name="weaver_shukuchi",target_team="enemy",target_types="hero",target_priority_1_type="nearest"})
local rules,orders={},{ }
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o end},get_phase=function() return phase end,
    get_battle_units=function() return {caster} end,get_rules=function() return rules end,
    build_context=function() return {get_candidates=function() return {enemy,other} end,
        get_target_actor=function(key) if key=="ch05:enemy:npc_dota_hero_weaver:0" then return enemy end end} end})
function engine:Debug() end
local function reset(r)
    engine:Reset(); orders={}; rules=r; time=0; phase="FIGHT"
    caster.idle=true; caster.acquisition=4000; caster.hp=100
    caster.mods={}; caster.p=Vector(0,0,0); caster.root=false; caster.stun=false; caster.channel=false; caster.restricted=false; caster.active=nil
    enemy.hp=100; enemy.p=Vector(400,0,0); other.hp=100; other.p=Vector(900,0,0); GridNav=nil
    attack.action.positioning_mode=nil; attack.use_conditions={}
    return engine:GetState(caster)
end
local function tick(t)
    time=t; orders={}; engine:EvaluateUnit(caster,engine:GetState(caster),time); return orders[#orders]
end
local function enter() caster.mods.modifier_weaver_shukuchi=true end
local function cast() caster.observer:OnAbilityExecuted({unit=caster,ability=spell}) end
local function release(target) caster.observer:OnAttack({attacker=caster,target=target or enemy}) end
local function windup() caster.observer:OnAttackStart({attacker=caster,target=enemy}) end
local r=movement(); local s=reset({r,ability,attack})
assert(tick(0).OrderType==6 and not s.movement,"buff absent falls through to ordinary skill")
enter(); assert(tick(.3).OrderType==1 and s.movement,"buff enter starts native move")
assert(tick(.6).OrderType==1 and #orders==1,"exclusive session blocks available skill and attack")
other.p=Vector(50,0,0); tick(.9); assert(s.movement.target==enemy,"no arbitrary retarget")
caster.mods.modifier_weaver_shukuchi=nil
assert(tick(1.2).OrderType==6 and not s.movement,"buff exit runs next rule same tick")
other.p=Vector(500,0,0); enter(); tick(1.5); assert(s.movement,"new buff episode re-arms")
enemy.hp=0; assert(tick(1.8).OrderType==6 and not s.movement,"dead locked target exits to next rule")
assert(not s.movement); tick(2.1); assert(not s.movement,"same episode cannot restart on another target")
r=movement({movement_trigger_ability="weaver_shukuchi"}); s=reset({r,ability})
-- Ancient native cast recorded before the rule is first observed is baseline only.
cast(); enter(); tick(0); assert(not s.movement,"ancient native cast cannot trigger")
cast(); tick(.3); assert(s.movement,"new native cast starts movement")
tick(9); assert(not s.movement,"finite timeout")
tick(9.3); assert(not s.movement,"same cast never retriggers after timeout")
cast(); tick(9.6); assert(s.movement,"later native cast re-arms")
-- Order history is not a native cast signal.
s=reset({r,ability}); enter(); tick(0); tick(.3); assert(not s.movement,"issued ability orders cannot impersonate executed casts")
-- All modes use real points, with clockwise/counterclockwise and finite traversal.
for _,mode in ipairs({"follow","pass","orbit","cycle"}) do
    r=movement({movement_mode=mode,movement_direction="cw"}); s=reset({r,attack}); enter()
    local order=tick(0); assert(order.OrderType==1 and s.movement,mode.." starts")
    if mode=="orbit" then assert(order.Position.y>0,"clockwise from west points north") end
    if mode=="pass" or mode=="cycle" then
        assert(order.Position.x==600,"first leg crosses target")
        caster.p=order.Position; tick(.3)
        if mode=="pass" then assert(not s.movement,"nonloop pass completes")
        else assert(s.movement and s.movement.target==other and orders[1].Position.x==1100,"cycle crosses a different unvisited target with retarget disabled")
            assert(s.movement.visited[enemy],"completed target handle is visited")
            caster.p=orders[1].Position; tick(.6); assert(not s.movement,"nonloop cycle completes all eligible targets") end
    end
end
r=movement({movement_mode="orbit",movement_direction="ccw",movement_loop="1"}); s=reset({r,attack}); enter()
assert(tick(0).Position.y<0,"counterclockwise geometry")
for i=1,18 do caster.p=orders[1].Position; tick(i*.2) end
assert(s.movement,"loop survives full orbit but remains duration capped")
r=movement({movement_mode="orbit"}); s=reset({r,attack}); enter(); tick(0)
for i=1,16 do
    if s.movement then caster.p=orders[#orders].Position; tick(i*.2) end
end
assert(not s.movement,"nonloop orbit completes a revolution")
r=movement({movement_mode="cycle",movement_loop="1",movement_retarget="1"}); s=reset({r,attack}); enter(); tick(0)
other.p=Vector(50,0,0); tick(.3); assert(s.movement.target==enemy,"retarget flag does not change a valid leg for priorities")
enemy.hp=0; tick(.4); assert(s.movement.target==other,"explicit retarget replaces dead target")
for _,control in ipairs({"root","stun","restricted","channel","motion","taunted","feared"}) do
    caster[control]=true; assert(tick(.6)==nil and s.movement,control.." pauses without orders")
    caster[control]=false
end
caster.active={IsInAbilityPhase=function() return true end}; assert(tick(.9)==nil and s.movement,"native cast phase never interrupted")
caster.active=nil; tick(1.2); assert(s.movement)
GridNav={CanFindPath=function() return false end}; tick(1.5); assert(not s.movement,"unreachable path ends session")
r=movement(); s=reset({r,attack}); enter(); tick(0); tick(1.6); assert(not s.movement,"no-progress timeout ends session")
r=movement({movement_duration="0.5"}); s=reset({r,attack}); enter(); tick(0); tick(.6); assert(not s.movement,"authored cap")
-- A visit reset starts another tour, and never repicks the completed target
-- while a different eligible target exists (even when it has lower priority).
r=movement({movement_mode="cycle",movement_loop="1"}); s=reset({r,attack}); enter(); tick(0)
caster.p=orders[1].Position; tick(.2); assert(s.movement.target==other and s.movement.visited[enemy])
other.p=Vector(650,0,0); tick(.3); assert(s.movement.target==other,"leg remains locked while target moves")
caster.p=orders[1].Position; tick(.4)
assert(s.movement.target==enemy and next(s.movement.visited)==nil,"loop clears visits after exhausting candidates")
caster.p=orders[1].Position; tick(.6); assert(s.movement.target==other and s.movement.visited[enemy],"next tour visits different handles")
-- F39 cannot be bypassed by cycling, looping, or death retarget.
for _,loop in ipairs({false,true}) do
    r=movement({movement_mode="cycle",movement_loop=loop and "1" or "0",movement_retarget="1"})
    r.target_filters={{type="specified_enemy",target_actor="ch05:enemy:npc_dota_hero_weaver:0"}}
    s=reset({r,attack}); enter(); tick(0); assert(s.movement.target==enemy)
    caster.p=orders[1].Position; tick(.2)
    if loop then
        assert(s.movement and s.movement.target==enemy,"single F39 target loops without broadening filters")
        enemy.hp=0; tick(.4); assert(not s.movement,"F39 fails closed on death")
    else assert(not s.movement,"F39 tour ends without selecting undesignated enemy") end
end
-- Recheck use conditions and target filters throughout active movement.
r=movement(); r.use_conditions={{type="self_hp_pct_lte",value=.5}}
s=reset({r,attack}); caster.hp=40; enter(); tick(0); assert(s.movement)
caster.hp=100; tick(.2); assert(not s.movement,"active use condition failure ends session")
for _,mode in ipairs({"follow","pass","orbit","cycle"}) do
    for _,retarget in ipairs({false,true}) do
        r=movement({movement_mode=mode,movement_retarget=retarget and "1" or "0"})
        r.target_filters={{type="hp_pct_gte",value=.5}}
        s=reset({r,attack}); enter(); tick(0)
        other.p=Vector(50,0,0); tick(.2); assert(s.movement.target==enemy,"valid target stays locked in "..mode)
        enemy.hp=20; tick(.4)
        assert(retarget and s.movement and s.movement.target==other or not retarget and not s.movement,"filter failure requires explicit retarget in "..mode)
    end
end
-- Auto orbit turns around a blocked segment, including real no-progress stalls.
r=movement({movement_mode="orbit"}); s=reset({r,attack}); enter()
GridNav={CanFindPath=function(_,_,goal) return goal.y>0 end}
assert(tick(0).Position.y>0 and s.movement,"auto reverses blocked initial direction")
GridNav={CanFindPath=function(_,_,goal) return goal.y<0 end}
assert(tick(.2).Position.y<0 and s.movement,"auto alternates when opposite segment blocks")
GridNav=nil; assert(tick(1.8).Position.y>0 and s.movement,"auto reverses after no native movement progress")
GridNav={CanFindPath=function() return false end}; tick(2); assert(not s.movement,"both orbit directions blocked ends session")
r=movement({movement_mode="orbit",movement_direction="ccw"}); s=reset({r,attack}); enter()
GridNav={CanFindPath=function(_,_,goal) return goal.y>0 end}; tick(0); assert(not s.movement,"explicit direction remains explicit")
r=movement({movement_mode="orbit",movement_distance="32"}); s=reset({r,attack}); enter()
caster.hull=80; enemy.hull=90; local orbit=tick(0)
assert((orbit.Position-enemy.p):Length2D()*math.cos(.45/2)>=178-1e-6,"orbit chord clears combined native hulls")
caster.hull=nil; enemy.hull=nil
r=movement({movement_mode="orbit",movement_distance="32"}); s=reset({r,attack}); enter()
caster.p=Vector(400-(48+8)/math.cos(.45/2),0,0); tick(0)
for i=1,5 do tick(i*.2) end
assert(s.movement and s.movement.arc==0,"small orbit cannot accumulate traversal without native displacement")
-- Explicit higher priority interrupt only.
r=movement(); ability.enabled=false; s=reset({ability,r,attack}); enter(); tick(0); ability.enabled=true
assert(tick(.3).OrderType==1 and s.movement,"ordinary higher priority rule remains blocked")
r.action.movement_interruptible=true; assert(tick(.6).OrderType==6 and not s.movement,"explicit emergency interrupt")
-- Acquisition remains suppressed at arrival, through control pauses, and is
-- restored once on every release path without cancelling an interrupting cast.
s=reset({movement(),attack}); enter(); caster.p=Vector(200,0,0)
assert(tick(0).OrderType==21 and s.movement and not caster.idle and caster.acquisition==0,"follow starting inside radius cancels prior attack while suppressing acquisition")
s=reset({movement(),attack}); enter(); tick(0)
assert(caster.idle==false and caster.acquisition==0 and s.events.exclusive_movement and engine:IsExclusiveMovement(caster))
caster.p=Vector(200,0,0); assert(tick(.2).OrderType==21 and s.movement,"follow radius stops only locomotion")
assert(caster.idle==false and caster.acquisition==0,"follow STOP cannot re-enable native attacks")
for _,control in ipairs({"root","stun","restricted","channel","motion","taunted","feared"}) do
    caster[control]=true; tick(.4)
    assert(caster.idle==false and caster.acquisition==0 and s.events.exclusive_movement,"pause keeps exclusivity: "..control)
    caster[control]=false
end
caster.mods.modifier_weaver_shukuchi=nil; tick(.6)
assert(caster.idle and caster.acquisition==4000 and not s.events.exclusive_movement and not engine:IsExclusiveMovement(caster),"buff exit restores native acquisition")
for _,ending in ipairs({"timeout","reset","death","prepare"}) do
    s=reset({movement(),attack}); enter(); tick(0)
    if ending=="timeout" then tick(9)
    elseif ending=="reset" then engine:Reset()
    elseif ending=="death" then caster.hp=0; engine:Think()
    else phase="PREPARE"; engine:Think() end
    assert(not s.movement and not s.events.exclusive_movement,ending.." releases session")
    if ending=="prepare" then assert(caster.idle==false and caster.acquisition==0,"PREPARE stays passive")
    else assert(caster.idle and caster.acquisition==4000,ending.." restores captured range") end
end
r=movement({movement_interruptible="1"}); ability.enabled=false
s=reset({ability,r,attack}); enter(); tick(0); ability.enabled=true; tick(.3)
assert(#orders==1 and orders[1].OrderType==6 and caster.idle and caster.acquisition==4000,"interrupt releases without STOP cancelling cast")
-- A replacement must inherit the first session's saved state, not false/zero.
local replacement=movement(); replacement.id="replacement"; replacement.enabled=false
s=reset({replacement,r,attack}); enter(); tick(0); replacement.enabled=true; tick(.3)
assert(s.movement.rule==replacement and not caster.idle and caster.acquisition==0,"higher movement replaces while acquisition stays disabled")
engine:Reset(); assert(caster.idle and caster.acquisition==4000,"replacement inherits original restore state")
s=reset({movement()}); caster.idle=false; caster.acquisition=321; enter(); tick(0); engine:Reset()
assert(caster.idle==false and caster.acquisition==321,"optional getter preserves original false")
local idleGetter=caster.GetIdleAcquire; caster.GetIdleAcquire=false
s=reset({movement()}); enter(); tick(0); engine:Reset()
assert(caster.idle and caster.acquisition==4000,"missing idle getter uses battle-known true")
caster.GetIdleAcquire=idleGetter
s=reset({movement()}); enter(); tick(0)
local nullGetter=caster.IsNull; caster.IsNull=function() error("deleted native handle") end
assert(pcall(function() engine:Reset() end) and not s.movement and not s.events.exclusive_movement,"invalid native handles clean up safely")
caster.IsNull=nullGetter
-- Kiting requires the production modifier's native OnAttack callback.
s=reset({attack}); attack.action.positioning_mode="attack_range"
assert(tick(0).OrderType==4,"attack order, not movement before release")
windup(); assert(tick(.3).OrderType==4,"windup cannot arm kite")
time=.4; release(); assert(tick(.5).OrderType==1,"native release permits movement in cooldown")
assert(orders[1].Position.x==-160,"uses safety point inside real attack range")
windup(); assert(tick(.6).OrderType==4,"next native windup invalidates old release")
time=.7; release(); caster.interval=.3; assert(tick(.9).OrderType==4,"live attack interval closes release window")
caster.interval=1; time=1; release(); caster.range=700; assert(tick(1.1).Position.x==-260,"live native range minus tolerance")
attack.use_conditions={{type="self_hp_pct_lte",value=.1}}; time=1.2; release(); assert(tick(1.3).OrderType==4,"authored condition gates posture; fallback remains default")
attack.use_conditions={}; time=1.4; release(); caster.channel=true; assert(tick(1.5)==nil,"kite cannot break channel")
caster.channel=false; caster.active={IsInAbilityPhase=function() return true end}; assert(tick(1.6)==nil,"kite cannot break cast phase")
-- The accepted band never extends beyond native attack range.
s=reset({attack}); attack.action.positioning_mode="attack_range"; caster.range=600
caster.p=Vector(-220,0,0); time=0; release(); local safe=tick(.1)
assert(safe.OrderType==1 and safe.Position.x==-160,"R plus half tolerance moves inward")
caster.p=safe.Position; time=.2; release(); assert(tick(.3).OrderType==4,"safety destination permits native attack")
s=reset({attack}); attack.action.positioning_mode="attack_range"
caster.p=Vector(-200,0,0); time=.4; release(); assert(tick(.5).OrderType==4,"exact range remains inside accepted band")
-- Ability posture is standalone, before native cast only.
s=reset({ability}); ability.action.positioning_mode="fixed"; ability.action.positioning_distance=250
assert(tick(0).OrderType==1,"ability posture prepositions")
caster.p=orders[1].Position; assert(tick(.3).OrderType==6,"ability casts once posture reached")
ability.action.positioning_mode="default"
-- Stage/reset cleanup removes observer, session, release and trigger history.
s=reset({movement(),attack}); enter(); tick(0); assert(caster.observer)
phase="SETTLE"; engine:Think(); assert(next(engine.states)==nil and not caster.rpgTacticsEvents and not caster.observer,"stage cleanup")
phase="FIGHT"; s=engine:GetState(caster); assert(not s.movement and not s.events.attack and next(s.events.casts)==nil,"fresh stage history")
-- Full flattened serialization: service sync -> decode, snapshot -> legacy.
r=movement({movement_mode="cycle",movement_retarget="1",movement_loop="1",movement_interruptible="1",movement_direction="ccw",movement_trigger_ability="weaver_shukuchi",positioning_mode="fixed",positioning_distance="500",positioning_tolerance="30"})
local payload
CustomNetTables={SetTableValue=function(_,_,_,p) payload=p end}
service:SyncRule(0,caster,1,r)
local decoded=service:DecodeFlat(payload)
local snapshot=Snapshot.ForHero({getRules=function() return {r} end},caster)[1]
local legacy=Bridge.ConvertLegacyRule(1,snapshot)
assert(legacy.action.kind=="move" and legacy.action.logical_id=="sustained_move")
assert(legacy.target.types[1]=="hero" and #legacy.target.types==1 and legacy.approach=="range_only","snapshot preserves target types and zero forced flag")
for _,key in ipairs(Contract.fields) do assert(decoded.action[key]==r.action[key],key.." sync"); assert(legacy.action[key]==r.action[key],key.." legacy") end
for key,value in pairs({movement_duration=math.huge,movement_distance=-1,movement_mode="teleport",movement_loop="maybe",positioning_tolerance=0/0}) do
    local bad=movement(); bad.action[key]=value; assert(not service:ValidateRule(0,caster,bad),"reject "..key)
end
assert(Contract.presets.weaver_shukuchi=="modifier_weaver_shukuchi" and Contract.presets.primal_beast_trample=="modifier_primal_beast_trample")
assert(Contract.presets.pangolier_gyroshell=="modifier_pangolier_gyroshell")
-- Rolling Thunder preset uses native cast observation + buff, retargets, and
-- exits on buff loss. Native roll steering/turn radius still needs client QA.
r=movement({movement_mode="orbit",movement_buff="modifier_pangolier_gyroshell",
    movement_trigger_ability="pangolier_gyroshell",movement_duration=20,movement_distance=150,
    movement_loop=true,movement_retarget=true})
s=reset({r,attack}); tick(0)
assert(not s.movement,"Rolling Thunder movement cannot begin before native cast/buff")
local roll={GetAbilityName=function() return "pangolier_gyroshell" end}
caster.mods.modifier_pangolier_gyroshell=true
caster.observer:OnAbilityExecuted({unit=caster,ability=roll})
assert(tick(.3).OrderType==1 and s.movement,"Rolling Thunder cast and buff arm orbit")
enemy.hp=0; tick(.6)
assert(s.movement and s.movement.target==other,"Rolling Thunder retargets after enemy death")
caster.stun=true; tick(.9)
assert(#orders==0 and s.movement,"Rolling Thunder preset respects native control")
caster.stun=false; caster.mods.modifier_pangolier_gyroshell=nil; tick(1.2)
assert(not s.movement and not s.events.exclusive_movement,"native roll ending releases exclusive movement")
-- Native reincarnation keeps the same handle: an observer removed on death
-- would leave a cached events table that never receives release/cast callbacks.
reset({attack}); tick(0)
local revivalObserver=caster.observer
local originalUnits=engine.get_battle_units
engine.get_battle_units=function() return {} end
engine:Think()
assert(caster.observer==revivalObserver,"temporary auxiliary-cast exclusion must not detach the event observer")
caster.observer:OnAbilityExecuted({unit=caster,ability=spell})
assert(engine:GetState(caster).events.casts.weaver_shukuchi==1,"excluded native cast still reaches its observer")
engine.get_battle_units=originalUnits
caster.hp=0
if revivalObserver:RemoveOnDeath() then caster:RemoveModifierByName("modifier_rpg_tactics_events") end
caster.hp=100; tick(2)
assert(caster.observer==revivalObserver,"same-handle revival retains the native observer")
caster.observer:OnAttack({attacker=caster,target=enemy})
assert(engine:GetState(caster).events.attack.target==enemy,"attack release still arrives after revival")
print("PASS: persistent movement + native-release posture engine, control, modes, lifecycle, validation and roundtrips (native APIs mocked)")
