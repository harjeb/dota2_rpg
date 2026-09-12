package.path = 'game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;' .. package.path
local Engine = require('tactics/tactic_engine')
local EnemyRules = require('issue_fixes/enemy_rules')
DOTA_ABILITY_BEHAVIOR_POINT = 16
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_ORDER_CAST_POSITION = 5
DOTA_UNIT_ORDER_CAST_NO_TARGET = 6
local vm = {}
function Vector(x, y, z) return setmetatable({x=x,y=y or 0,z=z or 0}, vm) end
vm.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__index = {Length2D=function(p) return math.sqrt(p.x*p.x+p.y*p.y) end}
local name, mask, radius = 'ogre_bruiser_ogre_smash', 0x10008050, 200
local source = {
    GetAbilityName=function() return name end,
    GetBehavior=function() return mask end,
    GetLevel=function() return 1 end,
    GetAbilityTargetTeam=function() return 2 end,
    GetAOERadius=function() return 0 end,
    GetCastRange=function() return 0 end,
    GetEffectiveCastRange=function() return 75 end,
    GetSpecialValueFor=function(_, key) return key=='radius' and radius or 0 end,
    IsFullyCastable=function() return true end,
    IsCooldownReady=function() return true end,
    CastFilterResultLocation=function(_,p)
        assert(p.GetAbsOrigin==nil, 'native location filter must receive a Vector')
        return p.x==0 and 0 or 1
    end,
    entindex=function() return 10 end,
}
local caster = {
    GetAbsOrigin=function() return Vector(0) end,
    GetUnitName=function() return 'npc_dota_neutral_ogre_mauler' end,
    IsAlive=function() return true end,
    GetTeamNumber=function() return 3 end,
    GetAbilityCount=function() return 1 end,
    GetAbilityByIndex=function() return source end,
    FindAbilityByName=function() return source end,
    entindex=function() return 1 end,
}
local enemy = {GetAbsOrigin=function() return Vector(100) end, IsAlive=function() return true end}
local orders = {}
local engine = Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o; return true end},
    get_phase=function() return 'FIGHT' end, get_battle_units=function() return {} end,
    get_rules=function() return {} end, build_context=function() return {} end})
local ctx = {caster=caster,now=1,get_candidates=function() return {enemy} end,
    resolve_action_name=function(_,id) return id end}
local rule = EnemyRules.CreateForUnit(caster,{})[1]
assert(rule.use_conditions[1] and rule.use_conditions[1].type=='nearby_enemies_gte'
    and rule.use_conditions[1].radius==200, 'ogre needs an enemy within native effect radius')
local spec = assert(engine.actions:Resolve(caster,rule.action,ctx))
assert(spec.target_mode=='self' and spec.cast_type=='point', 'ogre self point does not depend on missing enum or effective range bonus')
local point = assert(engine:ResolveRuleTarget(rule,spec,ctx))
assert(engine.actions:Issue(caster,spec,point,ctx))
assert(orders[1].OrderType==5 and orders[1].Position.x==0, 'ogre issues its own location')
name, mask = 'centaur_khan_war_stomp', 4
radius = 250
rule = EnemyRules.CreateForUnit(caster,{})[1]
assert(rule.use_conditions[1].type=='nearby_enemies_gte' and rule.use_conditions[1].radius==250,
    'stomp uses native radius special when AOE accessor returns zero')
ctx.count_enemies_around=function(_,r) assert(r==250); return 0 end
assert(not engine.conditions:EvaluateUseConditions(rule.use_conditions,ctx), 'distant enemy cannot trigger opening stomp')
ctx.count_enemies_around=function() return 1 end
assert(engine.conditions:EvaluateUseConditions(rule.use_conditions,ctx), 'near enemy enables stomp')
name, mask = 'dawnbreaker_fire_wreath', 4294967296+16+262144
spec = assert(engine.actions:Resolve(caster,{kind='ability',name=name},ctx))
assert(spec.target_mode=='point', 'self-cast permission does not turn directional spells into centered casts')
print('PASS: neutral native-radius gate, ogre self position, location filter and directional isolation')
