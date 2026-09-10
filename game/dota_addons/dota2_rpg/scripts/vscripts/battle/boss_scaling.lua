local BossScaling = {}
local MODIFIER = "modifier_rpg_boss_power"

if LinkLuaModifier ~= nil then
    LinkLuaModifier(MODIFIER, "modifiers/" .. MODIFIER, LUA_MODIFIER_MOTION_NONE)
end

local function valid(entity)
    return entity ~= nil and (entity.IsNull == nil or not entity:IsNull())
end

local function bounded(value, default, minimum, maximum)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return default
    end
    return math.max(minimum, math.min(maximum, number))
end

local function eligible(unit, entry)
    if not valid(unit) or type(entry) ~= "table" or type(entry.tags) ~= "table" then return false end
    if unit.IsRealHero == nil or not unit:IsRealHero() then return false end
    if unit.IsIllusion ~= nil and unit:IsIllusion() then return false end
    if unit:GetTeamNumber() ~= DOTA_TEAM_BADGUYS then return false end
    for _, tag in pairs(entry.tags) do
        if tag == "boss" then return true end
    end
    return false
end

-- Called during enemy preparation AFTER native leveling and equipment. All
-- damage/cooldown changes remain native modifier properties, not replayed orders.
function BossScaling.Apply(unit, entry)
    if IsServer ~= nil and not IsServer() then return nil end
    if not eligible(unit, entry) then return nil end
    local hpMultiplier = bounded(entry.boss_health_multiplier, 1, 1, 100)
    -- Absolute HP is applied after leveling/equipment, including a negative
    -- bonus when the native level-30 hero already exceeds the target.
    local targetHealth = bounded(entry.boss_max_health, 0, 0, 1000000)
    local attack = bounded(entry.boss_attack_damage_pct, 0, 0, 1000)
    local spell = bounded(entry.boss_spell_amp_pct, 0, 0, 1000)
    local cooldown = bounded(entry.boss_cooldown_reduction_pct, 0, 0, 80)
    local previous = unit:FindModifierByName(MODIFIER)
    if targetHealth == 0 and hpMultiplier == 1 and attack == 0 and spell == 0 and cooldown == 0 and not valid(previous) then
        return nil
    end
    unit:CalculateStatBonus(true)
    -- The old flat bonus is already part of GetMaxHealth on reapplication.
    local oldBonus = valid(previous) and previous:GetModifierHealthBonus() or 0
    local baseline = unit:GetMaxHealth() - oldBonus
    if baseline ~= baseline or baseline <= 0 or baseline == math.huge then return nil end
    local modifier = unit:AddNewModifier(unit, nil, MODIFIER, {
        health_bonus = targetHealth > 0 and (math.floor(targetHealth) - baseline)
            or math.floor(baseline * (hpMultiplier - 1)),
        attack_damage_pct = attack,
        spell_amp_pct = spell,
        cooldown_reduction_pct = cooldown,
    })
    if not valid(modifier) then return nil end
    unit:CalculateStatBonus(true)
    unit:SetHealth(unit:GetMaxHealth())
    print(string.format("[RPG][BossPower] unit=%s max_hp=%d hp_multiplier=%.2f attack_bonus_pct=%.1f spell_amp_pct=%.1f cooldown_reduction_pct=%.1f",
        unit:GetUnitName(), unit:GetMaxHealth(), hpMultiplier, attack, spell, cooldown))
    return modifier
end

return BossScaling
