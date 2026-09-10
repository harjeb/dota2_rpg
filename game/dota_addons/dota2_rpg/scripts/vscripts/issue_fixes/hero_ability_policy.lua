-- Native definitions: scripts/npc/heroes/npc_dota_hero_morphling.txt and
-- scripts/npc/heroes/npc_dota_hero_largo.txt (data/native_skill_conditions.json).
-- Apply to project-owned heroes immediately after creation, before leveling skills.
local Policy = {}

-- GetAbilityCount is the native addressable slot bound, including sparse talents.
-- Empty slots within that bound are valid; probing beyond it emits engine warnings.
function Policy.GetSlotCount(hero)
    return hero and hero.GetAbilityCount and hero:GetAbilityCount() or 0
end

local removedByHero = {
    npc_dota_hero_morphling = {
        morphling_replicate = true,
        morphling_morph_replicate = true,
        morphling_hybrid = true,
    },
    npc_dota_hero_largo = {
        largo_amphibian_rhapsody = true,
        largo_song_fight_song = true,
        largo_song_double_time = true,
        largo_song_good_vibrations = true,
    },
}

local function valid(handle)
    return handle ~= nil and (not handle.IsNull or not handle:IsNull())
end

function Policy.Apply(hero)
    if not valid(hero) or not hero.GetUnitName then return 0 end
    local removed = removedByHero[hero:GetUnitName()]
    if not removed then return 0 end

    -- Snapshot names first: RemoveAbility can compact native slots and removing
    -- an ultimate can also remove its subskills. Never retain handles across it.
    local names, seen = {}, {}
    local count = Policy.GetSlotCount(hero)
    for index = 0, count - 1 do
        local ability = hero:GetAbilityByIndex(index)
        if valid(ability) then
            local name = ability:GetAbilityName()
            if removed[name] and not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    local total = 0
    for _, name in ipairs(names) do
        if valid(hero:FindAbilityByName(name)) then
            hero:RemoveAbility(name)
            total = total + 1
        end
    end
    return total
end

-- Raw talent levels do not replay the engine's learned-talent registry.
-- New entities must learn through UpgradeAbility; an already prepared live hero
-- retains its native choices and must not spend those points again.
function Policy.RestoreManualAbilities(hero, data, fallbackPoints)
    local levels = data and data.ability_levels or {}
    local unspent = math.max(0, data and (data.skill_points or data.level) or fallbackPoints)
    local refund, restored = 0, true
    for slot = 0, Policy.GetSlotCount(hero) - 1 do
        local ability = hero:GetAbilityByIndex(slot)
        if valid(ability) then
            local name = ability:GetAbilityName()
            local saved = levels[name]
            if saved ~= nil then
                if name:sub(1, 14) == "special_bonus_" and saved > 0 then
                    if not hero.rpgAbilitiesRestored then ability:SetLevel(0) end
                    while ability:GetLevel() < saved do
                        local before = ability:GetLevel()
                        hero:SetAbilityPoints(math.max(1, hero:GetAbilityPoints()))
                        local ok, err = pcall(function() hero:UpgradeAbility(ability) end)
                        if not ok or ability:GetLevel() <= before then
                            local missing = math.max(0, saved - ability:GetLevel())
                            refund = refund + missing
                            -- Record the actual build so another prepare/capture cannot
                            -- refund the same failed choice a second time.
                            levels[name] = ability:GetLevel()
                            restored = false
                            print(string.format("[Dota2Rpg] Talent restore failed: %s saved=%s actual=%s refunded=%s error=%s",
                                name, tostring(saved), tostring(ability:GetLevel()), tostring(missing),
                                ok and "native upgrade made no progress" or tostring(err)))
                            break
                        end
                    end
                else
                    ability:SetLevel(saved)
                end
            end
        end
    end
    hero:SetAbilityPoints(unspent + refund)
    if data then data.skill_points = unspent + refund end
    return restored
end

return Policy
