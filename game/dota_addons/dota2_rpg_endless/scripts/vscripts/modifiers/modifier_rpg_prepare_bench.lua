modifier_rpg_prepare_bench = class({})

function modifier_rpg_prepare_bench:IsHidden()
    return true
end

function modifier_rpg_prepare_bench:IsPurgable()
    return false
end

function modifier_rpg_prepare_bench:RemoveOnDeath()
    return false
end

function modifier_rpg_prepare_bench:CheckState()
    return {
        [MODIFIER_STATE_INVULNERABLE] = true,
        [MODIFIER_STATE_ROOTED] = true,
        [MODIFIER_STATE_DISARMED] = true,
        [MODIFIER_STATE_SILENCED] = true,
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
    }
end

-- Intentionally absent:
-- [MODIFIER_STATE_STUNNED] = true
-- [MODIFIER_STATE_COMMAND_RESTRICTED] = true
-- Those two states prevent skill training and native shop orders.
