local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Score = require("battle.run_score")
local Results = require("battle.run_results")

-- Exhaust the score space and preserve difficulty scaling.
local maxFailure, minClear = 0, math.huge
for hearts = 0, 5 do
    for stages = 0, 30 do
        local base = Score.Calculate(hearts, stages, 0, false)
        if hearts < 5 then assert(Score.Calculate(hearts + 1, stages, 0, false).score > base.score) end
        if stages < 30 then assert(Score.Calculate(hearts, stages + 1, 0, false).score > base.score) end
        local timed = Score.Calculate(hearts, stages, stages * 120000, false)
        assert(timed.core_score == base.core_score and timed.time_bonus_score == stages * 1200)
        if stages < 30 then maxFailure = math.max(maxFailure, timed.score) end
        for name, numerator in pairs({easy=7, default=10, hard=20}) do
            local scaled = Score.Calculate(hearts, stages, stages * 120000, false, name)
            assert(scaled.score == math.floor(timed.score * numerator / 10))
            assert(scaled.remaining_time_ms == timed.remaining_time_ms and scaled.base_score == timed.score)
        end
    end
    if hearts > 0 then minClear = math.min(minClear, Score.Calculate(hearts, 30, 0, true).score) end
end
assert(minClear > maxFailure)
assert(Score.Calculate(5, 30, 3600000, true).score == 1456000)
assert(Score.Calculate(0, 0, 0, false).score == 100000)

local clock, requests, timers, identities, events = 0, 0, 0, 0, {}
GameRules = {GetGameTime=function() return clock end, GetGameModeEntity=function() return {
    SetContextThink=function() timers=timers+1 end,
} end}
Timers = {CreateTimer=function() timers=timers+1 end}
local function identity() identities=identities+1; error("campaign must not collect identity") end
PlayerResource = {GetSteamAccountID=identity, GetSteamID=identity, GetPlayerName=identity,
    GetPlayer=function(_,id) return id end}
CustomGameEventManager = {Send_ServerToPlayer=function(_,player,event,payload)
    assert(event == "rpg_run_result")
    assert(payload.status == "disabled" and payload.submission_id == nil and payload.steam_id == nil)
    local copy={}; for k,v in pairs(payload) do copy[k]=v end
    events[#events+1]={player=player,event=event,data=copy}
end}
CreateHTTPRequestScriptVM = function() requests=requests+1; error("offline HTTP forbidden") end
CreateHTTPRequest = CreateHTTPRequestScriptVM
LoadKeyValues = function() error("offline result must not load host keys") end
GetDedicatedServerKeyV3 = LoadKeyValues
local function game()
    local g={orderedLevels={},currentLevelId="ch01",playerId=0,settlementGeneration=0,runLives={remaining=5}}
    for i=1,30 do g.orderedLevels[i]=string.format("ch%02d",i) end
    Results.Reset(g)
    return g
end
local function settle(g,win,elapsed,remaining)
    Results.StartBattle(g)
    clock=clock+elapsed
    g.settlementGeneration=g.settlementGeneration+1
    Results.RecordBattle(g,win,elapsed,remaining)
end
local g=game()
settle(g,true,20,100)
Results.RecordBattle(g,true,20,100)
assert(g.runResults.completed==1 and g.runResults.remainingMs==100000)
g.currentLevelId="ch02"
settle(g,false,120,0)
assert(g.runResults.completed==1 and g.runResults.remainingMs==100000)
for i=2,30 do
    g.currentLevelId=string.format("ch%02d",i)
    settle(g,true,120,0)
end
assert(g.runResults.eligible)
g.phase,g.runComplete="result",true
local settlement={}
local summary=Results.Finish(g,true,settlement)
assert(summary.remaining_time_ms==100000 and summary.stage_count==30 and settlement.run_complete==1)
assert(summary.remaining_hearts==5 and summary.settlement_generation==31)
assert(summary.status=="disabled" and settlement.status=="disabled")
assert(g.runResults.payload==nil and summary.submission_id==nil)
for key,value in pairs(summary) do assert(settlement[key]==value) end
assert(Results.Finish(g,false,{})==summary, "finish must settle once")
Results.SendTerminal(g)
Results.SendTerminal(g)
assert(#events==2)
local before=#events
Results.Resend(g,1)
assert(#events==before)
Results.Resend(g,0)
assert(#events==before+1 and events[#events].data.score==summary.score)

-- Replay discards all prior accounting and suppresses old results.
local old=g.runResults
Results.Reset(g)
g.phase,g.runComplete="setup",false
before=#events
Results.Publish(g,old)
Results.SendTerminal(g)
Results.Resend(g,0)
assert(#events==before)
assert(g.runResults.completed==0 and g.runResults.remainingMs==0)
assert(next(g.runResults.generations)==nil and g.runResults.result==nil)
g.currentLevelId="ch01"
settle(g,true,10,110)
assert(g.runResults.completed==1 and g.runResults.remainingMs==110000)

local failure=game()
settle(failure,false,120,0)
failure.runLives.remaining=0
failure.phase,failure.runComplete="result",true
local failed=Results.Finish(failure,false,{})
assert(failed.remaining_hearts==0 and failed.stage_count==0 and failed.status=="disabled")
Results.SendTerminal(failure)
assert(events[#events].data.score==failed.score and failure.runResults.payload==nil)
local practice=game()
practice.currentLevelId="ch30"
settle(practice,true,1,119)
assert(Results.Finish(practice,true,{}).status=="disabled")
local debug=game()
IsInToolsMode=function() return true end
settle(debug,false,120,0)
assert(Results.Finish(debug,false,{}).status=="disabled")
IsInToolsMode=nil
Results.Invalidate(debug)
assert(debug.runResults.eligible==false)
assert(requests==0 and timers==0 and identities==0, "all finish/publish/replay/resend paths must stay offline")
print("PASS offline run results: score, difficulty scaling, lives, generations, local events, replay; zero HTTP, timers, identity reads")
