modifier_rpg_affix_blood_frenzy = class({})

function modifier_rpg_affix_blood_frenzy:IsHidden() return false end
function modifier_rpg_affix_blood_frenzy:IsPurgable() return false end
function modifier_rpg_affix_blood_frenzy:RemoveOnDeath() return false end

function modifier_rpg_affix_blood_frenzy:OnCreated(kv)
    self.threshold_pct = tonumber(kv.threshold_pct or 35)
    self.attack_speed = tonumber(kv.attack_speed or 25)
    self.move_speed_pct = tonumber(kv.move_speed_pct or 10)
    if IsServer() then
        self:StartIntervalThink(0.1)
        self:OnIntervalThink()
    end
end

function modifier_rpg_affix_blood_frenzy:OnIntervalThink()
    local parent = self:GetParent()
    local active = parent:GetHealth() / math.max(1, parent:GetMaxHealth()) <= self.threshold_pct / 100
    self:SetStackCount(active and 1 or 0)
end

function modifier_rpg_affix_blood_frenzy:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
        MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
    }
end

function modifier_rpg_affix_blood_frenzy:GetModifierAttackSpeedBonus_Constant()
    return self:GetStackCount() == 1 and self.attack_speed or 0
end

function modifier_rpg_affix_blood_frenzy:GetModifierMoveSpeedBonus_Percentage()
    return self:GetStackCount() == 1 and self.move_speed_pct or 0
end
