local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
function class() local t = {}; t.__index = t; return t end
function IsValidEntity(u) return u and not u.invalid end
local now = 10
GameRules = {GetGameTime = function() return now end}
local Buyback = require("battle.buyback")
require("battle.battle_manager")
local cases = 0
local function test(name, fn) fn(); cases = cases + 1; print("PASS: " .. name) end
local function cooldown(n)
    return {remaining = n, IsNull = function() return false end,
        GetCooldownTimeRemaining = function(self) return self.remaining end,
        EndCooldown = function(self) self.remaining = 0 end,
        StartCooldown = function(self, value) self.remaining = value end}
end
local heroSerial = 0
local function hero(level, team)
    heroSerial = heroSerial + 1
    local h = {name = "npc_dota_hero_test_" .. heroSerial, level = level or 1, team = team or 2, alive = false, position = {x=12,y=34,z=0},
        abilities = {[0]=cooldown(12), [1]=cooldown(0)}, items = {[0]=cooldown(25), [8]=cooldown(7)},
        rules = {{enabled=true, action={kind="buyback"}}}, events = {}, respawns = 0,
        modifiers = {modifier_unrelated = true}, stops = 0}
    function h:IsNull() return self.invalid == true end
    function h:IsRealHero() return self.real ~= false end
    function h:GetTeamNumber() return self.team end
    function h:GetLevel() return self.level end
    function h:GetUnitName() return self.name end
    function h:IsAlive() return self.alive end
    function h:IsReincarnating() return self.returning == true end
    function h:GetAbsOrigin() return self.position end
    function h:GetAbilityCount() return 2 end
    function h:GetAbilityByIndex(i) return self.abilities[i] end
    function h:GetItemInSlot(i) return self.items[i] end
    function h:SetRespawnsDisabled(v) self.disabled = v end
    function h:SetRespawnPosition(v) self.respawnPosition = v end
    function h:RespawnHero(resetInventory, buyback)
        assert(resetInventory == false and buyback == false)
        assert(self.events[#self.events] == "reset", "ResetUnit must precede native revive")
        self.events[#self.events+1] = "revive"; self.respawns = self.respawns + 1
        if self.fail == "throw" then error("mock respawn failure") end
        if self.fail then return end
        self.alive = true
        self.modifiers.modifier_fountain_invulnerability = true
        -- Native respawn may refresh cooldowns; backend must put them back.
        for _, source in pairs(self.abilities) do source.remaining = 0 end
        for _, source in pairs(self.items) do source.remaining = 0 end
    end
    function h:RemoveModifierByName(name)
        assert(self.alive, "modifier cleanup must follow revive")
        self.modifiers[name] = nil
    end
    function h:Stop()
        assert(self.alive, "Stop must follow revive")
        self.stops = self.stops + 1
    end
    function h:GetMaxHealth() return 1000 end
    function h:GetMaxMana() return 500 end
    function h:SetHealth(n) self.health = n end
    function h:SetMana(n) self.mana = n end
    function h:SetIdleAcquire(v) self.acquire = v end
    function h:SetAcquisitionRange(v) self.range = v end
    return h
end
local function game(heroes, gold)
    local g = {phase="fight", gold=gold or 0, spends=0, refunds=0}
    function g:GetGoldBalance() return self.gold end
    function g:SpendGold(n)
        if self.rejectSpend or self.gold < n then return false end
        self.gold = self.gold - n; self.spends = self.spends + 1; return true
    end
    function g:AddGold(n) self.gold = self.gold + n; self.refunds = self.refunds + 1 end
    function g:EndBattle(winner) self.winner = winner end
    g.tacticBridge = {getRules=function(h) return h.rules end,
        ResetUnit=function(_, h) assert(not h.alive); h.events[#h.events+1]="reset" end}
    g.battleManager = setmetatable({}, BattleManager)
    g.battleManager:constructor(g)
    local enemy = hero(1, 3); enemy.alive = true
    g.battleManager.teamHeroes = {[2]=heroes, [3]={enemy}}
    g.battleManager.phase, g.battleManager.battleStartedAt = "fight", 0
    Buyback.BeginBattle(g)
    return g
end

test("cost curve and level bounds", function()
    for level=1,30 do
        local base=100+50*level+5*level*level
        for difficulty,rate in pairs({easy=.75,default=1,hard=1.25}) do
            assert(Buyback.Cost(level,difficulty)==math.floor(base*rate/5+.5)*5)
        end
        assert(Buyback.Cost(level)==base and Buyback.Cost(level,"unknown")==base)
    end
    assert(Buyback.Cost(1)==155 and Buyback.Cost(10)==1100 and Buyback.Cost(30)==6100)
    assert(Buyback.Cost(0)==155 and Buyback.Cost(31)==6100 and Buyback.Cost("10")==1100)
end)
test("enabled forms, absent rules, and alive heroes", function()
    for _, enabled in ipairs({false, 0, "0"}) do
        local h=hero(); h.rules[1].enabled=enabled; local g=game({h},1000)
        Buyback.Process(g); assert(g.spends==0 and not h.alive)
    end
    for _, enabled in ipairs({true, 1, "1"}) do
        local h=hero(); h.rules[1].enabled=enabled; local g=game({h},155)
        Buyback.Process(g); assert(h.alive and g.gold==0)
    end
    local h=hero(); h.rules={}; local g=game({h},1000)
    Buyback.Process(g); assert(g.spends==0)
    h.rules={{action={kind="buyback"}}}; h.alive=true
    Buyback.Process(g); assert(g.spends==0 and h.respawns==0)
    h.alive=false; Buyback.Process(g); assert(g.spends==1)
end)
test("insufficient balance and failed atomic debit do not revive", function()
    for _, reject in ipairs({false,true}) do
        local h=hero(); local g=game({h},reject and 155 or 154); g.rejectSpend=reject
        Buyback.Process(g); assert(not h.alive and h.respawns==0 and g.spends==0 and #h.events==0)
    end
end)
test("stable shared wallet, duplicate rules and repeated ticks", function()
    local a,b=hero(),hero(); a.rules[2]=a.rules[1]
    local g=game({a,b},155); Buyback.Process(g); Buyback.Process(g)
    assert(a.alive and not b.alive and g.spends==1 and g.gold==0)
    g:AddGold(155); Buyback.Process(g)
    assert(b.alive and g.spends==2)
    a.alive=false; g:AddGold(155); Buyback.Process(g)
    assert(not a.alive and a.respawns==1 and g.spends==2 and g.gold==155,
        "a second death in the same mission must not buy back")
    a.rules[1].enabled=false; Buyback.Process(g); a.rules[1].enabled=true; Buyback.Process(g)
    assert(not a.alive and g.spends==2, "toggling or duplicate rules cannot reset the allowance")
    g.battleManager:StartBattle(g.battleManager.teamRules)
    Buyback.Process(g)
    assert(not a.alive and a.respawns==1 and g.spends==2, "default retry must respect hero cooldown")
end)
test("difficulty price uses the campaign setting and exact affordability", function()
    for difficulty,cost in pairs({easy=825,default=1100,hard=1375}) do
        local h=hero(10); local g=game({h},cost-1); g.campaignDifficulty=difficulty
        Buyback.Process(g); assert(not h.alive and g.spends==0)
        g:AddGold(1); Buyback.Process(g)
        assert(h.alive and g.spends==1 and g.gold==0)
    end
end)
test("native reincarnation, enemy, arena and non-lineup exclusion", function()
    local h=hero(); local g=game({h},1000); h.returning=true
    Buyback.Process(g); assert(g.spends==0)
    assert(not g.battleManager.buybackState[h].used, "native reincarnation does not consume paid allowance")
    h.returning=false; h.team=3; Buyback.Process(g); assert(g.spends==0)
    h.team=2; g.battleManager.arenaActive=true; Buyback.Process(g); assert(g.spends==0)
    g.battleManager.arenaActive=false; assert(not Buyback.IsEligible(g,hero()))
    h.real=false; Buyback.Process(g); assert(g.spends==0)
    h.real=true; g.phase="prepare"; Buyback.Process(g); assert(g.spends==0)
    g.phase="fight"; g.battleManager.phase="settle"; Buyback.Process(g); assert(g.spends==0)
end)
test("failed respawn refunds once and suppresses repeated charges for that death", function()
    for _, failure in ipairs({true,"throw"}) do
        local h=hero(); h.fail=failure; local g=game({h},155)
        Buyback.Process(g); Buyback.Process(g); Buyback.Process(g)
        assert(g.gold==155 and g.spends==1 and g.refunds==1 and h.respawns==1 and h.disabled)
        assert(not g.battleManager.buybackState[h].used, "a failed revive must not spend the allowance")
        h.fail=nil; h.alive=true; Buyback.Process(g); h.alive=false; Buyback.Process(g)
        assert(h.alive and g.spends==2 and g.gold==0, "new death clears failed-attempt latch")
    end
end)
test("same hero retains inventory and cooldowns and resets tactics before revive", function()
    local h=hero(); local g=game({h},155); local origin=h.position
    local inventory, spell, item=h.items,h.abilities[0],h.items[0]
    h.position={x=99,y=99,z=0}; Buyback.Process(g)
    assert(g.battleManager.teamHeroes[2][1]==h and h.items==inventory and h.items[0]==item)
    assert(h.abilities[0]==spell and spell.remaining==12 and h.abilities[1].remaining==0)
    assert(item.remaining==25 and h.items[8].remaining==7)
    assert(h.respawnPosition==origin and h.health==1000 and h.mana==500)
    assert(h.acquire and h.range==4000 and h.events[1]=="reset" and h.events[2]=="revive")
end)
test("revive removes fountain protection, preserves unrelated modifiers and stops orders", function()
    local h=hero(); local g=game({h},155)
    Buyback.Process(g)
    assert(h.alive and h.respawns==1)
    assert(h.modifiers.modifier_fountain_invulnerability==nil, "native fountain protection must be removed")
    assert(h.modifiers.modifier_unrelated==true, "unrelated modifiers must survive cleanup")
    assert(h.stops==1, "revived hero must stop stale orders once")
    Buyback.Process(g)
    assert(h.stops==1, "alive ticks must not interrupt new orders")
end)
test("actual wipe gate buys back affordable full wipe and ends unaffordable wipe", function()
    now=10
    local h=hero(); local g=game({h},155)
    assert(not g.battleManager:CheckBattleEnd() and h.alive and g.winner==nil and g.gold==0)
    h=hero(); g=game({h},154)
    assert(g.battleManager:CheckBattleEnd() and g.winner=="dire" and g.spends==0)
end)
test("a second full wipe ends battle despite enough money", function()
    now=10
    local h=hero(); local g=game({h},10000)
    assert(not g.battleManager:CheckBattleEnd() and h.alive)
    h.alive=false
    assert(g.battleManager:CheckBattleEnd() and g.winner=="dire")
    assert(g.spends==1 and g.gold==9845 and h.respawns==1)
end)
test("actual wipe gate resolves timeout before spending", function()
    now=120
    local h=hero(); local g=game({h},1000)
    assert(g.battleManager:CheckBattleEnd() and g.winner=="timeout" and g.spends==0 and h.respawns==0)
    now=10
end)
test("hard retry restores shared quota while each hero keeps its cooldown", function()
    local a,b=hero(),hero(); local g=game({a,b},10000)
    g.campaignDifficulty="hard"; g.currentLevelId=4; Buyback.BeginBattle(g)
    local quota=g.hardBuybackState
    Buyback.Process(g)
    assert(a.alive and not b.alive and g.spends==1 and quota.used and not quota.processing)
    a.alive=false; Buyback.BeginBattle(g); Buyback.Process(g)
    assert(g.hardBuybackState~=quota and g.spends==2 and not a.alive and b.alive,
        "same chapter retry restores team quota for a different ready hero")
    b.alive=false; g.currentLevelId=5; Buyback.BeginBattle(g); Buyback.Process(g)
    assert(not a.alive and not b.alive and g.spends==2 and not g.hardBuybackState.used,
        "next chapter resets team quota but cannot clear hero cooldowns")
end)
test("hard payment reserves the team quota before nested processing", function()
    local a,b=hero(),hero(); local g=game({a,b},10000)
    g.campaignDifficulty="hard"; g.currentLevelId=1; Buyback.BeginBattle(g)
    local spend=g.SpendGold
    function g:SpendGold(n)
        assert(self.hardBuybackState.processing)
        Buyback.Process(self)
        assert(b.respawns==0 and self.spends==0)
        return spend(self,n)
    end
    Buyback.Process(g)
    assert(a.alive and not b.alive and g.spends==1 and not g.hardBuybackState.processing)
end)
test("hard rejected payment releases reservation without consumption", function()
    local h=hero(); local g=game({h},10000); g.campaignDifficulty="hard"; g.rejectSpend=true
    Buyback.Process(g)
    assert(not g.hardBuybackState.used and not g.hardBuybackState.processing and g.spends==0)
    g.rejectSpend=false; Buyback.Process(g)
    assert(h.alive and g.spends==1 and g.hardBuybackState.used)
end)
test("hard failed revival refunds and leaves quota for another hero", function()
    for _,failure in ipairs({true,"throw"}) do
        local a,b=hero(),hero(); a.fail=failure
        local g=game({a,b},10000); g.campaignDifficulty="hard"
        local add=g.AddGold
        function g:AddGold(n)
            assert(self.hardBuybackState.processing and not self.hardBuybackState.used)
            Buyback.Process(self)
            assert(b.respawns==0)
            add(self,n)
        end
        Buyback.Process(g); Buyback.Process(g)
        assert(not a.alive and b.alive and g.spends==2 and g.refunds==1)
        assert(g.gold==10000-Buyback.Cost(1,"hard"))
        assert(g.hardBuybackState.used and not g.hardBuybackState.processing)
    end
end)
test("hard successful revival consumes quota despite cleanup failure", function()
    local a,b=hero(),hero(); local g=game({a,b},10000); g.campaignDifficulty="hard"
    function a:Stop() error("mock cleanup failure") end
    Buyback.Process(g); Buyback.Process(g)
    assert(a.alive and not b.alive and g.spends==1 and g.refunds==0 and g.hardBuybackState.used)
end)
test("easy retains per-hero allowance on every retry", function()
    local a,b=hero(),hero(); local g=game({a,b},10000); g.campaignDifficulty="easy"
    for attempt=1,4 do
        if attempt>1 then Buyback.BeginBattle(g) end
        a.alive=false; b.alive=false; Buyback.Process(g)
        assert(a.alive and b.alive and g.spends==attempt*2)
        a.alive=false; b.alive=false; Buyback.Process(g)
        assert(not a.alive and not b.alive and g.spends==attempt*2)
    end
end)
test("default and hard skip exactly the next two or three battle attempts", function()
    for difficulty,skipped in pairs({default=2,hard=3}) do
        local h=hero(); local g=game({h},10000); g.campaignDifficulty=difficulty
        Buyback.Process(g); assert(h.alive and g.spends==1)
        h.alive=false
        for attempt=1,skipped do
            -- Mix retries and new chapters; both count and neither clears CD early.
            g.currentLevelId=attempt<skipped and "ch01" or "ch02"
            g.battleManager:StartBattle(g.battleManager.teamRules)
            Buyback.Process(g); Buyback.Process(g)
            assert(not h.alive and g.spends==1, difficulty .. " blocked attempt " .. attempt)
        end
        g.battleManager:StartBattle(g.battleManager.teamRules); Buyback.Process(g)
        assert(h.alive and g.spends==2, difficulty .. " expires after all skipped battles")
        h.alive=false; Buyback.Process(g)
        assert(not h.alive and g.spends==2, "still only once in the eligible battle")
        Buyback.BeginBattle(g); Buyback.Process(g)
        assert(not h.alive and g.spends==2, "second buyback starts a new cooldown")
    end
end)
test("hero identity survives entity recreation, lineup moves and rule toggles", function()
    local a,b=hero(),hero(); local g=game({a,b},10000)
    b.rules={}; Buyback.Process(g); assert(a.alive and g.spends==1)
    local replacement=hero(); replacement.lineupHeroName=a.name
    g.battleManager.teamHeroes[2]={b,replacement}
    replacement.rules[1].enabled=false; Buyback.Process(g)
    replacement.rules[1].enabled=true; Buyback.Process(g)
    assert(not replacement.alive and g.spends==1, "new entity cannot bypass current cooldown")
    Buyback.BeginBattle(g); Buyback.Process(g)
    assert(not replacement.alive and g.spends==1)
    -- Benching does not erase the saved identity; an actual battle still counts.
    g.battleManager.teamHeroes[2]={b}; Buyback.BeginBattle(g)
    g.battleManager.teamHeroes[2]={replacement,b}; Buyback.Process(g)
    assert(not replacement.alive and g.spends==1)
    Buyback.BeginBattle(g); Buyback.Process(g)
    assert(replacement.alive and g.spends==2)
end)
test("arena battles and repeated prepare processing cannot advance campaign cooldown", function()
    local h=hero(); local g=game({h},10000); Buyback.Process(g); h.alive=false
    local battle=g.buybackBattleNumber
    g.phase="setup"
    for i=1,10 do Buyback.Process(g) end
    assert(g.buybackBattleNumber==battle)
    g.battleManager.arenaActive=true; Buyback.BeginBattle(g)
    g.battleManager.arenaActive=false; g.arena={mode="arena"}; Buyback.BeginBattle(g)
    assert(g.buybackBattleNumber==battle)
    g.arena=nil; g.phase="fight"; Buyback.BeginBattle(g); Buyback.Process(g)
    assert(not h.alive and g.spends==1, "first subsequent campaign battle is still blocked")
end)
test("fresh run clears persisted hard quota", function()
    local originalRequire=require
    local fresh=assert(loadfile(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/battle/fresh_run.lua"))
    setfenv(fresh,setmetatable({require=function(name)
        if name=="battle.respawn_policy" then return originalRequire(name) end
        return {Reset=function() end,Clear=function() end,Ensure=function() end}
    end},{__index=_G}))
    local g=game({},1000); g.hardBuybackState={used=true,processing=true}
    g.buybackBattleNumber=8; g.buybackReadyBattle={npc_dota_hero_axe=12}
    g.battleManager.teamHeroes={[2]={},[3]={}}
    g.battleManager.StopBattle=function() end
    g.battleManager.ResetBattleStats=function() end
    g.tacticBridge.ResetState=function() end
    g.GetStashUnit=function() return nil end
    g.InitializeRecruitmentState=function() end
    g.SetGoldBalance=function(self,n) self.gold=n end
    fresh().Reset(g)
    assert(g.hardBuybackState==nil and g.buybackBattleNumber==nil and g.buybackReadyBattle==nil)
    g.campaignDifficulty="hard"; g.currentLevelId=1; Buyback.BeginBattle(g)
    assert(not g.hardBuybackState.used and not g.hardBuybackState.processing)
end)
print("PASS: " .. cases .. " buyback backend scenarios")
