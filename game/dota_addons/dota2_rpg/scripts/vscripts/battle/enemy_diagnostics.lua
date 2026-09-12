-- Passive enemy roster diagnostics. Never resolves entities or submits orders.
local M = {}
local sessions = setmetatable({}, {__mode = "k"})
local function get(object, key)
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
end
local function call(object, key)
    local method = get(object, key)
    if type(method) ~= "function" then return nil end
    if key ~= "IsNull" then
        local null = get(object, "IsNull")
        if type(null) == "function" then
            local ok, invalid = pcall(null, object)
            if not ok or invalid then return nil end
        end
    end
    local ok, value = pcall(method, object)
    if ok then return value end
end
-- 带参数的安全调用：call() 只转发单个参数，取技能槽需要传 slot。
local function call_args(object, key, ...)
    local method = get(object, key)
    if type(method) ~= "function" then return nil end
    if key ~= "IsNull" then
        local null = get(object, "IsNull")
        if type(null) == "function" then
            local ok, invalid = pcall(null, object)
            if not ok or invalid then return nil end
        end
    end
    local ok, value = pcall(method, object, ...)
    if ok then return value end
end
local function text(value)
    if type(value) == "number" then
        if value ~= value or math.abs(value) == math.huge then return "unknown" end
        return string.format("%.2f", value)
    end
    if type(value) == "string" then return value:gsub("%s", "_") end
    if type(value) == "boolean" then return value and "1" or "0" end
    return "unknown"
end
local function num(value)
    if type(value) == "number" and value == value and math.abs(value) < math.huge then return value end
end
local function position(unit)
    local p = call(unit, "GetAbsOrigin")
    local x, y = num(get(p, "x")), num(get(p, "y"))
    if x and y then return {x=x, y=y} end
end
local function distance(a, b)
    if a and b then return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2) end
end
local function id(unit) return call(unit, "entindex") or call(unit, "GetEntityIndex") end
local function emit(line)
    -- Keep round diagnostics available after the ordinary 1500-line trace budget
    -- is exhausted. Throttling is per entity/phase below, not per whole run.
    pcall(print, "[RPGEnemy] " .. line)
end
local flags = {alive="IsAlive", reincarnating="IsReincarnating", idle="IsIdle",
    stun="IsStunned", root="IsRooted", disarm="IsDisarmed", restricted="IsCommandRestricted",
    casting="IsUsingAbility", channel="IsChanneling", abilityphase="IsInAbilityPhase", invalid="IsNull"}
local function snapshot(game, unit, old, now)
    local p, target, forced = position(unit), call(unit, "GetAttackTarget"), call(unit, "GetForceAttackTarget")
    local fields, stable = {}, {}
    local function add(key, value, transition)
        local part = key .. "=" .. text(value)
        fields[#fields+1] = part
        if transition then stable[#stable+1] = part end
    end
    add("entity", id(unit), true); add("name", call(unit, "GetUnitName"), true)
    -- Fixed iteration order keeps the transition signature deterministic.
    for _, key in ipairs({"alive","reincarnating","idle","stun","root","disarm","restricted","casting","channel","abilityphase","invalid"}) do
        add(key, call(unit, flags[key]), true)
    end
    add("hp", call(unit, "GetHealth")); add("maxhp", call(unit, "GetMaxHealth"))
    add("pos", p and (text(p.x) .. "," .. text(p.y)))
    add("delta", distance(p, old and old.position))
    add("target", id(target), true); add("targetdist", distance(p, position(target)))
    add("forced", id(forced), true); add("forceddist", distance(p, position(forced)))
    add("range", call(unit, "Script_GetAttackRange"))
    add("active", call(call(unit, "GetCurrentActiveAbility"), "GetAbilityName"), true)
    -- 临时诊断：野怪技能为什么放不出来 —— 逐个报技能等级/冷却/可施放/蓝量。
    -- 由 RPG_ENEMY_ABILITY_PROBE 开关控制（默认关闭，避免扰动既有行数断言）。
    -- 排查完成后应连同开关一起删除（见 docs 或 git log）。
    if RPG_ENEMY_ABILITY_PROBE then
        add("unitlv", call(unit, "GetLevel"), true)
        add("hasSetLevel", type(get(unit, "SetLevel")) == "function" and "1" or "0", true)
        add("hasHeroLevelUp", type(get(unit, "HeroLevelUp")) == "function" and "1" or "0", true)
        add("mana", call(unit, "GetMana")); add("maxmana", call(unit, "GetMaxMana"))
        local count = tonumber(call(unit, "GetAbilityCount")) or 0
        local parts = {}
        for slot = 0, math.min(count, 8) - 1 do
            local ability = call_args(unit, "GetAbilityByIndex", slot)
            if ability ~= nil then
                local aname = call(ability, "GetAbilityName")
                if type(aname) == "string" and aname ~= "" then
                    parts[#parts+1] = string.format("%s[lv=%s cd=%s cast=%s mana=%s passive=%s hidden=%s]",
                        aname,
                        text(call(ability, "GetLevel")),
                        text(call(ability, "GetCooldownTimeRemaining")),
                        text(call(ability, "IsFullyCastable")),
                        text(call(ability, "IsOwnersManaEnough")),
                        text(call(ability, "IsPassive")),
                        text(call(ability, "IsHidden")))
                end
            end
        end
        add("abilities", #parts > 0 and table.concat(parts, "|") or "none", true)
    end
    local attack = get(get(unit, "rpgTacticsEvents"), "attack")
    local released = num(get(attack, "time"))
    add("releaseage", now and released and math.max(0, now-released))
    local intent = get(unit, "rpg_neutral_attack_intent")
    for _, pair in ipairs({{"owner","owner"},{"retry","retries"},{"request","requested"},{"progress","progress"},{"blocked","blocked_until"}}) do
        add("intent." .. pair[1], get(intent, pair[2]), pair[1]=="owner" or pair[1]=="retry" or pair[1]=="blocked")
    end
    local engine = get(get(game, "tacticBridge"), "tacticEngine")
    local state = get(get(engine, "states"), id(unit))
    if get(state, "unit") ~= unit then state = nil end
    local chase = get(state, "chase")
    add("chase", chase ~= nil, true)
    for _, key in ipairs({"target_index","rule_index","logical_id","deadline","max_distance"}) do
        add("chase." .. key, get(chase, key), key ~= "deadline")
    end
    return table.concat(fields, " "), table.concat(stable, " "), p
end
local function think(game)
    if type(game) ~= "table" then return end
    local now = num(call(GameRules, "GetGameTime"))
    local phase, level = text(get(game, "phase")), text(get(game, "currentLevelId"))
    local session = sessions[game]
    if not session then session = {units={}}; sessions[game] = session end
    local changed = phase ~= session.phase or level ~= session.level or (now and session.time and now < session.time)
    local prefix = "level=" .. level .. " phase=" .. phase .. " time=" .. text(now) .. " "
    if changed then emit(prefix .. "event=phase") end
    local roster = get(get(get(game, "battleManager"), "teamHeroes"), DOTA_TEAM_BADGUYS or 3)
    local seen = {}
    if type(roster) == "table" then
        for _, unit in pairs(roster) do
            if (type(unit) == "table" or type(unit) == "userdata") and not seen[unit] then
                seen[unit] = true
                local old = session.units[unit]
                local ok, line, signature, p = pcall(snapshot, game, unit, old, now)
                if not ok then line, signature = "state=unknown", "unknown" end
                local periodic = phase:lower() == "fight" and now and old and (not old.time or now-old.time >= 2)
                if changed or not old or old.signature ~= signature or periodic then
                    local event = not old and "added" or changed and "phase" or old.signature ~= signature and "state" or "periodic"
                    emit(prefix .. "event=" .. event .. " " .. line)
                    session.units[unit] = {signature=signature, position=p, time=now, line=line}
                end
            end
        end
    end
    for unit, old in pairs(session.units) do
        if not seen[unit] then emit(prefix .. "event=removed " .. old.line); session.units[unit] = nil end
    end
    session.phase, session.level, session.time = phase, level, now
end
function M.OnThink(game)
    local ok = pcall(think, game)
    if not ok then
        -- One error per broken interval; malformed native getters normally stay field-local.
        if not M.failed then emit("event=error state=unknown") end
        M.failed = true
    else M.failed = nil end
end
return M
