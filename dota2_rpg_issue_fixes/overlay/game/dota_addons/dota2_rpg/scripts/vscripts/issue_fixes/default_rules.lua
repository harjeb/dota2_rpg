-- Generate defaults from currently learned active abilities; preserve authored lists.

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
            logical_id = "basic_attack",
        },
        target = { team = "enemy", types = { "hero", "monster", "summon" } },
        target_filters = {},
        target_priorities = {
            { type = "nearest" },
        },
        use_conditions = {},
        approach = "range_only",
        is_default = true,
    }
end

local function call(entity, method)
    if entity ~= nil and entity[method] ~= nil then return entity[method](entity) end
end

local function flag(value, mask)
    return value ~= nil and mask ~= nil and mask > 0 and math.floor(value / mask) % 2 == 1
end

function DefaultRules.CreateForHero(hero)
    local result, seen = {}, {}
    for slot = 0, (call(hero, "GetAbilityCount") or 0) - 1 do
        local ability = hero:GetAbilityByIndex(slot)
        local valid = ability ~= nil and call(ability, "IsNull") ~= true
        local name = valid and call(ability, "GetAbilityName") or ""
        if valid
            and name ~= "" and name ~= "generic_hidden"
            and not name:match("^special_bonus") and not name:match("^rubick_hidden%d+$")
            and call(ability, "IsPassive") ~= true and call(ability, "IsHidden") ~= true
            and call(ability, "IsActivated") ~= false and (call(ability, "GetLevel") or 0) > 0
            and not seen[name] then
            seen[name] = true
            local behavior = call(ability, "GetBehaviorInt") or call(ability, "GetBehavior") or 0
            local team = "enemy"
            local targeted = flag(behavior, DOTA_ABILITY_BEHAVIOR_UNIT_TARGET)
                or flag(behavior, DOTA_ABILITY_BEHAVIOR_POINT)
                or flag(behavior, DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING)
            if not targeted and (flag(behavior, DOTA_ABILITY_BEHAVIOR_NO_TARGET)
                or flag(behavior, DOTA_ABILITY_BEHAVIOR_TOGGLE)) then
                team = "self"
            elseif call(ability, "GetAbilityTargetTeam") == DOTA_UNIT_TARGET_TEAM_FRIENDLY
                and DOTA_UNIT_TARGET_TEAM_FRIENDLY ~= nil then
                team = "ally"
            end
            local rule = DefaultRules.CreateAttackNearestRule()
            rule.id = "default_ability_" .. name
            rule.action = { kind = "ability", logical_id = name }
            rule.target.team = team
            -- Native action validation supplies mana/cooldown/range checks.
            -- No arbitrary HP threshold or delayed ultimate usage is needed.
            result[#result + 1] = rule
        end
    end
    result[#result + 1] = DefaultRules.CreateAttackNearestRule()
    return result
end

function DefaultRules.IsDefaultOnly(rules)
    if type(rules) ~= "table" or #rules == 0 then return false end
    for _, rule in ipairs(rules) do
        if type(rule) ~= "table" or rule.is_default ~= true then return false end
    end
    return true
end

function DefaultRules.Normalize(saved_rules, hero)
    local result = {}

    -- Preserve real player-authored rules. Remove only explicitly marked padding or
    -- empty placeholders; never infer that a valid-looking rule is disposable.
    for _, rule in ipairs(type(saved_rules) == "table" and saved_rules or {}) do
        if type(rule) == "table"
            and rule.is_padding ~= true
            and rule.placeholder ~= true
            and has_action(rule) then
            result[#result + 1] = rule
        end
    end

    if #result == 0 or (hero ~= nil and DefaultRules.IsDefaultOnly(result)) then
        result = DefaultRules.CreateForHero(hero)
    end

    return result
end

function DefaultRules.InitializeHeroRules(rules_by_hero, hero_key, hero)
    assert(type(rules_by_hero) == "table", "rules_by_hero must be a table")
    assert(hero_key ~= nil, "hero_key is required")

    rules_by_hero[hero_key] = DefaultRules.Normalize(rules_by_hero[hero_key], hero)
    return rules_by_hero[hero_key]
end

return DefaultRules
