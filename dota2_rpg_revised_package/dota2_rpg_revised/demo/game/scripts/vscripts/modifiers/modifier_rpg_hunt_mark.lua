modifier_rpg_hunt_mark = class({})

function modifier_rpg_hunt_mark:IsHidden() return false end
function modifier_rpg_hunt_mark:IsDebuff() return true end
function modifier_rpg_hunt_mark:IsPurgable() return true end

function modifier_rpg_hunt_mark:OnCreated(kv)
    self.bonus_damage_pct = tonumber(kv.bonus_damage_pct or 0)
    self.mark_team = tonumber(kv.mark_team or -1)
end

function modifier_rpg_hunt_mark:GetBonusDamagePct()
    return self.bonus_damage_pct or 0
end

function modifier_rpg_hunt_mark:GetMarkTeam()
    return self.mark_team or -1
end
