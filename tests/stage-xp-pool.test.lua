local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Data = require("data.progression_data")
local Class = {}; require("patches.progression_patch").Install(Class)
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." ~= "..tostring(b)) end
local function game(count)
    local g=setmetatable({ownedHeroes={},heroData={},lineup={}}, {__index=Class})
    for i=1,count do
        local name="hero"..i
        g.ownedHeroes[i]=name;g.heroData[name]={level=1,current_xp=0,skill_points=1}
    end
    return g
end
local total=0
local kv=assert(io.open(root.."/game/dota_addons/dota2_rpg/scripts/data/levels.kv")):read("*a")
local stage=0
for xp in kv:gmatch('"xp_pool"%s+"(%d+)"') do
    stage=stage+1; near(tonumber(xp),Data.STAGE_XP[stage])
end
assert(stage==30);assert(not kv:find('"xp_per_active_hero"',1,true))
local full=game(5)
for i=1,29 do
    total=total+Data.STAGE_XP[i]
    local share,count=full:AwardStageXp(Data.STAGE_XP[i])
    near(share,Data.ORIGINAL_STAGE_XP_PER_HERO[i]);assert(count==5)
end
near(total,168600);near(Data.STAGE_XP[30],0)
for _,d in pairs(full.heroData) do assert(d.level==30 and d.current_xp==0 and d.skill_points==30) end
-- Bench, dead, missing entity and actual active combatant all share by ownership.
local g=game(7);g.lineup={"hero1","hero2","enemy","summon"}
g.ownedHeroes[#g.ownedHeroes+1]="hero1" -- duplicated ownership never doubles XP
g.ownedHeroes[#g.ownedHeroes+1]="stale" -- no progression record
for _,name in ipairs({"enemy","summon","commander","orphan"}) do g.heroData[name]={level=1,current_xp=0} end
g.battleManager={teamHeroes={[2]={"hero1","summon"},[3]={"enemy"}}}
local share,count=g:AwardStageXp(601);near(share,601/7);assert(count==7)
local credited=0
for i=1,7 do credited=credited+g.heroData["hero"..i].current_xp end
near(credited,601)
for _,name in ipairs({"enemy","summon","commander","orphan"}) do near(g.heroData[name].current_xp,0) end
-- Fractions survive subsequent XP awards and level transitions.
g=game(3)
for i=1,3 do g:AwardStageXp(100) end
for _,d in pairs(g.heroData) do assert(d.level==2);near(d.current_xp,0) end
g:AwardStageXp(1);g:AddXpToHero("hero1",20);near(g.heroData.hero1.current_xp,20+1/3)
-- Repeated thirds/sixths cannot leave heroes stuck just below an integer level.
local fractional=game(6)
for i=1,600 do fractional:AwardStageXp(1) end
for _,d in pairs(fractional.heroData) do assert(d.level==2);near(d.current_xp,0) end
-- Capped heroes count, discarding their own share without boosting others.
g=game(2);g.heroData.hero1.level=30
g:AwardStageXp(120);near(g.heroData.hero1.current_xp,0);near(g.heroData.hero2.current_xp,60)
local empty=game(0);local s,n=empty:AwardStageXp(600);assert(s==0 and n==0)
g=game(1);g:AwardStageXp(-5);near(g.heroData.hero1.current_xp,0)
print("stage-xp-pool: all checks passed (30 authored pools, full-party pace, ownership, fractions, caps)")
