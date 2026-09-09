local Special = {}
local function call(unit, method, ...)
    if unit == nil then return nil end
    local readable, fn = pcall(function() return unit[method] end)
    if not readable or type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, unit, ...)
    if ok then return value end
end
local function valid(unit) return unit ~= nil and call(unit, "IsNull") ~= true end
local function distance(a, b)
    local x, y = call(a, "GetAbsOrigin"), call(b, "GetAbsOrigin")
    if x == nil or y == nil then return math.huge end
    return math.sqrt((x.x-y.x)^2 + (x.y-y.y)^2)
end
local object_names = {
    npc_dota_ember_spirit_remnant = true,
    npc_dota_elder_titan_ancestral_spirit = true,
}
function Special.OnSpawn(game, unit)
    if not valid(unit) or not object_names[call(unit, "GetUnitName")] then return false end
    game.specialObjects = game.specialObjects or {}
    game.specialObjects[unit] = true
    return true
end
function Special.Clear(game)
    for unit in pairs(game.specialObjects or {}) do
        if valid(unit) and unit.RemoveSelf ~= nil then unit:RemoveSelf() end
    end
    game.specialObjects = {}
end
function Special.OwnRemnants(ctx)
    local found = {}
    for unit in pairs(ctx.special_objects or {}) do
        if valid(unit) and call(unit,"IsAlive") ~= false and call(unit, "GetUnitName") == "npc_dota_ember_spirit_remnant"
            and (call(unit, "GetOwnerEntity") == ctx.caster or call(unit, "GetOwner") == ctx.caster)
            and call(unit, "GetTeamNumber") == call(ctx.caster, "GetTeamNumber") then
            found[#found+1] = unit
        end
    end
    return found
end
Special.destination_actions = {
    ember_spirit_fire_remnant = true, ember_spirit_activate_fire_remnant = true,
    elder_titan_ancestral_spirit = true, elder_titan_move_spirit = true,
}
Special.destinations = {target=true, self=true, remnant_nearest=true, remnant_farthest=true,
    remnant_near_enemy=true, remnant_safe=true}
function Special.ValidDestination(name, mode)
    return mode == nil or mode == "target" or (Special.destination_actions[name] == true
        and Special.destinations[mode] == true
        and (not mode:match("^remnant_") or name == "ember_spirit_activate_fire_remnant"))
end
-- This selects a native point destination; native cast/location/range checks
-- remain in ActionAdapter. No remnant is created or teleported by this module.
function Special.SelectDestination(rule, spec, ctx, conditions)
    local mode = (rule.action or {}).destination or "target"
    if mode == "target" then return false end
    if not Special.ValidDestination(spec.logical_id, mode) or spec.target_mode ~= "point" then
        return true, nil, nil, "invalid_destination"
    end
    local function result(unit)
        local minimum = tonumber(rule.min_aoe_hits) or 0
        if minimum > 0 then
            local radius = tonumber(call(spec.source or spec.ability,"GetAOERadius")) or 0
            local count = 0
            if radius > 0 then
                for _, enemy in ipairs(ctx.enemies or {}) do
                    if valid(enemy) and call(enemy,"IsAlive") ~= false and call(enemy,"IsOutOfGame") ~= true
                        and call(enemy,"IsInvulnerable") ~= true and distance(unit,enemy) <= radius then count=count+1 end
                end
            end
            if count < minimum then return true,nil,nil,"not_enough_destination_hits" end
        end
        return true,unit:GetAbsOrigin(),unit
    end
    if mode == "self" then
        if not conditions:EvaluateTargetFilters(rule.target_filters, ctx, ctx.caster) then
            return true, nil, nil, "destination_filter_failed"
        end
        return result(ctx.caster)
    end
    local candidates = {}
    for _, remnant in ipairs(Special.OwnRemnants(ctx)) do
        if conditions:EvaluateTargetFilters(rule.target_filters, ctx, remnant) then
            candidates[#candidates+1] = remnant
        end
    end
    local function nearest_enemy(unit)
        local closest = math.huge
        for _, enemy in ipairs(ctx.enemies or {}) do
            if valid(enemy) and call(enemy,"IsAlive") ~= false and call(enemy,"IsOutOfGame") ~= true then
                closest = math.min(closest, distance(unit, enemy))
            end
        end
        return closest
    end
    local function rank(unit)
        if mode == "remnant_farthest" then return -distance(ctx.caster,unit) end
        if mode == "remnant_near_enemy" then return nearest_enemy(unit) end
        if mode == "remnant_safe" then return -nearest_enemy(unit) end
        return distance(ctx.caster,unit)
    end
    table.sort(candidates,function(a,b)
        local x,y = rank(a),rank(b)
        if x ~= y then return x < y end
        local da,db = distance(ctx.caster,a),distance(ctx.caster,b)
        if da ~= db then return da < db end
        return (call(a,"entindex") or 0) < (call(b,"entindex") or 0)
    end)
    local selected = candidates[1]
    if selected == nil then return true,nil,nil,"no_owned_remnant_destination" end
    return result(selected)
end
-- Grab selection is native-nearest, independent of the landing target. Never
-- filter first and claim Tiny will grab a farther preferred unit instead.
function Special.GrabTarget(ctx)
    local spec = ctx.current_action_spec
    if spec == nil or spec.logical_id ~= "tiny_toss" then return nil end
    local radius = tonumber(call(spec.source or spec.ability,"GetSpecialValueFor","grab_radius")) or 0
    if radius <= 0 or type(FindUnitsInRadius) ~= "function" then return nil end
    local ok, units = pcall(FindUnitsInRadius,ctx.caster:GetTeamNumber(),ctx.caster:GetAbsOrigin(),nil,radius,
        DOTA_UNIT_TARGET_TEAM_BOTH or 3,(DOTA_UNIT_TARGET_HERO or 1)+(DOTA_UNIT_TARGET_BASIC or 2),
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 16,FIND_CLOSEST or 1,false)
    if not ok or type(units) ~= "table" then return nil end
    local candidates = {}
    for _, unit in pairs(units) do
        if unit ~= ctx.caster and valid(unit) and call(unit,"IsAlive") ~= false
            and call(unit,"IsInvulnerable") ~= true and call(unit,"IsOutOfGame") ~= true
            and call(unit,"IsBuilding") ~= true and call(unit,"IsOther") ~= true
            and distance(ctx.caster,unit) <= radius then candidates[#candidates+1] = unit end
    end
    table.sort(candidates,function(a,b)
        local da,db = distance(ctx.caster,a),distance(ctx.caster,b)
        if da ~= db then return da < db end
        return (call(a,"entindex") or 0) < (call(b,"entindex") or 0)
    end)
    local nearest = candidates[1]
    -- Ambiguous same-distance candidates and protected units fail closed.
    if nearest == nil or call(nearest,"IsRoshan") == true or call(nearest,"IsAncient") == true
        or (candidates[2] ~= nil and math.abs(distance(ctx.caster,nearest)-distance(ctx.caster,candidates[2])) < 0.01) then return nil end
    return nearest
end
return Special
