modifier_rpg_opening_shield = class({})

function modifier_rpg_opening_shield:IsHidden() return false end
function modifier_rpg_opening_shield:IsPurgable() return true end

function modifier_rpg_opening_shield:OnCreated(kv)
    if not IsServer() then return end
    self.remaining = math.max(0, tonumber(kv.shield_amount or 0))
    self:SetStackCount(math.floor(self.remaining))
end

function modifier_rpg_opening_shield:DeclareFunctions()
    return { MODIFIER_PROPERTY_TOTAL_CONSTANT_BLOCK }
end

function modifier_rpg_opening_shield:GetModifierTotal_ConstantBlock(params)
    if not IsServer() or self.remaining <= 0 then return 0 end
    local blocked = math.min(self.remaining, tonumber(params.damage or 0))
    self.remaining = self.remaining - blocked
    self:SetStackCount(math.floor(self.remaining))
    if self.remaining <= 0 then
        self:Destroy()
    end
    return blocked
end
