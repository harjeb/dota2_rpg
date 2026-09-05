modifier_rpg_affix_thick_hide = class({})

function modifier_rpg_affix_thick_hide:IsHidden() return false end
function modifier_rpg_affix_thick_hide:IsPurgable() return false end
function modifier_rpg_affix_thick_hide:RemoveOnDeath() return false end

function modifier_rpg_affix_thick_hide:OnCreated(kv)
    self.max_health_pct = tonumber(kv.max_health_pct or 12)
    self.attack_reduction_pct = tonumber(kv.attack_physical_reduction_pct or 5)
    if IsServer() then
        self.base_max_health = self:GetParent():GetMaxHealth()
    end
end

function modifier_rpg_affix_thick_hide:DeclareFunctions()
    return { MODIFIER_PROPERTY_HEALTH_BONUS }
end

function modifier_rpg_affix_thick_hide:GetModifierHealthBonus()
    return math.floor((self.base_max_health or 0) * self.max_health_pct / 100)
end

function modifier_rpg_affix_thick_hide:GetAttackReductionPct()
    return self.attack_reduction_pct or 0
end
