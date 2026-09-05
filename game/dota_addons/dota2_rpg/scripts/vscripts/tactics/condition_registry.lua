local ConditionRegistry = {
    use_conditions = {},
    target_filters = {},
}

local function is_valid_entity(entity)
    if entity == nil then
        return false
    end
    if entity.IsNull ~= nil and entity:IsNull() then
        return false
    end
    return true
end

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function health_pct(unit)
    if not is_valid_entity(unit) then
        return 0
    end
    local max_health = math.max(1, unit:GetMaxHealth())
    return clamp(unit:GetHealth() / max_health, 0, 1)
end

local function mana_pct(unit)
    if not is_valid_entity(unit) or unit.GetMaxMana == nil then
        return 0
    end
    local max_mana = math.max(1, unit:GetMaxMana())
    return clamp(unit:GetMana() / max_mana, 0, 1)
end

local function distance_between(a, b)
    if not is_valid_entity(a) or not is_valid_entity(b) then
        return math.huge
    end
    return (a:GetAbsOrigin() - b:GetAbsOrigin()):Length2D()
end

local function has_tag(ctx, unit, wanted)
    if ctx.get_tags == nil then
        return false
    end
    local tags = ctx.get_tags(unit) or {}
    if tags[wanted] == true then
        return true
    end
    for _, tag in pairs(tags) do
        if tag == wanted then
            return true
        end
    end
    return false
end

local function safe_boolean_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        return false, result
    end
    return result == true, nil
end

function ConditionRegistry:RegisterUseCondition(name, evaluator)
    assert(type(name) == "string" and name ~= "", "use condition name is required")
    assert(type(evaluator) == "function", "use condition evaluator must be a function")
    self.use_conditions[name] = evaluator
end

function ConditionRegistry:RegisterTargetFilter(name, evaluator)
    assert(type(name) == "string" and name ~= "", "target filter name is required")
    assert(type(evaluator) == "function", "target filter evaluator must be a function")
    self.target_filters[name] = evaluator
end

function ConditionRegistry:EvaluateUseConditions(conditions, ctx)
    for index, condition in ipairs(conditions or {}) do
        local evaluator = self.use_conditions[condition.type]
        if evaluator == nil then
            return false, "unknown_use_condition:" .. tostring(condition.type), index
        end

        local passed, err = safe_boolean_call(evaluator, ctx, condition)
        if err ~= nil then
            return false, "use_condition_error:" .. tostring(condition.type), index
        end
        if not passed then
            return false, "use_condition_failed:" .. tostring(condition.type), index
        end
    end
    return true, nil, nil
end

function ConditionRegistry:EvaluateTargetFilters(filters, ctx, target)
    for index, condition in ipairs(filters or {}) do
        local evaluator = self.target_filters[condition.type]
        if evaluator == nil then
            return false, "unknown_target_filter:" .. tostring(condition.type), index
        end

        local passed, err = safe_boolean_call(evaluator, ctx, target, condition)
        if err ~= nil then
            return false, "target_filter_error:" .. tostring(condition.type), index
        end
        if not passed then
            return false, "target_filter_failed:" .. tostring(condition.type), index
        end
    end
    return true, nil, nil
end

-- Use conditions -----------------------------------------------------------

ConditionRegistry:RegisterUseCondition("always", function(_ctx, _condition)
    return true
end)

ConditionRegistry:RegisterUseCondition("self_hp_pct_lte", function(ctx, condition)
    return health_pct(ctx.caster) <= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("self_hp_pct_gte", function(ctx, condition)
    return health_pct(ctx.caster) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("self_mana_pct_lte", function(ctx, condition)
    return mana_pct(ctx.caster) <= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("self_mana_pct_gte", function(ctx, condition)
    return mana_pct(ctx.caster) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("alive_ally_count_gte", function(ctx, condition)
    return tonumber(ctx.alive_ally_count or 0) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("alive_enemy_count_lte", function(ctx, condition)
    return tonumber(ctx.alive_enemy_count or 0) <= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("dead_ally_count_gte", function(ctx, condition)
    return tonumber(ctx.dead_ally_count or 0) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("elapsed_gte", function(ctx, condition)
    return tonumber(ctx.elapsed or 0) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("elapsed_lte", function(ctx, condition)
    return tonumber(ctx.elapsed or 0) <= tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("phase_is", function(ctx, condition)
    return tostring(ctx.boss_phase or "") == tostring(condition.value or "")
end)

ConditionRegistry:RegisterUseCondition("action_use_count_lt", function(ctx, condition)
    local logical_id = tostring(condition.action_id or ctx.current_action_id or "")
    local count = 0
    if ctx.get_action_use_count ~= nil then
        count = tonumber(ctx.get_action_use_count(ctx.caster, logical_id) or 0)
    end
    return count < tonumber(condition.value)
end)

ConditionRegistry:RegisterUseCondition("self_recently_damaged", function(ctx, condition)
    if ctx.was_recently_damaged == nil then
        return false
    end
    return ctx.was_recently_damaged(ctx.caster, tonumber(condition.seconds or condition.value or 2))
end)

ConditionRegistry:RegisterUseCondition("any_ally_recently_damaged", function(ctx, condition)
    if ctx.any_ally_recently_damaged == nil then
        return false
    end
    return ctx.any_ally_recently_damaged(ctx.caster, tonumber(condition.seconds or condition.value or 2))
end)

ConditionRegistry:RegisterUseCondition("no_enemy_within", function(ctx, condition)
    if ctx.count_enemies_around == nil then
        return false
    end
    return ctx.count_enemies_around(ctx.caster, tonumber(condition.radius or condition.value)) == 0
end)

ConditionRegistry:RegisterUseCondition("self_has_modifier", function(ctx, condition)
    return ctx.caster:HasModifier(tostring(condition.value))
end)

ConditionRegistry:RegisterUseCondition("self_not_has_modifier", function(ctx, condition)
    return not ctx.caster:HasModifier(tostring(condition.value))
end)

-- Target hard filters ------------------------------------------------------

ConditionRegistry:RegisterTargetFilter("hp_pct_lte", function(_ctx, target, condition)
    return health_pct(target) <= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("hp_pct_gte", function(_ctx, target, condition)
    return health_pct(target) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("mana_pct_lte", function(_ctx, target, condition)
    return mana_pct(target) <= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("mana_pct_gte", function(_ctx, target, condition)
    return mana_pct(target) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("health_lte", function(_ctx, target, condition)
    return target:GetHealth() <= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("health_gte", function(_ctx, target, condition)
    return target:GetHealth() >= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("distance_lte", function(ctx, target, condition)
    return distance_between(ctx.caster, target) <= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("has_tag", function(ctx, target, condition)
    return has_tag(ctx, target, tostring(condition.value))
end)

ConditionRegistry:RegisterTargetFilter("not_has_tag", function(ctx, target, condition)
    return not has_tag(ctx, target, tostring(condition.value))
end)

ConditionRegistry:RegisterTargetFilter("is_channeling", function(_ctx, target, _condition)
    return target.IsChanneling ~= nil and target:IsChanneling()
end)

ConditionRegistry:RegisterTargetFilter("is_casting", function(_ctx, target, _condition)
    if target.IsInAbilityPhase ~= nil and target:IsInAbilityPhase() then
        return true
    end
    return target.IsChanneling ~= nil and target:IsChanneling()
end)

ConditionRegistry:RegisterTargetFilter("is_stunned", function(_ctx, target, _condition)
    return target.IsStunned ~= nil and target:IsStunned()
end)

ConditionRegistry:RegisterTargetFilter("is_silenced", function(_ctx, target, _condition)
    return target.IsSilenced ~= nil and target:IsSilenced()
end)

ConditionRegistry:RegisterTargetFilter("is_rooted", function(_ctx, target, _condition)
    return target.IsRooted ~= nil and target:IsRooted()
end)

ConditionRegistry:RegisterTargetFilter("has_modifier", function(_ctx, target, condition)
    return target:HasModifier(tostring(condition.value))
end)

ConditionRegistry:RegisterTargetFilter("not_has_modifier", function(_ctx, target, condition)
    return not target:HasModifier(tostring(condition.value))
end)

ConditionRegistry:RegisterTargetFilter("is_hero", function(_ctx, target, _condition)
    return target.IsRealHero ~= nil and target:IsRealHero()
end)

ConditionRegistry:RegisterTargetFilter("is_summon", function(ctx, target, _condition)
    return has_tag(ctx, target, "summon")
end)

ConditionRegistry:RegisterTargetFilter("not_illusion", function(_ctx, target, _condition)
    return target.IsIllusion == nil or not target:IsIllusion()
end)

ConditionRegistry:RegisterTargetFilter("recently_damaged", function(ctx, target, condition)
    if ctx.was_recently_damaged == nil then
        return false
    end
    return ctx.was_recently_damaged(target, tonumber(condition.seconds or condition.value or 2))
end)

ConditionRegistry:RegisterTargetFilter("nearby_allies_gte", function(ctx, target, condition)
    if ctx.count_allies_around == nil then
        return false
    end
    return ctx.count_allies_around(target, tonumber(condition.radius or 600)) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("nearby_enemies_gte", function(ctx, target, condition)
    if ctx.count_enemies_around == nil then
        return false
    end
    return ctx.count_enemies_around(target, tonumber(condition.radius or 600)) >= tonumber(condition.value)
end)

ConditionRegistry:RegisterTargetFilter("has_affix", function(ctx, target, condition)
    if ctx.has_affix == nil then
        return false
    end
    return ctx.has_affix(target, tostring(condition.value))
end)

ConditionRegistry:RegisterTargetFilter("has_dispellable_buff", function(ctx, target, _condition)
    return ctx.has_dispellable_buff ~= nil and ctx.has_dispellable_buff(target)
end)

ConditionRegistry:RegisterTargetFilter("has_dispellable_debuff", function(ctx, target, _condition)
    return ctx.has_dispellable_debuff ~= nil and ctx.has_dispellable_debuff(target)
end)

ConditionRegistry:RegisterTargetFilter("has_shield", function(ctx, target, _condition)
    return ctx.has_shield ~= nil and ctx.has_shield(target)
end)

ConditionRegistry.HealthPct = health_pct
ConditionRegistry.ManaPct = mana_pct
ConditionRegistry.DistanceBetween = distance_between
ConditionRegistry.HasTag = has_tag
ConditionRegistry.IsValidEntity = is_valid_entity

return ConditionRegistry
