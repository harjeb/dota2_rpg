local Conditions = require("tactics/condition_registry")
local okLog, RuntimeLog = pcall(require, "issue_fixes.runtime_log")
if not okLog then RuntimeLog = { Write = print } end

local RuleService = {}
RuleService.__index = RuleService

-- Only persisted rules are migrated; newly submitted removed IDs stay invalid.
local REMOVED_CONDITIONS = {
    dead_ally_count_gte = true,
    self_strength_gte = true,
    self_agility_gte = true,
    owned_summons_gte = true,
    owned_summons_lte = true,
    action_used_within = true,
    action_not_used_within = true,
    not_illusion = true,
    is_creep = true,
    is_invulnerable = true,
    not_invulnerable = true,
    has_tag = true,
    not_has_tag = true,
}

function RuleService.StripRemovedConditions(rule)
    if type(rule) ~= "table" then return rule end
    for _, field in ipairs({ "use_conditions", "target_filters" }) do
        local conditions = rule[field]
        if type(conditions) == "table" then
            for index = #conditions, 1, -1 do
                local condition = conditions[index]
                if type(condition) == "table" and REMOVED_CONDITIONS[condition.type] then
                    table.remove(conditions, index)
                end
            end
        end
    end
    return rule
end

local MAX_RULES = 32
local Context = require("tactics/condition_context")
local finite = Context.Number
local VALID_TEAMS = { self = true, ally = true, enemy = true }
local VALID_APPROACH = { range_only = true, allow_approach = true }
local VALID_ACTION_KINDS = { ability = true, item = true, attack = true, move = true, wait = true }

local NUMERIC_LIMITS = {
    action_elapsed_gte = { 0, 86400 },
    action_elapsed_lte = { 0, 86400 },
    tiny_grab_hp_pct_lte = { 0, 1 },
    tiny_grab_hp_pct_gte = { 0, 1 },
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
    distance_gte = { 0, 5000 },
    missing_health_gte = { 0, 1000000 },
    missing_health_lte = { 0, 1000000 },
    alive_enemy_count_gte = { 0, 1000 },
    ability_charges_gte = { 0, 1000 },
    alive_ally_count_gte = { 0, 20 },
    alive_enemy_count_lte = { 0, 20 },
    elapsed_gte = { 0, 120 },
    elapsed_lte = { 0, 120 },
    action_use_count_lt = { 0, 100 },
    no_enemy_within = { 0, 3000 },
    nearby_allies_gte = { 0, 20 },
    nearby_enemies_gte = { 0, 20 },
}

for _, prefix in ipairs({ "", "self_" }) do
    for _, suffix in ipairs({ "gte", "lte" }) do
        NUMERIC_LIMITS[prefix .. "modifier_stacks_" .. suffix] = { 0, 1000000 }
        NUMERIC_LIMITS[prefix .. "modifier_remaining_" .. suffix] = { 0, 86400 }
    end
end

local PRIORITY_TYPES = {
    lowest_attack_damage = true,
    highest_magic_resistance = true,
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
    if type(raw) ~= "string" and type(raw) ~= "number" and type(raw) ~= "boolean" then return raw end
    local number = finite(raw)
    if number ~= nil then
        return number
    end
    if raw == "true" then return true end
    if raw == "false" then return false end
    return tostring(raw)
end

local function condition_from_flat(prefix, args)
    local condition_type = args[prefix .. "_type"] or args[prefix] or ""
    if condition_type == "" then
        return nil
    end
    return {
        type = condition_type,
        value = parse_scalar(args[prefix .. "_value"]),
        radius = args[prefix .. "_radius"],
        seconds = args[prefix .. "_seconds"],
        modifier = args[prefix .. "_modifier"],
        action_id = args[prefix .. "_action_id"],
        action_actor = args[prefix .. "_action_actor"],
        target_actor = args[prefix .. "_target_actor"],
    }
end

local function priority_from_flat(prefix, args)
    local priority_type = args[prefix .. "_type"] or args[prefix] or ""
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
        is_target_actor_allowed = options.is_target_actor_allowed,
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
    local toggle = args.desired_toggle_state
    if toggle == "0" or toggle == 0 or toggle == "false" then toggle = false
    elseif toggle == "1" or toggle == 1 or toggle == "true" then toggle = true
    elseif toggle == "" then toggle = nil end
    local rule = {
        id = tostring(args.rule_id or ""),
        enabled = args.enabled ~= false and args.enabled ~= 0 and args.enabled ~= "0",
        action = {
            kind = tostring(args.action_kind or ""),
            logical_id = tostring(args.action_id or ""),
            name = args.action_name ~= "" and args.action_name or nil,
            cast_type = args.cast_type ~= "" and args.cast_type or nil,
            target_mode = args.target_mode ~= "" and args.target_mode or nil,
            target_team = args.target_team ~= "" and args.target_team or nil,
            desired_toggle_state = toggle,
            destination = args.destination ~= "" and args.destination or nil,
            cast_preference = args.cast_preference ~= "" and args.cast_preference or nil,
            aoe_radius = args.aoe_radius,
        },
        target = {
            team = tostring(args.target_team or "enemy"),
            types = {},
        },
        target_filters = {},
        target_priorities = {},
        use_conditions = {},
        approach = tostring(args.approach or "range_only"),
        chase_timeout = args.chase_timeout,
        max_chase_distance = args.max_chase_distance,
        min_aoe_hits = args.min_aoe_hits,
        aoe_prefer_tag = args.aoe_prefer_tag ~= "" and args.aoe_prefer_tag or nil,
    }

    for unit_type in string.gmatch(tostring(args.target_types or "hero"), "[^,]+") do
        table.insert(rule.target.types, unit_type)
    end

    for index = 1, 4 do
        compact_insert(rule.target_filters, condition_from_flat("target_filter_" .. index, args))
        compact_insert(rule.use_conditions, condition_from_flat("use_condition_" .. index, args))
    end
    for index = 1, 2 do
        compact_insert(rule.target_priorities, priority_from_flat("target_priority_" .. index, args))
    end

    return rule
end

function RuleService:ValidateCondition(condition, registry)
    if type(condition) ~= "table" or type(condition.type) ~= "string" then
        return false, "invalid_condition"
    end
    if registry[condition.type] == nil then return false, "unknown_condition:" .. condition.type end
    for _, field in ipairs({ "modifier", "action_id", "action_actor", "target_actor" }) do
        local value = condition[field]
        if value == "" then condition[field] = nil
        elseif value ~= nil and (type(value) ~= "string" or #value > 256) then
            return false, "invalid_condition_" .. field
        end
    end
    if condition.type == "specified_enemy" then
        if not require("tactics/rule_snapshot").ValidTargetActor(condition.target_actor) then
            return false, "invalid_condition_target_actor"
        end
    elseif condition.target_actor ~= nil then
        return false, "unexpected_condition_target_actor"
    end
    if condition.action_actor ~= nil then
        if not condition.action_actor:match("^[%w_:]+$") or condition.action_id == nil then
            return false, "invalid_condition_action_actor"
        end
        if condition.type ~= "action_elapsed_gte" and condition.type ~= "action_elapsed_lte"
            and condition.type ~= "action_use_count_lt" and condition.type ~= "ability_charges_gte" then
            return false, "unexpected_condition_action_actor"
        end
    end
    local limits = NUMERIC_LIMITS[condition.type]
    if limits then
        local isTimer = condition.type:find("action_elapsed_", 1, true)
        local value = finite(condition.value or (isTimer and condition.seconds) or (condition.type == "no_enemy_within" and condition.radius))
        if value == nil or value < limits[1] or value > limits[2] then
            return false, "invalid_numeric_value:" .. condition.type
        end
        condition.value = value
    elseif condition.value ~= nil and type(condition.value) ~= "string"
        and finite(condition.value) == nil then
        return false, "invalid_condition_value"
    end
    if condition.type:find("modifier_stacks_", 1, true) or condition.type:find("modifier_remaining_", 1, true) then
        if condition.modifier == nil then return false, "modifier_required" end
    elseif condition.type:find("has_modifier", 1, true) or condition.type == "has_affix" or condition.type == "phase_is" then
        local name = condition.modifier or condition.value
        if type(name) ~= "string" or name == "" or #name > 256 then return false, "string_value_required" end
    end
    for _, field in ipairs({ "seconds", "radius" }) do
        if condition[field] == "" then condition[field] = nil end
        if condition[field] ~= nil then
            local n = finite(condition[field])
            if n == nil or n < 0 or n > (field == "seconds" and 86400 or 30000) then
                return false, "invalid_condition_" .. field
            end
            condition[field] = n
        end
    end
    if condition.type:find("recently_damaged", 1, true) then
        local seconds = finite(condition.seconds or condition.value or 2)
        if seconds == nil or seconds < 0 or seconds > 86400 then return false, "invalid_condition_seconds" end
        condition.seconds = seconds
    end
    return true, nil
end

function RuleService:ValidateRule(player_id, hero, rule)
    if type(rule) ~= "table" or type(rule.action) ~= "table" or type(rule.target) ~= "table"
        or type(rule.target_filters) ~= "table" or type(rule.use_conditions) ~= "table"
        or type(rule.target_priorities) ~= "table" then return false, "invalid_rule" end
    if type(rule.action.logical_id) ~= "string" or #rule.action.logical_id > 256 then return false, "invalid_action_id" end
    if not require("tactics/special_targets").ValidDestination(rule.action.logical_id, rule.action.destination) then
        return false, "invalid_destination"
    end
    local preference = rule.action.cast_preference
    if preference ~= nil and preference ~= "auto" and preference ~= "unit" and preference ~= "point" then
        return false, "invalid_cast_preference"
    end
    if rule.action.desired_toggle_state ~= nil and type(rule.action.desired_toggle_state) ~= "boolean" then
        return false, "invalid_toggle_state"
    end
    for _, key in ipairs({ "name", "cast_type", "target_mode", "target_team" }) do
        if rule.action[key] ~= nil and type(rule.action[key]) ~= "string" then return false, "invalid_action_" .. key end
    end
    for _, pair in ipairs({ { rule, "chase_timeout" }, { rule, "max_chase_distance" },
        { rule, "min_aoe_hits" }, { rule.action, "aoe_radius" } }) do
        local object, key = pair[1], pair[2]
        if object[key] == "" then object[key] = nil end
        if object[key] ~= nil then
            local n = finite(object[key])
            if n == nil or n < 0 then return false, "invalid_" .. key end
            object[key] = n
        end
    end
    if not VALID_ACTION_KINDS[rule.action.kind] then
        return false, "invalid_action_kind"
    end
    if rule.action.logical_id == "" then
        return false, "missing_action_id"
    end
    if type(rule.target.types) ~= "table" then return false, "invalid_target_types" end
    for _, unitType in pairs(rule.target.types) do
        if unitType ~= "hero" and unitType ~= "monster" and unitType ~= "summon" then return false, "invalid_target_type" end
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
    for _, pair in ipairs({ { rule.target_filters, 4 }, { rule.use_conditions, 4 }, { rule.target_priorities, 2 } }) do
        local count = 0
        for index in pairs(pair[1]) do
            if type(index) ~= "number" or finite(index) == nil or index < 1
                or index ~= math.floor(index) or index > pair[2] then return false, "too_many_conditions" end
            count = count + 1
        end
        for index = 1, count do
            if pair[1][index] == nil then return false, "sparse_conditions" end
        end
    end

    for _, condition in ipairs(rule.target_filters) do
        local ok, reason = self:ValidateCondition(condition, self.conditions.target_filters)
        if not ok then return false, reason end
        if condition.type == "specified_enemy" then
            if rule.target.team ~= "enemy" then return false, "invalid_specified_enemy_team" end
            if self.is_target_actor_allowed ~= nil
                and not self.is_target_actor_allowed(player_id, hero, condition.target_actor) then
                return false, "target_actor_not_in_current_roster"
            end
        end
    end
    for _, condition in ipairs(rule.use_conditions) do
        local ok, reason = self:ValidateCondition(condition, self.conditions.use_conditions)
        if not ok then return false, reason end
    end
    for _, priority in ipairs(rule.target_priorities) do
        if type(priority) ~= "table" or type(priority.type) ~= "string" then return false, "invalid_priority" end
        if (priority.type == "prefer_tag" or priority.type == "prefer_affix")
            and (type(priority.value) ~= "string" or priority.value == "" or #priority.value > 256) then
            return false, "priority_value_required"
        end
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
    for _, rule in pairs(self.state.rules[key]) do
        RuleService.StripRemovedConditions(rule)
    end
    return self.state.rules[key]
end

function RuleService:UpdateRule(player_id, hero_index, slot, flat_args)
    if type(flat_args) ~= "table" then return false, "invalid_payload" end
    for key, value in pairs(flat_args) do
        if type(key) ~= "string" or (type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean") then
            return false, "invalid_payload_type"
        end
        if type(value) == "number" and finite(value) == nil then return false, "invalid_payload_number" end
        local index = key:match("^use_condition_(%d+)") or key:match("^target_filter_(%d+)")
        local priorityIndex = key:match("^target_priority_(%d+)")
        if (index and (tonumber(index) < 1 or tonumber(index) > 4))
            or (priorityIndex and (tonumber(priorityIndex) < 1 or tonumber(priorityIndex) > 2)) then
            return false, "too_many_conditions"
        end
    end
    if self.get_phase() ~= "PREPARE" then
        return false, "wrong_phase"
    end
    for _, key in ipairs({ "action_kind", "action_id", "action_name", "cast_type", "target_mode",
        "target_team", "target_types", "approach", "hero_name", "aoe_prefer_tag" }) do
        if flat_args[key] ~= nil and type(flat_args[key]) ~= "string" then return false, "invalid_" .. key end
    end
    local enabled = flat_args.enabled
    if enabled ~= nil and enabled ~= true and enabled ~= false and enabled ~= 0 and enabled ~= 1
        and enabled ~= "0" and enabled ~= "1" then return false, "invalid_enabled" end
    slot = finite(slot)
    if slot == nil or slot < 1 or slot > MAX_RULES or slot ~= math.floor(slot) then
        return false, "invalid_rule_slot"
    end
    local rule_count = flat_args.rule_count ~= nil and finite(flat_args.rule_count) or nil
    if flat_args.rule_count ~= nil and (rule_count == nil or rule_count < 1
        or rule_count > MAX_RULES or rule_count ~= math.floor(rule_count) or slot > rule_count) then
        return false, "invalid_rule_count"
    end

    local index = finite(hero_index)
    local hero
    if index and index >= 0 and index == math.floor(index) then
        local ok, entity = pcall(EntIndexToHScript, index)
        if ok then hero = entity end
    end
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
    local payload = {
        desired_toggle_state = rule.action.desired_toggle_state == nil and "" or (rule.action.desired_toggle_state and "1" or "0"),
        destination = rule.action.destination or "target",
        cast_preference = rule.action.cast_preference or "auto",
        target_types = table.concat(rule.target.types or {}, ","),
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
    }
    for prefix, list in pairs({ use_condition = rule.use_conditions, target_filter = rule.target_filters,
        target_priority = rule.target_priorities }) do
        for index = 1, (prefix == "target_priority" and 2 or 4) do
            local item = list[index] or {}
            local keyPrefix = prefix .. "_" .. index
            payload[keyPrefix] = item.type or ""
            for _, field in ipairs({ "type", "value", "radius", "seconds", "action_id", "action_actor", "target_actor", "modifier" }) do
                payload[keyPrefix .. "_" .. field] = item[field] ~= nil and item[field] or ""
            end
        end
    end
    CustomNetTables:SetTableValue("rpg_rules", key, payload)
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
        RuntimeLog.Write(string.format("RuleUpdate player=%s hero=%s slot=%s action=%s ok=%s reason=%s",
            tostring(player_id), tostring(args.hero_index), tostring(args.slot), tostring(args.action_id or ""),
            tostring(ok), tostring(reason or "")))
        self:SendResult(player_id, args.request_id, ok, reason)
    end)
end

return RuleService
