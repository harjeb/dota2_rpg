local root = arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = root .. "/?.lua;" .. package.path
local Special = require("tactics/special_targets")
local Conditions = require("tactics/condition_registry")
local Service = require("tactics/rule_service")
local vectorMeta = {}
vectorMeta.__index = vectorMeta
function vectorMeta:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
function vectorMeta.__sub(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=0},vectorMeta) end
local function unit(id,team,x,name,owner)
    local u={id=id,team=team,x=x,name=name,owner=owner,hp=40}
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return true end
    function u:GetTeamNumber() return self.team end
    function u:GetAbsOrigin() return setmetatable({x=self.x,y=0,z=0},vectorMeta) end
    function u:GetUnitName() return self.name end
    function u:GetOwnerEntity() return self.owner end
    function u:entindex() return self.id end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return 100 end
    function u:IsHero() return self.name == "hero" end
    function u:IsCreep() return self.name == "creep" end
    function u:RemoveSelf() self.removed=true end
    return u
end
local caster=unit(1,2,0,"hero")
local ally=unit(2,2,10,"hero")
local enemy=unit(3,3,40,"hero")
local creep=unit(4,3,70,"creep")
local source={GetSpecialValueFor=function(_,key) assert(key=="grab_radius"); return 300 end}
local ctx={caster=caster,enemies={enemy},current_action_spec={logical_id="tiny_toss",source=source}}
FindUnitsInRadius=function() return {creep,enemy,caster,ally} end
assert(Special.GrabTarget(ctx)==ally,"native nearest is selected before user filters")
assert(not Conditions:EvaluateUseConditions({{type="tiny_grab_is_enemy"}},ctx),"enemy filter cannot skip nearer ally")
assert(Conditions:EvaluateUseConditions({{type="tiny_grab_is_ally"},{type="tiny_grab_is_hero"},{type="tiny_grab_hp_pct_lte",value=.5}},ctx))
ally.x=400
assert(Special.GrabTarget(ctx)==enemy)
assert(Conditions:EvaluateUseConditions({{type="tiny_grab_is_enemy"},{type="tiny_grab_is_hero"}},ctx))
enemy.x=500
assert(Conditions:EvaluateUseConditions({{type="tiny_grab_is_creep"}},ctx))
creep.x=400
assert(Special.GrabTarget(ctx)==nil,"outside native radius rejected")
creep.x=40; enemy.x=40
assert(Special.GrabTarget(ctx)==nil,"ambiguous nearest units fail closed")
ctx.current_action_spec.logical_id="other"
assert(not Conditions:EvaluateUseConditions({{type="tiny_grab_is_enemy"}},ctx),"Tiny-only condition cannot authorize another ability")
local game={}
local near=unit(11,2,100,"npc_dota_ember_spirit_remnant",caster)
local far=unit(12,2,900,"npc_dota_ember_spirit_remnant",caster)
local foreign=unit(13,2,20,"npc_dota_ember_spirit_remnant",ally)
local enemyRemnant=unit(14,3,10,"npc_dota_ember_spirit_remnant",enemy)
for _,u in ipairs({near,far,foreign,enemyRemnant}) do assert(Special.OnSpawn(game,u)) end
assert(not Special.OnSpawn(game,caster),"real heroes are not intercepted")
ctx.special_objects=game.specialObjects
assert(#Special.OwnRemnants(ctx)==2,"ownership and team both enforced")
ctx.enemies={enemy}; enemy.x=950
local rule={action={logical_id="ember_spirit_activate_fire_remnant",destination="remnant_nearest"},target_filters={}}
local spec={logical_id=rule.action.logical_id,target_mode="point",source={GetAOERadius=function() return 100 end}}
local function selected(mode)
    rule.action.destination=mode
    local handled,point,anchor=Special.SelectDestination(rule,spec,ctx,Conditions)
    assert(handled and point==nil or handled and point.x==anchor.x)
    return anchor
end
assert(selected("remnant_nearest")==near)
assert(selected("remnant_farthest")==far)
assert(selected("remnant_near_enemy")==far)
assert(selected("remnant_safe")==near)
rule.target_filters={{type="distance_lte",value=300}}
assert(selected("remnant_farthest")==near,"existing target filters constrain destinations")
rule.target_filters={}; rule.min_aoe_hits=999
assert(selected("remnant_near_enemy")==far,"legacy hit count does not block native remnant destination")
rule.min_aoe_hits=nil
far.removed=true
assert(selected("remnant_farthest")==near,"expired remnant handle excluded")
near.owner=ally
assert(selected("remnant_nearest")==nil,"lost ownership invalidates destination")
local service=Service.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function() return true end,state={rules={}}})
for mode in pairs(Special.destinations) do
    local r=service:DecodeFlat({action_kind="ability",action_id="ember_spirit_activate_fire_remnant",destination=mode,target_team="enemy"})
    assert(service:ValidateRule(0,caster,r),mode)
    assert(r.action.destination==mode,"destination survives wire decoding")
end
assert(not Special.ValidDestination("tiny_toss","remnant_nearest"))
assert(not Special.ValidDestination("elder_titan_move_spirit","remnant_nearest"))
assert(Special.ValidDestination("elder_titan_move_spirit","self"))
assert(not Special.ValidDestination("elder_titan_move_spirit",{}))
local bad=service:DecodeFlat({action_kind="ability",action_id="tiny_toss",destination="remnant_nearest"})
assert(not service:ValidateRule(0,caster,bad),"server rejects forged destination on unrelated skill")
Special.Clear(game)
assert(next(game.specialObjects)==nil and foreign.removed and not caster.removed)
print("special-targets tests passed")
