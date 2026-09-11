-- Player-operated sandbox. Enter/exit start fresh runs; a test reset keeps its build.
local Debug = { LEVEL = "skill_test", UNIT = "npc_rpg_skill_test_target", HP = 50000, GOLD = 99999 }
local Log = require("issue_fixes.runtime_log")
local Lifecycle = require("issue_fixes.hero_lifecycle_log")
local Policy = require("issue_fixes.hero_ability_policy")
local RespawnPolicy = require("battle.respawn_policy")
local cleanup = { require("battle.tempest_double"), require("tactics.special_targets"),
    require("battle.summon_behavior"), require("issue_fixes.tiny_tree") }
local function valid(unit) return unit ~= nil and (not unit.IsNull or not unit:IsNull()) end
local function state(game) return game.skillDebug end
local function safe(game, name, fn)
    if game.RunLifecycleStep then return game:RunLifecycleStep("debug_" .. name, fn) end
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then Log.Write("SkillDebug step=" .. name .. " error=" .. tostring(err)) end
    return ok, err
end
local function owner(game, payload)
    return type(payload) == "table" and game.playerId ~= nil and game.playerId >= 0
        and tonumber(payload.PlayerID) == game.playerId
end
local function number(value)
    local n = tonumber(value)
    if n == nil or n ~= n or n < 0 or n > 10000 or n ~= math.floor(n) then return nil end
    return n
end
function Debug.Catalog(game)
    local names, allowed = {}, {}
    local function add(hero)
        if type(hero) == "string" and hero:match("^npc_dota_hero_[a-z0-9_]+$") and not allowed[hero] then
            names[#names + 1], allowed[hero] = hero, true
        end
    end
    for _, category in pairs(game.heroPool or {}) do
        for _, hero in pairs(category) do add(hero) end
    end
    -- The ordinary recruitment pool deliberately omits four complex heroes.
    -- The independent, repository-audited catalog enables them for testing too.
    if game.skillDebugCatalog == nil then
        local ok, loaded = pcall(function() return LoadKeyValues("scripts/data/debug_heroes.kv") end)
        game.skillDebugCatalog = ok and type(loaded) == "table" and (loaded.debug_heroes or loaded) or {}
    end
    for _, hero in pairs(game.skillDebugCatalog) do add(hero) end
    table.sort(names)
    return names, allowed
end
function Debug.Publish(game, err)
    local s = state(game)
    local names = Debug.Catalog(game)
    local player = PlayerResource:GetPlayer(game.playerId)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, "rpg_debug_state", {
            active = s.active and 1 or 0, pending = s.pending and 1 or 0,
            phase = game.phase, run_complete = game.runComplete and 1 or 0,
            hero = s.hero or "", attack_damage = s.damage or 100,
            heroes_text = table.concat(names, ";"), error = err or "",
        })
    end
end
function Debug.Level(game)
    return { name = "Skill condition test", time_limit = 120, multi = 1,
        reward = { gold = 0, xp_per_active_hero = 0 },
        enemies = {{ unit = Debug.UNIT, count = 1, level = 1, ai = "demo_default", tags = {"skill_test"} }} }
end
local function all_units(game)
    local result = {}
    for _, units in pairs(game.battleManager.teamHeroes) do
        for _, unit in ipairs(units) do result[#result + 1] = unit end
    end
    return result
end
local function stop(game)
    -- Claim before native cleanup; callbacks cannot settle this fight twice.
    game.phase = "result"
    RespawnPolicy.SetBattleActive(game, false)
    for i, module in ipairs(cleanup) do safe(game, "clear_" .. i, function() module.Clear(game) end) end
    safe(game, "stop", function() game.battleManager:StopBattle() end)
    if game.issueFixes then safe(game, "enemy_stop", function() game.issueFixes:OnBattleEnded(all_units(game)) end) end
    game.tacticBridge:ResetState()
    if game.damageStats then
        game.damageStats:Stop(GameRules:GetGameTime())
        safe(game, "damage", function() game:BroadcastDamageStats() end)
    end
end
local function remove_item(item)
    if valid(item) and item.RemoveSelf then item:RemoveSelf() end
end
local function clear_items(unit)
    if not valid(unit) or not unit.GetItemInSlot then return end
    for slot = 0, 16 do
        local item = unit:GetItemInSlot(slot)
        if valid(item) then
            if unit.TakeItem then unit:TakeItem(item) end
            remove_item(item)
        end
    end
end
local function clear_run(game)
    stop(game)
    local removed = {}
    local function remove(unit)
        if not valid(unit) or removed[unit] then return end
        removed[unit] = true
        clear_items(unit)
        Lifecycle.Remove(game, unit, "debug_run_reset")
    end
    for _, unit in ipairs(all_units(game)) do remove(unit) end
    for _, unit in ipairs(game.benchUnits or {}) do remove(unit) end
    clear_items(game:GetStashUnit())
    -- A fresh run must not inherit equipment left on the ground in the old run.
    if Entities and Entities.FindAllByClassname then
        for _, drop in pairs(Entities:FindAllByClassname("dota_item_physical") or {}) do
            if valid(drop) and drop.GetContainedItem then
                remove_item(drop:GetContainedItem())
                if valid(drop) then drop:RemoveSelf() end
            end
        end
    end
    game.battleManager.teamHeroes = {[DOTA_TEAM_GOODGUYS]={}, [DOTA_TEAM_BADGUYS]={}}
    game.battleManager.teamRules = {[DOTA_TEAM_GOODGUYS]={}, [DOTA_TEAM_BADGUYS]={}}
    game.battleManager.heroStates, game.battleManager.enemyTags = {}, {}
    game.battleManager:ResetBattleStats()
    game.ownedHeroes, game.lineup, game.benchUnits, game.heroData = {}, {}, {}, {}
    game.heroOrder, game.benchSlots, game.refreshCount, game.freeRecruitChoices = 0, 0, 0, 0
    game.heroRulesByName, game.heroInventories, game.autoAbilityHeroes, game.placedPositions = {}, {}, {}, {}
    game.scrollStock, game.scrollPurchases, game.scrollBought = {low=0,high=0}, {low=0,high=0}, {low=0,high=0}
    game.pendingNativePurchases, game.nativePurchaseOrderContexts, game.nativePurchaseClaimedIds = {}, {}, {}
    game.nativeOrderSignatures, game.nativePurchaseBaseline = {}, {}
    game.nativePurchaseSelectionHero, game.nativeShopTransactionPending = nil, nil
    game.rosterAbilitySnapshot, game.equipmentSnapshot = nil, nil
    game.runComplete, game.runFailed, game.runLives = false, false, nil
    game.shopOffers, game.shopOfferText, game.winner = {}, "", ""
    game.damageStats = nil
    game.attemptBuybacks, game.encounterSeed = 0, nil
    if game.tacticBridge.ruleService then game.tacticBridge.ruleService.state.rules = {} end
    game.ruleGeneration = (game.ruleGeneration or 0) + 1
    game.tacticBridge:ResetState()
end
local function broadcast(game)
    game:BroadcastLevelInfo()
    game:BroadcastBattleState()
    game:BroadcastHeroInfo()
    game:BroadcastShopState()
    Debug.Publish(game)
end
local function ready(game)
    game.phase, game.winner, game.runComplete, game.runFailed = "setup", "", false, false
    if valid(game.placeholderHero) then game.placeholderHero:RemoveModifierByName("modifier_invulnerable") end
    game:SpawnLevelEnemies(game.currentLevelId)
    game:RespawnPlayerRoster()
    assert(#game.battleManager.teamHeroes[DOTA_TEAM_BADGUYS] == 1, "test enemy did not spawn")
    assert(#game.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] == 1, "test hero did not spawn")
    for _, unit in ipairs(all_units(game)) do
        for slot = 0, Policy.GetSlotCount(unit) - 1 do
            local ability = unit:GetAbilityByIndex(slot)
            if valid(ability) and ability.EndCooldown then ability:EndCooldown() end
        end
        if unit.GetItemInSlot then
            for slot = 0, 16 do
                local item = unit:GetItemInSlot(slot)
                if valid(item) and item.EndCooldown then item:EndCooldown() end
            end
        end
    end
    game:SetGoldBalance(Debug.GOLD)
    game.teamsSpawned = true
    game:SpawnBattleBarrier()
    broadcast(game)
end
function Debug.Reset(game)
    local s = state(game)
    if not s.active or s.pending then return false, "wrong_phase" end
    game.settlementGeneration = (game.settlementGeneration or 0) + 1
    stop(game)
    ready(game)
    Log.Write("SkillDebug reset hero=" .. s.hero .. " damage=" .. s.damage)
    return true
end
function Debug.Enter(game, hero, damage)
    local s = state(game)
    clear_run(game)
    s.active, s.hero, s.damage = true, hero, damage
    game.orderedLevels, game.currentLevelId = {Debug.LEVEL}, Debug.LEVEL
    game.ownedHeroes, game.lineup, game.heroOrder = {hero}, {hero}, 1
    game.heroData[hero] = {level=30, current_xp=0, skill_points=30, quality="common", order=1, inventory={}}
    ready(game)
    Log.Write("SkillDebug enter hero=" .. hero .. " level=30 gold=99999 hp=50000 damage=" .. damage .. " rule_generation=" .. (game.ruleGeneration or 0))
end
function Debug.Exit(game)
    local s = state(game)
    if not s.active and not s.pending then return false, "wrong_phase" end
    s.serial, s.pending = s.serial + 1, false
    game.settlementGeneration = (game.settlementGeneration or 0) + 1
    -- Cancelling initial resource loading leaves the existing normal run intact.
    if not s.active then Debug.Publish(game); return true end
    clear_run(game)
    s.active, s.hero = false, nil
    game.orderedLevels = s.normalLevels
    game.currentLevelId = game.orderedLevels[1] or "ch01"
    game.phase, game.teamsSpawned = "setup", true
    if valid(game.placeholderHero) then game.placeholderHero:RemoveModifierByName("modifier_invulnerable") end
    game:InitializeRecruitmentState()
    game:SetGoldBalance(game.initialGold)
    game:SpawnLevelEnemies(game.currentLevelId)
    game:RespawnPlayerRoster()
    game:SpawnBattleBarrier()
    game:RollShop()
    broadcast(game)
    Log.Write("SkillDebug exit normal_level=" .. game.currentLevelId .. " rule_generation=" .. (game.ruleGeneration or 0))
    return true
end
function Debug.Start(game, payload)
    local s = state(game)
    if s.pending then return false, "busy" end
    if (game.phase ~= "setup" and not (game.phase == "result" and game.runComplete))
        or not game.teamsSpawned or not valid(game:GetStashUnit()) then return false, "wrong_phase" end
    local _, allowed = Debug.Catalog(game)
    if not allowed[payload.hero] then return false, "invalid_hero" end
    local damage = number(payload.attack_damage)
    if damage == nil then return false, "invalid_damage" end
    local hero, phase, generation = payload.hero, game.phase, game.settlementGeneration
    s.serial, s.pending = s.serial + 1, true
    local serial = s.serial
    Debug.Publish(game)
    local function pending_current() return s.serial == serial and s.pending end
    local function current()
        return pending_current() and game.phase == phase and game.settlementGeneration == generation
    end
    local function fail(reason)
        -- A stale phase must cancel its own pending request, while an older
        -- serial must never clear a newer request or recreate a departed test.
        if not pending_current() then return end
        s.pending = false
        Debug.Publish(game, reason)
    end
    local function complete()
        if not current() then fail("wrong_phase"); return end
        s.pending = false
        game.settlementGeneration = (game.settlementGeneration or 0) + 1
        local ok = safe(game, "enter", function() Debug.Enter(game, hero, damage) end)
        if not ok then Debug.Publish(game, "spawn_failed") end
    end
    local function load(name, callback)
        if type(PrecacheUnitByNameAsync) ~= "function" then callback(); return end
        local ok = pcall(PrecacheUnitByNameAsync, name, function()
            if current() then callback() else fail("wrong_phase") end
        end, game.playerId)
        if not ok then fail("precache_failed") end
    end
    GameRules:GetGameModeEntity():SetContextThink("RpgSkillDebugPrecache", function()
        fail("precache_failed"); return nil
    end, 30)
    load(hero, function() load(Debug.UNIT, complete) end)
    return true
end
function Debug.EndBattle(game, winner)
    if game.phase ~= "fight" then return end
    local elapsed = math.floor(game.battleManager:GetBattleTime())
    stop(game)
    game.winner = winner
    game.settlementGeneration = (game.settlementGeneration or 0) + 1
    local generation = game.settlementGeneration
    safe(game, "settlement", function()
        CustomGameEventManager:Send_ServerToAllClients("rpg_settlement", {
            level=Debug.LEVEL, winner=winner, gold=0, base_gold=0, time_bonus=0,
            xp_pool=0, xp_per_active_hero=0, xp_per_bench_hero=0, stars=0, clear_time=elapsed,
            loot_text="", lives_remaining=5, max_lives=5, run_failed=0, debug=1,
        })
    end)
    game:BroadcastBattleState()
    Debug.Publish(game)
    GameRules:GetGameModeEntity():SetContextThink("RpgSkillDebugReset", function()
        if state(game).active and game.phase == "result" and game.settlementGeneration == generation then
            local ok = safe(game, "reset", function() Debug.Reset(game) end)
            if not ok then Debug.Publish(game, "spawn_failed") end
        end
        return nil
    end, 3)
end
function Debug.Install(game)
    if game.skillDebug then return end
    game.skillDebug = {active=false, pending=false, damage=100, serial=0, normalLevels=game.orderedLevels}
    local getLevel = game.dataLoader.GetLevel
    game.dataLoader.GetLevel = function(loader, id)
        if state(game).active and id == Debug.LEVEL then return Debug.Level(game) end
        return getLevel(loader, id)
    end
    local spawn = game.SpawnLevelEnemies
    game.SpawnLevelEnemies = function(self, id)
        local result = spawn(self, id)
        if state(self).active then
            for _, unit in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
                unit:SetBaseMaxHealth(Debug.HP); unit:SetMaxHealth(Debug.HP); unit:SetHealth(Debug.HP)
                unit:SetBaseDamageMin(state(self).damage); unit:SetBaseDamageMax(state(self).damage)
            end
        end
        return result
    end
    local ending = game.EndBattle
    game.EndBattle = function(self, winner, team)
        if state(self).active then return Debug.EndBattle(self, winner) end
        return ending(self, winner, team)
    end
    local starting = game.OnStartBattle
    game.OnStartBattle = function(self, ...)
        if state(self).pending then return end
        return starting(self, ...)
    end
    -- Keep exactly one selected hero; ordinary recruitment/level switching is
    -- available again immediately after exiting the sandbox.
    for _, method in ipairs({"OnShopBuy", "OnShopRefresh", "OnBenchBuy", "OnLineupSet", "OnSelectLevel"}) do
        local original = game[method]
        game[method] = function(self, ...)
            if state(self).active or state(self).pending then return end
            return original(self, ...)
        end
    end
    local function listen(event, action)
        CustomGameEventManager:RegisterListener(event, function(_, payload)
            if not owner(game, payload) then return end
            local ok, accepted, err = xpcall(function() return action(payload) end, debug.traceback)
            if not ok then
                Log.Write("SkillDebug event=" .. event .. " error=" .. tostring(accepted))
                state(game).pending = false
                Debug.Publish(game, "spawn_failed")
            elseif accepted == false then Debug.Publish(game, err) end
        end)
    end
    listen("rpg_debug_request", function() Debug.Publish(game); return true end)
    listen("rpg_debug_start", function(payload) return Debug.Start(game, payload) end)
    listen("rpg_debug_reset", function() return Debug.Reset(game) end)
    listen("rpg_debug_exit", function() return Debug.Exit(game) end)
    listen("rpg_debug_damage", function(payload)
        if not state(game).active or state(game).pending or game.phase ~= "setup" then return false, "wrong_phase" end
        local damage = number(payload.attack_damage)
        if damage == nil then return false, "invalid_damage" end
        state(game).damage = damage
        for _, unit in ipairs(game.battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
            if valid(unit) then unit:SetBaseDamageMin(damage); unit:SetBaseDamageMax(damage) end
        end
        Debug.Publish(game)
        Log.Write("SkillDebug damage=" .. damage)
        return true
    end)
end
return Debug
