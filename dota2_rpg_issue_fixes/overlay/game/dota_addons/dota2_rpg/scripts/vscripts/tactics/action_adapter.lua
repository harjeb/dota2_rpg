local Conditions = require("tactics/condition_registry")
local VectorTarget = require("tactics/vector_target")
local Behavior = require("tactics/ability_behavior")
local ActionAdapter = {}
ActionAdapter.__index = ActionAdapter

local function is_valid(entity)
    return Conditions.IsValidEntity(entity)
end

local function release_fallback_target(caster)
    if caster.rpg_fallback_force_target ~= nil or caster.rpg_tactic_force_target ~= nil then
        if caster.SetForceAttackTarget ~= nil then caster:SetForceAttackTarget(nil) end
        caster.rpg_fallback_force_target = nil
        caster.rpg_tactic_force_target = nil
    end
end

local function own_attack_target(caster, spec, target)
    if spec.kind == "attack" and caster.GetUnitName ~= nil
        and caster:GetUnitName():match("^npc_dota_neutral_")
        and is_valid(target) and caster.SetForceAttackTarget ~= nil then
        caster:SetForceAttackTarget(target)
        caster.rpg_fallback_force_target = nil
        caster.rpg_tactic_force_target = target
    else
        release_fallback_target(caster)
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

local has_flag = Behavior.HasFlag
local get_behavior = Behavior.Read

local function infer_cast_type(ability)
    local behavior = get_behavior(ability)
    if has_flag(behavior, DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING) then
        return VectorTarget.NativeMode(ability) ~= nil and "vector" or nil
    end
    if ability.GetAbilityTargetType ~= nil and DOTA_UNIT_TARGET_TREE ~= nil
        and ability:GetAbilityTargetType() == DOTA_UNIT_TARGET_TREE
        and not has_flag(behavior, DOTA_ABILITY_BEHAVIOR_POINT) then return nil end
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
    if not is_valid(ability) then
        return 0
    end
    local origin = caster:GetAbsOrigin()
    -- GetCastRange accepts an entity, not the Vector selected for point spells.
    if target ~= nil and target.GetAbsOrigin == nil then
        target = nil
    end
    local function read_range(method)
        if ability[method] == nil then return nil end
        local ok, value = pcall(ability[method], ability, origin, target)
        return ok and tonumber(value) or nil
    end
    local value = read_range("GetEffectiveCastRange")
    if value == nil or value <= 0 then value = read_range("GetCastRange") end
    if value ~= nil and value > 0 then return value end
    -- Native data can store range in AbilityValues.AbilityCastRange,
    -- not the legacy top-level cast-range field. Resolve that value when the
    -- native range accessor gives zero; never invent a fixed range.
    if ability.GetSpecialValueFor ~= nil then
        local ok, special = pcall(ability.GetSpecialValueFor, ability, "AbilityCastRange")
        -- Time Walk declares its native travel distance in AbilityValues.range.
        -- Other abilities may use "range" for unrelated effects; keep this explicit.
        if (not ok or tonumber(special) == nil or tonumber(special) <= 0)
            and ability.GetAbilityName ~= nil
            and ability:GetAbilityName() == "faceless_void_time_walk" then
            ok, special = pcall(ability.GetSpecialValueFor, ability, "range")
        end
        if ok and tonumber(special) ~= nil and tonumber(special) > 0 then
            local bonus = caster.GetCastRangeBonus ~= nil and caster:GetCastRangeBonus() or 0
            return tonumber(special) + (tonumber(bonus) or 0)
        end
    end
    return math.max(0, value or 0)
end

local function ability_aoe_radius(ability)
    if ability.GetAOERadius ~= nil then
        local ok, radius = pcall(ability.GetAOERadius, ability)
        if ok and tonumber(radius) ~= nil and radius > 0 then return radius end
    end
    -- Do not guess a circle from damage_radius/width specials: line and cone
    -- spells must not be counted as circular AoEs.
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

    local native_cast_type = infer_cast_type(source)
    if native_cast_type == nil then return nil, "special_adapter_required" end
    if action.cast_type == "tree"
        or action.target_mode == "tree"
        or action.target_mode == "facing" then return nil, "special_adapter_required" end
    local preference = action.cast_preference
    if preference ~= nil and preference ~= "auto" then
        if native_cast_type == "vector" then return nil, "unsupported_cast_preference" end
        local flag = preference == "unit" and DOTA_ABILITY_BEHAVIOR_UNIT_TARGET
            or preference == "point" and DOTA_ABILITY_BEHAVIOR_POINT
        if native_cast_type == "toggle" or flag == nil or not has_flag(get_behavior(source),flag) then
            return nil, "unsupported_cast_preference"
        end
        native_cast_type = preference
    end
    if native_cast_type == "unit" and source.GetAbilityTargetType ~= nil
        and DOTA_UNIT_TARGET_TREE ~= nil and source:GetAbilityTargetType() == DOTA_UNIT_TARGET_TREE then
        return nil, "special_adapter_required"
    end
    local cast_type = action.cast_type or native_cast_type
    if cast_type ~= native_cast_type then return nil, "unsupported_cast_type" end
    local target_mode = action.target_mode or cast_type
    if target_mode ~= cast_type and not (cast_type == "unit" and target_mode == "self") then
        return nil, "unsupported_target_mode"
    end

    return {
        kind = action.kind,
        logical_id = logical_id,
        target_mode = target_mode,
        target_team = action.target_team,
        cast_type = cast_type,
        vector_mode = cast_type == "vector" and VectorTarget.NativeMode(source) or nil,
        desired_toggle_state = action.desired_toggle_state ~= false,
        aoe_radius = ability_aoe_radius(source),
        cast_range_override = tonumber(action.cast_range_override),
        cast_range = tonumber(action.cast_range_override) or ability_cast_range(caster, source, nil),
        source = source,
        ability = source,
    }
end

function ActionAdapter:IsValidTarget(caster, spec, target)
    if not is_valid(target) or (target.IsAlive ~= nil and not target:IsAlive()) then
        return false
    end
    if spec.kind == "attack" then
        return not (target.IsInvulnerable ~= nil and target:IsInvulnerable())
            and not (target.IsAttackImmune ~= nil and target:IsAttackImmune())
            and not (target.IsOutOfGame ~= nil and target:IsOutOfGame())
    end
    if spec.cast_type == "vector" and spec.vector_mode == "point" then
        return not (target.IsInvulnerable ~= nil and target:IsInvulnerable())
            and not (target.IsOutOfGame ~= nil and target:IsOutOfGame())
    end
    if spec.cast_type ~= "unit" and not (spec.cast_type == "vector" and spec.vector_mode == "unit") then return true end
    local source = spec.source
    if source == nil then return false end
    if UnitFilter ~= nil and source.GetAbilityTargetTeam ~= nil
        and source.GetAbilityTargetType ~= nil and source.GetAbilityTargetFlags ~= nil
        and caster.GetTeamNumber ~= nil then
        local ok, result = pcall(UnitFilter, target, source:GetAbilityTargetTeam(),
            source:GetAbilityTargetType(), source:GetAbilityTargetFlags(), caster:GetTeamNumber())
        if not ok or result ~= (UF_SUCCESS or 0) then return false end
    end
    if source.CastFilterResultTarget ~= nil then
        local ok, result = pcall(source.CastFilterResultTarget, source, target)
        if not ok or result ~= (UF_SUCCESS or 0) then return false end
    end
    return true
end

function ActionAdapter:CanExecute(caster, spec, ctx)
    if not is_valid(caster) or caster:IsAlive() == false then
        return false, "caster_invalid"
    end

    if caster.IsChanneling ~= nil and caster:IsChanneling() then return false, "channeling" end

    local custom = self.custom[spec.logical_id]
    if custom ~= nil and custom.CanExecute ~= nil then
        return custom:CanExecute(caster, spec, ctx)
    end

    if spec.kind == "attack" then
        if (caster.IsDisarmed ~= nil and caster:IsDisarmed()) or (caster.IsStunned ~= nil and caster:IsStunned()) then
            return false, "cannot_attack"
        end
        return true, nil
    end
    if spec.kind == "move" or spec.kind == "wait" then
        return true, nil
    end

    local source = spec.source
    if not is_valid(source) then
        return false, "action_source_missing"
    end

    if spec.kind == "ability" and source:GetLevel() <= 0 then
        return false, "ability_unlearned"
    end
    if source.IsHidden ~= nil and source:IsHidden() then
        return false, "action_hidden"
    end
    if source.IsPassive ~= nil and source:IsPassive() then
        return false, "action_passive"
    end
    if source.IsActivated ~= nil and not source:IsActivated() then
        return false, "action_deactivated"
    end
    local turning_off = spec.cast_type == "toggle" and spec.desired_toggle_state == false
        and source.GetToggleState ~= nil and source:GetToggleState()
    local maxCharges = spec.kind == "ability" and source.GetMaxAbilityCharges ~= nil
        and tonumber(source:GetMaxAbilityCharges(source:GetLevel())) or 0
    local charges = maxCharges > 0 and source.GetCurrentAbilityCharges ~= nil
        and tonumber(source:GetCurrentAbilityCharges()) or nil
    if not turning_off and charges ~= nil and charges <= 0 then
        return false, "no_charges"
    end
    -- A charge-restoration cooldown does not prevent spending a remaining charge.
    if not turning_off and (charges == nil or charges <= 0) and source.IsCooldownReady ~= nil and not source:IsCooldownReady() then
        return false, "cooldown"
    end
    if not turning_off and source.IsFullyCastable ~= nil and not source:IsFullyCastable() then
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
    if spec.cast_range_override ~= nil then
        return spec.cast_range_override
    end
    if spec.source ~= nil then
        return ability_cast_range(caster, spec.source, target)
    end
    return tonumber(spec.cast_range or 0)
end

function ActionAdapter:IsInRange(caster, spec, target_or_point)
    if spec.cast_type == "toggle" or spec.target_mode == "none" or spec.target_mode == "self" or spec.kind == "wait" then
        return true
    end

    if spec.cast_type == "vector" then
        local primary = type(target_or_point) == "table" and target_or_point.primary or nil
        local point = primary ~= nil and primary:GetAbsOrigin() or target_or_point
        if point ~= nil and point.GetAbsOrigin ~= nil then primary, point = point, point:GetAbsOrigin() end
        if not VectorTarget.IsPoint(point) or not VectorTarget.IsPoint(caster:GetAbsOrigin()) then return false end
        local range = ability_cast_range(caster, spec.source, spec.vector_mode == "unit" and primary or nil)
        local origin = caster:GetAbsOrigin()
        local dx, dy = origin.x - point.x, origin.y - point.y
        return range == range and range < math.huge and math.sqrt(dx * dx + dy * dy) <= range
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

local function unsupported_geometry(spec)
    return spec.cast_type == "tree" or spec.cast_type == "facing"
        or spec.target_mode == "tree" or spec.target_mode == "facing"
end

function ActionAdapter:Issue(caster, spec, target_or_point, ctx)
    if caster.IsChanneling ~= nil and caster:IsChanneling() then return false, "channeling" end
    if unsupported_geometry(spec) then return false, "special_adapter_required" end
    if spec.cast_type == "vector" then
        if not is_valid(caster) or (caster.IsAlive ~= nil and not caster:IsAlive()) then return false, "caster_invalid" end
        local target = target_or_point
        local mode = VectorTarget.NativeMode(spec.source)
        if mode == nil or mode ~= spec.vector_mode or not VectorTarget.IsDescriptor(target) then
            return false, "invalid_vector_target"
        end
        local first = DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION
        local second
        if mode == "point" then second = DOTA_UNIT_ORDER_CAST_POSITION else second = DOTA_UNIT_ORDER_CAST_TARGET end
        local function enum(value) return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value) end
        local unit_index, ability_index, target_index = VectorTarget.EntityIndex(caster),
            VectorTarget.EntityIndex(spec.source), VectorTarget.EntityIndex(target.primary)
        if not enum(first) or not enum(second) or unit_index == nil or ability_index == nil or target_index == nil then
            return false, "vector_native_contract_unavailable"
        end
        if not self:IsValidTarget(caster, spec, target.primary) then return false, "invalid_native_target" end
        local fresh = VectorTarget.Build(caster, target.primary)
        if fresh == nil or fresh.start.x ~= target.start.x or fresh.start.y ~= target.start.y
            or fresh.start.z ~= target.start.z or fresh.finish.x ~= target.finish.x
            or fresh.finish.y ~= target.finish.y or fresh.finish.z ~= target.finish.z then return false, "stale_vector_target" end
        if mode == "point" and spec.source.CastFilterResultLocation ~= nil then
            local ok, result = pcall(spec.source.CastFilterResultLocation, spec.source, target.start)
            if not ok or result ~= (UF_SUCCESS or 0) then return false, "invalid_native_location" end
        end
        if not self:IsInRange(caster, spec, target) then return false, "out_of_range" end
        local setup = {UnitIndex=unit_index, AbilityIndex=ability_index, OrderType=first, Position=target.finish, Queue=false}
        local cast = {UnitIndex=unit_index, AbilityIndex=ability_index, OrderType=second, Queue=false}
        if mode == "point" then cast.Position = target.start else cast.TargetIndex = target_index end
        release_fallback_target(caster)
        self.order_gate:Execute(setup)
        self.order_gate:Execute(cast)
        return true, nil
    end
    if (spec.cast_type == "unit" or spec.kind == "attack") and not self:IsValidTarget(caster, spec, target_or_point) then
        return false, "invalid_native_target"
    end
    if spec.cast_type == "point" and spec.source ~= nil and spec.source.CastFilterResultLocation ~= nil then
        local ok, result = pcall(spec.source.CastFilterResultLocation, spec.source, target_or_point)
        if not ok or result ~= (UF_SUCCESS or 0) then return false, "invalid_native_location" end
    end
    own_attack_target(caster, spec, target_or_point)
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
        order.Position = target_or_point ~= nil and target_or_point.GetAbsOrigin ~= nil
            and target_or_point:GetAbsOrigin() or target_or_point
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
    if caster.IsChanneling ~= nil and caster:IsChanneling() then return false, "channeling" end
    if unsupported_geometry(spec) then return false, "special_adapter_required" end
    if spec.cast_type == "vector" then
        if VectorTarget.NativeMode(spec.source) ~= spec.vector_mode or spec.vector_mode == nil
            or not VectorTarget.IsDescriptor(target_or_point) then return false, "invalid_vector_target" end
        target_or_point = target_or_point.primary
    end
    own_attack_target(caster, spec, target_or_point)
    local order = {
        UnitIndex = caster:entindex(),
        Queue = false,
    }

    if target_or_point ~= nil and target_or_point.GetAbsOrigin ~= nil then
        order.OrderType = spec.kind == "attack" and DOTA_UNIT_ORDER_ATTACK_TARGET or DOTA_UNIT_ORDER_MOVE_TO_TARGET
        order.TargetIndex = target_or_point:entindex()
    else
        order.OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION
        order.Position = target_or_point
    end

    self.order_gate:Execute(order)
    return true
end

return ActionAdapter
