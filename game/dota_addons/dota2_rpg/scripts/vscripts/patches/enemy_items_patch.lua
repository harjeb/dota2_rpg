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
    for _, itemName in ipairs(orderedValues(enemyEntry.items)) do
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
                equipped = equipped + 1
            else
                print(string.format("[RPG][EnemyItems] Failed to equip %s on %s: %s",
                    itemName, tostring(enemyEntry.unit or "enemy"), ok and "no item returned" or tostring(item)))
            end
        end
    end
    return equipped
end

return EnemyItems
