local ItemCatalog = require("data/items")

local ShopService = {}
ShopService.__index = ShopService

local MAX_WAREHOUSE_ITEMS = 60
local ACTIVE_INVENTORY_SLOTS = 6

local function valid_entity(entity)
    return entity ~= nil and (entity.IsNull == nil or not entity:IsNull())
end

local function copy_array(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

local function find_entry(entries, uid)
    for index, entry in ipairs(entries or {}) do
        if tostring(entry.uid) == tostring(uid) then
            return index, entry
        end
    end
    return nil, nil
end

function ShopService.new(options)
    options = options or {}
    return setmetatable({
        get_phase = assert(options.get_phase, "get_phase is required"),
        is_roster_hero = assert(options.is_roster_hero, "is_roster_hero is required"),
        state = assert(options.state, "current-run state is required"),
        catalog = options.catalog or ItemCatalog,
        next_uid = 1,
    }, ShopService)
end

function ShopService:InitializePlayer(player_id, initial_gold)
    self.state.gold[player_id] = tonumber(initial_gold or 1000)
    self.state.warehouse[player_id] = self.state.warehouse[player_id] or {}
    self.state.equipped_items = self.state.equipped_items or {}
    self:Sync(player_id)
end

function ShopService:GetGold(player_id)
    return tonumber(self.state.gold[player_id] or 0)
end

function ShopService:AddGold(player_id, amount, _reason)
    self.state.gold[player_id] = math.max(0, self:GetGold(player_id) + math.floor(tonumber(amount or 0)))
    self:Sync(player_id)
end

function ShopService:GetWarehouse(player_id)
    self.state.warehouse[player_id] = self.state.warehouse[player_id] or {}
    return self.state.warehouse[player_id]
end

function ShopService:GetCurrentCost(item_name)
    local definition = self.catalog[item_name]
    if definition == nil or definition.enabled ~= true then
        return nil, "item_not_whitelisted"
    end

    local cost = GetItemCost(item_name)
    if cost == nil or cost <= 0 then
        return nil, "invalid_item_cost"
    end
    return math.floor(cost), nil
end

function ShopService:CanMutateInventory()
    return self.get_phase() == "PREPARE"
end

function ShopService:NewUID()
    local uid = tostring(self.next_uid)
    self.next_uid = self.next_uid + 1
    return uid
end

function ShopService:Purchase(player_id, item_name)
    if not self:CanMutateInventory() then
        return false, "wrong_phase"
    end

    item_name = tostring(item_name or "")
    local cost, reason = self:GetCurrentCost(item_name)
    if cost == nil then
        return false, reason
    end

    local warehouse = self:GetWarehouse(player_id)
    if #warehouse >= MAX_WAREHOUSE_ITEMS then
        return false, "warehouse_full"
    end
    if self:GetGold(player_id) < cost then
        return false, "not_enough_gold"
    end

    self.state.gold[player_id] = self:GetGold(player_id) - cost
    table.insert(warehouse, {
        uid = self:NewUID(),
        item_name = item_name,
        purchase_cost = cost,
        source = "shop",
    })
    self:Sync(player_id)
    return true, nil
end

function ShopService:AddDrop(player_id, item_name, source)
    local cost, reason = self:GetCurrentCost(item_name)
    if cost == nil then
        return false, reason
    end
    local warehouse = self:GetWarehouse(player_id)
    if #warehouse >= MAX_WAREHOUSE_ITEMS then
        return false, "warehouse_full"
    end
    table.insert(warehouse, {
        uid = self:NewUID(),
        item_name = item_name,
        purchase_cost = cost,
        source = source or "loot",
    })
    self:Sync(player_id)
    return true, nil
end

local function has_active_inventory_slot(hero)
    for slot = 0, ACTIVE_INVENTORY_SLOTS - 1 do
        if not valid_entity(hero:GetItemInSlot(slot)) then
            return true
        end
    end
    return false
end

function ShopService:Equip(player_id, warehouse_uid, hero_index)
    if not self:CanMutateInventory() then
        return false, "wrong_phase"
    end

    local hero = EntIndexToHScript(tonumber(hero_index or -1))
    if not valid_entity(hero) or not self.is_roster_hero(player_id, hero) then
        return false, "invalid_hero"
    end
    if not has_active_inventory_slot(hero) then
        return false, "hero_inventory_full"
    end

    local warehouse = self:GetWarehouse(player_id)
    local index, entry = find_entry(warehouse, warehouse_uid)
    if entry == nil then
        return false, "warehouse_item_missing"
    end

    local item = CreateItem(entry.item_name, hero, hero)
    if not valid_entity(item) then
        return false, "create_item_failed"
    end

    hero:AddItem(item)
    table.remove(warehouse, index)
    self.state.equipped_items[item:entindex()] = {
        uid = entry.uid,
        owner_player_id = player_id,
        item_name = entry.item_name,
        purchase_cost = entry.purchase_cost,
        source = entry.source,
        hero_index = hero:entindex(),
    }
    self:Sync(player_id)
    return true, nil
end

function ShopService:Unequip(player_id, item_index)
    if not self:CanMutateInventory() then
        return false, "wrong_phase"
    end

    item_index = tonumber(item_index or -1)
    local record = self.state.equipped_items[item_index]
    if record == nil or record.owner_player_id ~= player_id then
        return false, "equipped_item_missing"
    end

    local warehouse = self:GetWarehouse(player_id)
    if #warehouse >= MAX_WAREHOUSE_ITEMS then
        return false, "warehouse_full"
    end

    local hero = EntIndexToHScript(record.hero_index)
    local item = EntIndexToHScript(item_index)
    if not valid_entity(hero) or not valid_entity(item) then
        return false, "item_entity_invalid"
    end

    hero:RemoveItem(item)
    UTIL_Remove(item)
    self.state.equipped_items[item_index] = nil
    table.insert(warehouse, {
        uid = record.uid,
        item_name = record.item_name,
        purchase_cost = record.purchase_cost,
        source = record.source,
    })
    self:Sync(player_id)
    return true, nil
end

function ShopService:Sell(player_id, warehouse_uid)
    if not self:CanMutateInventory() then
        return false, "wrong_phase"
    end

    local warehouse = self:GetWarehouse(player_id)
    local index, entry = find_entry(warehouse, warehouse_uid)
    if entry == nil then
        return false, "warehouse_item_missing"
    end

    local refund = math.floor(tonumber(entry.purchase_cost or 0) * 0.5)
    table.remove(warehouse, index)
    self.state.gold[player_id] = self:GetGold(player_id) + refund
    self:Sync(player_id)
    return true, nil, refund
end

function ShopService:Sync(player_id)
    local compact_items = {}
    for index, entry in ipairs(self:GetWarehouse(player_id)) do
        compact_items[index] = table.concat({
            tostring(entry.uid),
            entry.item_name,
            tostring(entry.purchase_cost),
            entry.source,
        }, "|")
    end

    CustomNetTables:SetTableValue("rpg_shop", tostring(player_id), {
        gold = self:GetGold(player_id),
        warehouse_count = #compact_items,
        warehouse = table.concat(compact_items, ";"),
    })
end

function ShopService:SendResult(player_id, request_id, ok, reason, extra)
    local player = PlayerResource:GetPlayer(player_id)
    if player == nil then
        return
    end
    CustomGameEventManager:Send_ServerToPlayer(player, "rpg_shop_result", {
        request_id = tostring(request_id or ""),
        ok = ok and 1 or 0,
        reason = reason or "",
        extra = extra or 0,
    })
end

function ShopService:InstallEventListeners()
    CustomGameEventManager:RegisterListener("rpg_shop_buy", function(_, args)
        local player_id = tonumber(args.PlayerID)
        local ok, reason = self:Purchase(player_id, args.item_name)
        self:SendResult(player_id, args.request_id, ok, reason)
    end)

    CustomGameEventManager:RegisterListener("rpg_shop_equip", function(_, args)
        local player_id = tonumber(args.PlayerID)
        local ok, reason = self:Equip(player_id, args.warehouse_uid, args.hero_index)
        self:SendResult(player_id, args.request_id, ok, reason)
    end)

    CustomGameEventManager:RegisterListener("rpg_shop_unequip", function(_, args)
        local player_id = tonumber(args.PlayerID)
        local ok, reason = self:Unequip(player_id, args.item_index)
        self:SendResult(player_id, args.request_id, ok, reason)
    end)

    CustomGameEventManager:RegisterListener("rpg_shop_sell", function(_, args)
        local player_id = tonumber(args.PlayerID)
        local ok, reason, refund = self:Sell(player_id, args.warehouse_uid)
        self:SendResult(player_id, args.request_id, ok, reason, refund)
    end)
end

return ShopService
