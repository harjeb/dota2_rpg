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

require = function(moduleName)
	-- The production entry point installs the issue-fix bootstrap at EOF.  This
	-- focused test exercises precache/spawn geometry, so only stub that module.
	if moduleName == "issue_fixes.bootstrap" then
		return { Install = function() end }
	end
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

local precachedItems = {}
function PrecacheItemByNameSync(itemName, context)
	assert(context == precacheContext, "item precache context was not forwarded")
	precachedItems[itemName] = (precachedItems[itemName] or 0) + 1
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
assert(precachedItems.item_rpg_scroll_low == 1 and precachedItems.item_rpg_scroll_high == 1,
	"the two project scroll items must be precached exactly once")

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
	function unit:GetUnitName() return self.name end
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
	function unit:SetAbilityPoints(value) self.abilityPoints = value end
	function unit:GetAbilityCount() return 0 end
	function unit:AddNewModifier() end
	function unit:RemoveSelf() self.removed = true end
	function unit:SetOwner(owner) self.owner = owner end
	function unit:GetPlayerOwnerID() return self.controlledByPlayer or -1 end
	function unit:SetControllableByPlayer(playerId, value)
		self.controlledByPlayer = value and playerId or nil
	end
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
	function manager:RegisterEnemyTags() end
	function manager:ResetBattleStats() self.reset = true end
	function manager:StartBattle()
		self.started = true
	end
	return manager
end

local commander = {
	GetPlayerOwnerID = function() return 0 end,
	IsNull = function() return false end,
}
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
	playerId = 0,
	placeholderHero = commander,
	heroData = {},
	heroOrder = 0,
	placedPositions = {},
	heroRulesByName = {},
	battleManager = newBattleManager(),
	dataLoader = {
		GetLevel = function()
			return levelData.ch01
		end,
	},
}, CDota2RpgDemo)
spawnGame.PrepareBattleHero = function() end
spawnGame.SpawnBenchEnclosure = function() end
spawnGame.SpawnBenchHeroes = function() end
spawnGame.PrepareEnemyCreep = function() end
spawnGame.BuildEnemyRules = function() return {} end
spawnGame.BroadcastHeroInfo = function() end
spawnGame:RespawnPlayerRoster()
for index = 1, 5 do
	assert(spawned[index].controlledByPlayer == 0,
		"each fielded hero must be controllable in preparation for movement/pickup")
end
spawnGame:SpawnLevelEnemies("ch01")

local teamCounts = { [DOTA_TEAM_GOODGUYS] = 0, [DOTA_TEAM_BADGUYS] = 0 }
for _, unit in ipairs(spawned) do
	teamCounts[unit.team] = teamCounts[unit.team] + 1
	assert(math.abs(unit.position.x) <= 1200, "battlefield x spawn must stay inside compact boundary")
	assert(math.abs(unit.position.y) <= 450, "battlefield y spawn must stay inside compact boundary")
	if unit.team == DOTA_TEAM_GOODGUYS then
		assert(unit.position.x <= -150, "friendly spawn must stay in the left preparation zone")
	else
		assert(unit.position.x >= 150, "enemy spawn must stay in the right preparation zone")
	end
end
assert(teamCounts[DOTA_TEAM_GOODGUYS] == 5, "five friendly spawn slots must be available")
assert(teamCounts[DOTA_TEAM_BADGUYS] == 5, "five enemy spawn slots must be available")

-- Player placement must be clamped to the compact left preparation zone before
-- the position is persisted for roster respawns.
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
function EntIndexToHScript(index)
	for _, unit in ipairs(spawned) do
		if unit.entityIndex == index then return unit end
	end
	return nil
end
local placementOrder = {
	issuer_player_id_const = 0,
	order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
	units = { ["0"] = spawned[1]:GetEntityIndex() },
	position_x = 9999,
	position_y = 9999,
}
assert(spawnGame:ValidatePrepareOrder(placementOrder), "fielded placement order must be accepted")
assert(placementOrder.position_x == -150 and placementOrder.position_y == 386,
	"placement must clamp to the compact preparation boundary")
assert(spawnGame.placedPositions[spawned[1]:GetUnitName()].x == -150,
	"clamped placement must be persisted")
placementOrder.position_x = -9999
placementOrder.position_y = -9999
assert(spawnGame:ValidatePrepareOrder(placementOrder), "far placement order must be accepted and clamped")
assert(placementOrder.position_x == -1136 and placementOrder.position_y == -386,
	"placement must clamp to the compact outer boundary")

local radiant = newUnit("npc_dota_hero_axe", Vector(-650, 0, 128), DOTA_TEAM_GOODGUYS)
local dire = newUnit("npc_dota_hero_lion", Vector(650, 0, 128), DOTA_TEAM_BADGUYS)
local fightGame = setmetatable({
	phase = "setup",
	teamsSpawned = true,
	lineup = { "npc_dota_hero_axe" },
	heroRulesByName = { npc_dota_hero_axe = { { action = "attack" } } },
	battleManager = newBattleManager(),
	tacticBridge = { ResetState = function() end },
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

print("PASS: categorized unit precache, compact team spawns, and expanded battle acquisition range")
