local Conditions = require("tactics/condition_registry")
local VectorTarget = require("tactics/vector_target")
local Behavior = require("tactics/ability_behavior")
local NativeTargeting = require("tactics/native_targeting")
local NeutralAttack = require("tactics/neutral_attack")
local SustainedCast = require("tactics/sustained_cast")
local Capability = require("tactics/ability_capability")
local Lifecycle = require("tactics/action_lifecycle")
local State = require("tactics/state_controller")
local ActionAdapter = {}
ActionAdapter.__index = ActionAdapter

local function is_valid(entity)
    return Conditions.IsValidEntity(entity)
end

local function release_fallback_target(caster)
    NeutralAttack.Release(caster)
end

local function own_attack_target(caster, spec, target)
    if spec.kind ~= "attack" or not NeutralAttack.IsNeutral(caster) then
        release_fallback_target(caster)
    end
end

local function submit_order(caster, spec, target, gate, order)
    if spec.kind == "attack" and NeutralAttack.IsNeutral(caster) then
        return NeutralAttack.Submit(caster, target, "tactic", function() return gate:Execute(order) end)
    end
    if gate:Execute(order) == false then return false, "order_rejected" end
    return true
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

-- Native destination/travel ranges whose values are outside AbilityCastRange.
local special_cast_ranges = {
    faceless_void_time_walk = "range",
    dawnbreaker_celestial_hammer = "range",
    puck_waning_rift = "max_distance",
    magnataur_skewer = "range",
    void_spirit_astral_step = "max_travel_distance",
    monkey_king_wukongs_command = "cast_range",
}
-- Directional orders can report zero cast range. Use their native effect reach
-- to choose a nearby enemy direction; cast-range items do not enlarge a melee
-- sweep, fixed arc, or arrow's attack-based reach.
local special_effect_reaches = {
    dawnbreaker_fire_wreath = "swipe_radius",
    mars_gods_rebuke = "radius",
    mars_spear = "spear_range",
    clinkz_burning_barrage = "range",
    phoenix_icarus_dive = "dash_length",
    drow_ranger_multishot = "arrow_range_base",
}
-- Zero is also the native representation of these reviewed global casts.
-- Never turn an arbitrary zero-range or self-centered ability into a global one.
local global_casts = {
    elder_titan_move_spirit = true,
    rattletrap_rocket_flare = true,
    furion_wrath_of_nature = true,
    treant_living_armor = true,
    storm_spirit_ball_lightning = true,
}

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
    local native_range = read_range("GetCastRange")
    local name = ability.GetAbilityName ~= nil and ability:GetAbilityName() or ""
    if global_casts[name] and native_range ~= nil and native_range <= 0 then
        return math.huge
    end
    if native_range ~= nil and native_range <= 0
        and (special_cast_ranges[name] or special_effect_reaches[name]) then
        -- Some native effective accessors return only the caster's range bonus
        -- when their ordinary range is zero. That is not the spell's full reach.
        local bonus = caster.GetCastRangeBonus ~= nil and tonumber(caster:GetCastRangeBonus()) or 0
        if value ~= nil and bonus ~= nil and bonus > 0 and value <= bonus then value = 0 end
    end
    if value == nil or value <= 0 then value = native_range end
    if value ~= nil and value > 0 then return value end
    -- Native data can store range in AbilityValues.AbilityCastRange,
    -- not the legacy top-level cast-range field. Resolve that value when the
    -- native range accessor gives zero; never invent a fixed range.
    if ability.GetSpecialValueFor ~= nil then
        local ok, special = pcall(ability.GetSpecialValueFor, ability, "AbilityCastRange")
        -- Only reviewed native travel/reach specials are cast-range fallbacks.
        local special_key = special_cast_ranges[name] or special_effect_reaches[name]
        local effect_reach = false
        if (not ok or tonumber(special) == nil or tonumber(special) <= 0)
            and special_key ~= nil then
            ok, special = pcall(ability.GetSpecialValueFor, ability, special_key)
            effect_reach = special_effect_reaches[name] ~= nil
            if name == "monkey_king_wukongs_command" and caster.HasScepter ~= nil and caster:HasScepter() then
                local scepter_ok, scepter_range = pcall(ability.GetSpecialValueFor, ability, "cast_range_scepter")
                if scepter_ok and tonumber(scepter_range) and tonumber(scepter_range) > 0 then
                    ok, special = true, scepter_range
                end
            end
            if name == "drow_ranger_multishot" then
                -- Native description: attack range + arrow_range_base. Read the
                -- current attack range so equipment/talents are reflected live.
                local attack_ok, attack_range = false, nil
                if caster.Script_GetAttackRange ~= nil then
                    attack_ok, attack_range = pcall(caster.Script_GetAttackRange, caster)
                end
                if ok and tonumber(special) and attack_ok and tonumber(attack_range) then
                    special = tonumber(special) + math.max(0, tonumber(attack_range))
                else ok = false end
            end
        end
        if ok and tonumber(special) ~= nil and tonumber(special) > 0 then
            local bonus = not effect_reach and caster.GetCastRangeBonus ~= nil and caster:GetCastRangeBonus() or 0
            return tonumber(special) + (tonumber(bonus) or 0)
        end
    end
    if ability.GetAbilityName ~= nil and global_casts[ability:GetAbilityName()] then return math.huge end
    return math.max(0, value or 0)
end

local function ability_aoe_radius(ability)
    if ability.GetAOERadius ~= nil then
        local ok, radius = pcall(ability.GetAOERadius, ability)
        if ok and tonumber(radius) ~= nil and radius > 0 then return radius end
    end
    -- Preserve native radius semantics without guessing from width/damage specials.
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
            target_mode = action.logical_id == "sustained_move" and "unit" or (action.target_mode or "point"),
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
    if action.cast_variant ~= nil and action.cast_variant ~= "default" then
        return nil, "alternate_adapter_unavailable"
    end
    if action.desired_autocast_state ~= nil then
        if not has_flag(get_behavior(source), DOTA_ABILITY_BEHAVIOR_AUTOCAST) then
            return nil, "autocast_not_supported"
        end
        native_cast_type = "autocast"
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
        desired_autocast_state = action.desired_autocast_state,
        state_policy = action.state_policy,
        state_mana_on = action.state_mana_on,
        state_mana_off = action.state_mana_off,
        state_hold_seconds = action.state_hold_seconds,
        capability = Capability.Describe(caster, source, action, {runtime=true}),
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
    if NativeTargeting.RejectsTarget(source, caster, target) then return false end
    if UnitFilter ~= nil and source.GetAbilityTargetTeam ~= nil
        and source.GetAbilityTargetType ~= nil and source.GetAbilityTargetFlags ~= nil
        and caster.GetTeamNumber ~= nil then
        local team, types = NativeTargeting.ResolveMasks(source,
            source:GetAbilityTargetTeam(), source:GetAbilityTargetType())
        local ok, result = pcall(UnitFilter, target, team,
            types, source:GetAbilityTargetFlags(), caster:GetTeamNumber())
        if not ok or result ~= (UF_SUCCESS or 0) then return false end
    end
    local readable, method = pcall(function() return source.CastFilterResultTarget end)
    if not readable then return false end
    if method ~= nil then
        local ok, result = pcall(method, source, target)
        if not ok or result ~= (UF_SUCCESS or 0) then return false end
    end
    return true
end

-- Enemy control remains based on engine states (including Chronosphere exceptions).
-- Separately protect reviewed native sustained casts from our replacement orders.
local function native_control(caster, spec, approaching)
    if not is_valid(caster) or (caster.IsAlive ~= nil and not caster:IsAlive()) then
        return false, "caster_invalid"
    end
    if SustainedCast.ActiveAbility(caster) then return false, "sustained_cast" end
    local function state(method)
        return caster[method] ~= nil and caster[method](caster)
    end
    if state("IsChanneling") and (approaching or not Lifecycle.CanRelease(caster, spec)) then return false, "channeling" end
    local active = caster.GetCurrentActiveAbility and caster:GetCurrentActiveAbility()
    if state("IsInAbilityPhase") or (active and active.IsInAbilityPhase and active:IsInAbilityPhase()) then
        return false, "ability_phase"
    end
    -- Waiting emits no order and does not attempt to break a disable.
    if spec.kind == "wait" and not approaching then return true end
    for _, entry in ipairs({
        {"IsOutOfGame", "caster_out_of_game"},
        {"IsCommandRestricted", "caster_command_restricted"},
        {"IsStunned", "caster_stunned"},
        {"IsFrozen", "caster_frozen"},
    }) do
        if state(entry[1]) then return false, entry[2] end
    end
    if approaching or spec.kind == "move" then
        if state("IsRooted") then return false, "caster_rooted" end
        if state("IsCurrentlyHorizontalMotionControlled") or state("IsCurrentlyVerticalMotionControlled")
            or state("IsTaunted") or state("IsFeared") then return false, "native_movement_control" end
    end
    if spec.kind == "attack" and state("IsDisarmed") then return false, "cannot_attack" end
    if not approaching then
        if spec.kind == "ability" and state("IsSilenced") then return false, "caster_silenced" end
        if spec.kind == "item" and state("IsMuted") then return false, "caster_muted" end
        if (spec.kind == "ability" or spec.kind == "item") and spec.source ~= nil
            and has_flag(get_behavior(spec.source), DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES)
            and state("IsRooted") then return false, "caster_rooted" end
    end
    return true
end

function ActionAdapter:CanExecute(caster, spec, ctx)
    local allowed, reason = native_control(caster, spec, false)
    if not allowed then return false, reason end

    local custom = self.custom[spec.logical_id]
    if custom ~= nil and custom.CanExecute ~= nil then
        return custom:CanExecute(caster, spec, ctx)
    end

    if spec.kind == "attack" then
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
    if State.IsManaged(spec) then
        local change, why = State.CanChange(caster, spec, ctx)
        if not change then return false, why end
        -- Autocast state orders do not cast the spell or consume a charge.
        if spec.cast_type == "autocast" then
            if DOTA_UNIT_ORDER_CAST_TOGGLE_AUTO == nil then return false, "native_autocast_order_unavailable" end
            return true
        end
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
    if spec.kind == "move" and spec.logical_id == "sustained_move" then return true end
    if spec.cast_type == "toggle" or spec.cast_type == "autocast" or spec.target_mode == "none" or spec.target_mode == "self" or spec.kind == "wait" then
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
    local allowed, reason = native_control(caster, spec, false)
    if not allowed then return false, reason end
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
        if self.order_gate:Execute(setup) == false then return false, "vector_setup_rejected" end
        if self.order_gate:Execute(cast) == false then return false, "vector_cast_rejected" end
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
    elseif spec.cast_type == "autocast" then
        if DOTA_UNIT_ORDER_CAST_TOGGLE_AUTO == nil then return false, "native_autocast_order_unavailable" end
        order.OrderType = DOTA_UNIT_ORDER_CAST_TOGGLE_AUTO
        order.AbilityIndex = spec.source:entindex()
    elseif spec.cast_type == "toggle" then
        order.OrderType = DOTA_UNIT_ORDER_CAST_TOGGLE
        order.AbilityIndex = spec.source:entindex()
    else
        return false, "unsupported_cast_type:" .. tostring(spec.cast_type)
    end

    if State.IsManaged(spec) then
        -- Recheck at submission: another controller may have already changed it.
        local change, why = State.CanChange(caster, spec, ctx)
        if not change then return false, why end
    end
    local ok, why = submit_order(caster, spec, target_or_point, self.order_gate, order)
    if ok and State.IsManaged(spec) then State.Issued(caster, spec, ctx) end
    return ok, why
end

function ActionAdapter:IssueApproach(caster, spec, target_or_point)
    local allowed, reason = native_control(caster, spec, true)
    if not allowed then return false, reason end
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

    return submit_order(caster, spec, target_or_point, self.order_gate, order)
end

return ActionAdapter
