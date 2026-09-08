local root = arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = root .. "/?.lua;" .. package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 8
DOTA_ABILITY_BEHAVIOR_POINT = 16
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
DOTA_ABILITY_BEHAVIOR_TOGGLE = 512
DOTA_UNIT_TARGET_TEAM_FRIENDLY = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
local Defaults = require("issue_fixes.default_rules")
local function spell(name, options)
    local a = options or {}
    function a:IsNull() return false end
    function a:GetAbilityName() return name end
    function a:GetLevel() return self.level or 1 end
    function a:IsHidden() return self.hidden == true end
    function a:IsPassive() return self.passive == true end
    function a:IsActivated() return self.activated ~= false end
    function a:GetBehaviorInt() return self.behavior or 8 end
    function a:GetAbilityTargetTeam() return self.team or 2 end
    return a
end
local skills = {
    spell("nuke"), spell("heal", {team=1}), spell("stomp", {behavior=4}),
    spell("blink", {behavior=16}), spell("toggle", {behavior=512}),
    spell("passive", {passive=true}), spell("hidden", {hidden=true}),
    spell("unlearned", {level=0}), spell("inactive", {activated=false}),
    spell("special_bonus_damage"), spell("generic_hidden"), spell("nuke"),
}
local hero = {}
function hero:GetAbilityCount() return #skills end
function hero:GetAbilityByIndex(i) return skills[i+1] end
local rules = Defaults.Normalize(nil, hero)
assert(#rules == 6)
for i, name in ipairs({"nuke", "heal", "stomp", "blink", "toggle"}) do
    assert(rules[i].action.logical_id == name)
    assert(rules[i].action.kind == "ability")
    assert(#rules[i].use_conditions == 0)
    assert(rules[i].is_default == true)
end
assert(rules[1].target.team == "enemy")
assert(rules[2].target.team == "ally")
assert(rules[3].target.team == "self")
assert(rules[4].target.team == "enemy")
assert(rules[5].target.team == "self")
assert(rules[6].action.logical_id == "basic_attack")
skills[8].level = 1
local refreshed = Defaults.Normalize(rules, hero)
assert(#refreshed == 7 and refreshed[6].action.logical_id == "unlearned")
skills[1].hidden = true
refreshed = Defaults.Normalize(refreshed, hero)
-- The second duplicate nuke is still visible and has its own valid slot.
assert(refreshed[#refreshed-1].action.logical_id == "nuke")
local manual = {id="mine", enabled=false, action={kind="ability", logical_id="hidden"},
    target={team="self"}, use_conditions={{type="self_hp_pct_lte",value=0.3}}}
local preserved = Defaults.Normalize({manual}, hero)
assert(#preserved == 1 and preserved[1] == manual and not preserved[1].enabled)
local mixed = Defaults.Normalize({rules[1], manual}, hero)
assert(#mixed == 2 and mixed[2] == manual)
local unmarkedAttack = {action="attack",condition="always",target="enemy_distance_nearest"}
assert(Defaults.Normalize({unmarkedAttack}, hero)[1] == unmarkedAttack)
local migrated = Defaults.Normalize({Defaults.CreateAttackNearestRule()}, hero)
assert(#migrated == 7 and migrated[#migrated].action.kind == "attack")
local store = {}
Defaults.InitializeHeroRules(store, "hero", hero)
assert(#store.hero == 7)
store.hero = {manual}
assert(Defaults.InitializeHeroRules(store, "hero", hero)[1] == manual)
local Service = require("tactics/rule_service")
local service = Service.new({get_phase=function() return "PREPARE" end,
    is_roster_hero=function() return true end, is_action_allowed=function() return true end,
    state={rules={}}})
for _, rule in ipairs(migrated) do
    local ok, reason = service:ValidateRule(0, hero, rule)
    assert(ok, reason)
end
print("default rules tests passed")
