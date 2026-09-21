-- Recipient-side aggregation: team effects are applied once, with no carrier dependency.
modifier_endless_card_stats=class({})
local Modifier=modifier_endless_card_stats
local function server() return not IsServer or IsServer() end
local function runtime() return require('endless/card_effects') end
function Modifier:IsHidden() return true end
function Modifier:IsPurgable() return false end
function Modifier:IsPurgeException() return false end
function Modifier:RemoveOnDeath() return false end
function Modifier:AllowIllusionDuplicate() return false end
-- Bonus capacity is consumed before the native barrier at the same damage stage.
function Modifier:GetPriority() return MODIFIER_PRIORITY_SUPER_ULTRA or 4 end
function Modifier:OnCreated()
    self.stats={}
    if server() and self.SetHasCustomTransmitterData then self:SetHasCustomTransmitterData(true) end
end
function Modifier:SetStats(stats)
    self.stats=self.stats or {}
    local changed=false
    for k,v in pairs(stats) do if self.stats[k]~=v then changed=true end end
    for k in pairs(self.stats) do if stats[k]==nil then changed=true end end
    if not changed then return end
    local parent=self:GetParent()
    local function get(name,default) return parent[name] and parent[name](parent) or default end
    local maxhp,maxmp=get('GetMaxHealth',0),get('GetMaxMana',0)
    local hp,mp=get('GetHealth',0),get('GetMana',0)
    local initial=not self.initialized
    local recalc=false
    for _,key in ipairs({'health','mana','strength','agility','intelligence','all_attributes'}) do
        if (self.stats[key] or 0)~=(stats[key] or 0) then recalc=true end
    end
    self.stats={};for k,v in pairs(stats) do self.stats[k]=v end
    self.initialized=true
    if server() and recalc then
        if parent.CalculateStatBonus then parent:CalculateStatBonus(true) end
        if parent.CalculateGenericBonuses then parent:CalculateGenericBonuses() end
        -- Initial static capacity changes preserve ratios. Subsequent field drains do
        -- not heal; their explicit HPLOSS accounting is handled by the runtime.
        if initial then
            if parent.SetHealth and maxhp>0 and hp>0 then parent:SetHealth(math.max(1,get('GetMaxHealth',maxhp)*hp/maxhp)) end
            if parent.SetMana and maxmp>0 then parent:SetMana(get('GetMaxMana',maxmp)*mp/maxmp) end
        end
    end
    if self.SendBuffRefreshToClients then self:SendBuffRefreshToClients() end
end
function Modifier:AddCustomTransmitterData() return self.stats or {} end
function Modifier:HandleCustomTransmitterData(data) self.stats=data or {} end
local properties={
    {'MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT','GetModifierAttackSpeedBonus_Constant','attack_speed'},
    {'MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE','GetModifierPreAttack_BonusDamage','attack_damage'},
    {'MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE','GetModifierBaseDamageOutgoing_Percentage','base_damage_pct'},
    {'MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE','GetModifierDamageOutgoing_Percentage','attack_damage_pct'},
    {'MODIFIER_PROPERTY_SPELL_AMPLIFY_PERCENTAGE','GetModifierSpellAmplify_Percentage','spell_amp'},
    {'MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE','GetModifierPercentageCooldown','cooldown'},
    {'MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE','GetModifierMoveSpeedBonus_Percentage','move_speed'},
    {'MODIFIER_PROPERTY_STATUS_RESISTANCE_STACKING','GetModifierStatusResistanceStacking','status_resistance'},
    {'MODIFIER_PROPERTY_HEALTH_REGEN_PERCENTAGE','GetModifierHealthRegenPercentage','health_regen_pct'},
    {'MODIFIER_PROPERTY_MANA_REGEN_CONSTANT','GetModifierConstantManaRegen','mana_regen'},
    {'MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS','GetModifierPhysicalArmorBonus','armor'},
    {'MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE','GetModifierIncomingDamage_Percentage','incoming_damage'},
    {'MODIFIER_PROPERTY_MAGICAL_RESISTANCE_BONUS','GetModifierMagicalResistanceBonus','magic_resistance'},
    {'MODIFIER_PROPERTY_EVASION_CONSTANT','GetModifierEvasion_Constant','evasion'},
    {'MODIFIER_PROPERTY_MISS_PERCENTAGE','GetModifierMiss_Percentage','miss'},
    {'MODIFIER_PROPERTY_HEALTH_BONUS','GetModifierHealthBonus','health'},
    {'MODIFIER_PROPERTY_MANA_BONUS','GetModifierManaBonus','mana'},
    {'MODIFIER_PROPERTY_STATS_STRENGTH_BONUS','GetModifierBonusStats_Strength','strength'},
    {'MODIFIER_PROPERTY_STATS_AGILITY_BONUS','GetModifierBonusStats_Agility','agility'},
    {'MODIFIER_PROPERTY_STATS_INTELLECT_BONUS','GetModifierBonusStats_Intellect','intelligence'},
    {'MODIFIER_PROPERTY_HEAL_AMPLIFY_PERCENTAGE_TARGET','GetModifierHealAmplify_PercentageTarget','heal_amp'},
    {'MODIFIER_PROPERTY_HP_REGEN_AMPLIFY_PERCENTAGE','GetModifierHPRegenAmplify_Percentage','heal_amp'},
    {'MODIFIER_PROPERTY_LIFESTEAL_AMPLIFY_PERCENTAGE','GetModifierLifestealRegenAmplify_Percentage','heal_amp'},
    {'MODIFIER_PROPERTY_MANACOST_PERCENTAGE_STACKING','GetModifierPercentageManacostStacking','mana_cost'},
}
for _,p in ipairs(properties) do local key=p[3];Modifier[p[2]]=function(self) return (self.stats or {})[key] or 0 end end
local events={
    'MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT','MODIFIER_PROPERTY_INCOMING_DAMAGE_CONSTANT',
    'MODIFIER_PROPERTY_INCOMING_PHYSICAL_DAMAGE_CONSTANT','MODIFIER_PROPERTY_INCOMING_SPELL_DAMAGE_CONSTANT',
    'MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE','MODIFIER_PROPERTY_TOTALDAMAGEOUTGOING_PERCENTAGE',
    'MODIFIER_EVENT_ON_ABILITY_EXECUTED','MODIFIER_EVENT_ON_TAKEDAMAGE','MODIFIER_EVENT_ON_DEATH',
    'MODIFIER_EVENT_ON_ATTACK','MODIFIER_EVENT_ON_ATTACK_LANDED','MODIFIER_EVENT_ON_ATTACK_RECORD_DESTROY',
}
function Modifier:DeclareFunctions()
    local result={}
    for _,p in ipairs(properties) do if _G[p[1]] then result[#result+1]=_G[p[1]] end end
    for _,name in ipairs(events) do if _G[name] then result[#result+1]=_G[name] end end
    return result
end
function Modifier:GetModifierConstantHealthRegen()
    local stats,parent=self.stats or {},self:GetParent()
    local max=parent:GetMaxHealth()
    local missing=max>0 and math.max(0,math.min(1,1-parent:GetHealth()/max)) or 0
    return (stats.health_regen or 0)+(stats.missing_health_regen or 0)*missing
end
function Modifier:GetModifierSpellAmplify_Percentage()
    local s,u=self.stats or {},self:GetParent()
    local missing=u:GetMaxHealth()>0 and math.max(0,math.min(1,1-u:GetHealth()/u:GetMaxHealth())) or 0
    return (s.spell_amp or 0)+(s.missing_health_amp or 0)*missing
end
function Modifier:GetModifierPercentageCooldown(params)
    local a=params and params.ability
    if not a or (a.IsItem and a:IsItem()) then return 0 end
    return (self.stats or {}).cooldown or 0
end
function Modifier:GetModifierPercentageManacostStacking(params)
    local a=params and params.ability
    if not a or (a.IsItem and a:IsItem()) then return 0 end
    -- Native property is mana cost reduction: positive design cost becomes negative.
    return -((self.stats or {}).mana_cost or 0)
end
function Modifier:GetModifierIncomingDamage_Percentage(params)
    local s=self.stats or {}
    local reduction=params and params.damage_type==DAMAGE_TYPE_PHYSICAL and (s.physical_reduction or 0) or 0
    return (s.incoming_damage or 0)-reduction
end
function Modifier:GetModifierBonusStats_Strength() local s=self.stats or {};return (s.strength or 0)+(s.all_attributes or 0) end
function Modifier:GetModifierBonusStats_Agility() local s=self.stats or {};return (s.agility or 0)+(s.all_attributes or 0) end
function Modifier:GetModifierBonusStats_Intellect() local s=self.stats or {};return (s.intelligence or 0)+(s.all_attributes or 0) end
function Modifier:GetModifierAttackSpeedBonus_Constant()
    return ((self.stats or {}).attack_speed or 0)+(server() and self.game and runtime().MarkAttackSpeed(self.game,self:GetParent()) or 0)
end
function Modifier:GetModifierTotalDamageOutgoing_Percentage(params)
    return server() and self.game and runtime().Outgoing(self.game,self:GetParent(),params) or 0
end
function Modifier:GetModifierIncomingDamageConstant(params)
    if not server() or not self.game then return 0 end
    return runtime().Absorb(self.game,self:GetParent(),params)
end
function Modifier:GetModifierIncomingPhysicalDamageConstant(params)
    if server() and self.game then return runtime().AbsorbNative(self.game,self:GetParent(),params,'physical') end
    return 0
end
function Modifier:GetModifierIncomingSpellDamageConstant(params)
    if server() and self.game then return runtime().AbsorbNative(self.game,self:GetParent(),params,'magic') end
    return 0
end
function Modifier:GetModifierPreAttack_CriticalStrike(params)
    if server() and self.game then return runtime().Critical(self.game,self:GetParent(),params) end
end
function Modifier:OnAbilityExecuted(params)
    if server() and self.game and params.unit==self:GetParent() then runtime().Cast(self.game,params.unit,params.ability) end
end
function Modifier:OnTakeDamage(params)
    -- OnTakeDamage broadcasts to every modifier; only the victim handles it once.
    if server() and self.game and params.unit==self:GetParent() then runtime().TakeDamage(self.game,params) end
end
function Modifier:OnDeath(params)
    if server() and self.game and params.unit==self:GetParent() then runtime().Death(self.game,params) end
end
function Modifier:OnAttack(params)
    if server() and self.game and params.attacker==self:GetParent() then runtime().Attack(self.game,params.attacker,params) end
end
function Modifier:OnAttackLanded(params)
    if server() and self.game and params.target==self:GetParent() then runtime().AttackLanded(self.game,params.target,params) end
end
function Modifier:OnAttackRecordDestroy(params)
    if server() and self.game and params.attacker==self:GetParent() then runtime().AttackRecordDestroy(self.game,params.attacker,params) end
end
-- Same stat transport, separate preparation lifetime, no combat event listeners.
modifier_endless_card_prepare=class(Modifier)
function modifier_endless_card_prepare:DeclareFunctions()
    local result={}
    for _,name in ipairs({'MODIFIER_PROPERTY_HEALTH_BONUS','MODIFIER_PROPERTY_MANA_BONUS','MODIFIER_PROPERTY_STATS_STRENGTH_BONUS','MODIFIER_PROPERTY_STATS_AGILITY_BONUS','MODIFIER_PROPERTY_STATS_INTELLECT_BONUS'}) do
        if _G[name] then result[#result+1]=_G[name] end
    end
    return result
end
return Modifier
