local Conditions = require("tactics/condition_registry")

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
    elseif kind == "highest_attack_damage" then
        return -attack_damage(target)
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

function TargetSelector:FilterCandidates(candidates, target_filters, ctx)
    local filtered = {}
    for _, target in ipairs(candidates or {}) do
        if self.conditions.IsValidEntity(target)
            and (target.IsAlive == nil or target:IsAlive()) then
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
        local passed = self.conditions:EvaluateTargetFilters(rule.target_filters, ctx, ctx.caster)
        if passed then
            return ctx.caster, nil
        end
        return nil, "self_failed_target_filters"
    end

    local candidates = {}
    if ctx.get_candidates ~= nil then
        candidates = ctx.get_candidates(ctx.caster, action_spec, rule.target or {}) or {}
    end

    local filtered = self:FilterCandidates(candidates, rule.target_filters, ctx)
    if #filtered == 0 then
        return nil, "no_legal_target"
    end

    self:SortCandidates(filtered, rule.target_priorities, ctx)
    return filtered[1], nil
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

    local legal = self:FilterCandidates(candidates, rule.target_filters, ctx)
    if #legal == 0 then
        return nil, nil, "no_legal_aoe_anchor"
    end

    local points = {}
    for _, unit in ipairs(legal) do
        table.insert(points, unit:GetAbsOrigin())
    end
    local center = centroid(legal)
    if center ~= nil then
        table.insert(points, center)
    end

    local radius = tonumber(action_spec.aoe_radius or 0)
    local min_hits = tonumber(rule.min_aoe_hits or 1)
    local best_point = nil
    local best_score = -math.huge
    local best_anchor = nil

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
                if distance < nearest_distance then
                    nearest_distance = distance
                    nearest_anchor = unit
                end
            end
        end

        if hit_count >= min_hits then
            local score = hit_count * 100
                + preferred_count * 30
                + total_missing_health * tonumber(rule.aoe_missing_health_weight or 0)
                - Conditions.DistanceBetween(ctx.caster, nearest_anchor) * 0.001

            if score > best_score then
                best_score = score
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
    local legal = self:FilterCandidates(candidates, rule.target_filters, ctx)
    local radius = tonumber(action_spec.aoe_radius or rule.aoe_radius or 0)
    local min_hits = tonumber(rule.min_aoe_hits or 1)
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
