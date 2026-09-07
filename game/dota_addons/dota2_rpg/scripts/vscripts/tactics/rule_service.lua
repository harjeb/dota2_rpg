local Conditions = require("tactics/condition_registry")

local RuleService = {}
RuleService.__index = RuleService

local MAX_RULES = 10
local VALID_TEAMS = { self = true, ally = true, enemy = true }
local VALID_APPROACH = { range_only = true, allow_approach = true }
local VALID_ACTION_KINDS = { ability = true, item = true, attack = true, move = true, wait = true }

local NUMERIC_LIMITS = {
    self_hp_pct_lte = { 0, 1 },
    self_hp_pct_gte = { 0, 1 },
    self_mana_pct_lte = { 0, 1 },
    self_mana_pct_gte = { 0, 1 },
    hp_pct_lte = { 0, 1 },
    hp_pct_gte = { 0, 1 },
    mana_pct_lte = { 0, 1 },
    mana_pct_gte = { 0, 1 },
    health_lte = { 0, 1000000 },
    health_gte = { 0, 1000000 },
    distance_lte = { 0, 5000 },
    alive_ally_count_gte = { 0, 20 },
    alive_enemy_count_lte = { 0, 20 },
    dead_ally_count_gte = { 0, 20 },
    elapsed_gte = { 0, 120 },
    elapsed_lte = { 0, 120 },
    action_use_count_lt = { 0, 100 },
    no_enemy_within = { 0, 3000 },
    nearby_allies_gte = { 0, 20 },
    nearby_enemies_gte = { 0, 20 },
}

local PRIORITY_TYPES = {
    lowest_hp_pct = true,
    highest_hp_pct = true,
    lowest_health = true,
    highest_health = true,
    most_missing_health = true,
    nearest = true,
    farthest = true,
    lowest_armor = true,
    highest_armor = true,
    lowest_magic_resistance = true,
    highest_attack_damage = true,
    prefer_tag = true,
    prefer_channeling = true,
    prefer_affix = true,
    prefer_dispellable_buff = true,
}

local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function parse_scalar(raw)
    if raw == nil or raw == "" then
        return nil
    end
    local number = tonumber(raw)
    if number ~= nil then
        return number
    end
    if raw == "true" then return true end
    if raw == "false" then return false end
    return tostring(raw)
end

local function condition_from_flat(prefix, args)
    local condition_type = tostring(args[prefix .. "_type"] or "")
    if condition_type == "" then
        return nil
    end
    return {
        type = condition_type,
        value = parse_scalar(args[prefix .. "_value"]),
        radius = tonumber(args[prefix .. "_radius"]),
        seconds = tonumber(args[prefix .. "_seconds"]),
        action_id = args[prefix .. "_action_id"],
    }
end

local function priority_from_flat(prefix, args)
    local priority_type = tostring(args[prefix .. "_type"] or "")
    if priority_type == "" then
        return nil
    end
    return {
        type = priority_type,
        value = parse_scalar(args[prefix .. "_value"]),
    }
end

local function compact_insert(list, value)
    if value ~= nil then
        table.insert(list, value)
    end
end

function RuleService.new(options)
    options = options or {}
    return setmetatable({
        get_phase = assert(options.get_phase, "get_phase is required"),
        is_roster_hero = assert(options.is_roster_hero, "is_roster_hero is required"),
        find_roster_hero = options.find_roster_hero,
        get_hero_key = options.get_hero_key or function(hero)
            if hero == nil then return nil end
            if hero.lineupHeroName ~= nil and hero.lineupHeroName ~= "" then
                return tostring(hero.lineupHeroName)
            end
            return hero.GetUnitName ~= nil and tostring(hero:GetUnitName()) or nil
        end,
        is_action_allowed = assert(options.is_action_allowed, "is_action_allowed is required"),
        state = assert(options.state, "current-run state is required"),
        conditions = options.conditions or Conditions,
    }, RuleService)
end

function RuleService:DecodeFlat(args)
    local rule = {
        id = tostring(args.rule_id or ""),
        enabled = tonumber(args.enabled or 1) ~= 0,
        action = {
            kind = tostring(args.action_kind or ""),
            logical_id = tostring(args.action_id or ""),
            name = args.action_name ~= "" and args.action_name or nil,
            cast_type = args.cast_type ~= "" and args.cast_type or nil,
            target_mode = args.target_mode ~= "" and args.target_mode or nil,
            target_team = args.target_team ~= "" and args.target_team or nil,
            desired_toggle_state = args.desired_toggle_state == "1" and true
                or (args.desired_toggle_state == "0" and false or nil),
            aoe_radius = tonumber(args.aoe_radius),
        },
        target = {
            team = tostring(args.target_team or "enemy"),
            types = {},
        },
        target_filters = {},
        target_priorities = {},
        use_conditions = {},
        approach = tostring(args.approach or "range_only"),
        chase_timeout = tonumber(args.chase_timeout),
        max_chase_distance = tonumber(args.max_chase_distance),
        min_aoe_hits = tonumber(args.min_aoe_hits),
        aoe_prefer_tag = args.aoe_prefer_tag ~= "" and args.aoe_prefer_tag or nil,
    }

    for unit_type in string.gmatch(tostring(args.target_types or "hero"), "[^,]+") do
        table.insert(rule.target.types, unit_type)
    end

    compact_insert(rule.target_filters, condition_from_flat("target_filter_1", args))
    compact_insert(rule.target_filters, condition_from_flat("target_filter_2", args))
    compact_insert(rule.target_priorities, priority_from_flat("target_priority_1", args))
    compact_insert(rule.target_priorities, priority_from_flat("target_priority_2", args))
    compact_insert(rule.use_conditions, condition_from_flat("use_condition_1", args))
    compact_insert(rule.use_conditions, condition_from_flat("use_condition_2", args))

    return rule
end

function RuleService:ValidateCondition(condition, registry)
    if condition == nil then
        return true, nil
    end
    if registry[condition.type] == nil then
        return false, "unknown_condition:" .. tostring(condition.type)
    end

    local limits = NUMERIC_LIMITS[condition.type]
    if limits ~= nil then
        local value = tonumber(condition.value or condition.radius)
        if value == nil then
            return false, "numeric_value_required:" .. condition.type
        end
        condition.value = clamp(value, limits[1], limits[2])
    end

    if condition.seconds ~= nil then
        condition.seconds = clamp(tonumber(condition.seconds) or 0, 0, 30)
    end
    if condition.radius ~= nil then
        condition.radius = clamp(tonumber(condition.radius) or 0, 0, 3000)
    end
    return true, nil
end

function RuleService:ValidateRule(player_id, hero, rule)
    if not VALID_ACTION_KINDS[rule.action.kind] then
        return false, "invalid_action_kind"
    end
    if rule.action.logical_id == "" then
        return false, "missing_action_id"
    end
    if not VALID_TEAMS[rule.target.team] then
        return false, "invalid_target_team"
    end
    if not VALID_APPROACH[rule.approach] then
        return false, "invalid_approach"
    end
    if not self.is_action_allowed(player_id, hero, rule.action) then
        return false, "action_not_allowed_for_hero"
    end
    if #rule.target_filters > 2 or #rule.target_priorities > 2 or #rule.use_conditions > 2 then
        return false, "too_many_conditions"
    end

    for _, condition in ipairs(rule.target_filters) do
        local ok, reason = self:ValidateCondition(condition, self.conditions.target_filters)
        if not ok then return false, reason end
    end
    for _, condition in ipairs(rule.use_conditions) do
        local ok, reason = self:ValidateCondition(condition, self.conditions.use_conditions)
        if not ok then return false, reason end
    end
    for _, priority in ipairs(rule.target_priorities) do
        if not PRIORITY_TYPES[priority.type] then
            return false, "unknown_priority:" .. tostring(priority.type)
        end
    end

    if rule.chase_timeout ~= nil then
        rule.chase_timeout = clamp(rule.chase_timeout, 0.1, 5.0)
    end
    if rule.max_chase_distance ~= nil then
        rule.max_chase_distance = clamp(rule.max_chase_distance, 100, 2000)
    end
    if rule.min_aoe_hits ~= nil then
        rule.min_aoe_hits = math.floor(clamp(rule.min_aoe_hits, 1, 20))
    end
    return true, nil
end

function RuleService:GetHeroRules(hero)
    local key = self.get_hero_key(hero)
    if key == nil or key == "" then
        return {}
    end
    self.state.rules[key] = self.state.rules[key] or {}
    return self.state.rules[key]
end

function RuleService:UpdateRule(player_id, hero_index, slot, flat_args)
    if self.get_phase() ~= "PREPARE" then
        return false, "wrong_phase"
    end
    slot = tonumber(slot)
    if slot == nil or slot < 1 or slot > MAX_RULES or slot ~= math.floor(slot) then
        return false, "invalid_rule_slot"
    end
    local rule_count = flat_args.rule_count ~= nil and tonumber(flat_args.rule_count) or nil
    if flat_args.rule_count ~= nil and (rule_count == nil or rule_count < 1
        or rule_count > MAX_RULES or rule_count ~= math.floor(rule_count) or slot > rule_count) then
        return false, "invalid_rule_count"
    end

    local hero = EntIndexToHScript(tonumber(hero_index or -1))
    if (hero == nil or hero:IsNull()) and self.find_roster_hero ~= nil then
        hero = self.find_roster_hero(player_id, flat_args.hero_name)
    end
    if hero == nil or hero:IsNull() or not self.is_roster_hero(player_id, hero) then
        return false, "invalid_hero"
    end

    local rule = self:DecodeFlat(flat_args)
    local hero_key = self.get_hero_key(hero)
    if hero_key == nil or hero_key == "" then
        return false, "missing_hero_key"
    end
    rule.id = rule.id ~= "" and rule.id or (hero_key .. ":" .. slot)
    local ok, reason = self:ValidateRule(player_id, hero, rule)
    if not ok then
        return false, reason
    end

    local rules = self:GetHeroRules(hero)
    if rule_count ~= nil then
        for index = rule_count + 1, MAX_RULES do
            rules[index] = nil
            CustomNetTables:SetTableValue("rpg_rules", hero_key .. ":" .. tostring(index), {})
        end
    end
    rules[slot] = rule
    self:SyncRule(player_id, hero, slot, rule)
    return true, nil
end

function RuleService:SyncRule(_player_id, hero, slot, rule)
    local hero_key = self.get_hero_key(hero)
    if hero_key == nil or hero_key == "" then
        return
    end
    local key = hero_key .. ":" .. tostring(slot)
    CustomNetTables:SetTableValue("rpg_rules", key, {
        id = rule.id,
        enabled = rule.enabled and 1 or 0,
        action_kind = rule.action.kind,
        action_id = rule.action.logical_id,
        target_team = rule.target.team,
        approach = rule.approach,
        target_filter_1 = rule.target_filters[1] and rule.target_filters[1].type or "",
        target_filter_2 = rule.target_filters[2] and rule.target_filters[2].type or "",
        target_priority_1 = rule.target_priorities[1] and rule.target_priorities[1].type or "",
        target_priority_2 = rule.target_priorities[2] and rule.target_priorities[2].type or "",
        use_condition_1 = rule.use_conditions[1] and rule.use_conditions[1].type or "",
        use_condition_2 = rule.use_conditions[2] and rule.use_conditions[2].type or "",
    })
end

function RuleService:SendResult(player_id, request_id, ok, reason)
    local player = PlayerResource:GetPlayer(player_id)
    if player == nil then return end
    CustomGameEventManager:Send_ServerToPlayer(player, "rpg_rule_update_result", {
        request_id = tostring(request_id or ""),
        ok = ok and 1 or 0,
        reason = reason or "",
    })
end

function RuleService:InstallEventListener()
    if self._listener_installed then
        return
    end
    self._listener_installed = true
    CustomGameEventManager:RegisterListener("rpg_update_rule", function(event_source_index, args)
        args = args or {}
        local player_id = tonumber(args.PlayerID)
        if player_id == nil then
            player_id = tonumber(event_source_index) or 0
        end
        local ok, reason = self:UpdateRule(player_id, args.hero_index, args.slot, args)
        self:SendResult(player_id, args.request_id, ok, reason)
    end)
end

return RuleService
