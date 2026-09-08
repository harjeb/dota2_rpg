local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Engine=require("tactics/tactic_engine")
local Rules=require("tactics/rule_service")
local Context=require("tactics/condition_context")
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_ABILITY_BEHAVIOR_POINT=16
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4
DOTA_UNIT_ORDER_CAST_TARGET=6
DOTA_UNIT_ORDER_CAST_POSITION=5
DOTA_UNIT_ORDER_MOVE_TO_TARGET=1
bit={band=function(a,b) return a==b and b or 0 end}
local vm={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__div=function(a,b) return Vector(a.x/b,a.y/b,a.z/b) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local entities={}
local function unit(id,x,hp,team)
    local u={id=id,x=x,hp=hp,mana=100,team=team or 3,immune=false}
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return Vector(self.x,0,0) end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return 100 end
    function u:GetMana() return self.mana end
    function u:GetMaxMana() return 100 end
    function u:IsAlive() return self.hp>0 end
    function u:IsNull() return false end
    function u:IsInvulnerable() return self.invulnerable == true end
    function u:IsMagicImmune() return self.immune end
    function u:GetTeamNumber() return self.team end
    entities[id]=u
    return u
end
local caster=unit(1,0,100,2)
local far=unit(2,900,20)
local near=unit(3,400,70)
local spell={behavior=8,radius=200}
function spell:GetLevel() return 1 end
function spell:GetBehaviorInt() return self.behavior end
function spell:GetCastRange() return 600 end
function spell:GetAOERadius() return self.radius end
function spell:IsFullyCastable() return true end
function spell:IsCooldownReady() return true end
function spell:entindex() return 99 end
function spell:CastFilterResultTarget(target) return target.team==3 and not target.immune and 0 or 1 end
caster.FindAbilityByName=function() return spell end
GameRules={GetGameTime=function() return 10 end}
EntIndexToHScript=function(id) return entities[id] end
local service=Rules.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function() return true end,state={rules={}}})
local rule=service:DecodeFlat({action_kind="ability",action_id="test_spell",action_name="test_spell",
    target_team="enemy",target_types="hero",approach="range_only",
    use_condition_1_type="self_hp_pct_gte",use_condition_1_value="0.5",
    use_condition_2_type="self_mana_pct_gte",use_condition_2_value="0.2",
    use_condition_3_type="nearby_enemies_gte",use_condition_3_value="1",use_condition_3_radius="650",
    use_condition_4_type="elapsed_gte",use_condition_4_value="5",
    target_filter_1_type="hp_pct_lte",target_filter_1_value="0.8",
    target_filter_2_type="distance_gte",target_filter_2_value="100",
    target_filter_3_type="mana_pct_gte",target_filter_3_value="0.1",target_filter_4_type="not_spell_immune",
    target_priority_1_type="lowest_hp_pct",target_priority_2_type="nearest"})
assert(service:ValidateRule(0,caster,rule))
local orders={}
local elapsed=10
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o end},
    get_phase=function() return "FIGHT" end,get_battle_units=function() return {caster,far,near} end,
    get_rules=function() return {rule} end,build_context=function()
        return {elapsed=elapsed,get_candidates=function() return {far,near} end,
            count_enemies_around=function(center,radius) return Context.CountAround({caster,far,near},center,radius,false) end}
    end})
local function attempt()
    orders={}
    return engine:TryRule(caster,engine:GetState(caster),engine:BuildContext(caster,10),rule,1)
end
assert(attempt() and orders[1].TargetIndex==near.id,"range-only chooses eligible in-range target instead of starving on far low HP")
engine:Reset(); caster.mana=10
assert(not attempt() and #orders==0,"second of four AND gates blocks actual order")
caster.mana=100; elapsed=4
assert(not attempt() and #orders==0,"fourth AND gate is actually evaluated")
elapsed=10; near.immune=true
assert(not attempt() and #orders==0,"invalid native target never wins selection")
near.immune=false; near.invulnerable=true
local nativeFilter=spell.CastFilterResultTarget
spell.CastFilterResultTarget=nil
assert(not attempt() and #orders==0,"native invulnerability fallback blocks casting without a condition")
spell.CastFilterResultTarget=nativeFilter
near.invulnerable=false; rule.approach="allow_approach"; engine:Reset()
assert(attempt() and orders[1].OrderType==DOTA_UNIT_ORDER_MOVE_TO_TARGET)
local state=engine:GetState(caster)
assert(state.chase and state.chase.target_index==far.id)
far.hp=100;near.hp=100;caster.x=350;orders={}
assert(not engine:ContinueChase(caster,state,engine:BuildContext(caster,10.5),10.5) and #orders==0,
    "healed targets stop satisfying HP filter during chase; no stale cast")
-- Unit-target circular AoE uses the same minimum-hit gate as point/no-target.
caster.x=0;far.x=500;far.hp=30;near.hp=70;rule.approach="range_only";rule.min_aoe_hits=2;engine:Reset()
assert(attempt() and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_TARGET,"clustered unit AoE may cast")
far.x=900;engine:Reset()
assert(not attempt() and #orders==0,"isolated unit AoE waits for its configured hit count")
-- Point spells honour priority ties, not an unrelated implicit nearest rank.
far.x=550;near.x=200;spell.behavior=16;spell.radius=0;rule.min_aoe_hits=1;engine:Reset()
assert(attempt() and orders[1].Position.x==550,"point spell ties honour lowest HP priority")
print("condition-execution tests passed")

-- Reproduce the Time Walk report through DecodeFlat -> engine -> native point order.
spell.GetAbilityName=function() return "faceless_void_time_walk" end
spell.GetBehaviorInt=function() return 525328 end
spell.GetEffectiveCastRange=function() return 0 end
spell.GetCastRange=function() return 0 end
spell.GetSpecialValueFor=function(_,key) return key=="range" and 650 or 0 end
spell.CastFilterResultLocation=function() return 0 end
caster.hp=60; caster.x=0; near.x=200; far.x=250
local targetContext=engine.build_context
engine.build_context=function(...)
    local ctx=targetContext(...)
    ctx.get_candidates=function(unit,_,target)
        return target.team=="self" and {unit} or {far,near}
    end
    return ctx
end
local timeWalkPayload={action_kind="ability",action_id="faceless_void_time_walk",action_name="faceless_void_time_walk",
    target_team="enemy",target_types="hero,monster,summon",approach="range_only",
    use_condition_1_type="self_hp_pct_lte",use_condition_1_value=0.6,
    target_filter_1_type="distance_gte",target_filter_1_value=350,
    target_filter_2_type="distance_lte",target_filter_2_value=900,target_priority_1_type="nearest"}
rule=service:DecodeFlat(timeWalkPayload); engine:Reset()
assert(not attempt() and #orders==0,"old gapclose filters block nearby enemies even after HP passes")
timeWalkPayload.target_team="self"
timeWalkPayload.target_filter_1_type=nil; timeWalkPayload.target_filter_2_type=nil
rule=service:DecodeFlat(timeWalkPayload); engine:Reset()
assert(service:ValidateRule(0,caster,rule))
assert(attempt() and #orders==1 and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_POSITION
    and orders[1].Position.x==caster.x,"recovery sends a point order at the caster with nearby enemies")
caster.hp=61; engine:Reset()
assert(not attempt() and #orders==0,"recovery preserves the user's HP threshold")
caster.hp=60; timeWalkPayload.target_team="enemy"; near.x=600; far.x=900
rule=service:DecodeFlat(timeWalkPayload); engine:Reset()
assert(attempt() and orders[1].Position.x==600,"native Time Walk range fallback enables an enemy anchor in range")
near.x=700; engine:Reset()
assert(not attempt() and #orders==0,"native Time Walk range still rejects distant enemy anchors")
print("PASS: Time Walk old-filter reproduction, self recovery, HP boundary and native point range through engine")

-- Enemy healer profiles must not turn Crystal Nova into a spell at the caster's feet.
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1
DOTA_UNIT_TARGET_TEAM_ENEMY=2
spell.GetAbilityName=function() return "crystal_maiden_crystal_nova" end
spell.GetBehaviorInt=function() return 16 end
spell.GetEffectiveCastRange=nil
spell.GetCastRange=function() return 600 end
spell.GetAbilityTargetTeam=function() return DOTA_UNIT_TARGET_TEAM_ENEMY end
caster.GetAbilityCount=function() return 1 end
caster.GetAbilityByIndex=function() return spell end
caster.hp=100;near.x=350;far.x=900
local healerProfile={action={kind="ability",logical_id="ability_1"},target={team="ally"}}
rule=require("issue_fixes.enemy_rules").CreateForUnit(caster,{healerProfile})[1]
engine.build_context=function()
    return {resolve_action_name=function(_,name) return name end,
        get_candidates=function(unit,_,target)
        return target.team=="enemy" and {far,near} or {unit}
    end}
end
engine:Reset()
assert(attempt() and #orders==1 and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_POSITION
    and orders[1].Position.x==near.x and orders[1].Position.x~=caster.x,
    "native enemy rule targets the opposing hero instead of the healer profile's allied caster")
print("PASS: Crystal Nova profile correction reaches a native point order on an opposing hero")

-- Q/W's special ranges must survive the full saved-rule -> selector -> order path.
local nativeLevel, allowRange, stunned = 1, false, false
spell.GetLevel=function() return nativeLevel end
spell.GetCastRange=function() return 0 end
spell.GetEffectiveCastRange=function() return 0 end
caster.IsStunned=function() return stunned end
for _, name in ipairs({"dawnbreaker_fire_wreath", "dawnbreaker_celestial_hammer"}) do
    nativeLevel, allowRange = 1, false
    spell.GetAbilityName=function() return name end
    spell.GetSpecialValueFor=function(_, key)
        if not allowRange then return 0 end
        if name=="dawnbreaker_fire_wreath" and key=="swipe_radius" then return 300 end
        if name=="dawnbreaker_celestial_hammer" and key=="range" then return ({700,900,1100,1300})[nativeLevel] end
        return 0
    end
    near.x=name=="dawnbreaker_fire_wreath" and 250 or 600; far.x=1600
    rule=service:DecodeFlat({action_kind="ability",action_id=name,action_name=name,
        target_team="enemy",target_types="hero",approach="range_only",target_priority_1_type="nearest"})
    assert(service:ValidateRule(0,caster,rule))
    engine:Reset()
    assert(not attempt() and #orders==0, name .. " reproduces no legal anchor when range collapses to zero")
    allowRange=true; engine:Reset()
    assert(attempt() and #orders==1 and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_POSITION
        and orders[1].Position.x==near.x and orders[1].Position.x~=caster.x,
        name .. " now emits a native point cast toward an in-range enemy")
    caster.GetCastRangeBonus=function() return 125 end
    spell.GetEffectiveCastRange=function() return 125 end
    engine:Reset()
    assert(attempt() and orders[1].Position.x==near.x, name .. " also casts when the effective accessor returns only a range bonus")
    stunned=true; engine:Reset()
    assert(not attempt() and #orders==0, name .. " still cannot cast while stunned")
    stunned=false
    spell.CastFilterResultLocation=function() return 1 end; engine:Reset()
    assert(not attempt() and #orders==0, name .. " keeps native location filtering")
    spell.CastFilterResultLocation=function() return 0 end
    near.x=name=="dawnbreaker_fire_wreath" and 400 or 850; engine:Reset()
    assert(not attempt() and #orders==0, name .. " rejects a target beyond level-one reach")
    if name=="dawnbreaker_celestial_hammer" then
        nativeLevel=2; engine:Reset()
        assert(attempt() and orders[1].Position.x==850, "Hammer level two refreshes range to 900 without reauthoring a rule")
    end
end
print("PASS: Dawnbreaker Q/W zero-range reproduction, native enemy point orders, range upgrades and legality/control gates")
