-- Campaign enemy progression. Arena opponents restore their saved builds separately.
local Progression = {}

function Progression.TrainTalents(hero)
    local talents = {}
    for slot = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(slot)
        if ability and not ability:IsNull()
            and ability:GetAbilityName():sub(1, 14) == "special_bonus_"
            and ability:GetAbilityName() ~= "special_bonus_attributes"
            and ability:GetMaxLevel() > 0 then
            talents[#talents + 1] = ability
        end
    end
    -- Native hero definitions list the two choices at each tier in slot order.
    -- Keep one deterministic choice per tier; preserve any already learned side.
    local level = hero:GetLevel()
    for tier = 1, math.min(4, math.floor(#talents / 2)) do
        local first, second = talents[tier * 2 - 1], talents[tier * 2]
        if level >= 5 + tier * 5 then
            local choices = level >= 30 and {first, second} or
                ((first:GetLevel() > 0 or second:GetLevel() > 0) and {} or {first})
            for _, ability in ipairs(choices) do
                if ability:GetLevel() == 0 then
                    hero:SetAbilityPoints(math.max(1, hero:GetAbilityPoints()))
                    -- SetLevel alone does not register a native learned talent.
                    local ok, reason = pcall(hero.UpgradeAbility, hero, ability)
                    if not ok or ability:GetLevel() == 0 then
                        print("[RPG][EnemyTalents] Upgrade failed: " .. ability:GetAbilityName()
                            .. " " .. tostring(reason))
                    end
                end
            end
        end
    end
    hero:SetAbilityPoints(0)
end

function Progression.ApplyUpgrades(unit, entry)
    local upgrades = entry.quality_upgrades
    -- Explicit encounter builds (including an empty list) override the curve.
    if upgrades == nil and unit:IsRealHero() then
        upgrades = {}
        local level = unit:GetLevel()
        if level >= 15 then upgrades[#upgrades + 1] = "shard" end
        if level >= 25 then upgrades[#upgrades + 1] = "scepter" end
    end
    for _, upgrade in pairs(upgrades or {}) do
        local modifier = upgrade == "shard" and "modifier_item_aghanims_shard"
            or upgrade == "scepter" and "modifier_item_ultimate_scepter_consumed"
        if modifier and (not unit.HasModifier or not unit:HasModifier(modifier)) then
            unit:AddNewModifier(unit, nil, modifier, {})
        end
    end
end

return Progression
