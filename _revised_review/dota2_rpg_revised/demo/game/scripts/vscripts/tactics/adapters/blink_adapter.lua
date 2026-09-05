local BlinkAdapter = {}
BlinkAdapter.__index = BlinkAdapter

local function find_blink(caster)
    for slot = 0, 8 do
        local item = caster:GetItemInSlot(slot)
        if item ~= nil and not item:IsNull() and item:GetAbilityName() == "item_blink" then
            return item
        end
    end
    return nil
end

function BlinkAdapter.new()
    return setmetatable({}, BlinkAdapter)
end

function BlinkAdapter:Resolve(caster, action, _ctx)
    local item = find_blink(caster)
    if item == nil then
        return nil, "blink_not_equipped"
    end
    return {
        kind = "item",
        logical_id = action.logical_id or "blink_to_target",
        target_mode = "unit", -- Select a unit, then convert it to a landing point.
        target_team = action.target_team or "enemy",
        cast_type = "point",
        source = item,
        cast_range = tonumber(action.cast_range_override or 1200),
        desired_gap = tonumber(action.desired_gap or 225),
    }
end

function BlinkAdapter:CanExecute(caster, spec, _ctx)
    if caster:IsStunned() or caster:IsRooted() or caster:IsMuted() then
        return false, "blink_caster_disabled"
    end
    if not spec.source:IsCooldownReady() or not spec.source:IsFullyCastable() then
        return false, "blink_not_ready"
    end
    return true, nil
end

function BlinkAdapter:Issue(caster, spec, target, _ctx, order_gate)
    if target == nil or target:IsNull() or not target:IsAlive() then
        return false, "blink_target_invalid"
    end

    local caster_pos = caster:GetAbsOrigin()
    local target_pos = target:GetAbsOrigin()
    local direction = target_pos - caster_pos
    direction.z = 0
    local length = direction:Length2D()
    if length < 1 then
        direction = caster:GetForwardVector()
    else
        direction = direction:Normalized()
    end

    local landing = target_pos - direction * spec.desired_gap
    local max_distance = tonumber(spec.cast_range or 1200)
    if (landing - caster_pos):Length2D() > max_distance then
        landing = caster_pos + direction * max_distance
    end

    order_gate:Execute({
        UnitIndex = caster:entindex(),
        OrderType = DOTA_UNIT_ORDER_CAST_POSITION,
        Position = landing,
        AbilityIndex = spec.source:entindex(),
        Queue = false,
    })
    return true, nil
end

return BlinkAdapter
