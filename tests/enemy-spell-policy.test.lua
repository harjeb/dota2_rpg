local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local Policy=require("issue_fixes.enemy_spell_policy")
local Conditions=require("tactics/condition_registry")
local Selector=require("tactics/target_selector").new()
local vector={};vector.__index=vector
function vector.__sub(a,b) return setmetatable({x=a.x-b.x},vector) end
function vector:Length2D() return math.abs(self.x) end
local function hero(id,hp,maxhp,x)
    return {hp=hp,mods={},GetHealth=function(s) return s.hp end,GetMaxHealth=function() return maxhp end,
        HasModifier=function(s,n) return s.mods[n]==true end,IsNull=function() return false end,
        IsAlive=function() return true end,GetAbsOrigin=function() return setmetatable({x=x},vector) end,
        entindex=function() return id end}
end
local caster=hero(1,1000,1000,0)
local hurt=hero(2,350,1000,400)
local moreMissing=hero(3,1000,2000,450)
local ctx={caster=caster,get_candidates=function() return {caster,hurt,moreMissing} end,
    is_in_range=function() return true end}
local spec={kind="ability",target_mode="unit",ability={CastFilterResultTarget=function() return 0 end}}
local function rule(name,team)
    return {enabled=true,action={kind="ability",logical_id=name},target={team=team},
        target_filters={},target_priorities={{type="nearest"}},use_conditions={},approach="range_only"}
end
local grave=rule("dazzle_shallow_grave","ally")
Policy.Apply(caster,grave)
assert(Selector:SelectUnit(grave,spec,ctx)==hurt,"grave protects critically wounded ally instead of full-health self")
hurt.hp=351
assert(Selector:SelectUnit(grave,spec,ctx)==nil,"grave 35 percent boundary")
hurt.hp=350;hurt.mods.modifier_dazzle_shallow_grave=true
assert(Selector:SelectUnit(grave,spec,ctx)==nil,"do not reapply active grave")
hurt.mods={}
local promise=rule("oracle_false_promise","ally")
Policy.Apply(caster,promise)
hurt.hp=400
assert(Selector:SelectUnit(promise,spec,ctx)==hurt)
hurt.hp=401
assert(Selector:SelectUnit(promise,spec,ctx)==nil,"promise 40 percent boundary")
hurt.hp=300;hurt.mods.modifier_oracle_false_promise_timer=true
assert(Selector:SelectUnit(promise,spec,ctx)==nil,"do not waste promise on already protected target")
hurt.mods={};hurt.hp=350
for _,name in ipairs({"omniknight_purification","dazzle_shadow_wave"}) do
    local heal=rule(name,"ally")
    heal.target_filters={{type="exclude_self"}}
    Policy.Apply(caster,heal)
    assert(Selector:SelectUnit(heal,spec,ctx)==moreMissing,"heals prefer greater missing health over nearest or lowest percent")
    assert(heal.target_filters[1].type=="exclude_self","preserve existing filters")
    hurt.hp=851;moreMissing.hp=2000
    assert(Selector:SelectUnit(heal,spec,ctx)==nil,"hold healing above 85 percent")
    hurt.hp=850
    assert(Selector:SelectUnit(heal,spec,ctx)==hurt,"healing threshold inclusive")
    hurt.hp=350;moreMissing.hp=1000
end
local borrowed=rule("abaddon_borrowed_time","self")
borrowed.use_conditions={{type="always"}}
Policy.Apply(caster,borrowed)
assert(not Conditions:EvaluateUseConditions(borrowed.use_conditions,ctx),"do not spend Borrowed Time at full health")
caster.hp=400
assert(Conditions:EvaluateUseConditions(borrowed.use_conditions,ctx),"allow proactive Borrowed Time at 40 percent")
assert(borrowed.use_conditions[1].type=="always","retain existing use conditions")
local ending=rule("dazzle_nothl_projection_end","self")
Policy.Apply(caster,ending)
assert(ending.enabled==false,"generated enemy rules must not immediately end projection")
local ordinary=rule("lina_laguna_blade","enemy")
Policy.Apply(caster,ordinary)
assert(ordinary.enabled and #ordinary.use_conditions==0 and #ordinary.target_filters==0,"unrelated spell remains available")
-- Exercise the actual generation path: policy follows generic conditions.
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8;DOTA_ABILITY_BEHAVIOR_NO_TARGET=4
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1
local abilities={}
for _,row in ipairs({{"dazzle_shallow_grave",8},{"dazzle_nothl_projection_end",4}}) do
    local name,behavior=row[1],row[2]
    abilities[#abilities+1]={GetAbilityName=function() return name end,GetBehavior=function() return behavior end,
        GetAbilityTargetTeam=function() return 1 end,GetLevel=function() return 1 end}
end
caster.GetAbilityCount=function() return #abilities end
caster.GetAbilityByIndex=function(_,i) return abilities[i+1] end
caster.FindAbilityByName=function(_,name) for _,a in ipairs(abilities) do if a:GetAbilityName()==name then return a end end end
local generated=require("issue_fixes.enemy_rules").CreateForUnit(caster,{})
assert(generated[1].target_filters[1].type=="hp_pct_lte")
assert(generated[2].enabled==false)
local player=require("issue_fixes.default_rules").CreateForHero(caster)
assert(player[2].enabled~=false and #player[1].target_filters==0,"player defaults stay separate")
print("enemy-spell-policy.test.lua: passed")
