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
function IsServer() return true end

require = function(moduleName)
	if moduleName == "tactics/ability_catalog" or moduleName == "tactics/rule_snapshot"
		or moduleName == "tactics/ability_behavior" then
		return dofile(repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/" .. moduleName .. ".lua")
	end
	if moduleName == "issue_fixes.hero_lifecycle_log" then
		return dofile(repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/hero_lifecycle_log.lua")
	end
	if moduleName == "issue_fixes.default_rules" then
		return dofile(repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/default_rules.lua")
	end
	if moduleName == "patches.enemy_items_patch" then
		return dofile(repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/patches/enemy_items_patch.lua")
	end
	if moduleName == "battle.damage_stats" then
		return dofile(repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/battle/damage_stats.lua")
	end
	if moduleName == "battle.enemy_scaling" or moduleName == "battle.boss_scaling" or moduleName == "battle.run_lives"
        or moduleName == "battle/summon_behavior" or moduleName == "issue_fixes/tiny_tree"
        or moduleName == "issue_fixes/item_sales"
        or moduleName == "issue_fixes/hero_precache" or moduleName == "tactics/special_targets"
        or moduleName == "battle.enemy_diagnostics" or moduleName == "battle.respawn_policy"
        or moduleName == "battle.item_cooldowns"
        or moduleName == "issue_fixes.runtime_log"
        or moduleName == "battle.tempest_double" or moduleName == "issue_fixes/hero_ability_policy" then
		return dofile(repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/" .. moduleName:gsub("%.", "/") .. ".lua")
	end
	-- Keep the independent debug event installer out of this focused spawn fixture.
	if moduleName == "issue_fixes.bootstrap" or moduleName == "battle.skill_debug" then
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
	"npc_dota_neutral_kobold",
}
for _, unitName in ipairs(expectedUnits) do
	assert(precached[unitName] == 1, unitName .. " must be precached exactly once")
end
assert(precached.npc_dota_hero_sven == nil and precached.npc_dota_hero_lion == nil,
    "shop-only heroes load asynchronously on purchase, not all at startup")
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
		modifiers = {},
	}
	function unit:GetEntityIndex() return self.entityIndex end
	function unit:entindex() return self.entityIndex end
	function unit:GetTeamNumber() return self.team end
	function unit:GetUnitName() return self.name end
	function unit:IsRealHero() return false end
	function unit:IsAlive() return true end
	function unit:IsNull() return false end
	function unit:RemoveModifierByName(name) self.modifiers[name] = nil end
	function unit:GetMaxHealth() return 1000 end
	function unit:GetMaxMana() return 500 end
	function unit:SetHealth(value) self.health = value end
	function unit:SetMana(value) self.mana = value end
	function unit:SetIdleAcquire(value) self.idleAcquire = value end
	function unit:SetAcquisitionRange(value) self.acquisitionRange = value end
	function unit:SetAbilityPoints(value) self.abilityPoints = value end
	function unit:GetAbilityPoints() return self.abilityPoints or 1 end
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
		for _, heroes in pairs(self.teamHeroes) do
			for _, hero in ipairs(heroes) do
				assert(not hero.modifiers.modifier_rpg_prepare_bench,
					"fielded preparation restriction must be removed before battle manager starts")
			end
		end
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
	assert(math.abs(unit.position.y) <= 675, "battlefield y spawn must stay inside expanded boundary")
	if unit.team == DOTA_TEAM_GOODGUYS then
		assert(unit.position.x <= -150, "friendly spawn must stay in the left preparation zone")
	else
		assert(unit.position.x >= 150, "enemy spawn must stay in the right preparation zone")
	end
end
assert(teamCounts[DOTA_TEAM_GOODGUYS] == 5, "five friendly spawn slots must be available")
assert(teamCounts[DOTA_TEAM_BADGUYS] == 5, "five enemy spawn slots must be available")

-- Dead neutral entities disappear while still present in the round's roster.
-- Looking up any hero's rules must not call GetUnitName on those stale handles;
-- surviving duplicates must retain the same per-instance rule identity.
local Snapshot = require("tactics/rule_snapshot")
local enemyKeys, duplicates = {}, {}
for _, enemy in ipairs(spawnGame.battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
	local key = Snapshot.HeroKey(spawnGame.battleManager, enemy)
	assert(enemy.ruleSnapshotKey == key and not enemyKeys[key], "spawn assigns unique stable enemy keys")
	enemyKeys[key] = true
	if enemy:GetUnitName() == "npc_dota_neutral_kobold" then duplicates[#duplicates+1] = enemy end
end
local removed, survivor = duplicates[1], duplicates[2]
local survivorKey = Snapshot.HeroKey(spawnGame.battleManager, survivor)
local originalName, originalNull = removed.GetUnitName, removed.IsNull
removed.GetUnitName = function() error("Invalid object passed to GetUnitName") end
removed.IsNull = function() return true end
assert(Snapshot.HeroKey(spawnGame.battleManager, spawned[1]) == spawned[1].name,
	"a removed enemy must not interrupt friendly rule evaluation")
assert(Snapshot.HeroKey(spawnGame.battleManager, survivor) == survivorKey,
	"a removed duplicate must not shift surviving enemy rules")
assert(Snapshot.HeroKey(spawnGame.battleManager, removed) == nil)
assert(#Snapshot.ForHero(spawnGame.battleManager, removed) == 0)
local legacy = newUnit("npc_dota_hero_legacy", Vector(0, 0, 128), DOTA_TEAM_GOODGUYS)
assert(Snapshot.HeroKey(spawnGame.battleManager, legacy) == "npc_dota_hero_legacy",
	"legacy unkeyed heroes also ignore stale enemies")
removed.GetUnitName, removed.IsNull = originalName, originalNull

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
assert(placementOrder.position_x == -150 and placementOrder.position_y == 611,
	"placement must clamp to the compact preparation boundary")
assert(spawnGame.placedPositions[spawned[1]:GetUnitName()].x == -150,
	"clamped placement must be persisted")
placementOrder.position_x = -9999
placementOrder.position_y = -9999
assert(spawnGame:ValidatePrepareOrder(placementOrder), "far placement order must be accepted and clamped")
assert(placementOrder.position_x == -1136 and placementOrder.position_y == -611,
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
radiant.modifiers.modifier_rpg_prepare_bench = true
local bench = newUnit("npc_dota_hero_sven", Vector(-2300, 0, 128), DOTA_TEAM_GOODGUYS)
bench.modifiers.modifier_rpg_prepare_bench = true
fightGame.selectedHero = bench
fightGame.BroadcastBattleState = function() end
GameRules = { GetGameTime = function() return 0 end }
local damagePacket
CustomGameEventManager = { Send_ServerToAllClients = function(_, event, data)
	if event == "rpg_damage_stats" then damagePacket = data end
end }
fightGame:OnStartBattle(nil, { radiant_hero_1_count = 1 })
assert(damagePacket and #damagePacket.units == 2 and damagePacket.elapsed == 0,
	"battle start publishes both real combatants with zero damage")
fightGame.battleManager.RecordDamage = function() end
EntIndexToHScript = function(id)
	if id == radiant:entindex() then return radiant end
	if id == dire:entindex() then return dire end
end
GameRules.GetGameTime = function() return 2 end
fightGame:OnEntityHurt({entindex_attacker=radiant:entindex(), entindex_killed=dire:entindex(), damage=120})
fightGame:BroadcastDamageStats()
assert(damagePacket.elapsed == 2 and damagePacket.units[1].total == 120 and damagePacket.units[1].dps == 60,
	"real event adapter publishes post-mitigation damage and elapsed DPS")
assert(bench.modifiers.modifier_rpg_prepare_bench, "selected bench hero remains restricted")

assert(fightGame.battleManager.started, "battle manager must start")
assert(radiant.idleAcquire and dire.idleAcquire, "both teams must enable idle acquisition")
assert(radiant.acquisitionRange == 4000 and dire.acquisitionRange == 4000,
	"both teams must use the expanded 4000-unit acquisition range")

print("PASS: categorized unit precache, compact team spawns, and expanded battle acquisition range")

-- Exercise the actual spawn -> auto-level -> equipment -> BossScaling path.
-- Only the native unit API is simulated; no stub replaces the Boss module.
local bossCases = {
	{ chapter = "ch10", hero = "centaur", level = 14, items = 3, hp = 6, attack = 100, spell = 100, cdr = 25 },
	{ chapter = "ch20", hero = "spirit_breaker", level = 24, items = 3, hp = 10, attack = 200, spell = 150, cdr = 40 },
	{ chapter = "ch30", hero = "skeleton_king", level = 30, items = 5, hp = 16, attack = 300, spell = 200, cdr = 50 },
}
local activeBossCase
function CreateUnitByName(unitName, position, _, _, _, team)
	local unit = newUnit(unitName, position, team)
	unit.level, unit.itemCount = 1, 0
	function unit:IsRealHero() return true end
	function unit:IsIllusion() return false end
	function unit:GetLevel() return self.level end
	function unit:HeroLevelUp() self.level = self.level + 1 end
	function unit:SetRespawnsDisabled(value) self.respawnsDisabled = value end
	function unit:CalculateStatBonus() self.statRecalculations = (self.statRecalculations or 0) + 1 end
	function unit:GetMaxHealth()
		local power = self.modifiers.modifier_rpg_boss_power
		return 1000 + self.level * 10 + self.itemCount * 100 + (power and power:GetModifierHealthBonus() or 0)
	end
	function unit:AddItemByName()
		self.itemCount = self.itemCount + 1
		return { IsNull = function() return false end }
	end
	function unit:FindModifierByName(name) return self.modifiers[name] end
	function unit:AddNewModifier(_, _, name, params)
		if name == "modifier_rpg_boss_power" then
			assert(self.level == activeBossCase.level and self.itemCount == activeBossCase.items,
				"Boss power must be applied after native levels and all configured items")
		end
		local modifier = { params = params }
		function modifier:GetModifierHealthBonus() return tonumber(self.params.health_bonus) or 0 end
		function modifier:IsNull() return false end
		self.modifiers[name] = modifier
		return modifier
	end
	return unit
end
spawnGame.PrepareBattleHero = CDota2RpgDemo.PrepareBattleHero
local BossScaling = require("battle.boss_scaling")
for _, case in ipairs(bossCases) do
	activeBossCase = case
	local equipment = {}
	for index = 1, case.items do equipment[tostring(index)] = "item_bracer" end
	local bossEntry = {
		unit = "npc_dota_hero_" .. case.hero, level = tostring(case.level), items = equipment,
		tags = { ["1"] = "boss" }, ai = "aggro_front",
		boss_health_multiplier = tostring(case.hp), boss_attack_damage_pct = tostring(case.attack),
		boss_spell_amp_pct = tostring(case.spell), boss_cooldown_reduction_pct = tostring(case.cdr),
	}
	local ordinaryEntry = { unit = "npc_dota_hero_lina", level = tostring(case.level),
		items = equipment, tags = { ["1"] = "hero" }, ai = "focus_lowest_hp" }
	spawnGame.dataLoader.GetLevel = function() return { enemies = { bossEntry, ordinaryEntry } } end
	spawnGame:SpawnLevelEnemies(case.chapter)
	local boss, ordinary
	for _, unit in pairs(spawnGame.battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
		if unit.name == bossEntry.unit then boss = unit else ordinary = unit end
	end
	local baseline = 1000 + case.level * 10 + case.items * 100
	assert(boss and ordinary and boss.enemyRuleIndex and ordinary.enemyRuleIndex)
	assert(boss:GetMaxHealth() == baseline * case.hp and boss.health == boss:GetMaxHealth(),
		"real spawn must create a full-health boss scaled from the equipped hero")
	assert(ordinary:GetMaxHealth() == baseline and ordinary.modifiers.modifier_rpg_boss_power == nil,
		"ordinary enemies in the same stage must retain normal stats")
	spawnGame:PrepareEnemyHero(boss, case.level)
	BossScaling.Apply(boss, bossEntry)
	assert(boss:GetMaxHealth() == baseline * case.hp and boss.health == boss:GetMaxHealth(),
		"repreparing/reapplying cannot compound boss health")
end
print("PASS: all three Boss tiers reach actual spawn/level/equipment/rule registration with full HP and no compounding")

-- Exercise the actual npc_spawned routing: a real-hero native double must not
-- reach commander hiding, ownership reassignment or roster preparation.
local copy = {
    IsNull=function() return false end,
    IsTempestDouble=function() return true end,
    IsRealHero=function() error("double reached commander routing") end,
    SetIdleAcquire=function(self,value) self.acquire=value end,
    SetAcquisitionRange=function(self,value) self.range=value end,
}
local oldResolve = EntIndexToHScript
EntIndexToHScript = function(index) assert(index==901); return copy end
local summonGame=setmetatable({phase="fight"},CDota2RpgDemo)
summonGame:OnNpcSpawned({entindex=901})
assert(copy.acquire and copy.range==4000 and summonGame.tempestDoubles[copy])
EntIndexToHScript = oldResolve
print("PASS: native Tempest Double spawn bypasses commander routing and acquires attacks")

for _, spec in ipairs({{"morphling", "morphling_replicate", "morphling_waveform"},
    {"largo", "largo_amphibian_rhapsody", "largo_frogstomp"}}) do
    for _, location in ipairs({"benchHeroName", "lineupHeroName"}) do
        local hero=CreateUnitByName("npc_dota_hero_"..spec[1],Vector(0,0,0),false,nil,nil,DOTA_TEAM_GOODGUYS)
        hero[location]=hero.name
        local abilities={}
        for _, name in ipairs({spec[2],spec[3]}) do
            abilities[#abilities+1]={IsNull=function() return false end,GetAbilityName=function() return name end}
        end
        function hero:GetAbilityCount() return #abilities end
        function hero:GetAbilityByIndex(index) return abilities[index+1] end
        function hero:FindAbilityByName(name)
            for _, ability in ipairs(abilities) do if ability:GetAbilityName()==name then return ability end end
        end
        function hero:RemoveAbility(name)
            for i=#abilities,1,-1 do if abilities[i]:GetAbilityName()==name then table.remove(abilities,i) end end
        end
        local prepareGame=setmetatable({autoAbilityHeroes={},heroData={},CaptureHeroAbilities=function(_,unit)
            assert(not unit:FindAbilityByName(spec[2]) and unit:FindAbilityByName(spec[3]),
                "removed ultimate cannot enter stored levels or rule catalogs")
        end},CDota2RpgDemo)
        prepareGame:PrepareBattleHero(hero,1)
        assert(hero.abilityPoints==1 and hero:FindAbilityByName(spec[3]), "manual basic skill points remain available")
    end
end
print("PASS: bench and lineup preparation remove disabled ultimates before ability capture")
