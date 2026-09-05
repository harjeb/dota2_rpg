local root = arg[1] or "../game/scripts/vscripts"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

CustomNetTables = { SetTableValue = function() end }
local hero = { id = 42 }
function hero:entindex() return self.id end
function hero:IsNull() return false end
function EntIndexToHScript(id) if id == 42 then return hero end return nil end

local RuleService = require("tactics/rule_service")
local state = { rules = {} }
local service = RuleService.new({
    get_phase = function() return "PREPARE" end,
    is_roster_hero = function(_player_id, candidate) return candidate == hero end,
    is_action_allowed = function(_player_id, _hero, action)
        return action.logical_id == "primary_heal"
    end,
    state = state,
})

local base = {
    hero_index = "42",
    enabled = "1",
    action_kind = "ability",
    action_id = "primary_heal",
    target_team = "ally",
    target_types = "hero",
    target_mode = "unit",
    approach = "range_only",
    target_filter_1_type = "hp_pct_lte",
    target_filter_1_value = "0.25",
    target_priority_1_type = "lowest_hp_pct",
    use_condition_1_type = "self_mana_pct_gte",
    use_condition_1_value = "0.2",
}

local ok, reason = service:UpdateRule(0, 42, 1, base)
assert(ok, reason)

local second = {}
for key, value in pairs(base) do second[key] = value end
second.target_filter_1_value = "0.70"
ok, reason = service:UpdateRule(0, 42, 2, second)
assert(ok, reason)
assert(state.rules[42][1].action.logical_id == state.rules[42][2].action.logical_id)
assert(state.rules[42][1].target_filters[1].value == 0.25)
assert(state.rules[42][2].target_filters[1].value == 0.70)

local bad = {}
for key, value in pairs(base) do bad[key] = value end
bad.target_filter_1_type = "target_exists"
ok, reason = service:UpdateRule(0, 42, 3, bad)
assert(not ok and string.find(reason, "unknown_condition") ~= nil)

print("rule service tests passed")
