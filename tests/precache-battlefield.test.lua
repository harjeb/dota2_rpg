local repoRoot = TEST_REPO_ROOT or "."

function class()
	local result = {}
	result.__index = result
	return result
end

local vectorMeta = {}
vectorMeta.__add = function(left, right)
	return setmetatable({ x = left.x + right.x, y = left.y + right.y, z = left.z + right.z }, vectorMeta)
end

function Vector(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, vectorMeta)
end

DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3

require = function()
	error("Dota modules are not needed by the precache/battlefield test")
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
}

local enemyEntries = {}
for index = 1, 5 do
	enemyEntries[tostring(index)] = {
		unit = index == 1 and "npc_dota_hero_axe" or "npc_dota_neutral_kobold",
		count = "1",
		level = "1",
		ai = "simple_nearest",
	}
end

local levelData = {
	ch01 = {
		name = "Level display name must not be precached",
		enemies = enemyEntries,
	},
}

function LoadKeyValues(path)
	if path == "scripts/data/heroes.kv" then
		return heroData
	end
	if path == "scripts/data/levels.kv" then
		return levelData
	end
	error("unexpected data path: " .. tostring(path))
end

local precached = {}
local precacheContext = {}
function PrecacheUnitByNameSync(unitName, context)
	assert(context == precacheContext, "precache context was not forwarded")
	precached[unitName] = (precached[unitName] or 0) + 1
end

local addonPath = repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua"
local loaded, loadError = pcall(dofile, addonPath)
assert(loaded, "failed to load addon_game_mode.lua: " .. tostring(loadError))

Precache(precacheContext)

local expectedUnits = {
	"npc_dota_hero_wisp",
	"npc_dota_hero_axe",
	"npc_dota_hero_sven",
	"npc_dota_hero_juggernaut",
	"npc_dota_hero_sniper",
	"npc_dota_hero_lina",
	"npc_dota_hero_lion",
	"npc_dota_hero_marci",
	"npc_dota_hero_muerta",
	"npc_dota_neutral_kobold",
}
for _, unitName in ipairs(expectedUnits) do
	assert(precached[unitName] == 1, unitName .. " must be precached exactly once")
end
assert(precached["Level display name must not be precached"] == nil, "level labels are not unit names")

TacticEngine = {
	IsValidUnit = function(unit)
		return unit ~= nil and unit.valid ~= false
	end,
	ParseRules = function(_, _, _, _, fallbackRules)
		return fallbackRules
	end,
}

local nextEntityIndex = 100
local spawned = {}
local function newUnit(unitName, position, team)
	nextEntityIndex = nextEntityIndex + 1
	local unit = {
		name = unitName,
		position = position,
		team = team,
		entityIndex = nextEntityIndex,
	}
	function unit:GetEntityIndex() return self.entityIndex end
	function unit:IsRealHero() return false end
	function unit:IsAlive() return true end
	function unit:IsNull() return false end
	function unit:RemoveModifierByName() end
	function unit:GetMaxHealth() return 1000 end
	function unit:GetMaxMana() return 500 end
	function unit:SetHealth(value) self.health = value end
	function unit:SetMana(value) self.mana = value end
	function unit:SetIdleAcquire(value) self.idleAcquire = value end
	function unit:SetAcquisitionRange(value) self.acquisitionRange = value end
	table.insert(spawned, unit)
	return unit
end

function GetGroundPosition(position)
	return position
end

function CreateUnitByName(unitName, position, _, _, _, team)
	return newUnit(unitName, position, team)
end

function FindClearSpaceForUnit() end

local function newBattleManager()
	local manager = {
		teamHeroes = {
			[DOTA_TEAM_GOODGUYS] = {},
			[DOTA_TEAM_BADGUYS] = {},
		},
		teamRules = {
			[DOTA_TEAM_GOODGUYS] = {},
			[DOTA_TEAM_BADGUYS] = {},
		},
		heroStates = {},
	}
	function manager:RegisterHero(team, _, unit)
		table.insert(self.teamHeroes[team], unit)
	end
	function manager:StartBattle()
		self.started = true
	end
	return manager
end

local spawnGame = setmetatable({
	phase = "setup",
	lineup = {
		"npc_dota_hero_axe",
		"npc_dota_hero_sven",
		"npc_dota_hero_juggernaut",
		"npc_dota_hero_sniper",
		"npc_dota_hero_lina",
	},
	playerLevel = 30,
	heroRulesByName = {},
	battleManager = newBattleManager(),
	dataLoader = {
		GetLevel = function()
			return levelData.ch01
		end,
	},
}, CDota2RpgDemo)
spawnGame.PrepareBattleHero = function() end
spawnGame.PrepareEnemyCreep = function() end
spawnGame.BuildEnemyRules = function() return {} end
spawnGame.BroadcastHeroInfo = function() end
spawnGame:RespawnPlayerRoster()
spawnGame:SpawnLevelEnemies("ch01")

local teamCounts = { [DOTA_TEAM_GOODGUYS] = 0, [DOTA_TEAM_BADGUYS] = 0 }
for _, unit in ipairs(spawned) do
	teamCounts[unit.team] = teamCounts[unit.team] + 1
	assert(math.abs(unit.position.x) <= 800, "battlefield x spawn must stay within 800 units of center")
	assert(math.abs(unit.position.y) <= 700, "battlefield y spawn must stay within 700 units of center")
end
assert(teamCounts[DOTA_TEAM_GOODGUYS] == 5, "five friendly spawn slots must be available")
assert(teamCounts[DOTA_TEAM_BADGUYS] == 5, "five enemy spawn slots must be available")

local radiant = newUnit("npc_dota_hero_axe", Vector(-650, 0, 128), DOTA_TEAM_GOODGUYS)
local dire = newUnit("npc_dota_hero_lion", Vector(650, 0, 128), DOTA_TEAM_BADGUYS)
local fightGame = setmetatable({
	phase = "setup",
	teamsSpawned = true,
	lineup = { "npc_dota_hero_axe" },
	heroRulesByName = { npc_dota_hero_axe = { { action = "attack" } } },
	battleManager = newBattleManager(),
	currentLevelId = "ch01",
}, CDota2RpgDemo)
fightGame.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] = { radiant }
fightGame.battleManager.teamHeroes[DOTA_TEAM_BADGUYS] = { dire }
fightGame.BroadcastBattleState = function() end
fightGame:OnStartBattle(nil, { radiant_hero_1_count = 1 })

assert(fightGame.battleManager.started, "battle manager must start")
assert(radiant.idleAcquire and dire.idleAcquire, "both teams must enable idle acquisition")
assert(radiant.acquisitionRange == 4000 and dire.acquisitionRange == 4000,
	"both teams must use the expanded 4000-unit acquisition range")

print("PASS: categorized unit precache, close team spawns, and expanded battle acquisition range")
