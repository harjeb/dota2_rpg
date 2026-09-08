-- Compact rectangular arena: two preparation zones joined side by side.
-- Hammer provides the outer blockers; native temporary trees close the middle
-- divider without baking a permanent obstruction into terrain/grid navigation.
-- The default 2400×900 arena is two 1200×900 zones, each slightly roomier
-- than the original 1040×760 bench/preparation enclosure.

local ArenaController = {}
ArenaController.__index = ArenaController

local function is_valid(entity)
    if entity == nil then return false end
    if IsValidEntity ~= nil and not IsValidEntity(entity) then return false end
    if entity.IsNull ~= nil and entity:IsNull() then return false end
    return true
end

local function safe_call(entity, method_name, default_value, ...)
    if not is_valid(entity) or entity[method_name] == nil then
        return default_value
    end
    local ok, value = pcall(entity[method_name], entity, ...)
    if not ok then return default_value end
    return value
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function entity_position(name)
    if Entities == nil then return nil end
    local entity = Entities:FindByName(nil, name)
    if not is_valid(entity) then return nil end
    return safe_call(entity, "GetAbsOrigin", nil)
end

local function make_vector(x, y, z)
    if Vector ~= nil then return Vector(x, y, z) end
    return { x = x, y = y, z = z }
end

local MOVEMENT_ORDERS = {}
local function register_order(global_name)
    local value = rawget(_G, global_name)
    if value ~= nil then MOVEMENT_ORDERS[value] = true end
end
register_order("DOTA_UNIT_ORDER_MOVE_TO_POSITION")
register_order("DOTA_UNIT_ORDER_ATTACK_MOVE")
register_order("DOTA_UNIT_ORDER_MOVE_TO_DIRECTION")
register_order("DOTA_UNIT_ORDER_PATROL")
register_order("DOTA_UNIT_ORDER_MOVE_RELATIVE")

function ArenaController.new(options)
    options = options or {}

    -- `square_size` is retained for installed packages that explicitly selected
    -- the old two-square geometry.  New callers can set the two axes separately.
    local legacy_square_size = tonumber(options.square_size)
    local half_width = tonumber(options.half_width)
        or legacy_square_size
        or 1200
    local half_height = tonumber(options.half_height)
        or (legacy_square_size and legacy_square_size * 0.5)
        or 675

    return setmetatable({
        min_marker = options.min_marker or "rpg_arena_min",
        max_marker = options.max_marker or "rpg_arena_max",
        center_marker = options.center_marker or "rpg_arena_center",
        gate_nav_name = options.gate_nav_name or "rpg_mid_gate_nav",
        gate_tree_spacing = math.max(32, math.min(96, tonumber(options.gate_tree_spacing) or 96)),
        gate_trees = {},
        middle_gate_open = false,
        half_width = half_width,
        half_height = half_height,
        correction_interval = tonumber(options.correction_interval) or 0.20,
        game_mode_entity = options.game_mode_entity,
        phase = "PREPARE",
        min = nil,
        max = nil,
        center = nil,
        units = {},
        think_installed = false,
    }, ArenaController)
end

function ArenaController:LoadBounds()
    local min_position = entity_position(self.min_marker)
    local max_position = entity_position(self.max_marker)
    local center = entity_position(self.center_marker)

    if min_position ~= nil and max_position ~= nil then
        self.min = make_vector(
            math.min(min_position.x, max_position.x),
            math.min(min_position.y, max_position.y),
            math.min(min_position.z or 0, max_position.z or 0)
        )
        self.max = make_vector(
            math.max(min_position.x, max_position.x),
            math.max(min_position.y, max_position.y),
            math.max(min_position.z or 0, max_position.z or 0)
        )
        self.center = make_vector(
            (self.min.x + self.max.x) * 0.5,
            (self.min.y + self.max.y) * 0.5,
            center and center.z or self.min.z
        )
        return true
    end

    center = center or make_vector(0, 0, 0)
    self.min = make_vector(
        center.x - self.half_width,
        center.y - self.half_height,
        center.z
    )
    self.max = make_vector(
        center.x + self.half_width,
        center.y + self.half_height,
        center.z
    )
    self.center = center

    print(string.format(
        "[RPG][Arena] rpg_arena_min/max markers missing; using fallback %dx%d bounds.",
        self.half_width * 2,
        self.half_height * 2
    ))
    return false
end

function ArenaController:GetCenter()
    if self.center == nil then self:LoadBounds() end
    return self.center
end

function ArenaController:RegisterUnits(units)
    self.units = units or {}
end

function ArenaController:BoundsForUnit(unit)
    if self.min == nil or self.max == nil then self:LoadBounds() end

    local minimum_x = self.min.x
    local maximum_x = self.max.x

    -- During preparation, Radiant/player units stay in the left preparation
    -- zone and Dire enemies stay in the right one. During fight both use the
    -- whole rectangle.
    if self.phase == "PREPARE" and is_valid(unit) then
        local team = safe_call(unit, "GetTeamNumber", -1)
        if team == rawget(_G, "DOTA_TEAM_GOODGUYS") then
            maximum_x = self.center.x - 24
        elseif team == rawget(_G, "DOTA_TEAM_BADGUYS") then
            minimum_x = self.center.x + 24
        end
    end

    return {
        min_x = minimum_x,
        max_x = maximum_x,
        min_y = self.min.y,
        max_y = self.max.y,
    }
end

function ArenaController:Contains(position, unit, margin)
    if position == nil then return false end
    margin = tonumber(margin) or 0
    local bounds = self:BoundsForUnit(unit)
    return position.x >= bounds.min_x + margin
        and position.x <= bounds.max_x - margin
        and position.y >= bounds.min_y + margin
        and position.y <= bounds.max_y - margin
end

function ArenaController:ClampPosition(position, unit, margin)
    margin = tonumber(margin) or 48
    local bounds = self:BoundsForUnit(unit)
    return make_vector(
        clamp(position.x, bounds.min_x + margin, bounds.max_x - margin),
        clamp(position.y, bounds.min_y + margin, bounds.max_y - margin),
        position.z or self.center.z
    )
end

function ArenaController:ValidateOrder(filter_table)
    if self.center == nil then self:LoadBounds() end
    local order_type = filter_table.order_type
    if MOVEMENT_ORDERS[order_type] ~= true then return true end

    local x = tonumber(filter_table.position_x)
    local y = tonumber(filter_table.position_y)
    local z = tonumber(filter_table.position_z) or self.center.z
    if x == nil or y == nil then return true end

    local first_unit = nil
    for _, entity_index in pairs(filter_table.units or {}) do
        local unit = EntIndexToHScript(entity_index)
        if is_valid(unit) then
            first_unit = unit
            break
        end
    end

    local wanted = make_vector(x, y, z)
    local corrected = self:ClampPosition(wanted, first_unit, 48)
    filter_table.position_x = corrected.x
    filter_table.position_y = corrected.y
    filter_table.position_z = corrected.z
    return true
end

function ArenaController:EnsureMiddleTrees()
    if self.middle_gate_open or CreateTempTree == nil then return end
    if self.center == nil then self:LoadBounds() end
    local length = math.max(0, self.max.y - self.min.y - 48)
    local intervals = math.max(1, math.ceil(length / self.gate_tree_spacing))
    for index = 0, intervals do
        local tree = self.gate_trees[index + 1]
        if not is_valid(tree) or not safe_call(tree, "IsStanding", true) then
            if is_valid(tree) and UTIL_Remove ~= nil then UTIL_Remove(tree) end
            -- The authored arena is flat. Ground queries at the divider can
            -- return the top of an older compiled clip brush instead of terrain.
            local position = make_vector(self.center.x, self.min.y + 24 + length * index / intervals, self.center.z)
            self.gate_trees[index + 1] = CreateTempTree(position, 86400)
        end
    end
end

function ArenaController:DisableLegacyMiddleBrush()
    -- Older maps may still contain this entity. Never re-enable it: only a
    -- rebuilt map can remove the baked navigation/height obstruction.
    if DoEntFire ~= nil then
        DoEntFire(self.gate_nav_name, "Disable", "", 0, nil, nil)
        DoEntFire(self.gate_nav_name, "SetNonsolid", "", 0, nil, nil)
    end
end

function ArenaController:OpenMiddleGate()
    self.middle_gate_open = true
    self:DisableLegacyMiddleBrush()
    -- Cut only our temporary divider trees, including both ends of the row.
    -- Cutting updates native tree navigation; removing the handle avoids stumps.
    for _, tree in pairs(self.gate_trees) do
        if is_valid(tree) then
            safe_call(tree, "CutDown", nil, rawget(_G, "DOTA_TEAM_GOODGUYS") or 2)
            if UTIL_Remove ~= nil then UTIL_Remove(tree)
            else safe_call(tree, "RemoveSelf", nil) end
        end
    end
    self.gate_trees = {}
end

function ArenaController:CloseMiddleGate()
    self.middle_gate_open = false
    self:DisableLegacyMiddleBrush()
    self:EnsureMiddleTrees()
end

function ArenaController:StartPrepare(units)
    self.phase = "PREPARE"
    self:RegisterUnits(units)
    self:CloseMiddleGate()
end

function ArenaController:StartFight(units)
    self.phase = "FIGHT"
    self:RegisterUnits(units)
    self:OpenMiddleGate()
end

function ArenaController:EnforceBounds()
    if self.phase == "PREPARE" then self:EnsureMiddleTrees() end
    for _, unit in ipairs(self.units) do
        if is_valid(unit) and safe_call(unit, "IsAlive", true) then
            local position = safe_call(unit, "GetAbsOrigin", nil)
            if position ~= nil and not self:Contains(position, unit, -32) then
                local corrected = self:ClampPosition(position, unit, 64)
                if FindClearSpaceForUnit ~= nil then
                    FindClearSpaceForUnit(unit, corrected, true)
                elseif unit.SetAbsOrigin ~= nil then
                    unit:SetAbsOrigin(corrected)
                end
                safe_call(unit, "Stop", nil)
            end
        end
    end
    return self.correction_interval
end

function ArenaController:InstallThink()
    if self.think_installed then return end
    if self.game_mode_entity == nil
        or self.game_mode_entity.SetContextThink == nil then
        return
    end

    self.think_installed = true
    self.game_mode_entity:SetContextThink(
        "RpgArenaBoundsThink",
        function() return self:EnforceBounds() end,
        self.correction_interval
    )
end

return ArenaController
