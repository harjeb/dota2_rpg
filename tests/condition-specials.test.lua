package.path = "game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local H = require("tactics/condition_context")
local C = require("tactics/condition_registry")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function vec(x)
    return setmetatable({x=x}, {__sub=function(a,b) return {Length2D=function() return math.abs(a.x-b.x) end} end})
end
local function unit(team, x, owner)
    return { IsNull=function() return false end, IsAlive=function() return true end,
        GetTeamNumber=function() return team end, GetAbsOrigin=function() return vec(x or 0) end,
        GetOwnerEntity=function() return owner end, HasModifier=function() return false end }
end
local caster, enemy, dead = unit(2), unit(2), unit(2)
dead.IsAlive=function() return false end
local roster = {caster, enemy, dead}
local summon = unit(3, 10, caster)
local nested = unit(3, 20, summon)
local other = unit(2, 30, enemy)
local wild = unit(2, 40)
local deadSummon = unit(2, 0, caster); deadSummon.IsAlive=function() return false end
local nullSummon = unit(2, 0, caster); nullSummon.IsNull=function() return true end
local bench = unit(2, 0, caster); bench.HasModifier=function(_,name) return name=="modifier_rpg_prepare_bench" end
local cycleA, cycleB = unit(2), unit(2)
cycleA.GetOwnerEntity=function() return cycleB end; cycleB.GetOwnerEntity=function() return cycleA end
check(H.OwnerRoot(nested, roster)==caster,"nested owner root")
check(H.OwnerRoot(caster, roster)==caster,"root identity")
check(H.OwnerRoot(cycleA, roster)==nil,"ownership cycle terminates")
check(H.OwnerRoot(wild, roster)==nil,"unowned unit has no roster root")
local fallback = unit(2)
fallback.GetOwnerEntity=function() error("unavailable") end
fallback.GetOwner=function() return caster end
check(H.OwnerRoot(fallback, roster)==caster,"guarded GetOwner fallback")
cycleB.GetOwner=function() return caster end
check(H.OwnerRoot(cycleA, roster)==caster,"alternate owner escapes cyclic branch")
cycleB.GetOwner=nil
local deep = caster
for i=1,8 do deep=unit(2,0,deep) end
check(H.OwnerRoot(deep,roster)==caster,"eight owner links accepted")
deep=unit(2,0,deep)
check(H.OwnerRoot(deep,roster)==nil,"ninth owner link rejected")
check(H.OwnerRoot(setmetatable({}, {__index=function() error("invalid handle") end}),roster)==nil,"guard property access")
local expanded, roots, available = H.ExpandBattleUnits(roster)
check(expanded==roster and available==false and roots[caster]==caster,"missing native preserves roster and unknown discovery")
FIND_UNITS_EVERYWHERE=-1; DOTA_UNIT_TARGET_TEAM_BOTH=3; DOTA_UNIT_TARGET_HERO=1
DOTA_UNIT_TARGET_BASIC=2; DOTA_UNIT_TARGET_FLAG_NONE=0; FIND_ANY_ORDER=0
FindUnitsInRadius=function(team,origin,cache,radius,teams,types,flags,order,grow)
    check(team==2 and origin.x==0 and cache==nil and radius==-1,"global native query")
    check(teams==3 and types==3 and flags==0 and order==0 and grow==false,"hero and basic query")
    return {caster,dead,summon,nested,other,wild,deadSummon,nullSummon,bench,cycleA,summon}
end
expanded, roots, available = H.ExpandBattleUnits(roster)
check(available and #expanded==6,"only living roster-owned additions; duplicates removed")
check(expanded[3]==dead and roots[dead]==dead,"dead original roster retained")
check(roots[summon]==caster and roots[nested]==caster and roots[other]==enemy,"ownership map")
check(roots[wild]==nil and roots[deadSummon]==nil and roots[bench]==nil,"excluded units have no roots")
local sides={[caster]="ally",[enemy]="enemy",[dead]="ally"}
check(H.CountAround(expanded,caster,100,true,sides,roots)==2,"allies inherit logical owner side despite native team")
check(H.CountAround(expanded,caster,100,false,sides,roots)==2,"enemies differ logically despite matching native team")
check(H.CountAround(expanded,nested,100,true,sides,roots)==2,"summon center inherits logical side")
check(H.CountAround(expanded,caster,100,true,{},roots)==nil,"unknown logical center fails closed")
FindUnitsInRadius=function() error("unavailable") end
expanded, roots, available=H.ExpandBattleUnits(roster)
check(expanded==roster and not available,"throwing query fallback")
FindUnitsInRadius=function() return nil end
check(select(3,H.ExpandBattleUnits(roster))==false,"invalid query result unavailable")
check(not H.IsSummon(wild),"nonhero is not automatically a summon")
check(H.IsSummon(nested,roster) and not H.IsSummon(caster,roster),"verified ownership summon")
check(H.IsSummon(summon,{[summon]=caster}),"ownership map accepted")
wild.IsSummoned=function() return true end
check(H.IsSummon(wild),"native summoned observation")
wild.IsSummoned=function() error("unavailable") end
check(not H.IsSummon(wild),"summon API failure closed")
local ctx={caster=caster,current_action_id="current"}
local function use(id,value,seconds,action)
    return C:EvaluateUseConditions({{type=id,value=value,seconds=seconds,action_id=action}},ctx)
end
local function target(id,unit)
    return C:EvaluateTargetFilters({{type=id}},ctx,unit)
end
for _, id in ipairs({"action_elapsed_gte","action_elapsed_lte"}) do
    check(not use(id,0),id.." missing observation fails closed")
end
ctx.get_action_elapsed=function(who,id) check(who==caster and id=="current","current action identity"); return 0 end
check(use("action_elapsed_gte",0) and use("action_elapsed_lte",0),"elapsed zero known")
ctx.get_action_elapsed=function(_,id) return id=="spell" and 3 or nil end
check(use("action_elapsed_gte",99,3,"spell") and use("action_elapsed_lte",99,3,"spell"),"seconds preferred and explicit action")
check(not use("action_elapsed_lte",10,nil,"unknown"),"unknown action history fails closed")
ctx.get_action_elapsed=function() error("history unavailable") end
check(not use("action_elapsed_lte",10),"throwing history callback")

check(not target("owned_by_self",summon),"missing ownership callback")
ctx.is_owned_by=function(observed,who) return H.OwnerRoot(observed,roster)==who and observed~=who end
check(target("owned_by_self",nested) and not target("owned_by_self",other),"owned by self uses root")
ctx.get_tags=function() return {summon=true} end
wild.IsRealHero=function() return false end
check(not target("is_summon",wild),"tags and nonrealhero do not invent summon")
ctx.is_summon=function(observed) return H.IsSummon(observed,roster) end
check(target("is_summon",nested) and not target("is_summon",wild),"verified ownership callback")
ctx.is_summon=nil; wild.IsSummoned=function() return true end
check(target("is_summon",wild),"native summon filter")
check(target("is_illusion",{IsIllusion=function() return true end}),"native illusion true")
check(not target("is_illusion",{}) and not target("is_illusion",{IsIllusion=function() error("invalid") end}),"illusion unknown fails closed")
print("condition-specials: "..checks.." checks passed")
