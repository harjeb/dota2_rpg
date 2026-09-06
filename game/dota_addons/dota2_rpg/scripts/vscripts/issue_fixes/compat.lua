-- Compatibility adapter for the current monolithic game mode. It intentionally
-- reads several known field names but never writes progression/economy data.

local RosterAccess = require("issue_fixes.roster_access")

local Compat = {}
Compat.__index = Compat

local function is_valid(entity)
    if entity == nil then return false end
    if IsValidEntity ~= nil and not IsValidEntity(entity) then return false end
    if entity.IsNull ~= nil and entity:IsNull() then return false end
    return true
end

local function safe_call(entity, name, default_value, ...)
    if not is_valid(entity) or entity[name] == nil then return default_value end
    local ok, value = pcall(entity[name], entity, ...)
    if not ok then return default_value end
    return value
end

local function add_unique(result, seen, unit)
    if not is_valid(unit) then return end
    if safe_call(unit, "IsCourier", false) then return end

    local index = tonumber(safe_call(unit, "entindex", -1)) or -1
    if index < 0 or seen[index] then return end
    seen[index] = true
    result[#result + 1] = unit
end

local function collect_table(value, result, seen)
    if type(value) ~= "table" then return end
    for _, candidate in pairs(value) do
        if is_valid(candidate) then
            add_unique(result, seen, candidate)
        elseif type(candidate) == "table" then
            local unit = candidate.unit_handle
                or candidate.handle
                or candidate.entity
                or candidate.hero
            add_unique(result, seen, unit)
        end
    end
end

local function collect_fields(root, fields, result, seen)
    if type(root) ~= "table" then return end
    for _, field in ipairs(fields or {}) do
        collect_table(root[field], result, seen)
    end
end

local function target_flags()
    local result = 0
    result = result + (rawget(_G, "DOTA_UNIT_TARGET_FLAG_INVULNERABLE") or 0)
    result = result + (rawget(_G, "DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD") or 0)
    return result
end

function Compat.new(game)
    return setmetatable({ game = game }, Compat)
end

function Compat:GetPhase()
    local game = self.game
    local candidates = {
        game.phase,
        game.battlePhase,
        game.battle_state,
        game.battleState,
        game.state and game.state.phase,
        game.runState and game.runState.phase,
    }

    if game.battleManager ~= nil then
        if game.battleManager.GetPhase ~= nil then
            local ok, value = pcall(game.battleManager.GetPhase, game.battleManager)
            if ok then candidates[#candidates + 1] = value end
        end
        candidates[#candidates + 1] = game.battleManager.phase
        candidates[#candidates + 1] = game.battleManager.state
    end

    for _, value in ipairs(candidates) do
        if type(value) == "string" then
            local upper = string.upper(value)
            if upper == "PREPARE" or upper == "PREPARATION" then return "PREPARE" end
            if upper == "COUNTDOWN" then return "COUNTDOWN" end
            if upper == "FIGHT" or upper == "BATTLE" then return "FIGHT" end
            if upper == "SETTLE" or upper == "SETTLEMENT" then return "SETTLE" end
        end
    end

    if game.battleStarted == true or game.inBattle == true then return "FIGHT" end
    return "PREPARE"
end

function Compat:CollectKnownUnits()
    local game = self.game
    local result = {}
    local seen = {}
    local fields = {
        "battleUnits",
        "battle_units",
        "playerUnits",
        "player_units",
        "activeUnits",
        "active_units",
        "lineupUnits",
        "lineup_units",
        "enemyUnits",
        "enemy_units",
        "currentEnemyUnits",
        "current_enemy_units",
        "spawnedEnemies",
        "spawned_enemies",
        "benchUnits",
        "bench_units",
        "heroUnits",
        "hero_units",
    }

    for _, field in ipairs(fields) do
        collect_table(game[field], result, seen)
    end

    if game.state ~= nil then
        collect_table(game.state.battle_units, result, seen)
        collect_table(game.state.roster, result, seen)
    end

    return result, seen
end

function Compat:ScanArenaUnits(existing, seen)
    existing = existing or {}
    seen = seen or {}

    if FindUnitsInRadius == nil or self.game.issueFixes == nil then
        return existing
    end

    local center = self.game.issueFixes.arena:GetCenter()
    local team = rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
    local team_filter = rawget(_G, "DOTA_UNIT_TARGET_TEAM_BOTH")
    local hero_type = rawget(_G, "DOTA_UNIT_TARGET_HERO") or 0
    local basic_type = rawget(_G, "DOTA_UNIT_TARGET_BASIC") or 0
    local find_order = rawget(_G, "FIND_ANY_ORDER") or 0

    if team_filter == nil then return existing end

    local ok, units = pcall(
        FindUnitsInRadius,
        team,
        center,
        nil,
        5000,
        team_filter,
        hero_type + basic_type,
        target_flags(),
        find_order,
        false
    )
    if ok then
        for _, unit in ipairs(units or {}) do
            add_unique(existing, seen, unit)
        end
    end

    return existing
end

function Compat:GetAllUnits()
    local units, seen = self:CollectKnownUnits()
    return self:ScanArenaUnits(units, seen)
end

function Compat:GetPlayerUnits()
    local known = {}
    local seen = {}
    collect_fields(self.game, {
        "playerUnits",
        "player_units",
        "currentPlayerUnits",
        "current_player_units",
        "lineupUnits",
        "lineup_units",
        "benchUnits",
        "bench_units",
    }, known, seen)
    if self.game.state ~= nil then
        collect_fields(self.game.state, {
            "player_units",
            "lineup_units",
            "bench_units",
            "roster",
        }, known, seen)
    end

    local candidates = known
    if #candidates == 0 then candidates = self:GetAllUnits() end

    local result = {}
    local good_team = rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
    for _, unit in ipairs(candidates) do
        if safe_call(unit, "GetTeamNumber", -1) == good_team then
            result[#result + 1] = unit
        end
    end
    return result
end

function Compat:GetEnemyUnits()
    local known = {}
    local seen = {}
    collect_fields(self.game, {
        "enemyUnits",
        "enemy_units",
        "currentEnemyUnits",
        "current_enemy_units",
        "spawnedEnemies",
        "spawned_enemies",
    }, known, seen)
    if self.game.state ~= nil then
        collect_fields(self.game.state, {
            "enemy_units",
            "current_enemy_units",
            "spawned_enemies",
        }, known, seen)
    end

    -- Prefer the current stage's explicit runtime list. Arena scanning is only a
    -- fallback, because a broad scan may include summons, critters or map helpers.
    local candidates = known
    if #candidates == 0 then candidates = self:GetAllUnits() end

    local result = {}
    local good_team = rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
    for _, unit in ipairs(candidates) do
        if safe_call(unit, "GetTeamNumber", good_team) ~= good_team then
            result[#result + 1] = unit
        end
    end
    return result
end

function Compat:IsRosterHero(player_id, hero)
    if not is_valid(hero) then return false end
    local owner_id = tonumber(safe_call(hero, "GetPlayerOwnerID", -1)) or -1
    if owner_id == tonumber(player_id) then return true end

    for _, candidate in ipairs(self:GetPlayerUnits()) do
        if candidate == hero then return true end
    end
    return false
end

function Compat:GetStageEntries()
    local game = self.game
    local stage_data = game.currentLevelData
        or game.current_level_data
        or game.currentStageData
        or game.current_stage_data
        or game.currentLevel

    if type(stage_data) == "table" then
        return stage_data.enemies
            or stage_data.enemy_units
            or stage_data.units
            or {}
    end

    local stage = tonumber(game.currentStage or game.current_stage or game.stage)
    local levels = game.levels or game.levelData or game.level_data
    if stage ~= nil and type(levels) == "table" then
        local level = levels[stage]
            or levels[tostring(stage)]
            or levels["stage_" .. tostring(stage)]
            or levels["ch" .. tostring(stage)]
        if type(level) == "table" then
            return level.enemies or level.enemy_units or level.units or {}
        end
    end
    return {}
end

function Compat:GetLevels()
    return self.game.levels or self.game.levelData or self.game.level_data
end

function Compat:HasTacticOrder(unit)
    local candidates = {
        self.game.tacticBridge,
        self.game.tactics,
        self.game.tacticEngine,
        self.game.enemyAI,
    }
    local methods = {
        "HasPendingOrder",
        "HasActiveOrder",
        "HasLockedAction",
        "IsUnitBusy",
    }

    for _, object in ipairs(candidates) do
        if object ~= nil then
            for _, method_name in ipairs(methods) do
                if type(object[method_name]) == "function" then
                    local ok, value = pcall(object[method_name], object, unit)
                    if ok and value == true then return true end
                end
            end
        end
    end
    return false
end

function Compat:BindTacticProfile(unit, profile, entry)
    local candidates = {
        self.game.tacticBridge,
        self.game.tactics,
        self.game.tacticEngine,
        self.game.enemyAI,
    }
    local methods = {
        "RegisterEnemyUnit",
        "RegisterUnit",
        "SetUnitProfile",
        "BindProfile",
    }

    for _, object in ipairs(candidates) do
        if object ~= nil then
            for _, method_name in ipairs(methods) do
                if object[method_name] ~= nil then
                    local ok = pcall(
                        object[method_name],
                        object,
                        unit,
                        profile,
                        entry
                    )
                    if ok then return true end
                end
            end
        end
    end
    return false
end

function Compat:OnNpcSpawned(event)
    if self:GetPhase() ~= "PREPARE" then return end
    local unit = EntIndexToHScript(tonumber(event.entindex) or -1)
    if not is_valid(unit) or not safe_call(unit, "IsHero", false) then return end

    local player_id = tonumber(safe_call(unit, "GetPlayerOwnerID", -1)) or -1
    local good_team = rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
    if player_id >= 0 and safe_call(unit, "GetTeamNumber", -1) == good_team then
        RosterAccess.AssignToPlayer(unit, player_id)
    end
end

return Compat
