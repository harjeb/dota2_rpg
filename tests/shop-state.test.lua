local repoRoot = TEST_REPO_ROOT or "."

function class()
	local result = {}
	result.__index = result
	return result
end

function Vector(x, y, z)
	return { x = x, y = y, z = z }
end

DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3

require = function()
	error("Dota modules are not needed by the shop-state test")
end

local heroData = {
	strength = {
		["1"] = "npc_dota_hero_axe",
		["2"] = "npc_dota_hero_sven",
	},
	agility = {
		["1"] = "npc_dota_hero_juggernaut",
		["2"] = "npc_dota_hero_sniper",
	},
	intelligence = {
		["1"] = "npc_dota_hero_lina",
		["2"] = "npc_dota_hero_lion",
	},
	universal = {
		["1"] = "npc_dota_hero_marci",
		["2"] = "npc_dota_hero_muerta",
	},
	hero_cost = "100",
	refresh_cost = "20",
	bench_slot_cost = "200",
	bench_slot_max = "5",
	lineup_max = "5",
	initial_gold = "300",
}

function LoadKeyValues(path)
	assert(path == "scripts/data/heroes.kv", "unexpected data path: " .. tostring(path))
	return heroData
end

local addonPath = repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua"
local loaded, loadError = pcall(dofile, addonPath)
assert(loaded, "failed to load addon_game_mode.lua: " .. tostring(loadError))

local function newGame(values)
	return setmetatable(values or {}, CDota2RpgDemo)
end

local function assertEqual(actual, expected, message)
	assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local game = newGame({
	currentLevelId = "ch01",
	ownedHeroes = {},
	lineup = {},
	benchSlots = 0,
	shopOffers = {},
	shopOfferText = "",
	refreshCount = 0,
	BroadcastShopState = function(self)
		self.broadcastCalled = true
	end,
})
game:LoadHeroPool()
assertEqual(#game.heroPool.strength, 2, "strength pool size")
assertEqual(#game.heroPool.agility, 2, "agility pool size")
assertEqual(#game.heroPool.intelligence, 2, "intelligence pool size")
assertEqual(#game.heroPool.universal, 2, "universal pool size")
assertEqual(game.shopCosts.initial_gold, 300, "configured initial gold")

game.gold = game.shopCosts.initial_gold
math.randomseed(12345)
game:RollShop()
assertEqual(game.gold, 300, "initial shop gold")
assertEqual(#game.shopOffers, 5, "shop offer size")
assert(game.broadcastCalled, "shop state was not broadcast")

local offerCount = 0
local uniqueOffers = {}
for serializedOffer in string.gmatch(game.shopOfferText, "([^;]+)") do
	offerCount = offerCount + 1
	local heroName = string.match(serializedOffer, "^([^|]+)")
	uniqueOffers[heroName] = true
end
local uniqueCount = 0
for _ in pairs(uniqueOffers) do
	uniqueCount = uniqueCount + 1
end
assertEqual(offerCount, 5, "serialized offer size")
assertEqual(uniqueCount, 5, "serialized unique offer size")

-- 首次创建战场时必须自动生成报价，不能只广播空 offer_text。
local initial = newGame({
	teamsSpawned = false,
	shopOffers = {},
	itemCatalog = {},
	currentLevelId = "ch01",
	RollShop = function(self)
		self.rollShopCalled = true
		self.shopOffers = { { hero = "npc_dota_hero_axe" } }
	end,
	SpawnLevelEnemies = function(self)
		self.spawnEnemiesCalled = true
	end,
	RespawnPlayerRoster = function(self)
		self.respawnCalled = true
	end,
	SpawnBattleBarrier = function(self)
		self.barrierCalled = true
	end,
	BroadcastShopState = function(self)
		self.broadcastCalled = true
	end,
	BroadcastLevelInfo = function() end,
	BroadcastBattleState = function() end,
})
initial:EnsureBattlefield()
assert(initial.rollShopCalled, "initial battlefield did not roll the hero shop")
assert(initial.spawnEnemiesCalled and initial.respawnCalled and initial.barrierCalled,
	"initial battlefield setup did not finish")
assert(initial.broadcastCalled, "initial populated shop state was not broadcast")

print("PASS: initial hero shop rolls five unique offers and broadcasts before setup UI")
