local Conditions = require("tactics/condition_registry")
local VectorTarget = {}

local function valid_entity(entity)
    local ok, valid = pcall(Conditions.IsValidEntity, entity)
    return ok and valid
end

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function VectorTarget.IsPoint(point)
    local ok, valid = pcall(function()
        return finite(point.x) and finite(point.y) and finite(point.z)
    end)
    return ok and valid
end

function VectorTarget.NativeMode(source)
    if not valid_entity(source) then return nil end
    local ok, behavior = pcall(function()
        return source.GetBehaviorInt ~= nil and source:GetBehaviorInt() or source:GetBehavior()
    end)
    if not ok or not finite(behavior) or bit == nil or DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING == nil then return nil end
    local function has(flag) return flag ~= nil and bit.band(behavior, flag) == flag end
    if not has(DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING) then return nil end
    if has(DOTA_ABILITY_BEHAVIOR_POINT) then return "point" end
    if has(DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) then
        if source.GetAbilityTargetType ~= nil and DOTA_UNIT_TARGET_TREE ~= nil
            and source:GetAbilityTargetType() == DOTA_UNIT_TARGET_TREE then return nil end
        return "unit"
    end
end

function VectorTarget.Build(caster, primary)
    if not valid_entity(caster) or not valid_entity(primary) then return nil end
    local ok, origin, start = pcall(function() return caster:GetAbsOrigin(), primary:GetAbsOrigin() end)
    if not ok then return nil end
    if not VectorTarget.IsPoint(origin) or not VectorTarget.IsPoint(start) then return nil end
    local dx, dy = start.x - origin.x, start.y - origin.y
    local length = math.sqrt(dx * dx + dy * dy)
    if not finite(length) or length <= 0 then return nil end
    local finish = Vector(start.x + dx / length * 150, start.y + dy / length * 150, start.z)
    if not VectorTarget.IsPoint(finish) then return nil end
    return { start = start, finish = finish, primary = primary }
end

function VectorTarget.IsDescriptor(target)
    return type(target) == "table" and VectorTarget.IsPoint(target.start)
        and VectorTarget.IsPoint(target.finish) and valid_entity(target.primary)
        and (target.start.x ~= target.finish.x or target.start.y ~= target.finish.y)
end

function VectorTarget.EntityIndex(entity)
    if not valid_entity(entity) then return nil end
    local ok, index = pcall(function() return entity:entindex() end)
    if ok and finite(index) and index >= 0 and index == math.floor(index) then return index end
end

return VectorTarget
