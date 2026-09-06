-- Default tactic policy: create one fallback attack rule only.
-- Do not pad the editor to active-skill count, item count or a fixed slot count.

local DefaultRules = {}

local function has_action(rule)
    if type(rule) ~= "table" then return false end
    local action = rule.action
    if type(action) == "string" then return action ~= "" end
    if type(action) ~= "table" then return false end
    return action.kind ~= nil
        or action.type ~= nil
        or action.logical_id ~= nil
        or action.name ~= nil
end

function DefaultRules.CreateAttackNearestRule()
    return {
        id = "default_attack_nearest",
        enabled = true,
        action = {
            kind = "attack",
        },
        target_filters = {
            team = "enemy",
        },
        target_priorities = {
            "nearest",
        },
        use_conditions = {},
        approach = "range_only",
        is_default = true,
    }
end

function DefaultRules.Normalize(saved_rules)
    local result = {}

    -- Preserve real player-authored rules. Remove only explicitly marked padding or
    -- empty placeholders; never infer that a valid-looking rule is disposable.
    for _, rule in ipairs(saved_rules or {}) do
        if type(rule) == "table"
            and rule.is_padding ~= true
            and rule.placeholder ~= true
            and has_action(rule) then
            result[#result + 1] = rule
        end
    end

    if #result == 0 then
        result[1] = DefaultRules.CreateAttackNearestRule()
    end

    return result
end

function DefaultRules.InitializeHeroRules(rules_by_hero, hero_key)
    assert(type(rules_by_hero) == "table", "rules_by_hero must be a table")
    assert(hero_key ~= nil, "hero_key is required")

    rules_by_hero[hero_key] = DefaultRules.Normalize(rules_by_hero[hero_key])
    return rules_by_hero[hero_key]
end

return DefaultRules
