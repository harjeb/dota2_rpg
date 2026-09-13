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
-- The full mask remains authoritative when the native int accessor overflows.
local wide = spell("wide_no_target")
wide.GetBehavior = function() return 137438953472 + 4 end
wide.GetBehaviorInt = function() return -2147483648 end
local wideHero = {GetAbilityCount=function() return 1 end, GetAbilityByIndex=function() return wide end}
local wideRules = Defaults.CreateForHero(wideHero)
assert(wideRules[1].target.team == "self", "high behavior flags must preserve no-target defaults")

-- 远程英雄的普攻默认在最大攻击距离站位；近战英雄、非英雄单位与技能行都不受影响。
local function rangedHeroMock(ranged)
    -- 用全新的技能，避免复用上面已被隐藏的技能。
    local probe = spell("posture_probe")
    return {GetAbilityCount=function() return 1 end, GetAbilityByIndex=function() return probe end,
        IsRealHero=function() return true end, IsRangedAttacker=function() return ranged end}
end
local rangedHero = rangedHeroMock(true)
local rangedRules = Defaults.CreateForHero(rangedHero)
assert(rangedRules[1].action.kind == "ability" and rangedRules[1].action.positioning_mode == nil,
    "ability rows must keep their own posture choice")
assert(rangedRules[#rangedRules].action.kind == "attack"
    and rangedRules[#rangedRules].action.positioning_mode == "attack_range",
    "a ranged hero attack row must default to max attack range")
local meleeRules = Defaults.CreateForHero(rangedHeroMock(false))
assert(meleeRules[#meleeRules].action.positioning_mode == nil, "a melee hero attack row keeps the previous default")
local rangedCreep = {GetAbilityCount=function() return 0 end, IsRealHero=function() return false end,
    IsRangedAttacker=function() return true end}
assert(Defaults.CreateForHero(rangedCreep)[1].action.positioning_mode == nil,
    "ranged non-hero units must not receive the hero posture default")
local authored = Defaults.CreateAttackNearestRule()
authored.action.positioning_mode = "fixed"
Defaults.ApplyRangedAttackPosture(authored, rangedHero)
assert(authored.action.positioning_mode == "fixed", "an explicitly authored posture must never be overwritten")
local noNativeFlag = {IsRealHero=function() return true end, Script_GetAttackRange=function() return 600 end}
assert(Defaults.ApplyRangedAttackPosture(Defaults.CreateAttackNearestRule(), noNativeFlag).action.positioning_mode
    == "attack_range", "a missing native ranged flag must fall back to the native attack range")
local nearRange = {IsRealHero=function() return true end, Script_GetAttackRange=function() return 150 end}
assert(Defaults.ApplyRangedAttackPosture(Defaults.CreateAttackNearestRule(), nearRange).action.positioning_mode == nil,
    "a melee native attack range must stay unchanged")
assert(Defaults.ApplyRangedAttackPosture(Defaults.CreateAttackNearestRule(), nil).action.positioning_mode == nil,
    "a missing unit must not receive the hero posture default")
for _, rule in ipairs(Defaults.CreateForHero(rangedHero)) do
    local ok, reason = service:ValidateRule(0, rangedHero, rule)
    assert(ok, reason)
end
print("default rules tests passed")
