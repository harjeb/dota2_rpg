-- Replacement for the current project order filter.
-- Fixes:
--   * skill training and native-shop/item orders in PREPARE;
--   * internal/enemy AI orders in FIGHT;
--   * arena placement validation for movement orders.

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
    self.depth = math.max(0, self.depth - 1)

    if not ok then
        print("[RPG][OrderGate] ExecuteOrderFromTable failed: " .. tostring(err))
        return false
    end
    return true
end

local function add_order(set, global_name)
    local value = rawget(_G, global_name)
    if value ~= nil then set[value] = true end
end

local PREPARE_UI_ORDERS = {}
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_TRAIN_ABILITY")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_PURCHASE_ITEM")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_SELL_ITEM")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_DISASSEMBLE_ITEM")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_MOVE_ITEM")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_GIVE_ITEM")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_DROP_ITEM")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_PICKUP_ITEM")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_SET_ITEM_COMBINE_LOCK")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_SET_ITEM_MARK_FOR_SELL")
add_order(PREPARE_UI_ORDERS, "DOTA_UNIT_ORDER_CONSUME_ITEM")

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
    game_mode_entity:SetExecuteOrderFilter(
        Dynamic_Wrap(OrderFilter, "Filter"),
        self
    )
end

function OrderFilter:ContainsBattleUnit(filter_table)
    for _, entity_index in pairs(filter_table.units or {}) do
        local unit = EntIndexToHScript(entity_index)
        if unit ~= nil
            and (unit.IsNull == nil or not unit:IsNull())
            and self.is_battle_unit(unit) then
            return true
        end
    end
    return false
end

function OrderFilter:Filter(filter_table)
    if self.gate:IsInternal() then
        return true
    end

    local phase = self.get_phase()
    local issuer = tonumber(filter_table.issuer_player_id_const) or -1
    local order_type = filter_table.order_type
    local contains_battle_unit = self:ContainsBattleUnit(filter_table)

    -- Engine AI and server-issued enemy orders commonly use issuer -1. Let them
    -- execute during FIGHT; player-issued orders still have a real PlayerID and
    -- remain blocked during automatic combat.
    if phase == "FIGHT" and issuer == -1 then
        return true
    end

    if phase == "COUNTDOWN" or phase == "FIGHT" or phase == "SETTLE" then
        -- Purchase/train orders can arrive without a unit list. They must still be
        -- blocked outside PREPARE instead of escaping through ContainsBattleUnit.
        if PREPARE_UI_ORDERS[order_type] == true then
            return false
        end
        if contains_battle_unit then
            return false
        end
        return true
    end

    if phase ~= "PREPARE" then
        return not contains_battle_unit
    end

    -- Keep engine AI dormant during preparation even when a preparation modifier
    -- was relaxed to permit player skill/shop orders. Scripted placement orders
    -- must use OrderGate:Execute and therefore bypass this branch.
    if issuer == -1 and contains_battle_unit then
        return false
    end

    -- These orders must bypass placement-only validation. Blocking them is why
    -- both field and bench heroes could not train abilities or use native shop.
    if PREPARE_UI_ORDERS[order_type] == true then
        return true
    end

    if not contains_battle_unit then
        return true
    end

    if self.validate_prepare_order ~= nil then
        return self.validate_prepare_order(filter_table) == true
    end

    return true
end

return {
    OrderGate = OrderGate,
    OrderFilter = OrderFilter,
    PREPARE_UI_ORDERS = PREPARE_UI_ORDERS,
}
