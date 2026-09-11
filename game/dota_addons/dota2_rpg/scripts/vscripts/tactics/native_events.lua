local M = {}
local linked = false
local sequence = 0
-- Called only by the native successful-execution observer, never order submission.
function M.RecordSuccess(unit, name, now)
    local events = unit and unit.rpgTacticsEvents
    if not events or type(name) ~= "string" or name == "" then return end
    sequence = sequence + 1
    events.casts[name] = (events.casts[name] or 0) + 1
    events.successes[name] = {sequence=sequence, time=now}
    require("tactics/action_lifecycle").Executed(unit,name,now)
end
function M.SucceededAfter(actor, prerequisite, caster, action, seconds, now)
    local before = actor and actor.rpgTacticsEvents and actor.rpgTacticsEvents.successes
    local own = caster and caster.rpgTacticsEvents and caster.rpgTacticsEvents.successes
    before = before and before[prerequisite]
    own = own and own[action]
    if not before or (own and own.sequence >= before.sequence) then return false end
    local age = now - before.time
    return age >= 0 and age <= seconds
end
function M.Attach(unit)
    if unit.rpgTacticsEvents then return unit.rpgTacticsEvents end
    local events = {casts={}, successes={}}
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
