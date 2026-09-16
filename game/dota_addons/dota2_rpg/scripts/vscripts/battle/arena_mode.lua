local Json = require("lib.json")
local Profile = require("battle.arena_profile")
local Presets = require("battle.arena_presets")
local Arena = {}
local function live(u) return u and (not u.IsNull or not u:IsNull()) end
local function current(g,s) return g.arena==s and not s.cancelled end
local function call(g,name,...) if type(g[name])=="function" then return g[name](g,...) end end
local function clock() return GameRules:GetGameTime() end
local function state(g) return g.arena end
function Arena.Mode(g) return g.arena and g.arena.mode or "campaign" end
function Arena.IsActive(g) return Arena.Mode(g)=="arena" end
function Arena.CanCampaign(g) return Arena.Mode(g)=="campaign" end
function Arena.CanEdit(g)
    if Arena.CanCampaign(g) then return true end
    local s=state(g)
    return s and s.mode=="arena" and not s.practice and (s.phase=="preparing" or s.phase=="adjusting")
end
function Arena.CanBuy(g) return Arena.CanCampaign(g) or (Arena.CanEdit(g) and not state(g).locked) end
local function publishEvent(g,event,payload)
    local player=g.playerId~=nil and PlayerResource:GetPlayer(g.playerId)
    if player then CustomGameEventManager:Send_ServerToPlayer(player,event,payload) end
end
local function catalog(g)
    if g.arenaCatalog then return g.arenaCatalog end
    local data=LoadKeyValues("scripts/data/debug_heroes.kv") or {}
    data=data.debug_heroes or data
    local list={}
    for _,name in pairs(data) do
        if type(name)=="string" and name~="npc_dota_hero_wisp" and name:match("^npc_dota_hero_[a-z0-9_]+$") then list[#list+1]=name end
    end
    table.sort(list);g.arenaCatalog=list;return list
end
function Arena.Publish(g,playerId)
    if playerId~=nil and playerId~=g.playerId then return end
    local s=state(g);if not s or g.playerId==nil then return end
    local opponent=s.opponent or {}
    local out={mode=s.mode,phase=s.phase,generation=s.generation,rating=s.rating or 1500,round=math.min(7,#s.results+1),wins=s.wins or 0,
        catalog=catalog(g),results=s.results,opponent_name=opponent.player_name or "",opponent_rating=opponent.rating,
        can_edit=Arena.CanEdit(g),can_buy=Arena.CanBuy(g),offline=true,can_start=false,can_test=Arena.CanEdit(g),
        can_export=false,practice=s.practice==true,test_result=s.test_result,error=s.error or "",
        rating_before=s.rating_before,rating_after=s.rating_after,rating_change=s.rating_change,perfect_bonus=s.perfect_bonus}
    publishEvent(g,"rpg_arena_state",{state_json=Json.encode(out)})
    if g.campaignDifficultyInstalled then require("battle.campaign_difficulty").Publish(g, playerId) end
end
local function change(g,s,phase,err)
    if not current(g,s) then return end
    s.phase,s.error=phase,err
    g.arenaGeneration=(g.arenaGeneration or 0)+1;s.generation=g.arenaGeneration
    Arena.Publish(g)
end
local function broadcast(g)
    for _,name in ipairs({"BroadcastLevelInfo","BroadcastHeroInfo","BroadcastShopState","BroadcastBattleState","BroadcastDamageStats"}) do
        pcall(call,g,name)
    end
    Arena.Publish(g)
end
local function later(g,s,label,seconds,fn)
    local mode=GameRules:GetGameModeEntity()
    mode:SetContextThink("RpgArena_"..label.."_"..s.serial,function()
        if current(g,s) then fn() end
        return nil
    end,seconds)
end
local function stop(g)
    -- Claim first: native Stop/Remove callbacks must never settle the round twice.
    g.phase="result"
    local function step(name,fn)
        if g.RunLifecycleStep then g:RunLifecycleStep("arena_"..name,fn) else fn() end
    end
    for _,name in ipairs({"battle.tempest_double","tactics.special_targets","battle.summon_behavior","issue_fixes.tiny_tree"}) do
        step(name,function() require(name).Clear(g) end)
    end
    step("respawn",function() require("battle.respawn_policy").SetBattleActive(g,false) end)
    step("battle_stop",function() g.battleManager:StopBattle() end)
    if g.damageStats then step("damage_stop",function() g.damageStats:Stop(clock()) end) end
end
local failure
local function precache(g,s,teams,done)
    local names,seen={},{}
    for _,team in ipairs(teams) do for _,h in ipairs(team.heroes or {}) do if not seen[h.name] then seen[h.name]=true;names[#names+1]=h.name end end end
    local ended=false
    local function complete(ok)
        if ended or not current(g,s) then return end
        ended=true
        local completed=pcall(done,ok)
        if not completed then failure(g,s,"operation_failed") end
    end
    later(g,s,"precache",40,function() complete(false) end)
    local function nextHero(index)
        if ended or not current(g,s) then return end
        if index>#names then complete(true);return end
        if type(PrecacheUnitByNameAsync)~="function" then complete(false);return end
        local ok=pcall(PrecacheUnitByNameAsync,names[index],function() nextHero(index+1) end,g.playerId)
        if not ok then complete(false) end
    end
    nextHero(1)
end
local function operation(g,s,phase,fn)
    s.retry=fn;change(g,s,phase);fn()
end
failure=function(g,s,code) change(g,s,"error",code or "request_failed");broadcast(g) end
local function prepare(g,s,opponent,done)
    g.phase="result";g.stageLoading=true
    precache(g,s,{s.team,opponent.team},function(ok)
        if not ok then g.stageLoading=false;failure(g,s,"precache_failed");return end
        g.phase="setup"
        -- Death-dropped items are battle artifacts. The saved inventories already
        -- restore their originals; leaving drops would duplicate Rapiers/Gems.
        if Entities and Entities.FindAllByClassname then
            for _,drop in pairs(Entities:FindAllByClassname("dota_item_physical") or {}) do
                if live(drop) then
                    local item=drop.GetContainedItem and drop:GetContainedItem()
                    if live(item) then item:RemoveSelf() end
                    if live(drop) then drop:RemoveSelf() end
                end
            end
        end
        local ownOk=Profile.Spawn(g,s.team,DOTA_TEAM_GOODGUYS,false)
        local enemyOk=ownOk and Profile.Spawn(g,opponent.team,DOTA_TEAM_BADGUYS,opponent.preset==true)
        g.stageLoading=false
        if not ownOk or not enemyOk then g.phase="result";failure(g,s,"spawn_failed");return end
        g.stageLoadError=nil;g.teamsSpawned=true;g.preparedEnemyLevel="arena"
        g.battleManager.arenaActive=true
        if g.issueFixes and g.issueFixes.RegisterCurrentStage then
            local entries={};for _,h in ipairs(opponent.team.heroes) do entries[#entries+1]={unit=h.name,level=30} end
            g.issueFixes:RegisterCurrentStage(entries,g.battleManager.teamHeroes[DOTA_TEAM_BADGUYS])
        end
        call(g,"SpawnBattleBarrier");call(g,"EnsureCommanderProtected")
        g.tacticBridge:ResetState()
        s.opponent=opponent
        done()
    end)
end
local function launch(g,s,opponent)
    prepare(g,s,opponent,function()
        s.roundDeaths=0;s.deadEvents={};g.runComplete=false;g.runFailed=false;g.winner=""
        change(g,s,"fighting")
        g.arenaLaunching=true
        local ok=pcall(g.OnStartBattle,g,nil,{})
        g.arenaLaunching=false
        if not ok or g.phase~="fight" then failure(g,s,"start_failed") else broadcast(g) end
    end)
end
local function setTeam(g,s)
    if g.nativeShopTransactionPending or next(g.pendingNativePurchases or {})~=nil then return false,"purchase_pending" end
    local team=Profile.Capture(g)
    if not team then return false,"capture_failed" end
    s.team=team;return true
end
function Arena.EndBattle(g,winner)
    local s=state(g)
    if not Arena.IsActive(g) or g.phase~="fight" or s.phase~="fighting" then return end
    local survivors=0
    for _,u in ipairs(g.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do if live(u) and u:IsAlive() then survivors=survivors+1 end end
    local deaths=math.max(s.roundDeaths or 0,5-survivors)
    stop(g);g.settlementGeneration=(g.settlementGeneration or 0)+1
    local won=winner=="radiant" and survivors>0
    if s.practice then
        s.test_result={won=won,survivors=survivors,deaths=deaths,opponent_name=s.opponent.player_name,strength=s.opponent.strength}
        change(g,s,"transition")
        local function restore()
            prepare(g,s,s.opponent,function()
                s.practice=false;g:SetGoldBalance(s.testGold);change(g,s,s.returnPhase);s.retry=nil;broadcast(g)
            end)
        end
        s.retry=restore;later(g,s,"practice_result",2,restore);return
    end
    -- A retained formal-round state may settle locally, but never upload or advance.
    s.retry=nil;s.locked=false;change(g,s,"preparing","offline_unavailable");broadcast(g)
end
function Arena.OnKilled(g,unit)
    local s=state(g)
    if not s or s.phase~="fighting" or g.phase~="fight" or not live(unit) then return end
    for _,h in ipairs(g.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
        if h==unit then
            -- Reincarnations are real deaths. Deduplicate only identical callbacks
            -- in the same engine frame; another life later in the fight counts.
            local tick=clock()
            if s.deadEvents[unit]~=tick then s.deadEvents[unit]=tick;s.roundDeaths=(s.roundDeaths or 0)+1 end
            return
        end
    end
end
local function start(g,s)
    s.error="offline_unavailable";Arena.Publish(g)
end
local function test(g,s,strength)
    if not Arena.CanEdit(g) or (strength~="lower" and strength~="similar" and strength~="higher") then return end
    local ok,why=setTeam(g,s);if not ok then s.error=why;Arena.Publish(g);return end
    s.returnPhase=s.phase;s.testGold=call(g,"GetGoldBalance") or g.gold or 0;s.practice=true
    local opponent=Presets.Generate(catalog(g),strength,s.rating)
    operation(g,s,"transition",function() launch(g,s,opponent) end)
end
local function export(g,s)
    publishEvent(g,"rpg_arena_export_result",{generation=s.generation,error="offline_unavailable"})
    s.error="offline_unavailable"
end
local function newState(g,mode,rating)
    g.arenaSerial=(g.arenaSerial or 0)+1;g.arenaGeneration=(g.arenaGeneration or 0)+1
    local s={mode=mode,phase="preparing",serial=g.arenaSerial,generation=g.arenaGeneration,results={},rating=rating or 1500,wins=0}
    g.arena=s;return s
end
local function resetCampaign(g,s)
    require("battle.fresh_run").Reset(g)
    g.orderedLevels=g.arenaNormalLevels;g.currentLevelId=g.orderedLevels[1] or "ch01"
    g.battleManager.arenaActive=false;g.phase="setup";g.runComplete=false;g.runFailed=false
    g:SpawnLevelEnemies(g.currentLevelId);g:RespawnPlayerRoster();g:SpawnBattleBarrier();g:RollShop()
    change(g,s,"preparing");broadcast(g)
end
local function exit(g,s)
    if g.phase=="fight" then stop(g) end
    -- Invalidate previous round and precache callbacks before restoring campaign.
    s.cancelled=true
    local nextState=newState(g,"select",s.rating)
    local ok=pcall(resetCampaign,g,nextState)
    if not ok then failure(g,nextState,"spawn_failed") end
end
local function enter(g,s,payload)
    if (s.mode=="arena" and s.phase~="finished") or g.phase=="fight" or g.stageLoading then return end
    if g.skillDebug and (g.skillDebug.active or g.skillDebug.pending) then s.error="wrong_phase";Arena.Publish(g);return end
    local allowed={};for _,name in ipairs(catalog(g)) do allowed[name]=true end
    local names={};for name in tostring(payload.heroes_text or ""):gmatch("[^;]+") do
        if not allowed[name] then s.error="invalid_hero";Arena.Publish(g);return end
        allowed[name]=nil;names[#names+1]=name
    end
    if #names~=5 then s.error="invalid_hero";Arena.Publish(g);return end
    s.cancelled=true;s=newState(g,"arena",s.rating)
    g.settlementGeneration=(g.settlementGeneration or 0)+1
    g.enemySpawnRequest=nil
    local resourceTeam={heroes={}};for _,name in ipairs(names) do resourceTeam.heroes[#resourceTeam.heroes+1]={name=name} end
    local function load()
        precache(g,s,{resourceTeam},function(ok)
            if not ok then failure(g,s,"precache_failed");return end
            g.phase="restarting"
            local ready=pcall(function()
                require("battle.fresh_run").Reset(g)
                g.orderedLevels={"arena"};g.currentLevelId="arena";g.battleManager.arenaActive=true
                g.ownedHeroes=Profile.Copy(names);g.lineup=Profile.Copy(names);g.heroOrder=5
                for i,name in ipairs(names) do g.heroData[name]={level=30,current_xp=0,skill_points=30,quality="common",order=i,inventory={}} end
                g.phase="setup";g:RespawnPlayerRoster();g:SetGoldBalance(99999)
                g.teamsSpawned=true;g.stageLoading=false;g.stageLoadError=nil;g.preparedEnemyLevel="arena"
                g:SpawnBattleBarrier();g:EnsureCommanderProtected()
            end)
            if not ready then failure(g,s,"spawn_failed");return end
            s.retry=nil;change(g,s,"preparing");broadcast(g)

        end)
    end
    operation(g,s,"transition",load)
end
function Arena.Install(g)
    if g.arena then return end
    g.arenaNormalLevels=Profile.Copy(g.orderedLevels)
    newState(g,"select",1500)
    for _,action in ipairs({"request","campaign","enter","start","retry","exit","test","export"}) do
        CustomGameEventManager:RegisterListener("rpg_arena_"..action,function(_,payload)
            if type(payload)~="table" or tonumber(payload.PlayerID)~=g.playerId then return end
            local s=state(g)
            if action=="request" then Arena.Publish(g);return end
            if tonumber(payload.generation)~=s.generation then Arena.Publish(g);return end
            local ok=pcall(function()
                if action=="campaign" then
                    if s.mode~="arena" and g.phase~="fight" then s.mode="campaign";s.error=nil;change(g,s,"preparing");broadcast(g) end
                elseif action=="enter" then enter(g,s,payload)
                elseif action=="start" then start(g,s)
                elseif action=="test" then test(g,s,payload.strength)
                elseif action=="export" then export(g,s)
                elseif action=="exit" and s.mode=="arena" then exit(g,s)
                elseif action=="retry" and s.phase=="error" and s.retry then local retry=s.retry;change(g,s,"transition");retry() end
            end)
            if not ok then failure(g,state(g),"operation_failed") end
            Arena.Publish(g)
        end)
    end
end
return Arena
