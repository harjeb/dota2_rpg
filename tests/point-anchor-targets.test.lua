package.path='game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;tests/?.lua;'..package.path
local H=require('capability_test_helpers')
local Adapter=require('tactics/action_adapter')
local Selector=require('tactics/target_selector')
local Compatibility=require('tactics/rule_compatibility')
local caster,ally,enemy=H.unit(2),H.unit(2,300),H.unit(3,400)
local ability=H.ability(caster,'magnataur_skewer',16,2,1)
local unitCalls,locationCalls=0,0
UnitFilter=function(target,team) unitCalls=unitCalls+1; return target.team~=caster.team and team==2 and 0 or 1 end
function ability:CastFilterResultTarget() error('POINT must not use unit filter') end
function ability:CastFilterResultLocation(point) locationCalls=locationCalls+1; return point.x==600 and 1 or 0 end
local orders={}
local adapter=Adapter.new({Execute=function(_,order) orders[#orders+1]=order;return true end})
local rule=H.rule(ability.name,'ally');rule.target.types={'hero'}
local spec=assert(adapter:Resolve(caster,rule.action,{}))
assert(Compatibility.Validate(caster,rule),'enemy damage allegiance does not restrict ally anchors')
local ctx={caster=caster,get_candidates=function(_,_,target) return target.team=='ally' and {ally} or {enemy} end}
local selector=Selector.new()
local point,anchor=selector:SelectPoint(rule,spec,ctx)
assert(point==ally.position and anchor==ally)
-- Order submission is observed directly without any game operations.
assert(adapter:Issue(caster,spec,point,{}))
assert(orders[#orders].OrderType==DOTA_UNIT_ORDER_CAST_POSITION and orders[#orders].Position==ally.position)
assert(unitCalls==0 and locationCalls>=2)
rule.target.team='enemy';assert(Compatibility.Validate(caster,rule))
assert(selector:SelectPoint(rule,spec,ctx)==enemy.position)
ally.position=Vector(600,0,0);rule.target.team='ally'
assert(selector:SelectPoint(rule,spec,ctx)==nil,'illegal native location still rejected')
assert(not adapter:Issue(caster,spec,ally.position,{}))
ally.position=Vector(300,0,0)
-- A self-centered POINT spec is also a location, not a native unit target.
spec.target_mode='self'
assert(#selector:FilterCandidates({caster},{},ctx,spec)==1)
assert(unitCalls==0)
local offensive=H.ability(caster,'lion_finger_of_death',8,2,1)
rule=H.rule(offensive.name,'ally');spec=assert(adapter:Resolve(caster,rule.action,{}))
local ok,reason=Compatibility.Validate(caster,rule)
assert(not ok and reason=='target_team_incompatible')
assert(#selector:FilterCandidates({ally},{},ctx,spec)==0)
assert(not adapter:IsValidTarget(caster,spec,ally))
assert(not adapter:Issue(caster,spec,ally,{}))
assert(adapter:IsValidTarget(caster,spec,enemy))
print('point-anchor-targets: PASS (ally/enemy Skewer anchors, position order, native location rejection, self-point anchor, offensive unit safety)')
