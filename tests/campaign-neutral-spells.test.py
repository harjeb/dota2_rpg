"""Exercise every campaign native active contract through real rule/target/order code."""
import json
from pathlib import Path
from lua_test_runtime import lua_literal, run_lua

ROOT = Path(__file__).resolve().parents[1]
snapshot = json.loads((ROOT / 'scripts/data/campaign-neutral-native.json').read_text(encoding='utf-8'))
assert not snapshot['unresolved_abilities'], snapshot['unresolved_abilities']
print(run_lua('local snapshot = ' + lua_literal(snapshot) + '\n' + r'''
DOTA_ABILITY_BEHAVIOR_PASSIVE=2
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_ABILITY_BEHAVIOR_POINT=16
DOTA_ABILITY_BEHAVIOR_AOE=32
DOTA_ABILITY_BEHAVIOR_CAN_SELF_CAST=0x10000000
DOTA_ABILITY_BEHAVIOR_DONT_RESUME_MOVEMENT=0x8000
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1
DOTA_UNIT_TARGET_TEAM_ENEMY=2
DOTA_UNIT_TARGET_HERO=1
DOTA_UNIT_TARGET_BASIC=2
DOTA_UNIT_ORDER_CAST_POSITION=5
DOTA_UNIT_ORDER_CAST_TARGET=6
DOTA_UNIT_ORDER_CAST_NO_TARGET=8
local meta={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},meta) end
meta.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
meta.__index={Length2D=function(p) return math.sqrt(p.x*p.x+p.y*p.y) end}
local Engine=require('tactics/tactic_engine')
local Rules=require('issue_fixes/enemy_rules')
local expected={
    centaur_khan_war_stomp={'self',8,250},
    ogre_bruiser_ogre_smash={'enemy',5,200},
    big_thunder_lizard_slam={'self',8,350},
    big_thunder_lizard_frenzy={'ally',6},
    black_dragon_fireball={'enemy',5},
    dark_troll_warlord_raise_dead={'self',8},
    harpy_storm_chain_lightning={'enemy',6},
    ice_shaman_incendiary_bomb={'enemy',6},
    polar_furbolg_ursa_warrior_thunder_clap={'self',8,300},
    satyr_hellcaller_shockwave={'enemy',5},
}
local function number(v)
    if type(v)=='table' then v=v.value end
    return tonumber(tostring(v or ''):match('^[%d%.%-]+')) or 0
end
local function unit(name,index,team,x)
    return {GetUnitName=function() return name end,entindex=function() return index end,
        GetAbsOrigin=function() return Vector(x) end,GetForwardVector=function() return Vector(1) end,
        IsAlive=function() return true end,GetTeamNumber=function() return team end}
end
local enemy,ally=unit('enemy',2,2,100),unit('ally',3,3,50)
local seen,casts={},0
for name,definition in pairs(snapshot.units) do
    local caster=unit(name,1,3,0)
    local slots,byname={},{}
    for slot=1,8 do
        local abilityName=definition['Ability'..slot]
        if abilityName and abilityName~='' then
            local native=assert(snapshot.abilities[abilityName],abilityName)
            local passive=native.AbilityBehavior:find('PASSIVE')~=nil
            local mask=0
            for flag in native.AbilityBehavior:gmatch('DOTA_ABILITY_BEHAVIOR_[A-Z_]+') do mask=mask+(_G[flag] or 0) end
            local ready=true
            local source={GetAbilityName=function() return abilityName end,
                GetBehavior=function() return mask end,GetLevel=function() return 1 end,
                IsPassive=function() return passive end,GetAOERadius=function() return 0 end,
                GetSpecialValueFor=function(_,key) return number((native.AbilityValues or {})[key]) end,
                GetCastRange=function() return number(native.AbilityCastRange) end,
                GetAbilityTargetTeam=function() return _G[native.AbilityUnitTargetTeam] end,
                IsFullyCastable=function() return ready end,IsCooldownReady=function() return true end,
                entindex=function() return 10+slot end,
                setReady=function(value) ready=value end,
                CastFilterResultLocation=function(_,p) assert(p and p.GetAbsOrigin==nil); return 0 end,
                CastFilterResultTarget=function(_,target)
                    local friendly=native.AbilityUnitTargetTeam=='DOTA_UNIT_TARGET_TEAM_FRIENDLY'
                    return (friendly==(target:GetTeamNumber()==caster:GetTeamNumber())) and 0 or 1
                end}
            slots[slot],byname[abilityName]=source,source
        end
    end
    caster.GetAbilityCount=function() return 8 end
    caster.GetAbilityByIndex=function(_,i) return slots[i+1] end
    caster.FindAbilityByName=function(_,id) return byname[id] end
    local orders={}
    local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o;return true end},
        get_phase=function() return 'FIGHT' end,get_battle_units=function() return {} end,
        get_rules=function() return {} end,build_context=function() return {} end})
    local ctx={caster=caster,now=1,resolve_action_name=function(_,id) return id end,
        get_candidates=function(_,_,target)
            return target.team=='ally' and {ally} or {enemy}
        end, alive_enemy_count=1,
        count_enemies_around=function() return 1 end}
    local generated=Rules.CreateForUnit(caster,{})
    local count=0
    for _,rule in ipairs(generated) do
        if rule.action.kind=='ability' then
            count=count+1
            local id=rule.action.logical_id
            local contract=assert(expected[id],'uncovered active spell '..id)
            seen[id]=true
            assert(rule.target.team==contract[1],id..' wrong allegiance')
            if contract[3] then
                assert(rule.use_conditions[1].radius==contract[3],id..' missing native proximity gate')
                ctx.count_enemies_around=function() return 0 end
                assert(not engine.conditions:EvaluateUseConditions(rule.use_conditions,ctx),id..' opens into empty space')
                ctx.count_enemies_around=function() return 1 end
            end
            assert(engine.conditions:EvaluateUseConditions(rule.use_conditions,ctx),id..' blocked near enemy')
            local spec=assert(engine.actions:Resolve(caster,rule.action,ctx))
            local point=assert(engine:ResolveRuleTarget(rule,spec,ctx),id..' unresolved target')
            assert(engine.actions:IsInRange(caster,spec,point),id..' unexpectedly out of range')
            assert(engine.actions:CanExecute(caster,spec,ctx))
            spec.source.setReady(false)
            assert(not engine.actions:CanExecute(caster,spec,ctx),id..' ignores native castability/mana')
            spec.source.setReady(true)
            assert(engine.actions:Issue(caster,spec,point,ctx),id..' rejected order')
            local order=orders[#orders]
            assert(order.OrderType==contract[2] and order.AbilityIndex==spec.source:entindex(),id..' wrong order')
            if contract[2]==6 then
                assert(order.TargetIndex==(contract[1]=='ally' and 3 or 2),id..' wrong native target')
            elseif contract[2]==5 then
                assert(order.Position.x==(id=='ogre_bruiser_ogre_smash' and 16 or 100),id..' wrong cursor')
            end
            casts=casts+1
        end
    end
    local nativeCount=0
    for id,source in pairs(byname) do
        if not source:IsPassive() then nativeCount=nativeCount+1 end
    end
    assert(count==nativeCount,name..' dropped an active slot or attempted a passive')
    assert(generated[#generated].action.kind=='attack',name..' missing fallback')
end
for id in pairs(expected) do assert(seen[id],id..' not exercised') end
print('PASS: all 10 native active contracts across 23 creatures; '..casts..' casts, native slots/passives, allegiance, proximity, castability and destinations')
'''))
