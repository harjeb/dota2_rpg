-- Confirmed native releases only; no orders, cast phases or cursor polling.
local M = {}
local reviewed = {
    lina_light_strike_array = {"light_strike_array_aoe", "light_strike_array_delay_time"},
    leshrac_split_earth = {"radius", "delay"},
    kunkka_torrent = {"radius", "delay"},
}
local records, viewers, executed = {}, {}, {}
local sequence = 0
local function call(object, method, ...)
    if not object then return nil end
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= "function" then return nil end
    local success, value = pcall(fn, object, ...)
    if success then return value end
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function position(ability)
    local value = call(ability, "GetCursorPosition")
    local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
    if ok and finite(x) and finite(y) and finite(z) then return {x=x,y=y,z=z} end
end
local function prune(now)
    for id, record in pairs(records) do
        if now >= record.expires_at then records[id] = nil end
    end
end
function M.OnExecuted(unit, ability, now)
    if not unit or not ability or not finite(now) then return end
    local keys = reviewed[call(ability, "GetAbilityName")]
    if not keys then return end
    -- Keep the latest event per ability, including unseen/invalid releases. A
    -- duplicate must never resample a cursor or acquire new team sightings.
    local events = executed[unit]
    if not events then events = {}; executed[unit] = events end
    if events[ability] and now <= events[ability] then return end
    events[ability] = now
    prune(now)
    local enemyTeam = call(unit, "GetTeamNumber")
    if not finite(enemyTeam) then return end
    local seen = {}
    for viewer in pairs(viewers) do
        local team = call(viewer, "GetTeamNumber")
        if finite(team) and team ~= enemyTeam and call(viewer, "IsNull") ~= true
            and call(viewer, "IsAlive") ~= false
            and call(viewer, "CanEntityBeSeenByMyTeam", unit) == true then
            seen[team] = true
        end
    end
    if not next(seen) then return end
    local radius = call(ability, "GetSpecialValueFor", keys[1])
    local delay = call(ability, "GetSpecialValueFor", keys[2])
    local point = position(ability)
    if not point or not finite(radius) or radius <= 0 or not finite(delay) or delay <= 0
        or not finite(now + delay) then return end
    sequence = sequence + 1
    records[sequence] = {id=sequence,caster=unit,ability=ability,position=point,radius=radius,
        phase="released",released_at=now,impact_at=now+delay,expires_at=now+delay,seen=seen}
end
function M.Observe(units, now)
    if not finite(now) then return end
    prune(now)
    -- The latest battle roster supplies viewers; visibility is checked at the
    -- execution event, never used to discover an earlier hidden release.
    viewers = {}
    for _, unit in pairs(units or {}) do viewers[unit] = true end
    for unit in pairs(executed) do
        if call(unit, "IsNull") == true then executed[unit] = nil end
    end
end
function M.Threats(caster, now)
    if not finite(now) then return {} end
    prune(now)
    local result = {}
    local team = call(caster, "GetTeamNumber")
    if not finite(team) then return result end
    for _, record in pairs(records) do
        if record.seen[team] and now >= record.released_at then
            -- Return copies so consumers cannot change another team's snapshot.
            local copy = {}
            for key, value in pairs(record) do if key ~= "seen" then copy[key] = value end end
            copy.position = {x=record.position.x,y=record.position.y,z=record.position.z}
            result[#result+1] = copy
        end
    end
    table.sort(result,function(a,b) return a.id < b.id end)
    return result
end
function M.Reset(unit)
    if unit then
        for id, record in pairs(records) do
            if record.caster == unit then records[id] = nil end
        end
        viewers[unit], executed[unit] = nil, nil
    else
        records, viewers, executed = {}, {}, {}
    end
end
return M
