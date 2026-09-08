-- Stable action identities for visible native actions. Hidden helper abilities
-- become selectable when the engine exposes them (e.g. a transformation).
local Catalog = {}

function Catalog.ListAbilities(hero)
    local names, seen = {}, {}
    for slot = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(slot)
        if ability ~= nil and not ability:IsNull() then
            local name = ability:GetAbilityName()
            if name ~= "" and name ~= "generic_hidden" and not name:match("^special_bonus")
                and not name:match("^rubick_hidden%d+$") and not seen[name]
                and (ability.IsHidden == nil or not ability:IsHidden()) then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    return names
end

function Catalog.ListActions(hero)
    local actions, seen = {}, {}
    for slot = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(slot)
        if ability ~= nil and not ability:IsNull() then
            local name = ability:GetAbilityName()
            if name ~= "" and name ~= "generic_hidden"
                and not name:match("^special_bonus") and not name:match("^rubick_hidden%d+$")
                and (ability.IsHidden == nil or not ability:IsHidden())
                and not ability:IsPassive() and not seen[name] then
                seen[name] = true
                table.insert(actions, name)
            end
        end
    end
    if hero.GetItemInSlot ~= nil then
        for slot = 0, 5 do
            local item = hero:GetItemInSlot(slot)
            if item ~= nil and not item:IsNull() and not item:IsHidden() and not item:IsPassive() then
                table.insert(actions, "item_" .. (slot + 1))
            end
        end
    end
    table.insert(actions, "attack")
    return actions
end

function Catalog.DescribeAction(hero, action)
    if action == "attack" then return "attack", "" end
    if action == "ultimate" then
        for slot = 0, hero:GetAbilityCount() - 1 do
            local ability = hero:GetAbilityByIndex(slot)
            if ability ~= nil and not ability:IsNull() and not ability:IsPassive()
                and not ability:IsHidden() and ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
                return "ability", ability:GetAbilityName()
            end
        end
        return "ability", ""
    end
    local slot = tonumber(action:match("^ability_(%d+)$"))
    if slot ~= nil then
        local ability = hero:GetAbilityByIndex(slot - 1)
        return "ability", ability ~= nil and not ability:IsNull() and ability:GetAbilityName() or ""
    end
    slot = tonumber(action:match("^item_(%d+)$"))
    if slot ~= nil and hero.GetItemInSlot ~= nil then
        local item = hero:GetItemInSlot(slot - 1)
        return "item", item ~= nil and not item:IsNull() and item:GetAbilityName() or ""
    end
    local ability = hero.FindAbilityByName ~= nil and hero:FindAbilityByName(action) or nil
    if ability ~= nil and not ability:IsNull() then return "ability", ability:GetAbilityName() end
    return "ability", action
end

return Catalog
