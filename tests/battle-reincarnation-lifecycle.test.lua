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
        or name == "battle.run_lives" then return nativeRequire(name) end
    if name == "battle.tempest_double" then return hooks end
    return { Install=function() end, OnThink=function() end, Clear=function() end,
        Write=function(message) logs[#logs+1]=message end, Event=function() end }
end
dofile(modules .. "addon_game_mode.lua")
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
        tacticBridge={OnThink=function() aiTicks=aiTicks+1 end},
        BroadcastDamageStats=function() end, BroadcastBattleState=function() end,
        BroadcastShopState=function() end, BroadcastLevelInfo=function() end,
        SpawnLevelEnemies=function() end, RespawnPlayerRoster=function(self) self.rebuilt=true end,
        SpawnBattleBarrier=function() end, RollShop=function(self) self.shopOffers={} end,
        refreshCount=0, AwardStageXp=function() end, AddGold=function() end,
    },CDota2RpgDemo)
    local bm=setmetatable({},BattleManager); bm:constructor(g); g.battleManager=bm
    local wk,enemy=unit(true,false),unit(true,false)
    bm.teamHeroes={[2]={wk},[3]={enemy}}; bm:StartBattle({})
    return g,bm,wk,enemy
end
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
