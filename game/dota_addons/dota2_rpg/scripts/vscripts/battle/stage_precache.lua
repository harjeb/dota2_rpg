-- Native adapters and the deferred scheduler are supplied by the caller.
local M = {}
local essentials = {units={"npc_dota_hero_wisp"}, items={
    "item_rpg_scroll_low", "item_rpg_scroll_high", "item_aegis", "item_cheese"}}
local function valid(name, prefix)
    return type(name) == "string" and name:match("^" .. prefix .. "[%w_]+$") ~= nil
end
function M.Plan(level)
    local plan, seen = {units={}, items={}}, {}
    local function add(kind, name, prefix)
        if valid(name, prefix) and not seen[name] then
            seen[name] = true; plan[kind][#plan[kind]+1] = name
        end
    end
    for _, enemy in pairs(type(level) == "table" and type(level.enemies) == "table" and level.enemies or {}) do
        if type(enemy) == "table" then
            add("units", enemy.unit, "npc_dota_")
            for _, item in pairs(type(enemy.items) == "table" and enemy.items or {}) do add("items", item, "item_") end
        end
    end
    table.sort(plan.units); table.sort(plan.items)
    return plan
end
local function first(levels)
    local keys = {}
    for id in pairs(levels) do keys[#keys+1] = id end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    return keys[1]
end
local function resources(plan)
    local out = {}
    for _, kind in ipairs({"units", "items"}) do
        for _, name in ipairs(plan[kind]) do out[#out+1] = {name=name, kind=kind} end
    end
    return out
end
local function seed(levels)
    local id, ready = first(levels), {}
    for _, plan in ipairs({essentials, M.Plan(levels[id])}) do
        for _, r in ipairs(resources(plan)) do ready[r.name] = r.kind end
    end
    return id, ready
end
-- Returns {levelId=first sorted key, units={...}, items={...}, ready={[name]=true}}.
-- A missing/failed startup API raises; callers must not construct a seeded cache then.
function M.Startup(context, levels)
    local id, names = seed(levels or {})
    local result = {levelId=id, units={}, items={}, ready={}}
    for name, kind in pairs(names) do result[kind][#result[kind]+1] = name end
    for _, kind in ipairs({"units", "items"}) do
        table.sort(result[kind])
        local load
        if kind == "units" then load = PrecacheUnitByNameSync else load = PrecacheItemByNameSync end
        assert(type(load) == "function", "missing startup precache API: " .. kind)
        for _, name in ipairs(result[kind]) do
            local started = type(RealTime) == "function" and RealTime() or nil
            assert(load(name, context) ~= false, "startup precache failed: " .. name)
            result.ready[name] = true
            print(string.format("[RPGPrecache] startup_resource %s elapsed=%s", name,
                started and string.format("%.3f", RealTime() - started) or "unavailable"))
        end
    end
    return result
end
local function validate(level)
    if type(level) ~= "table" or type(level.enemies) ~= "table" or next(level.enemies) == nil then return false end
    for _, enemy in pairs(level.enemies) do
        if type(enemy) ~= "table" or not valid(enemy.unit, "npc_dota_") then return false end
        if enemy.items ~= nil then
            if type(enemy.items) ~= "table" then return false end
            for _, item in pairs(enemy.items) do if not valid(item, "item_") then return false end end
        end
    end
    return true
end
function M.new(levels, options)
    levels, options = levels or {}, options or {}
    assert(type(options.schedule) == "function", "deferred schedule required")
    assert(type(options.now) == "function", "monotonic now required")
    local self = {}
    local states, stages, active, scheduled = {}, {}, nil, false
    local timeout, serial = tonumber(options.timeout) or 30, 0
    assert(timeout > 0, "positive timeout required")
    local _, seeded = seed(levels)
    for name in pairs(seeded) do states[name] = "ready" end
    local function log(message)
        if type(options.log) == "function" then pcall(options.log, message) end
    end
    local function observe(callback, ok, reason)
        if type(callback) == "function" then
            local success = xpcall(function() callback(ok, reason) end, function(err) return tostring(err) end)
            if not success then log("stage observer failure") end
        end
    end
    local function stage(id)
        if stages[id] then return stages[id] end
        if not validate(levels[id]) then return nil end
        local s = {id=id, resources=resources(M.Plan(levels[id])), watchers={}}
        stages[id] = s
        return s
    end
    local function ready(s)
        if not s then return false end
        for _, r in ipairs(s.resources) do if states[r.name] ~= "ready" then return false end end
        return true
    end
    local function status(s, message)
        local count = 0
        for _, r in ipairs(s.resources) do if states[r.name] == "ready" then count = count+1 end end
        log(string.format("stage %s %s %d/%d %.3fs", tostring(s.id), message,
            count, #s.resources, options.now()-(s.started or options.now())))
    end
    local function settle(s, ok, reason)
        local watchers = s.watchers
        s.watchers, s.pending, s.foreground = {}, false, false
        status(s, ok and "ready" or reason)
        for _, callback in ipairs(watchers) do observe(callback, ok, reason) end
    end
    local pump, wake
    wake = function()
        if scheduled then return end
        scheduled = true
        options.schedule(function() scheduled = false; pump() end, 0.1)
    end
    local function finish(token, ok, reason)
        -- Timeout abandons this logical operation; native APIs offer no cancellation.
        -- A later callback cannot mutate the cache or complete a replacement request.
        if active ~= token then return end
        active = nil
        states[token.name] = ok and "ready" or {error=reason}
        log(string.format("resource %s %s %.3fs", token.name, ok and "ready" or reason, options.now()-token.started))
        -- Detach all affected stages before notifying consumers (which may retry).
        local affected = {}
        for _, s in pairs(stages) do
            if s.pending then
                local failed = false
                for _, r in ipairs(s.resources) do if r.name == token.name and not ok then failed = true end end
                if failed or ready(s) then affected[#affected+1] = {s=s, ok=not failed} end
            end
        end
        for _, entry in ipairs(affected) do
            entry.watchers = entry.s.watchers
            entry.s.watchers, entry.s.pending, entry.s.foreground = {}, false, false
        end
        for _, entry in ipairs(affected) do
            local snapshot = {id=entry.s.id, resources=entry.s.resources, watchers=entry.watchers, started=entry.s.started}
            settle(snapshot, entry.ok, entry.ok and nil or reason)
        end
        wake()
    end
    pump = function()
        if active then return end
        local chosen
        for _, foreground in ipairs({true, false}) do
            for _, s in pairs(stages) do
                if s.pending and s.foreground == foreground
                    and (not chosen or (foreground and s.priority > chosen.priority)
                        or (not foreground and s.priority < chosen.priority)) then chosen = s end
            end
            if chosen then break end
        end
        if not chosen then return end
        if ready(chosen) then settle(chosen, true); wake(); return end
        local r
        for _, candidate in ipairs(chosen.resources) do
            if states[candidate.name] ~= "ready" then r = candidate; break end
        end
        if type(states[r.name]) == "table" then settle(chosen, false, states[r.name].error); wake(); return end
        local token = {name=r.name, started=options.now()}
        active = token
        log("resource " .. r.name .. " start")
        local load
        if r.kind == "units" then load = options.load_unit else load = options.load_item end
        if type(load) ~= "function" then finish(token, false, "missing API"); return end
        -- Buffer inline callbacks until the adapter returns, so false/throw wins.
        local invoking, called, callbackOK = true, false, true
        local function callback(ok)
            if called then return end
            called, callbackOK = true, ok ~= false
            if not invoking then finish(token, callbackOK, callbackOK and nil or "native failure") end
        end
        local ok, result = pcall(load, r.name, callback)
        invoking = false
        if not ok or result == false then finish(token, false, ok and "native rejected" or ("native throw: " .. tostring(result)))
        elseif called then finish(token, callbackOK, callbackOK and nil or "native failure")
        else options.schedule(function() finish(token, false, "timeout") end, timeout) end
    end
    function self:IsReady(id) return ready(stage(id)) end
    function self:Request(id, callback)
        local s = stage(id)
        if not s then observe(callback, false, "unknown or malformed level"); return end
        if ready(s) then observe(callback, true); return end
        if not s.pending then
            s.started = options.now()
            for _, r in ipairs(s.resources) do if type(states[r.name]) == "table" then states[r.name] = nil end end
            status(s, "requested")
        end
        serial = serial + 1
        s.priority = serial -- The latest selected stage outranks obsolete foreground work.
        s.pending, s.foreground = true, true
        if type(callback) == "function" then s.watchers[#s.watchers+1] = callback end
        wake()
    end
    function self:Prefetch(id)
        local s = stage(id)
        if not s or ready(s) or s.pending then return end
        -- A failed background resource requires an explicit foreground retry.
        for _, r in ipairs(s.resources) do if type(states[r.name]) == "table" then return end end
        serial = serial + 1
        s.priority = serial -- Background stages retain campaign enqueue order.
        s.pending, s.foreground, s.started = true, false, options.now()
        status(s, "prefetch")
        wake()
    end
    return self
end
return M
