local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 8
DOTA_ABILITY_BEHAVIOR_POINT = 16
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
DOTA_ABILITY_BEHAVIOR_TOGGLE = 512
DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING = 1073741824
DOTA_UNIT_TARGET_TEAM_FRIENDLY = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
local EnemyRules = require("issue_fixes.enemy_rules")
local function ability(name, behavior, team, radius, passive)
    return { GetAbilityName = function() return name end, GetBehavior = function() return behavior end,
        GetAbilityTargetTeam = function() return team end, GetLevel = function() return 4 end,
        GetAOERadius = function() return radius or 0 end, IsPassive = function() return passive == true end }
end
local nova = ability("crystal_maiden_crystal_nova", 16, 2, 425)
local frostbite = ability("crystal_maiden_frostbite", 8, 2)
local aura = ability("crystal_maiden_brilliance_aura", 2, 1, 0, true)
local field = ability("crystal_maiden_freezing_field", 4, 2, 810)
local list = { nova, frostbite, aura, field }
local unit = { GetAbilityCount = function() return #list end,
    GetAbilityByIndex = function(_, slot) return list[slot + 1] end,
    FindAbilityByName = function(_, name)
        for _, entry in ipairs(list) do if entry:GetAbilityName() == name then return entry end end
    end }
local attack = { action = { kind = "attack" }, target = { team = "enemy" },
    target_priorities = { { type = "lowest_hp_pct" } }, approach = "allow_approach" }
local rules = EnemyRules.CreateForUnit(unit, {
    { action = { kind = "ability", logical_id = "ability_1" }, target = { team = "ally" } },
    { action = { kind = "ability", logical_id = "ultimate" }, target = { team = "self" } }, attack,
})
assert(#rules == 4, "all learned active native spells and one attack, no passive")
assert(rules[1].action.logical_id == "crystal_maiden_crystal_nova" and rules[1].target.team == "enemy",
    "harmful native point spell must never inherit healer profile's ally/self target")
assert(rules[2].action.logical_id == "crystal_maiden_frostbite" and rules[2].target.team == "enemy")
assert(rules[3].target.team == "self" and rules[3].use_conditions[1].radius == 810,
    "native no-target AoE requires an enemy inside its native radius")
assert(rules[4] == attack, "preserve profile attack priorities and chase policy")
list = { ability("omniknight_purification", 8, 1) }
rules = EnemyRules.CreateForUnit(unit, {})
assert(rules[1].target.team == "ally", "native friendly spell must select allies")
list = {}
assert(#EnemyRules.CreateForUnit(unit, {}) == 1, "creeps without active abilities retain attack fallback")
print("enemy-rules.test.lua: passed")
