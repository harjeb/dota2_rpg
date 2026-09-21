-- Generate defaults from currently learned active abilities; preserve authored lists.

local Behavior = require("tactics/ability_behavior")
local DefaultRules = {}

-- Native Empower is always on its caster (always_on=1, should_self_cast=0).
-- Marci's partner buffs likewise provide her own passive benefits. An ally pool
-- includes the caster, so nearest alone otherwise continually selects self when
-- the native filter permits it. Keep this policy in generated defaults only.
local partner_buffs = {
    magnataur_empower = true,
    marci_bodyguard = true,
    marci_guardian = true,
}

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

-- 只认英雄：野怪、小兵和召唤物保持原有站位，不受这条默认策略影响。
local function is_ranged_hero(unit)
    if unit == nil then return false end
    local real_hero = call(unit, "IsRealHero")
    if real_hero == nil then real_hero = call(unit, "IsHero") end
    if real_hero ~= true then return false end
    -- 原生标记优先；拿不到时退回攻击距离（近战约 150，远程 400 以上）。
    -- 注意先落到局部变量：方法不返回值时，直接 tonumber(call(...)) 会变成零参数调用而报错。
    local ranged = call(unit, "IsRangedAttacker")
    if ranged ~= nil then return ranged == true end
    local range = call(unit, "Script_GetAttackRange")
    return tonumber(range) ~= nil and tonumber(range) > 300
end

-- 远程英雄的普攻默认在最大攻击距离站位（风筝），近战英雄不变。
-- 只处理普攻行：技能行继续由玩家选择默认 / 固定距离 / 原生施法距离。
-- 已经显式配过 positioning_mode 的行原样保留，玩家和关卡配置都不会被覆盖。
function DefaultRules.ApplyRangedAttackPosture(rule, unit)
    if type(rule) ~= "table" or type(rule.action) ~= "table" then return rule end
    if rule.action.kind ~= "attack" or rule.action.positioning_mode ~= nil then return rule end
    if not is_ranged_hero(unit) then return rule end
    rule.action.positioning_mode = "attack_range"
    return rule
end

local flag = Behavior.HasFlag

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
            local behavior = Behavior.Read(ability)
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
            -- Reincarnation may expose a native active cast. Leave it visible but
            -- disabled by default so its death-triggered revive stays available.
            if name == "skeleton_king_reincarnation" then rule.enabled = false end
            rule.target.team = team
            if team == "ally" and partner_buffs[name] then
                rule.target_filters = { { type = "exclude_self" } }
            end
            -- Native action validation supplies mana/cooldown/range checks.
            -- No arbitrary HP threshold or delayed ultimate usage is needed.
            result[#result + 1] = rule
        end
    end
    result[#result + 1] = DefaultRules.ApplyRangedAttackPosture(DefaultRules.CreateAttackNearestRule(), hero)
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
