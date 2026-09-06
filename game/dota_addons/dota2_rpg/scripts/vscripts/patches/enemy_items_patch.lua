local EnemyItems = {}

local function orderedValues(values)
    local result = {}
    if type(values) ~= "table" then
        return result
    end
    local numeric = {}
    for key, value in pairs(values) do
        local index = tonumber(key)
        if index ~= nil then
            table.insert(numeric, { index = index, value = value })
        else
            table.insert(result, tostring(value))
        end
    end
    table.sort(numeric, function(a, b) return a.index < b.index end)
    for _, entry in ipairs(numeric) do
        table.insert(result, tostring(entry.value))
    end
    return result
end

function EnemyItems.EquipConfiguredItems(unit, enemyEntry)
    if unit == nil or type(enemyEntry) ~= "table" then
        return 0
    end
    local equipped = 0
    for _, itemName in ipairs(orderedValues(enemyEntry.items)) do
        if itemName ~= "" then
            local item = nil
            if unit.AddItemByName ~= nil then
                item = unit:AddItemByName(itemName)
            elseif CreateItem ~= nil and unit.AddItem ~= nil then
                item = CreateItem(itemName, unit, unit)
                if item ~= nil then
                    unit:AddItem(item)
                end
            end
            if item ~= nil then
                equipped = equipped + 1
            end
        end
    end
    return equipped
end

return EnemyItems
