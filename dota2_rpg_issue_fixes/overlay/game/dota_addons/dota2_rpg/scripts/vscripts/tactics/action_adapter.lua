local Conditions = require("tactics/condition_registry")

local ActionAdapter = {}
ActionAdapter.__index = ActionAdapter

local function is_valid(entity)
    return Conditions.IsValidEntity(entity)
end

local function release_fallback_target(caster)
    if caster.rpg_fallback_force_target ~= nil then
        if caster.SetForceAttackTarget ~= nil then caster:SetForceAttackTarget(nil) end
        caster.rpg_fallback_force_target = nil
    end
end

local function find_item_by_name(unit, item_name)
    if unit == nil or unit.GetItemInSlot == nil then
        return nil
    end
    for slot = 0, 8 do
        local item = unit:GetItemInSlot(slot)
        if is_valid(item) and item:GetAbilityName() == item_name then
            return item
        end
    end
    return nil
end

local function has_flag(value, flag)
    if value == nil or flag == nil or bit == nil then
        return false
    end
    return bit.band(value, flag) == flag
end

local function get_behavior(ability)
    if ability.GetBehaviorInt ~= nil then
        return ability:GetBehaviorInt()
    end
    if ability.GetBehavior ~= nil then
        return ability:GetBehavior()
    end
    return 0
end

local function infer_cast_type(ability)
    local behavior = get_behavior(ability)
    if has_flag(behavior, DOTA_ABILITY_BEHAVIOR_TOGGLE) then
        return "toggle"
    end
    if has_flag(behavior, DOTA_ABILITY_BEHAVIOR_POINT) then
        return "point"
    end
    if has_flag(behavior, DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) then
        return "unit"
    end
    if has_flag(behavior, DOTA_ABILITY_BEHAVIOR_NO_TARGET) then
        return "none"
    end
    return nil
end

local function ability_cast_range(caster, ability, target)
    if not is_valid(ability) or ability.GetCastRange == nil then
        return 0
    end
    local origin = caster:GetAbsOrigin()
    local ok, value = pcall(function()
        return ability:GetCastRange(origin, target)
    end)
    if ok and value ~= nil then
        return math.max(0, tonumber(value) or 0)
    end
    return 0
end

function ActionAdapter.new(order_gate)
    return setmetatable({
        order_gate = assert(order_gate, "order_gate is required"),
        custom = {},
    }, ActionAdapter)
end

function ActionAdapter:Register(logical_id, adapter)
    assert(type(logical_id) == "string" and logical_id ~= "", "logical_id is required")
    assert(type(adapter) == "table", "adapter must be a table")
    self.custom[logical_id] = adapter
end

function ActionAdapter:Resolve(caster, action, ctx)
    if action == nil or action.kind == nil then
        return nil, "invalid_action"
    end

    if action.kind == "attack" then
        return {
            kind = "attack",
            logical_id = action.logical_id or "basic_attack",
            target_mode = "unit",
            target_team = action.target_team or "enemy",
            cast_range = caster.Script_GetAttackRange ~= nil and caster:Script_GetAttackRange() or 150,
            source = nil,
        }
    end

    if action.kind == "move" then
        return {
            kind = "move",
            logical_id = action.logical_id or "move",
            target_mode = action.target_mode or "point",
            target_team = action.target_team,
            cast_range = 0,
            source = nil,
        }
    end

    if action.kind == "wait" then
        return {
            kind = "wait",
            logical_id = action.logical_id or "wait",
            target_mode = "none",
            wait_duration = tonumber(action.duration or 0.35),
            source = nil,
        }
    end

    local logical_id = action.logical_id or action.name
    local custom = self.custom[logical_id]
    if custom ~= nil and custom.Resolve ~= nil then
        return custom:Resolve(caster, action, ctx)
    end

    local source = nil
    if action.kind == "ability" then
        local ability_name = action.name
        if ability_name == nil and ctx.resolve_action_name ~= nil then
            ability_name = ctx.resolve_action_name(caster, logical_id)
        end
        source = ability_name ~= nil and caster:FindAbilityByName(ability_name) or nil
    elseif action.kind == "item" then
        local item_name = action.name
        if item_name == nil and ctx.resolve_action_name ~= nil then
            item_name = ctx.resolve_action_name(caster, logical_id)
        end
        source = item_name ~= nil and find_item_by_name(caster, item_name) or nil
    else
        return nil, "unsupported_action_kind:" .. tostring(action.kind)
    end

    if not is_valid(source) then
        return nil, "action_source_missing"
    end

    local cast_type = action.cast_type or infer_cast_type(source)
    if cast_type == nil then
        return nil, "special_adapter_required"
    end

    return {
        kind = action.kind,
        logical_id = logical_id,
        target_mode = action.target_mode or cast_type,
        target_team = action.target_team,
        cast_type = cast_type,
        desired_toggle_state = action.desired_toggle_state,
        aoe_radius = tonumber(action.aoe_radius or 0),
        cast_range = tonumber(action.cast_range_override) or ability_cast_range(caster, source, nil),
        source = source,
    }
end

function ActionAdapter:CanExecute(caster, spec, ctx)
    if not is_valid(caster) or caster:IsAlive() == false then
        return false, "caster_invalid"
    end

    local custom = self.custom[spec.logical_id]
    if custom ~= nil and custom.CanExecute ~= nil then
        return custom:CanExecute(caster, spec, ctx)
    end

    if spec.kind == "attack" or spec.kind == "move" or spec.kind == "wait" then
        return true, nil
    end

    local source = spec.source
    if not is_valid(source) then
        return false, "action_source_missing"
    end

    if spec.kind == "ability" and source:GetLevel() <= 0 then
        return false, "ability_unlearned"
    end
    if source.IsActivated ~= nil and not source:IsActivated() then
        return false, "action_deactivated"
    end
    if source.IsCooldownReady ~= nil and not source:IsCooldownReady() then
        return false, "cooldown"
    end
    if source.IsFullyCastable ~= nil and not source:IsFullyCastable() then
        return false, "not_fully_castable"
    end
    if caster.IsStunned ~= nil and caster:IsStunned() then
        return false, "caster_stunned"
    end
    if spec.kind == "ability" and caster.IsSilenced ~= nil and caster:IsSilenced() then
        return false, "caster_silenced"
    end
    if spec.kind == "item" and caster.IsMuted ~= nil and caster:IsMuted() then
        return false, "caster_muted"
    end

    if spec.cast_type == "toggle" and spec.desired_toggle_state ~= nil
        and source.GetToggleState ~= nil
        and source:GetToggleState() == spec.desired_toggle_state then
        return false, "toggle_already_in_desired_state"
    end

    return true, nil
end

function ActionAdapter:GetRequiredRange(caster, spec, target)
    if spec.kind == "attack" then
        return tonumber(spec.cast_range or 150)
    end
    if spec.kind == "move" or spec.kind == "wait" or spec.target_mode == "none" then
        return 0
    end
    if spec.source ~= nil then
        return ability_cast_range(caster, spec.source, target)
    end
    return tonumber(spec.cast_range or 0)
end

function ActionAdapter:IsInRange(caster, spec, target_or_point)
    if spec.target_mode == "none" or spec.target_mode == "self" or spec.kind == "wait" then
        return true
    end

    local range = self:GetRequiredRange(caster, spec, target_or_point)
    local point = target_or_point
    if target_or_point ~= nil and target_or_point.GetAbsOrigin ~= nil then
        point = target_or_point:GetAbsOrigin()
    end
    if point == nil then
        return false
    end

    local distance = (caster:GetAbsOrigin() - point):Length2D()
    local hull_buffer = caster.GetHullRadius ~= nil and caster:GetHullRadius() or 0
    return distance <= range + hull_buffer + 24
end

function ActionAdapter:Issue(caster, spec, target_or_point, ctx)
    release_fallback_target(caster)
    local custom = self.custom[spec.logical_id]
    if custom ~= nil and custom.Issue ~= nil then
        return custom:Issue(caster, spec, target_or_point, ctx, self.order_gate)
    end

    if spec.kind == "wait" then
        return true, "wait"
    end

    local order = {
        UnitIndex = caster:entindex(),
        Queue = false,
    }

    if spec.kind == "attack" then
        order.OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET
        order.TargetIndex = target_or_point:entindex()
    elseif spec.kind == "move" then
        if target_or_point ~= nil and target_or_point.GetAbsOrigin ~= nil then
            order.OrderType = DOTA_UNIT_ORDER_MOVE_TO_TARGET
            order.TargetIndex = target_or_point:entindex()
        else
            order.OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION
            order.Position = target_or_point
        end
    elseif spec.cast_type == "unit" then
        order.OrderType = DOTA_UNIT_ORDER_CAST_TARGET
        order.TargetIndex = target_or_point:entindex()
        order.AbilityIndex = spec.source:entindex()
    elseif spec.cast_type == "point" then
        order.OrderType = DOTA_UNIT_ORDER_CAST_POSITION
        order.Position = target_or_point
        order.AbilityIndex = spec.source:entindex()
    elseif spec.cast_type == "none" then
        order.OrderType = DOTA_UNIT_ORDER_CAST_NO_TARGET
        order.AbilityIndex = spec.source:entindex()
    elseif spec.cast_type == "toggle" then
        order.OrderType = DOTA_UNIT_ORDER_CAST_TOGGLE
        order.AbilityIndex = spec.source:entindex()
    else
        return false, "unsupported_cast_type:" .. tostring(spec.cast_type)
    end

    self.order_gate:Execute(order)
    return true, nil
end

function ActionAdapter:IssueApproach(caster, spec, target_or_point)
    release_fallback_target(caster)
    local order = {
        UnitIndex = caster:entindex(),
        Queue = false,
    }

    if target_or_point ~= nil and target_or_point.GetAbsOrigin ~= nil then
        order.OrderType = DOTA_UNIT_ORDER_MOVE_TO_TARGET
        order.TargetIndex = target_or_point:entindex()
    else
        order.OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION
        order.Position = target_or_point
    end

    self.order_gate:Execute(order)
    return true
end

return ActionAdapter
