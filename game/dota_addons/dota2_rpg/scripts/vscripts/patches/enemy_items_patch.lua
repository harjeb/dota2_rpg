local EnemyItems = {}

local function orderedValues(values)
    local result = {}
    if type(values) ~= "table" then
        return result
    end
    local numeric = {}
    local named = {}
    for key, value in pairs(values) do
        local index = tonumber(key)
        if index ~= nil then
            table.insert(numeric, { index = index, value = value })
        else
            table.insert(named, { key = tostring(key), value = value })
        end
    end
    table.sort(numeric, function(a, b) return a.index < b.index end)
    table.sort(named, function(a, b) return a.key < b.key end)
    for _, entry in ipairs(numeric) do
        table.insert(result, tostring(entry.value))
    end
    for _, entry in ipairs(named) do
        table.insert(result, tostring(entry.value))
    end
    return result
end

local function valid(entity)
    return entity ~= nil and (entity.IsNull == nil or not entity:IsNull())
end

function EnemyItems.EquipConfiguredItems(unit, enemyEntry)
    if not valid(unit) or type(enemyEntry) ~= "table" then
        return 0
    end
    local equipped = 0
    local function equip(itemName, targetSlot)
        if itemName ~= "" then
            -- A stale/invalid native item ID must not abort the whole enemy
            -- spawn before its remaining equipment, tactics and roster binding.
            local ok, item = pcall(function()
                if unit.AddItemByName ~= nil then
                    return unit:AddItemByName(itemName)
                elseif CreateItem ~= nil and unit.AddItem ~= nil then
                    local created = CreateItem(itemName, unit, unit)
                    if valid(created) then
                        return unit:AddItem(created)
                    end
                end
            end)
            if ok and valid(item) then
                local placed, reason = pcall(function()
                    if targetSlot ~= nil then
                        assert(item.GetItemSlot ~= nil and unit.SwapItems ~= nil, "native slot APIs unavailable")
                        local current = item:GetItemSlot()
                        assert(current ~= nil and current >= 0, "item not in inventory")
                        if current ~= targetSlot then unit:SwapItems(current, targetSlot) end
                        assert(item:GetItemSlot() == targetSlot, "native slot placement rejected")
                    end
                end)
                if placed then
                    equipped = equipped + 1
                else
                    -- Never leave a backpack/neutral item active in a main slot.
                    if unit.RemoveItem ~= nil then pcall(unit.RemoveItem, unit, item) end
                    print(string.format("[RPG][EnemyItems] Failed slot %s for %s: %s", tostring(targetSlot), itemName, tostring(reason)))
                end
            else
                print(string.format("[RPG][EnemyItems] Failed to equip %s on %s: %s",
                    itemName, tostring(enemyEntry.unit or "enemy"), ok and "no item returned" or tostring(item)))
            end
        end
    end
    for _, itemName in ipairs(orderedValues(enemyEntry.items)) do
        equip(itemName)
    end
    -- KV uses string indices, JSON uses numeric indices. Look up each fixed
    -- position without compacting holes: backpack indices 1..3 map to slots 6..8.
    local backpack = enemyEntry.backpack_items
    if type(backpack) == "table" then
        for index = 1, 3 do
            local name = backpack[index] or backpack[tostring(index)]
            if type(name) == "string" and name ~= "" then equip(name, index + 5) end
        end
    end
    if type(enemyEntry.neutral_item) == "string" and enemyEntry.neutral_item ~= "" then
        equip(enemyEntry.neutral_item, DOTA_ITEM_NEUTRAL_SLOT or 16)
    end
    return equipped
end

return EnemyItems
