local root = TEST_REPO_ROOT or "."
local moduleRoot = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
function class() local result = {}; result.__index = result; return result end
function Vector(x, y, z) return { x = x, y = y, z = z } end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_UNIT_ORDER_TRAIN_ABILITY = 11
function IsValidEntity(unit) return unit ~= nil end
TacticEngine = { IsValidUnit = function(unit) return unit ~= nil end }
require = function(name)
    if name == "issue_fixes.bootstrap" then return { Install = function() end } end
    local path = moduleRoot .. name:gsub("%.", "/") .. ".lua"
    local file = io.open(path, "r")
    if file then file:close(); return dofile(path) end
    error("unused engine module: " .. name)
end
dofile(moduleRoot .. "addon_game_mode.lua")

local nativeWarnings = {}
local function makeHero(level)
    local hero = { level = level, points = 2, lineupHeroName = "axe", abilities = {},
        rpgAbilitiesRestored = true, hp = 123, mana = 45, idle = true, acquisition = 600,
        modifiers = {}, cooldown = 8 }
    function hero:IsNull() return false end
    function hero:GetUnitName() return "npc_dota_hero_axe" end
    function hero:GetEntityIndex() return 100 end
    function hero:GetLevel() return self.level end
    function hero:HeroLevelUp() self.level = self.level + 1; self.points = self.points + 1 end
    function hero:GetAbilityPoints() return self.points end
    function hero:SetAbilityPoints(points) self.points = points end
    -- Sparse talent index 23 is valid because the native slot bound includes it.
    function hero:GetAbilityCount() return 24 end
    function hero:GetAbilityByIndex(slot)
        if slot < 0 or slot >= self:GetAbilityCount() then
            nativeWarnings[#nativeWarnings + 1] = "GetAbilityByIndex requested for invalid index " .. slot
            return nil
        end
        return self.abilities[slot]
    end
    function hero:SetRespawnsDisabled() end
    function hero:GetMaxHealth() return 1000 end
    function hero:GetMaxMana() return 500 end
    function hero:SetHealth(v) self.hp = v end
    function hero:SetMana(v) self.mana = v end
    function hero:SetIdleAcquire(v) self.idle = v end
    function hero:SetAcquisitionRange(v) self.acquisition = v end
    function hero:AddNewModifier(_, _, name) self.modifiers[name] = true end
    for slot, name in pairs({ [0] = "axe_berserkers_call", [23] = "special_bonus_unique_axe_5" }) do
        local ability = { name = name, level = slot == 0 and 3 or 1, id = 500 + slot }
        function ability:IsNull() return false end
        function ability:GetAbilityName() return self.name end
        function ability:GetLevel() return self.level end
        function ability:SetLevel(v) self.level = v end
        function ability:entindex() return self.id end
        function ability:GetCaster() return hero end
        hero.abilities[slot] = ability
    end
    return hero
end
local hero = makeHero(10)
local game = setmetatable({ phase = "setup", playerId = 0, lineup = { "axe" }, benchUnits = {},
    autoAbilityHeroes = {}, scrollStock = { high = 1 },
    heroData = { axe = { level = 10, current_xp = 0, skill_points = 2 } },
    FindLineupUnit = function() return hero end,
    SyncHeroInventoryFromUnit = function() end,
    BroadcastHeroInfo = function() end, BroadcastShopState = function() end,
    IsNativeItemShopOrder = function() return false end,
    IsEquipmentCarrier = function(_, unit) return unit == hero end,
    IsLineupUnit = function(_, unit) return unit == hero end,
    IsBenchUnit = function() return false end,
}, CDota2RpgDemo)
local data = game.heroData.axe
-- Exercise the actual scroll handler and installed XP curve.
game:OnScrollUse(nil, { hero = "axe", kind = "high" })
assert(data.level > 10 and hero.level == data.level, "scroll applies earned levels immediately")
assert(hero.points == 2 + data.level - 10, "one point per earned level")
assert(game.scrollStock.high == 0, "scroll consumed once")
assert(next(hero.modifiers) == nil and hero.idle and hero.acquisition == 600,
    "scroll must not reapply battle preparation or disable live acquisition")
assert(hero.hp == 123 and hero.mana == 45 and hero.cooldown == 8,
    "scroll preserves live combat state")
assert(hero.abilities[23].level == 1, "live talent stays learned")
game:OnScrollUse(nil, { hero = "axe", kind = "high" })
assert(hero.points == 2 + data.level - 10, "empty stock cannot add points")

-- Learn between think ticks and rebuild immediately: capture must retain talents.
hero.abilities[23].level = 1
hero.points = hero.points - 1
local expectedPoints = hero.points
local snapshotBefore = game:BuildRosterAbilitySnapshot()
hero.abilities[23].level = 0
assert(snapshotBefore ~= game:BuildRosterAbilitySnapshot(), "snapshot includes high talent slot")
hero.abilities[23].level = 1
game:CaptureHeroAbilities(hero)
assert(data.ability_levels.special_bonus_unique_axe_5 == 1, "capture includes sparse talents")
-- Stage XP earned while the old entity is still at its previous level.
data.level = data.level + 2
game:CaptureHeroAbilities(hero)
assert(data.skill_points == expectedPoints + 2, "pending stage levels retain points")
local replacement = makeHero(1)
replacement.rpgAbilitiesRestored = nil
replacement.abilities[0].level, replacement.abilities[23].level = 0, 0
replacement.abilities[19], replacement.abilities[23] = replacement.abilities[23], nil
game:PrepareBattleHero(replacement, data.level)
assert(replacement.abilities[0].level == 3 and replacement.abilities[19].level == 1,
    "next-stage entity restores ordinary abilities and high-slot talent by name")
assert(replacement.points == expectedPoints + 2, "rebuild preserves unspent and earned points")
game:CaptureHeroAbilities(replacement)
assert(data.skill_points == replacement.points, "capture after rebuild cannot award twice")
replacement.benchHeroName, replacement.lineupHeroName = "axe", nil
replacement.points = replacement.points - 1
game:CaptureHeroAbilities(replacement)
assert(data.skill_points == replacement.points and data.ability_levels.special_bonus_unique_axe_5 == 1,
    "bench heroes persist the same talent and point records")
local bench = makeHero(1)
bench.benchHeroName, bench.lineupHeroName, bench.rpgAbilitiesRestored = "axe", nil, nil
bench.abilities[23].level = 0
game:PrepareBattleHero(bench, data.level)
assert(bench.abilities[23].level == 1 and bench.points == replacement.points,
    "bench rebuild restores talents without retraining")
assert(bench.modifiers.modifier_rpg_prepare_bench, "bench preparation still applies on creation")

EntIndexToHScript = function(id)
    if id == 100 then return hero end
    if id == 523 then return hero.abilities[23] end
end
assert(game:ValidatePrepareOrder({ issuer_player_id_const = 0, order_type = 11,
    units = { ["0"] = 100 }, entindex_ability = 523 }), "native talent entity training allowed")
assert(game:ValidatePrepareOrder({ issuer_player_id_const = 0, order_type = 11,
    units = { ["0"] = 100 }, entindex_ability = 23 }), "native talent slot training allowed")
assert(game:ValidatePrepareOrder({ issuer_player_id_const = 0, order_type = 11,
    ability_index = 523 }), "unitless alias resolves talent caster")
assert(not game:ValidatePrepareOrder({ issuer_player_id_const = 0, order_type = 11,
    units = { ["0"] = 100 }, entindex_ability = 24 }), "out-of-bound talent slot rejected")
assert(not game:ValidatePrepareOrder({ issuer_player_id_const = 1, order_type = 11,
    units = { ["0"] = 100 }, entindex_ability = 523 }), "other player rejected")
game.phase = "fight"
assert(not game:ValidatePrepareOrder({ issuer_player_id_const = 0, order_type = 11,
    units = { ["0"] = 100 }, entindex_ability = 523 }), "combat training remains blocked")
-- Engine refusal at the cap must not trap the server in an infinite level loop.
function hero:HeroLevelUp() end
game:UpdateHeroLevel(hero, 999)
assert(hero.level < 30, "failed engine level up returns safely")
game.phase, game.scrollStock.high, data.level = "setup", 1, 30
game:OnScrollUse(nil, { hero = "axe", kind = "high" })
assert(game.scrollStock.high == 1, "max-level heroes cannot consume scrolls")
game.phase, data.level = "fight", 10
game:OnScrollUse(nil, { hero = "axe", kind = "high" })
assert(game.scrollStock.high == 1, "scroll rejected once fight has started")
assert(#nativeWarnings == 0, table.concat(nativeWarnings, "\n"))
print("hero-progression.test.lua: passed")
