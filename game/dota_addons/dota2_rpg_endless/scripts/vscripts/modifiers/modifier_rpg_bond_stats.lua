modifier_rpg_bond_stats = class({})

function modifier_rpg_bond_stats:IsHidden() return false end
function modifier_rpg_bond_stats:IsPurgable() return false end
function modifier_rpg_bond_stats:RemoveOnDeath() return false end

function modifier_rpg_bond_stats:OnCreated(kv)
    self.max_health_pct = tonumber(kv.max_health_pct or 0)
    self.mana_regen_pct = tonumber(kv.mana_regen_pct or 0)
    self.heal_amp_pct = tonumber(kv.heal_amp_pct or 0)
    if IsServer() then
        self.base_max_health = self:GetParent():GetMaxHealth()
    end
end

function modifier_rpg_bond_stats:OnRefresh(kv)
    self:OnCreated(kv)
end

function modifier_rpg_bond_stats:DeclareFunctions()
    local funcs = {
        MODIFIER_PROPERTY_HEALTH_BONUS,
    }
    if MODIFIER_PROPERTY_MANA_REGEN_TOTAL_PERCENTAGE ~= nil then
        table.insert(funcs, MODIFIER_PROPERTY_MANA_REGEN_TOTAL_PERCENTAGE)
    end
    if MODIFIER_PROPERTY_HEAL_AMPLIFY_PERCENTAGE_SOURCE ~= nil then
        table.insert(funcs, MODIFIER_PROPERTY_HEAL_AMPLIFY_PERCENTAGE_SOURCE)
    end
    return funcs
end

function modifier_rpg_bond_stats:GetModifierHealthBonus()
    return math.floor((self.base_max_health or 0) * self.max_health_pct / 100)
end

function modifier_rpg_bond_stats:GetModifierTotalPercentageManaRegen()
    return self.mana_regen_pct
end

function modifier_rpg_bond_stats:GetModifierHealAmplify_PercentageSource()
    return self.heal_amp_pct
end
