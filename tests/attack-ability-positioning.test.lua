local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local V={};V.__index=V
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z or 0},V) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function V:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_ABILITY_BEHAVIOR_ATTACK=131072
DOTA_ABILITY_BEHAVIOR_AUTOCAST=4096
DOTA_UNIT_ORDER_CAST_TARGET=6
DOTA_UNIT_ORDER_MOVE_TO_POSITION=1
local clock=10
GameRules={GetGameTime=function() return clock end}
local unit={ranged=true}
function unit:GetAbsOrigin() return Vector(200,0) end
function unit:entindex() return 1 end
function unit:IsAlive() return true end
function unit:IsRealHero() return true end
function unit:IsRangedAttacker() return self.ranged end
function unit:Script_GetAttackRange() return 600 end
function unit:GetSecondsPerAttack() return 2 end
function unit:IsChanneling() return self.channel end
function unit:IsInAbilityPhase() return self.phase end
local target={GetAbsOrigin=function() return Vector(0,0) end,entindex=function() return 2 end}
local behavior=8+131072+4096
local source={GetBehaviorInt=function() return behavior end,GetLevel=function() return 1 end,
    GetCastRange=function() return 600 end,GetAbilityName=function() return "drow_ranger_frost_arrows" end,
    entindex=function() return 3 end}
function unit:FindAbilityByName() return source end
local Adapter=require("tactics/action_adapter")
local Engine=require("tactics/tactic_engine")
local orders={}
local gate={Execute=function(_,o) orders[#orders+1]=o;return true end}
local adapter=Adapter.new(gate)
local skill={action={kind="ability",name="drow_ranger_frost_arrows"}}
local attack={action={kind="attack",positioning_mode="attack_range"}}
local rules={skill,attack}
local engine=Engine.new({order_gate=gate,get_phase=function() return "FIGHT" end,
    get_battle_units=function() return {unit} end,get_rules=function() return rules end,
    build_context=function() return {} end,actions=adapter,
    conditions={EvaluateUseConditions=function(_,c) return not c or not c.fail end}})
function engine:ResolveRuleTarget(rule) return rule.selected or target,target end
function engine:Debug() end
local spec=assert(adapter:Resolve(unit,skill.action,{}))
assert(spec.is_attack_ability and spec.kind=="ability" and spec.cast_type=="unit")
local ctx={now=clock,caster=unit}
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_mode=="attack_range")
assert(skill.action.positioning_mode==nil,"inheritance must not mutate saved skill")
attack.action.positioning_mode="fixed_distance";attack.action.positioning_distance=450
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_distance==450)
attack.action.positioning_mode="default"
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_mode=="default")
attack.enabled=false
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_mode=="attack_range")
unit.ranged=false
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_mode==nil,"no melee default")
attack.enabled=true;attack.action.positioning_mode="fixed_distance"
attack.use_conditions={fail=true}
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_mode==nil,"failed attack conditions cannot lend stance")
attack.use_conditions=nil;attack.selected={}
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_mode==nil,"different selected target cannot lend stance")
attack.selected=nil
assert(engine:PositioningRule(unit,ctx,skill,spec,target).action.positioning_mode=="fixed_distance","authored melee stance remains usable")
unit.ranged=true;attack.enabled=true;attack.action.positioning_mode="attack_range"
skill.action.positioning_mode="default"
assert(engine:PositioningRule(unit,ctx,skill,spec,target)==skill,"explicit default opts out")
skill.action.positioning_mode="fixed_distance"
assert(engine:PositioningRule(unit,ctx,skill,spec,target)==skill,"explicit skill stance wins")
skill.action.positioning_mode=nil
behavior=8
local spell=assert(adapter:Resolve(unit,skill.action,{}))
assert(not spell.is_attack_ability and engine:PositioningRule(unit,ctx,skill,spell,target)==skill,"ordinary spells untouched")
behavior=8+131072+4096
local auto=assert(adapter:Resolve(unit,{kind="ability",name="drow_ranger_frost_arrows",desired_autocast_state=true},{}))
assert(not auto.is_attack_ability,"autocast state changes are not shots")
local Position=require("tactics/positioning")
local stance=engine:PositioningRule(unit,ctx,skill,spec,target)
local state={events={}}
assert(not Position.Try(engine,unit,state,ctx,stance,spec,target) and #orders==0,"no pre-shot retreat")
state.events.attack={time=9.8,target=target}
assert(Position.Try(engine,unit,state,ctx,stance,spec,target) and orders[#orders].OrderType==1,"Frost Arrows release allows retreat")
state.events.attack.target={}
assert(not Position.Try(engine,unit,state,ctx,stance,spec,target),"different target release blocks retreat")
state.events.attack.target=target
state.events.attack.time=8
assert(not Position.Try(engine,unit,state,ctx,stance,spec,target),"expired release blocks retreat")
state.events.attack.time=9.8;state.attack_order_time=9.9
assert(not Position.Try(engine,unit,state,ctx,stance,spec,target),"new manual shot invalidates old release")
state.attack_order_time=nil;unit.channel=true
assert(not Position.Try(engine,unit,state,ctx,stance,spec,target),"channel cannot be interrupted")
unit.channel=false;unit.phase=true
assert(not Position.Try(engine,unit,state,ctx,stance,spec,target),"windup cannot be interrupted")
unit.phase=false
-- Full priority evaluation: Frost Arrows must yield this tick to its inherited
-- posture, rather than consuming it with another CAST_TARGET order.
orders={};state.last_order_time=0
assert(engine:EvaluateRules(unit,state,ctx,rules,1,#rules))
assert(#orders==1 and orders[1].OrderType==1,"non_attack pass applies inherited posture")
orders={};state.events.attack=nil
assert(engine:EvaluateRules(unit,state,ctx,rules,1,#rules))
assert(#orders==1 and orders[1].OrderType==6,"without release the native shot fires")
assert(state.attack_order_time==clock,"manual shot records release invalidation timestamp")
orders={};unit.channel=true
assert(not engine:EvaluateRules(unit,state,ctx,rules,1,#rules) and #orders==0)
print("PASS: native attack ability runtime posture inheritance and release/channel guards")
