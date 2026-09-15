package.path='game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;tests/?.lua;'..package.path
local H=require('capability_test_helpers')
DOTA_UNIT_ORDER_STOP=21
local time=0
GameRules={GetGameTime=function() return time end}
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,CanFindPath=function() return true end}
local Threats=require('tactics/aoe_threats')
local R=require('tactics/aoe_reaction')
local Engine=require('tactics/tactic_engine')
local unit,enemy=H.unit(2,100),H.unit(3,0)
function unit:GetIdealSpeed() return self.speed or 350 end
unit.idleAcquire=true;unit.acquisitionRange=700
function unit:GetIdleAcquire() return self.idleAcquire end
function unit:SetIdleAcquire(value) self.idleAcquire=value end
function unit:GetAcquisitionRange() return self.acquisitionRange end
function unit:SetAcquisitionRange(value) self.acquisitionRange=value end
local ability=H.ability(unit,'antimage_blink',16,0,0)
local defend=H.ability(unit,'abaddon_borrowed_time',4,0,0)
local rules,orders,list={},{},{}
local engine=Engine.new({order_gate={Execute=function(_,order) orders[#orders+1]=order;return true end},
 get_phase=function() return 'FIGHT' end,get_battle_units=function() return {unit,enemy} end,
 get_rules=function(u) return u==unit and rules or {} end,build_context=function() return {} end})
Threats.Threats=function() return list end
local state=engine:GetState(unit)
local randomCalls=0
local function ctx(t)
 time=t
 local c=engine:BuildContext(unit,t)
 c.aoe_state=state;c.aoe_random=function(a,b) randomCalls=randomCalls+1;assert(a==0 and b==1);return (200-80)/(500-80) end
 return c
end
local function threat(id,impact,phase)
 return {id=id,position=Vector(0,0,0),radius=180,impact_at=impact,expires_at=impact,phase=phase or 'released',caster=enemy}
end
local rule=H.rule(ability.name,'enemy');rule.use_conditions={{type='incoming_aoe',response='walk'}};rules={rule}
list={threat(1,2,'windup')}
assert(not R.Try(engine,unit,state,ctx(0),rules) and randomCalls==0,'windup never starts reaction')
list={threat(1,2)}
assert(not R.Try(engine,unit,state,ctx(0),rules) and randomCalls==1)
assert(not R.Try(engine,unit,state,ctx(.1),rules) and randomCalls==1)
ability.cooldown=false -- walking never requires the row spell to be ready
assert(R.Try(engine,unit,state,ctx(.2),rules))
assert(orders[#orders].OrderType==DOTA_UNIT_ORDER_MOVE_TO_POSITION and randomCalls==1)
assert(not unit.idleAcquire and unit.acquisitionRange==0 and state.events.exclusive_movement,'disable native acquisition while evading')
local destination=orders[#orders].Position
assert(destination.x>220,'walk outside circle and hull')
local count=#orders
assert(R.Try(engine,unit,state,ctx(.25),rules) and #orders==count,'same escape does not spam orders')
unit.position=destination
assert(R.Try(engine,unit,state,ctx(.3),rules) and orders[#orders].OrderType==DOTA_UNIT_ORDER_STOP)
count=#orders
assert(R.Try(engine,unit,state,ctx(.4),rules) and #orders==count,'hold safe edge without reentering')
list={};assert(not R.Try(engine,unit,state,ctx(2),rules) and not state.aoe_walk)
assert(unit.idleAcquire and unit.acquisitionRange==700 and not state.events.exclusive_movement,'restore acquisition on release')
-- Walk too slow => fall through to the next configured spell, not suicide movement.
unit.position=Vector(100,0,0);ability.cooldown=true
local cast=H.rule(ability.name,'enemy');cast.use_conditions={{type='incoming_aoe',response='cast'}}
rules={rule,cast};list={threat(2,2.35)}
assert(not R.Try(engine,unit,state,ctx(2),rules))
assert(R.Try(engine,unit,state,ctx(2.2),rules))
assert(orders[#orders].OrderType==DOTA_UNIT_ORDER_CAST_POSITION)
assert(randomCalls==2,'one draw for same threat across walk and cast rows')
count=#orders
require('tactics/native_events').RecordSuccess(unit,ability.name,2.21)
assert(not R.Try(engine,unit,state,ctx(2.25),rules) and #orders==count,'one spell response per threat')
-- No-target defense keeps native no-target order; cooldown and native control remain authoritative.
local protect=H.rule(defend.name,'self');protect.use_conditions={{type='incoming_aoe',response='cast'}}
rules={protect};list={threat(3,4)}
assert(not R.Try(engine,unit,state,ctx(3),rules))
unit.channel=true
assert(not R.Try(engine,unit,state,ctx(3.2),rules),'do not interrupt own channel')
unit.channel=false;defend.cooldown=false
assert(not R.Try(engine,unit,state,ctx(3.25),rules))
defend.cooldown=true
assert(R.Try(engine,unit,state,ctx(3.3),rules) and orders[#orders].OrderType==DOTA_UNIT_ORDER_CAST_NO_TARGET)
-- No threat means even a satisfied alternative OR condition cannot execute a defense.
protect.use_conditions={{type='always'},{type='incoming_aoe',response='cast'}};protect.use_conditions_mode='priority'
list={};count=#orders
assert(not R.Try(engine,unit,state,ctx(5),rules) and #orders==count)
assert(not engine:TryRule(unit,state,ctx(5),protect,1),'ordinary execution cannot bypass response controller')
-- Blocked paths and root refuse movement rather than forcing an invalid order.
rules={rule};list={threat(4,8)};assert(not R.Try(engine,unit,state,ctx(6),rules))
GridNav.IsTraversable=function() return false end
assert(not R.Try(engine,unit,state,ctx(6.2),rules))
GridNav.IsTraversable=function() return true end
function unit:IsRooted() return true end
assert(not R.Try(engine,unit,state,ctx(6.3),rules))
function unit:IsRooted() return false end
assert(R.Try(engine,unit,state,ctx(6.4),rules))
rule.enabled=false
assert(not R.Try(engine,unit,state,ctx(6.5),rules) and not state.aoe_walk,'disabled rule releases held movement')
-- Multiple circles: escape must leave every known area, not just the nearest one.
unit.position=Vector(100,0,0);list={threat(5,12),{id=6,position=Vector(270,0,0),radius=100,impact_at=12,expires_at=12,phase='released'}}
local safe=assert(R.SafePoint(engine,unit,ctx(10)))
for _,t in ipairs(list) do assert((safe-Vector(t.position.x,t.position.y,0)):Length2D()>t.radius+48) end
-- Distinct per-row intervals share a draw without silently inheriting the first row's delay.
list={threat(7,15)}
local slow={type='incoming_aoe',response='walk',reaction_min_ms=1000,reaction_max_ms=1000}
local fast={type='incoming_aoe',response='cast',reaction_min_ms=100,reaction_max_ms=100}
local draws=randomCalls
assert(not R.Match(ctx(13),slow));assert(not R.Match(ctx(13),fast));assert(randomCalls==draws+1)
assert(not R.Match(ctx(13.11),slow) and R.Match(ctx(13.11),fast) and randomCalls==draws+1)
-- Reaching padded endpoint after impact is fine if the path clears the circle in time.
list={threat(8,16.48)};unit.position=Vector(100,0,0)
assert(R.SafePoint(engine,unit,ctx(16)),'use clearance at impact, not padded destination arrival')
-- Strict blink boundary: an out-of-range escape must not use the normal +24 approach tolerance.
ability.range=140
local blinkSpec=assert(engine.actions:Resolve(unit,cast.action,ctx(16)))
assert(engine.actions:IsInRange(unit,blinkSpec,Vector(252,0,0)))
assert(not R.SafePoint(engine,unit,ctx(16),blinkSpec),'reject beyond true instantaneous cast range')
ability.range=800
-- Revalidate an active escape when the unit slows: stop the owned unsafe order.
list={threat(9,20)};rule.enabled=true;rules={rule}
assert(not R.Try(engine,unit,state,ctx(18),rules));assert(R.Try(engine,unit,state,ctx(18.2),rules))
unit.speed=10
assert(not R.Try(engine,unit,state,ctx(18.3),rules) and not state.aoe_walk)
assert(orders[#orders].OrderType==DOTA_UNIT_ORDER_STOP and unit.idleAcquire)
unit.speed=350
-- An accepted but unconfirmed cast holds duplicate orders, then permits another response.
list={threat(10,24)};rules={cast,protect};protect.use_conditions={{type='incoming_aoe',response='cast'}}
assert(not R.Try(engine,unit,state,ctx(22),rules))
assert(R.Try(engine,unit,state,ctx(22.2),rules));count=#orders
assert(R.Try(engine,unit,state,ctx(22.25),rules) and #orders==count,'hold pending submission')
assert(R.Try(engine,unit,state,ctx(22.6),rules) and orders[#orders].OrderType==DOTA_UNIT_ORDER_CAST_NO_TARGET,'unconfirmed order permits next response')
require('tactics/native_events').RecordSuccess(unit,defend.name,22.61)
assert(not R.Try(engine,unit,state,ctx(22.65),rules),'only native success consumes threat response')
-- Integration: reaction-equipped heroes evaluate on the native 50ms engine think path.
rule.enabled=true;state.next_eval=99;list={};local evaluations=0
local evaluate=engine.EvaluateUnit
engine.EvaluateUnit=function(self,u,s,t) if u==unit then evaluations=evaluations+1 end end
engine:Think();assert(evaluations==1)
engine.EvaluateUnit=evaluate
engine:Reset();assert(next(engine.states)==nil)
print('aoe-reaction: PASS (release-only timing, single random draw, walk/cast fallback, safe-edge hold, native orders/control, OR safety, disable/reset and 50ms cadence)')
