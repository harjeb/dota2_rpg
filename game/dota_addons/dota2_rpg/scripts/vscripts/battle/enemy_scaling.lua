local EnemyScaling = {}

function EnemyScaling.Resolve(value)
    local multi = tonumber(value)
    if multi == nil or multi ~= multi or multi == math.huge or multi <= 0 then
        return 1
    end
    return multi
end

-- Applied once to freshly spawned neutrals, before per-entry bonuses.
function EnemyScaling.Apply(unit, value)
    if unit == nil or unit:IsNull() or unit:IsRealHero() then return end
    local multi = EnemyScaling.Resolve(value)
    if multi == 1 then return end
    local health = math.max(1, math.floor(unit:GetMaxHealth() * multi + 0.5))
    unit:SetBaseMaxHealth(health)
    unit:SetMaxHealth(health)
    unit:SetHealth(health)
    unit:SetBaseDamageMin(unit:GetBaseDamageMin() * multi)
    unit:SetBaseDamageMax(unit:GetBaseDamageMax() * multi)
    unit:SetPhysicalArmorBaseValue(unit:GetPhysicalArmorBaseValue() * multi)
end

return EnemyScaling
