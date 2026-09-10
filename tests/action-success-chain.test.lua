local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local Native=require("tactics/native_events")
local Engine=require("tactics/tactic_engine")
local Rules=require("tactics/rule_service")
local Snapshot=require("tactics/rule_snapshot")
DOTA_TEAM_GOODGUYS=2; DOTA_TEAM_BADGUYS=3
DOTA_ABILITY_BEHAVIOR_POINT=16; DOTA_ABILITY_BEHAVIOR_NO_TARGET=4; DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_UNIT_ORDER_CAST_POSITION=5; DOTA_UNIT_ORDER_CAST_NO_TARGET=8
bit={band=function(a,b) return math.floor(a/b)%2==1 and b or 0 end}
local vm={__index={Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__div=function(a,b) return Vector(a.x/b,a.y/b,a.z/b) end
local now=10
GameRules={GetGameTime=function() return now end}
IsServer=function() return true end
class=function(t) return t end
require("modifiers/modifier_rpg_tactics_events")
local function hero(id,name,x,team)
    local u={id=id,name=name,x=x,team=team,items={}}
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:entindex() return self.id end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:GetAbsOrigin() return Vector(self.x,0,0) end
    function u:GetItemInSlot(slot) return self.items[slot] end
    function u:FindAbilityByName(name) return self.spell end
    return u
end
local axe=hero(1,"npc_dota_hero_axe",0,2)
local centaur=hero(2,"npc_dota_hero_centaur",0,2)
local near=hero(3,"enemy",250,3)
local far=hero(4,"enemy",600,3)
local function ability(id,name,behavior)
    local a={name=name}
    function a:IsNull() return false end
    function a:GetAbilityName() return self.name end
    function a:GetLevel() return 1 end
    function a:GetBehaviorInt() return behavior end
    function a:GetCastRange() return 1200 end
    function a:IsFullyCastable() return true end
    function a:IsCooldownReady() return true end
    function a:entindex() return id end
    return a
end
axe.items[0]=ability(11,"item_blink",16)
axe.items[1]=ability(12,"item_blade_mail",4)
axe.spell=ability(13,"axe_berserkers_call",4)
centaur.items[0]=ability(21,"item_blink",16)
centaur.items[1]=ability(22,"item_blade_mail",4)
local observer=setmetatable({GetParent=function() return axe end},{__index=modifier_rpg_tactics_events})
local function executed(source,unit) observer:OnAbilityExecuted({unit=unit or axe,ability=source}) end
local entities={[1]=axe,[2]=centaur}
EntIndexToHScript=function(id) return entities[id] end
local net={}
CustomNetTables={SetTableValue=function(_,_,key,value) net[key]=value end}
local manager={teamHeroes={[2]={axe,centaur},[3]={near,far}}}
local service=Rules.new({get_phase=function() return "PREPARE" end,state={rules={}},
    get_hero_key=function(h) return Snapshot.HeroKey(manager,h) end,
    is_roster_hero=function(_,h) return h==axe or h==centaur end,is_action_allowed=function() return true end})
local function payload(kind,name,prerequisite)
    return {action_kind=kind,action_id=name,action_name=name,target_team=kind=="item" and name=="item_blink" and "enemy" or "self",
        target_types="hero",approach="range_only",target_priority_1_type="nearest",
        use_condition_1_type=prerequisite and "action_succeeded_after" or nil,
        use_condition_1_action_id=prerequisite,use_condition_1_seconds=2}
end
local blink=service:DecodeFlat(payload("item","item_blink"))
local mail=service:DecodeFlat(payload("item","item_blade_mail","item_blink"))
local call=service:DecodeFlat(payload("ability","axe_berserkers_call","item_blade_mail"))
for _,r in ipairs({blink,mail,call}) do assert(service:ValidateRule(0,axe,r)) end
local orders={}
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o end},
    get_phase=function() return "FIGHT" end,get_battle_units=function() return {axe,centaur,near,far} end,
    get_rules=function() return {blink,mail,call} end,
    build_context=function() return {get_candidates=function(_,_,target) return target.team=="self" and {axe} or {far,near} end,
        action_succeeded_after=function(actor,pre,caster,action,seconds) return Native.SucceededAfter(actor,pre,caster,action,seconds,now) end} end})
local function attempt(rule)
    return engine:TryRule(axe,engine:GetState(axe),engine:BuildContext(axe,now),rule,1)
end
assert(not attempt(mail) and not attempt(call),"no successful prerequisite means no chain")
assert(attempt(blink) and orders[#orders].Position.x==near.x,"blink chooses nearest enemy")
assert(not attempt(mail),"submitted or failed blink orders must not unlock mail")
executed(axe.items[0],centaur)
assert(not attempt(mail),"foreign native events cannot unlock this hero")
executed(axe.items[0])
assert(attempt(mail),"native blink success unlocks blade mail")
assert(not attempt(call),"failed mail order cannot unlock call")
executed(axe.items[1])
assert(not attempt(mail),"one blink success allows only one successful mail")
assert(attempt(call),"mail success unlocks call in the same game-time tick")
executed(axe.spell)
assert(not attempt(call),"mail cannot unlock a second call even when cooldown is ready")
assert(axe.rpgTacticsEvents.casts.item_blink==1)
executed(axe.items[0])
assert(attempt(mail),"a second blink success permits another mail")
now=12.01
assert(not attempt(mail),"expired success does not unlock a late action")
now=10
executed(axe.items[1]); executed(axe.spell)
engine:Reset()
assert(not attempt(mail) and not attempt(call),"new battle clears both prerequisite and consumption history")
assert(axe.rpgTacticsEvents.casts.item_blink==nil)
Native.Attach(centaur)
Native.RecordSuccess(centaur,"item_blink",now)
assert(not attempt(mail),"other heroes holding the same item remain independent")
-- Real save -> hero-key storage -> network snapshots with identical equipment.
assert(service:UpdateRule(0,1,1,payload("item","item_blade_mail","item_blink")))
local other=payload("item","item_blade_mail")
other.use_condition_1_type="self_hp_pct_lte";other.use_condition_1_value=0.3
assert(service:UpdateRule(0,2,1,other))
assert(service:GetHeroRules(axe)[1].use_conditions[1].type=="action_succeeded_after")
assert(service:GetHeroRules(centaur)[1].use_conditions[1].value==0.3)
assert(net[axe.name..":1"].use_condition_1_action_id=="item_blink")
assert(net[centaur.name..":1"].use_condition_1_value==0.3)
other.use_condition_1_value=0.7
assert(service:UpdateRule(0,2,1,other))
assert(service:GetHeroRules(axe)[1].use_conditions[1].action_id=="item_blink","editing another hero cannot mutate the first rule")
local invalid=payload("item","item_blade_mail","item_blink")
for _,seconds in ipairs({-1,86401,"nan"}) do
    invalid.use_condition_1_seconds=seconds
    assert(not service:ValidateRule(0,axe,service:DecodeFlat(invalid)))
end
invalid.use_condition_1_seconds=2;invalid.use_condition_1_action_id=nil
assert(not service:ValidateRule(0,axe,service:DecodeFlat(invalid)),"missing prerequisite is rejected")
print("PASS: native blink -> blade mail -> call, failed orders, single consumption, expiry, reset and per-hero item rules")
