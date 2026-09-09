-- Native definitions: scripts/npc/heroes/npc_dota_hero_morphling.txt and
-- scripts/npc/heroes/npc_dota_hero_largo.txt (data/native_skill_conditions.json).
-- Apply to project-owned heroes immediately after creation, before leveling skills.
local Policy = {}

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
    local count = hero.GetAbilityCount and hero:GetAbilityCount() or 32
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

return Policy
