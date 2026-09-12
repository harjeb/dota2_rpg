local root = TEST_REPO_ROOT or "."
local modules = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
package.path = modules .. "?.lua;" .. package.path
local Loot = require("battle.campaign_loot")
local Lives = require("battle.run_lives")
assert(#Loot.Catalog == 270)
local config = {pool="all_items", items={{chance=.35},{chance=.30},{chance=.20}}}
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
local slots, added, full = {}, 0, false
local filler={GetCurrentCharges=function() return 1 end}
local stash={IsNull=function() return false end, GetItemInSlot=function(_,i) return full and filler or slots[i] end}
local game={GetStashUnit=function() return stash end, StashAddItem=function(_,name)
    added=added+1
    assert(name~="item_aghanims_shard" and name~="item_ultimate_scepter_2")
    slots[added]={GetCurrentCharges=function() return 1 end}
    return true
end}
local function choose(name) return function(a,b) return a and index[name] or 0 end end
full=true
local names=Loot.Award(game,config,choose("item_aghanims_shard"))
assert(#names==3 and names[1]=="item_aghanims_shard_roshan" and added==0)
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
print("PASS campaign loot: real EndBattle, 271 catalog rows, bounded gates, aliases, full stash, retries, ambiguous native delivery")
