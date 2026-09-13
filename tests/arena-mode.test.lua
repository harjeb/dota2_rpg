local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
local Json=require("lib.json")
local function copy(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
local names={"npc_dota_hero_axe","npc_dota_hero_lina","npc_dota_hero_sven","npc_dota_hero_lion","npc_dota_hero_lich","npc_dota_hero_zuus"}
local function team()
 local t={version="arena-team-v1",heroes={},storage={}}
 for i=1,5 do t.heroes[i]={id="h"..i,name=names[i],level=30,position={x=-700,y=i*50},facing=0,abilities={},ability_points=30,items={},shard=false,scepter=false,rules={}} end
 return t
end
local timers,listeners,events,requests={}, {}, {}, {}
local now,g,serverSeries,finishes=0,nil,{},0
local function unit(name) return {name=name,alive=true,IsNull=function() return false end,IsAlive=function(u) return u.alive end,GetUnitName=function(u) return u.name end} end
local function spawn(game,t,side)
 game.battleManager.teamHeroes[side]={}
 for _,h in ipairs(t.heroes) do game.battleManager.teamHeroes[side][#game.battleManager.teamHeroes[side]+1]=unit(h.name) end
 if side==2 then game.team=copy(t) end
 return true
end
package.loaded["battle.arena_profile"]={Copy=copy,Capture=function(game) return copy(game.team) end,Spawn=spawn,Clear=function(game,side) game.battleManager.teamHeroes[side]={} end}
for _,module in ipairs({"battle.tempest_double","tactics.special_targets","battle.summon_behavior","issue_fixes.tiny_tree"}) do package.loaded[module]={Clear=function() end} end
package.loaded["battle.respawn_policy"]={SetBattleActive=function() end}
package.loaded["battle.fresh_run"]={Reset=function(game) game.heroData={};game.pendingNativePurchases={};game.ownedHeroes={};game.lineup={};game.team=team();game.battleManager.teamHeroes={[2]={},[3]={}};game.runComplete=false;game.runFailed=false end}
LoadKeyValues=function() return {debug_heroes=names} end
PlayerResource={GetSteamAccountID=function() return 1 end,GetPlayerName=function() return "测试" end,GetPlayer=function(_,id) return id end}
GameRules={GetGameTime=function() return now end,GetGameModeEntity=function() return {SetContextThink=function(_,key,fn,delay) timers[key]={fn=fn,at=now+delay} end} end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,Send_ServerToPlayer=function(_,player,event,payload) events[#events+1]={event=event,payload=copy(payload)} end}
local unique=0
DoUniqueString=function() unique=unique+1;return "arena-"..unique end
RandomInt=function(a,b) return a end
PrecacheUnitByNameAsync=function(_,fn) fn() end
local failFinish,holdStart,held,abandoned=0,false,nil,0
CreateHTTPRequestScriptVM=function(method,url)
 local r={method=method,url=url}
 function r:SetHTTPRequestAbsoluteTimeoutMS(v) assert(v==15000) end
 function r:SetHTTPRequestRawPostBody(kind,body) assert(kind=="application/json");self.body=body end
 function r:Send(callback)
  requests[#requests+1]=self
  local body=self.body and Json.decode(self.body)
  local result,status={success=true},200
  if url:match("/players/") then result.rating=1500
  elseif url:match("/exports$") then result.url="https://dota2-rpg-leaderboard-api.dota2-rpg-leaderboard-worker.workers.dev/api/v1/arena/exports/"..string.rep("a",64);result.filename="team.json"
  elseif url:match("/abandon$") then abandoned=abandoned+1
  elseif url:match("/finish$") then
   if failFinish>0 then failFinish=failFinish-1;callback({StatusCode=503,Body="{}"});return true end
   finishes=finishes+1;assert(#body.rounds==7);serverSeries.final=copy(body.team);serverSeries.rounds=body.rounds
   result={success=true,rating_before=1500,rating_after=1600,rating_change=100,perfect_bonus=0,rounds={}}
   for i,r in ipairs(body.rounds) do result.rounds[i]={delta=r.won and 18 or -16} end
  elseif url:match("/series$") then
   result.series_id=body.submission_id;result.rating=1500;result.opponents={}
   for i=1,7 do result.opponents[i]={id="opponent"..i,player_name="Team "..i,rating=1400+i*30,preset=true,team=team()} end
   serverSeries=copy(result)
   if holdStart then held=function() callback({StatusCode=201,Body=Json.encode(result)}) end;return true end
  else error(url) end
  callback({StatusCode=status,Body=Json.encode(result)});return true
 end
 return r
end
local Arena=require("battle.arena_mode")
local function newGame()
 timers={};listeners={};events={};requests={};finishes=0;now=0;failFinish=0;holdStart=false;held=nil
 g={playerId=0,phase="setup",orderedLevels={"ch01","ch02"},currentLevelId="ch01",settlementGeneration=0,gold=500,heroData={},pendingNativePurchases={},lineup={},team=team()}
 g.battleManager={teamHeroes={[2]={},[3]={}},StopBattle=function() end}
 g.tacticBridge={ResetState=function() end}
 function g:RespawnPlayerRoster() spawn(self,self.team,2) end
 function g:SetGoldBalance(v) self.gold=v end
 function g:GetGoldBalance() return self.gold end
 function g:OnStartBattle() assert(self.arenaLaunching);self.phase="fight";self.starts=(self.starts or 0)+1 end
 for _,name in ipairs({"SpawnLevelEnemies","SpawnBattleBarrier","EnsureCommanderProtected","RollShop","BroadcastLevelInfo","BroadcastHeroInfo","BroadcastShopState","BroadcastBattleState","BroadcastDamageStats"}) do g[name]=function() end end
 Arena.Install(g);return g
end
local function action(name,payload)
 payload=payload or {};payload.PlayerID=payload.PlayerID or 0;payload.generation=payload.generation or g.arena.generation
 listeners["rpg_arena_"..name](nil,payload)
end
local function advance(delta)
 local untilTime=now+delta
 for guard=1,100 do
  local key,nextTimer
  for k,t in pairs(timers) do if t.at<=untilTime and (not nextTimer or t.at<nextTimer.at) then key,nextTimer=k,t end end
  if not key then now=untilTime;return end
  timers[key]=nil;now=nextTimer.at;nextTimer.fn()
 end
 error("timer loop")
end
local function enter()
 action("enter",{heroes_text=table.concat(names,";",1,5)})
 assert(g.arena.phase=="preparing",g.arena.error)
 assert(g.gold==99999 and Arena.CanBuy(g) and #g.lineup==5)
end
newGame()
assert(Arena.Mode(g)=="select" and not Arena.CanEdit(g) and not Arena.CanCampaign(g))
action("campaign",{PlayerID=1});assert(Arena.Mode(g)=="select")
action("campaign",{generation=-1});assert(Arena.Mode(g)=="select")
action("campaign");assert(Arena.CanCampaign(g));enter()
local count=#requests
action("export");assert(#requests==count+1)
assert(events[#events-1].event=="rpg_arena_export_result" or events[#events].event=="rpg_arena_export_result")
action("test",{strength="higher"})
assert(g.arena.practice and g.phase=="fight" and not Arena.CanEdit(g) and not Arena.CanBuy(g))
local income=g.gold;g.gold=income+2000
local droppedItem={IsNull=function(self) return self.removed end,RemoveSelf=function(self) self.removed=true end}
local dropped={IsNull=function(self) return self.removed end,GetContainedItem=function() return droppedItem end,RemoveSelf=function(self) self.removed=true end}
Entities={FindAllByClassname=function() return {dropped} end}
Arena.OnKilled(g,g.battleManager.teamHeroes[2][1]);Arena.OnKilled(g,g.battleManager.teamHeroes[2][1]);assert(g.arena.roundDeaths==1)
now=now+1;Arena.OnKilled(g,g.battleManager.teamHeroes[2][1]);assert(g.arena.roundDeaths==2)
Arena.EndBattle(g,"radiant");advance(2)
assert(g.arena.phase=="preparing" and not g.arena.practice and g.gold==income)
assert(dropped.removed and droppedItem.removed,"battle-dropped equipment cannot duplicate restored items")
Entities=nil
assert(#g.arena.results==0 and finishes==0 and not g.arena.series_id)
assert(g.arena.test_result.deaths==2 and Arena.CanBuy(g))
-- Freeze the pre-combat team. Battle mutations must not overwrite its positions.
g.team.heroes[1].position.x=-900
action("start");assert(g.phase=="fight" and g.starts==2 and not Arena.CanBuy(g))
for round=1,7 do
 assert(g.arena.opponent.id=="opponent"..round)
 g.team.heroes[1].position.x=-151
 if round==2 then
  for _,u in ipairs(g.battleManager.teamHeroes[2]) do u.alive=false end
  Arena.EndBattle(g,"dire");Arena.EndBattle(g,"dire");assert(#g.arena.results==2)
  advance(2);assert(g.arena.phase=="adjusting" and Arena.CanEdit(g) and not Arena.CanBuy(g))
  assert(g.team.heroes[1].position.x==-900)
  g.team.heroes[1].position.x=-1000
action("start")
 elseif round==7 then
  failFinish=2;Arena.EndBattle(g,"radiant");assert(g.arena.phase=="saving");advance(6)
 else
  Arena.EndBattle(g,"radiant");assert(g.arena.phase=="transition" and not Arena.CanEdit(g));advance(3)
 end
end
assert(g.arena.phase=="finished" and g.runComplete and finishes==1)
assert(serverSeries.final.heroes[1].position.x==-1000 and #serverSeries.rounds==7)
local attempts={};for _,r in ipairs(requests) do if r.url:match("/finish$") then attempts[#attempts+1]=r.body end end
assert(#attempts==3 and attempts[1]==attempts[2] and attempts[2]==attempts[3])
assert(g.arena.rating_after==1600 and g.arena.results[2].delta==-16)
action("exit");assert(Arena.Mode(g)=="select" and g.currentLevelId=="ch01")
-- HTTP callbacks from an exited map-run cannot start or replace the new run.
newGame();enter();holdStart=true;action("start");assert(g.arena.phase=="matching")
local old=g.arena
action("exit");assert(Arena.Mode(g)=="select")
held();assert(Arena.Mode(g)=="select" and old.cancelled and (g.starts or 0)==0)
-- Pending native purchases prevent a snapshot or first match from locking.
newGame();enter();g.pendingNativePurchases={one={}};action("start")
assert(g.arena.phase=="preparing" and not g.arena.locked and g.arena.error=="purchase_pending")
-- An exception in an asynchronous native restore is recoverable from the HUD.
newGame();enter();g.tacticBridge.ResetState=function() error("native restore unavailable") end;action("start")
assert(g.arena.phase=="error" and g.arena.retry)
g.tacticBridge.ResetState=function() end;action("retry");assert(g.phase=="fight")
-- Resource loading is bounded, and a late callback cannot resurrect a timed-out load.
newGame();local delayed
PrecacheUnitByNameAsync=function(_,callback) delayed=callback end
action("enter",{heroes_text=table.concat(names,";",1,5)});advance(40)
assert(g.arena.phase=="error" and g.arena.error=="precache_failed")
delayed();assert(g.arena.phase=="error")
print("PASS mode choice, owner/generation, 5-hero setup, export, practice isolation/gold restoration, seven rounds, loss-only editing, last-prep positions, exact retry and stale callback cancellation")
