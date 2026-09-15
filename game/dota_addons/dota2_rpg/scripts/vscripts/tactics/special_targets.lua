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
-- 点目标落点偏移：以规则选中的敌人锚点为参照计算施法位置。这些模式只负责选点，
-- 原生施法位置/射程校验仍由 ActionAdapter 完成。
Special.offset_destinations = {
    away_from_target = true,
    target_front = true,
    target_behind = true,
    around_target = true,
}
Special.destinations = {target=true, self=true, remnant_nearest=true, remnant_farthest=true,
    remnant_near_enemy=true, remnant_safe=true, away_from_target=true, target_front=true,
    target_behind=true, around_target=true}
function Special.ValidDestination(name, mode)
    if mode == nil or mode == "" or mode == "target" then return true end
    -- 偏移落点对任意动作开放；非点目标动作在运行时按无效落点拒绝。
    if type(mode) == "string" and Special.offset_destinations[mode] then return true end
    return Special.destination_actions[name] == true and Special.destinations[mode] == true
        and (not mode:match("^remnant_") or name == "ember_spirit_activate_fire_remnant")
end
-- This selects a native point destination; native cast/location/range checks
-- remain in ActionAdapter. No remnant is created or teleported by this module.
function Special.SelectDestination(rule, spec, ctx, conditions)
    local mode = (rule.action or {}).destination or "target"
    if mode == "target" then return false end
    -- 偏移落点必须先由目标选择器选出锚点，交给战术引擎处理；这里直接调用视为无效。
    if Special.offset_destinations[mode] then
        return true, nil, nil, "offset_destination_requires_engine"
    end
    if not Special.ValidDestination(spec.logical_id, mode) or spec.target_mode ~= "point" then
        return true, nil, nil, "invalid_destination"
    end
    local function result(unit)
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
-- 偏移落点：away_from_target 从施法者背向敌人起算，贴近边缘时扫描可站立方向；
-- target_front/target_behind 以敌人当前朝向为轴，around_target 取"你→敌人"连线的
-- 敌人近侧。后三者相对敌人量取距离，不因施法者更近而收缩。
local OFFSET_SWEEP = {0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 90, -90}
local DEFAULT_OFFSET_DISTANCE = 400

local function horizontal_direction(from, to)
    local a, b = call(from, "GetAbsOrigin"), call(to, "GetAbsOrigin")
    if a == nil or b == nil then return nil end
    local dx, dy = b.x - a.x, b.y - a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.001 then return nil end
    return dx / length, dy / length
end

local function facing_direction(unit)
    local forward = call(unit, "GetForwardVector")
    if forward == nil then return nil end
    local dx, dy = tonumber(forward.x), tonumber(forward.y)
    if dx == nil or dy == nil then return nil end
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.001 then return nil end
    return dx / length, dy / length
end

local function rotated_point(from, dir_x, dir_y, degrees, distance, z)
    local radians = degrees * math.pi / 180
    local cos, sin = math.cos(radians), math.sin(radians)
    local x = dir_x * cos - dir_y * sin
    local y = dir_x * sin + dir_y * cos
    return Vector(from.x + x * distance, from.y + y * distance, z)
end

local function walkable(from, point)
    if GridNav == nil or GridNav.CanFindPath == nil then return true end
    local ok, path = pcall(GridNav.CanFindPath, GridNav, from, point)
    return not ok or path ~= false
end

local function native_legal_location(source, point)
    if source == nil or source.CastFilterResultLocation == nil then return true end
    local ok, result = pcall(source.CastFilterResultLocation, source, point)
    return ok and result == (UF_SUCCESS or 0)
end

-- 上限只在背向自身移动时生效：远离越彻底越好，但没有理由超过施法距离。
local function backstep_distance(wanted, range)
    local distance = wanted > 0 and wanted or (range or DEFAULT_OFFSET_DISTANCE)
    if range ~= nil then distance = math.min(distance, range) end
    return math.max(0, distance)
end

function Special.OffsetDestination(mode, caster, anchor, spec, action, actions)
    if spec == nil or spec.target_mode ~= "point" then return nil, "invalid_destination" end
    if not valid(caster) or not valid(anchor) then return nil, "invalid_offset_anchor" end
    local origin, center = call(caster, "GetAbsOrigin"), call(anchor, "GetAbsOrigin")
    if origin == nil or center == nil then return nil, "invalid_offset_anchor" end
    local range = nil
    if actions ~= nil and actions.GetRequiredRange ~= nil then
        range = tonumber(actions:GetRequiredRange(caster, spec, nil))
        if range ~= nil and (range <= 0 or range ~= range or range == math.huge) then range = nil end
    end
    local wanted = tonumber(action and action.destination_distance) or 0
    local source = spec.source or spec.ability
    if mode == "away_from_target" then
        local dir_x, dir_y = horizontal_direction(anchor, caster)
        if dir_x == nil then dir_x, dir_y = facing_direction(caster) end
        if dir_x == nil then return nil, "invalid_offset_direction" end
        local distance = backstep_distance(wanted, range)
        if distance <= 0 then return nil, "invalid_backstep_distance" end
        for _, degrees in ipairs(OFFSET_SWEEP) do
            local point = rotated_point(origin, dir_x, dir_y, degrees, distance, origin.z)
            if walkable(origin, point) and native_legal_location(source, point) then return point, nil end
        end
        return nil, "no_away_destination"
    end
    local dir_x, dir_y
    if mode == "around_target" then
        local ux, uy = horizontal_direction(caster, anchor)
        if ux == nil then return nil, "invalid_offset_direction" end
        dir_x, dir_y = -ux, -uy
    elseif mode == "target_front" or mode == "target_behind" then
        dir_x, dir_y = facing_direction(anchor)
        if dir_x == nil then return nil, "invalid_offset_direction" end
        if mode == "target_behind" then dir_x, dir_y = -dir_x, -dir_y end
    else
        return nil, "unsupported_offset_mode"
    end
    local distance = wanted > 0 and wanted or DEFAULT_OFFSET_DISTANCE
    local point = Vector(center.x + dir_x * distance, center.y + dir_y * distance, center.z)
    if not walkable(origin, point) then return nil, "no_offset_destination" end
    if not native_legal_location(source, point) then return nil, "invalid_native_location" end
    return point, nil
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
