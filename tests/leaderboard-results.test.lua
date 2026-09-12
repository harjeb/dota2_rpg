local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Score = require("battle.run_score")
local Results = require("battle.run_results")
local Json = require("lib.json")
local Config = require("data.leaderboard_config")

-- Exhaust the v1 space: every clear dominates even a theoretical five-heart
-- nonclear; each dimension is monotonic, time stays an independent addend.
local maxFailure, minClear = 0, math.huge
for hearts = 0, 5 do
    for stages = 0, 30 do
        local base = Score.Calculate(hearts, stages, 0, false)
        if hearts < 5 then assert(Score.Calculate(hearts + 1, stages, 0, false).score > base.score) end
        if stages < 30 then assert(Score.Calculate(hearts, stages + 1, 0, false).score > base.score) end
        local timed = Score.Calculate(hearts, stages, stages * 120000, false)
        assert(timed.core_score == base.core_score and timed.time_bonus_score == stages * 1200)
        if stages < 30 then maxFailure = math.max(maxFailure, timed.score) end
    end
    if hearts > 0 then minClear = math.min(minClear, Score.Calculate(hearts, 30, 0, true).score) end
end
assert(minClear > maxFailure)
assert(Score.Calculate(5, 30, 3600000, true).score == 1456000)
assert(Score.Calculate(0, 0, 0, false).score == 100000)
assert(Score.Calculate(5, 0, 0, false).core_score == 210000)
assert(Score.Calculate(0, 30, 0, false).core_score == 200000)
assert(Results.SteamId(1) == "76561197960265729")
assert(Results.SteamId(4294967295) == "76561202255233023")
assert(Results.SteamId(0) == nil and Results.SteamId(1.5) == nil)
assert(Json.decode(Json.encode({name='玩家"\\测试', steam_id=Results.SteamId(1)})).steam_id == "76561197960265729")

local clock, requests, events, timers = 0, {}, {}, {}
GameRules = {GetGameTime=function() return clock end, GetGameModeEntity=function() return {
    SetContextThink=function(_, name, fn, delay) timers[#timers+1]={fn=fn,delay=delay} end,
} end}
PlayerResource = {GetSteamAccountID=function() return 1 end, GetPlayerName=function() return "玩家" end,
    GetPlayer=function(_,id) return id end}
CustomGameEventManager = {Send_ServerToPlayer=function(_,player,event,payload)
    local copy={};for k,v in pairs(payload) do copy[k]=v end
    events[#events+1]={player=player,event=event,data=copy}
end}
DoUniqueString = function() return "unique-1" end
-- A normal listen server has no host configuration or Valve key. Neither
-- may be read, and uploads must not depend on either API being available.
LoadKeyValues = function() error("automatic upload must not read a host key") end
GetDedicatedServerKeyV3 = function() error("no official server key on local hosts") end
IsDedicatedServer = function() return false end
Config.endpoint = "https://example.invalid"
CreateHTTPRequestScriptVM = function(method,url)
    local request={method=method,url=url}
    requests[#requests+1]=request
    function request:SetHTTPRequestHeaderValue(name,value) self[name]=value end
    function request:SetHTTPRequestAbsoluteTimeoutMS(timeout) self.timeout=timeout end
    function request:SetHTTPRequestRawPostBody(content,body) self.body=body end
    function request:Send(callback) self.callback=callback end
    return request
end
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
Results.RecordBattle(g,true,20,100) -- duplicate generation ignored
assert(g.leaderboardRun.completed==1 and g.leaderboardRun.remainingMs==100000)
g.currentLevelId="ch02"
settle(g,false,120,0)
assert(g.leaderboardRun.completed==1 and g.leaderboardRun.remainingMs==100000)
for i=2,30 do
    g.currentLevelId=string.format("ch%02d",i)
    clock=clock+5 -- setup time belongs in duration, not rank time
    settle(g,true,120,0)
end
g.phase,g.runComplete="result",true
local settlement={}
local summary=Results.Finish(g,true,settlement)
assert(summary.remaining_time_ms==100000 and summary.stage_count==30 and settlement.run_complete==1)
assert(g.leaderboardRun.payload.speedrun_time_ms==100000)
assert(g.leaderboardRun.payload.run_duration_ms>30*120000)
Results.SendTerminal(g)
Results.SendTerminal(g)
assert(#requests==1 and #events==2)
assert(requests[1].Authorization==nil and requests[1].method=="POST")
assert(Json.decode(requests[1].body).steam_id=="76561197960265729")
requests[1].callback({StatusCode=503})
assert(#timers==1 and timers[1].delay==2)
timers[1].fn()
assert(#requests==2 and requests[2].body==requests[1].body and requests[2].Authorization==nil)
local result={submission_id=g.leaderboardRun.payload.submission_id,rankings={
    score={rank=1,total=7,personal_record=true,global_record=true,first_entry=false},
    speedrun={rank=3,total=4,personal_record=false,global_record=false,first_entry=true},
}}
local me=g.leaderboardRun.payload.steam_id
result.leaderboards={score={total=7,player_rank=1,rows={}},speedrun={total=4,player_rank=3,rows={}}}
for i=1,5 do
    result.leaderboards.score.rows[i]={rank=i,steam_id=i==1 and me or Results.SteamId(i+10),
        player_name=i==1 and '玩家 <b>"你好"</b>' or "邻居"..i,value=1400000-i,is_self=0,payload_hash="not a HUD field"}
end
for i=1,4 do
    result.leaderboards.speedrun.rows[i]={rank=i,steam_id=i==3 and me or Results.SteamId(i+10),
        player_name="速通玩家"..i,value=i==1 and 0 or i,is_self=1}
end
requests[2].callback({StatusCode=201,Body=Json.encode(result)})
assert(events[#events].data.status=="success" and events[#events].data.score_rank==1)
local mapped=events[#events].data
assert(mapped.score_list_available==1 and mapped.score_list_count==5 and mapped.score_list_player_rank==1)
assert(mapped.speedrun_list_available==1 and mapped.speedrun_list_count==4 and mapped.speedrun_list_player_rank==3)
assert(mapped.score_row_1_name=='玩家 <b>"你好"</b>' and mapped.score_row_1_is_self==1)
assert(mapped.speedrun_row_1_value==0 and mapped.speedrun_row_1_is_self==0 and mapped.speedrun_row_3_is_self==1)
assert(mapped.leaderboards==nil and mapped.score_row_1_payload_hash==nil and mapped.score_row_1_steam_id==nil)
assert(#Json.encode(mapped)<16384, "bounded flat event fits comfortably within a game event")
assert(events[#events].data.score_global_record==1 and events[#events].data.speedrun_first_entry==1)
local before=#events
Results.Resend(g,1)
assert(#events==before)
Results.Resend(g,0)
assert(#events==before+1)
assert(events[#events].data.score_row_1_name==mapped.score_row_1_name and events[#events].data.speedrun_row_3_is_self==1)

-- Replay suppresses late old-run UI while preserving the in-flight submission.
local old=g.leaderboardRun
Results.Reset(g)
g.phase,g.runComplete="setup",false
before=#events
Results.Publish(g,old)
assert(#events==before)
local failure=game()
settle(failure,false,120,0)
failure.runLives.remaining=0
failure.phase,failure.runComplete="result",true
Results.Finish(failure,false,{})
assert(failure.leaderboardRun.payload.speedrun_time_ms==nil)
Results.SendTerminal(failure)
local pending=requests[#requests]
local body=pending.body
Results.Reset(failure)
failure.phase,failure.runComplete="setup",false
before=#events
pending.callback({StatusCode=500})
timers[#timers].fn()
assert(requests[#requests].body==body)
requests[#requests].callback({StatusCode=400})
assert(#events==before)

local function detailCase(details)
    local f=game()
    settle(f,false,120,0)
    f.runLives.remaining=0
    f.phase,f.runComplete="result",true
    Results.Finish(f,false,{})
    Results.SendTerminal(f)
    requests[#requests].callback({StatusCode=201,Body=Json.encode({submission_id=f.leaderboardRun.payload.submission_id,
        rankings={score={rank=1,total=1}},leaderboards=details})})
    assert(f.leaderboardRun.result.status=="success", "missing detail must not turn accepted score into failed upload")
    return f.leaderboardRun.result
end
local noDetail=detailCase(nil)
assert(noDetail.score_list_available==0 and noDetail.speedrun_list_available==0 and noDetail.score_rank==1)
local empty=detailCase({speedrun={total=0,rows={}}})
assert(empty.speedrun_list_available==1 and empty.speedrun_list_count==0 and empty.speedrun_list_player_rank==0)
local prior=detailCase({speedrun={total=1,player_rank=1,rows={{rank=1,steam_id=me,player_name="旧纪录",value=0}}}})
assert(prior.speedrun_list_available==1 and prior.speedrun_row_1_is_self==1 and prior.speedrun_rank==nil)
local tooMany={total=20,rows={}}
for i=1,11 do tooMany.rows[i]={rank=i,steam_id=Results.SteamId(i+10),player_name="邻居",value=i} end
assert(detailCase({score=tooMany}).score_list_available==0)
local duplicate={total=2,rows={{rank=1,steam_id=Results.SteamId(10),player_name="邻居",value=1},
    {rank=2,steam_id=Results.SteamId(10),player_name="重复",value=2}}}
assert(detailCase({score=duplicate}).score_list_available==0)
local badSelf={total=2,player_rank=2,rows={{rank=1,steam_id=me,player_name="错误名次",value=1}}}
assert(detailCase({score=badSelf}).score_list_available==0)
local unordered={total=2,rows={{rank=2,steam_id=Results.SteamId(10),player_name="后",value=2},
    {rank=1,steam_id=Results.SteamId(11),player_name="前",value=1}}}
assert(detailCase({score=unordered}).score_list_available==0)

local practice=game()
practice.currentLevelId="ch30"
settle(practice,true,1,119)
assert(Results.Finish(practice,true,{}).status=="ineligible")
local debug=game()
IsInToolsMode=function() return true end
settle(debug,false,120,0)
assert(Results.Finish(debug,false,{}).status=="ineligible")
IsInToolsMode=nil
print("PASS permanent score, exact SteamID, run accounting, idempotent retry, rank mapping and replay isolation")
