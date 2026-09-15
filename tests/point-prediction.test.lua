package.path='game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;tests/?.lua;'..package.path
local H=require('capability_test_helpers')
local P=require('tactics/point_prediction')
local Selector=require('tactics/target_selector')
local Adapter=require('tactics/action_adapter')
local caster,enemy,other=H.unit(2),H.unit(3,300),H.unit(3,100)
function enemy:GetForwardVector() return Vector(0,1,0) end
function other:GetForwardVector() return Vector(1,0,0) end
local ability=H.ability(caster,'lina_light_strike_array',16,2,1)
local rule=H.rule(ability.name,'enemy')
rule.target.prediction_direction='forward';rule.target.prediction_distance=200
rule.target_priorities={{type='farthest'}}
local orders={}
local adapter=Adapter.new({Execute=function(_,order) orders[#orders+1]=order;return true end})
local spec=assert(adapter:Resolve(caster,rule.action,{}))
local ctx={caster=caster,prediction_time=1,get_candidates=function() return {other,enemy} end}
local selector=Selector.new()
local function check(x,y)
    local point,anchor=selector:SelectPoint(rule,spec,ctx)
    assert(point and math.abs(point.x-x)<0.001 and math.abs(point.y-y)<0.001)
    assert(anchor==enemy,'ranking chooses anchor before offset')
    return point
end
P.Observe({enemy},1);check(300,200) -- first observation uses facing
P.Observe({enemy},1);check(300,200) -- same tick is stable
ctx.prediction_time=1.1;enemy.position=Vector(330,0,0);P.Observe({enemy},1.1)
local point=check(530,0) -- actual movement beats facing
assert(adapter:Issue(caster,spec,point,{}))
assert(orders[#orders].OrderType==DOTA_UNIT_ORDER_CAST_POSITION and orders[#orders].Position==point)
rule.target.prediction_direction='backward';check(130,0)
ctx.prediction_time=1.2;P.Observe({enemy},1.2);check(330,-200) -- stopped
rule.target.prediction_direction='forward'
ctx.prediction_time=1.3;enemy.position=Vector(1500,0,0);P.Observe({enemy},1.3);check(1500,200) -- teleport discarded
ctx.prediction_time=2;check(1500,200) -- stale direction discarded
rule.target.prediction_distance=0;check(1500,0)
rule.target.prediction_distance=200
ctx.is_in_range=function(_,p) return p.x<1000 end
rule.approach='in_range_only'
assert(selector:SelectPoint(rule,spec,ctx)==nil,'out-of-range winner must not switch to another anchor')
rule.approach='allow_approach';check(1500,200)
function ability:CastFilterResultLocation(p) return p.y==200 and 1 or 0 end
assert(selector:SelectPoint(rule,spec,ctx)==nil,'illegal offset must not fall back to feet or second target')
rule.target.prediction_direction=nil
local original,anchor=selector:SelectPoint(rule,spec,ctx)
assert(original==enemy.position and anchor==enemy,'disabled rules preserve original point')
print('point-prediction: PASS (movement/facing, forward/backward/zero, stale/teleport, ranking, range/chase, native legality and position order)')
