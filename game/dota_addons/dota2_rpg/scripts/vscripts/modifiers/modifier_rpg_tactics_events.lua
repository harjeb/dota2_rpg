-- OnAttack fires on native attack release, not OnAttackStart (windup).
modifier_rpg_tactics_events = class({})
function modifier_rpg_tactics_events:IsHidden() return true end
function modifier_rpg_tactics_events:IsPurgable() return false end
-- Reincarnating the same native handle must retain its observer. Stage resets
-- explicitly detach it; removing a hero destroys the modifier with that hero.
function modifier_rpg_tactics_events:RemoveOnDeath() return false end
function modifier_rpg_tactics_events:DeclareFunctions()
    return {MODIFIER_EVENT_ON_ATTACK, MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ABILITY_EXECUTED}
end
function modifier_rpg_tactics_events:OnAttackStart(event)
    if not IsServer() or event.attacker ~= self:GetParent() then return end
    local events = self:GetParent().rpgTacticsEvents
    if events then events.attack = nil end
end
function modifier_rpg_tactics_events:OnAttack(event)
    if not IsServer() or event.attacker ~= self:GetParent() or event.no_attack_cooldown then return end
    local events = self:GetParent().rpgTacticsEvents
    if events then
        events.attack = {time=GameRules:GetGameTime(), target=event.target}
    end
end
function modifier_rpg_tactics_events:OnAbilityExecuted(event)
    if not IsServer() or event.unit ~= self:GetParent() or not event.ability then return end
    require("tactics/native_events").RecordSuccess(self:GetParent(), event.ability:GetAbilityName(), GameRules:GetGameTime())
end
