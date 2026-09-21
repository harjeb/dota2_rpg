modifier_rpg_affix_spell_shell = class({})

function modifier_rpg_affix_spell_shell:IsHidden() return false end
function modifier_rpg_affix_spell_shell:IsPurgable() return true end
function modifier_rpg_affix_spell_shell:RemoveOnDeath() return false end

function modifier_rpg_affix_spell_shell:OnCreated(kv)
    self.reduction_pct = tonumber(kv.reduction_pct or 40)
    if IsServer() then self:SetStackCount(1) end
end

function modifier_rpg_affix_spell_shell:GetReductionPct()
    return self.reduction_pct or 40
end
