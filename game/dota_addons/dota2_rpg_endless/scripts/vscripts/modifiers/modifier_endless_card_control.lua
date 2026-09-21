modifier_endless_card_control=class({})
local M=modifier_endless_card_control
function M:IsHidden() return false end
function M:IsDebuff() return true end
function M:IsPurgable() return self.kind~='stun' end
function M:IsPurgeException() return true end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_MULTIPLE or 0 end
function M:OnCreated(kv)
    self.kind=kv.kind
    if IsServer() and self.kind=='fear' then self:StartIntervalThink(.2);self:OnIntervalThink() end
end
function M:CheckState()
    local states={}
    local key=self.kind=='stun' and MODIFIER_STATE_STUNNED or self.kind=='silence' and MODIFIER_STATE_SILENCED or self.kind=='fear' and MODIFIER_STATE_FEARED
    if key then states[key]=true end
    return states
end
function M:OnIntervalThink()
    if self.kind~='fear' then return end
    local u=self:GetParent()
    local origin=u:GetAbsOrigin()
    local targets=FindUnitsInRadius(u:GetTeamNumber(),origin,nil,FIND_UNITS_EVERYWHERE or -1,DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO+DOTA_UNIT_TARGET_BASIC,DOTA_UNIT_TARGET_FLAG_NONE or 0,FIND_CLOSEST,false)
    local target=targets and targets[1]
    if target and u.MoveToPosition then
        local delta=origin-target:GetAbsOrigin()
        if delta:Length2D()<1 then delta=Vector(1,0,0) end
        u:MoveToPosition(origin+delta:Normalized()*500)
    end
end
function M:OnDestroy()
    if IsServer() and self.kind=='fear' and self:GetParent().Stop then self:GetParent():Stop() end
end
modifier_endless_card_source=class({})
function modifier_endless_card_source:IsHidden() return true end
function modifier_endless_card_source:IsPurgable() return false end
function modifier_endless_card_source:CheckState()
    local result={}
    for _,name in ipairs({'MODIFIER_STATE_INVULNERABLE','MODIFIER_STATE_UNSELECTABLE','MODIFIER_STATE_NO_HEALTH_BAR',
        'MODIFIER_STATE_NOT_ON_MINIMAP','MODIFIER_STATE_NO_UNIT_COLLISION','MODIFIER_STATE_OUT_OF_GAME'}) do
        if _G[name] then result[_G[name]]=true end
    end
    return result
end
