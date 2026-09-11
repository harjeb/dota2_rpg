-- Refresh native equipment timers at non-combat lifecycle boundaries only.
local Cooldowns = {}
local function valid(entity)
    return entity ~= nil and (not entity.IsNull or not entity:IsNull())
end
function Cooldowns.Refresh(game)
    if game.phase == "fight" or game.phase == "countdown" then return end
    local seenUnits, seenItems = {}, {}
    local function refresh(unit)
        if not valid(unit) or seenUnits[unit] or not unit.GetItemInSlot then return end
        seenUnits[unit] = true
        -- Includes backpack, native stash, TP and neutral slots. Dead carriers
        -- retain items too; do not require IsAlive or recreate their equipment.
        for slot = 0, 16 do
            local item = unit:GetItemInSlot(slot)
            if valid(item) and not seenItems[item] and item.EndCooldown then
                seenItems[item] = true
                item:EndCooldown()
            end
        end
    end
    for _, units in pairs(game.battleManager and game.battleManager.teamHeroes or {}) do
        for _, unit in pairs(units) do refresh(unit) end
    end
    for _, unit in pairs(game.benchUnits or {}) do refresh(unit) end
    if game.GetStashUnit then refresh(game:GetStashUnit()) end
end
return Cooldowns
