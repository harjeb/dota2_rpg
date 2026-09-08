-- The editor exposes both phases of reviewed native skill swaps. Runtime
-- availability (hidden, deactivated, cooldown, etc.) belongs to ActionAdapter.
local Catalog = {}

-- Only real handles owned by this hero are included. At least one member must
-- be visible, so unavailable upgrade/facet groups do not leak into the picker.
-- Keep native identities separate; never alias a follow-up to its first cast.
local phase_groups = {
    {"dawnbreaker_celestial_hammer", "dawnbreaker_converge"},
    {"dawnbreaker_solar_guardian", "dawnbreaker_land"},
    {"phoenix_fire_spirits", "phoenix_launch_fire_spirit"},
    {"phoenix_icarus_dive", "phoenix_icarus_dive_stop"},
    {"phoenix_sun_ray", "phoenix_sun_ray_stop", "phoenix_sun_ray_toggle_move"},
    {"kunkka_x_marks_the_spot", "kunkka_return"},
    {"alchemist_unstable_concoction", "alchemist_unstable_concoction_throw"},
    {"ancient_apparition_ice_blast", "ancient_apparition_ice_blast_release"},
    {"puck_illusory_orb", "puck_ethereal_jaunt"},
    {"shredder_chakram", "shredder_return_chakram"},
    {"tusk_snowball", "tusk_launch_snowball"},
    {"keeper_of_the_light_illuminate", "keeper_of_the_light_illuminate_end"},
    {"hoodwink_sharpshooter", "hoodwink_sharpshooter_release"},
    {"primal_beast_onslaught", "primal_beast_onslaught_release"},
    {"monkey_king_mischief", "monkey_king_untransform"},
    {"naga_siren_song_of_the_siren", "naga_siren_song_of_the_siren_cancel"},
    {"life_stealer_infest", "life_stealer_consume"},
    {"rubick_telekinesis", "rubick_telekinesis_land"},
    {"ringmaster_tame_the_beasts", "ringmaster_tame_the_beasts_crack"},
    {"tiny_tree_grab", "tiny_toss_tree"},
    {"wisp_tether", "wisp_tether_break"},
    {"nyx_assassin_burrow", "nyx_assassin_unburrow"},
}

local function editable_abilities(hero)
    local abilities, owned, visible, selectable = {}, {}, {}, {}
    for slot = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(slot)
        if ability ~= nil and not ability:IsNull() then
            local name = ability:GetAbilityName()
            if name ~= "" and name ~= "generic_hidden" and not name:match("^special_bonus")
                and not name:match("^rubick_hidden%d+$") and not owned[name] then
                owned[name] = ability
                abilities[#abilities + 1] = ability
                visible[name] = ability.IsHidden == nil or not ability:IsHidden()
                selectable[name] = visible[name]
            end
        end
    end
    for _, group in ipairs(phase_groups) do
        local hasVisibleMember = false
        for _, name in ipairs(group) do
            if visible[name] then hasVisibleMember = true end
        end
        if hasVisibleMember then
            for _, name in ipairs(group) do
                if owned[name] ~= nil then selectable[name] = true end
            end
        end
    end
    local result = {}
    for _, ability in ipairs(abilities) do
        if selectable[ability:GetAbilityName()] then result[#result + 1] = ability end
    end
    return result
end

function Catalog.ListAbilities(hero)
    local names = {}
    for _, ability in ipairs(editable_abilities(hero)) do
        names[#names + 1] = ability:GetAbilityName()
    end
    return names
end

function Catalog.ListActions(hero)
    local actions = {}
    for _, ability in ipairs(editable_abilities(hero)) do
        if not ability:IsPassive() then
            actions[#actions + 1] = ability:GetAbilityName()
        end
    end
    if hero.GetItemInSlot ~= nil then
        for slot = 0, 5 do
            local item = hero:GetItemInSlot(slot)
            if item ~= nil and not item:IsNull() and not item:IsHidden() and not item:IsPassive() then
                table.insert(actions, "item_" .. (slot + 1))
            end
        end
    end
    table.insert(actions, "attack")
    return actions
end

function Catalog.DescribeAction(hero, action)
    if action == "attack" then return "attack", "" end
    if action == "ultimate" then
        for slot = 0, hero:GetAbilityCount() - 1 do
            local ability = hero:GetAbilityByIndex(slot)
            if ability ~= nil and not ability:IsNull() and not ability:IsPassive()
                and not ability:IsHidden() and ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
                return "ability", ability:GetAbilityName()
            end
        end
        return "ability", ""
    end
    local slot = tonumber(action:match("^ability_(%d+)$"))
    if slot ~= nil then
        local ability = hero:GetAbilityByIndex(slot - 1)
        return "ability", ability ~= nil and not ability:IsNull() and ability:GetAbilityName() or ""
    end
    slot = tonumber(action:match("^item_(%d+)$"))
    if slot ~= nil and hero.GetItemInSlot ~= nil then
        local item = hero:GetItemInSlot(slot - 1)
        return "item", item ~= nil and not item:IsNull() and item:GetAbilityName() or ""
    end
    local ability = hero.FindAbilityByName ~= nil and hero:FindAbilityByName(action) or nil
    if ability ~= nil and not ability:IsNull() then return "ability", ability:GetAbilityName() end
    return "ability", action
end

return Catalog
