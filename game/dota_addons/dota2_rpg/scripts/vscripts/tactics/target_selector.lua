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
    if ability == nil or NativeTargeting.RejectsSelf(ability, ctx.caster, target) then return false end
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
        if self.conditions.IsValidEntity(target)
            and (target.IsAlive == nil or target:IsAlive()) and native_legal(target, action_spec, ctx) then
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
        local hits, min_hits = 0, tonumber(rule.min_aoe_hits or 1)
        if min_hits <= 1 then
            hits = 1
        elseif tonumber(action_spec.aoe_radius or 0) > 0 then
            for _, other in ipairs(filtered) do
                if Conditions.DistanceBetween(target, other) <= action_spec.aoe_radius then hits = hits + 1 end
            end
        end
        if in_range and hits >= min_hits then return target, nil end
    end
    return nil, "no_target_in_range_or_aoe_min_hits"
end

local function point_distance(a, b)
    return (a - b):Length2D()
end

local function centroid(units)
    if #units == 0 then
        return nil
    end
    local sum = Vector(0, 0, 0)
    for _, unit in ipairs(units) do
        sum = sum + unit:GetAbsOrigin()
    end
    return sum / #units
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
    if tonumber(rule.min_aoe_hits or 0) <= 1 then
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
    local ranks = {}
    local points = {}
    for rank, unit in ipairs(legal) do
        ranks[unit] = rank
        table.insert(points, unit:GetAbsOrigin())
    end
    local center = centroid(legal)
    if center ~= nil then
        table.insert(points, center)
    end

    local radius = tonumber(action_spec.aoe_radius or 0)
    local min_hits = tonumber(rule.min_aoe_hits or 1)
    if radius <= 0 then return nil,nil,"native_aoe_radius_unavailable" end
    local best_point = nil
    local best_score = -math.huge
    local best_anchor = nil
    local best_rank = math.huge

    for _, point in ipairs(points) do
        local hit_count = 0
        local preferred_count = 0
        local total_missing_health = 0
        local nearest_anchor = nil
        local nearest_distance = math.huge

        for _, unit in ipairs(legal) do
            local distance = point_distance(point, unit:GetAbsOrigin())
            if distance <= radius then
                hit_count = hit_count + 1
                total_missing_health = total_missing_health + missing_health(unit)
                if rule.aoe_prefer_tag ~= nil and Conditions.HasTag(ctx, unit, rule.aoe_prefer_tag) then
                    preferred_count = preferred_count + 1
                end
                if nearest_anchor == nil or ranks[unit] < ranks[nearest_anchor] then
                    nearest_distance = distance
                    nearest_anchor = unit
                end
            end
        end

        local in_range = rule.approach == "allow_approach" or ctx.is_in_range == nil
            or ctx.is_in_range(action_spec, point)
        if hit_count >= min_hits and in_range then
            local score = hit_count * 100
                + preferred_count * 30
                + total_missing_health * tonumber(rule.aoe_missing_health_weight or 0)
            local rank = ranks[nearest_anchor] or math.huge

            if score > best_score or (score == best_score and rank < best_rank) then
                best_score = score
                best_rank = rank
                best_point = point
                best_anchor = nearest_anchor
            end
        end
    end

    if best_point == nil then
        return nil, nil, "aoe_min_hits_not_met"
    end
    return best_point, best_anchor, nil
end

function TargetSelector:SelectVector(rule, action_spec, ctx)
    if action_spec.cast_type ~= "vector" or action_spec.vector_mode == nil
        or VectorTarget.NativeMode(action_spec.source) ~= action_spec.vector_mode then
        return nil, nil, "unsupported_target_mode"
    end
    if tonumber(rule.min_aoe_hits or 0) > 0 then return nil, nil, "vector_geometry_unknown" end
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
    local requires_area_check = (rule.min_aoe_hits ~= nil)
        or (rule.target_filters ~= nil and #rule.target_filters > 0)

    if not requires_area_check then
        return true, nil
    end

    local candidates = {}
    if ctx.get_candidates ~= nil then
        candidates = ctx.get_candidates(ctx.caster, action_spec, rule.target or {}) or {}
    end
    local legal = self:FilterCandidates(candidates, rule.target_filters, ctx, action_spec)
    local radius = tonumber(action_spec.aoe_radius or 0)
    local min_hits = tonumber(rule.min_aoe_hits or 0)
    -- Without an explicit circular hit gate, filters mean 'a matching unit
    -- exists'. Global release/cancel actions have no native AoE radius.
    if min_hits <= 0 then
        if #legal > 0 then return true, nil end
        return false, "no_matching_trigger_target"
    end
    if radius <= 0 then return false, "native_aoe_radius_unavailable" end
    local hits = 0
    for _, unit in ipairs(legal) do
        if Conditions.DistanceBetween(ctx.caster, unit) <= radius then
            hits = hits + 1
        end
    end
    if hits < min_hits then
        return false, "no_target_min_hits_not_met"
    end
    return true, nil
end

return TargetSelector
