-- Sparse lifecycle evidence only: never stop abilities or alter native modifiers.
-- Separate from RuntimeLog's session budget so late-round crashes remain visible.
local Lifecycle = {}
local sequence = 0

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...)
        if type(object[method]) ~= "function" then return nil end
        return object[method](object, ...)
    end, ...)
    if ok then return value end
    return nil
end

local function text(value)
    if value == nil then return "?" end
    return tostring(value):gsub("[%s\r\n]+", "_")
end

function Lifecycle.Event(mode, stage, detail)
    sequence = sequence + 1
    local gameTime = tonumber(call(GameRules, "GetGameTime")) or 0
    local realTime = type(Time) == "function" and Time() or 0
    print(string.format("[RPGLifecycle seq=%d t=%.3f real=%.3f level=%s phase=%s] %s %s",
        sequence, gameTime, realTime, text(mode and mode.currentLevelId),
        text(mode and mode.phase), text(stage), detail or ""))
end

function Lifecycle.Snapshot(unit)
    if unit == nil then return "entity=nil" end
    -- Do not inspect an invalid native handle. Lua pcall only guards Lua/API errors;
    -- it cannot catch a native access violation.
    local null = call(unit, "IsNull")
    if null ~= false then return "entity=invalid null=" .. text(null) end
    local modifiers = {}
    local count = tonumber(call(unit, "GetModifierCount")) or 0
    for index = 0, math.min(count, 64) - 1 do
        modifiers[#modifiers + 1] = text(call(unit, "GetModifierNameByIndex", index))
    end
    if count > 64 then modifiers[#modifiers + 1] = "..." end
    local active = call(unit, "GetCurrentActiveAbility")
    local abilityName = "none"
    if active ~= nil and call(active, "IsNull") == false then
        abilityName = text(call(active, "GetAbilityName"))
    end
    return string.format("entity=%s name=%s alive=%s channel=%s outofgame=%s active=%s modifiers=%d[%s]",
        text(call(unit, "GetEntityIndex")), text(call(unit, "GetUnitName")),
        text(call(unit, "IsAlive")), text(call(unit, "IsChanneling")),
        text(call(unit, "IsOutOfGame")), abilityName, count, table.concat(modifiers, ","))
end

function Lifecycle.Remove(mode, unit, role)
    -- Marker precedes native state inspection so a crash inside inspection is visible.
    Lifecycle.Event(mode, "remove_inspect", "role=" .. text(role))
    local snapshot = Lifecycle.Snapshot(unit)
    Lifecycle.Event(mode, "remove_before", "role=" .. text(role) .. " " .. snapshot)
    unit:RemoveSelf()
    -- Never query the removed entity, even for logging.
    Lifecycle.Event(mode, "remove_after", "role=" .. text(role) .. " " .. snapshot)
end

function Lifecycle.Create(mode, name, position, team, role)
    Lifecycle.Event(mode, "create_before", "role=" .. text(role) .. " name=" .. text(name) .. " team=" .. text(team))
    local unit = CreateUnitByName(name, position, true, nil, nil, team)
    Lifecycle.Event(mode, "create_returned", "role=" .. text(role) .. " name=" .. text(name))
    Lifecycle.Event(mode, "create_after", "role=" .. text(role) .. " " .. Lifecycle.Snapshot(unit))
    return unit
end

return Lifecycle
