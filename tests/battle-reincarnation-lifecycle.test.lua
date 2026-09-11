-- Exercise the real root think/settlement boundary, not only CheckBattleEnd.
local root = TEST_REPO_ROOT or "."
local modules = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
package.path = modules .. "?.lua;" .. package.path
function class() local c = {}; c.__index = c; return c end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2,3
function IsValidEntity(u) return u ~= nil and not u.invalid end
local nativeRequire = require
local logs = {}
local hooks = { OnThink = function() end, Clear = function() end }
require = function(name)
    if name == "battle.battle_manager" or name == "battle.unit_helpers"
        or name == "battle.item_cooldowns"
        or name == "battle.fresh_run" or name == "battle.run_lives" or name == "battle.respawn_policy" then return nativeRequire(name) end
    if name == "battle.campaign_loot" then return {Award=function() return {} end} end
    if name == "battle.tempest_double" then return hooks end
    if name == "issue_fixes.hero_lifecycle_log" then return {Event=function() end,
        Remove=function(g,u) assert(g.ruleGeneration > 0); u.removed=true end} end
    return { Install=function() end, OnThink=function() end, Clear=function() end,
        Write=function(message) logs[#logs+1]=message end, Event=function() end }
end
dofile(modules .. "addon_game_mode.lua")
-- Install the real fresh-start recruitment defaults (not a duplicated constant).
local savedRequire=require; require=nativeRequire
nativeRequire("patches.recruitment_patch").Install(CDota2RpgDemo)
require=savedRequire
local now, callback, events, payload, orders, aiTicks
GameRules = { GetGameTime=function() return now end,
    GetGameModeEntity=function() return { SetContextThink=function(_,name,fn,delay)
        assert(name == "Dota2RpgBackToSetup" and delay == 3)
        assert(callback == nil, "one setup callback")
        callback = fn
    end } end }
CustomGameEventManager = { Send_ServerToAllClients=function(_,event,data)
    assert(event == "rpg_settlement"); events=events+1; payload=data
end }
local function unit(alive,reviving)
    return { alive=alive, reviving=reviving, IsNull=function() return false end,
        IsAlive=function(s) return s.alive end, IsReincarnating=function(s) return s.reviving end,
        Stop=function() orders=orders+1 end, SetIdleAcquire=function() end }
end
local function fixture()
    now,callback,events,payload,orders,aiTicks=0,nil,0,nil,0,0
    logs={}
    hooks.OnThink=function() end; hooks.Clear=function() end
    local g=setmetatable({phase="fight", teamsSpawned=true, currentLevelId="ch01",
        orderedLevels={"ch01","ch02"}, lineup={"wk"}, runLives={remaining=5,pendingItems={}},
        dataLoader={GetLevel=function() return {reward={gold=0,xp_per_active_hero=0}} end},
        tacticBridge={OnThink=function() aiTicks=aiTicks+1 end, ResetState=function() end,
            ruleService={state={rules={old=true}}}},
        GetStashUnit=function(s) return s.stash end,
        BroadcastHeroInfo=function() end,
        BroadcastDamageStats=function() end, BroadcastBattleState=function() end,
        BroadcastShopState=function() end, BroadcastLevelInfo=function() end,
        SpawnLevelEnemies=function() end, RespawnPlayerRoster=function(self) self.rebuilt=true end,
        SpawnBattleBarrier=function() end, RollShop=function(self) self.shopOffers={} end,
        refreshCount=0, AwardStageXp=function() end, AddGold=function() end, CalculateTimeBonus=function() return 0 end,
    },CDota2RpgDemo)
    local bm=setmetatable({},BattleManager); bm:constructor(g); g.battleManager=bm
    local wk,enemy=unit(true,false),unit(true,false)
    bm.teamHeroes={[2]={wk},[3]={enemy}}; bm:StartBattle({})
    return g,bm,wk,enemy
end
for _,winner in ipairs({"radiant", "dire", "draw", "timeout"}) do
    local g,bm,wk=fixture()
    local item={remaining=40,charges=2,custom={used=true},EndCooldown=function(s) s.remaining=0 end}
    wk.GetItemInSlot=function(_,slot) if slot==8 then return item end end
    wk.alive=winner=="radiant"
    g:EndBattle(winner,winner=="radiant" and 2 or 3)
    assert(item.remaining==0 and item.charges==2 and item.custom.used,
        "all settlement outcomes refresh dead/live inventory before delayed setup")
    assert(callback and not g.rebuilt)
end
print("PASS: immediate item cooldown refresh across victory, defeat, draw and timeout")
for _,rebornAtDeadline in ipairs({false,true}) do
    local g,bm,wk=fixture()
    assert(g:OnThink()==0.1 and aiTicks==1)
    now=20; wk.alive=false; wk.reviving=true
    g:OnThink(); assert(g.phase=="fight" and events==0 and bm:GetAliveCount(2)==0)
    now=23; wk.alive=true; wk.reviving=false
    g:OnThink(); assert(g.phase=="fight" and events==0)
    now=119.9; wk.alive=false; wk.reviving=true; g:OnThink()
    now=120; wk.alive=rebornAtDeadline; wk.reviving=not rebornAtDeadline
    local before=aiTicks; g:OnThink()
    assert(g.phase=="result" and bm.phase=="settle" and events==1)
    assert(payload.winner=="timeout" and payload.clear_time==120 and g.runLives.remaining==4)
    assert(aiTicks==before, "no AI after settlement")
    g:OnThink(); g:EndBattle("timeout",3); assert(events==1 and g.runLives.remaining==4)
    now=123; callback(); callback()
    assert(g.phase=="setup" and g.rebuilt and g.currentLevelId=="ch01")
    g.phase="fight"; bm:StartBattle({}); assert(bm:GetTimeLeft()==120)
end
print("PASS: root think -> WK death/rebirth -> deadline -> one settlement/life -> setup -> fresh battle")
-- Inject native boundary failures: upkeep must keep ticking and independent
-- cleanup/broadcast failures must not strand an already-claimed settlement.
local function logged(stage, message)
    for _, line in ipairs(logs) do
        if line:find("step="..stage,1,true) and line:find(message,1,true)
            and line:find("stack traceback",1,true) then return true end
    end
    return false
end
do
    local g,bm=fixture(); now=120
    hooks.OnThink=function() error("injected lifecycle tick failure") end
    assert(g:OnThink()==0.1)
    assert(g.phase=="result" and bm.phase=="settle" and events==1 and callback)
    assert(g.runLives.remaining==4 and logged("tempest_think","injected lifecycle tick failure"))
    g:OnThink(); g:EndBattle("timeout",3)
    assert(events==1 and g.runLives.remaining==4)
    now=123; callback(); assert(g.phase=="setup" and g.rebuilt)
end
do
    local g,bm=fixture(); now=120
    hooks.Clear=function() error("injected settlement cleanup failure") end
    assert(g:OnThink()==0.1)
    assert(g.phase=="result" and bm.phase=="settle" and events==1 and callback)
    assert(logged("tempest_clear","injected settlement cleanup failure"))
    now=123; callback(); callback()
    assert(g.phase=="setup" and g.rebuilt and g.runLives.remaining==4)
end
do
    local g,bm=fixture(); now=120
    g.damageStats={Stop=function(self) self.stopped=true end}
    g.BroadcastDamageStats=function() error("injected damage broadcast failure") end
    g.BroadcastBattleState=function() error("injected result broadcast failure") end
    g:OnThink()
    assert(g.damageStats.stopped and events==1 and callback and bm.phase=="settle")
    assert(logged("damage_final_broadcast","injected damage broadcast failure"))
    assert(logged("result_broadcast","injected result broadcast failure"))
    -- A new test session must invalidate the old round's deferred setup callback.
    g.settlementGeneration=g.settlementGeneration+1
    callback(); assert(g.phase=="result" and not g.rebuilt)
end
do
    local g=fixture()
    hooks.OnThink=function() error("repeated tick failure") end
    for tick=1,20 do now=tick*.1; assert(g:OnThink()==0.1) end
    assert(#logs==1, "same failing hook must not flood the console every tick")
    assert(g.phase=="fight" and aiTicks==20, "independent tactics still run before the deadline")
end
print("PASS: lifecycle/cleanup/broadcast exceptions preserve deadline and settlement; traces throttled; stale callback rejected (native APIs mocked)")

for _,winner in ipairs({"radiant", "dire", "timeout", "draw"}) do
    local g,bm=fixture()
    g.playerId=0; g.currentLevelId="ch02"
    g.runLives.remaining=winner=="radiant" and 5 or 1
    local build={inventory={"item_blink"}, level=20}; g.heroData={wk=build}
    g.heroRulesByName={wk={{action="attack"}}}; local rules=g.heroRulesByName
    g.gold=1234; g.GetGoldBalance=function(s) return s.gold end
    g.refreshCount=7; g.scrollPurchases={low=3,high=2}
    local function item() return {IsNull=function(s) return s.removed==true end,
        RemoveSelf=function(s) s.removed=true end} end
    local stashItem, groundItem, orphanItem, heroItem = item(), item(), item(), item()
    local drop=item(); drop.GetContainedItem=function() return groundItem end
    Entities={FindAllByClassname=function() return {drop} end}
    g.stash={GetItemInSlot=function(_,slot) if slot==16 then return stashItem end end,
        permanent={moon=true,shard=true,blessing=true},xp=5000}
    g.placeholderHero=g.stash
    g.OnNpcSpawned=function(s) s.placeholderHero.rpgPlaceholderReady=true end
    local commanderReplacements=0
    PlayerResource={ReplaceHeroWith=function(_,id,name,gold,xp)
        assert(id==0 and name=="npc_dota_hero_wisp" and gold==0 and xp==0)
        commanderReplacements=commanderReplacements+1
        local fresh={permanent={},xp=0,IsNull=function() return false end,
            RemoveModifierByName=function() end,entindex=function() return 900 end,GetItemInSlot=function() end}
        g.stash=fresh
        return fresh
    end}
    bm.teamHeroes[2][1].GetItemInSlot=function(_,slot) if slot==0 then return heroItem end end
    g.runLives.pendingItems={{item=orphanItem}}
    local bench=unit(true,false); g.benchUnits={bench}; g.pendingEnemyCleanup={bench}
    g.ownedHeroes={"wk"}; g.benchSlots=4; g.heroData.wk.purchased_shard=true
    g.scrollStock={low=9,high=8}; g.scrollBought={low=7,high=6}
    local tableFields={"heroInventories","autoAbilityHeroes","placedPositions","pendingNativePurchases",
        "nativePurchaseOrderContexts","nativePurchaseClaimedIds","nativeOrderSignatures",
        "nativePurchaseBaseline","nativePurchaseObservedStates"}
    local nilFields={"nativePurchaseSelectionHero","nativeShopTransactionPending","rosterAbilitySnapshot",
        "equipmentSnapshot","lastBroadcastGold","encounterSeed","shardPurchaseBusy","shardRestockAt"}
    for _,f in ipairs(tableFields) do g[f]={old=true} end
    for _,f in ipairs(nilFields) do g[f]="old" end
    local cache={ready=true}; g.stagePrecache=cache
    local stalePurchase, purchased = nil, 0
    g.recruitPrecache={cached="ready"}
    PrecacheUnitByNameAsync=function(_, cb) stalePurchase=cb end
    local heroCache=nativeRequire("issue_fixes.hero_precache")
    assert(not heroCache.Request(g,"pending_hero",function() purchased=purchased+1 end))
    g.enemySpawnRequest={old=true}; g.stageLoading=true
    local setupStates,rebuilt,enemies,barriers,rolls=0,0,0,0,0
    g.BroadcastBattleState=function(s)
        local data=s:BuildBattleState()
        if s.phase=="result" then assert(data.replay_available==1 and data.run_complete==1) end
        if s.phase=="setup" then setupStates=setupStates+1; assert(data.ready==1 and data.replay_available==0) end
    end
    local request
    g.RespawnPlayerRoster=function(s)
        rebuilt=rebuilt+1
        assert(s.phase=="setup" and not s.runComplete and s.runLives.remaining==5)
        assert(not s:OnReplayRun(0,request), "reentrant replay cannot rebuild twice")
    end
    g.SpawnLevelEnemies=function(s,id) enemies=enemies+1; assert(id==s.currentLevelId); s.preparedEnemyLevel=id end
    g.SpawnBattleBarrier=function() barriers=barriers+1 end
    g.RollShop=function(s) rolls=rolls+1; s.shopOffers={} end
    g:EndBattle(winner,winner=="radiant" and 2 or 3)
    assert(g.runComplete and g.phase=="result" and callback==nil)
    request={PlayerID=0,settlement_generation=g.settlementGeneration}
    assert(not g:OnReplayRun(0,{settlement_generation=request.settlement_generation}))
    assert(not g:OnReplayRun(0,{PlayerID=1,settlement_generation=request.settlement_generation}))
    assert(not g:OnReplayRun(0,{PlayerID=0,settlement_generation=request.settlement_generation-1}))
    g.skillDebug={pending=true}; assert(not g:OnReplayRun(0,request))
    g.skillDebug={active=true}; assert(not g:OnReplayRun(0,request)); g.skillDebug=nil
    assert(g:OnReplayRun(0,request)); assert(not g:OnReplayRun(0,request))
    assert(rebuilt==1 and enemies==1 and barriers==1 and rolls==1 and setupStates==1)
    assert(g.currentLevelId=="ch01", "all terminal replays restart chapter one")
    assert(g.refreshCount==0 and g.scrollPurchases.low==0 and g.scrollPurchases.high==0)
    assert(next(g.heroData)==nil and next(g.heroRulesByName)==nil and g.heroRulesByName~=rules)
    assert(g.gold==500 and g.freeRecruitChoices==2 and g.benchSlots==0)
    assert(commanderReplacements==1 and g.placeholderHero==g.stash and g.stash.rpgPlaceholderReady)
    assert(next(g.stash.permanent)==nil and g.stash.xp==0, "commander native consumable flags/XP are not retained")
    assert(stashItem.removed and groundItem.removed and orphanItem.removed and heroItem.removed and drop.removed and bench.removed)
    for _,f in ipairs(tableFields) do assert(next(g[f])==nil, f) end
    for _,f in ipairs(nilFields) do assert(g[f]==nil, f) end
    assert(g.stagePrecache==cache and g.enemySpawnRequest==nil and not g.stageLoading)
    stalePurchase()
    assert(purchased==0 and g.recruitPrecache.pending_hero==nil, "old captured precache table cannot purchase into a fresh run")
    assert(g.recruitPrecache.cached=="ready", "completed asset knowledge is not progression")
    assert(#g.runLives.pendingItems==0 and g.scrollStock.low==0 and g.scrollBought.high==0)
    assert(g.nativePurchaseTransactionId==0 and g.nativePurchaseTick==0)
    assert(bm.battleStartedAt==nil and bm.phase=="prepare")
    assert(next(g.lineup)==nil and next(g.ownedHeroes)==nil)
    assert(next(g.tacticBridge.ruleService.state.rules)==nil and g.ruleGeneration==1)
    g.phase="fight"; bm:StartBattle({}); assert(bm:GetTimeLeft()==120)
    g.runLives.remaining=1; g:EndBattle("dire",3)
    assert(not g:OnReplayRun(0,request), "old result request rejected at later terminal")
    request={PlayerID=0,settlement_generation=g.settlementGeneration}
    assert(g:OnReplayRun(0,request) and rebuilt==2)
end
do
    local g=fixture(); g.playerId=0
    g:EndBattle("dire",3); local oldSetup=callback
    -- An old automatic transition can still be queued when another lifecycle starts.
    g.settlementGeneration=g.settlementGeneration+1
    g.runComplete=true; g.runFailed=true
    assert(g:OnReplayRun(0,{PlayerID=0,settlement_generation=g.settlementGeneration}))
    g.rebuilt=false; g.phase="result"; oldSetup()
    assert(not g.rebuilt and g.phase=="result", "old delayed setup cannot reset a replay")
end
do
    local g=fixture(); g.playerId=0; g.phase="result";g.runComplete=true;g.settlementGeneration=10
    g.placeholderHero={IsNull=function() return false end}
    PlayerResource={ReplaceHeroWith=function() return nil end}
    assert(not g:OnReplayRun(0,{PlayerID=0,settlement_generation=10}))
    assert(g.phase=="result" and g.runComplete and g.settlementGeneration==11,
        "native reset failure remains locked and can be retried with a new result generation")
end
print("PASS real EndBattle/replay: all terminal outcomes, owner/generation gates, reentrancy, fresh empty build/wallet/rules, five lives, unit rebuild, fresh deadline, old timer invalidation")
