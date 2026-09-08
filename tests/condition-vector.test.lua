-- Fake-source/native contract tests. NativeDLL enum strings were verified earlier;
-- these tests do not establish actual in-game vector execution or hit geometry.
local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Adapter = require("tactics/action_adapter")
local Selector = require("tactics/target_selector")
local Engine = require("tactics/tactic_engine")
local Targets = require("tactics/vector_target")
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=1
DOTA_ABILITY_BEHAVIOR_POINT=2
DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING=16
DOTA_ABILITY_BEHAVIOR_CHANNELLED=32
DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION=100
DOTA_UNIT_ORDER_CAST_TARGET=101
DOTA_UNIT_ORDER_CAST_POSITION=102
DOTA_UNIT_ORDER_MOVE_TO_TARGET=103
bit={band=function(a,b) return math.floor(a/b)%2==1 and b or 0 end}
local vm={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local entities={}
local function unit(id,x)
    local u={id=id,x=x,alive=true}
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return Vector(self.x,0,0) end
    function u:IsAlive() return self.alive end
    function u:IsNull() return false end
    function u:GetTeamNumber() return 2 end
    function u:IsInvulnerable() return self.invulnerable or false end
    function u:IsOutOfGame() return false end
    function u:IsChanneling() return self.channeling or false end
    function u:GetHullRadius() return 100 end
    function u:GetHealth() return self.hp or 100 end
    function u:GetMaxHealth() return 100 end
    entities[id]=u
    return u
end
local caster,near,far,invalid=unit(1,0),unit(2,300),unit(3,301),unit(4,50)
invalid.illegal=true
local source={behavior=17,range=300}
function source:GetBehaviorInt() return self.behavior end
function source:GetCastRange() return self.range end
function source:GetLevel() return 1 end
function source:entindex() return self.id or 99 end
function source:GetAbilityTargetTeam() return 2 end
function source:GetAbilityTargetType() return 1 end
function source:GetAbilityTargetFlags() return 0 end
function source:CastFilterResultTarget(t) return t.illegal and 1 or 0 end
function source:CastFilterResultLocation(p) return self.reject_location and 1 or 0 end
UnitFilter=function(t) return t.filtered and 1 or 0 end
caster.FindAbilityByName=function() return source end
local orders,records={},0
local adapter=Adapter.new({Execute=function(_,o) orders[#orders+1]=o end})
local selector=Selector.new()
local rule={action={kind="ability",name="generic"},approach="range_only"}
local ctx={caster=caster,get_candidates=function() return {far,invalid,near} end,
    is_in_range=function(s,t) return adapter:IsInRange(caster,s,t) end}
local function resolve() return assert(adapter:Resolve(caster,rule.action,ctx)) end
local spec=resolve()
local target,anchor=selector:SelectVector(rule,spec,ctx)
assert(anchor==near and target.start.x==300 and target.finish.x==450,"nearest legal in-range primary, endpoint may exceed range")
assert(adapter:Issue(caster,spec,target,ctx) and #orders==2)
assert(orders[1].OrderType==100 and orders[1].Position==target.finish)
assert(orders[2].OrderType==101 and orders[2].TargetIndex==near.id)
for _,o in ipairs(orders) do assert(o.Queue==false and o.UnitIndex==1 and o.AbilityIndex==99) end
assert(not adapter:IsInRange(caster,spec,Targets.Build(caster,far)),"strict native range without hull padding")
spec.cast_range_override=9999
assert(not adapter:IsInRange(caster,spec,Targets.Build(caster,far)),"vector cannot override native range")
local function rejected(t,s)
    orders={}
    assert(not adapter:Issue(caster,s or spec,t or target,ctx) and #orders==0,"preflight emits no partial pair")
end
DOTA_UNIT_ORDER_CAST_TARGET=nil; rejected(); DOTA_UNIT_ORDER_CAST_TARGET=101
DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION=nil; rejected(); DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION=100
DOTA_UNIT_ORDER_CAST_TARGET=0/0; rejected(); DOTA_UNIT_ORDER_CAST_TARGET=101
near.id=0/0; rejected(); near.id=2
source.id=math.huge; rejected(); source.id=nil
caster.alive=false; rejected(); caster.alive=true
near.alive=false; rejected(); near.alive=true
local malformed={start=target.start,finish=target.finish,primary=42}; rejected(malformed)
near.illegal=true; rejected(); near.illegal=false
near.filtered=true; rejected(); near.filtered=false
rejected(Targets.Build(caster,far))
target.finish.x=math.huge; rejected(); target=Targets.Build(caster,near)
target.start.x=0/0; rejected(); target=Targets.Build(caster,near)
target.finish=target.start; rejected(); target=Targets.Build(caster,near)
near.x=290; rejected(); near.x=300
caster.channeling=true; rejected(); assert(not adapter:IssueApproach(caster,spec,target)); caster.channeling=false
near.x=0; assert(Targets.Build(caster,near)==nil,"zero direction fails closed"); near.x=300
rule.min_aoe_hits=1
assert(selector:SelectVector(rule,spec,ctx)==nil,"explicit positive min AoE rejects unknown geometry")
rule.min_aoe_hits=0
assert(selector:SelectVector(rule,spec,ctx))
rule.min_aoe_hits=nil
source.behavior=18; spec=resolve(); invalid.invulnerable=true
local point=assert(selector:SelectVector(rule,spec,ctx))
orders={}; assert(adapter:Issue(caster,spec,point,ctx))
assert(orders[2].OrderType==102 and orders[2].Position.x==300 and orders[1].Position.x==450)
DOTA_UNIT_ORDER_CAST_POSITION=nil; rejected(point); DOTA_UNIT_ORDER_CAST_POSITION=102
DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION="DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION"; rejected(point); DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION=100
source.reject_location=true; rejected(point); assert(selector:SelectVector(rule,spec,ctx)==nil); source.reject_location=false
source.behavior=16; assert(adapter:Resolve(caster,rule.action,ctx)==nil); rejected(point)
source.behavior=17
-- Generic filters and priorities still apply.
far.x=250; far.hp=20; near.hp=80
rule.target_filters={{type="hp_pct_lte",value=0.5}}
assert(select(2,selector:SelectVector(rule,resolve(),ctx))==far)
rule.target_filters=nil; rule.target_priorities={{type="farthest"}}
assert(select(2,selector:SelectVector(rule,resolve(),ctx))==near)
rule.target_priorities=nil
GameRules={GetGameTime=function() return 10 end}
EntIndexToHScript=function(id) return entities[id] end
local engine=Engine.new({order_gate=adapter.order_gate,actions=adapter,get_phase=function() return "FIGHT" end,
    get_battle_units=function() return {caster} end,get_rules=function() return {rule} end,
    build_context=function() return {get_candidates=ctx.get_candidates,
        record_action_order=function() records=records+1 end} end})
orders={}; records=0
assert(engine:TryRule(caster,engine:GetState(caster),engine:BuildContext(caster,10),rule,1))
assert(#orders==2 and records==1,"paired orders count as one action")
local a=Targets.Build(caster,near)
local signature=engine:OrderSignature(resolve(),a)
a.finish=Vector(999,0,0); assert(signature~=engine:OrderSignature(resolve(),a))
a=Targets.Build(caster,near); a.start=Vector(999,0,0); assert(signature~=engine:OrderSignature(resolve(),a))
a=Targets.Build(caster,near); a.primary=far; assert(signature~=engine:OrderSignature(resolve(),a))
-- Chase unwraps the descriptor and reselects/rebuilds it when in range.
near.x=600;far.x=700;rule.approach="allow_approach";engine:Reset();orders={};records=0
local state=engine:GetState(caster)
assert(engine:TryRule(caster,state,engine:BuildContext(caster,10),rule,1))
assert(state.chase and orders[1].OrderType==103 and orders[1].TargetIndex==near.id)
caster.x=300; orders={}
assert(engine:ContinueChase(caster,state,engine:BuildContext(caster,10.5),10.5))
assert(#orders==2 and orders[1].Position.x==750 and orders[2].TargetIndex==near.id and records==1)
-- Ordinary channelled startup and all busy protections remain native/generic.
source.behavior=17+32; spec=resolve(); orders={}
assert(spec.cast_type=="vector" and adapter:CanExecute(caster,spec,ctx))
assert(adapter:Issue(caster,spec,Targets.Build(caster,near),ctx) and #orders==2)
source.behavior=1+32; spec=resolve(); orders={}
assert(spec.cast_type=="unit" and adapter:CanExecute(caster,spec,ctx))
assert(adapter:Issue(caster,spec,near,ctx) and #orders==1)
caster.channeling=true; orders={}
assert(engine:IsBusy(caster) and not adapter:CanExecute(caster,spec,ctx))
assert(not adapter:Issue(caster,spec,near,ctx) and not adapter:IssueApproach(caster,spec,near) and #orders==0)
print("condition-vector tests passed (fake natives; actual game execution unverified)")
