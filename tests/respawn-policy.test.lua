-- Offline Lua 5.1 regression: real root hooks, BattleManager and respawn policy.
-- Native IsReincarnating/SetRespawnsDisabled semantics require in-engine evidence.
local root = TEST_REPO_ROOT or "."
local modules = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
package.path = modules .. "?.lua;" .. package.path
function class() local c={}; c.__index=c; return c end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
function IsValidEntity(u) return u ~= nil and not u.invalid end
local noop=function() end
local nativeRequire=require
local cleanupCheck, spawnOrder, logs
local function spawnHook(label)
    return {OnSpawn=function(_,u)
        spawnOrder[#spawnOrder+1]=label
        return u and u.summonHook==label
    end, Clear=function(g) if cleanupCheck then cleanupCheck(g) end end,
        -- 敌方召唤物登记是生产模块新增的接口：替身必须同样提供，否则 OnNpcSpawned 会报错。
        TrackEnemySummon=function() return false end}
end
local hooks={ ["battle.tempest_double"]=spawnHook("double"),
    ["tactics/special_targets"]=spawnHook("special"),
    ["battle/summon_behavior"]=spawnHook("summon") }
require=function(name)
    if name=="battle.battle_manager" or name=="battle.unit_helpers" or name=="battle.run_lives"
        or name=="battle.respawn_policy" then return nativeRequire(name) end
    if hooks[name] then return hooks[name] end
    if name=="battle.damage_stats" then return {new=function() return {Start=noop,Stop=noop} end} end
    return {Install=noop,Clear=noop,Write=function(message) logs[#logs+1]=message end,Event=noop}
end
dofile(modules .. "addon_game_mode.lua")
local entities, nextId, callbacks, settlements, now
function EntIndexToHScript(id) return entities[id] end
local function unit(name,real)
    nextId=nextId+1
    local u={id=nextId,name=name or "npc_dota_hero_skeleton_king",real=real~=false,
        alive=true,reviving=false,disabled=true,permissionCalls=0,mods={},stops=0,
        hp=417,mana=93,cooldown=27,learned=3,items={},stateWrites=0}
    function u:IsNull() return self.invalid==true end
    function u:IsRealHero() return self.real end
    function u:IsAlive() return self.alive end
    function u:IsReincarnating() return self.reviving end
    function u:GetEntityIndex() return self.id end
    function u:GetUnitName() return self.name end
    function u:GetPlayerOwnerID() return 0 end
    function u:SetRespawnsDisabled(value)
        assert(type(value)=="boolean")
        self.permissionCalls=self.permissionCalls+1
        if self.badSetter then error("injected respawn setter failure") end
        self.disabled=value
    end
    function u:RemoveModifierByName(name)
        assert(not self.real or self.disabled==false,"permission must precede preparation removal")
        self.mods[name]=nil
    end
    function u:SetHealth(value) self.hp=value; self.stateWrites=self.stateWrites+1 end
    function u:SetMana(value) self.mana=value; self.stateWrites=self.stateWrites+1 end
    function u:GetMaxHealth() return 900 end
    function u:GetMaxMana() return 300 end
    function u:SetIdleAcquire(value)
        if value then assert(not self.real or self.disabled==false,"permission before attack acquisition") end
        self.idle=value
    end
    function u:SetAcquisitionRange(value) assert(value>0) end
    function u:Stop() self.stops=self.stops+1 end
    function u:AddNewModifier(_,_,name,args) assert(type(args)=="table"); self.mods[name]=true end
    -- These APIs must never participate in native death/rebirth classification.
    function u:GetItemInSlot() error("respawn policy must not inspect consumed Aegis") end
    function u:RespawnHero() error("native respawn must not be replaced manually") end
    function u:GetAbilityByIndex() error("native rebirth must not relearn/reset abilities") end
    entities[u.id]=u
    return u
end
local function fixture()
    entities,nextId,callbacks,settlements,now={},0,{},0,0
    cleanupCheck,spawnOrder,logs=nil,{},{}
    GameRules={GetGameTime=function() return now end,GetGameModeEntity=function() return {
        SetContextThink=function(_,name,fn,delay)
            assert(name=="Dota2RpgBackToSetup" and delay==3,"no manual respawn timer")
            callbacks[#callbacks+1]=fn
        end} end}
    CustomGameEventManager={Send_ServerToAllClients=function(_,event)
        assert(event=="rpg_settlement"); settlements=settlements+1
    end}
    local g=setmetatable({phase="setup",teamsSpawned=true,currentLevelId="ch01",orderedLevels={"ch01","ch02"},
        lineup={"wk"},ownedHeroes={},heroData={},playerId=0,runLives={remaining=5,pendingItems={}},
        dataLoader={GetLevel=function() return {reward={gold=0,xp_per_active_hero=0}} end},
        tacticBridge={ResetState=noop},RemoveBattleBarrier=noop,BroadcastDamageStats=noop,
        BroadcastBattleState=noop,BroadcastShopState=noop,ScheduleStateBroadcast=noop},CDota2RpgDemo)
    local bm=setmetatable({},BattleManager); bm:constructor(g); g.battleManager=bm
    local a,b=unit(),unit(); bm.teamHeroes={[2]={a},[3]={b}}
    return g,bm,a,b
end
local function killed(g,u,reviving)
    u.alive=false; u.reviving=reviving
    g:OnEntityKilled({entindex_killed=u.id})
end
local function spawned(g,u)
    u.alive=true; u.reviving=false
    g:OnNpcSpawned({entindex=u.id})
end
local function disabledRoster(g)
    for _,units in pairs(g.battleManager.teamHeroes) do for _,u in ipairs(units) do
        if u.real and not u.invalid and not u.badSetter then assert(u.disabled,"all roster heroes disabled before cleanup") end
    end end
end
local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end

test("rejected starts never grant respawn permission",function()
    for _,reject in ipairs({function(g) g.runComplete=true end,function(g) g.phase="result" end,
        function(g) g.teamsSpawned=false end,function(g) g.lineup={} end,function(g) g.phase="fight" end}) do
        local g,bm,a,b=fixture(); reject(g); g:OnStartBattle(nil,{})
        assert(a.permissionCalls==0 and b.permissionCalls==0 and bm.phase=="prepare")
    end
end)
test("real start enables both teams before preparation removal and acquisition",function()
    local g,bm,a,b=fixture(); g:OnStartBattle(nil,{})
    assert(g.phase=="fight" and bm.phase=="fight" and not a.disabled and not b.disabled)
    assert(a.permissionCalls==1 and b.permissionCalls==1 and a.idle and b.idle)
end)
test("WK death/rebirth on both teams preserves the exact entity and native state",function()
    local g,bm,a,b=fixture(); g:OnStartBattle()
    for _,u in ipairs({a,b}) do
        g.ScheduleStateBroadcast=function() assert(u.rpgDeathBeforeRespawn and not u.disabled,"policy before broadcast") end
        killed(g,u,true); assert(not u.disabled and u.rpgDeathBeforeRespawn)
        u.hp,u.mana,u.cooldown,u.learned=311,47,19,4
        local writes=u.stateWrites; local items=u.items
        spawned(g,u)
        assert(not u.disabled and not u.rpgDeathBeforeRespawn and not u.rpgPlaceholderReady)
        assert(u.hp==311 and u.mana==47 and u.cooldown==19 and u.learned==4 and u.items==items)
        assert(u.stateWrites==writes and u.stops==0 and next(u.mods)==nil)
    end
    assert(bm.teamHeroes[2][1]==a and bm.teamHeroes[3][1]==b and #callbacks==0)
    assert(table.concat(spawnOrder,",")=="double,special,summon,double,special,summon")
end)
test("consumed Aegis uses native flag; later ordinary death disables automatic respawn",function()
    local g,bm,a=fixture(); a.name="npc_dota_hero_axe"; g:OnStartBattle()
    killed(g,a,true); assert(not a.disabled and next(a.items)==nil)
    spawned(g,a); killed(g,a,false); assert(a.disabled and a.rpgDeathBeforeRespawn)
    assert(#callbacks==0 and g.phase=="fight")
end)
test("ordinary death on either team disables permission before event broadcast",function()
    local g,bm,a,b=fixture(); g:OnStartBattle()
    for _,u in ipairs({a,b}) do
        g.ScheduleStateBroadcast=function() assert(u.disabled and u.rpgDeathBeforeRespawn) end
        killed(g,u,false); assert(u.disabled)
    end
end)
test("commander bench summon and stale handles are excluded by roster identity",function()
    local g,bm,a=fixture()
    local commander,bench,summon,stale=unit("npc_dota_hero_wisp"),unit(),unit(),unit()
    commander.rpgPlaceholderReady=true; g.placeholderHero=commander
    bench.benchHeroName=bench.name; summon.summonHook="summon"
    stale.id=a.id -- Equal entindex/name is insufficient: this is not the current object.
    local creep=unit("npc_dota_neutral_kobold",false); table.insert(bm.teamHeroes[3],creep)
    local invalid=unit(); invalid.invalid=true; table.insert(bm.teamHeroes[2],invalid)
    g:OnStartBattle()
    for _,u in ipairs({commander,bench,summon,stale,creep,invalid}) do
        entities[u.id]=u; killed(g,u,true)
        assert(u.permissionCalls==0 and not u.rpgDeathBeforeRespawn)
    end
    for _,u in ipairs({commander,bench,summon}) do spawned(g,u); assert(u.permissionCalls==0) end
    bm:StopBattle()
    for _,u in ipairs({commander,bench,summon,stale,creep,invalid}) do assert(u.permissionCalls==0) end
end)
test("initial roster and pre-tag owned spawns avoid commander conversion and setup roots",function()
    local g,bm,a=fixture(); spawned(g,a)
    assert(a.disabled and not a.rpgPlaceholderReady and a.stops==0 and next(a.mods)==nil and a.stateWrites==0)
    local early=unit("npc_dota_hero_axe"); g.heroData[early.name]={}; g.ownedHeroes={early.name}
    spawned(g,early)
    assert(not early.rpgPlaceholderReady and early.permissionCalls==0 and early.stops==0 and next(early.mods)==nil)
end)
test("late deaths and native rebirth outside fight remain disabled and contained",function()
    for _,phase in ipairs({"result","setup"}) do
        local g,bm,a,b=fixture(); g:OnStartBattle(); killed(g,a,true)
        g.phase=phase
        spawned(g,a)
        assert(a.disabled and a.stops==1 and a.idle==false and not a.rpgDeathBeforeRespawn)
        for _,name in ipairs({"modifier_invulnerable","modifier_rooted","modifier_disarmed","modifier_silence"}) do assert(a.mods[name]) end
        killed(g,b,true); assert(b.disabled and b.rpgDeathBeforeRespawn,"late death policy before phase return")
    end
end)
test("real settlement disables pending dead and alive heroes before cleanup, despite one bad setter",function()
    for _,broken in ipairs({false,true}) do
        local g,bm,a,b=fixture(); local alive=unit(); table.insert(bm.teamHeroes[2],alive)
        g:OnStartBattle(); killed(g,a,true); killed(g,b,true)
        if broken then local bad=unit(); bad.alive=false; bad.disabled=false; bad.badSetter=true; table.insert(bm.teamHeroes[2],1,bad) end
        local clears=0
        cleanupCheck=function(game) assert(game.phase=="result"); disabledRoster(game); clears=clears+1 end
        g:EndBattle("timeout",3)
        assert(g.phase=="result" and bm.phase=="settle" and settlements==1 and #callbacks==1 and clears==3)
        disabledRoster(g); assert(g.runLives.remaining==4)
        if broken then
            local found=false; for _,line in ipairs(logs) do if line:find("injected respawn setter failure",1,true) then found=true end end
            assert(found,"failed native setter is reported")
        end
        g:EndBattle("timeout",3); assert(settlements==1 and g.runLives.remaining==4)
    end
end)
test("victory and terminal settlement disable pending rebirth without a setup escape",function()
    for _,case in ipairs({{winner="radiant"},{winner="radiant",final=true},{winner="dire",lastLife=true}}) do
        local g,bm,a,b=fixture(); g.AddGold=noop; g.AwardStageXp=noop
        g.CalculateTimeBonus=function() return 0 end
        if case.final then g.orderedLevels={"ch01"} end
        if case.lastLife then g.runLives.remaining=1 end
        g:OnStartBattle(); killed(g,a,true); killed(g,b,false)
        cleanupCheck=disabledRoster
        g:EndBattle(case.winner,case.winner=="radiant" and 2 or 3)
        disabledRoster(g)
        assert(g.phase=="result" and bm.phase=="settle" and settlements==1)
        if case.final or case.lastLife then assert(g.runComplete and #callbacks==0)
        else assert(not g.runComplete and #callbacks==1) end
    end
end)
test("direct BattleManager stop disables dead pending heroes even with a failed setter",function()
    local g,bm,a,b=fixture(); local bad=unit(); table.insert(bm.teamHeroes[2],1,bad)
    g:OnStartBattle(); killed(g,a,true); killed(g,b,true)
    bad.alive=false; bad.badSetter=true
    bm:StopBattle(); assert(bm.phase=="settle"); disabledRoster(g)
    assert(a.stops==0 and b.stops==0,"dead heroes still receive permission change without Stop")
end)
test("addon global respawn opt-in remains enabled (source guard, not native proof)",function()
    local f=assert(io.open(modules .. "addon_game_mode.lua","r")); local source=f:read("*a"); f:close()
    assert(source:find("GameRules:SetHeroRespawnEnabled%(true%)"),"native global respawn must be enabled")
    assert(not source:find("GameRules:SetHeroRespawnEnabled%(false%)"),"global switch must follow the new respawn policy")
end)
local failures={}
for _,entry in ipairs(tests) do
    local ok,err=xpcall(entry[2],debug.traceback)
    if ok then print("PASS " .. entry[1]) else print("FAIL " .. entry[1] .. "\n" .. err); failures[#failures+1]=entry[1] end
end
print(string.format("respawn-policy: %d passed, %d failed; native API semantics are mocked, not proven",#tests-#failures,#failures))
assert(#failures==0,table.concat(failures,"; "))
