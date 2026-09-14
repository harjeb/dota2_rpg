local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Loot = require("battle.campaign_loot")
local Lives = require("battle.run_lives")
local D = require("battle.campaign_difficulty")
local Sales = require("issue_fixes.item_sales")
local assembled = require("data.assembled_loot_items")
local byName, cheapest = {}, math.huge
for _, row in ipairs(Loot.Catalog) do
    byName[row.name] = row
    if row.category == "standard" and assembled[row.name] and row.cost > 0 then cheapest = math.min(cheapest,row.cost) end
end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function first(a,b) if a then return a end return 0 end
local pogo = assert(byName.item_pogo_stick)
eq(pogo.cost,0); eq(Sales.NeutralPrice(pogo.name),200);eq(Loot.NeutralEquivalent(pogo),400)
local function verify(game,row,stage,random)
    local history={highestEquipmentCost=1800}
    local bundle,budget=Loot.NeutralBundle(game,row,random or first,stage,history)
    eq(history.highestEquipmentCost,1800)
    eq(bundle[1],row);eq(row.cost,0)
    eq(budget.target,D.Scale(game,budget.ordinaryCost))
    local spent=0
    for i=2,#bundle do
        local item=bundle[i]
        eq(item.category,"standard");assert(assembled[item.name]);assert(item.cost>0)
        spent=spent+item.cost
    end
    eq(spent,budget.equipment)
    assert(spent<=math.max(0,budget.target-budget.credit))
    eq(budget.residual,math.max(0,budget.target-budget.credit)-spent)
    assert(budget.residual<cheapest,"shortfall bounded by cheapest assembled item")
    return bundle,budget
end
for _,name in ipairs({"easy","default","hard"}) do
    local game={campaignDifficulty=name,currentLevelId="ch09"}
    local bundle,b=verify(game,pogo,9)
    assert(#bundle>1,"chapter9 tier2 must supplement actual ordinary equipment")
    print(string.format("ch09 %s reference=%s ordinary=%d budget=%d neutral_credit=%d equipment=%d residual=%d",name,b.ordinary,b.ordinaryCost,b.target,b.credit,b.equipment,b.residual))
    -- Every stage, every eligible neutral category/tier, both endpoint choices.
    for stage=1,30 do
        for _,row in ipairs(Loot.PoolForStage(stage)) do
            if row.neutral then
                verify(game,row,stage)
                verify(game,row,stage,function(a,b) if a then return b end return .99 end)
            end
        end
    end
end
-- Freeze the whole award before delivery. Zero capacity and later chapters must
-- never reroll, upgrade tier, compound difficulty, or append another supplement.
local originalRoll=Loot.Roll
local gates=0
Loot.Roll=function() gates=gates+1;return {pogo,pogo,pogo} end
for _,name in ipairs({"easy","default","hard"}) do
    local calls,delivered={},{}
    local game={campaignDifficulty=name,currentLevelId="ch09",GetStashUnit=function() return nil end}
    local earned=Loot.Award(game,{pool="all_items"},first)
    local pending=Lives.Ensure(game).pendingCampaignLoot
    eq(#pending,#earned);assert(#earned>=6)
    local originals={}
    local neutrals=0
    for i,p in ipairs(pending) do originals[i]=p.delivery;if p.delivery==pogo.delivery then neutrals=neutrals+1 end end
    eq(neutrals,3)
    game.currentLevelId="ch30";game.campaignDifficulty="easy"
    for i=1,5 do eq(Loot.Flush(game),#earned) end
    for i,p in ipairs(Lives.Ensure(game).pendingCampaignLoot) do eq(p.delivery,originals[i]) end
    local occupied=true
    local filler={GetCurrentCharges=function() return 1 end}
    local stash={IsNull=function() return false end,GetItemInSlot=function(_,slot) if occupied then return filler end end}
    game.GetStashUnit=function() return stash end
    game.StashAddItem=function(_,item) delivered[#delivered+1]=item;return true end
    eq(Loot.Flush(game),#earned);eq(#delivered,0)
    occupied=false
    eq(Loot.Flush(game),0);eq(#delivered,#earned)
    eq(Loot.Flush(game),0);eq(#delivered,#earned)
    for i,item in ipairs(delivered) do eq(item,earned[i]) end
end
eq(gates,3)
-- Ambiguous callbacks quarantine each earned item, never recreate the bundle.
Loot.Roll=function() return {pogo} end
local game={currentLevelId="ch09",GetStashUnit=function() return nil end}
local names=Loot.Award(game,{},first)
local attempts=0
local stash={IsNull=function() return false end,GetItemInSlot=function() return nil end}
game.GetStashUnit=function() return stash end
game.StashAddItem=function() attempts=attempts+1;error("native ambiguous") end
eq(Loot.Flush(game),#names);eq(attempts,#names)
for i=1,3 do eq(Loot.Flush(game),#names) end
eq(attempts,#names)
-- Ordinary and utility gates do not call bundle policy or consume new RNG.
local originalBundle=Loot.NeutralBundle
Loot.NeutralBundle=function() error("ordinary/special entered neutral branch") end
for _,row in ipairs({byName.item_ogre_axe,byName.item_aegis,byName.item_cheese}) do
    local calls=0
    local function rng(a,b) calls=calls+1;return first(a,b) end
    local g={currentLevelId="ch09",GetStashUnit=function() return nil end}
    local expected=Loot.ScaleEquipment(g,Loot.UpgradeEquipment(row,rng),rng)
    local expectedCalls=calls;calls=0
    Loot.Roll=function() return {row} end
    local got=Loot.Award(g,{},rng)
    eq(#got,1);eq(got[1],expected.delivery);eq(calls,expectedCalls)
end
Loot.NeutralBundle=originalBundle;Loot.Roll=originalRoll
-- Inherited pre-policy pending upgrades still work, but never get retroactive
-- supplements. Newly budgeted rewards remain frozen even if not yet delivered.
local old={name="item_foragers_kit",delivery="item_foragers_kit"}
Loot.UpgradePendingNeutral({currentLevelId="ch13"},old)
assert(old.delivery~="item_foragers_kit")
local once=old.delivery;Loot.UpgradePendingNeutral({currentLevelId="ch13"},old);eq(old.delivery,once)
local fresh={name=pogo.name,delivery=pogo.delivery,neutralBudget={target=4000}}
Loot.UpgradePendingNeutral({currentLevelId="ch30",campaignDifficulty="easy"},fresh);eq(fresh.delivery,pogo.delivery)
print("PASS neutral reward budgets: all chapters/difficulties/categories, assembled residual bound, original tier/sales, three independent bundles, retries/quarantine exact-once, ordinary RNG and utility unchanged")
