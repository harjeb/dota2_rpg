-- Enemy runtime driven by the current stage's actual entries and spawned units.
-- No hero names and no fixed "three enemy heroes" list are stored here.

local EnemyRuntime = {}
EnemyRuntime.__index = EnemyRuntime

local function is_valid(entity)
    if entity == nil then return false end
    if IsValidEntity ~= nil and not IsValidEntity(entity) then return false end
    if entity.IsNull ~= nil and entity:IsNull() then return false end
    return true
end

local function is_alive(unit)
    if not is_valid(unit) then return false end
    if unit.IsAlive == nil then return true end
    return unit:IsAlive()
end

local function safe_call(entity, method_name, default_value, ...)
    if not is_valid(entity) or entity[method_name] == nil then
        return default_value
    end
    local ok, result = pcall(entity[method_name], entity, ...)
    if not ok then return default_value end
    return result
end

local function unit_index(unit)
    return tonumber(safe_call(unit, "entindex", -1)) or -1
end

local function distance_2d(a, b)
    local pa = safe_call(a, "GetAbsOrigin", nil)
    local pb = safe_call(b, "GetAbsOrigin", nil)
    if pa == nil or pb == nil then return math.huge end

    local dx = (tonumber(pa.x) or 0) - (tonumber(pb.x) or 0)
    local dy = (tonumber(pa.y) or 0) - (tonumber(pb.y) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function nearest_alive_enemy(source, candidates)
    local best = nil
    local best_distance = math.huge
    local source_team = safe_call(source, "GetTeamNumber", -1)

    for _, candidate in ipairs(candidates or {}) do
        if is_alive(candidate)
            and safe_call(candidate, "GetTeamNumber", source_team) ~= source_team then
            local distance = distance_2d(source, candidate)
            if distance < best_distance then
                best = candidate
                best_distance = distance
            end
        end
    end

    return best
end

local function ordered_entries(value)
    if type(value) ~= "table" then return {} end
    local rows = {}
    for key, entry in pairs(value) do
        rows[#rows + 1] = {
            order = tonumber(key) or 1000000,
            key = tostring(key),
            value = entry,
        }
    end
    table.sort(rows, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)
    local result = {}
    for _, row in ipairs(rows) do result[#result + 1] = row.value end
    return result
end

local function expand_entries(entries)
    local result = {}
    for _, entry in ipairs(ordered_entries(entries)) do
        local count = 1
        if type(entry) == "table" then
            count = math.max(1, math.floor(tonumber(entry.count) or 1))
        end
        for _ = 1, count do result[#result + 1] = entry end
    end
    return result
end

local function entry_unit_name(entry)
    if type(entry) == "string" then return entry end
    if type(entry) ~= "table" then return nil end
    return entry.unit or entry.unit_name or entry.name or entry.npc or entry[1]
end

local function match_entry(entries, used, unit)
    local unit_name = tostring(safe_call(unit, "GetUnitName", ""))
    if unit_name ~= "" then
        for index, entry in ipairs(entries) do
            if not used[index]
                and tostring(entry_unit_name(entry) or "") == unit_name then
                used[index] = true
                return entry
            end
        end
        return {}
    end

    for index, entry in ipairs(entries) do
        if not used[index] then
            used[index] = true
            return entry
        end
    end
    return {}
end

local function default_execute(order)
    if ExecuteOrderFromTable == nil then return false end
    local ok = pcall(ExecuteOrderFromTable, order)
    return ok
end

function EnemyRuntime.new(options)
    options = options or {}
    return setmetatable({
        get_phase = options.get_phase or function() return "FIGHT" end,
        get_player_units = options.get_player_units,
        bind_tactic_profile = options.bind_tactic_profile,
        has_tactic_order = options.has_tactic_order,
        execute_order = options.execute_order or default_execute,
        game_mode_entity = options.game_mode_entity,
        acquisition_range = tonumber(options.acquisition_range) or 1800,
        think_interval = tonumber(options.think_interval) or 0.25,
        remove_prepare_modifiers = options.remove_prepare_modifiers or {
            "modifier_rpg_prepare_lock",
            "modifier_rpg_battle_preparation",
            "modifier_rpg_waiting",
            "modifier_rpg_prepare_bench",
            "modifier_invulnerable",
            "modifier_stunned",
            "modifier_rooted",
            "modifier_disarmed",
            "modifier_silence",
        },
        stage_entries = {},
        enemy_units = {},
        player_units = {},
        fight_center = nil,
        running = false,
    }, EnemyRuntime)
end

function EnemyRuntime:RegisterStage(stage_entries, spawned_enemy_units)
    self.stage_entries = expand_entries(stage_entries or {})
    self.enemy_units = spawned_enemy_units or {}

    local used_entries = {}
    for _, unit in ipairs(self.enemy_units) do
        if is_valid(unit) then
            local entry = match_entry(self.stage_entries, used_entries, unit)
            if type(entry) == "string" then entry = { unit = entry } end
            unit.rpg_stage_enemy_entry = entry
            unit.rpg_ai_profile = entry.ai_profile or entry.ai or "attack_nearest"

            if self.bind_tactic_profile ~= nil then
                local ok, err = pcall(
                    self.bind_tactic_profile,
                    unit,
                    unit.rpg_ai_profile,
                    entry
                )
                if not ok then
                    print("[RPG][EnemyRuntime] profile bind failed: " .. tostring(err))
                end
            end
        end
    end

    if #self.stage_entries ~= #self.enemy_units then
        print(string.format(
            "[RPG][EnemyRuntime] stage entries=%d, spawned units=%d; "
                .. "runtime will use every spawned current-stage unit.",
            #self.stage_entries,
            #self.enemy_units
        ))
    end
end

function EnemyRuntime:RemovePrepareRestrictions(unit)
    if not is_valid(unit) then return end

    if unit.RemoveModifierByName ~= nil then
        for _, modifier_name in ipairs(self.remove_prepare_modifiers) do
            pcall(unit.RemoveModifierByName, unit, modifier_name)
        end
    end

    safe_call(unit, "SetIdleAcquire", nil, true)
    safe_call(unit, "SetAcquisitionRange", nil, self.acquisition_range)
    safe_call(unit, "SetForceAttackTarget", nil, nil)
end

function EnemyRuntime:IssueAttack(unit, target)
    if not is_alive(unit) or not is_alive(target) then return false end

    return self.execute_order({
        UnitIndex = unit_index(unit),
        OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
        TargetIndex = unit_index(target),
        Queue = false,
    }) == true
end

function EnemyRuntime:IssueAttackMove(unit)
    if not is_alive(unit) or self.fight_center == nil then return false end

    return self.execute_order({
        UnitIndex = unit_index(unit),
        OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE,
        Position = self.fight_center,
        Queue = false,
    }) == true
end

function EnemyRuntime:CanFallbackOrder(unit)
    if not is_alive(unit) then return false end
    if safe_call(unit, "IsChanneling", false) then return false end
    if safe_call(unit, "IsInAbilityPhase", false) then return false end
    if safe_call(unit, "IsStunned", false) then return false end
    if safe_call(unit, "IsCommandRestricted", false) then return false end
    if safe_call(unit, "GetCurrentActiveAbility", nil) ~= nil then return false end
    if unit.IsIdle ~= nil and not safe_call(unit, "IsIdle", true) then return false end

    if self.has_tactic_order ~= nil then
        local ok, has_order = pcall(self.has_tactic_order, unit)
        if ok and has_order == true then return false end
    end

    return true
end

function EnemyRuntime:Think()
    if not self.running then return nil end
    if self.get_phase() ~= "FIGHT" then return self.think_interval end

    if self.get_player_units ~= nil then
        local ok, units = pcall(self.get_player_units)
        if ok and type(units) == "table" then
            self.player_units = units
        end
    end

    for _, unit in ipairs(self.enemy_units) do
        if self:CanFallbackOrder(unit) then
            local current_target = safe_call(unit, "GetAttackTarget", nil)
            if not is_alive(current_target) then
                local target = nearest_alive_enemy(unit, self.player_units)
                if target ~= nil then
                    self:IssueAttack(unit, target)
                else
                    self:IssueAttackMove(unit)
                end
            end
        end
    end

    return self.think_interval
end

function EnemyRuntime:Start(player_units, fight_center)
    if self.get_phase() ~= "FIGHT" then return false end
    self.player_units = player_units or {}
    self.fight_center = fight_center
    self.running = true

    for _, unit in ipairs(self.enemy_units) do
        self:RemovePrepareRestrictions(unit)
        local target = nearest_alive_enemy(unit, self.player_units)
        if target ~= nil then
            self:IssueAttack(unit, target)
        else
            self:IssueAttackMove(unit)
        end
    end

    if self.game_mode_entity ~= nil
        and self.game_mode_entity.SetContextThink ~= nil then
        self.game_mode_entity:SetContextThink(
            "RpgEnemyRuntimeThink",
            function() return self:Think() end,
            self.think_interval
        )
    end
end

function EnemyRuntime:Stop()
    self.running = false
    self.player_units = {}
    self.enemy_units = {}
    self.stage_entries = {}
end

return EnemyRuntime
