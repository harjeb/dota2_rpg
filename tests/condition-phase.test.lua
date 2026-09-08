local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local Engine=require("tactics/tactic_engine")
local Adapter=require("tactics/action_adapter")
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8;DOTA_ABILITY_BEHAVIOR_POINT=16;DOTA_ABILITY_BEHAVIOR_NO_TARGET=4
DOTA_UNIT_ORDER_CAST_NO_TARGET=8
bit={band=function(a,b) return math.floor(a/b)%2==1 and b or 0 end}
local vm={__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
local active={name="generic_channel",start=9.8,phase=true}
function active:IsInAbilityPhase() return self.phase end
function active:GetAbilityName() return self.name end
function active:GetChannelStartTime() return self.start end
local source={name="generic_child",behavior=4}
function source:IsNull() return false end
function source:GetLevel() return 1 end
function source:GetAbilityName() return self.name end
function source:GetBehaviorInt() return self.behavior end
function source:GetCastRange() return 600 end
function source:entindex() return 9 end
function source:IsFullyCastable() return true end
function source:IsCooldownReady() return true end
local unit={channel=false}
function unit:IsNull() return false end
function unit:IsAlive() return true end
function unit:entindex() return 1 end
function unit:GetAbsOrigin() return Vector(0,0,0) end
function unit:GetCurrentActiveAbility() return active end
function unit:IsChanneling() return self.channel end
function unit:FindAbilityByName() return source end
local orders,records={},0
GameRules={GetGameTime=function() return 10 end}
local rule={action={kind="ability",logical_id=source.name,name=source.name},target={team="self",types={"hero"}},
    use_conditions={},target_filters={},target_priorities={},approach="range_only"}
local attack_rule={action={kind="attack",logical_id="basic_attack"},target={},use_conditions={},target_filters={}}
local engine=Engine.new({order_gate={Execute=function(_,order) orders[#orders+1]=order end},
    get_phase=function() return "FIGHT" end,get_battle_units=function() return {unit} end,get_rules=function() return {attack_rule,rule} end,
    build_context=function() return {get_candidates=function() return {unit} end,
        record_action_order=function() records=records+1 end} end})
assert(engine:IsBusy(unit),"native active ability wind-up is busy even without a unit phase API")
engine:EvaluateUnit(unit,engine:GetState(unit),10)
assert(#orders==0 and records==0,"wind-up cannot be interrupted by a new action or attack")
active.phase=false;unit.channel=true
engine:EvaluateUnit(unit,engine:GetState(unit),10)
assert(#orders==0 and records==0,"channeling blocks an otherwise ready action")
active.start=8
engine:EvaluateUnit(unit,engine:GetState(unit),10)
assert(#orders==0 and records==0,"elapsed channel duration never permits child actions")
local state=engine:GetState(unit)
local chase={rule=attack_rule,rule_index=1}
state.chase=chase
engine:EvaluateUnit(unit,state,10)
assert(#orders==0 and state.chase==chase,"channel protection also suspends attack chase evaluation")
state.chase=nil
unit.channel=false
engine:EvaluateUnit(unit,engine:GetState(unit),10)
assert(#orders==1 and records==1 and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_NO_TARGET,
    "after channel ends, skills take priority over an earlier attack rule")
orders={};records=0;engine:Reset()
unit.IsInAbilityPhase=function() return true end
engine:EvaluateUnit(unit,engine:GetState(unit),10)
assert(#orders==0 and records==0,"unit phase API also protects wind-up")
unit.IsInAbilityPhase=nil
-- Mixed-mode skills can explicitly select native unit targeting, never invent a mode.
source.behavior=24
local adapter=Adapter.new({Execute=function() end})
assert(adapter:Resolve(unit,{kind="ability",logical_id="test",name="test",cast_preference="unit"},{}).cast_type=="unit")
assert(adapter:Resolve(unit,{kind="ability",logical_id="test",name="test",cast_preference="point"},{}).cast_type=="point")
source.behavior=4
assert(adapter:Resolve(unit,{kind="ability",logical_id="test",name="test",cast_preference="unit"},{})==nil)
unit.channel=true
local blocked={kind="ability",logical_id="test",cast_type="none",target_mode="none",source=source}
assert(not adapter:CanExecute(unit,blocked,{}))
assert(not adapter:Issue(unit,blocked,nil,{}),"direct casts cannot interrupt channeling")
assert(not adapter:IssueApproach(unit,blocked,unit),"direct chase orders cannot interrupt channeling")
print("condition-phase tests passed")
