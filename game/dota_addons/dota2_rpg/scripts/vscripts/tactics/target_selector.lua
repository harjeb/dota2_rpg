local Context = require("tactics/condition_context")
local Conditions = require("tactics/condition_registry")
local NativeTargeting = require("tactics/native_targeting")

local VectorTarget = require("tactics/vector_target")
local TargetSelector = {}
TargetSelector.__index = TargetSelector

local function entity_index(entity)
    if entity ~= nil and entity.entindex ~= nil then
        return entity:entindex()
    end
    return 2147483647
end

local function armor_value(target)
    if target.GetPhysicalArmorValue == nil then
        return 0
    end
    return target:GetPhysicalArmorValue(false)
end

local function attack_damage(target)
    if target.GetAverageTrueAttackDamage == nil then
        return 0
    end
    return target:GetAverageTrueAttackDamage(nil)
end

local function magic_resistance(target)
    if target.GetMagicalArmorValue == nil then
        return 0
    end
    return target:GetMagicalArmorValue()
end

local function missing_health(target)
    return math.max(0, target:GetMaxHealth() - target:GetHealth())
end

local function rank_value(priority, ctx, target)
    local kind = priority.type
    if kind == "lowest_hp_pct" then
        return Conditions.HealthPct(target)
    elseif kind == "highest_hp_pct" then
        return -Conditions.HealthPct(target)
    elseif kind == "lowest_health" then
        return target:GetHealth()
    elseif kind == "highest_health" then
        return -target:GetHealth()
    elseif kind == "most_missing_health" then
        return -missing_health(target)
    elseif kind == "nearest" then
        return Conditions.DistanceBetween(ctx.caster, target)
    elseif kind == "farthest" then
        return -Conditions.DistanceBetween(ctx.caster, target)
    elseif kind == "lowest_armor" then
        return armor_value(target)
    elseif kind == "highest_armor" then
        return -armor_value(target)
    elseif kind == "lowest_magic_resistance" then
        return magic_resistance(target)
    elseif kind == "highest_magic_resistance" then
        return -magic_resistance(target)
    elseif kind == "lowest_attack_damage" then
        return attack_damage(target)
    elseif kind == "highest_attack_damage" then
        return -attack_damage(target)
    elseif kind == "prefer_teammate" then
        -- Candidate team, native legality and hard filters remain authoritative.
        -- Keep self eligible as a fallback; subsequent priorities rank teammates.
        return target == ctx.caster and 1 or 0
    elseif kind == "prefer_tag" then
        return Conditions.HasTag(ctx, target, tostring(priority.value)) and 0 or 1
    elseif kind == "prefer_channeling" then
        return (target.IsChanneling ~= nil and target:IsChanneling()) and 0 or 1
    elseif kind == "prefer_affix" then
        if ctx.has_affix ~= nil and ctx.has_affix(target, tostring(priority.value)) then
            return 0
        end
        return 1
    elseif kind == "prefer_dispellable_buff" then
        if ctx.has_dispellable_buff ~= nil and ctx.has_dispellable_buff(target) then
            return 0
        end
        return 1
    end

    -- Unknown soft priorities are neutral instead of making the rule invalid.
    return 0
end

function TargetSelector.new(condition_registry)
    return setmetatable({
        conditions = condition_registry or Conditions,
    }, TargetSelector)
end

local function native_legal(target, spec, ctx)
    if spec ~= nil and spec.kind == "attack" then
        return Context.Call(target, "IsInvulnerable") ~= true
            and Context.Call(target, "IsAttackImmune") ~= true
            and Context.Call(target, "IsOutOfGame") ~= true
    end
    if spec == nil or (spec.kind ~= "ability" and spec.kind ~= "item") then return true end
    -- A point/area anchor is not the spell's native unit target. In particular,
    -- tree-capable point spells must not UnitFilter their enemy anchor as a tree.
    if spec.target_mode ~= "unit" and spec.target_mode ~= "self" then
        return Context.Call(target,"IsOutOfGame") ~= true and Context.Call(target,"IsInvulnerable") ~= true
    end
    local ability = spec.ability or spec.source
    if ability == nil or NativeTargeting.RejectsTarget(ability, ctx.caster, target) then return false end
    local checked = false
    if spec.target_mode == "unit" or spec.target_mode == "self" then
        local readable, method = pcall(function() return ability.CastFilterResultTarget end)
        if not readable then return false end
        if type(method) == "function" then
            local ok, result = pcall(method, ability, target)
            if not ok or result ~= (UF_SUCCESS or 0) then return false end
            checked = true
        end
    end
    local team, types = NativeTargeting.ResolveMasks(ability,
        Context.Call(ability, "GetAbilityTargetTeam"), Context.Call(ability, "GetAbilityTargetType"))
    local flags = Context.Call(ability, "GetAbilityTargetFlags")
    if type(UnitFilter) == "function" and team ~= nil and types ~= nil and types ~= 0 and flags ~= nil then
        local ok, result = pcall(UnitFilter, target, team, types, flags, ctx.caster:GetTeamNumber())
        return ok and result == (UF_SUCCESS or 0)
    end
    if checked then return true end
    return Context.Call(target, "IsInvulnerable") ~= true
        and Context.Call(target, "IsOutOfGame") ~= true
        and Context.Call(target, "IsMagicImmune") ~= true
end

function TargetSelector:FilterCandidates(candidates, target_filters, ctx, action_spec)
    local filtered = {}
    for _, target in ipairs(candidates or {}) do
        require("tactics/modifier_catalog").Observe(target)
        local alive = self.conditions.IsValidEntity(target) and (target.IsAlive == nil or target:IsAlive())
        local native = alive and native_legal(target, action_spec, ctx)
        if ctx.native_target_trace then
            local key=native and "accepted" or "rejected"
            ctx.native_target_trace[key]=ctx.native_target_trace[key]+1
        end
        if native then
            local passed = self.conditions:EvaluateTargetFilters(target_filters, ctx, target)
            if passed then
                table.insert(filtered, target)
            end
        end
    end
    return filtered
end

function TargetSelector:SortCandidates(candidates, priorities, ctx)
    table.sort(candidates, function(a, b)
        for _, priority in ipairs(priorities or {}) do
            local av = rank_value(priority, ctx, a)
            local bv = rank_value(priority, ctx, b)
            if av ~= bv then
                return av < bv
            end
        end

        -- Stable and deterministic fallback.
        local ad = Conditions.DistanceBetween(ctx.caster, a)
        local bd = Conditions.DistanceBetween(ctx.caster, b)
        if ad ~= bd then
            return ad < bd
        end
        return entity_index(a) < entity_index(b)
    end)
    return candidates
end

function TargetSelector:SelectUnit(rule, action_spec, ctx)
    if action_spec.target_mode == "self" then
        local passed = native_legal(ctx.caster, action_spec, ctx) and self.conditions:EvaluateTargetFilters(rule.target_filters, ctx, ctx.caster)
        if passed then
            return ctx.caster, nil
        end
        return nil, "self_failed_target_filters"
    end

    local candidates = {}
    if ctx.get_candidates ~= nil then
        candidates = ctx.get_candidates(ctx.caster, action_spec, rule.target or {}) or {}
    end

    local filtered = self:FilterCandidates(candidates, rule.target_filters, ctx, action_spec)
    if #filtered == 0 then
        return nil, "no_legal_target"
    end

    self:SortCandidates(filtered, rule.target_priorities, ctx)
    for _, target in ipairs(filtered) do
        local in_range = rule.approach == "allow_approach" or ctx.is_in_range == nil
            or ctx.is_in_range(action_spec, target)
        if in_range then return target, nil end
    end
    return nil, "no_target_in_range"
end

function TargetSelector:SelectPoint(rule, action_spec, ctx)
    local candidates = {}
    if ctx.get_candidates ~= nil then
        candidates = ctx.get_candidates(ctx.caster, action_spec, rule.target or {}) or {}
    end

    local legal = self:FilterCandidates(candidates, rule.target_filters, ctx, action_spec)
    if #legal == 0 then
        return nil, nil, "no_legal_aoe_anchor"
    end

    self:SortCandidates(legal, rule.target_priorities, ctx)
    for _, anchor in ipairs(legal) do
        local point = anchor:GetAbsOrigin()
        local valid = true
        local source = action_spec.source or action_spec.ability
        if source ~= nil and source.CastFilterResultLocation ~= nil then
            local ok,result = pcall(source.CastFilterResultLocation,source,point)
            valid = ok and result == (UF_SUCCESS or 0)
        end
        if valid and (rule.approach == "allow_approach" or ctx.is_in_range == nil or ctx.is_in_range(action_spec,point)) then
            return point,anchor,nil
        end
    end
    return nil,nil,"no_legal_point_in_range"
end

function TargetSelector:SelectVector(rule, action_spec, ctx)
    if action_spec.cast_type ~= "vector" or action_spec.vector_mode == nil
        or VectorTarget.NativeMode(action_spec.source) ~= action_spec.vector_mode then
        return nil, nil, "unsupported_target_mode"
    end
    local native_spec = {}
    for key, value in pairs(action_spec) do native_spec[key] = value end
    native_spec.target_mode = action_spec.vector_mode
    local candidates = ctx.get_candidates ~= nil
        and ctx.get_candidates(ctx.caster, native_spec, rule.target or {}) or {}
    local legal = self:FilterCandidates(candidates, rule.target_filters, ctx, native_spec)
    self:SortCandidates(legal, rule.target_priorities, ctx)
    for _, primary in ipairs(legal) do
        local target = VectorTarget.Build(ctx.caster, primary)
        local valid = target ~= nil
        local source = action_spec.source
        if valid and action_spec.vector_mode == "point" and source.CastFilterResultLocation ~= nil then
            local ok, result = pcall(source.CastFilterResultLocation, source, target.start)
            valid = ok and result == (UF_SUCCESS or 0)
        end
        if valid and (rule.approach == "allow_approach" or ctx.is_in_range == nil
            or ctx.is_in_range(action_spec, target)) then return target, primary, nil end
    end
    return nil, nil, "no_legal_vector_in_range"
end

function TargetSelector:CheckNoTarget(rule, action_spec, ctx)
    local requires_area_check = rule.target_filters ~= nil and #rule.target_filters > 0

    if not requires_area_check then
        return true, nil
    end

    local candidates = {}
    if ctx.get_candidates ~= nil then
        candidates = ctx.get_candidates(ctx.caster, action_spec, rule.target or {}) or {}
    end
    local legal = self:FilterCandidates(candidates, rule.target_filters, ctx, action_spec)
    -- Filters require a matching trigger. Explicit distance/nearby conditions
    -- own proximity restrictions, independently of the retired hit-count gate.
    if #legal > 0 then return true, nil end
    return false, "no_matching_trigger_target"
end

return TargetSelector
