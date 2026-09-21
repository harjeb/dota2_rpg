-- Inventory/control commander only; recruited Io must retain normal attacks.
modifier_rpg_commander_disarmed = class({})

function modifier_rpg_commander_disarmed:IsHidden()
    return true
end

function modifier_rpg_commander_disarmed:IsPurgable()
    return false
end

function modifier_rpg_commander_disarmed:IsPurgeException()
    return false
end

function modifier_rpg_commander_disarmed:RemoveOnDeath()
    return false
end

function modifier_rpg_commander_disarmed:CheckState()
    return { [MODIFIER_STATE_DISARMED] = true }
end
