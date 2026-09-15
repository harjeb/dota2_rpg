-- Offline integration: production engine/adapter/selector/lifecycle, mocked native APIs.
local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
DOTA_UNIT_ORDER_MOVE_TO_POSITION=1; DOTA_UNIT_ORDER_ATTACK_TARGET=4
DOTA_UNIT_ORDER_CAST_TARGET=6; DOTA_UNIT_ORDER_CAST_NO_TARGET=8; DOTA_UNIT_ORDER_STOP=21
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_ABILITY_BEHAVIOR_NO_TARGET=4
bit={band=function(a,b) return math.floor(a/b)%2==1 and b or 0 end}
local vm={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local Engine=require("tactics/tactic_engine")
local Rules=require("tactics/rule_service")
local Lifecycle=require("tactics/action_lifecycle")
local time,phase=0,"FIGHT"
GameRules={GetGameTime=function() return time end}
local function unit(id,x)
    local u={id=id,p=Vector(x,0),hp=100,idle=true,acquisition=1234,f=Vector(1,0)}
    function u:entindex() return self.id end
    function u:IsNull() return false end
    function u:IsAlive() return self.hp>0 end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return 100 end
    function u:GetUnitName() return "npc_dota_hero_mirana" end
    function u:GetTeamNumber() return self.id==1 and 2 or 3 end
    function u:GetAbsOrigin() return self.p end
    function u:GetForwardVector() return self.f end
    function u:GetIdleAcquire() return self.idle end
    function u:GetAcquisitionRange() return self.acquisition end
    function u:SetIdleAcquire(v) self.idle=v end
    function u:SetAcquisitionRange(v) self.acquisition=v end
    function u:HasModifier() return false end
    function u:GetCurrentActiveAbility() return self.active end
    function u:IsChanneling() return self.channel end
    function u:IsRooted() return self.rooted end
    function u:Script_GetAttackRange() return 600 end
    function u:SetForwardVector() error("must observe native facing, never snap it") end
    function u:SetAbsOrigin() error("must issue native movement, never teleport") end
    return u
end
local caster,enemy,other=unit(1,0),unit(2,400),unit(3,800)
local function source(name,behavior,id)
    local a={ready=true,castable=true}
    function a:GetAbilityName() return name end
    function a:GetBehaviorInt() return behavior end
    function a:GetLevel() return 1 end
    function a:GetCastRange() return 600 end
    function a:IsCooldownReady() return self.ready end
    function a:IsFullyCastable() return self.castable end
    function a:entindex() return id end
    function a:CastFilterResultTarget(target) return target==caster and 0 or 1 end
    return a
end
local force=source("item_force_staff",8,91)
local leap=source("mirana_leap",4,92)
function caster:GetItemInSlot(slot) if slot==0 then return force end end
function caster:FindAbilityByName(name) if name=="mirana_leap" then return leap end end
local service=Rules.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function() return true end,state={rules={}},get_hero_key=function() return "mirana" end})
local function rule(name)
    local r=service:DecodeFlat({rule_id="retreat",action_kind=name=="mirana_leap" and "ability" or "item",
        action_id=name,action_name=name,target_team="enemy",target_types="hero",target_priority_1_type="nearest"})
    r.action.destination="away_from_target"
    return r
end
local rules,orders,debug={},{},{}
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o; return true end},
    get_phase=function() return phase end,get_battle_units=function() return caster.hp>0 and {caster} or {} end,
    get_rules=function() return rules end,build_context=function() return {get_candidates=function() return {enemy,other} end} end})
function engine:Debug(_,event,detail) debug[#debug+1]={event=event,detail=detail} end
local fallback=engine.ExecuteFallback
local fallbacks=0
function engine:ExecuteFallback(...) fallbacks=fallbacks+1; return fallback(self,...) end
local function reset(name)
    engine:Reset(); time=0; phase="FIGHT"; orders={}; debug={}; fallbacks=0; GridNav=nil
    caster.hp=100; caster.p=Vector(0,0); caster.f=Vector(1,0); caster.idle=true; caster.acquisition=1234
    caster.active=nil; caster.channel=false; caster.rooted=false
    enemy.hp=100; enemy.p=Vector(400,0); other.hp=100; other.p=Vector(800,0)
    force.ready=true; force.castable=true; leap.ready=true; leap.castable=true
    rules={rule(name)}
    return engine:GetState(caster),name=="mirana_leap" and leap or force
end
local function tick(t)
    time=t; orders={}; engine:EvaluateUnit(caster,engine:GetState(caster),time)
    return orders[1]
end
local function released(s,label)
    assert(not s.facing_retreat and not s.events.exclusive_movement,label.." releases session/events")
    assert(not engine:IsExclusiveMovement(caster) and not engine:HasActiveOrder(caster),label.." releases ownership")
    assert(caster.idle and caster.acquisition==1234,label.." restores native acquisition")
end
for _,name in ipairs({"item_force_staff","mirana_leap"}) do
    local s,a=reset(name)
    s.chase={}; s.posture_order={owns_order=true}; s.last_order_signature="old attack"
    -- TryRule isolates acquisition from the already-owned chase's continuation.
    assert(engine:TryRule(caster,s,engine:BuildContext(caster,0),rules[1],1))
    assert(#orders==1 and orders[1].OrderType==1 and orders[1].Queue==false,name.." begins with ordinary MOVE")
    assert(orders[1].Position.x==-64 and orders[1].Position.y==0,"turn goal points away from enemy")
    assert(s.facing_retreat and s.facing_retreat.owns_order and not s.chase and not s.posture_order)
    assert(not caster.idle and caster.acquisition==0 and s.events.exclusive_movement)
    assert(engine:IsExclusiveMovement(caster) and engine:HasActiveOrder(caster))
    other.p=Vector(20,0)
    assert(tick(.1).OrderType==1 and #orders==1 and s.facing_retreat.anchor==enemy,"turn retains anchor and only owns MOVE")
    assert(fallbacks==0,"fallback must not interrupt turn")
    caster.f=Vector(0,1); assert(tick(.2).OrderType==1,"partial native turn is not confirmation")
    caster.f=Vector(-1,0)
    local cast=tick(.3)
    assert(#orders==1 and cast.AbilityIndex==a:entindex(),name.." casts exactly once after facing confirmation")
    if name=="item_force_staff" then
        assert(cast.OrderType==6 and cast.TargetIndex==caster:entindex(),"Force Staff casts on self, never enemy anchor")
    else assert(cast.OrderType==8 and cast.TargetIndex==nil and cast.Position==nil,"Leap uses native no-target semantics") end
    assert(s.facing_retreat.submitted and not s.facing_retreat.owns_order,"cast relinquishes MOVE order")
    for _,t in ipairs({.4,.8,1.6,2.2}) do
        tick(t); assert(#orders==0 and s.facing_retreat and fallbacks==0,"pending cast has no repeated cast/MOVE/STOP/fallback")
    end
    Lifecycle.Executed(caster,name,2.21); tick(2.22)
    assert(#orders==0,"native execution releases without STOP cancelling cast"); released(s,"executed")

    for _,failure in ipairs({"cooldown","mana","use_condition"}) do
        s,a=reset(name)
        if failure=="cooldown" then a.ready=false
        elseif failure=="mana" then a.castable=false
        else rules[1].use_conditions={{type="self_hp_pct_lte",value=.5}} end
        tick(0)
        assert(not s.facing_retreat and caster.idle and caster.acquisition==1234,failure.." rejected before turn")
        for _,o in ipairs(orders) do assert(o.OrderType~=1 and o.OrderType~=6 and o.OrderType~=8,"unavailable retreat cannot move/cast") end
        assert(fallbacks==1,"unavailable retreat leaves fallback reachable")
    end

    for _,ending in ipairs({"timeout","blocked_path","target_death","rule_edit","rule_removed","cooldown_loss","condition_loss"}) do
        s,a=reset(name); assert(tick(0).OrderType==1)
        if ending=="blocked_path" then GridNav={CanFindPath=function() return false end}
        elseif ending=="target_death" then enemy.hp=0
        elseif ending=="rule_edit" then rules[1].target_priorities={{type="farthest"}}
        elseif ending=="rule_removed" then rules={}
        elseif ending=="cooldown_loss" then a.ready=false
        elseif ending=="condition_loss" then
            -- Change live health, not the authored rule, to exercise condition revalidation.
            s,a=reset(name); rules[1].use_conditions={{type="self_hp_pct_lte",value=.5}}
            caster.hp=40; tick(0); caster.hp=100
        end
        local stop=tick(ending=="timeout" and 1.5 or .2)
        assert(#orders==1 and stop.OrderType==21,ending.." cancels owned MOVE with STOP")
        assert(fallbacks==0,ending.." cancellation consumes tick")
        released(s,ending)
        local expected=({timeout="turn_timeout",blocked_path="turn_path_blocked",target_death="anchor_invalid",
            rule_edit="rule_changed",rule_removed="rule_changed",cooldown_loss="conditions_changed",condition_loss="conditions_changed"})[ending]
        assert(debug[#debug].event=="retreat_cancelled" and debug[#debug].detail.reason==expected,ending.." diagnostic")
    end
    for _,pending in ipairs({false,true}) do
        s,a=reset(name); tick(0)
        if pending then caster.f=Vector(-1,0); tick(.1) end
        orders={}; engine:Reset()
        assert(#orders==(pending and 0 or 1),"reset stops owned movement but preserves submitted cast")
        if not pending then assert(orders[1].OrderType==21) end
        released(s,"reset")
        assert(next(engine.states)==nil and caster.rpgActionLifecycle==nil,"reset clears engine/lifecycle history")
    end
    s=reset(name); tick(0); tick(.1); tick(1.5)
    enemy.hp=100; tick(1.6); assert(not s.facing_retreat,"timeout retry delay prevents immediate turn loop")
end
-- Saved native names behind legacy logical slot aliases retain the same route.
for _,entry in ipairs({{"item_force_staff","item_0",6},{"mirana_leap","ability_2",8}}) do
    local s,a=reset(entry[1])
    rules[1].action.logical_id=entry[2]
    rules[1].action.name=entry[1]
    assert(tick(0).OrderType==1 and s.facing_retreat,"native name recognizes slot alias")
    caster.f=Vector(-1,0)
    local cast=tick(.1)
    assert(#orders==1 and cast.OrderType==entry[3] and cast.AbilityIndex==a:entindex(),"alias preserves native cast semantics")
    tick(.2); assert(#orders==0 and s.facing_retreat,"alias uses native name for pending lifecycle")
end
-- Priority filters are alternatives: the impossible first tier must not turn them into AND.
local s=reset("item_force_staff")
rules[1].target_filters_mode="priority"
rules[1].target_filters={{type="distance_lte",value=10},{type="distance_lte",value=500}}
assert(tick(0).OrderType==1 and s.facing_retreat.anchor==enemy,"priority filters choose first matching tier")
assert(tick(.1).OrderType==1,"locked anchor retains priority filter semantics")
-- A native legal self-push needs no movement permission when already aligned.
s=reset("item_force_staff"); caster.rooted=true; caster.f=Vector(-1,0)
assert(tick(0).OrderType==6 and #orders==1,"aligned rooted caster self-pushes without MOVE")
s=reset("item_force_staff"); caster.rooted=true
local ctx=engine:BuildContext(caster,0)
assert(not engine:TryRule(caster,s,ctx,rules[1],1) and #orders==0 and not s.facing_retreat,
    "unaligned rooted caster cannot begin turning")
s=reset("item_force_staff"); tick(0); caster.rooted=true; caster.f=Vector(-1,0)
assert(tick(.1).OrderType==6,"aligned continuation permits legal self-push after root")
-- Rejected/unobserved native orders have a bounded ownership lifetime.
s=reset("mirana_leap"); tick(0); caster.f=Vector(-1,0); tick(.1)
tick(2.2); assert(#orders==0,"unconfirmed cast release never submits another order")
released(s,"unconfirmed")
engine:Reset()
print("PASS: facing retreat native MOVE/facing/cast semantics, ownership, eligibility, cancellation and reset (Dota APIs mocked)")
