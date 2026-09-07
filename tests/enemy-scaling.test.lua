local Scaling = dofile('game/dota_addons/dota2_rpg/scripts/vscripts/battle/enemy_scaling.lua')
local function unit(hero)
    local u = { hp = 100, min = 10, max = 20, armor = 4 }
    function u:IsNull() return false end
    function u:IsRealHero() return hero end
    function u:GetMaxHealth() return self.hp end
    function u:SetBaseMaxHealth(v) self.basehp = v end
    function u:SetMaxHealth(v) self.hp = v end
    function u:SetHealth(v) self.current = v end
    function u:GetBaseDamageMin() return self.min end
    function u:GetBaseDamageMax() return self.max end
    function u:SetBaseDamageMin(v) self.min = v end
    function u:SetBaseDamageMax(v) self.max = v end
    function u:GetPhysicalArmorBaseValue() return self.armor end
    function u:SetPhysicalArmorBaseValue(v) self.armor = v end
    return u
end
local creep = unit(false)
Scaling.Apply(creep, '1.5')
assert(creep.hp == 150 and creep.basehp == 150 and creep.current == 150)
assert(creep.min == 15 and creep.max == 30 and creep.armor == 6)
local hero = unit(true)
Scaling.Apply(hero, 10)
assert(hero.hp == 100 and hero.min == 10 and hero.max == 20 and hero.armor == 4)
for _, value in ipairs({'bad', 0, -1, math.huge, 0/0}) do
    assert(Scaling.Resolve(value) == 1)
end
assert(Scaling.Resolve(nil) == 1)
local legacy = unit(false)
Scaling.Apply(legacy, nil)
assert(legacy.hp == 100 and legacy.min == 10 and legacy.armor == 4)
print('PASS: neutral multi HP/damage/armor, hero exclusion and invalid/default coefficients')
