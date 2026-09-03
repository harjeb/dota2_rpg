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
		["1"] = { name = "npc_dota_hero_axe" },
		["2"] = { name = "npc_dota_hero_sven" },
	},
	agility = {
		["1"] = { name = "npc_dota_hero_juggernaut" },
		["2"] = { name = "npc_dota_hero_sniper" },
	},
	intelligence = {
		["1"] = { name = "npc_dota_hero_lina" },
		["2"] = { name = "npc_dota_hero_lion" },
	},
	universal = {
		["1"] = { name = "npc_dota_hero_marci" },
		["2"] = { name = "npc_dota_hero_muerta" },
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

local lastEvent = nil
CustomGameEventManager = {
	Send_ServerToAllClients = function(_, eventName, payload)
		lastEvent = { name = eventName, payload = payload }
	end,
}

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
	playerLevel = 1,
	ownedHeroes = {},
	lineup = {},
	benchSlots = 0,
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
assertEqual(#game.shopOffer, 5, "shop offer size")
assert(lastEvent ~= nil and lastEvent.name == "rpg_shop_state", "shop state event was not broadcast")
assertEqual(lastEvent.payload.gold, 300, "broadcast initial gold")

local offerCount = 0
local uniqueOffers = {}
for heroName in string.gmatch(lastEvent.payload.offer_text, "([^;]+)") do
	offerCount = offerCount + 1
	uniqueOffers[heroName] = true
end
local uniqueCount = 0
for _ in pairs(uniqueOffers) do
	uniqueCount = uniqueCount + 1
end
assertEqual(offerCount, 5, "serialized offer size")
assertEqual(uniqueCount, 5, "serialized unique offer size")

local synced = newGame({
	phase = "setup",
	gold = 0,
	playerLevel = 1,
	benchSlots = 0,
	ownedHeroes = {},
	lineup = {},
	shopCosts = { bench_slot_max = 5 },
	teamsSpawned = false,
	dataLoader = {
		GetLevel = function(_, levelId)
			return levelId == "ch01" and {} or nil
		end,
	},
	RollShop = function(self)
		self.rollShopCalled = true
	end,
	RespawnPlayerRoster = function(self)
		self.respawnCalled = true
	end,
})
synced:OnSaveSync(nil, {
	gold = 300,
	level = 1,
	bench_slots = 0,
	owned_text = "npc_dota_hero_axe;npc_dota_hero_sven",
	lineup_text = "npc_dota_hero_sven",
	current_level = "ch01",
})
assertEqual(synced.gold, 300, "synced gold")
assertEqual(#synced.ownedHeroes, 2, "synced owned heroes")
assertEqual(synced.ownedHeroes[1], "npc_dota_hero_axe", "first synced owned hero")
assertEqual(#synced.lineup, 1, "synced lineup")
assertEqual(synced.lineup[1], "npc_dota_hero_sven", "first synced lineup hero")
assert(synced.rollShopCalled and synced.respawnCalled, "save sync did not refresh shop and roster")

local lineupGame = newGame({
	phase = "setup",
	ownedHeroes = { "npc_dota_hero_axe", "npc_dota_hero_sven" },
	lineup = {},
	shopCosts = { lineup_max = 5 },
	RespawnPlayerRoster = function(self)
		self.respawnCalled = true
	end,
	BroadcastShopState = function(self)
		self.broadcastCalled = true
	end,
})
lineupGame:OnLineupSet(nil, {
	lineup_text = "npc_dota_hero_sven;npc_dota_hero_unknown;npc_dota_hero_axe",
})
assertEqual(#lineupGame.lineup, 2, "validated lineup size")
assertEqual(lineupGame.lineup[1], "npc_dota_hero_sven", "validated first lineup hero")
assertEqual(lineupGame.lineup[2], "npc_dota_hero_axe", "validated second lineup hero")
assert(lineupGame.respawnCalled and lineupGame.broadcastCalled, "lineup update was not applied")

print("PASS: shop offers, initial gold, flat save sync, and lineup validation")
