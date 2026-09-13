-- Native arena snapshots. Profiles contain values only, never entity handles.
local Lifecycle = require("issue_fixes.hero_lifecycle_log")
local AbilityPolicy = require("issue_fixes.hero_ability_policy")
local Profile = {}
local function valid(unit) return unit ~= nil and (not unit.IsNull or not unit:IsNull()) end
local function own(side) return side == DOTA_TEAM_GOODGUYS end
local function checkSide(side)
    assert(side == DOTA_TEAM_GOODGUYS or side == DOTA_TEAM_BADGUYS, "invalid arena side")
end
function Profile.Copy(value, active)
    local kind = type(value)
    assert(kind == "table" or kind == "string" or kind == "number" or kind == "boolean" or kind == "nil", "non-plain profile value")
    if kind ~= "table" then return value end
    assert(getmetatable(value) == nil, "non-plain profile table")
    active = active or {}
    assert(not active[value], "cyclic profile value")
    active[value] = true
    local result = {}
    for key, child in pairs(value) do result[Profile.Copy(key, active)] = Profile.Copy(child, active) end
    active[value] = nil
    return result
end
function Profile.PositionForSide(position, side)
    checkSide(side)
    local sign = own(side) and 1 or -1
    return { x = position.x * sign, y = position.y * sign }
end
local function canonical(rules)
    local result = Profile.Copy(rules or {})
    local function visit(node)
        if type(node) ~= "table" then return end
        if type(node.target_actor) == "string" then
            node.target_actor = node.target_actor:gsub("^[^:]+:enemy:(.+):(%d+)$", "arena:enemy:%1:%2")
        end
        for _, child in pairs(node) do if type(child) == "table" then visit(child) end end
    end
    visit(result)
    return result
end
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
local function rounded(value, low, high)
    return math.max(low, math.min(high, math.floor(value + 0.5)))
end
local function angle(value) return (value + 180) % 360 - 180 end
local function items(unit, slots)
    local result = {}
    if not valid(unit) then return result end
    for slot = 0, 16 do
        local item = unit:GetItemInSlot(slot)
        if valid(item) then
            assert(slot ~= 15, "unsupported native item state: TP slot 15")
            local record = { name = item:GetAbilityName(), charges = item:GetCurrentCharges(),
                secondary_charges = item:GetSecondaryCharges() }
            if slots then record.slot = slot end
            result[#result + 1] = record
        end
    end
    return result
end
function Profile.Capture(game)
    local ok, result = pcall(function()
        assert(#(game.lineup or {}) == 5, "arena requires five lineup heroes")
        if Entities and Entities.FindAllByClassname then
            for _,drop in pairs(Entities:FindAllByClassname("dota_item_physical") or {}) do
                assert(not (valid(drop) and drop.GetContainedItem and valid(drop:GetContainedItem())),
                    "collect ground equipment before saving the arena team")
            end
        end
        local manager = assert(game.battleManager, "missing battle manager")
        local ruleProvider = game.tacticBridge or manager
        assert(type(ruleProvider.getRules) == "function", "canonical rule provider unavailable")
        local team = { version = "arena-team-v1", heroes = {}, storage = items(game.placeholderHero, false) }
        local used = {}
        for index, name in ipairs(game.lineup) do
            local unit
            for _, candidate in ipairs(manager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
                if valid(candidate) and not used[candidate] and candidate:GetUnitName() == name then unit = candidate; break end
            end
            assert(unit, "missing live lineup hero: " .. tostring(name))
            used[unit] = true
            assert(unit:GetLevel() == 30, "arena capture requires level 30 heroes")
            local position, abilities = unit:GetAbsOrigin(), {}
            for slot = 0, AbilityPolicy.GetSlotCount(unit) - 1 do
                local ability = unit:GetAbilityByIndex(slot)
                if valid(ability) then abilities[ability:GetAbilityName()] = ability:GetLevel() end
            end
            team.heroes[index] = { id = "h" .. index, name = name, level = 30,
                position = { x = rounded(position.x, -1136, -150), y = rounded(position.y, -611, 611) },
                facing = angle(unit:GetAnglesAsVector().y), abilities = abilities,
                ability_points = unit:GetAbilityPoints(), items = items(unit, true),
                shard = unit:HasModifier("modifier_item_aghanims_shard"),
                moon_shard = unit:HasModifier("modifier_item_moon_shard_consumed"),
                scepter = unit:HasModifier("modifier_item_ultimate_scepter_consumed"),
                rules = canonical(ruleProvider.getRules(unit)) }
            assert(integer(team.heroes[index].ability_points, 0, 30), "unsupported native ability points")
        end
        return team
    end)
    if ok then return result end
    return nil, tostring(result)
end
local function purge(game, unit, seen)
    if not valid(unit) then return end
    seen = seen or {}
    for slot = 0, 16 do
        local item = unit:GetItemInSlot(slot)
        if valid(item) and not seen[item] then
            seen[item] = true
            unit:RemoveItem(item)
            if valid(item) then Lifecycle.Remove(game, item, "arena_item") end
        end
    end
end
function Profile.Clear(game, side)
    checkSide(side)
    local manager = game.battleManager
    local seen = {}
    for _, unit in pairs(manager.teamHeroes[side] or {}) do
        if valid(unit) then
            local id, name = unit:GetEntityIndex(), unit:GetUnitName()
            purge(game, unit, seen)
            if own(side) then
                local data = game.heroData and game.heroData[name]
                if data then
                    for _, item in pairs(data.inventory_entities or {}) do
                        if not seen[item] and valid(item) then seen[item] = true; Lifecycle.Remove(game, item, "arena_inventory_mirror") end
                    end
                    data.inventory, data.inventory_states, data.inventory_entities = {}, {}, {}
                end
                if game.heroInventories then game.heroInventories[name] = nil end
                local service = game.tacticBridge and game.tacticBridge.ruleService
                if service then service.state.rules[service.get_hero_key(unit)] = nil end
            end
            if game.autoAbilityHeroes then game.autoAbilityHeroes[id] = nil end
            for _, map in ipairs({ "heroStates", "recentDamage", "recentHitCounts", "enemyTags" }) do
                if manager[map] then manager[map][id] = nil end
            end
            Lifecycle.Remove(game, unit, "arena_hero")
        end
    end
    manager.teamHeroes[side], manager.teamRules[side] = {}, {}
    game.equipmentSnapshot = nil
end
local function validate(team)
    Profile.Copy(team)
    assert(team.version == "arena-team-v1" and #team.heroes == 5, "invalid arena team")
    local names = {}
    local function validateItems(list, slotted)
        local slots = {}
        for _, item in ipairs(list) do
            assert(type(item.name) == "string" and item.name:match("^item_"), "invalid item name")
            assert(integer(item.charges, 0, 2147483647) and integer(item.secondary_charges, 0, 2147483647), "invalid item charges")
            if slotted then
                assert(integer(item.slot, 0, 16) and item.slot ~= 15 and not slots[item.slot], "unsupported or duplicate item slot")
                slots[item.slot] = true
            end
        end
    end
    for index, hero in ipairs(team.heroes) do
        assert(hero.id == "h" .. index and hero.level == 30, "invalid hero id or level")
        assert(type(hero.name) == "string" and hero.name:match("^npc_dota_hero_") and not names[hero.name], "invalid or duplicate hero name")
        names[hero.name] = true
        assert(integer(hero.position.x, -1136, -150) and integer(hero.position.y, -611, 611), "invalid hero position")
        assert(type(hero.facing) == "number" and hero.facing >= -180 and hero.facing <= 180, "invalid facing")
        assert(integer(hero.ability_points, 0, 30), "invalid ability points")
        assert(type(hero.shard) == "boolean" and type(hero.scepter) == "boolean", "invalid upgrade flags")
        assert(hero.moon_shard == nil or type(hero.moon_shard) == "boolean", "invalid Moon Shard flag")
        assert(type(hero.rules) == "table" and type(hero.abilities) == "table", "invalid rules or abilities")
        for name, level in pairs(hero.abilities) do assert(type(name) == "string" and integer(level, 0, 30), "invalid ability") end
        validateItems(hero.items, true)
    end
    validateItems(team.storage, false)
end
local function restoreItems(game, unit, records, slotted)
    purge(game, unit)
    local ordered = Profile.Copy(records)
    assert(#ordered <= 16, "unsupported native storage capacity")
    if not slotted then
        for index, record in ipairs(ordered) do record.slot = index <= 15 and index - 1 or 16 end
    end
    -- Fill high slots first: native AddItemByName needs a free ordinary slot.
    table.sort(ordered, function(a, b) return a.slot > b.slot end)
    for _, record in ipairs(ordered) do
        local item = unit:AddItemByName(record.name)
        assert(valid(item), "native item creation failed: " .. record.name)
        -- AddItemByName may return a dropped item when no native slot is available.
        local actual
        for slot = 0, 16 do if unit:GetItemInSlot(slot) == item then actual = slot; break end end
        if actual == nil then
            local container = item.GetContainer and item:GetContainer()
            if valid(container) then Lifecycle.Remove(game, container, "arena_dropped_container") end
            if valid(item) then Lifecycle.Remove(game, item, "arena_dropped_item") end
            error("unsupported native item state: no inventory slot for " .. record.name)
        end
        if actual ~= record.slot then unit:SwapItems(actual, record.slot) end
        assert(unit:GetItemInSlot(record.slot) == item, "native item slot restoration failed")
        item:SetCurrentCharges(record.charges)
        item:SetSecondaryCharges(record.secondary_charges)
        assert(item:GetCurrentCharges() == record.charges and item:GetSecondaryCharges() == record.secondary_charges,
            "unsupported native item charge state: " .. record.name)
        item:EndCooldown()
    end
    -- Native combining/stacking or a later insertion must not silently alter earlier items.
    local expected = {}
    for _, record in ipairs(ordered) do expected[record.slot] = record end
    for slot = 0, 16 do
        local item, record = unit:GetItemInSlot(slot), expected[slot]
        assert((record == nil and not valid(item)) or (record ~= nil and valid(item)
            and item:GetAbilityName() == record.name and item:GetCurrentCharges() == record.charges
            and item:GetSecondaryCharges() == record.secondary_charges), "unsupported native item state after restoration")
    end
end
function Profile.Spawn(game, team, side, preset)
    local checked, reason = pcall(function() checkSide(side); validate(team) end)
    if not checked then return false, tostring(reason) end
    local ok, failure = pcall(function()
        Profile.Clear(game, side)
        local manager = game.battleManager
        game.autoAbilityHeroes = game.autoAbilityHeroes or {}
        game.heroData = game.heroData or {}
        for index, record in ipairs(team.heroes) do
            local pos = Profile.PositionForSide(record.position, side)
            local ground = GetGroundPosition(Vector(pos.x, pos.y, 128), nil)
            local unit = Lifecycle.Create(game, record.name, ground, side, "arena_hero")
            assert(valid(unit), "native hero creation failed: " .. record.name)
            -- Register immediately so every later failure can remove the partial team.
            manager.teamHeroes[side][index] = unit
            FindClearSpaceForUnit(unit, ground, true)
            unit:SetAbsOrigin(ground)
            unit:SetAngles(0, angle(record.facing + (own(side) and 0 or 180)), 0)
            local data = { level = 30, current_xp = 0, quality = "common", ability_levels = Profile.Copy(record.abilities),
                skill_points = record.ability_points, inventory = {}, inventory_states = {}, inventory_entities = {} }
            if own(side) then
                game.heroData[record.name] = data
                unit.lineupHeroName = record.name
                game.autoAbilityHeroes[unit:GetEntityIndex()] = nil
                assert(game:BindEquipmentCarrierToPlayer(unit), "failed to bind arena equipment owner")
            else
                unit.enemyRuleIndex = index
                game.autoAbilityHeroes[unit:GetEntityIndex()] = true
                if not preset then unit.arenaRules = canonical(record.rules) end
            end
            game:PrepareBattleHero(unit, 30)
            if record.shard then unit:AddNewModifier(unit, nil, "modifier_item_aghanims_shard", {}) end
            if record.scepter then unit:AddNewModifier(unit, nil, "modifier_item_ultimate_scepter_consumed", {}) end
            if record.moon_shard then unit:AddNewModifier(unit, nil, "modifier_item_moon_shard_consumed", {}) end
            restoreItems(game, unit, record.items, true)
            -- Upgrades/items may expose additional abilities; replay the saved build afterward.
            if not preset then
                assert(AbilityPolicy.RestoreManualAbilities(unit, data, 30), "native ability restoration failed")
                unit.rpgAbilitiesRestored = true
                for name, level in pairs(record.abilities) do
                    local ability = unit:FindAbilityByName(name)
                    assert(valid(ability) and ability:GetLevel() == level, "unsupported native ability: " .. name)
                end
            end
            if own(side) then
                for slot = 0, 16 do
                    local item = unit:GetItemInSlot(slot)
                    if valid(item) then
                        data.inventory[#data.inventory + 1] = item:GetAbilityName()
                        data.inventory_states[#data.inventory_states + 1] = {
                            name = item:GetAbilityName(), charges = item:GetCurrentCharges(),
                            secondary_charges = item:GetSecondaryCharges(), slot = slot }
                        data.inventory_entities[#data.inventory_entities + 1] = item
                    end
                end
            end
            unit:SetHealth(unit:GetMaxHealth())
            unit:SetMana(unit:GetMaxMana())
            for slot = 0, AbilityPolicy.GetSlotCount(unit) - 1 do
                local ability = unit:GetAbilityByIndex(slot)
                if valid(ability) then ability:EndCooldown() end
            end
            if own(side) then
                local service = assert(game.tacticBridge and game.tacticBridge.ruleService, "canonical rule service unavailable")
                service.state.rules[service.get_hero_key(unit)] = canonical(record.rules)
                if game.heroRulesByName then game.heroRulesByName[record.name] = canonical(record.rules) end
                if game.placedPositions then game.placedPositions[record.name] = Profile.Copy(record.position) end
            end
            manager.teamRules[side][index] = not preset and canonical(record.rules) or nil
        end
        if own(side) then
            assert(valid(game.placeholderHero) or #team.storage == 0, "storage commander unavailable")
            if valid(game.placeholderHero) then restoreItems(game, game.placeholderHero, team.storage, false) end
        end
    end)
    if not ok then
        local cleaned, cleanupReason = pcall(function()
            Profile.Clear(game, side)
            if own(side) then purge(game, game.placeholderHero) end
        end)
        return false, tostring(failure) .. (cleaned and "" or "; cleanup failed: " .. tostring(cleanupReason))
    end
    return true
end
return Profile
