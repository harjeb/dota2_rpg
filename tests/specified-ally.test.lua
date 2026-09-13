package.path = "game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Snapshot=require("tactics/rule_snapshot")
local Rules=require("tactics/rule_service")
local Conditions=require("tactics/condition_registry")
local Engine=require("tactics/tactic_engine")
DOTA_TEAM_GOODGUYS=2; DOTA_TEAM_BADGUYS=3
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_ABILITY_BEHAVIOR_POINT=16
DOTA_UNIT_ORDER_CAST_TARGET=6; DOTA_UNIT_ORDER_CAST_POSITION=5
bit={band=function(a,b) return a==b and b or 0 end}
local vm={}; function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local function unit(id,name,team)
 local u={id=id,name=name,team=team,hp=100}
 function u:entindex() return self.id end
 function u:GetUnitName() return self.name end
 function u:GetTeamNumber() return self.team end
 function u:IsNull() return self.missing==true end
 function u:IsAlive() return self.hp>0 end
 function u:GetAbsOrigin() return Vector(self.id*10,0,0) end
 function u:GetHealth() return self.hp end
 function u:GetMaxHealth() return 100 end
 function u:IsInvulnerable() return false end
 function u:IsMagicImmune() return false end
 return u
end
local key="npc_dota_hero_lion"
local caster=unit(1,"npc_dota_hero_axe",2)
local ally=unit(2,key,2)
local enemy=unit(3,key,3)
local manager={teamHeroes={[2]={caster,ally},[3]={enemy}}}
local function resolve(k) return Snapshot.ResolveAllyActor(manager,caster,k) end
local service=Rules.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
 is_action_allowed=function() return true end,get_hero_key=function() return caster.name end,state={rules={}},
 is_target_actor_allowed=function(_,_,k,kind) assert(kind=="specified_ally"); return resolve(k)~=nil end})
local capability=require("tactics/ability_capability")
assert(capability.ConditionReason({},"target",{type="specified_ally"},"enemy")=="invalid_specified_ally_team")
assert(capability.ConditionReason({},"target",{type="specified_ally"},"ally")==nil)
local rule=service:DecodeFlat({action_kind="ability",action_id="spell",action_name="spell",target_team="ally",
 target_filter_1_type="specified_ally",target_filter_1_target_actor=key})
assert(service:ValidateRule(0,caster,rule))
for _,bad in ipairs({"",123,"enemy:"..key..":0","ch05:enemy:"..key..":0","npc_dota_neutral_centaur_khan"}) do
 assert(not service:ValidateCondition({type="specified_ally",target_actor=bad},Conditions.target_filters))
end
for _,team in ipairs({"enemy","both","self"}) do rule.target.team=team; assert(not service:ValidateRule(0,caster,rule)) end
rule.target.team="ally"
local spell={mode=8}
function spell:IsNull() return false end
function spell:GetAbilityName() return "spell" end
function spell:GetLevel() return 1 end
function spell:GetBehaviorInt() return self.mode end
function spell:GetCastRange() return 600 end
function spell:GetAOERadius() return 0 end
function spell:IsFullyCastable() return true end
function spell:IsCooldownReady() return true end
function spell:entindex() return 99 end
function spell:CastFilterResultTarget(t) return t==ally and not self.reject and 0 or 1 end
caster.FindAbilityByName=function() return spell end
GameRules={GetGameTime=function() return 10 end}
local orders={}
local engine=Engine.new({order_gate={Execute=function(_,o) if o.OrderType==6 or o.OrderType==5 then orders[#orders+1]=o end end},get_phase=function() return "FIGHT" end,
 get_battle_units=function() return {caster} end,get_rules=function() return {rule} end,
 build_context=function() return {get_candidates=function() return {caster,ally,enemy} end,get_ally_actor=resolve} end})
local function tick(ok)
 orders={}; engine:Reset(); engine:GetState(caster).next_eval=0; engine:Think()
 assert(#orders==(ok and 1 or 0),"unavailable ally must fail without fallback")
 if ok then
  if spell.mode==8 then assert(orders[1].TargetIndex==ally.id)
  else assert(orders[1].OrderType==5 and orders[1].Position.x==ally:GetAbsOrigin().x,"POINT uses chosen ally location") end
 end
end
tick(true)
ally.hp=0; tick(false); ally.hp=100
ally.missing=true; tick(false); ally.missing=false
ally.team=3; assert(resolve(key)==nil); tick(false); ally.team=2
manager.teamHeroes[2]={caster}; assert(not service:ValidateRule(0,caster,rule)); tick(false)
local old=ally; ally=unit(12,key,2); manager.teamHeroes[2]={caster,ally}
assert(resolve(key)==ally and resolve(key)~=old); tick(true)
spell.reject=true; tick(false); spell.reject=false
spell.mode=16; tick(true); ally.id=15; tick(true)
manager.getRules=function() return {rule} end
assert(Snapshot.ForHero(manager,caster)[1].target_filters[1].target_actor==key)
assert(not Conditions:EvaluateTargetFilters(rule.target_filters,{caster=caster},ally))
-- Mirrored arena profiles retain relative allied hero identity, never the opposing same-name unit.
manager.arenaActive=true; enemy.ruleSnapshotKey="enemy:"..key..":0"
assert(Snapshot.ResolveAllyActor(manager,enemy,key)==enemy)
assert(Snapshot.ResolveAllyActor(manager,caster,key)==ally)
print("PASS: F40 validation, hostile/bench rejection, death/removal fail-closed, native UNIT/POINT targets, replacement identities and snapshot")
