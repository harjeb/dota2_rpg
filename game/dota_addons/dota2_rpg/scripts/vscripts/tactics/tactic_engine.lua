local Conditions = require("tactics/condition_registry")
local TargetSelector = require("tactics/target_selector")
local ActionAdapter = require("tactics/action_adapter")
local Context = require("tactics/condition_context")
local Movement = require("tactics/persistent_movement")
local Positioning = require("tactics/positioning")
local NativeEvents = require("tactics/native_events")
local NeutralAttack = require("tactics/neutral_attack")
local SustainedCast = require("tactics/sustained_cast")
local Compatibility = require("tactics/rule_compatibility")
local Lifecycle = require("tactics/action_lifecycle")
local StateControl = require("tactics/state_controller")
local okLog, RuntimeLog = pcall(require, "issue_fixes.runtime_log")
if not okLog then RuntimeLog = { Write = print } end

local TacticEngine = {}
TacticEngine.__index = TacticEngine

local DEFAULT_TICK = 0.20
local THINK_INTERVAL = 0.05
local DEFAULT_ABILITY_CHASE_TIMEOUT = 1.50
local DEFAULT_ATTACK_CHASE_TIMEOUT = 2.50
local DEFAULT_MAX_CHASE_DISTANCE = 1200

local function now()
    return GameRules:GetGameTime()
end

local function entity_index(entity)
    if entity ~= nil and entity.entindex ~= nil then
        return entity:entindex()
    end
    return -1
end

local function is_alive(entity)
    return Conditions.IsValidEntity(entity)
        and (entity.IsAlive == nil or entity:IsAlive())
end

local function shallow_copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function round_position(position)
    if position == nil then
        return "nil"
    end
    return string.format("%d:%d", math.floor(position.x / 16), math.floor(position.y / 16))
end

function TacticEngine.new(options)
    options = options or {}
    local order_gate = assert(options.order_gate, "order_gate is required")

    return setmetatable({
        get_phase = assert(options.get_phase, "get_phase is required"),
        get_battle_units = assert(options.get_battle_units, "get_battle_units is required"),
        get_rules = assert(options.get_rules, "get_rules is required"),
        build_context = assert(options.build_context, "build_context is required"),
        on_debug = options.on_debug,
        conditions = options.conditions or Conditions,
        selector = options.selector or TargetSelector.new(options.conditions or Conditions),
        actions = options.actions or ActionAdapter.new(order_gate),
        order_gate = order_gate,
        states = {},
        running = false,
        tick_interval = tonumber(options.tick_interval or DEFAULT_TICK),
        think_name = options.think_name or "RPG_TacticEngineThink",
    }, TacticEngine)
end

function TacticEngine:Debug(unit, event, detail)
    detail = detail or {}
    self.trace_times = self.trace_times or {}
    local key = tostring(entity_index(unit)) .. ":" .. event .. ":" .. tostring(detail.rule_index or detail.rule_id or "")
    local time = now()
    local signature = tostring(detail.reason or detail.action_id or detail.target_index or "")
    local previous = self.trace_times[key]
    if previous == nil or previous.signature ~= signature or time - previous.time >= 5 then
        self.trace_times[key] = { signature = signature, time = time }
        RuntimeLog.Write(string.format("Tactic unit=%d hero=%s event=%s rule=%s action=%s target=%s reason=%s",
            entity_index(unit), tostring(Context.Call(unit, "GetUnitName") or ""), event, tostring(detail.rule_index or detail.rule_id or ""),
            tostring(detail.action_id or ""), tostring(detail.target_index or ""), tostring(detail.reason or "")))
    end
    if self.on_debug ~= nil then
        self.on_debug(unit, event, detail)
    end
end

function TacticEngine:GetState(unit)
    local id = entity_index(unit)
    local state = self.states[id]
    if state ~= nil and state.unit ~= unit then
        Movement.Release(self, state.unit, state, {}, false)
        pcall(NativeEvents.Detach, state.unit)
        Lifecycle.Reset(state.unit)
        StateControl.Reset(state.unit)
        state = nil
    end
    if state == nil then
        state = {
            next_eval = now() + ((math.max(0, id) % 4) * 0.03),
            last_order_signature = nil,
            last_order_time = -math.huge,
            chase = nil,
            wait_until = 0,
            unit = unit,
            events = NativeEvents.Attach(unit),
        }
        self.states[id] = state
    end
    return state
end

function TacticEngine:IsExclusiveMovement(unit)
    local state = self.states[entity_index(unit)]
    return state ~= nil and state.unit == unit and state.movement ~= nil
end

function TacticEngine:HasActiveOrder(unit)
    if self.get_phase() ~= "FIGHT" then return false end
    local state = self.states[entity_index(unit)]
    if not state or state.unit ~= unit then return false end
    return state.chase ~= nil or state.movement ~= nil or (state.wait_until or 0) > now()
        or (state.posture_order ~= nil and (state.posture_order.expires or 0) > now())
        or NeutralAttack.HasTactic(unit)
end

function TacticEngine:Reset()
    for _, state in pairs(self.states) do
        NeutralAttack.Release(state.unit)
        if state.movement then Movement.Release(self, state.unit, state, {}, true)
        else Movement.StopOrder(self, state.unit, state.posture_order, {}) end
        pcall(NativeEvents.Detach, state.unit)
        Lifecycle.Reset(state.unit)
        StateControl.Reset(state.unit)
    end
    self.states = {}
end

function TacticEngine:Start(game_mode_entity)
    if self.running then
        return
    end
    self.running = true
    game_mode_entity:SetContextThink(self.think_name, function()
        if not self.running then
            return nil
        end
        self:Think()
        return THINK_INTERVAL
    end, 0)
end

function TacticEngine:Stop()
    self.running = false
    self:Reset()
end

function TacticEngine:Think()
    if self.get_phase() ~= "FIGHT" then
        self:Reset()
        return
    end

    -- The bridge temporarily omits live units during auxiliary native casts
    -- (e.g. Tiny grabbing a tree). Keep their observer so cast completion is
    -- still recorded. Stage reset handles roster changes; dead handles release.
    for id, state in pairs(self.states) do
        if not is_alive(state.unit) then
            Movement.Release(self, state.unit, state, {}, true)
            pcall(NativeEvents.Detach, state.unit)
        Lifecycle.Reset(state.unit)
        StateControl.Reset(state.unit)
            self.states[id] = nil
        end
    end
    local current_time = now()
    for _, unit in ipairs(self.get_battle_units() or {}) do
        if is_alive(unit) then
            local state = self:GetState(unit)
            if current_time >= state.next_eval then
                state.next_eval = current_time + self.tick_interval
                self:EvaluateUnit(unit, state, current_time)
            end
        end
    end
end

function TacticEngine:BuildContext(unit, current_time)
    local ctx = self.build_context(unit) or {}
    ctx.caster = unit
    ctx.now = current_time
    ctx.current_time = current_time
    ctx.is_in_range = function(spec, target)
        return self.actions:IsInRange(unit, spec, target)
    end
    return ctx
end

function TacticEngine:IsBusy(unit)
    if SustainedCast.ActiveAbility(unit) then
        return true, "sustained_cast"
    end
    if unit.IsChanneling ~= nil and unit:IsChanneling() then
        return true, "channeling"
    end
    local active = Context.Call(unit, "GetCurrentActiveAbility")
    if Context.Call(unit, "IsInAbilityPhase") == true or Context.Call(active, "IsInAbilityPhase") == true then
        return true, "ability_phase"
    end
    return false, nil
end

function TacticEngine:EvaluateUnit(unit, state, current_time)
    if unit.rpg_debug_manual_cast then return end
    if self.get_phase() ~= "FIGHT" then
        return
    end

    if current_time < (state.wait_until or 0) then
        return
    end

    Lifecycle.Observe(unit, current_time)
    local ctx = self:BuildContext(unit, current_time)
    local rules = self.get_rules(unit) or {}
    state.events = state.events or NativeEvents.Attach(unit)
    Movement.Observe(unit, state, rules)
    if state.movement then
        local active = state.movement
        if active.rule.action.movement_interruptible == true and not self:IsBusy(unit) then
            if self:EvaluateRules(unit, state, ctx, rules, 1, active.rule_index - 1, "non_attack") then
                if state.movement == active then Movement.Release(self, unit, state, ctx, false) end
                return
            end
        end
        if Movement.Continue(self, unit, state, ctx) then return end
    end
    local busy, busy_reason = self:IsBusy(unit)
    if busy then
        -- Only the reviewed release belonging to the active channel may pass.
        -- Never let an attack/move/fallback cancel an unrelated channel.
        if busy_reason == "channeling" then
            for index, rule in ipairs(rules) do
                if rule.enabled ~= false and rule.action then
                    local spec = self.actions:Resolve(unit, rule.action, ctx)
                    if spec and Lifecycle.CanRelease(unit, spec) then
                        local done, why = self:TryRule(unit, state, ctx, rule, index)
                        if done then return end
                        self:Debug(unit, "rule_skipped", {rule_index=index, action_id=spec.logical_id, reason=why, conditions=ctx.condition_trace})
                    end
                end
            end
        end
        return
    end

    -- A higher-priority emergency rule may interrupt a movement chase.
    if state.chase ~= nil then
        local attack_chase = state.chase.rule.action.kind == "attack"
        local max_priority = attack_chase and #rules or math.max(0, (state.chase.rule_index or 1) - 1)
        local handled = self:EvaluateRules(unit, state, ctx, rules, 1, max_priority, "non_attack")
        if handled then
            return
        end
        if self:ContinueChase(unit, state, ctx, current_time) then
            return
        end
    end

    if self:EvaluateRules(unit, state, ctx, rules, 1, #rules) then
        return
    end

    self:ExecuteFallback(unit, state, ctx)
end

function TacticEngine:EvaluateRules(unit, state, ctx, rules, first_index, last_index, mode)
    if last_index < first_index then
        return false
    end

    -- Basic attacks fill downtime; they must not starve later skills or items.
    if mode == nil then
        return self:EvaluateRules(unit, state, ctx, rules, first_index, last_index, "non_attack")
            or self:EvaluateRules(unit, state, ctx, rules, first_index, last_index, "attack")
    end
    for index = first_index, last_index do
        local rule = rules[index]
        local is_attack = rule ~= nil and rule.action ~= nil and rule.action.kind == "attack"
        if rule ~= nil and rule.enabled ~= false and ((mode == "attack") == is_attack) then
            local executed, reason = self:TryRule(unit, state, ctx, rule, index)
            if executed then
                return true
            end
            self:Debug(unit, "rule_skipped", {
                rule_id = rule.id or index,
                rule_index = index,
                action_id = rule.action and (rule.action.name or rule.action.logical_id or rule.action.kind),
                reason = reason,
                conditions = ctx.condition_trace,
                native_targets = ctx.native_target_trace,
            })
        end
    end
    return false
end

function TacticEngine:ResolveRuleTarget(rule, spec, ctx)
    local handled, point, anchor, reason = require("tactics/special_targets").SelectDestination(rule, spec, ctx, self.conditions)
    if handled then return point, anchor, reason end
    if spec.target_mode == "vector" then
        return self.selector:SelectVector(rule, spec, ctx)
    elseif spec.target_mode == "point" then
        local point, anchor, reason = self.selector:SelectPoint(rule, spec, ctx)
        return point, anchor, reason
    elseif spec.target_mode == "none" or spec.cast_type == "toggle" or spec.cast_type == "autocast" then
        local passed, reason = self.selector:CheckNoTarget(rule, spec, ctx)
        if not passed then
            return nil, nil, reason
        end
        return ctx.caster, ctx.caster, nil
    elseif spec.target_mode == "unit" or spec.target_mode == "self" then
        local target, reason = self.selector:SelectUnit(rule, spec, ctx)
        return target, target, reason
    end
    return nil, nil, "unsupported_target_mode"
end

function TacticEngine:TryRule(unit, state, ctx, rule, rule_index)
    ctx.condition_trace = {}
    ctx.native_target_trace = {accepted=0, rejected=0}
    local spec, resolve_reason = self.actions:Resolve(unit, rule.action, ctx)
    if spec == nil then
        return false, resolve_reason
    end

    ctx.current_action_id = spec.logical_id
    ctx.current_action_spec = spec
    local compatible, why = Compatibility.Validate(unit, rule, {runtime=true, capability=spec.capability})
    if not compatible then return false, why end
    local can_execute, action_reason = self.actions:CanExecute(unit, spec, ctx)
    if not can_execute then
        return false, action_reason
    end

    local use_ok, use_reason = self.conditions:EvaluateUseConditions(rule.use_conditions, ctx)
    if not use_ok then
        return false, use_reason
    end

    local target_or_point, anchor, target_reason = self:ResolveRuleTarget(rule, spec, ctx)
    if target_or_point == nil then
        return false, target_reason
    end

    if spec.logical_id == "sustained_move" then
        return Movement.Start(self, unit, state, ctx, rule, rule_index, spec, anchor or target_or_point)
    end
    if Positioning.Try(self, unit, state, ctx, rule, spec, anchor or target_or_point) then
        state.chase = nil
        state.posture_order = {owns_order=true, expires=ctx.now+self.tick_interval*2}
        -- The next attack must not be suppressed as a duplicate of the order
        -- that preceded this move.
        state.last_order_signature = nil
        return true
    end
    if self.actions:IsInRange(unit, spec, target_or_point) then
        state.chase = nil
        return self:IssueAction(unit, state, ctx, rule, rule_index, spec, target_or_point, anchor)
    end

    if rule.approach ~= "allow_approach" then
        return false, "out_of_range"
    end

    local timeout = tonumber(rule.chase_timeout)
    if timeout == nil then
        timeout = spec.kind == "attack" and DEFAULT_ATTACK_CHASE_TIMEOUT or DEFAULT_ABILITY_CHASE_TIMEOUT
    end

    local approached, approach_reason = self.actions:IssueApproach(unit, spec, target_or_point)
    if not approached then
        state.chase = nil
        return false, approach_reason
    end

    state.chase = {
        rule = rule,
        rule_index = rule_index,
        logical_id = spec.logical_id,
        target_index = anchor ~= nil and entity_index(anchor) or -1,
        point = spec.target_mode == "point" and target_or_point or nil,
        deadline = ctx.now + timeout,
        start_position = unit:GetAbsOrigin(),
        max_distance = tonumber(rule.max_chase_distance or DEFAULT_MAX_CHASE_DISTANCE),
    }

    self:Debug(unit, "chase_started", {
        rule_id = rule.id or rule_index,
        target_index = state.chase.target_index,
        deadline = state.chase.deadline,
    })
    return true, nil
end

function TacticEngine:ContinueChase(unit, state, ctx, current_time)
    local chase = state.chase
    if chase == nil then
        return false
    end
    if current_time > chase.deadline then
        self:Debug(unit, "chase_cancelled", { reason = "timeout", rule_index = chase.rule_index })
        state.chase = nil
        return false
    end

    if (unit:GetAbsOrigin() - chase.start_position):Length2D() > chase.max_distance then
        self:Debug(unit, "chase_cancelled", { reason = "max_distance", rule_index = chase.rule_index })
        state.chase = nil
        return false
    end

    local rule = chase.rule
    local spec, reason = self.actions:Resolve(unit, rule.action, ctx)
    if spec == nil or spec.logical_id ~= chase.logical_id then
        self:Debug(unit, "chase_cancelled", { reason = reason or "action_changed", rule_index = chase.rule_index })
        state.chase = nil
        return false
    end

    ctx.current_action_id = spec.logical_id
    ctx.current_action_spec = spec
    local compatible, why = Compatibility.Validate(unit, rule, {runtime=true, capability=spec.capability})
    if not compatible then
        self:Debug(unit, "chase_cancelled", {reason=why, rule_index=chase.rule_index})
        state.chase=nil; return false
    end
    local can_execute = self.actions:CanExecute(unit, spec, ctx)
    local use_ok = self.conditions:EvaluateUseConditions(rule.use_conditions, ctx)
    if not can_execute or not use_ok then
        state.chase = nil
        return false
    end

    local target_or_point = chase.point
    local anchor = nil
    if chase.target_index >= 0 then
        anchor = EntIndexToHScript(chase.target_index)
        if not is_alive(anchor) then
            self:Debug(unit, "chase_cancelled", { reason = "target_invalid", rule_index = chase.rule_index })
            state.chase = nil
            return false
        end
        if spec.target_mode ~= "point" then
            target_or_point = anchor
        elseif target_or_point == nil then
            target_or_point = anchor:GetAbsOrigin()
        end
    end

    -- Thresholds and native legality can change while walking (healing,
    -- dispels, spell immunity, charge loss). Re-select with the same gates,
    -- retaining the original chase deadline instead of casting stale intent.
    target_or_point, anchor = self:ResolveRuleTarget(rule, spec, ctx)
    if target_or_point == nil then
        state.chase = nil
        return false
    end
    chase.target_index = anchor ~= nil and entity_index(anchor) or -1
    chase.point = spec.target_mode == "point" and target_or_point or nil

    if self.actions:IsInRange(unit, spec, target_or_point) then
        state.chase = nil
        return self:IssueAction(unit, state, ctx, rule, chase.rule_index, spec, target_or_point, anchor)
    end

    local approached, approach_reason = self.actions:IssueApproach(unit, spec, target_or_point)
    if not approached then
        self:Debug(unit, "chase_cancelled", { reason = approach_reason, rule_index = chase.rule_index })
        state.chase = nil
        return false, approach_reason
    end
    return true
end

function TacticEngine:OrderSignature(spec, target_or_point)
    if StateControl.IsManaged(spec) then
        local desired=spec.desired_toggle_state
        if spec.cast_type=="autocast" then desired=spec.desired_autocast_state end
        return spec.logical_id .. ":" .. spec.cast_type .. ":" .. tostring(desired)
    end
    if spec.target_mode == "vector" then
        return spec.logical_id .. ":vector:" .. tostring(entity_index(target_or_point.primary))
            .. ":" .. round_position(target_or_point.start) .. ":" .. round_position(target_or_point.finish)
    end
    if target_or_point ~= nil and target_or_point.entindex ~= nil then
        return spec.logical_id .. ":unit:" .. tostring(target_or_point:entindex())
    end
    return spec.logical_id .. ":point:" .. round_position(target_or_point)
end

function TacticEngine:IssueAction(unit, state, ctx, rule, rule_index, spec, target_or_point, anchor)
    local signature = self:OrderSignature(spec, target_or_point)
    if signature == state.last_order_signature and ctx.now - state.last_order_time < 0.25 then
        return true, nil
    end

    local issued, reason = self.actions:Issue(unit, spec, target_or_point, ctx)
    if not issued then
        return false, reason
    end
    if reason == "attack_persisted" then return true, nil end
    if spec.source and not StateControl.IsManaged(spec) then
        Lifecycle.Requested(unit, Context.Call(spec.source,"GetAbilityName") or spec.logical_id, ctx.now)
    end

    state.posture_order = nil
    state.last_order_signature = signature
    state.last_order_time = ctx.now
    if spec.kind == "attack" then state.attack_order_time = ctx.now end
    if spec.kind == "wait" then
        state.wait_until = ctx.now + tonumber(spec.wait_duration or 0.35)
    end

    if ctx.record_action_order ~= nil then
        ctx.record_action_order(unit, spec.logical_id, anchor or target_or_point)
    end

    self:Debug(unit, "rule_executed", {
        rule_id = rule.id or rule_index,
        rule_index = rule_index,
        action_id = spec.logical_id,
        reason = "order_submitted_not_native_confirmation",
        conditions = ctx.condition_trace,
        target_index = anchor ~= nil and entity_index(anchor) or -1,
    })
    return true, nil
end

function TacticEngine:ExecuteFallback(unit, state, ctx)
    local fallback = {
        id = "system_fallback_attack",
        enabled = true,
        action = {
            kind = "attack",
            logical_id = "system_fallback_attack",
            target_team = "enemy",
        },
        target = { team = "enemy", types = { "hero", "monster", "summon" } },
        target_filters = {},
        target_priorities = { { type = "nearest" } },
        use_conditions = {},
        approach = "allow_approach",
        chase_timeout = DEFAULT_ATTACK_CHASE_TIMEOUT,
        max_chase_distance = DEFAULT_MAX_CHASE_DISTANCE,
    }

    local executed = self:TryRule(unit, state, shallow_copy(ctx), fallback, 999)
    if not executed then
        self:Debug(unit, "fallback_failed", {})
    end
end

return TacticEngine
