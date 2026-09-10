local root = (TEST_REPO_ROOT or ".") .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
function class() local value = {}; value.__index = value; return value end
DOTA_TEAM_BADGUYS, DOTA_TEAM_GOODGUYS = 3, 2
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 0
LUA_MODIFIER_MOTION_NONE = 0
MODIFIER_PROPERTY_HEALTH_BONUS = 1
MODIFIER_PROPERTY_TOTALDAMAGEOUTGOING_PERCENTAGE = 2
MODIFIER_PROPERTY_SPELL_AMPLIFY_PERCENTAGE = 3
MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE = 4
local server = true
function IsServer() return server end
local linked
function LinkLuaModifier(name, path, motion)
    linked = { name, path, motion }
end
local Scaling = dofile(root .. "battle/boss_scaling.lua")
dofile(root .. "modifiers/modifier_rpg_boss_power.lua")
assert(linked[1] == "modifier_rpg_boss_power" and linked[2] == "modifiers/modifier_rpg_boss_power" and linked[3] == 0)
local Power = modifier_rpg_boss_power
local function unit()
    local hero = { baseHealth = 2000, team = DOTA_TEAM_BADGUYS, real = true, alive = true, modifiers = {}, adds = 0 }
    function hero:IsNull() return self.null == true end
    function hero:IsRealHero() return self.real end
    function hero:IsIllusion() return self.illusion == true end
    function hero:IsAlive() return self.alive end
    function hero:GetTeamNumber() return self.team end
    function hero:GetUnitName() return "npc_dota_hero_centaur" end
    function hero:CalculateStatBonus() self.calculations = (self.calculations or 0) + 1 end
    function hero:FindModifierByName(name) return self.modifiers[name] end
    function hero:GetMaxHealth()
        local bonus = self.modifiers.modifier_rpg_boss_power
        return self.baseHealth + (bonus and bonus:GetModifierHealthBonus() or 0)
    end
    function hero:SetHealth(amount) self.health = amount end
    function hero:AddNewModifier(caster, ability, name, kv)
        assert(caster == self and ability == nil and name == "modifier_rpg_boss_power")
        local power = self.modifiers[name]
        if power then
            power:OnRefresh(kv)
        else
            self.adds = self.adds + 1
            power = setmetatable({ parent = self }, Power)
            function power:GetParent() return self.parent end
            function power:IsNull() return false end
            function power:SetHasCustomTransmitterData(enabled) self.transmitter = enabled end
            function power:SendBuffRefreshToClients() self.sent = (self.sent or 0) + 1 end
            self.modifiers[name] = power
            power:OnCreated(kv)
        end
        return power
    end
    return hero
end
local function entry(hp, attack, spell, cdr)
    return { tags = { ["1"] = "hero", ["2"] = "boss" },
        boss_health_multiplier = tostring(hp), boss_attack_damage_pct = tostring(attack),
        boss_spell_amp_pct = tostring(spell), boss_cooldown_reduction_pct = tostring(cdr) }
end
for _, tier in ipairs({ {6, 100, 100, 25}, {10, 200, 150, 40}, {16, 300, 200, 50} }) do
    local hero, config = unit(), entry(unpack(tier))
    local power = Scaling.Apply(hero, config)
    assert(hero:GetMaxHealth() == 2000 * tier[1] and hero.health == hero:GetMaxHealth())
    assert(power:GetModifierTotalDamageOutgoing_Percentage({ damage_category = DOTA_DAMAGE_CATEGORY_ATTACK }) == tier[2])
    assert(power:GetModifierTotalDamageOutgoing_Percentage({ damage_category = DOTA_DAMAGE_CATEGORY_SPELL }) == 0,
        "spell damage must not receive the attack multiplier as well as spell amplification")
    assert(power:GetModifierTotalDamageOutgoing_Percentage({}) == 0)
    assert(power:GetModifierTotalDamageOutgoing_Percentage(nil) == 0)
    assert(power:GetModifierSpellAmplify_Percentage() == tier[3])
    assert(power:GetModifierPercentageCooldown() == tier[4])
    local properties = power:DeclareFunctions()
    assert(#properties == 4)
    for index = 1, 4 do assert(properties[index] == index) end
    assert(not power:IsHidden() and not power:IsPurgable() and not power:RemoveOnDeath())
    assert(not power:AllowIllusionDuplicate() and power.transmitter)
    assert(Scaling.Apply(hero, config) == power and hero.adds == 1 and power.sent == 1)
    assert(hero:GetMaxHealth() == 2000 * tier[1], "refresh cannot compound HP")
    hero.baseHealth = 2300
    Scaling.Apply(hero, config)
    assert(hero:GetMaxHealth() == 2300 * tier[1], "updated equipped baseline must exclude the previous Boss bonus")
    hero.alive = false
    assert(power:GetModifierHealthBonus() == 2300 * (tier[1] - 1))
    hero.alive = true
    assert(hero:GetMaxHealth() == 2300 * tier[1], "reincarnation retains one permanent bonus")

    -- Client KV is deliberately ignored; explicit transmission must restore all
    -- inspection values on initial creation and after a server-side refresh.
    server = false
    local client = setmetatable({ GetParent = function() return hero end }, Power)
    client:OnCreated({ health_bonus = 999999 })
    assert(client:GetModifierHealthBonus() == 0)
    client:HandleCustomTransmitterData(power:AddCustomTransmitterData())
    assert(client:GetModifierHealthBonus() == power:GetModifierHealthBonus())
    assert(client:GetModifierSpellAmplify_Percentage() == tier[3])
    assert(client:GetModifierPercentageCooldown() == tier[4])
    assert(client:GetModifierTotalDamageOutgoing_Percentage({ damage_category = 1 }) == tier[2])
    assert(Scaling.Apply(hero, config) == nil, "client cannot mutate native stats")
    server = true

    -- Even a forced copy of the modifier onto an illusion must contribute zero.
    hero.illusion = true
    assert(power:GetModifierHealthBonus() == 0)
    assert(power:GetModifierTotalDamageOutgoing_Percentage({ damage_category = 1 }) == 0)
    assert(power:GetModifierSpellAmplify_Percentage() == 0 and power:GetModifierPercentageCooldown() == 0)
end
local config = entry(6, 100, 100, 25)
for _, change in ipairs({
    function(hero) hero.team = DOTA_TEAM_GOODGUYS end,
    function(hero) hero.real = false end,
    function(hero) hero.illusion = true end,
    function(hero) hero.null = true end,
}) do
    local hero = unit(); change(hero)
    assert(Scaling.Apply(hero, config) == nil and hero.adds == 0)
end
for _, tags in ipairs({ {}, {"hero"}, {"elite"}, "boss" }) do
    local hero, ordinary = unit(), entry(6, 100, 100, 25)
    ordinary.tags = tags
    assert(Scaling.Apply(hero, ordinary) == nil and hero:GetMaxHealth() == 2000)
end
assert(Scaling.Apply(nil, config) == nil)
assert(Scaling.Apply(unit(), nil) == nil)
for _, value in ipairs({"invalid", "nan", "1e999", -100, -math.huge, 0/0}) do
    local hero = unit()
    assert(Scaling.Apply(hero, entry(value, value, value, value)) == nil and hero.adds == 0)
end
local hero = unit()
local power = Scaling.Apply(hero, entry(999999, 999999, 999999, 100))
assert(hero:GetMaxHealth() == 200000 and power:GetModifierPercentageCooldown() == 80,
    "invalid excessive config must not produce unbounded HP or zero cooldowns")
assert(power:GetModifierSpellAmplify_Percentage() == 1000)
local plain = unit()
assert(Scaling.Apply(plain, { tags = { "boss" } }) == nil, "a boss tag without strength config remains baseline")
for _, health in ipairs({6000, 10000, 16000}) do
    for _, baseline in ipairs({2000, 18000}) do
        local fixed = unit()
        fixed.baseHealth = baseline
        local config = { tags = { "boss" }, boss_max_health = tostring(health) }
        local bonus = Scaling.Apply(fixed, config)
        assert(fixed:GetMaxHealth() == health and fixed.health == health,
            "absolute Boss HP must include native level and equipped strength")
        assert(Scaling.Apply(fixed, config) == bonus and fixed:GetMaxHealth() == health,
            "refresh must not compound positive or negative health bonuses")
        fixed.alive = false
        assert(not bonus:RemoveOnDeath())
        fixed.alive = true
        assert(fixed:GetMaxHealth() == health, "native reincarnation retains target HP")
        fixed.baseHealth = baseline + 300
        Scaling.Apply(fixed, config)
        assert(fixed:GetMaxHealth() == health, "reapplication recalibrates a changed native baseline")
    end
end
print("PASS: Boss stat tiers, absolute HP, native properties, refresh, replication, death, eligibility and config bounds")
