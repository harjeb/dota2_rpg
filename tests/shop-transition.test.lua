local root = TEST_REPO_ROOT or "."
local moduleRoot = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
function class()
    local result = {}
    result.__index = result
    return result
end
function Vector(x, y, z) return { x = x, y = y, z = z } end
DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
TacticEngine = { IsValidUnit = function() return false end }
require = function(name)
    if name == "issue_fixes.bootstrap" then return { Install = function() end } end
    local modules = {
        ["issue_fixes.hero_lifecycle_log"] = true,
        ["tactics/ability_catalog"] = true,
        ["tactics/rule_snapshot"] = true,
        ["battle.damage_stats"] = true,
        ["battle.enemy_scaling"] = true,
        ["battle.boss_scaling"] = true,
        ["battle.run_lives"] = true,
        ["battle/summon_behavior"] = true,
        ["issue_fixes/tiny_tree"] = true,
        ["issue_fixes/hero_precache"] = true,
        ["tactics/special_targets"] = true,
        ["battle.tempest_double"] = true,
        ["issue_fixes/hero_ability_policy"] = true,
        ["data.progression_data"] = true,
        ["patches.recruitment_patch"] = true,
        ["patches.progression_patch"] = true,
        ["patches.enemy_items_patch"] = true,
    }
    if modules[name] then return dofile(moduleRoot .. name:gsub("%.", "/") .. ".lua") end
    error("unused engine module: " .. name)
end
dofile(moduleRoot .. "addon_game_mode.lua")
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function scenario(winner, final, initialLives)
    initialLives = initialLives or 5
    local callback, scheduled, settlements, lastSettlement = nil, 0, 0, nil
    GameRules = { GetGameModeEntity = function()
        return { SetContextThink = function(_, name, fn, delay)
            equal(name, "Dota2RpgBackToSetup", "transition timer")
            equal(delay, 3, "settlement delay")
            callback = fn
            scheduled = scheduled + 1
        end }
    end }
    CustomGameEventManager = { Send_ServerToAllClients = function(_, event, payload)
        equal(event, "rpg_settlement", "settlement event")
        settlements = settlements + 1
        lastSettlement = payload
    end }
    local game = setmetatable({
        phase = "fight", currentLevelId = final and "ch02" or "ch01",
        runLives = { remaining = initialLives, pendingItems = {} },
        orderedLevels = { "ch01", "ch02" }, lineup = {}, ownedHeroes = {},
        refreshCount = 3, scrollPurchases = { low = 2, high = 1 }, gold = 500,
        shopCosts = { lineup_max = 5 },
        heroPool = { strength = { "axe", "sven" }, agility = { "sniper" },
            intelligence = { "lina" }, universal = { "marci" } },
        shopOffers = { { hero = "old" } }, shopOfferText = "old", broadcasts = 0,
        dataLoader = { GetLevel = function() return { time_limit = 120, reward = { gold = 100, xp_per_active_hero = 0 } } end },
        battleManager = { GetBattleTime = function() return 120 end,
            teamHeroes = { [2] = {} }, StopBattle = function() end },
        AddGold = function(self, value) self.gold = self.gold + value end,
        AwardStageXp = function() end,
        SpendGold = function() error("automatic refresh must not spend gold") end,
        BroadcastBattleState = function() end, BroadcastLevelInfo = function() end,
        BroadcastShopState = function(self) self.broadcasts = self.broadcasts + 1 end,
        SpawnLevelEnemies = function(self, level) equal(level, self.currentLevelId, "spawn level") end,
        RespawnPlayerRoster = function() end, SpawnBattleBarrier = function() end,
        RollRecruitLevel = function() return 1 end,
        RollQuality = function(self, stage) self.qualityStage = stage; return "common" end,
        PriceFor = function() return 100 end,
    }, CDota2RpgDemo)
    game:EndBattle(winner, winner == "radiant" and 2 or 3)
    game:EndBattle(winner, 2)
    equal(settlements, 1, "duplicate battle end rejected")
    equal(game.runLives.remaining, initialLives - (winner == "radiant" and 0 or 1), "one life per lost battle")
    equal(lastSettlement.lives_remaining, game.runLives.remaining, "authoritative lives in settlement")
    equal(lastSettlement.life_reward_gold, winner ~= "radiant" and initialLives == 4 and 2000 or 0, "gold threshold")
    equal(game.gold, 500 + (winner == "radiant" and 100 or lastSettlement.life_reward_gold), "reward credited once")
    equal(lastSettlement.life_reward_items, winner ~= "radiant" and initialLives == 2 and "item_aegis;item_cheese" or "", "last-life items")
    equal(game.shopOfferText, "old", "offers remain during settlement")
    game:OnShopRefresh(nil, {})
    equal(game.shopOfferText, "old", "manual refresh rejected during settlement")
    if final or (winner ~= "radiant" and initialLives == 1) then
        equal(scheduled, 0, "terminal run has no preparation")
        equal(game.runComplete, true, "final run complete")
        equal(game.runFailed, winner ~= "radiant", "distinguish win from exhausted lives")
        equal(game.phase, "result", "final phase")
        game.phase = "setup"; game.teamsSpawned = true; game.lineup = { "axe" }
        game:OnStartBattle(nil, {})
        equal(game.phase, "setup", "terminal run rejects another battle even if preparation is requested")
        return
    end
    equal(scheduled, 1, "single transition")
    local gold = game.gold
    callback()
    equal(game.phase, "setup", "preparation phase")
    equal(game.currentLevelId, winner == "radiant" and "ch02" or "ch01", "next or retry level")
    equal(game.qualityStage, winner == "radiant" and 2 or 1, "quality uses destination stage")
    equal(game.gold, gold, "automatic roll free")
    equal(game.refreshCount, winner == "radiant" and 0 or 3, "paid refresh count")
    equal(game.scrollPurchases.low, winner == "radiant" and 0 or 2, "scroll limits")
    equal(#game.shopOffers, 5, "all recruitment offers replaced")
    assert(game.shopOfferText ~= "old", "serialized offers refreshed")
    equal(game.broadcasts, 1, "single shop broadcast from automatic roll")
    local offers = game.shopOffers
    callback()
    game:BroadcastShopState()
    game:EndBattle(winner, 2)
    equal(game.shopOffers, offers, "callback replay and rebroadcast do not reroll")
    equal(settlements, 1, "setup rejects settlement")
    game.phase = "result"
    callback()
    equal(game.shopOffers, offers, "old callback cannot reroll a later settlement")
end
scenario("radiant", false)
scenario("dire", false)
scenario("timeout", false)
scenario("draw", false)
scenario("radiant", true)
scenario("dire", false, 4)
scenario("timeout", false, 2)
scenario("dire", false, 1)
scenario("timeout", false, 1)
print("shop-transition tests passed")
