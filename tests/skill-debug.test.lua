-- Run from repository root with Lua 5.1 (including lupa.lua51).
-- Real skill_debug module; native APIs and Root class boundaries are mocked.
-- Respawn follows Root's capture-before-remove, inventory restore and authored-rule contract.
local root = arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = root .. "/?.lua;" .. package.path
local noop = function() end
package.loaded["issue_fixes.runtime_log"] = {Write=noop}
package.loaded["issue_fixes.hero_lifecycle_log"] = {Remove=function(_, u) u:RemoveSelf() end}
package.loaded["issue_fixes.hero_ability_policy"] = {GetSlotCount=function(u) return #u.abilities end}
for _, name in ipairs({"battle.tempest_double", "tactics.special_targets", "battle.summon_behavior", "issue_fixes.tiny_tree"}) do
    package.loaded[name] = {Clear=function(g)
        if g.assertRespawnStopped then g:assertRespawnStopped("cleanup") end
        g.cleanupCalls = g.cleanupCalls + 1
    end}
end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
local Debug = require("battle.skill_debug")
local HERO = "npc_dota_hero_axe"
local function eq(a,b,message) assert(a == b, (message or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end
-- The sandbox must exercise a real spell rule, not the attack-only campaign default.
local targetEntry = Debug.Level({}).enemies[1]
eq(targetEntry.unit, Debug.UNIT)
eq(targetEntry.ai, "skill_test_stomp")
local function readSource(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a"); file:close(); return text
end
local targetKV = readSource(root .. "/../npc/npc_units_custom.txt")
assert(targetKV:match('"Ability1"%s+"centaur_hoof_stomp"'), "test target needs a visible native stomp")
assert(targetKV:match('"StatusMana"%s+"1000"'), "test target needs mana")
assert(targetKV:match('"StatusManaRegen"%s+"20"'), "repeat casts need mana regeneration")
local aiKV = readSource(root .. "/../data/enemy_ai.kv")
local debugAI = assert(aiKV:match('"skill_test_stomp"(.-)"demo_default"'))
assert(debugAI:find('"ability_1"', 1, true) < debugAI:find('"attack"', 1, true), "cast before attack fallback")
local function cooldown(name, level)
    return {name=name, level=level or 0, remaining=20, IsNull=function() return false end,
        EndCooldown=function(self) self.remaining=0 end, RemoveSelf=function(self) self.removed=true end}
end
local function unit(name)
    local u = {name=name, items={}, abilities={cooldown("axe_berserkers_call"), cooldown("special_bonus_hp_250")}}
    function u:IsNull() return self.removed == true end
    function u:IsRealHero() return self.name:find("npc_dota_hero_",1,true)==1 end
    function u:IsAlive() return not self.dead end
    function u:IsReincarnating() return self.reincarnating==true end
    function u:SetRespawnsDisabled(value) self.respawnsDisabled=value end
    function u:GetUnitName() return self.name end
    function u:SetControllableByPlayer(playerId, enabled)
        self.controllingPlayerId, self.controlEnabled = playerId, enabled
    end
    function u:RemoveSelf() self.removed=true end
    function u:RemoveModifierByName(name) self.removedModifier=name end
    function u:GetItemInSlot(slot) return self.items[slot] end
    function u:TakeItem(item) for slot,v in pairs(self.items) do if v==item then self.items[slot]=nil end end end
    function u:GetAbilityByIndex(slot) return self.abilities[slot+1] end
    for _, pair in ipairs({{"SetBaseMaxHealth","baseHP"},{"SetMaxHealth","maxHP"},{"SetHealth","hp"},
        {"SetBaseDamageMin","damageMin"},{"SetBaseDamageMax","damageMax"}}) do
        local field=pair[2]; u[pair[1]]=function(self,value) self[field]=value end
    end
    return u
end
local Root = {}
function Root:GetStashUnit() return self.stash end
function Root:SetGoldBalance(value) self.gold=value end
function Root:SpawnBattleBarrier() self.barriers=self.barriers+1 end
function Root:InitializeRecruitmentState() self.recruitInitializations=self.recruitInitializations+1; self.freeRecruitChoices=3 end
function Root:RollShop() self.shopRolls=self.shopRolls+1; self.shopOffers={normal=true} end
for _, name in ipairs({"BroadcastLevelInfo","BroadcastBattleState","BroadcastHeroInfo","BroadcastShopState","BroadcastDamageStats"}) do Root[name]=noop end
function Root:RespawnPlayerRoster()
    if self.phase ~= "setup" then return end
    self.rosterSpawns=self.rosterSpawns+1
    for _, old in ipairs(self.battleManager.teamHeroes[2]) do
        local data=self.heroData[old.name]
        if data then
            data.ability_levels={}
            for _,a in ipairs(old.abilities) do data.ability_levels[a.name]=a.level end
            self.heroInventories[old.name]=old.items
        end
        old:RemoveSelf()
    end
    self.battleManager.teamHeroes[2]={}
    self.battleManager.teamRules[2]={}
    for i,name in ipairs(self.lineup) do
        local u=unit(name); local data=self.heroData[name]
        u.level=data.level
        for _,a in ipairs(u.abilities) do a.level=(data.ability_levels or {})[a.name] or 0 end
        u.items=self.heroInventories[name] or {}
        self.battleManager.teamHeroes[2][i]=u
        self.heroRulesByName[name]=self.heroRulesByName[name] or {"default"}
        self.battleManager.teamRules[2][i]=self.heroRulesByName[name]
    end
end
function Root:SpawnLevelEnemies(id)
    self.enemySpawns=self.enemySpawns+1
    for _,u in ipairs(self.battleManager.teamHeroes[3]) do u:RemoveSelf() end
    self.battleManager.teamHeroes[3]={}
    for _,entry in ipairs(self.dataLoader:GetLevel(id).enemies) do
        for i=1,entry.count do table.insert(self.battleManager.teamHeroes[3],unit(entry.unit)) end
    end
    return "spawn-return"
end
function Root:OnStartBattle(event,payload)
    self.startCalls=self.startCalls+1; self.startArgs={event,payload}
    if self.phase=="setup" and #self.lineup>0 and not self.runComplete then self.phase="fight" end
    return "start-return", 42
end
function Root:EndBattle(winner,team)
    self.normalAwards=self.normalAwards+1; self.runLives=self.runLives-1
    self.currentLevelId="ch02"; self.endArgs={winner,team}
    return "end-return", 43
end
for _,name in ipairs({"OnShopBuy","OnShopRefresh","OnBenchBuy","OnLineupSet","OnSelectLevel"}) do
    local method=name
    Root[name]=function(self,...) self.calls[method]={...}; return method,44 end
end
local function fixture()
    local f={listeners={}, events={}, loads={}, thinks={}}
    PlayerResource={GetPlayer=function(_,id) return id==7 and {id=id} or nil end}
    CustomGameEventManager={RegisterListener=function(_,name,fn) f.listeners[name]=fn end,
        Send_ServerToPlayer=function(_,player,name,payload) f.events[#f.events+1]={name=name,payload=payload,player=player} end,
        Send_ServerToAllClients=function(_,name,payload) f.events[#f.events+1]={name=name,payload=payload} end}
    GameRules={GetGameTime=function() return 17 end, GetGameModeEntity=function() return {
        SetContextThink=function(_,name,fn,delay) f.thinks[name]={fn=fn,delay=delay} end} end}
    PrecacheUnitByNameAsync=function(name,fn,id) f.loads[#f.loads+1]={name=name,fn=fn,id=id} end
    Entities={FindAllByClassname=function() return {} end}
    local bm={teamHeroes={[2]={},[3]={}},teamRules={[2]={},[3]={}},heroStates={},stops=0}
    function bm:StopBattle() self.stops=self.stops+1 end
    function bm:ResetBattleStats() self.statsReset=true end
    function bm:GetBattleTime() return 120.75 end
    local g=setmetatable({playerId=7,phase="setup",teamsSpawned=true,orderedLevels={"ch01","ch02"},
        currentLevelId="ch02",runLives=4,gold=321,initialGold=500,ownedHeroes={HERO},lineup={HERO},
        heroPool={str={HERO,"npc_dota_hero_sven",HERO,"bad/path"},agi={"npc_dota_hero_drow_ranger"}},
        heroData={[HERO]={level=8}},heroRulesByName={},heroInventories={},benchUnits={},stash=unit("stash"),
        placeholderHero=unit("wisp"),battleManager=bm,cleanupCalls=0,barriers=0,recruitInitializations=0,
        shopRolls=0,rosterSpawns=0,enemySpawns=0,startCalls=0,normalAwards=0,calls={},
        tacticBridge={ResetState=noop,ruleService={state={rules={}}}},
        dataLoader={GetLevel=function(_,id) return {id=id,enemies={{unit="normal_enemy",count=2}}} end}}, {__index=Root})
    g:RespawnPlayerRoster(); g:SpawnLevelEnemies("ch02")
    Debug.Install(g); f.g=g
    -- PlayerID is injected by the engine; listener's first argument is not the player ID.
    function f:emit(name,payload) self.listeners["rpg_debug_"..name](901,payload) end
    function f:start(damage) self:emit("start",{PlayerID=7,hero=HERO,attack_damage=damage or 100}) end
    function f:finish() self.loads[1].fn(); self.loads[#self.loads].fn() end
    function f:enter(damage) self:start(damage); self:finish() end
    return f,g
end
local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end

test("fresh runs advance rule generation once before roster broadcasts and discard old rules",function()
    local f,g=fixture()
    local expected=0
    local function seed()
        g.heroRulesByName[HERO]={{action="old"}}
        g.battleManager.teamRules[2]={{action="old"}}
        g.battleManager.teamRules[3]={{action="old"}}
        g.tacticBridge.ruleService.state.rules={old=true}
        g.enemySpawnRequest={level="ch02"}; g.stageLoading=true; g.stageLoadError="timeout"
    end
    local spawn=g.SpawnLevelEnemies
    g.SpawnLevelEnemies=function(self,id)
        eq(self.ruleGeneration,expected,"generation advances before roster spawn")
        assert(not self.enemySpawnRequest and not self.stageLoading and not self.stageLoadError,
            "debug entry and exit release obsolete campaign loading gate")
        eq(next(self.heroRulesByName),nil,"hero rules cleared before spawn")
        eq(next(self.battleManager.teamRules[2]),nil,"ally rules cleared before spawn")
        eq(next(self.battleManager.teamRules[3]),nil,"enemy rules cleared before spawn")
        eq(next(self.tacticBridge.ruleService.state.rules),nil,"service rules cleared before spawn")
        return spawn(self,id)
    end
    local broadcasts=0
    for _,name in ipairs({"BroadcastBattleState","BroadcastHeroInfo","BroadcastShopState"}) do
        g[name]=function(self)
            eq(self.ruleGeneration,expected,"snapshot observes fresh generation")
            broadcasts=broadcasts+1
        end
    end
    for generation=1,2 do
        seed(); expected=generation
        local loadStart=#f.loads
        f:start(); eq(g.ruleGeneration or 0,generation-1,"pending preserves generation")
        f.loads[loadStart+1].fn(); f.loads[loadStart+2].fn()
        eq(g.ruleGeneration,generation,"entry and reentry increment once")
        f.loads[loadStart+2].fn(); eq(g.ruleGeneration,generation,"duplicate callback is inert")
    end
    seed(); expected=3
    f:emit("exit",{PlayerID=7}); eq(g.ruleGeneration,3,"exit increments once")
    eq(next(g.heroRulesByName),nil,"empty normal lineup retains no old rules")
    eq(broadcasts,9,"all fresh runs publish their generation")
    f:emit("exit",{PlayerID=7}); eq(g.ruleGeneration,3,"inactive exit is inert")
end)
test("failed pending entry and cancellation preserve generation and rule stores",function()
    for _,action in ipairs({"cancel","timeout","exception","phase"}) do
        local f,g=fixture(); g.ruleGeneration=17; g.settlementGeneration=22
        local campaignRequest={level="ch03"}
        g.enemySpawnRequest=campaignRequest; g.stageLoading=true
        local heroRules=g.heroRulesByName
        local teamRules=g.battleManager.teamRules
        local serviceRules={authored=true}; g.tacticBridge.ruleService.state.rules=serviceRules
        if action=="exception" then PrecacheUnitByNameAsync=function() error("precache failed") end end
        f:start(); eq(g.ruleGeneration,17,"pending preserves generation")
        if action=="cancel" then f:emit("exit",{PlayerID=7})
        elseif action=="timeout" then f.thinks.RpgSkillDebugPrecache.fn()
        elseif action=="phase" then g.phase="result"; f.loads[1].fn() end
        if f.loads[1] then f.loads[1].fn() end
        eq(g.ruleGeneration,17,action .. " preserves generation")
        eq(g.settlementGeneration,22,action .. " preserves campaign preparation epoch")
        assert(g.enemySpawnRequest==campaignRequest and g.stageLoading,
            "cancelled debug entry retains the campaign preload request")
        eq(g.heroRulesByName,heroRules,action .. " preserves hero rules")
        eq(g.battleManager.teamRules,teamRules,action .. " preserves team rules")
        eq(g.tacticBridge.ruleService.state.rules,serviceRules,action .. " preserves service rules")
        assert(not g.skillDebug.pending and not g.skillDebug.active)
    end
end)

test("trusted sorted deduplicated catalog and owner metadata",function()
    local f,g=fixture(); local names,allowed=Debug.Catalog(g)
    eq(table.concat(names,","),HERO..",npc_dota_hero_drow_ranger,npc_dota_hero_sven")
    assert(not allowed["npc_dota_hero_lina"])
    for _,p in ipairs({false,17,"bad",{}, {PlayerID=8,hero=HERO,attack_damage=100}}) do f:emit("start",p) end
    f:emit("start",nil); eq(#f.loads,0)
    f:emit("start",{PlayerID=7,hero="npc_dota_hero_lina",attack_damage=100}); eq(#f.loads,0)
    f:emit("start",{PlayerID=7}); eq(#f.loads,0)
    f:emit("request",{PlayerID=7}); eq(f.events[#f.events].payload.heroes_text,table.concat(names,";"))
    f:start(); eq(#f.loads,1); eq(f.loads[1].id,7)
end)
test("debug catalog allows heroes outside ordinary recruitment",function()
    local previous = LoadKeyValues
    LoadKeyValues = function(path)
        eq(path,"scripts/data/debug_heroes.kv")
        return {debug_heroes={["1"]="npc_dota_hero_invoker",["2"]="invalid_unit",["3"]=false}}
    end
    local f,g=fixture(); local names,allowed=Debug.Catalog(g)
    LoadKeyValues = previous
    assert(allowed["npc_dota_hero_invoker"] and not allowed.invalid_unit)
    eq(#names,4)
    f:emit("start",{PlayerID=7,hero="npc_dota_hero_invoker",attack_damage=100}); f:finish()
    eq(g.lineup[1],"npc_dota_hero_invoker"); eq(g.heroData.npc_dota_hero_invoker.level,30)
end)
test("damage boundaries reject NaN fractions and out of range",function()
    for _,value in ipairs({-1,10001,0/0,0.5,math.huge,"garbage"}) do
        local f,g=fixture(); f:start(value); eq(#f.loads,0); eq(g.gold,321)
        f:enter(); local prior=g.skillDebug.damage
        f:emit("damage",{PlayerID=7,attack_damage=value}); eq(g.skillDebug.damage,prior)
    end
    for _,value in ipairs({0,10000,"0","10000"}) do
        local f,g=fixture(); f:enter(value)
        local enemy=g.battleManager.teamHeroes[3][1]; eq(enemy.damageMin,tonumber(value)); eq(enemy.damageMax,tonumber(value))
        f:emit("damage",{PlayerID=7,attack_damage=10000-tonumber(value)})
        eq(enemy.damageMin,10000-tonumber(value)); eq(enemy.damageMax,enemy.damageMin)
    end
end)
test("pending blocks battle and roster mutations without clearing campaign",function()
    local f,g=fixture(); local old=g.battleManager.teamHeroes[2][1]; f:start()
    g:OnStartBattle(nil,{}); eq(g.startCalls,0); eq(g.phase,"setup")
    for _,name in ipairs({"OnShopBuy","OnShopRefresh","OnBenchBuy","OnLineupSet","OnSelectLevel"}) do g[name](g,nil,{}); eq(g.calls[name],nil) end
    f:start(); eq(#f.loads,1); eq(g.gold,321); eq(g.runLives,4); eq(g.currentLevelId,"ch02"); assert(not old.removed)
    f:emit("reset",{PlayerID=7}); eq(g.rosterSpawns,1)
end)
test("cancel invalidates stale callbacks and retains campaign",function()
    local f,g=fixture(); f:start(); local stale=f.loads[1].fn
    f:emit("exit",{PlayerID=7}); stale(); eq(#f.loads,1); eq(g.gold,321); eq(g.runLives,4); eq(g.currentLevelId,"ch02")
    f:start(); stale(); eq(#f.loads,2); f.loads[2].fn(); f.loads[3].fn(); assert(g.skillDebug.active)
end)
test("precache timeout and exception preserve existing campaign",function()
    local f,g=fixture(); f:start(); eq(f.thinks.RpgSkillDebugPrecache.delay,30)
    f.thinks.RpgSkillDebugPrecache.fn(); assert(not g.skillDebug.pending); f.loads[1].fn()
    eq(g.gold,321); eq(g.rosterSpawns,1); eq(g.currentLevelId,"ch02")
    PrecacheUnitByNameAsync=function() error("native precache failure") end
    f:start(); assert(not g.skillDebug.pending); eq(g.gold,321)
end)
test("one level 30 hero, one 50000 HP target and 99999 gold; callback idempotence",function()
    local f,g=fixture(); f:enter(0)
    eq(#g.ownedHeroes,1); eq(#g.lineup,1); eq(#g.battleManager.teamHeroes[2],1); eq(#g.battleManager.teamHeroes[3],1)
    eq(g.battleManager.teamHeroes[2][1].level,30); eq(g.gold,99999)
    local enemy=g.battleManager.teamHeroes[3][1]; eq(enemy.name,Debug.UNIT)
    assert(require("tactics.neutral_attack").IsNeutral(enemy), "test creep uses persistent attack ownership instead of repeated attack orders")
    eq(enemy.hp,50000); eq(enemy.maxHP,50000); eq(enemy.baseHP,50000)
    eq(enemy.controllingPlayerId,7); eq(enemy.controlEnabled,true)
    local spawns=g.rosterSpawns; f.loads[1].fn(); f.loads[2].fn(); eq(g.rosterSpawns,spawns)
    eq(g.dataLoader:GetLevel(Debug.LEVEL).reward.gold,0)
    for _,name in ipairs({"OnShopBuy","OnShopRefresh","OnBenchBuy","OnLineupSet","OnSelectLevel"}) do g[name](g); eq(g.calls[name],nil) end
end)
test("reset retains authored rules equipment learned skills and talents; refreshes cooldowns",function()
    local f,g=fixture(); f:enter(); local old=g.battleManager.teamHeroes[2][1]
    local rules={{action="ability",condition="enemy_hp_below",value=30}}; g.heroRulesByName[HERO]=rules
    local serviceRules={authored=true}; g.tacticBridge.ruleService.state.rules=serviceRules
    old.abilities[1].level=4; old.abilities[2].level=1
    local item=cooldown("item_blink"); old.items[0]=item; g.gold=2; g.phase="fight"
    f:emit("reset",{PlayerID=7})
    eq(g.ruleGeneration,1,"reset keeps the current rule generation")
    local enemy=g.battleManager.teamHeroes[3][1]
    eq(enemy.controllingPlayerId,7); eq(enemy.controlEnabled,true)
    local new=g.battleManager.teamHeroes[2][1]; assert(new~=old and old.removed)
    eq(new.abilities[1].level,4); eq(new.abilities[2].level,1); eq(new.items[0],item)
    eq(new.abilities[1].remaining,0); eq(new.abilities[2].remaining,0); eq(item.remaining,0)
    eq(g.heroRulesByName[HERO],rules); eq(g.battleManager.teamRules[2][1],rules)
    eq(g.tacticBridge.ruleService.state.rules,serviceRules); eq(g.gold,99999); eq(g.phase,"setup")
end)
test("win death and timeout settle once with no normal awards lives or progression",function()
    for _,winner in ipairs({"good","bad","timeout"}) do
        local f,g=fixture(); f:enter(); g.runLives=4; g:OnStartBattle(nil,{})
        local item=cooldown("item_blink"); item.charges=3
        g.battleManager.teamHeroes[2][1].items[8]=item
        local stored=cooldown("item_refresher"); g.stash.items[14]=stored
        eq(item.remaining,20,"combat cooldown remains active")
        g:EndBattle(winner,3); g:EndBattle(winner,3)
        eq(item.remaining,0,"refresh before delayed debug rebuild")
        eq(stored.remaining,0,"debug warehouse refresh")
        eq(item.charges,3,"native charges preserved")
        eq(g.phase,"result"); eq(g.normalAwards,0); eq(g.runLives,4); eq(g.currentLevelId,Debug.LEVEL)
        local count=0
        for _,event in ipairs(f.events) do if event.name=="rpg_settlement" then
            count=count+1; eq(event.payload.debug,1); eq(event.payload.gold,0); eq(event.payload.xp_pool,0); eq(event.payload.clear_time,120)
        end end
        eq(count,1); local reset=f.thinks.RpgSkillDebugReset.fn; reset(); local n=g.rosterSpawns; reset(); eq(g.rosterSpawns,n)
        eq(g.phase,"setup"); eq(g.runLives,4)
    end
end)
test("exit from fight creates fresh normal run and restores recruitment and gold",function()
    local f,g=fixture(); local levels=g.orderedLevels; f:enter(); local old=g.battleManager.teamHeroes[2][1]
    local item=cooldown("item_blink"); old.items[0]=item
    g:OnStartBattle(nil,{}); eq(g.phase,"fight"); f:emit("exit",{PlayerID=7})
    assert(not g.skillDebug.active and not g.skillDebug.pending and old.removed and item.removed)
    eq(g.orderedLevels,levels); eq(g.currentLevelId,"ch01"); eq(g.phase,"setup"); eq(g.gold,500)
    eq(g.recruitInitializations,1); eq(g.freeRecruitChoices,3); eq(g.shopRolls,1)
    eq(#g.lineup,0); eq(#g.battleManager.teamHeroes[2],0); eq(#g.battleManager.teamHeroes[3],2)
    eq(g.battleManager.teamHeroes[3][1].name,"normal_enemy"); eq(g:OnShopBuy(4,"purchase"),"OnShopBuy")
    eq(g.calls.OnShopBuy[2],"purchase")
    for _,enemy in ipairs(g.battleManager.teamHeroes[3]) do eq(enemy.controllingPlayerId,nil) end
end)
test("settlement reset callback cannot reset a later normal run",function()
    local f,g=fixture(); f:enter(); g:OnStartBattle(); g:EndBattle("good")
    local stale=f.thinks.RpgSkillDebugReset.fn; f:emit("exit",{PlayerID=7}); stale()
    eq(g.gold,500); eq(g.currentLevelId,"ch01"); eq(g.recruitInitializations,1)
end)
test("normal wrappers preserve receiver arguments returns and install idempotence",function()
    local f,g=fixture(); local wrapped=g.EndBattle; Debug.Install(g); eq(g.EndBattle,wrapped)
    eq(g.dataLoader:GetLevel("ch02").id,"ch02"); eq(g:SpawnLevelEnemies("ch01"),"spawn-return")
    for _,enemy in ipairs(g.battleManager.teamHeroes[3]) do eq(enemy.controllingPlayerId,nil) end
    local a,b=g:OnStartBattle(9,"payload"); eq(a,"start-return"); eq(b,42); eq(g.startArgs[1],9); eq(g.startArgs[2],"payload")
    a,b=g:EndBattle("normal",2); eq(a,"end-return"); eq(b,43); eq(g.endArgs[2],2); eq(g.normalAwards,1)
    for _,name in ipairs({"OnShopBuy","OnShopRefresh","OnBenchBuy","OnLineupSet","OnSelectLevel"}) do
        a,b=g[name](g,6,"body"); eq(a,name); eq(b,44); eq(g.calls[name][1],6); eq(g.calls[name][2],"body")
    end
end)
test("manual stomp exception is exact and passes the real combat filter",function()
    local f,g=fixture(); f:enter(); g.phase="fight"
    DOTA_UNIT_ORDER_CAST_NO_TARGET=8
    local enemy=g.battleManager.teamHeroes[3][1]
    local ability={IsNull=function() return false end, entindex=function() return 902 end}
    enemy.entindex=function() return 901 end
    enemy.FindAbilityByName=function(_,name) if name=="centaur_hoof_stomp" then return ability end end
    EntIndexToHScript=function(id) if tonumber(id)==901 then return enemy end end
    local phase="FIGHT"
    local filter=require("tactics.order_filter").OrderFilter.new({
        get_phase=function() return phase end, is_battle_unit=function(u) return u==enemy end,
        allow_debug_cast=function(o) return Debug.AllowManualCast(g,o) end,
        validate_prepare_order=function() return false end,
    })
    local order={issuer_player_id_const=7,order_type=8,units={["0"]=901},entindex_ability=902}
    eq(filter:Filter(order),true)
    order.issuer_player_id_const=8; eq(filter:Filter(order),false); order.issuer_player_id_const=7
    order.entindex_ability=903; eq(filter:Filter(order),false); order.entindex_ability=902
    order.order_type=4; eq(filter:Filter(order),false); order.order_type=8
    order.units["1"]=999; eq(filter:Filter(order),false); order.units["1"]=nil
    order.units={}; eq(Debug.AllowManualCast(g,order),false); order.units={["0"]=901}
    g.skillDebug.pending=true; eq(filter:Filter(order),false); g.skillDebug.pending=false
    g.skillDebug.active=false; eq(filter:Filter(order),false); g.skillDebug.active=true
    for _,p in ipairs({"PREPARE","COUNTDOWN","SETTLE"}) do phase=p; eq(filter:Filter(order),false) end
    phase="FIGHT"; g.phase="setup"; eq(filter:Filter(order),false)
end)
test("all debug events require engine owner metadata",function()
    local f,g=fixture(); f:enter(); g:OnStartBattle()
    local spawns=g.rosterSpawns; local serial=g.skillDebug.serial; local events=#f.events
    for _,name in ipairs({"request","start","reset","exit","damage"}) do
        for _,payload in ipairs({{}, {PlayerID=8,hero=HERO,attack_damage=999}}) do f:emit(name,payload) end
    end
    eq(g.skillDebug.serial,serial); eq(g.rosterSpawns,spawns); eq(g.phase,"fight")
    eq(#f.events,events); assert(g.skillDebug.active)
end)
test("duplicate hero precache callbacks and cancellation during target loading",function()
    local f,g=fixture(); f:start(); f.loads[1].fn(); f.loads[1].fn()
    -- Native callbacks can repeat before target precache has completed.
    f.loads[2].fn(); local count=g.rosterSpawns; f.loads[3].fn(); eq(g.rosterSpawns,count)
    f,g=fixture(); f:start(); f.loads[1].fn(); local target=f.loads[2].fn
    f:emit("exit",{PlayerID=7}); target(); eq(g.gold,321); eq(g.currentLevelId,"ch02")
    assert(not g.skillDebug.active and not g.skillDebug.pending)
end)
test("stale phase timeout releases pending request (regression)",function()
    local f,g=fixture(); f:start(); g.phase="result"; f.loads[1].fn()
    assert(not g.skillDebug.active); eq(g.gold,321)
    f.thinks.RpgSkillDebugPrecache.fn()
    eq(g.skillDebug.pending,false,"phase change must not leave pending locked after timeout")
end)
test("debug end timeout reset and exit disable pending dead heroes before cleanup",function()
    for _,action in ipairs({"end","timeout","reset","exit"}) do
        local f,g=fixture(); f:enter(); g:OnStartBattle()
        local pending=g.battleManager.teamHeroes[2][1]
        pending.dead=true; pending.reincarnating=true; pending.respawnsDisabled=false
        -- Include a real enemy hero: the normal debug target is a non-hero creep.
        local enemy=unit("npc_dota_hero_skeleton_king")
        enemy.dead=true; enemy.reincarnating=true; enemy.respawnsDisabled=false
        table.insert(g.battleManager.teamHeroes[3],enemy)
        local alive=unit("npc_dota_hero_sven"); alive.respawnsDisabled=false
        table.insert(g.battleManager.teamHeroes[2],alive)
        local checks=0
        function g:assertRespawnStopped(stage)
            eq(self.phase,"result",stage .. " follows phase claim")
            for _,u in ipairs({pending,enemy,alive}) do
                eq(u.respawnsDisabled,true,action .. " disables all heroes before " .. stage)
                assert(not u.removed,"permission must change before removal")
            end
            checks=checks+1
        end
        -- The manager remains a mock so its own policy cannot conceal a missing
        -- Debug.stop call. Cleanup observes permission before even reaching it.
        g.battleManager.StopBattle=function(bm)
            g:assertRespawnStopped("manager stop"); bm.stops=bm.stops+1
        end
        if action=="end" or action=="timeout" then
            g:EndBattle(action=="timeout" and "timeout" or "good",3)
        else f:emit(action,{PlayerID=7}) end
        assert(checks>=5,"all cleanup modules and manager checked")
        eq(pending.respawnsDisabled,true); eq(enemy.respawnsDisabled,true)
    end
end)
local failures={}
for _,entry in ipairs(tests) do
    local ok,err=xpcall(entry[2],debug.traceback)
    if ok then print("PASS "..entry[1]) else print("FAIL "..entry[1].."\n"..err); failures[#failures+1]=entry[1] end
end
print(string.format("skill-debug: %d passed, %d failed (native respawn semantics mocked, not proven)",#tests-#failures,#failures))
assert(#failures==0,table.concat(failures,"; "))
