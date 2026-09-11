-- Fixes warehouse/courier -> hero item transfer without deleting the source item.
-- The same item handle is detached from the warehouse and attached to the hero.
-- The source item is never UTIL_Remove'd during a successful transfer.

local InventoryTransfer = {}
InventoryTransfer.__index = InventoryTransfer

local DEFAULT_FIRST_SLOT = 0
local DEFAULT_LAST_HERO_SLOT = 8 -- 0..5 inventory, 6..8 backpack
local DEFAULT_LAST_SOURCE_SLOT = 15

local function is_valid(handle)
    if handle == nil then
        return false
    end
    if IsValidEntity ~= nil and not IsValidEntity(handle) then
        return false
    end
    if handle.IsNull ~= nil and handle:IsNull() then
        return false
    end
    return true
end

local function safe_call(handle, method_name, default_value, ...)
    if not is_valid(handle) or handle[method_name] == nil then
        return default_value
    end

    local ok, value = pcall(handle[method_name], handle, ...)
    if not ok then
        return default_value
    end
    return value
end

local function item_name(item)
    local name = safe_call(item, "GetAbilityName", nil)
    if name == nil or name == "" then
        name = safe_call(item, "GetName", "unknown_item")
    end
    return tostring(name)
end

local function item_entindex(item)
    local index = safe_call(item, "entindex", -1)
    return tonumber(index) or -1
end

local function contains_exact_item(unit, wanted, last_slot)
    if not is_valid(unit) or not is_valid(wanted) then
        return false, nil
    end

    local wanted_index = item_entindex(wanted)
    for slot = DEFAULT_FIRST_SLOT, last_slot do
        local current = safe_call(unit, "GetItemInSlot", nil, slot)
        if is_valid(current) then
            if current == wanted or (wanted_index >= 0 and item_entindex(current) == wanted_index) then
                return true, slot
            end
        end
    end
    return false, nil
end

local function has_free_hero_slot(hero, last_slot)
    for slot = DEFAULT_FIRST_SLOT, last_slot do
        local current = safe_call(hero, "GetItemInSlot", nil, slot)
        if not is_valid(current) then
            return true
        end
    end
    return false
end

local function inventory_fingerprint(unit, last_slot)
    local rows = {}
    for slot = DEFAULT_FIRST_SLOT, last_slot do
        local item = safe_call(unit, "GetItemInSlot", nil, slot)
        if is_valid(item) then
            rows[#rows + 1] = table.concat({
                tostring(slot),
                item_name(item),
                tostring(item_entindex(item)),
                tostring(safe_call(item, "GetCurrentCharges", 0)),
                tostring(safe_call(item, "GetSecondaryCharges", 0)),
            }, ":")
        else
            rows[#rows + 1] = tostring(slot) .. ":empty"
        end
    end
    return table.concat(rows, "|")
end

-- TakeItem detaches a live entity. RemoveItem destroys it in the native engine.
-- Inspect ownership even if the API throws after completing the operation.
local function detach_item(unit, item, last_slot)
    if not is_valid(item) or unit.TakeItem == nil then return false end
    pcall(unit.TakeItem, unit, item)
    return is_valid(item) and not contains_exact_item(unit, item, last_slot)
end

local function has_ground_container(item)
    local container = safe_call(item, "GetContainer", nil)
    return is_valid(container) and safe_call(container, "GetContainedItem", nil) == item
end

local function preserve_on_ground(item, source)
    if not is_valid(item) then return false end
    if has_ground_container(item) then return true end
    local origin = safe_call(source, "GetAbsOrigin", nil)
    if origin ~= nil and CreateItemOnPositionSync ~= nil then
        local ok, container = pcall(CreateItemOnPositionSync, origin, item)
        return has_ground_container(item) or (ok and is_valid(container)
            and safe_call(container, "GetContainedItem", nil) == item)
    end
    return false
end

local function send_result(player_id, payload)
    if CustomGameEventManager == nil or PlayerResource == nil then
        return
    end

    local player = PlayerResource:GetPlayer(player_id)
    if player ~= nil then
        CustomGameEventManager:Send_ServerToPlayer(
            player,
            "rpg_inventory_transfer_result",
            payload
        )
    end
end

function InventoryTransfer.new(options)
    options = options or {}

    return setmetatable({
        get_phase = options.get_phase or function() return "PREPARE" end,
        is_roster_hero = options.is_roster_hero,
        is_inventory_source = options.is_inventory_source,
        on_success = options.on_success,
        hero_last_slot = options.hero_last_slot or DEFAULT_LAST_HERO_SLOT,
        source_last_slot = options.source_last_slot or DEFAULT_LAST_SOURCE_SLOT,
        event_name = options.event_name or "rpg_transfer_warehouse_item",
        on_error = options.on_error,
        listener_installed = false,
    }, InventoryTransfer)
end

function InventoryTransfer:Fail(player_id, code, message)
    print("[RPGInventory] failed player=" .. tostring(player_id) .. " code=" .. tostring(code))
    local payload = {
        ok = 0,
        code = tostring(code),
        message = tostring(message),
    }

    if self.on_error ~= nil then
        pcall(self.on_error, player_id, payload)
    end
    send_result(player_id, payload)
    return false, code
end

function InventoryTransfer:Succeed(player_id, item, hero, original_name, original_index)
    print("[RPGInventory] transferred player=" .. tostring(player_id)
        .. " item=" .. tostring(original_name) .. " entity=" .. tostring(original_index)
        .. " target=" .. tostring(safe_call(hero, "entindex", -1)))
    if self.on_success ~= nil then pcall(self.on_success, player_id, item, hero) end
    send_result(player_id, {
        ok = 1,
        item_entindex = is_valid(item) and item_entindex(item) or original_index,
        item_name = original_name or item_name(item),
        hero_name = safe_call(hero, "GetUnitName", ""),
        hero_entindex = safe_call(hero, "entindex", -1),
    })
    return true
end

function InventoryTransfer:Transfer(player_id, source_unit, source_item, target_hero)
    if self.get_phase() ~= "PREPARE" then
        return self:Fail(player_id, "not_prepare", "只能在准备阶段转交装备。")
    end

    if tonumber(player_id) == nil or tonumber(player_id) < 0 then
        return self:Fail(player_id, "invalid_player", "Invalid player.")
    end
    if self.is_inventory_source ~= nil
        and self.is_inventory_source(player_id, source_unit) ~= true then
        return self:Fail(player_id, "not_owned_source", "Source is not a player inventory carrier.")
    end
    if not is_valid(source_unit) then
        return self:Fail(player_id, "invalid_source", "仓库小精灵不存在。")
    end
    if not is_valid(source_item) then
        return self:Fail(player_id, "invalid_item", "装备不存在或已经被转移。")
    end
    if not is_valid(target_hero) then
        return self:Fail(player_id, "invalid_target", "目标英雄不存在。")
    end

    if self.is_roster_hero ~= nil
        and self.is_roster_hero(player_id, target_hero) ~= true then
        return self:Fail(player_id, "not_owned", "目标不是玩家当前拥有的英雄。")
    end

    local source_has_item = contains_exact_item(
        source_unit,
        source_item,
        self.source_last_slot
    )
    if not source_has_item then
        return self:Fail(player_id, "source_mismatch", "装备不在仓库小精灵库存中。")
    end

    -- Reject before detaching. This avoids AddItem dropping the item on the ground.
    -- Auto-combine with a completely full inventory is intentionally not attempted;
    -- the player can first free one inventory/backpack slot.
    if not has_free_hero_slot(target_hero, self.hero_last_slot) then
        return self:Fail(player_id, "inventory_full", "目标英雄物品栏与背包已满。")
    end

    local target_before = inventory_fingerprint(target_hero, self.hero_last_slot)
    local original_name = item_name(source_item)
    local original_index = item_entindex(source_item)

    print("[RPGInventory] requested player=" .. tostring(player_id)
        .. " item=" .. original_name .. " entity=" .. tostring(original_index)
        .. " source=" .. tostring(item_entindex(source_unit))
        .. " target=" .. tostring(item_entindex(target_hero)))
    if not detach_item(source_unit, source_item, self.source_last_slot) then
        return self:Fail(player_id, "detach_failed", "无法安全取出装备，未执行转交。")
    end

    pcall(function()
        target_hero:AddItem(source_item)
    end)

    local target_after = inventory_fingerprint(target_hero, self.hero_last_slot)
    local target_has_item = contains_exact_item(
        target_hero,
        source_item,
        self.hero_last_slot
    )

    -- target_after may change while the original handle is consumed by stacking or
    -- recipe combination. Both cases count as a successful transfer.
    if target_has_item or (not is_valid(source_item) and target_after ~= target_before) then
        return self:Succeed(
            player_id,
            source_item,
            target_hero,
            original_name,
            original_index
        )
    end

    -- Keep a native dropped item in its container: deleting a nonempty container
    -- can destroy its contents. A failed attachment must preserve the same item.
    if is_valid(source_item) then
        if contains_exact_item(target_hero, source_item, self.source_last_slot)
            and not detach_item(target_hero, source_item, self.source_last_slot) then
            return self:Fail(player_id, "target_retained", "装备仍在目标英雄储藏栏中，请检查装备列表。")
        end
        if not has_ground_container(source_item) then
            pcall(function() source_unit:AddItem(source_item) end)
        end
        if contains_exact_item(source_unit, source_item, self.source_last_slot) then
            return self:Fail(player_id, "target_rejected", "目标英雄未接收装备，装备已退回仓库。")
        end
        if preserve_on_ground(source_item, source_unit) then
            return self:Fail(player_id, "preserved_on_ground", "装备未能入栏，已保留在地面，请拾取。")
        end
    end

    return self:Fail(
        player_id,
        "rollback_failed",
        "装备转交失败且自动退回失败，请查看服务端日志。"
    )
end

function InventoryTransfer:TransferByEntIndex(player_id, source_index, item_index, hero_index)
    local source = EntIndexToHScript(tonumber(source_index) or -1)
    local item = EntIndexToHScript(tonumber(item_index) or -1)
    local hero = EntIndexToHScript(tonumber(hero_index) or -1)
    return self:Transfer(player_id, source, item, hero)
end

function InventoryTransfer:InstallEventListener()
    if self.listener_installed or CustomGameEventManager == nil then
        return
    end

    self.listener_installed = true
    CustomGameEventManager:RegisterListener(self.event_name, function(_source, data)
        data = data or {}
        local player_id = tonumber(data.PlayerID)
            or tonumber(data.player_id)
            or -1
        local source_index = data.source_entindex
            or data.courier_entindex
            or data.warehouse_entindex
        local item_index = data.item_entindex or data.item_index
        local hero_index = data.hero_entindex or data.target_entindex

        self:TransferByEntIndex(
            player_id,
            source_index,
            item_index,
            hero_index
        )
    end)
end

return InventoryTransfer
