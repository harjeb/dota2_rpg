modifier_rpg_boss_power = class({})

function modifier_rpg_boss_power:IsHidden() return false end
function modifier_rpg_boss_power:IsPurgable() return false end
function modifier_rpg_boss_power:RemoveOnDeath() return false end
function modifier_rpg_boss_power:AllowIllusionDuplicate() return false end
function modifier_rpg_boss_power:GetTexture() return "item_heart" end

local function assign(self, values)
    self.health_bonus = tonumber(values.health_bonus) or 0
    self.attack_damage_pct = tonumber(values.attack_damage_pct) or 0
    self.spell_amp_pct = tonumber(values.spell_amp_pct) or 0
    self.cooldown_reduction_pct = tonumber(values.cooldown_reduction_pct) or 0
end

function modifier_rpg_boss_power:OnCreated(kv)
    assign(self, {})
    if IsServer() then
        assign(self, kv)
        self:SetHasCustomTransmitterData(true)
    end
end

function modifier_rpg_boss_power:OnRefresh(kv)
    if IsServer() then
        assign(self, kv)
        self:SendBuffRefreshToClients()
    end
end

-- Arbitrary AddNewModifier KV fields are server-side. Transmit explicitly so
-- the client uses the same health/damage/cooldown values when inspecting Bosses.
function modifier_rpg_boss_power:AddCustomTransmitterData()
    return {
        health_bonus = self.health_bonus,
        attack_damage_pct = self.attack_damage_pct,
        spell_amp_pct = self.spell_amp_pct,
        cooldown_reduction_pct = self.cooldown_reduction_pct,
    }
end

function modifier_rpg_boss_power:HandleCustomTransmitterData(data)
    assign(self, data)
end

function modifier_rpg_boss_power:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_HEALTH_BONUS,
        MODIFIER_PROPERTY_TOTALDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_SPELL_AMPLIFY_PERCENTAGE,
        MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE,
    }
end

local function valueForRealUnit(self, field)
    local parent = self:GetParent()
    if parent ~= nil and parent.IsIllusion ~= nil and parent:IsIllusion() then return 0 end
    return self[field] or 0
end

function modifier_rpg_boss_power:GetModifierHealthBonus()
    return valueForRealUnit(self, "health_bonus")
end

function modifier_rpg_boss_power:GetModifierTotalDamageOutgoing_Percentage(params)
    if params == nil or params.damage_category ~= DOTA_DAMAGE_CATEGORY_ATTACK then return 0 end
    return valueForRealUnit(self, "attack_damage_pct")
end

function modifier_rpg_boss_power:GetModifierSpellAmplify_Percentage()
    return valueForRealUnit(self, "spell_amp_pct")
end

function modifier_rpg_boss_power:GetModifierPercentageCooldown()
    return valueForRealUnit(self, "cooldown_reduction_pct")
end
