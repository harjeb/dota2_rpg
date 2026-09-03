require("battle.tactic_engine")
require("battle.battle_manager")
require("data.data_loader")

if CDota2RpgDemo == nil then
	_G.CDota2RpgDemo = class({})
end

local PLAYER_PLACEHOLDER_HERO = "npc_dota_hero_wisp"
local HERO_LEVEL = 30
local THINK_INTERVAL = 0.1

local TEAM_ROSTERS = {
	[DOTA_TEAM_GOODGUYS] = {
		"npc_dota_hero_sven",
		"npc_dota_hero_lina",
		"npc_dota_hero_dazzle",
	},
	[DOTA_TEAM_BADGUYS] = {
		"npc_dota_hero_axe",
		"npc_dota_hero_lion",
		"npc_dota_hero_crystal_maiden",
	},
}

local TEAM_SPAWNS = {
	[DOTA_TEAM_GOODGUYS] = {
		Vector(-1100, -650, 128),
		Vector(-1350, 0, 128),
		Vector(-1100, 650, 128),
	},
	[DOTA_TEAM_BADGUYS] = {
		Vector(1100, 650, 128),
		Vector(1350, 0, 128),
		Vector(1100, -650, 128),
	},
}

local PRE_BATTLE_MODIFIERS = {
	"modifier_invulnerable",
	"modifier_rooted",
	"modifier_disarmed",
	"modifier_silence",
}

-- 默认规则模板（条件 → 动作 → 目标选择器），玩家可一键套用后微调
local DEFAULT_RULES = {
	{ action = "ability_1", condition = "enemy_exists", value = 50, target = "enemy_nearest", forced = false },
	{ action = "ability_2", condition = "enemy_exists", value = 50, target = "enemy_hp_pct_lowest", forced = false },
	{ action = "ability_3", condition = "self_hp_below", value = 50, target = "self", forced = false },
	{ action = "ultimate", condition = "enemy_count_ge", value = 2, target = "enemy_hp_pct_lowest", forced = true },
	{ action = "attack", condition = "always", value = 50, target = "enemy_nearest", forced = false },
}

local RULE_COUNT = #DEFAULT_RULES

local function CloneDefaultRules()
	local rules = {}
	for _, rule in ipairs(DEFAULT_RULES) do
		table.insert(rules, {
			action = rule.action,
			condition = rule.condition,
			value = rule.value,
			target = rule.target,
			forced = rule.forced,
		})
	end
	return rules
end

function Precache(context)
	PrecacheUnitByNameSync(PLAYER_PLACEHOLDER_HERO, context)
	for _, roster in pairs(TEAM_ROSTERS) do
		for _, heroName in ipairs(roster) do
			PrecacheUnitByNameSync(heroName, context)
		end
	end
end

function Activate()
	GameRules.Dota2RpgDemo = CDota2RpgDemo()
	GameRules.Dota2RpgDemo:InitGameMode()
end

function CDota2RpgDemo:InitGameMode()
	local gameMode = GameRules:GetGameModeEntity()

	self.playerId = -1
	self.placeholderHero = nil
	self.phase = "setup"
	self.winner = ""
	self.teamsSpawned = false
	self.battleManager = BattleManager(self)
	self.dataLoader = DataLoader()
	self.dataLoader:Init()

	self.heroRules = {}
	for team, roster in pairs(TEAM_ROSTERS) do
		self.heroRules[team] = {}
		for heroIndex = 1, #roster do
			self.heroRules[team][heroIndex] = CloneDefaultRules()
		end
	end

	gameMode:SetCustomGameForceHero(PLAYER_PLACEHOLDER_HERO)
	gameMode:SetBuybackEnabled(false)
	gameMode:SetDaynightCycleDisabled(true)
	gameMode:SetFogOfWarDisabled(true)
	gameMode:SetUnseenFogOfWarEnabled(false)
	gameMode:SetCameraDistanceOverride(1500)
	gameMode:SetExecuteOrderFilter(Dynamic_Wrap(CDota2RpgDemo, "FilterExecuteOrder"), self)
	gameMode:SetContextThink("Dota2RpgDemoThink", function()
		return self:OnThink()
	end, THINK_INTERVAL)

	GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 1)
	GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
	GameRules:SetCustomGameSetupTimeout(0)
	GameRules:SetHeroSelectionTime(0)
	GameRules:SetStrategyTime(0)
	GameRules:SetShowcaseTime(0)
	GameRules:SetPreGameTime(0)
	GameRules:SetPostGameTime(8)
	GameRules:SetStartingGold(0)
	GameRules:SetUseUniversalShopMode(true)
	if GameRules.SetHeroRespawnEnabled ~= nil then
		GameRules:SetHeroRespawnEnabled(false)
	end

	ListenToGameEvent("player_connect_full", Dynamic_Wrap(CDota2RpgDemo, "OnPlayerConnectFull"), self)
	ListenToGameEvent("npc_spawned", Dynamic_Wrap(CDota2RpgDemo, "OnNpcSpawned"), self)
	ListenToGameEvent("game_rules_state_change", Dynamic_Wrap(CDota2RpgDemo, "OnGameRulesStateChange"), self)
	ListenToGameEvent("entity_killed", Dynamic_Wrap(CDota2RpgDemo, "OnEntityKilled"), self)

	CustomGameEventManager:RegisterListener("rpg_start_battle", function(eventSourceIndex, payload)
		return self:OnStartBattle(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_request_battle_state", function(eventSourceIndex, payload)
		return self:OnRequestBattleState(eventSourceIndex, payload)
	end)

	PlayerResource:SetCustomTeamAssignment(0, DOTA_TEAM_GOODGUYS)
	print("[Dota2Rpg] TacticEngine + BattleManager initialized.")
end

function CDota2RpgDemo:ResolvePlayerId(payload)
	if payload ~= nil then
		local playerId = tonumber(payload.PlayerID)
		if playerId ~= nil and playerId >= 0 then
			return playerId
		end

		local playerIndex = tonumber(payload.index)
		if playerIndex ~= nil then
			local player = EntIndexToHScript(playerIndex)
			if player ~= nil and player.GetPlayerID ~= nil then
				return player:GetPlayerID()
			end
		end
	end

	return self.playerId >= 0 and self.playerId or 0
end

function CDota2RpgDemo:OnPlayerConnectFull(event)
	local playerId = self:ResolvePlayerId(event)
	self.playerId = playerId
	PlayerResource:SetCustomTeamAssignment(playerId, DOTA_TEAM_GOODGUYS)
	self:ScheduleStateBroadcast(0.5)
end

function CDota2RpgDemo:OnNpcSpawned(event)
	local unit = EntIndexToHScript(event.entindex or -1)
	if not TacticEngine.IsValidUnit(unit) or not unit:IsRealHero() then
		return
	end

	if unit:GetUnitName() ~= PLAYER_PLACEHOLDER_HERO or unit.rpgPlaceholderReady then
		return
	end

	unit.rpgPlaceholderReady = true
	self.placeholderHero = unit
	self.playerId = math.max(self.playerId, unit:GetPlayerOwnerID())
	unit:SetRespawnsDisabled(true)
	unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
	unit:AddNewModifier(unit, nil, "modifier_rooted", {})
	unit:AddNewModifier(unit, nil, "modifier_disarmed", {})
	unit:AddNewModifier(unit, nil, "modifier_silence", {})
	if unit.AddNoDraw ~= nil then
		unit:AddNoDraw()
	end
	FindClearSpaceForUnit(unit, Vector(-7600, -7600, 128), true)
	self:EnsureBattlefield()
	print(string.format("[Dota2Rpg] Hidden placeholder ready for player %d.", self.playerId))
end

function CDota2RpgDemo:OnGameRulesStateChange()
	local state = GameRules:State_Get()
	if state == DOTA_GAMERULES_STATE_PRE_GAME or state == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		self:EnsureBattlefield()
	end
end

function CDota2RpgDemo:EnsureBattlefield()
	if self.teamsSpawned then
		return
	end

	self.teamsSpawned = true
	for team, roster in pairs(TEAM_ROSTERS) do
		for index, heroName in ipairs(roster) do
			local spawnPosition = GetGroundPosition(TEAM_SPAWNS[team][index], nil)
			local hero = CreateUnitByName(heroName, spawnPosition, true, nil, nil, team)
			if TacticEngine.IsValidUnit(hero) then
				FindClearSpaceForUnit(hero, spawnPosition, true)
				self:PrepareBattleHero(hero)
				self.battleManager:RegisterHero(team, index, hero)
			else
				print(string.format("[Dota2Rpg] Failed to spawn %s.", heroName))
			end
		end
	end

	local cameraTarget = self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS][2]
		or self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS][1]
	if self.playerId >= 0 and TacticEngine.IsValidUnit(cameraTarget) then
		PlayerResource:SetCameraTarget(self.playerId, cameraTarget)
		GameRules:GetGameModeEntity():SetContextThink("ReleaseRpgBattleCamera", function()
			PlayerResource:SetCameraTarget(self.playerId, nil)
			return nil
		end, 0.5)
	end

	self:BroadcastBattleState()
	print("[Dota2Rpg] Spawned three level-30 heroes for each team.")
end

function CDota2RpgDemo:PrepareBattleHero(hero)
	while hero:GetLevel() < HERO_LEVEL do
		hero:HeroLevelUp(false)
	end

	for slot = 0, hero:GetAbilityCount() - 1 do
		local ability = hero:GetAbilityByIndex(slot)
		if ability ~= nil and not ability:IsNull() then
			local abilityName = ability:GetAbilityName()
			local isTalent = string.find(abilityName, "special_bonus", 1, true) ~= nil
			if not isTalent and ability:GetMaxLevel() > 0 then
				ability:SetLevel(ability:GetMaxLevel())
			end
		end
	end

	hero:SetAbilityPoints(0)
	hero:SetRespawnsDisabled(true)
	hero:SetHealth(hero:GetMaxHealth())
	hero:SetMana(hero:GetMaxMana())
	hero:SetIdleAcquire(false)
	hero:SetAcquisitionRange(0)

	for _, modifierName in ipairs(PRE_BATTLE_MODIFIERS) do
		hero:AddNewModifier(hero, nil, modifierName, {})
	end
end

function CDota2RpgDemo:FilterExecuteOrder(filterTable)
	local issuerPlayerId = tonumber(filterTable.issuer_player_id_const) or -1
	if issuerPlayerId >= 0 then
		return false
	end
	return true
end

function CDota2RpgDemo:OnRequestBattleState(eventSourceIndex, payload)
	local playerId = self:ResolvePlayerId(payload)
	local player = PlayerResource:GetPlayer(playerId)
	if player ~= nil then
		CustomGameEventManager:Send_ServerToPlayer(player, "rpg_battle_state", self:BuildBattleState())
	end
end

function CDota2RpgDemo:OnStartBattle(eventSourceIndex, payload)
	if self.phase ~= "setup" or not self.teamsSpawned then
		return
	end

	local battlePayload = payload or {}
	for team, roster in pairs(TEAM_ROSTERS) do
		local teamPrefix = team == DOTA_TEAM_GOODGUYS and "radiant" or "dire"
		for heroIndex = 1, #roster do
			local heroPrefix = string.format("%s_hero_%d", teamPrefix, heroIndex)
			self.heroRules[team][heroIndex] = TacticEngine:ParseRules(
				battlePayload, heroPrefix, RULE_COUNT, self.heroRules[team][heroIndex]
			)
		end
	end
	self.phase = "fight"

	for _, heroes in pairs(self.battleManager.teamHeroes) do
		for _, hero in ipairs(heroes) do
			if TacticEngine.IsValidUnit(hero) and hero:IsAlive() then
				for _, modifierName in ipairs(PRE_BATTLE_MODIFIERS) do
					hero:RemoveModifierByName(modifierName)
				end
				hero:SetHealth(hero:GetMaxHealth())
				hero:SetMana(hero:GetMaxMana())
				hero:SetIdleAcquire(true)
				hero:SetAcquisitionRange(2400)
			end
		end
	end

	self.battleManager:StartBattle(self.heroRules)
	self:BroadcastBattleState()
	print("[Dota2Rpg] Battle started with player-configured rules.")
end

function CDota2RpgDemo:OnEntityKilled(event)
	if self.phase ~= "fight" then
		return
	end

	local killed = EntIndexToHScript(event.entindex_killed or -1)
	if not TacticEngine.IsValidUnit(killed) then
		return
	end

	if self.battleManager.heroStates[killed:GetEntityIndex()] ~= nil then
		self:ScheduleStateBroadcast(0.05)
	end
end

function CDota2RpgDemo:OnThink()
	if not self.teamsSpawned then
		local state = GameRules:State_Get()
		if state >= DOTA_GAMERULES_STATE_PRE_GAME then
			self:EnsureBattlefield()
		end
	end

	if self.phase == "fight" then
		self.battleManager:OnThink()
	end

	return THINK_INTERVAL
end

function CDota2RpgDemo:EndBattle(winner, winnerTeam)
	if self.phase ~= "fight" then
		return
	end

	self.phase = "result"
	self.winner = winner
	self.battleManager:StopBattle()
	self:BroadcastBattleState()

	if winnerTeam ~= nil then
		GameRules:GetGameModeEntity():SetContextThink("Dota2RpgDeclareWinner", function()
			GameRules:SetGameWinner(winnerTeam)
			return nil
		end, 1.0)
	end
	print(string.format("[Dota2Rpg] Battle finished. Result=%s", winner))
end

function CDota2RpgDemo:BuildBattleState()
	return {
		phase = self.phase,
		ready = self.teamsSpawned and 1 or 0,
		radiant_alive = self.battleManager:GetAliveCount(DOTA_TEAM_GOODGUYS),
		dire_alive = self.battleManager:GetAliveCount(DOTA_TEAM_BADGUYS),
		winner = self.winner,
		battle_time = math.floor(self.battleManager:GetBattleTime()),
		time_limit = 120,
	}
end

function CDota2RpgDemo:BroadcastBattleState()
	CustomGameEventManager:Send_ServerToAllClients("rpg_battle_state", self:BuildBattleState())
end

function CDota2RpgDemo:ScheduleStateBroadcast(delay)
	GameRules:GetGameModeEntity():SetContextThink(DoUniqueString("Dota2RpgState"), function()
		self:BroadcastBattleState()
		return nil
	end, delay or 0)
end