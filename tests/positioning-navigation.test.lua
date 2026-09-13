local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local V={}; V.__index=V
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z or 0},V) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function V:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
local Position=require("tactics/positioning")
local unit={p=Vector(200,0),range=600,interval=2}
function unit:GetAbsOrigin() return self.p end
function unit:Script_GetAttackRange() return self.range end
function unit:GetSecondsPerAttack() return self.interval end
local target={p=Vector(0,0)}
function target:GetAbsOrigin() return self.p end
local orders={}
local engine={actions={}}
function engine:IsBusy() return unit.busy end
function engine.actions:Issue(_,spec,goal)
    assert(spec.kind=="move" and spec.logical_id=="action_positioning")
    orders[#orders+1]=goal; return true
end
local spec={kind="attack",logical_id="basic_attack"}
local rule={action={positioning_mode="attack_range",positioning_tolerance=40}}
local state,ctx
local function reset()
    unit.p=Vector(200,0);unit.range=600;unit.interval=2;unit.busy=false
    target.p=Vector(0,0); GridNav=nil; orders={}
    state={events={attack={target=target,time=0}}};ctx={now=0}
end
local function move(time)
    ctx.now=time or 0
    local ok=Position.Try(engine,unit,state,ctx,rule,spec,target)
    return ok and orders[#orders] or nil
end
local function safe(goal)
    assert(goal and (goal-target.p):Length2D()<=unit.range+.1,"waypoint stays in native attack range")
    assert((goal-target.p):Length2D()>(unit.p-target.p):Length2D(),"retreat opens space")
    local step=goal-unit.p;local rel=unit.p-target.p
    assert(rel.x*step.x+rel.y*step.y>=-4,"side step does not move toward the enemy")
end
reset()
local goal=move();assert(goal.x==560 and goal.y==0,"open terrain keeps original radial retreat")
reset();unit.p=Vector(550,0);assert(not move() and #orders==0,"hold inside tolerance band")
reset();state.events.attack=nil;assert(not move() and #orders==0,"windup/order alone never authorizes a move")
reset();state.events.attack.target={};assert(not move(),"release must concern current target")
reset();state.attack_order_time=.1;assert(not move(.2),"new attack order invalidates previous release")
reset();assert(not move(1.75) and #orders==0,"window ends before next attack")
reset();unit.interval=.2;assert(not move(.01),"fast attacks do not invent a release window")
reset();unit.busy=true;assert(not move(),"native casting/channeling blocks posture movement")

-- Rear wall: the radial destination is blocked, but a side is open.
reset();GridNav={IsTraversable=function(_,p) return p.x<=220 end,CanFindPath=function() return true end}
goal=move();safe(goal);assert(goal.y>0 and goal.x<=220,"counterclockwise side opens first")
local first=goal;goal=move(.1);assert(goal.x==first.x and goal.y==first.y,"keep a valid side waypoint instead of flipping each tick")
reset();GridNav={IsTraversable=function(_,p) return p.x<=220 and p.y<=10 end,CanFindPath=function() return true end}
goal=move();safe(goal);assert(goal.y<0,"clockwise side is used if counterclockwise is blocked")
unit.p=Vector(200,-20);target.p=Vector(0,30)
GridNav={IsTraversable=function(_,p) return p.x<=300 end,CanFindPath=function() return true end}
goal=move(.1);safe(goal);assert(goal.y<unit.p.y,"replanning keeps the successful side when both are now open")
reset();GridNav={IsTraversable=function(_,p) return p.x<=220 and p.y>=-100 and p.y<=100 end,CanFindPath=function() return true end}
goal=move();safe(goal);assert(math.abs(goal.y)<=100,"narrow corner uses shorter side steps")
reset();GridNav={IsTraversable=function(_,p) return p.x<=260 or p.x>=420 end,CanFindPath=function() return true end}
goal=move();safe(goal);assert(goal.x<=260 and goal.y~=0,"a navigable endpoint with a wall in between is not used")
reset();GridNav={IsBlocked=function(_,p) return p.x>220 end,CanFindPath=function() return true end}
goal=move();safe(goal);assert(goal.x<=220,"blocked tree/building cells are avoided")
reset();GridNav={CanFindPath=function(_,_,p) return p.y<0 end}
goal=move();safe(goal);assert(goal.y<0,"path-only native API still allows alternate direction")
reset();GridNav={CanFindPath=function() return false end}
assert(not move() and #orders==0,"no safe point falls through to the original attack rule")
reset();GridNav={CanFindPath=function() error('native unavailable') end}
assert(not move() and #orders==0,"navigation errors do not issue blind movement")

-- Static nav can say yes while native bodies keep the unit stationary.
reset();GridNav={CanFindPath=function() return true end}
move();goal=move(.5);safe(goal);assert(goal.y>0,"no progress on radial retreat chooses a side")
goal=move(.6);assert(goal.y>0,"do not reverse before the progress timeout")
goal=move(1);safe(goal);assert(goal.y<0,"no progress on one side tries the opposite direction")
reset();move();move(.5);unit.p=Vector(200,20)
goal=move(.6);assert(goal.y>0)
goal=move(1);assert(goal.y>0,"actual progress keeps the same side")
-- Holding in the safe band must not count idle attack time as a stuck move.
reset();move();unit.p=Vector(550,0);assert(not move(.1))
target.p=Vector(40,0);state.events.attack.time=4
assert(move(4).y==0 and move(4.1).y==0,"new retreat gets its own progress timer after holding range")
-- A temporary blockage may disappear even before the unit can move.
reset();move();move(.5)
GridNav={CanFindPath=function() return false end};assert(not move(.6))
GridNav={CanFindPath=function(_,_,p) return p.y==0 end};state.events.attack.time=2
goal=move(2.6);assert(goal and goal.y==0,"blocked radial route is periodically retried")
-- Translation/rotation must not introduce a fixed world direction.
reset();target.p=Vector(100,80);unit.p=Vector(100,280)
GridNav={IsTraversable=function(_,p) return p.y<=300 end,CanFindPath=function() return true end}
goal=move();safe(goal);assert(goal.x<100 and goal.y<=300,"sides rotate around the actual target")
print("PASS: attack-release kiting, wall/corner/segment rejection, both directions, progress recovery and no-path fallthrough")
