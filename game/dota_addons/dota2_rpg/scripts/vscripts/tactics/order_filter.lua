local OrderGate = {}
OrderGate.__index = OrderGate

function OrderGate.new()
    return setmetatable({ depth = 0 }, OrderGate)
end

function OrderGate:IsInternal()
    return self.depth > 0
end

function OrderGate:Execute(order)
    self.depth = self.depth + 1
    local ok, err = pcall(function()
        ExecuteOrderFromTable(order)
    end)
    self.depth = self.depth - 1

    if not ok then
        print("[RPG][OrderGate] ExecuteOrderFromTable failed: " .. tostring(err))
        return false
    end
    return true
end

local OrderFilter = {}
OrderFilter.__index = OrderFilter

function OrderFilter.new(options)
    options = options or {}
    return setmetatable({
        gate = options.gate or OrderGate.new(),
        get_phase = assert(options.get_phase, "get_phase is required"),
        is_battle_unit = assert(options.is_battle_unit, "is_battle_unit is required"),
        validate_prepare_order = options.validate_prepare_order,
    }, OrderFilter)
end

function OrderFilter:Install(game_mode_entity)
    game_mode_entity:SetExecuteOrderFilter(Dynamic_Wrap(OrderFilter, "Filter"), self)
end

function OrderFilter:Filter(filter_table)
    if self.gate:IsInternal() then
        return true
    end

    local units = filter_table.units or {}
    local contains_battle_unit = false
    for _, entity_index in pairs(units) do
        local unit = EntIndexToHScript(entity_index)
        if unit ~= nil and not unit:IsNull() and self.is_battle_unit(unit) then
            contains_battle_unit = true
            break
        end
    end

    if not contains_battle_unit then
        return true
    end

    local phase = self.get_phase()
    if phase == "FIGHT" or phase == "COUNTDOWN" or phase == "SETTLE" then
        return false
    end

    if phase == "PREPARE" and self.validate_prepare_order ~= nil then
        return self.validate_prepare_order(filter_table) == true
    end

    return phase == "PREPARE"
end

return {
    OrderGate = OrderGate,
    OrderFilter = OrderFilter,
}
