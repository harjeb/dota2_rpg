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
local function hero(level, team)
    local h = {level = level or 1, team = team or 2, alive = false, position = {x=12,y=34,z=0},
        abilities = {[0]=cooldown(12), [1]=cooldown(0)}, items = {[0]=cooldown(25), [8]=cooldown(7)},
        rules = {{enabled=true, action={kind="buyback"}}}, events = {}, respawns = 0,
        modifiers = {modifier_unrelated = true}, stops = 0}
    function h:IsNull() return self.invalid == true end
    function h:IsRealHero() return self.real ~= false end
    function h:GetTeamNumber() return self.team end
    function h:GetLevel() return self.level end
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
    for level=1,30 do assert(Buyback.Cost(level) == 100+50*level+5*level*level) end
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
    assert(a.alive and a.respawns==2 and g.spends==3, "a later death may buy back again")
end)
test("native reincarnation, enemy, arena and non-lineup exclusion", function()
    local h=hero(); local g=game({h},1000); h.returning=true
    Buyback.Process(g); assert(g.spends==0)
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
test("actual wipe gate resolves timeout before spending", function()
    now=120
    local h=hero(); local g=game({h},1000)
    assert(g.battleManager:CheckBattleEnd() and g.winner=="timeout" and g.spends==0 and h.respawns==0)
    now=10
end)
print("PASS: " .. cases .. " buyback backend scenarios")
