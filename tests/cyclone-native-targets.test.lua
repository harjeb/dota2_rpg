local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 1
DOTA_UNIT_TARGET_TEAM_FRIENDLY = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_TARGET_TEAM_BOTH = 3
DOTA_UNIT_TARGET_TEAM_CUSTOM = 4
DOTA_UNIT_TARGET_HERO = 1
DOTA_UNIT_TARGET_BASIC = 2
DOTA_UNIT_TARGET_CUSTOM = 128
DOTA_UNIT_TARGET_FLAG_NOT_SELF = 16
UF_SUCCESS = 0
local function band(a,b)
    local value, place = 0, 1
    while a > 0 and b > 0 do
        if a%2 == 1 and b%2 == 1 then value = value + place end
        a,b,place = math.floor(a/2),math.floor(b/2),place*2
    end
    return value
end
bit = {band=band}
local Native = require("tactics/native_targeting")
local Adapter = require("tactics/action_adapter")
local Selector = require("tactics/target_selector")
local Caps = require("tactics/ability_capability")
local function unit(team, hero)
    return {GetTeamNumber=function() return team end, IsHero=function() return hero end,
        IsAlive=function() return true end, IsNull=function() return false end}
end
local caster, ally, allyBasic, enemy, enemyBasic = unit(2,true), unit(2,true), unit(2,false), unit(3,true), unit(3,false)
local seen, forceReject = {}, false
UnitFilter = function(target,team,types,flags,casterTeam)
    seen = {team,types,flags}
    if forceReject or team == 4 or types == 128 then return 1 end
    if band(team,target:GetTeamNumber()==casterTeam and 1 or 2)==0 then return 1 end
    if band(types,target:IsHero() and 1 or 2)==0 then return 1 end
    if band(flags,16)~=0 and target==caster then return 1 end
    return 0
end
local selector = Selector.new({IsValidEntity=function(t) return t~=nil end,
    EvaluateTargetFilters=function() return true end})
local adapter = Adapter.new({})
local function source(name,team,types,flags)
    return {GetAbilityName=function() return name end, GetBehaviorInt=function() return 1 end,
        GetAbilityTargetTeam=function() return team or 4 end,
        GetAbilityTargetType=function() return types or 128 end,
        GetAbilityTargetFlags=function() return flags or 0 end}
end
local function check(item,target,expected,label)
    local spec={kind="item",source=item,ability=item,cast_type="unit",target_mode=target==caster and "self" or "unit"}
    assert(adapter:IsValidTarget(caster,spec,target)==expected,"adapter: "..label)
    local selected=selector:SelectUnit({target_filters={},target_priorities={}},spec,
        {caster=caster,get_candidates=function() return {target} end})
    assert((selected==target)==expected,"selector: "..label)
end
for _,name in ipairs({"item_cyclone","item_wind_waker"}) do
    local item=source(name,4,128,64)
    check(item,caster,true,name.." self without native cast method")
    check(item,enemy,true,name.." enemy hero")
    assert(seen[1]==3 and seen[2]==3 and seen[3]==64,"CUSTOM translated, native flags preserved")
    check(item,enemyBasic,true,name.." enemy basic")
    check(item,ally,name=="item_wind_waker",name.." ally hero")
    check(item,allyBasic,false,name.." allied basic")
    local cap=Caps.Describe(caster,item,{kind="item"},{runtime=true})
    assert(cap.teams.self==1 and cap.teams.enemy==1 and cap.teams.ally==(name=="item_cyclone" and 0 or 1))
    assert(cap.types.hero==1 and cap.types.monster==1)
    check(source(name,4,128,16),caster,false,name.." native NOT_SELF retained")
    forceReject=true
    check(item,enemy,false,name.." UnitFilter rejection")
    forceReject=false
    item.CastFilterResultTarget=function() return 1 end
    check(item,enemy,false,name.." native rejection")
    item.CastFilterResultTarget=function() error("native failure") end
    check(item,caster,false,name.." native error")
    item.CastFilterResultTarget=function() return 0 end
    check(item,enemy,true,name.." native success")
    check(item,ally,name=="item_wind_waker",name.." native success cannot bypass ally guard")
    item.CastFilterResultTarget=nil
    setmetatable(item,{__index=function(_,key) if key=="CastFilterResultTarget" then error("unreadable method") end end})
    check(item,enemy,false,name.." native method lookup error")
    for _,masks in ipairs({{2,128,2,3},{4,1,3,1},{2,1,2,1},{5,129,5,129}}) do
        local team,types=Native.ResolveMasks(source(name),masks[1],masks[2])
        assert(team==masks[3] and types==masks[4],"ordinary fields preserved independently")
    end
    check(source(name,2,1),caster,false,name.." ordinary enemy team preserved")
    check(source(name,2,1),enemyBasic,false,name.." ordinary hero type preserved")
end
local unknown=source("item_arbitrary_custom")
local team,types=Native.ResolveMasks(unknown,4,128)
assert(team==4 and types==128,"unreviewed CUSTOM unchanged")
check(unknown,enemy,false,"unreviewed CUSTOM rejected by generic filter")
for _,name in ipairs({"phantom_assassin_phantom_strike","tiny_toss","undying_soul_rip"}) do
    local skill=source(name)
    local team,types=Native.ResolveMasks(skill,4,128)
    assert(team==3 and types==3,"reviewed skills retain translation")
    check(skill,caster,name~="phantom_assassin_phantom_strike",name.." self contract retained")
    check(skill,ally,true,name.." allied target retained")
end
print("cyclone-native-targets tests passed (mock native APIs; no gameplay verification)")
