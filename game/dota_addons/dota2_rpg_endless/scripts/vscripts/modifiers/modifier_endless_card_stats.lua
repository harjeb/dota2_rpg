-- Aggregated battle-only card stats. No carrier/caster dependency and no copied stacking.
modifier_endless_card_stats = class({})
local Modifier = modifier_endless_card_stats
function Modifier:IsHidden() return true end
function Modifier:IsPurgable() return false end
function Modifier:IsPurgeException() return false end
function Modifier:RemoveOnDeath() return false end
function Modifier:AllowIllusionDuplicate() return false end
function Modifier:OnCreated()
    self.stats = {}
    if IsServer() and self.SetHasCustomTransmitterData then self:SetHasCustomTransmitterData(true) end
end
function Modifier:SetStats(stats)
    local changed = false
    for key, value in pairs(stats) do if self.stats[key] ~= value then changed = true end end
    for key in pairs(self.stats) do if stats[key] == nil then changed = true end end
    if not changed then return end
    self.stats = {}
    for key, value in pairs(stats) do self.stats[key] = value end
    if self.SendBuffRefreshToClients then self:SendBuffRefreshToClients() end
end
function Modifier:AddCustomTransmitterData() return self.stats or {} end
function Modifier:HandleCustomTransmitterData(data) self.stats = data or {} end
local properties = {
    {"MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT", "GetModifierAttackSpeedBonus_Constant", "attack_speed"},
    {"MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE", "GetModifierPreAttack_BonusDamage", "attack_damage"},
    {"MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE", "GetModifierBaseDamageOutgoing_Percentage", "base_damage_pct"},
    {"MODIFIER_PROPERTY_SPELL_AMPLIFY_PERCENTAGE", "GetModifierSpellAmplify_Percentage", "spell_amp"},
    {"MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE", "GetModifierPercentageCooldown", "cooldown"},
    {"MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE", "GetModifierMoveSpeedBonus_Percentage", "move_speed"},
    {"MODIFIER_PROPERTY_STATUS_RESISTANCE_STACKING", "GetModifierStatusResistanceStacking", "status_resistance"},
    {"MODIFIER_PROPERTY_HEALTH_REGEN_PERCENTAGE", "GetModifierHealthRegenPercentage", "health_regen_pct"},
    {"MODIFIER_PROPERTY_MANA_REGEN_CONSTANT", "GetModifierConstantManaRegen", "mana_regen"},
    {"MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS", "GetModifierPhysicalArmorBonus", "armor"},
    {"MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE", "GetModifierIncomingDamage_Percentage", "incoming_damage"},
}
for _, property in ipairs(properties) do
    local key = property[3]
    Modifier[property[2]] = function(self) return (self.stats or {})[key] or 0 end
end
-- C-g5 explicitly affects hero skills, not the ordinary equipment shop's items.
function Modifier:GetModifierPercentageCooldown(params)
    local ability = params and params.ability
    if not ability or (ability.IsItem and ability:IsItem()) then return 0 end
    return (self.stats or {}).cooldown or 0
end
function Modifier:DeclareFunctions()
    local result = {MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT}
    for _, property in ipairs(properties) do result[#result+1] = _G[property[1]] end
    return result
end
function Modifier:GetModifierConstantHealthRegen()
    local stats, parent = self.stats or {}, self:GetParent()
    local maximum = parent:GetMaxHealth()
    local missing = maximum > 0 and math.max(0, math.min(1, 1-parent:GetHealth()/maximum)) or 0
    return (stats.health_regen or 0) + (stats.missing_health_regen or 0) * missing
end
return Modifier
