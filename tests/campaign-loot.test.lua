local root = TEST_REPO_ROOT or "."
local modules = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
package.path = modules .. "?.lua;" .. package.path
local Loot = require("battle.campaign_loot")
local Lives = require("battle.run_lives")
assert(#Loot.Catalog == 351)
local config = {pool="all_items", items={{chance=.35},{chance=.30},{chance=.20}}}
local calls = 0
local function zero(a,b) calls=calls+1; if a then return b end; return 0 end
assert(#Loot.Roll(config,zero)==3 and calls==6)
assert(#Loot.Roll(config,function() return .35 end)==0, "strict boundary")
assert(#Loot.Roll(nil,zero)==0)
config.items[4]={chance=1}
assert(#Loot.Roll(config,zero)==3,"bounded even with extra rows")
local index={}
for i,r in ipairs(Loot.Catalog) do index[r.name]=i end
assert(index.item_ward_observer and index.item_aegis and index.item_recipe_black_king_bar)
assert(not index.item_recipe_phase_boots and not index.item_stout_shield)
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
print("PASS campaign loot: real EndBattle, 351 catalog rows, bounded gates, aliases, full stash, retries, ambiguous native delivery")
