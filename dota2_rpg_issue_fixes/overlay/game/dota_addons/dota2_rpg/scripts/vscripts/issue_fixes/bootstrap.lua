-- Optional compatibility bootstrap. The installer appends one call to this module
-- after all methods in addon_game_mode.lua have been defined.

local IssueFixes = require("issue_fixes.init")
local DefaultRules = require("issue_fixes.default_rules")
local Compat = require("issue_fixes.compat")

local Bootstrap = {}

local unpack_values = unpack or table.unpack
local function pack_values(...)
    return { n = select("#", ...), ... }
end

local function return_values(values)
    return unpack_values(values, 1, values.n)
end

local function wrap_first(class_table, names, wrapper_factory)
    for _, name in ipairs(names) do
        local original = class_table[name]
        if type(original) == "function" then
            class_table[name] = wrapper_factory(original, name)
            return name
        end
    end
    return nil
end

-- The current game mode keeps the authoritative playable units here.  Prefer it
-- to a radius scan: the scan includes benched heroes and the player wisp, which
-- must remain outside the compact arena boundary.
local function battle_team_units(game, team)
    local manager = game ~= nil and game.battleManager or nil
    local teams = manager ~= nil and manager.teamHeroes or nil
    local units = type(teams) == "table" and teams[team] or nil
    return type(units) == "table" and units or {}
end

local function current_battle_teams(game, compat)
    local good_team = rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
    local bad_team = rawget(_G, "DOTA_TEAM_BADGUYS") or 3
    local players = battle_team_units(game, good_team)
    local enemies = battle_team_units(game, bad_team)

    -- Retain compatibility fallbacks for other addon layouts, but never use a
    -- broad scan when the current game mode exposes an empty real battle list.
    if game.battleManager == nil or type(game.battleManager.teamHeroes) ~= "table" then
        players = compat:GetPlayerUnits()
        enemies = compat:GetEnemyUnits()
    end
    return players, enemies
end

local function all_battle_units(game, compat)
    if game.battleManager == nil or type(game.battleManager.teamHeroes) ~= "table" then
        return compat ~= nil and compat:GetAllUnits() or {}
    end

    local good_team = rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
    local bad_team = rawget(_G, "DOTA_TEAM_BADGUYS") or 3
    local all_units = {}
    for _, unit in ipairs(battle_team_units(game, good_team)) do
        all_units[#all_units + 1] = unit
    end
    for _, unit in ipairs(battle_team_units(game, bad_team)) do
        all_units[#all_units + 1] = unit
    end
    return all_units
end

-- On older addon_game_mode.lua revisions a changed stack in the native default
-- inventory was always split, even when no previous recipient owned it.  Mark an
-- unclaimed handle as directly routable so its original entity and charges move
-- together; stacks already claimed by another hero still take the split path.
local function install_unclaimed_purchase_stack_compat(class_table)
    local original = class_table.FindNewPurchasedItem
    if type(original) ~= "function" then return end

    class_table.FindNewPurchasedItem = function(self, ...)
        local found = original(self, ...)
        if type(found) == "table" and found.changed == true
            and found.item_id ~= nil then
            local claimed = self.nativePurchaseClaimedIds or {}
            if claimed[found.item_id] == nil then
                found.changed = false
            end
        end
        return found
    end
end

local function install_runtime(game)
    if game.issueFixes ~= nil then return end

    local compat = Compat.new(game)
    game.rpgIssueFixCompat = compat
    game.issueFixes = IssueFixes.new({
        game_mode_entity = GameRules:GetGameModeEntity(),
        get_phase = function() return compat:GetPhase() end,
        get_player_units = function() return compat:GetPlayerUnits() end,
        is_roster_hero = function(player_id, hero)
            return compat:IsRosterHero(player_id, hero)
        end,
        is_inventory_source = function(player_id, source)
            return compat:IsInventorySource(player_id, source)
        end,
        on_transfer_success = function()
            if game.SyncLiveEquipmentState ~= nil then game:SyncLiveEquipmentState(true) end
        end,
        bind_tactic_profile = function(unit, profile, entry)
            return compat:BindTacticProfile(unit, profile, entry)
        end,
        has_tactic_order = function(unit)
            return compat:HasTacticOrder(unit)
        end,
        order_gate = game.filters and game.filters.gate
            or game.orderFilter and game.orderFilter.gate
            or game.tacticBridge and game.tacticBridge.orderGate,
    })
    game.issueFixes:Install()

    local levels = compat:GetLevels()
    if type(levels) == "table" then
        local changed, reason = game.issueFixes:ApplyStageOneTwoFix(levels)
        if changed then
            print("[RPG][IssueFixes] level repair: " .. tostring(reason))
        end
        local valid, errors = game.issueFixes:ValidateLevelUniqueness(levels, 30)
        if not valid then
            for _, message in ipairs(errors) do
                print("[RPG][IssueFixes][LevelValidation] " .. message)
            end
        end
    end

    if ListenToGameEvent ~= nil then
        ListenToGameEvent("npc_spawned", function(event)
            compat:OnNpcSpawned(event or {})
        end, nil)
    end
end

function Bootstrap.Install(class_table)
    assert(type(class_table) == "table", "game mode class table is required")
    if class_table.__rpg_issue_fixes_bootstrapped then return end
    class_table.__rpg_issue_fixes_bootstrapped = true
    install_unclaimed_purchase_stack_compat(class_table)

    local original_init = assert(class_table.InitGameMode, "InitGameMode is required")
    class_table.InitGameMode = function(self, ...)
        local results = pack_values(original_init(self, ...))
        install_runtime(self)
        return return_values(results)
    end

    local stage_method = wrap_first(class_table, {
        "SpawnCurrentLevelEnemies",
        "SpawnLevelEnemies",
        "SpawnEnemiesForCurrentLevel",
        "SpawnEnemies",
        "CreateEnemies",
    }, function(original)
        return function(self, ...)
            local results = pack_values(original(self, ...))
            if self.issueFixes ~= nil and self.rpgIssueFixCompat ~= nil then
                self.issueFixes:RegisterCurrentStage(
                    self.rpgIssueFixCompat:GetStageEntries(),
                    self.rpgIssueFixCompat:GetEnemyUnits()
                )
            end
            return return_values(results)
        end
    end)

    local roster_method = wrap_first(class_table, {
        "RespawnPlayerRoster",
        "RespawnRoster",
        "SpawnPlayerRoster",
    }, function(original)
        return function(self, ...)
            local results = pack_values(original(self, ...))
            if self.issueFixes ~= nil and self.rpgIssueFixCompat ~= nil
                and self.rpgIssueFixCompat:GetPhase() == "PREPARE" then
                -- Register only fielded heroes, so the periodic boundary guard
                -- corrects retained placements without dragging the bench/wisp.
                local players = battle_team_units(
                    self,
                    rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
                )
                self.issueFixes.arena:StartPrepare(players)
            end
            return return_values(results)
        end
    end)

    local start_method = wrap_first(class_table, {
        "OnStartBattle",
        "StartBattle",
        "BeginBattle",
        "StartFight",
    }, function(original)
        return function(self, ...)
            local previous_phase = self.rpgIssueFixCompat and self.rpgIssueFixCompat:GetPhase()
            local results = pack_values(original(self, ...))
            if self.issueFixes ~= nil and self.rpgIssueFixCompat ~= nil
                and previous_phase ~= "FIGHT" and self.rpgIssueFixCompat:GetPhase() == "FIGHT" then
                local players, enemies = current_battle_teams(
                    self,
                    self.rpgIssueFixCompat
                )
                self.issueFixes:RegisterCurrentStage(
                    self.rpgIssueFixCompat:GetStageEntries(),
                    enemies
                )
                self.issueFixes:OnBattleStarted(players, enemies)
            end
            return return_values(results)
        end
    end)

    local end_method = wrap_first(class_table, {
        "OnBattleEnded",
        "EndBattle",
        "FinishBattle",
        "SettleBattle",
    }, function(original)
        return function(self, ...)
            local previous_phase = self.rpgIssueFixCompat and self.rpgIssueFixCompat:GetPhase()
            local results = pack_values(original(self, ...))
            if self.issueFixes ~= nil and previous_phase == "FIGHT"
                and self.rpgIssueFixCompat:GetPhase() ~= "FIGHT" then
                self.issueFixes:OnBattleEnded(
                    all_battle_units(self, self.rpgIssueFixCompat)
                )
            end
            return return_values(results)
        end
    end)

    wrap_first(class_table, {
        "BuildDefaultRules",
        "CreateDefaultRules",
        "GenerateDefaultRules",
        "GetDefaultRules",
    }, function(original)
        return function(self, ...)
            return DefaultRules.Normalize(original(self, ...))
        end
    end)

    print(string.format(
        "[RPG][IssueFixes] bootstrap installed (spawn=%s, roster=%s, start=%s, end=%s)",
        tostring(stage_method),
        tostring(roster_method),
        tostring(start_method),
        tostring(end_method)
    ))
end

return Bootstrap
