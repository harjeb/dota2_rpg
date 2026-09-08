local Context = require("tactics/condition_context")
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

local function action_actor(ctx, condition)
    if condition.action_actor == nil or condition.action_actor == "" then return ctx.caster end
    if type(ctx.get_action_actor) ~= "function" then return nil end
    return ctx.get_action_actor(condition.action_actor)
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
    local actor = action_actor(ctx, condition)
    if actor == nil or ctx.get_action_use_count == nil then return false end
    local count = tonumber(ctx.get_action_use_count(actor, logical_id))
    return count ~= nil and count < tonumber(condition.value)
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
    return ctx.caster:HasModifier(tostring(condition.modifier or condition.value))
end)

ConditionRegistry:RegisterUseCondition("self_not_has_modifier", function(ctx, condition)
    return not ctx.caster:HasModifier(tostring(condition.modifier or condition.value))
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

ConditionRegistry:RegisterTargetFilter("is_channeling", function(_ctx, target, _condition)
    return target.IsChanneling ~= nil and target:IsChanneling()
end)

ConditionRegistry:RegisterTargetFilter("is_casting", function(_ctx, target, _condition)
    if Context.Call(target, "IsInAbilityPhase") == true then return true end
    local active = Context.Call(target, "GetCurrentActiveAbility")
    if Context.Call(active, "IsInAbilityPhase") == true then return true end
    return Context.Call(target, "IsChanneling") == true
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
    return target:HasModifier(tostring(condition.modifier or condition.value))
end)

ConditionRegistry:RegisterTargetFilter("not_has_modifier", function(_ctx, target, condition)
    return not target:HasModifier(tostring(condition.modifier or condition.value))
end)

ConditionRegistry:RegisterTargetFilter("is_hero", function(_ctx, target, _condition)
    return target.IsRealHero ~= nil and target:IsRealHero()
end)

ConditionRegistry:RegisterTargetFilter("is_summon", function(ctx, target, _condition)
    if type(ctx.is_summon) == "function" then return ctx.is_summon(target) == true end
    return Context.IsSummon(target)
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


-- Conditions v2: explicit observations, shared by caster and selected target.
for _, resource in ipairs({ "hp", "mana" }) do
    local currentMethod = resource == "hp" and "GetHealth" or "GetMana"
    local maxMethod = resource == "hp" and "GetMaxHealth" or "GetMaxMana"
    for _, direction in ipairs({ "gte", "lte" }) do
        local function evaluate(unit, condition)
            local current = Context.Number(Context.Call(unit, currentMethod))
            local maximum = Context.Number(Context.Call(unit, maxMethod))
            local threshold = Context.Number(condition.value)
            if current == nil or maximum == nil or maximum <= 0 or threshold == nil then return false end
            local fraction = clamp(current / maximum, 0, 1)
            if direction == "gte" then return fraction >= threshold end
            return fraction <= threshold
        end
        ConditionRegistry:RegisterUseCondition("self_" .. resource .. "_pct_" .. direction,
            function(ctx, c) return evaluate(ctx.caster, c) end)
        ConditionRegistry:RegisterTargetFilter(resource .. "_pct_" .. direction,
            function(_, target, c) return evaluate(target, c) end)
    end
end
for _, side in ipairs({ "allies", "enemies" }) do
    ConditionRegistry:RegisterUseCondition("nearby_" .. side .. "_gte", function(ctx, c)
        local fn = ctx["count_" .. side .. "_around"]
        local count = fn and fn(ctx.caster, tonumber(c.radius or 600))
        return count ~= nil and count >= tonumber(c.value)
    end)
end
ConditionRegistry:RegisterUseCondition("alive_enemy_count_gte", function(ctx, c)
    return ctx.alive_enemy_count ~= nil and ctx.alive_enemy_count >= tonumber(c.value)
end)
for _, direction in ipairs({ "gte", "lte" }) do
    local function compare(actual, c)
        if actual == nil then return false end
        if direction == "gte" then return actual >= tonumber(c.value) end
        return actual <= tonumber(c.value)
    end
    ConditionRegistry:RegisterTargetFilter("missing_health_" .. direction, function(_, target, c)
        return compare(math.max(0, target:GetMaxHealth() - target:GetHealth()), c)
    end)
    for _, property in ipairs({ "stacks", "remaining" }) do
        local method = property == "stacks" and "GetStackCount" or "GetRemainingTime"
        local function evaluate(unit, c)
            return compare(Context.ModifierValue(unit, c.modifier, method), c)
        end
        ConditionRegistry:RegisterUseCondition("self_modifier_" .. property .. "_" .. direction,
            function(ctx, c) return evaluate(ctx.caster, c) end)
        ConditionRegistry:RegisterTargetFilter("modifier_" .. property .. "_" .. direction,
            function(_, target, c) return evaluate(target, c) end)
    end
end
ConditionRegistry:RegisterTargetFilter("distance_gte", function(ctx, target, c)
    return distance_between(ctx.caster, target) >= tonumber(c.value)
end)
ConditionRegistry:RegisterTargetFilter("exclude_self", function(ctx, target) return target ~= ctx.caster end)
ConditionRegistry:RegisterTargetFilter("is_controlled", function(_, target)
    for _, method in ipairs({ "IsStunned", "IsRooted", "IsSilenced", "IsHexed" }) do
        if Context.Call(target, method) == true then return true end
    end
    return false
end)
for id, method in pairs({ spell_immune = "IsMagicImmune" }) do
    ConditionRegistry:RegisterTargetFilter("is_" .. id, function(_, target)
        return Context.Call(target, method) == true
    end)
    ConditionRegistry:RegisterTargetFilter("not_" .. id, function(_, target)
        return Context.Call(target, method) == false
    end)
end
ConditionRegistry:RegisterUseCondition("ability_charges_gte", function(ctx, c)
    local actor = action_actor(ctx, c)
    if actor == nil or ctx.get_ability_charges == nil then return false end
    local n = ctx.get_ability_charges(actor, c.action_id or ctx.current_action_id)
    return n ~= nil and n >= tonumber(c.value)
end)

-- Special conditions use explicit observations; unknown is never zero.
local function observe(ctx, name, ...)
    if type(ctx[name]) ~= "function" then return nil end
    local ok, value = pcall(ctx[name], ...)
    if ok then return Context.Number(value) end
end
local function measured_compare(actual, threshold, direction)
    threshold = Context.Number(threshold)
    if actual == nil or threshold == nil then return false end
    if direction == "gte" then return actual >= threshold end
    return actual <= threshold
end
for _, direction in ipairs({ "gte", "lte" }) do
    ConditionRegistry:RegisterUseCondition("action_elapsed_" .. direction, function(ctx, c)
        local actor = action_actor(ctx, c)
        if actor == nil then return false end
        local elapsed = observe(ctx, "get_action_elapsed", actor, c.action_id or ctx.current_action_id)
        return elapsed ~= nil and elapsed >= 0 and measured_compare(elapsed, c.seconds or c.value, direction)
    end)
end
ConditionRegistry:RegisterTargetFilter("owned_by_self", function(ctx, target)
    if type(ctx.is_owned_by) ~= "function" then return false end
    local ok, owned = pcall(ctx.is_owned_by, target, ctx.caster)
    return ok and owned == true
end)
ConditionRegistry:RegisterTargetFilter("is_illusion", function(_, target)
    return Context.Call(target, "IsIllusion") == true
end)

ConditionRegistry.HealthPct = health_pct
ConditionRegistry.ManaPct = mana_pct
ConditionRegistry.DistanceBetween = distance_between
ConditionRegistry.HasTag = has_tag
ConditionRegistry.IsValidEntity = is_valid_entity

return ConditionRegistry
