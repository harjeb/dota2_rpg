-- Guard native APIs: unknown observations never become invented state.
local Context = {}
function Context.Call(object, method, ...)
    if object == nil then return nil end
    local ok, result = pcall(function(...)
        local fn = object[method]
        if type(fn) ~= "function" then return nil end
        return fn(object, ...)
    end, ...)
    if ok then return result end
end
function Context.Number(value)
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end
function Context.ModifierValue(unit, name, method)
    if type(name) ~= "string" or name == "" then return nil end
    local mods = Context.Call(unit, "FindAllModifiersByName", name)
    if type(mods) ~= "table" then
        local mod = Context.Call(unit, "FindModifierByName", name)
        mods = mod and { mod } or {}
    end
    local best
    for _, mod in pairs(mods) do
        local n = Context.Number(Context.Call(mod, method))
        -- Negative remaining duration is permanent, never an expiring buff.
        if n and method == "GetRemainingTime" and n < 0 then n = math.huge end
        if n and (best == nil or n > best) then best = n end
    end
    if best == nil and method == "GetStackCount" and Context.Call(unit,"HasModifier",name) == true then
        return Context.Number(Context.Call(unit,"GetModifierStackCount",name,nil))
    end
    return best
end
function Context.HasDispellable(unit, debuff)
    local mods = Context.Call(unit, "FindAllModifiers")
    if type(mods) ~= "table" then return false end
    for _, mod in pairs(mods) do
        if Context.Call(mod, "IsDebuff") == debuff and Context.Call(mod, "IsPurgable") == true then
            return true
        end
    end
    return false
end
function Context.HasShield(unit)
    -- Only explicit measured barrier pools count; modifier names/stacks do not.
    for _, method in ipairs({ "GetAllDamageBarrier", "GetPhysicalDamageBarrier", "GetMagicalDamageBarrier" }) do
        local n = Context.Number(Context.Call(unit, method))
        if n and n > 0 then return true end
    end
    return false
end
-- Return a roster root only after at most eight guarded ownership links.
function Context.OwnerRoot(unit, roster)
    local roots = {}
    for _, root in ipairs(roster or {}) do roots[root] = true end
    local function visit(current, depth, seen)
        if current == nil or seen[current] or Context.Call(current, "IsNull") == true then return nil end
        if roots[current] then return current end
        if depth == 8 then return nil end
        seen[current] = true
        for _, method in ipairs({ "GetOwnerEntity", "GetOwner" }) do
            local root = visit(Context.Call(current, method), depth + 1, seen)
            if root then seen[current] = nil; return root end
        end
        seen[current] = nil
    end
    return visit(unit, 0, {})
end

function Context.IsSummon(unit, rosterOrOwnerRoots)
    if unit == nil or Context.Call(unit, "IsNull") == true then return false end
    if Context.Call(unit, "IsSummoned") == true then return true end
    if type(rosterOrOwnerRoots) ~= "table" then return false end
    local root = rosterOrOwnerRoots[unit] or Context.OwnerRoot(unit, rosterOrOwnerRoots)
    return root ~= nil and root ~= unit
end

-- The third result distinguishes a measured zero from unavailable discovery.
function Context.ExpandBattleUnits(roster)
    roster = roster or {}
    local units, ownerRoots, seen = {}, {}, {}
    for _, unit in ipairs(roster) do
        units[#units + 1] = unit
        ownerRoots[unit], seen[unit] = unit, true
    end
    local anchor = roster[1]
    local team = Context.Call(anchor, "GetTeamNumber")
    local origin = Context.Call(anchor, "GetAbsOrigin")
    if type(FindUnitsInRadius) ~= "function" or team == nil or origin == nil
        or type(FIND_UNITS_EVERYWHERE) ~= "number" or type(DOTA_UNIT_TARGET_TEAM_BOTH) ~= "number"
        or type(DOTA_UNIT_TARGET_HERO) ~= "number" or type(DOTA_UNIT_TARGET_BASIC) ~= "number"
        or type(DOTA_UNIT_TARGET_FLAG_NONE) ~= "number" or type(FIND_ANY_ORDER) ~= "number" then
        return roster, ownerRoots, false
    end
    local flags = DOTA_UNIT_TARGET_FLAG_NONE
    local types = DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC
    local ok, found = pcall(FindUnitsInRadius, team, origin, nil, FIND_UNITS_EVERYWHERE,
        DOTA_UNIT_TARGET_TEAM_BOTH, types,
        flags, FIND_ANY_ORDER, false)
    if not ok or type(found) ~= "table" then return roster, ownerRoots, false end
    for _, unit in pairs(found) do
        if not seen[unit] and Context.Call(unit, "IsNull") ~= true
            and Context.Call(unit, "IsAlive") == true
            and Context.Call(unit, "HasModifier", "modifier_rpg_prepare_bench") ~= true then
            local root = Context.OwnerRoot(unit, roster)
            if root and Context.Call(root, "HasModifier", "modifier_rpg_prepare_bench") ~= true then
                seen[unit], ownerRoots[unit] = true, root
                units[#units + 1] = unit
            end
        end
    end
    return units, ownerRoots, true
end

function Context.CountAround(units, center, radius, allies, logicalSides, ownerRoots)
    radius = Context.Number(radius)
    local function side(unit)
        local root = ownerRoots and ownerRoots[unit] or unit
        if logicalSides ~= nil then return logicalSides[unit] or logicalSides[root] end
        return Context.Call(root, "GetTeamNumber")
    end
    local team = side(center)
    local origin = Context.Call(center, "GetAbsOrigin")
    if radius == nil or radius < 0 or team == nil or origin == nil then return nil end
    local count, seen = 0, {}
    for _, unit in ipairs(units or {}) do
        local otherTeam = side(unit)
        if unit ~= center and not seen[unit] and Context.Call(unit, "IsNull") ~= true
            and Context.Call(unit, "IsAlive") == true and otherTeam ~= nil
            and ((otherTeam == team) == allies) then
            seen[unit] = true
            local position = Context.Call(unit, "GetAbsOrigin")
            local ok, distance = pcall(function() return (position - origin):Length2D() end)
            if not ok or Context.Number(distance) == nil then return nil end
            if distance <= radius then count = count + 1 end
        end
    end
    return count
end
return Context
