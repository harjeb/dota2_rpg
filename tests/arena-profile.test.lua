-- Run from repository root with Lua 5.1 (also supported by Python lupa.lua51).
package.path = "game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
local GOOD, BAD = 2, 3
local nextId, entities, failName, failItem = 0, {}, nil, nil
local failCharges, dropItem = false, false
local function entity(name)
    nextId = nextId + 1
    local value = { name = name, id = nextId }
    entities[#entities + 1] = value
    function value:IsNull() return self.removed == true end
    function value:GetEntityIndex() return self.id end
    function value:GetUnitName() return self.name end
    function value:RemoveSelf() assert(not self.removed, "double removal"); self.removed = true end
    return value
end
local function ability(name, level)
    local value = { name = name, level = level, cooldown = 20 }
    function value:IsNull() return false end
    function value:GetAbilityName() return self.name end
    function value:GetLevel() return self.level end
    function value:SetLevel(level) self.level = level end
    function value:EndCooldown() self.cooldown = 0 end
    return value
end
local function item(name)
    local value = entity(name)
    value.charges, value.secondary, value.cooldown = 1, 9, 20
    function value:GetAbilityName() return self.name end
    function value:GetCurrentCharges() return self.charges end
    function value:GetSecondaryCharges() return self.secondary end
    function value:SetCurrentCharges(n) self.charges = n end
    function value:SetSecondaryCharges(n) if not failCharges then self.secondary = n end end
    function value:EndCooldown() self.cooldown = 0 end
    return value
end
function Vector(x, y, z) return { x = x, y = y, z = z } end
function GetGroundPosition(pos) return Vector(pos.x, pos.y, 42) end
function FindClearSpaceForUnit(unit, pos) unit.pos = Vector(pos.x + 1, pos.y + 1, pos.z) end
function CreateUnitByName(name, pos, _, _, _, side)
    if name == failName then return nil end
    local unit = entity(name)
    unit.pos, unit.side, unit.facing, unit.level, unit.points = pos, side, 0, 1, 0
    unit.items, unit.modifiers = {}, {}
    unit.abilities = { ability("spell_one", 0), ability("spell_two", 0), ability("special_bonus_test", 0) }
    function unit:GetLevel() return self.level end
    function unit:GetAbsOrigin() return self.pos end
    function unit:SetAbsOrigin(pos) self.pos = pos end
    function unit:GetAnglesAsVector() return { y = self.facing } end
    function unit:SetAngles(_, yaw) self.facing = yaw end
    function unit:GetAbilityCount() return 4 end -- sparse final slot
    function unit:GetAbilityByIndex(index) return self.abilities[index + 1] end
    function unit:FindAbilityByName(name)
        for _, value in ipairs(self.abilities) do if value.name == name then return value end end
    end
    function unit:GetAbilityPoints() return self.points end
    function unit:SetAbilityPoints(points) self.points = points end
    function unit:UpgradeAbility(value) value.level = value.level + 1; self.points = self.points - 1 end
    function unit:HasModifier(name) return self.modifiers[name] == true end
    function unit:AddNewModifier(_, _, name) self.modifiers[name] = true end
    function unit:GetItemInSlot(slot) return self.items[slot] end
    function unit:AddItemByName(name)
        if name == failItem then return nil end
        local value = item(name)
        if dropItem then return value end
        -- Native insertion can use only ordinary inventory/backpack space.
        for slot = 0, 8 do if not self.items[slot] then self.items[slot] = value; return value end end
        return value -- overflow creates a detached item
    end
    function unit:SwapItems(a, b) self.items[a], self.items[b] = self.items[b], self.items[a] end
    function unit:RemoveItem(value)
        for slot = 0, 16 do if self.items[slot] == value then self.items[slot] = nil end end
    end
    function unit:GetMaxHealth() return self.items[0] and 1400 or 1000 end
    function unit:GetMaxMana() return self.items[0] and 800 or 500 end
    function unit:SetHealth(value) self.health = value end
    function unit:SetMana(value) self.mana = value end
    return unit
end
local lifecycleEvents = 0
require("issue_fixes.hero_lifecycle_log").Event = function() lifecycleEvents = lifecycleEvents + 1 end
local Profile = require("battle.arena_profile")
local function equal(a, b, path)
    path = path or "root"
    assert(type(a) == type(b), path .. " type mismatch")
    if type(a) ~= "table" then assert(a == b, path .. ": " .. tostring(a) .. " ~= " .. tostring(b)); return end
    for k, v in pairs(a) do equal(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do assert(a[k] ~= nil, path .. " unexpected key " .. tostring(k)) end
end
local function fixture()
    local team = { version = "arena-team-v1", heroes = {}, storage = {
        { name = "item_shared", charges = 3, secondary_charges = 0 },
        { name = "item_shared", charges = 7, secondary_charges = 2 } } }
    for i = 1, 5 do
        team.heroes[i] = { id = "h" .. i, name = "npc_dota_hero_test" .. i, level = 30,
            position = { x = -1000 + i * 50, y = -600 + i * 100 }, facing = -170 + i * 20,
            abilities = { spell_one = 2, spell_two = 0, special_bonus_test = 1 }, ability_points = 17,
            items = { { slot = 0, name = "item_ultimate_scepter", charges = 0, secondary_charges = 0 },
                { slot = 7, name = "item_wand", charges = i, secondary_charges = 2 },
                { slot = 12, name = "item_stash", charges = 2, secondary_charges = 0 },
                { slot = 16, name = "item_neutral", charges = 0, secondary_charges = 0 } },
            shard = i == 1, scepter = i == 2, moon_shard = i == 1,
            rules = { { id = "rule-" .. i, enabled = false, priority = 19,
                condition = { target_actor = "arena:enemy:npc_dota_hero_test1:1", nested = { threshold = 42 } },
                action = { type = "cast", ability = "spell_one", extra = { "keep", "all" } } } } }
    end
    return team
end
local function gameFor(team)
    local game = { lineup = {}, heroData = {}, autoAbilityHeroes = {}, heroInventories = {},
        placedPositions = {}, heroRulesByName = {}, battleManager = {
            teamHeroes = { [GOOD] = {}, [BAD] = {} }, teamRules = { [GOOD] = {}, [BAD] = {} },
            heroStates = {}, recentDamage = {}, recentHitCounts = {}, enemyTags = {} } }
    game.placeholderHero = CreateUnitByName("commander", Vector(0, 0, 0), true, nil, nil, GOOD)
    for i, hero in ipairs(team.heroes) do game.lineup[i] = hero.name end
    local service = { state = { rules = {} }, get_hero_key = function(unit) return unit:GetEntityIndex() end }
    game.tacticBridge = { ruleService = service }
    game.tacticBridge.getRules = function(unit) return unit.arenaRules or service.state.rules[service.get_hero_key(unit)] or {} end
    function game:BindEquipmentCarrierToPlayer(unit) unit.bound = true; return true end
    function game:PrepareBattleHero(unit, level)
        unit.level = level
        if self.autoAbilityHeroes[unit.id] then
            for _, value in ipairs(unit.abilities) do value.level = 4 end
            unit.points = 0
        else
            assert(unit.bound and unit.lineupHeroName)
            assert(require("issue_fixes.hero_ability_policy").RestoreManualAbilities(unit, self.heroData[unit.name], level))
            unit.rpgAbilitiesRestored = true
        end
    end
    return game
end
local team = fixture()
local game = gameFor(team)
assert(Profile.Spawn(game, team, GOOD, false))
equal(assert(Profile.Capture(game)), team)
local dropped={IsNull=function() return false end,GetContainedItem=function() return {IsNull=function() return false end} end}
Entities={FindAllByClassname=function() return {dropped} end}
local groundCapture,groundReason=Profile.Capture(game)
assert(not groundCapture and groundReason:match("ground equipment"), "unowned ground items cannot silently vanish from the saved configuration")
Entities=nil
local roster = game.battleManager.teamHeroes[GOOD]
roster[1], roster[5] = roster[5], roster[1]
equal(assert(Profile.Capture(game)), team) -- lineup order wins over manager storage order
roster[1], roster[5] = roster[5], roster[1]
local ownUnit = game.battleManager.teamHeroes[GOOD][1]
assert(ownUnit.arenaRules == nil and ownUnit.bound)
assert(not ownUnit:HasModifier("modifier_item_ultimate_scepter_consumed"), "equipped scepter must not become consumed")
assert(ownUnit:HasModifier("modifier_item_aghanims_shard"))
assert(ownUnit:HasModifier("modifier_item_moon_shard_consumed"), "consumed Moon Shard survives restoration")
assert(ownUnit.health == ownUnit:GetMaxHealth() and ownUnit.mana == ownUnit:GetMaxMana())
for _, value in ipairs(ownUnit.abilities) do assert(value.cooldown == 0) end
for slot, value in pairs(ownUnit.items) do assert(value.cooldown == 0); assert(slot ~= 1) end
assert(Profile.Spawn(game, team, BAD, false))
local enemy = game.battleManager.teamHeroes[BAD][1]
equal(enemy.pos, { x = 950, y = 500, z = 42 })
assert(enemy.facing == 30 and enemy.lineupHeroName == nil and enemy.enemyRuleIndex == 1)
assert(game.autoAbilityHeroes[enemy.id] and enemy.points == 17)
assert(enemy.abilities[1].level == 2 and enemy.abilities[2].level == 0 and enemy.abilities[3].level == 1)
local enemyRules = enemy.arenaRules
enemyRules[1].condition.nested.threshold = 100
assert(team.heroes[1].rules[1].condition.nested.threshold == 42)
local ownRules = game.tacticBridge.ruleService.state.rules[ownUnit.id]
ownRules[1].condition.target_actor = "chapter_7:enemy:npc_dota_hero_test1:2"
ownRules[1].action.extra[2] = "edited"
ownUnit.pos = Vector(-200.4, 700.8, 0)
local captured = assert(Profile.Capture(game))
equal(captured.heroes[1].position, { x = -200, y = 611 })
assert(captured.heroes[1].rules[1].condition.target_actor == "arena:enemy:npc_dota_hero_test1:2")
assert(captured.heroes[1].rules[1].action.extra[2] == "edited")
assert(ownRules[1].condition.target_actor:match("^chapter_7:"), "capture must not mutate source rules")
assert(enemyRules[1].action.extra[2] == "all", "same-name teams share no rule tables")
ownUnit.pos = Vector(-2000, -611.4, 0)
equal(assert(Profile.Capture(game)).heroes[1].position, { x = -1136, y = -611 })
-- Replace native entities repeatedly, including consumed charges and persistent stats.
local oldItems, oldId = ownUnit.items, ownUnit.id
ownUnit.items[7].charges = 0
ownUnit.permanentStrength = 100
assert(Profile.Spawn(game, team, GOOD, false))
assert(ownUnit.removed and game.autoAbilityHeroes[oldId] == nil)
assert(game.tacticBridge.ruleService.state.rules[oldId] == nil)
for _, value in pairs(oldItems) do assert(value.removed) end
equal(assert(Profile.Capture(game)), team)
assert(game.battleManager.teamHeroes[GOOD][1].permanentStrength == nil)
assert(not enemy.removed and enemy.arenaRules == enemyRules)
-- Full slot occupancy tests insertion while ordinary native inventory is full.
local full = fixture()
full.heroes[1].items = {}
for slot = 0, 16 do
    if slot ~= 15 then full.heroes[1].items[#full.heroes[1].items + 1] = {
        slot = slot, name = "item_full", charges = slot, secondary_charges = 0 } end
end
assert(Profile.Spawn(game, full, GOOD, false))
equal(assert(Profile.Capture(game)), full)
-- Invalid input must be rejected before replacing an existing team.
local invalid = Profile.Copy(team)
invalid.heroes[1].items[1].slot = 15
local current = game.battleManager.teamHeroes[GOOD][1]
local ok, reason = Profile.Spawn(game, invalid, GOOD, false)
assert(not ok and reason:match("slot") and not current.removed)
-- Mid-spawn item failure cleans every created unit/item and own native storage.
failItem = "item_wand"
ok, reason = Profile.Spawn(game, team, GOOD, false)
assert(not ok and reason:match("item creation failed"))
assert(next(game.battleManager.teamHeroes[GOOD]) == nil)
assert(next(game.placeholderHero.items) == nil)
assert(not enemy.removed)
failItem = nil
assert(Profile.Spawn(game, team, GOOD, false))
equal(assert(Profile.Capture(game)), team)
-- A storage failure after all five heroes exist also rolls back the whole own side.
failItem = "item_shared"
ok, reason = Profile.Spawn(game, team, GOOD, false)
assert(not ok and reason:match("item_shared"))
assert(next(game.battleManager.teamHeroes[GOOD]) == nil and next(game.placeholderHero.items) == nil)
failItem = nil
assert(Profile.Spawn(game, team, GOOD, false))
local missingAbility = Profile.Copy(team)
missingAbility.heroes[2].abilities.removed_spell = 1
ok, reason = Profile.Spawn(game, missingAbility, GOOD, false)
assert(not ok and reason:match("unsupported native ability"))
assert(next(game.battleManager.teamHeroes[GOOD]) == nil)
assert(Profile.Spawn(game, team, GOOD, false))
failCharges = true
ok, reason = Profile.Spawn(game, team, GOOD, false)
assert(not ok and reason:match("charge state"))
failCharges = false
dropItem = true
ok, reason = Profile.Spawn(game, team, GOOD, false)
assert(not ok and reason:match("no inventory slot"))
dropItem = false
assert(Profile.Spawn(game, team, GOOD, false))
failName = team.heroes[3].name
ok, reason = Profile.Spawn(game, team, BAD, false)
assert(not ok and reason:match("hero creation failed"))
assert(next(game.battleManager.teamHeroes[BAD]) == nil and enemy.removed)
failName = nil
assert(Profile.Spawn(game, team, BAD, true))
for _, unit in ipairs(game.battleManager.teamHeroes[BAD]) do
    assert(unit.arenaRules == nil and unit.lineupHeroName == nil and unit.points == 0)
    assert(unit.abilities[1].level == 4)
end
-- Unsupported native slot state must not silently disappear from capture.
current = game.battleManager.teamHeroes[GOOD][1]
current.items[15] = item("item_tpscroll")
local missing, why = Profile.Capture(game)
assert(missing == nil and why:match("TP slot 15"))
Profile.Clear(game, GOOD)
Profile.Clear(game, GOOD)
Profile.Clear(game, BAD)
-- Clear leaves shared storage intact; explicitly remove it for leak accounting.
for _, value in pairs(game.placeholderHero.items) do value:RemoveSelf() end
game.placeholderHero:RemoveSelf()
for _, value in ipairs(entities) do assert(value.removed, "leaked native entity: " .. value.name) end
local copy = Profile.Copy(team)
copy.heroes[1].position.x = -151
assert(team.heroes[1].position.x == -950)
local cycle = {}; cycle.self = cycle
assert(not pcall(Profile.Copy, cycle))
equal(Profile.PositionForSide({ x = -1136, y = 611 }, BAD), { x = 1136, y = -611 })
equal(Profile.PositionForSide({ x = -1136, y = 611 }, GOOD), { x = -1136, y = 611 })
assert(lifecycleEvents > 0, "native create/remove must use lifecycle logger")
print("arena-profile tests passed")
