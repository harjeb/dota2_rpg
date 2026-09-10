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
    local candidates = {}
    local function append(value)
        if value ~= nil then candidates[#candidates + 1] = value end
    end
    append(game.phase)
    append(game.battlePhase)
    append(game.battle_state)
    append(game.battleState)
    append(game.state and game.state.phase)
    append(game.runState and game.runState.phase)

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
            if upper == "PREPARE" or upper == "PREPARATION" or upper == "SETUP" then return "PREPARE" end
            if upper == "COUNTDOWN" then return "COUNTDOWN" end
            if upper == "FIGHT" or upper == "BATTLE" then return "FIGHT" end
            if upper == "SETTLE" or upper == "SETTLEMENT" or upper == "RESULT" then return "SETTLE" end
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
    local teams = self.game.battleManager and self.game.battleManager.teamHeroes
    if type(teams) == "table" then
        return teams[rawget(_G, "DOTA_TEAM_GOODGUYS") or 2] or {}
    end
    local known = {}
    local seen = {}
    collect_fields(self.game, {
        "playerUnits",
        "player_units",
        "currentPlayerUnits",
        "current_player_units",
        "lineupUnits",
        "lineup_units",
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
    local teams = self.game.battleManager and self.game.battleManager.teamHeroes
    if type(teams) == "table" then
        return teams[rawget(_G, "DOTA_TEAM_BADGUYS") or 3] or {}
    end
    -- An explicitly empty current-stage list is authoritative, not a scan request.
    for _, field in ipairs({ "currentEnemyUnits", "current_enemy_units", "enemyUnits",
        "enemy_units", "spawnedEnemies", "spawned_enemies" }) do
        if type(self.game[field]) == "table" then return self.game[field] end
    end
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
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then return false end
    if self.game.playerId ~= nil and player_id ~= tonumber(self.game.playerId) then return false end
    if self.game.IsLineupUnit ~= nil and self.game.IsBenchUnit ~= nil then
        return self.game:IsLineupUnit(hero) or self.game:IsBenchUnit(hero)
    end
    return tonumber(safe_call(hero, "GetPlayerOwnerID", -1)) == player_id
end

function Compat:IsInventorySource(player_id, source)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then return false end
    if self.game.playerId ~= nil and player_id ~= tonumber(self.game.playerId) then return false end
    if self.game.IsEquipmentCarrier ~= nil then return self.game:IsEquipmentCarrier(source) end
    return tonumber(safe_call(source, "GetPlayerOwnerID", -1)) == player_id
end

function Compat:GetStageEntries()
    local game = self.game
    if game.dataLoader ~= nil and game.dataLoader.GetLevel ~= nil then
        local level = game.dataLoader:GetLevel(game.currentLevelId)
        return type(level) == "table" and (level.enemies or {}) or {}
    end
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
    if self.game.dataLoader ~= nil and self.game.dataLoader.GetAllLevels ~= nil then
        return self.game.dataLoader:GetAllLevels()
    end
    return self.game.levels or self.game.levelData or self.game.level_data
end

function Compat:HasTacticOrder(unit)
    local engine = self.game.tacticBridge and self.game.tacticBridge.tacticEngine
    local index = safe_call(unit, "entindex", -1)
    if engine and type(engine.HasActiveOrder) == "function" then
        local ok, active = pcall(engine.HasActiveOrder, engine, unit)
        if ok then return active == true end
    end
    local state = engine and engine.states and engine.states[index]
    if state ~= nil and (state.unit == nil or state.unit == unit) then
        local now = GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
        if state.chase ~= nil or (state.wait_until or 0) > now then return true end
    end
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

    for _, object in pairs(candidates) do
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
    local manager = self.game.battleManager
    if manager ~= nil and manager.teamRules ~= nil and unit.enemyRuleIndex ~= nil
        and self.game.BuildEnemyRules ~= nil then
        local team = rawget(_G, "DOTA_TEAM_BADGUYS") or 3
        manager.teamRules[team][unit.enemyRuleIndex] = self.game:BuildEnemyRules(profile)
        return true
    end
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

    for _, object in pairs(candidates) do
        if object ~= nil then
            for _, method_name in ipairs(methods) do
                if type(object[method_name]) == "function" then
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

    local unit_name = tostring(safe_call(unit, "GetUnitName", "") or "")
    if unit_name == "npc_dota_hero_wisp" then
        -- The forced hero is only the hidden inventory/control carrier; do not
        -- let a respawn or camera transition expose it in the arena.
        if unit.AddNoDraw ~= nil then
            pcall(unit.AddNoDraw, unit)
        end
        return
    end

    local player_id = tonumber(safe_call(unit, "GetPlayerOwnerID", -1)) or -1
    local good_team = rawget(_G, "DOTA_TEAM_GOODGUYS") or 2
    if player_id >= 0 and safe_call(unit, "GetTeamNumber", -1) == good_team then
        RosterAccess.AssignToPlayer(unit, player_id)
    end
end

return Compat
