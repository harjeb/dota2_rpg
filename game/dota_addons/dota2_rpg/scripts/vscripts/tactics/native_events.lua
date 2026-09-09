local M = {}
local linked = false
function M.Attach(unit)
    if unit.rpgTacticsEvents then return unit.rpgTacticsEvents end
    local events = {casts={}}
    unit.rpgTacticsEvents = events
    if LinkLuaModifier and unit.AddNewModifier then
        if not linked then
            LinkLuaModifier("modifier_rpg_tactics_events", "modifiers/modifier_rpg_tactics_events", LUA_MODIFIER_MOTION_NONE)
            linked = true
        end
        unit:AddNewModifier(unit, nil, "modifier_rpg_tactics_events", {})
    end
    return events
end
function M.Detach(unit)
    if not unit then return end
    if unit.IsNull and unit:IsNull() then return end
    unit.rpgTacticsEvents = nil
    if unit.RemoveModifierByName then unit:RemoveModifierByName("modifier_rpg_tactics_events") end
end
return M
