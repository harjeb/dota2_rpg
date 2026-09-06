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
        -- 小精灵不在战斗名单中，但它的原版物品订单也必须服从准备阶段锁。
        is_inventory_unit = options.is_inventory_unit or function() return false end,
        -- 原版购买/出售订单有时不带 units；仍必须进入阶段与归属校验。
        is_managed_order = options.is_managed_order or function() return false end,
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
    local contains_managed_unit = false
    for _, entity_index in pairs(units) do
        local unit = EntIndexToHScript(entity_index)
        if unit ~= nil and not unit:IsNull()
            and (self.is_battle_unit(unit) or self.is_inventory_unit(unit)) then
            contains_managed_unit = true
            break
        end
    end

    -- 不属于 RPG 的原版单位仍按 Dota 默认行为处理。原版购买/出售可能没有 units，
    -- 因此由 is_managed_order 显式接管，避免借空单位表绕过阶段锁。
    if not contains_managed_unit and not self.is_managed_order(filter_table) then
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
