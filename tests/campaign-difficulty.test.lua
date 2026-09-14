local root = TEST_REPO_ROOT or "."
local modules = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
package.path = modules .. "?.lua;" .. package.path
local D = require("battle.campaign_difficulty")
local Loot = require("battle.campaign_loot")
local Lives = require("battle.run_lives")
local Results = require("battle.run_results")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
for name, rate in pairs({easy=1.5,default=1,hard=.7}) do
    local g = {campaignDifficulty=name}
    eq(D.Multiplier(g),rate)
    for _, value in ipairs({0,1,2,3,5,7,100,2000}) do eq(D.Scale(g,value),math.floor(value*rate+.5)) end
    eq(D.Scale(g,-7),0); eq(D.Scale(g,0/0),0); eq(D.Scale(g,math.huge),0)
    g.arena={mode="arena"};eq(D.Scale(g,100),100)
end
eq(D.Scale({},100),100);eq(D.Name({campaignDifficulty="invalid"}),"default")
local g={playerId=0,phase="setup"}
for _, payload in ipairs({{difficulty="easy"},{PlayerID=1,difficulty="easy"},{PlayerID=0,difficulty="EASY"},{PlayerID=0,difficulty=1.5}}) do
    assert(not D.Select(g,payload)); assert(not g.campaignDifficultyLocked)
end
g.phase="fight";assert(not D.Select(g,{PlayerID=0,difficulty="easy"}));g.phase="setup"
g.arena={mode="arena"};assert(not D.Select(g,{PlayerID=0,difficulty="easy"}));g.arena=nil
assert(D.Select(g,{PlayerID=0,difficulty="hard",reward_multiplier=99}));eq(D.Multiplier(g),.7)
assert(not D.Select(g,{PlayerID=0,difficulty="easy"}));eq(D.Name(g),"hard")
Results.Reset(g);eq(D.Name(g),"hard");assert(g.campaignDifficultyLocked,"replay accounting reset cannot unlock selection")
-- Real native filter contracts: reason whitelists, owner, debits, no second wallet scaling.
DOTA_ModifyGold_GameTick=10;DOTA_ModifyGold_AbilityGold=17;DOTA_ModifyGold_CreepKill=13
DOTA_ModifyGold_SellItem=6;DOTA_ModifyGold_PurchaseItem=4;DOTA_ModifyGold_Unspecified=0
DOTA_ModifyXP_CreepKill=2;DOTA_ModifyXP_Unspecified=0;DOTA_ModifyXP_TomeOfKnowledge=4
for _, name in ipairs({"easy","default","hard"}) do
    g={playerId=0,campaignDifficulty=name}
    for _, reason in ipairs({10,17,13}) do
        local event={player_id_const=0,reason_const=reason,gold=101}
        assert(D.GoldFilter(g,event));eq(event.gold,D.Scale(g,101))
    end
    for _, case in ipairs({{0,6,101},{0,4,101},{0,0,101},{1,17,101},{0,17,-101},{0,17,0}}) do
        local event={player_id_const=case[1],reason_const=case[2],gold=case[3]}
        D.GoldFilter(g,event);eq(event.gold,case[3])
    end
    for _, reason in ipairs({0,2}) do
        local event={player_id_const=0,reason_const=reason,experience=101}
        D.XpFilter(g,event);eq(event.experience,D.Scale(g,101))
    end
    local event={player_id_const=0,reason_const=4,experience=101};D.XpFilter(g,event);eq(event.experience,101)
    local native={player_id_const=0,reason_const=17,gold=100}
    g.arena={mode="arena"};D.GoldFilter(g,native);eq(native.gold,100)
end
for _,case in ipairs({{"easy",15},{"hard",7}}) do
    local game={playerId=0,campaignDifficulty=case[1]};local total=0
    for i=1,10 do local tick={player_id_const=0,reason_const=10,gold=1};D.GoldFilter(game,tick);total=total+tick.gold end
    eq(total,case[2])
end
local event={player_id_const=0,reason_const=10,gold=1}
D.GoldFilter({playerId=0,campaignDifficultyInstalled=true},event);eq(event.gold,0)
-- No native stats editing; standard selection is bounded by the post-upgrade
-- budget. Neutrals retain their original tier; separate bundles scale value once.
local randomCalls=0
local function first(a,b) randomCalls=randomCalls+1;return a end
for _, row in ipairs(Loot.Catalog) do
    eq(Loot.ScaleEquipment({},row,first),row)
    for _, name in ipairs({"easy","hard"}) do
        local game={campaignDifficulty=name}
        local scaled=Loot.ScaleEquipment(game,row,first)
        if row.category=="standard" and row.cost>0 then
            if scaled then assert(scaled.cost<=D.Scale(game,row.cost));eq(scaled.category,"standard") end
        elseif row.neutral then
            eq(scaled,row) -- no tier scaling on top of neutral bundle budget
        else eq(scaled,row) end
    end
end
local before=randomCalls;Loot.ScaleEquipment({},Loot.Catalog[1],first);eq(randomCalls,before)
eq(Loot.ScaleEquipment({campaignDifficulty="hard"},{category="standard",cost=1},first),nil)
local pending={delivery="item_foragers_kit",name="item_foragers_kit"}
Loot.UpgradePendingNeutral({campaignDifficulty="hard",currentLevelId="ch13"},pending)
local once=pending.delivery;Loot.UpgradePendingNeutral({campaignDifficulty="hard",currentLevelId="ch13"},pending);eq(pending.delivery,once)
-- Loss compensation once per threshold, fixed utility rewards and delivery retries.
for _, name in ipairs({"easy","default","hard"}) do
    local game={campaignDifficulty=name,gold=500,AddGold=function(self,n) self.gold=self.gold+n end}
    eq(Lives.Lose(game).gold,0)
    eq(Lives.Lose(game).gold,D.Scale(game,2000));eq(game.gold,500+D.Scale(game,2000))
    eq(Lives.Lose(game).gold,0);eq(#Lives.Lose(game).items,2);Lives.Lose(game);Lives.Lose(game)
    eq(game.gold,500+D.Scale(game,2000))
end
-- Progression primitives remain fixed value: shop-bought XP cannot be amplified,
-- stage reward is scaled by settlement before one normal active/bench award.
local Progression={};require("patches.progression_patch").Install(Progression)
for _,name in ipairs({"easy","default","hard"}) do
    local game=setmetatable({campaignDifficulty=name,lineup={"a"},ownedHeroes={"a","b"},
        heroData={a={level=1,current_xp=0},b={level=1,current_xp=0}}},{__index=Progression})
    game:AddXpToHero("a",20);eq(game.heroData.a.current_xp,20)
    game:AwardStageXp(D.Scale(game,7));eq(game.heroData.a.current_xp,20+D.Scale(game,7))
    eq(game.heroData.b.current_xp,math.floor(D.Scale(game,7)*.5))
    game:AwardStageXp(D.Scale(game,0));eq(game.heroData.a.current_xp,20+D.Scale(game,7))
end
-- Installed server boundary: connection/recovery publication, exact native filter
-- registration, owner confirmation, campaign start/economy lock, arena bypass.
local listeners,filters,events={}, {}, {}
GameRules={GetGameTime=function() return 5 end,GetGameModeEntity=function() return {
    SetModifyGoldFilter=function(_,fn,context) filters.gold=function(e)return fn(context,e)end end,
    SetModifyExperienceFilter=function(_,fn,context) filters.xp=function(e)return fn(context,e)end end,
} end}
PlayerResource={GetPlayer=function(_,id) return id==0 and {} or nil end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_,player,name,payload) events[#events+1]={name=name,payload=payload} end}
g={playerId=0,phase="setup",OnStartBattle=function() return "started" end,
    OnShopBuy=function() return "bought" end,RequestStateRecovery=function() return "recovered" end}
D.Install(g);D.Install(g);assert(filters.gold and filters.xp)
eq(g:RequestStateRecovery(0),"recovered");eq(events[#events].payload.campaign_difficulty,"default")
eq(g:OnStartBattle(),false);eq(g:OnShopBuy(),false)
listeners.rpg_campaign_difficulty_select(nil,{PlayerID=1,difficulty="easy"});assert(not g.campaignDifficultyLocked)
listeners.rpg_campaign_difficulty_select(nil,{PlayerID=0,difficulty="easy"});eq(g:OnStartBattle(),"started");eq(g:OnShopBuy(),"bought")
eq(events[#events].payload.reward_multiplier,1.5)
g:RequestStateRecovery(0);eq(events[#events].payload.campaign_difficulty,"easy");eq(events[#events].payload.difficulty_locked,1)
-- Non-default data never reaches strict/unsegmented remote v1, including direct
-- submit entry. Local finish/settlement/reconnect retain explicit metadata.
CreateHTTPRequestScriptVM=function() error("non-default submission escaped guard") end
for _, name in ipairs({"easy","hard"}) do
    local game={playerId=0,campaignDifficulty=name,campaignDifficultyLocked=true,settlementGeneration=1,
        runLives={remaining=0},phase="result",runComplete=true}
    Results.Reset(game);local settlement={};local summary=Results.Finish(game,false,settlement)
    eq(summary.status,"difficulty_unranked");eq(summary.campaign_difficulty,name)
    eq(settlement.reward_multiplier,D.Multiplier(game));assert(not game.leaderboardRun.payload)
    Results.SendTerminal(game);Results.Submit(game,game.leaderboardRun);Results.Resend(game,0)
end
print("PASS campaign difficulty: validation/lock/recovery, reward rounding, native reason filters, arena isolation, catalog budgets, loss thresholds, leaderboard guards")
