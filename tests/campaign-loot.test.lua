local root = TEST_REPO_ROOT or "."
local modules = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
package.path = modules .. "?.lua;" .. package.path
local Loot = require("battle.campaign_loot")
local Lives = require("battle.run_lives")
assert(#Loot.Catalog == 266)

-- 掉落强度按关卡分级：第一章不掉 6000+ 的成品，最后一章不再掉一级散件。
assert(Loot.PowerCeiling(nil) == nil and Loot.PowerCeiling("last") == nil,
    "an unparseable stage disables the strength filter")
assert(Loot.PowerCeiling(1) == 1 and Loot.PowerCeiling(6) == 1 and Loot.PowerCeiling(7) == 2,
    "the ceiling steps up every six chapters")
assert(Loot.PowerCeiling(30) == 5 and Loot.PowerCeiling(9999) == 5, "the ceiling clamps at five")
local previous = 0
for stage = 1, 30 do
    local ceiling = Loot.PowerCeiling(stage)
    assert(ceiling >= previous, "the ceiling never falls as chapters advance")
    previous = ceiling
    local pool = Loot.PoolForStage(stage)
    assert(#pool > 0, "stage " .. stage .. " has a non-empty pool")
    local minimum, maximum = Loot.PriceRange(stage)
    local equipmentCount, bonusCount = 0, 0
    for _, row in ipairs(pool) do
        assert(tonumber(row.power) >= 1 and tonumber(row.power) <= ceiling,
            "stage " .. stage .. " pool stays within its ceiling")
        if row.category == "standard" then
            equipmentCount = equipmentCount + 1
            assert(row.cost >= minimum and row.cost <= maximum, "ordinary drops stay in the stage price window")
        else
            bonusCount = bonusCount + 1
            assert(row.power == ceiling, "neutral and special rewards no longer roll a lower tier")
        end
    end
    assert(equipmentCount > 0 and bonusCount > 0, "both reward categories exist at every stage")
end
assert(#Loot.PoolForStage(nil) == #Loot.Catalog, "an unknown stage keeps the full pool")
local function poolHas(pool, name)
    for _, row in ipairs(pool) do if row.name == name then return true end end
    return false
end
assert(not poolHas(Loot.PoolForStage(1), "item_aegis"), "chapter one cannot drop an Aegis")
assert(poolHas(Loot.PoolForStage(30), "item_aegis"), "the last chapters can drop an Aegis")
for stage = 1, 30 do
    local ceiling = Loot.PowerCeiling(stage)
    local function lowestPick(a, b) if a == nil then return 0 end return a end
    local rolled = Loot.Roll({pool="all_items", items={{chance=1},{chance=1},{chance=1}}}, lowestPick, stage)
    assert(#rolled == 3, "three drops at stage " .. stage)
    for _, row in ipairs(rolled) do
        assert(tonumber(row.power) <= ceiling, "stage " .. stage .. " never exceeds its ceiling")
    end
end
-- A high early roll cannot collapse the next protected reward, and a rare low
-- roll never lowers the run's remembered price. Exact 90% boundary is unprotected.
do
    local single = {pool="all_items", items={{chance=1}}}
    local function picker(protection)
        local step = 0
        return function(a, b)
            if a then return b end
            step = step + 1
            if step == 3 then return protection end
            return 0
        end
    end
    local history = {highestEquipmentCost=1500}
    local equal = Loot.Roll(single, picker(.899999), 6, history)[1]
    assert(equal.cost == 1500, "at the stage ceiling the protected drop holds its price")
    local low = Loot.Roll(single, picker(.90), 6, history)[1]
    assert(low.cost < 1500 and low.cost >= 500, "rare variation stays inside the current stage window")
    assert(history.highestEquipmentCost == 1500, "a low roll does not erase the high-water mark")
    local upgrade = Loot.Roll(single, picker(0), 7, history)[1]
    assert(upgrade.cost > 1500 and upgrade.cost <= 1750, "the next stage prefers a strictly more expensive option")
    assert(#Loot.Roll({pool="all_items",items={}}, picker(0), 30, history) == 0)
    assert(history.highestEquipmentCost == upgrade.cost, "failed gates do not advance price history")
    local topNames = {}
    for pick = 1, 9 do
        local row = Loot.Roll(single, function(a, b)
            if a then return pick end
            return 0
        end, 30, {highestEquipmentCost=7400})[1]
        assert(row.cost > 6000, "top-tier protection cannot return mid-tier gear")
        topNames[row.name] = true
    end
    local unique = 0
    for _ in pairs(topNames) do unique = unique + 1 end
    assert(unique == 9, "all nine top-tier items remain eligible after Dagon 5")
    local replay = Loot.Roll(single, picker(0), 1, history)[1]
    assert(replay.cost <= 250, "revisiting a lower stage never exceeds its price cap")
end

local config = {pool="all_items", items={{chance=.35},{chance=.30},{chance=.20}}}
-- Deterministic multi-run simulation of the real drop gates, tracking adjacent
-- ordinary rewards across empty stages and neutral rewards, not just pool means.
do
    local seed = 20260912
    local function random(a, b)
        seed = (seed * 16807) % 2147483647
        local fraction = (seed - 1) / 2147483646
        return a and (a + math.floor(fraction * (b - a + 1))) or fraction
    end
    local ordinary, total, comparisons, nondecreasing, increasing, valueHolds = 0, 0, 0, 0, 0, 0
    local sums, counts = {}, {}
    for run = 1, 1000 do
        local history, lastCost = {}, nil
        for stage = 1, 30 do
            for _, row in ipairs(Loot.Roll(config, random, stage, history)) do
                total = total + 1
                if row.category == "standard" then
                    ordinary = ordinary + 1
                    sums[stage] = (sums[stage] or 0) + row.cost
                    counts[stage] = (counts[stage] or 0) + 1
                    if lastCost then
                        comparisons = comparisons + 1
                        if row.cost >= lastCost then nondecreasing = nondecreasing + 1 end
                        if row.cost > lastCost then increasing = increasing + 1 end
                        if Loot.ProgressValue(row) >= math.min(lastCost, 6000) then valueHolds = valueHolds + 1 end
                    end
                    lastCost = row.cost
                end
            end
        end
    end
    assert(total > 24500 and total < 26500, "the existing .85 rewards per victory is preserved")
    assert(ordinary / total > .83 and ordinary / total < .87, "ordinary equipment dominates with an 85% share")
    assert(valueHolds / comparisons >= .90, "at least 90% hold or improve value, treating top-tier gear equally")
    assert(nondecreasing / comparisons >= .85, "even raw prices mostly hold or increase with top-tier variety")
    assert(increasing / comparisons > .65, "most ordinary rewards strictly improve, not just equal their predecessor")
    local lastMean = 0
    for stage = 1, 30 do
        local mean = sums[stage] / counts[stage]
        assert(mean > lastMean - 100, "average price cannot regress materially at stage " .. stage)
        lastMean = mean
    end
    for stage = 1, 24 do
        assert(sums[stage + 6] / counts[stage + 6] > sums[stage] / counts[stage] + 500,
            "each later chapter gives a substantial price improvement")
    end
    print(string.format("Loot simulation: %d runs, %d rewards, ordinary %.2f%%, value holds %.2f%%, price holds %.2f%%, strictly higher %.2f%%; stage means %.0f -> %.0f gold",
        1000, total, 100 * ordinary / total, 100 * valueHolds / comparisons, 100 * nondecreasing / comparisons, 100 * increasing / comparisons,
        sums[1] / counts[1], sums[30] / counts[30]))
end
local calls = 0
local function zero(a,b) calls=calls+1; if a then return b end; return 0 end
assert(#Loot.Roll(config,zero)==3 and calls==6)
assert(#Loot.Roll(config,function() return .35 end)==0, "strict boundary")
assert(#Loot.Roll(nil,zero)==0)
config.items[4]={chance=1}
assert(#Loot.Roll(config,zero)==3,"bounded even with extra rows")
-- 掉落默认必须走引擎原生随机：原版 Lua VM 的 math.random 起手是可重复序列，
-- 用它会让每一局的掉落顺序完全相同（实机反馈"掉落全是固定顺序"）。
do
    local native = 0
    RandomInt = function(a, b) native = native + 1; return b end
    local picked = Loot.Roll({pool="all_items", items={{chance=1},{chance=1},{chance=1}}})
    assert(#picked == 3, "all three gates pass with the native engine RNG")
    assert(native == 6, "three gates plus three catalog picks use RandomInt, got " .. native)
    assert(picked[1] == Loot.Catalog[#Loot.Catalog], "the catalog index comes from the native roll")
    RandomInt = nil
    local fallback = Loot.Roll({pool="all_items", items={{chance=1},{chance=1},{chance=1}}})
    assert(#fallback == 3, "standalone Lua hosts still roll without the engine RNG")
end

local index={}
for i,r in ipairs(Loot.Catalog) do index[r.name]=i end
assert(index.item_ward_observer and index.item_aegis)
assert(not index.item_roshans_banner)
for name in pairs(index) do assert(not name:match('^item_recipe_')) end
assert(not index.item_recipe_phase_boots and not index.item_stout_shield)
assert(not index.item_tpscroll, 'the mode has no Town Portal Scroll to drop')
assert(not index.item_aghanims_shard and not index.item_aghanims_shard_roshan,
    'dropped shards only exist as the inert Roshan consumable')
assert(not index.item_ultimate_scepter_roshan and not index.item_ultimate_scepter_2,
    'the Roshan Scepter does nothing on roster heroes')
assert(index.item_ultimate_scepter, 'the purchasable Scepter still drops')
local slots, added, full = {}, 0, false
local filler={GetCurrentCharges=function() return 1 end}
local stash={IsNull=function() return false end, GetItemInSlot=function(_,i) return full and filler or slots[i] end}
local game={GetStashUnit=function() return stash end, StashAddItem=function(_,name)
    added=added+1
    -- 交付名一律是实体名；被政策排除的肉山消耗品不会出现在这里。
    assert(name~="item_aghanims_shard_roshan" and name~="item_ultimate_scepter_roshan")
    slots[added]={GetCurrentCharges=function() return 1 end}
    return true
end}
local function choose(name) return function(a,b) return a and index[name] or 0 end end
full=true
-- Award remembers earned prices even when the warehouse is full, and replay
-- clears the history through the same runLives reset used by ResetSessionState.
do
    local progressionGame = {GetStashUnit=game.GetStashUnit, currentLevelId="level_06"}
    local function highest(a, b) return a or 0 end
    Loot.Award(progressionGame, config, highest)
    local state = Lives.Ensure(progressionGame)
    assert(state.campaignLootProgress.highestEquipmentCost == 1500)
    assert(#state.pendingCampaignLoot == 3)
    progressionGame.currentLevelId = "level_07"
    Loot.Award(progressionGame, config, highest)
    assert(state.campaignLootProgress.highestEquipmentCost > 1500, "Award carries price history across victories")
    assert(#state.pendingCampaignLoot == 6, "queued delivery does not prevent progression")
    progressionGame.runLives = nil
    progressionGame.currentLevelId = "level_01"
    Loot.Award(progressionGame, config, highest)
    assert(Lives.Ensure(progressionGame).campaignLootProgress.highestEquipmentCost <= 250, "a new run resets loot history")
end
local names=Loot.Award(game,config,choose("item_blink"))
assert(#names==3 and names[1]=="item_blink" and added==0)
assert(#Lives.Ensure(game).pendingCampaignLoot==3)
full=false
assert(Loot.Flush(game)==0 and added==3)
Loot.Flush(game); assert(added==3,"no duplicate delivery")

-- 中立装备进原版专属中立槽 16：它不占物品栏/背包/储藏栏，所以 0..14 全满时
-- 仍必须照常交付；中立槽被占用时不得发起创建，否则引擎会把新实体丢到地上。
assert(Loot.IsNeutralName("item_occult_bracelet") and Loot.IsNeutralName("item_enhancement_alert"))
assert(not Loot.IsNeutralName("item_blink") and not Loot.IsNeutralName(nil))
do
    local calls, neutralHeld = 0, false
    local neutralStash = {
        IsNull = function() return false end,
        GetItemInSlot = function(_, slot)
            if slot == 16 then return neutralHeld and filler or nil end
            return filler
        end,
    }
    local neutralGame = {
        GetStashUnit = function() return neutralStash end,
        StashAddItem = function(_, name)
            calls = calls + 1
            assert(name == "item_occult_bracelet")
            neutralHeld = true
            return true
        end,
    }
    local function pend(name)
        Lives.Ensure(neutralGame).pendingCampaignLoot = {{name = name, delivery = name}}
    end
    pend("item_occult_bracelet")
    assert(Loot.Flush(neutralGame) == 0 and calls == 1,
        "neutral reward delivers while 0..14 are full")
    pend("item_occult_bracelet")
    assert(Loot.Flush(neutralGame) == 1 and calls == 1,
        "occupied neutral slot defers the reward instead of creating a stray item")
    pend("item_blink")
    assert(Loot.Flush(neutralGame) == 1 and calls == 1,
        "ordinary reward still needs a real 0..14 slot")
end

-- 中立槽被占用、而 0..14 还有空位时：绝不能去调用交付（会被拒绝），
-- 更不能因此被判成"交付不明"而永久扣下这件奖励（实机曾出现 item_unrelenting_eye 被吞）。
do
    local calls = 0
    local occupiedStash = {
        IsNull = function() return false end,
        GetItemInSlot = function(_, slot)
            if slot == 16 then return filler end -- 中立槽已被占用
            if slot == 0 then return nil end     -- 0..14 有空位
            return filler
        end,
    }
    local occupiedGame = {
        GetStashUnit = function() return occupiedStash end,
        StashAddItem = function() calls = calls + 1; return false end,
    }
    Lives.Ensure(occupiedGame).pendingCampaignLoot = {
        { name = "item_occult_bracelet", delivery = "item_occult_bracelet" }}
    assert(Loot.Flush(occupiedGame) == 1 and calls == 0,
        "an occupied neutral slot must not trigger a doomed delivery attempt")
    local pending = Lives.Ensure(occupiedGame).pendingCampaignLoot
    assert(#pending == 1 and not pending[1].uncertain,
        "the reward stays retryable instead of being quarantined as ambiguous")
    -- 中立槽腾出后立刻补交同一件奖励。
    occupiedStash.GetItemInSlot = function(_, slot) if slot == 16 then return nil end return filler end
    local delivered = 0
    occupiedGame.StashAddItem = function() delivered = delivered + 1; return true end
    assert(Loot.Flush(occupiedGame) == 0 and delivered == 1, "the deferred reward is delivered once the slot frees")
end
game.StashAddItem=function() added=added+1; return false end
Loot.Award(game,config,choose("item_blink")); local prior=added
Loot.Flush(game); assert(added==prior,"ambiguous native failure cannot duplicate a consumed grant")
-- Native auto-combination/stacking may invalidate the returned handle.
slots={}; added=0
local merged={GetCurrentCharges=function() return 2 end}
game.StashAddItem=function() added=added+1; slots[added]=merged; return false end
Loot.Award(game,config,choose("item_branches"))
assert(#Lives.Ensure(game).pendingCampaignLoot==3, "only prior quarantined entries remain")
local timer
GameRules={GetGameModeEntity=function() return {SetContextThink=function(_,_,fn) timer=fn end} end}
full=true
Loot.Award(game,config,choose("item_blink")); assert(timer and timer()==1)
local oldRun=game.runLives
game.runLives=nil
assert(timer()==nil and game.runLives==nil, "old retry cannot recreate/deliver into a replay")
game.runLives=oldRun
GameRules=nil
-- Exercise the actual EndBattle source with native API/dependency mocks.
function class() local c={}; c.__index=c; return c end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS=2
DOTA_TEAM_BADGUYS=3
local originalRequire=require
require=function(name)
    if name == "battle.run_results" then return {StartBattle=function() end, RecordBattle=function() end, Finish=function() end, SendTerminal=function() end, Resend=function() end, Invalidate=function() end, Reset=function() end} end
    if name=="battle.campaign_loot" then return Loot end
    if name=="battle.run_lives" then return Lives end
    if name=="battle.unit_helpers" then return {IsValidUnit=function() return true end} end
    return {Clear=function() end,Refresh=function() end,SetBattleActive=function() end,Install=function() end}
end
dofile(modules .. "addon_game_mode.lua")
local payload, count
CustomGameEventManager={Send_ServerToAllClients=function(_,_,p) payload=p;count=(count or 0)+1 end}
GameRules=nil
for _,winner in ipairs({"radiant","dire","timeout"}) do
    local g=setmetatable({phase="fight",lineup={},currentLevelId="last",orderedLevels={"last"},
        battleManager={GetBattleTime=function() return 5 end,teamHeroes={[2]={}},StopBattle=function() end},
        dataLoader={GetLevel=function() return {loot="loot_basic",reward={}} end,GetLoot=function() return config end},
        RunLifecycleStep=function(_,_,fn) fn() end,CalculateTimeBonus=function() return 0 end,
        AddGold=function() end,AwardStageXp=function() end,BroadcastBattleState=function() end,
        BroadcastShopState=function() end,GetStashUnit=function() return nil end},CDota2RpgDemo)
    -- Defeat terminal avoids unrelated transition machinery.
    if winner~="radiant" then Lives.Ensure(g).remaining=1 end
    local old=math.random; math.random=choose("item_blink")
    count=0;g:EndBattle(winner,2);g:EndBattle(winner,2);math.random=old
    assert(count==1,"exactly once settlement")
    assert(payload.loot_text==(winner=="radiant" and "item_blink;item_blink;item_blink" or ""))
    assert(#(Lives.Ensure(g).pendingCampaignLoot or {})==(winner=="radiant" and 3 or 0))
end
print("PASS campaign loot: progression, 266 catalog rows, bounded gates, full stash, retries, ambiguous native delivery")
