require("battle.tactic_engine")
require("battle.battle_manager")
require("data.data_loader")

if CDota2RpgDemo == nil then
	_G.CDota2RpgDemo = class({})
end

local PLAYER_PLACEHOLDER_HERO = "npc_dota_hero_wisp"
local HERO_LEVEL = 30
local THINK_INTERVAL = 0.1

-- 玩家小队（MVP 固定 3 人）；敌方阵容完全由 levels.json 数据驱动
local PLAYER_ROSTER = {
	"npc_dota_hero_sven",
	"npc_dota_hero_lina",
	"npc_dota_hero_dazzle",
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

local ENEMY_SPAWN_SPACING = 220

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

-- 规则槽数量 = 主动技能数 + 主动装备数 + 1 条普通攻击（DESIGN.md §2.2）
-- 被动技能不生成规则槽；ability_1..3 对应技能栏 0..2，大招单独成槽
local function BuildHeroActionSlots(hero)
	local actions = {}
	for slot = 0, hero:GetAbilityCount() - 1 do
		local ability = hero:GetAbilityByIndex(slot)
		if ability ~= nil and not ability:IsNull() then
			local abilityName = ability:GetAbilityName()
			local isTalent = string.find(abilityName, "special_bonus", 1, true) ~= nil
			if not isTalent and not ability:IsHidden() and not ability:IsPassive() and ability:GetMaxLevel() > 0 then
				if ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
					table.insert(actions, "ultimate")
				elseif slot <= 2 then
					table.insert(actions, "ability_" .. (slot + 1))
				end
			end
		end
	end
	table.insert(actions, "attack")
	return actions
end

function Precache(context)
	PrecacheUnitByNameSync(PLAYER_PLACEHOLDER_HERO, context)
	for _, heroName in ipairs(PLAYER_ROSTER) do
		PrecacheUnitByNameSync(heroName, context)
	end
	-- 数据驱动：预缓存所有关卡用到的单位
	local levels = LoadKeyValues("scripts/data/levels.json")
	if levels ~= nil and levels ~= "" then
		for _, level in pairs(levels) do
			local enemies = type(level) == "table" and level.enemies or nil
			if enemies ~= nil then
				for _, entry in pairs(enemies) do
					if type(entry) == "table" and entry.unit ~= nil then
						PrecacheUnitByNameSync(entry.unit, context)
					end
				end
			end
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
	self.currentLevelId = "demo_3v3"
	self.battleManager = BattleManager(self)
	self.dataLoader = DataLoader()
	self.dataLoader:Init()

	self.heroRules = {
		[DOTA_TEAM_GOODGUYS] = {},
	}
	-- 玩家英雄等级由存档驱动（经验全队共享，DESIGN.md §2.1），默认 5 级
	self.playerLevels = { 5, 5, 5 }
	for heroIndex = 1, #PLAYER_ROSTER do
		self.heroRules[DOTA_TEAM_GOODGUYS][heroIndex] = CloneDefaultRules()
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
	CustomGameEventManager:RegisterListener("rpg_select_level", function(eventSourceIndex, payload)
		return self:OnSelectLevel(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_hero_levels", function(eventSourceIndex, payload)
		return self:OnHeroLevels(eventSourceIndex, payload)
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
	for index, heroName in ipairs(PLAYER_ROSTER) do
		local spawnPosition = GetGroundPosition(TEAM_SPAWNS[DOTA_TEAM_GOODGUYS][index], nil)
		local hero = CreateUnitByName(heroName, spawnPosition, true, nil, nil, DOTA_TEAM_GOODGUYS)
		if TacticEngine.IsValidUnit(hero) then
			FindClearSpaceForUnit(hero, spawnPosition, true)
			self:PrepareBattleHero(hero, self.playerLevels[index] or 1)
			self.battleManager:RegisterHero(DOTA_TEAM_GOODGUYS, index, hero)
			self.battleManager.teamRules[DOTA_TEAM_GOODGUYS][index] = self.heroRules[DOTA_TEAM_GOODGUYS][index]
		else
			print(string.format("[Dota2Rpg] Failed to spawn %s.", heroName))
		end
	end

	self:SpawnLevelEnemies(self.currentLevelId)

	local cameraTarget = self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS][2]
		or self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS][1]
	if self.playerId >= 0 and TacticEngine.IsValidUnit(cameraTarget) then
		PlayerResource:SetCameraTarget(self.playerId, cameraTarget)
		GameRules:GetGameModeEntity():SetContextThink("ReleaseRpgBattleCamera", function()
			PlayerResource:SetCameraTarget(self.playerId, nil)
			return nil
		end, 0.5)
	end

	self:BroadcastHeroInfo()
	self:BroadcastLevelInfo()
	self:BroadcastBattleState()
	print("[Dota2Rpg] Player roster spawned; enemies loaded for level " .. self.currentLevelId .. ".")
end

-- 从 levels.json 生成关卡敌方阵容（英雄/野怪混编，随关卡切换重建）
function CDota2RpgDemo:SpawnLevelEnemies(levelId)
	local battleManager = self.battleManager
	for _, unit in ipairs(battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
		if TacticEngine.IsValidUnit(unit) then
			unit:RemoveSelf()
		end
	end
	battleManager.teamHeroes[DOTA_TEAM_BADGUYS] = {}
	battleManager.teamRules[DOTA_TEAM_BADGUYS] = {}

	local level = self.dataLoader:GetLevel(levelId)
	if level == nil then
		print("[Dota2Rpg] WARNING: level '" .. tostring(levelId) .. "' not found in levels.json.")
		return
	end

	local enemyIndex = 0
	local spawnCount = #TEAM_SPAWNS[DOTA_TEAM_BADGUYS]
	for _, entry in pairs(level.enemies or {}) do
		local count = tonumber(entry.count) or 1
		for copyIndex = 1, count do
			enemyIndex = enemyIndex + 1
			local slot = ((enemyIndex - 1) % spawnCount) + 1
			local offset = Vector((copyIndex - 1) * ENEMY_SPAWN_SPACING - (count - 1) * ENEMY_SPAWN_SPACING / 2, 0, 0)
			local spawnPosition = GetGroundPosition(TEAM_SPAWNS[DOTA_TEAM_BADGUYS][slot] + offset, nil)
			local unit = CreateUnitByName(entry.unit, spawnPosition, true, nil, nil, DOTA_TEAM_BADGUYS)
			if TacticEngine.IsValidUnit(unit) then
				FindClearSpaceForUnit(unit, spawnPosition, true)
				if unit:IsRealHero() then
					self:PrepareEnemyHero(unit, tonumber(entry.level) or 1)
				else
					self:PrepareEnemyCreep(unit)
				end
				battleManager:RegisterHero(DOTA_TEAM_BADGUYS, enemyIndex, unit)
				battleManager.teamRules[DOTA_TEAM_BADGUYS][enemyIndex] = self:BuildEnemyRules(entry.ai)
			else
				print(string.format("[Dota2Rpg] Failed to spawn enemy %s.", tostring(entry.unit)))
			end
		end
	end
	print(string.format("[Dota2Rpg] Level '%s' spawned %d enemy units.", levelId, enemyIndex))
end

function CDota2RpgDemo:PrepareEnemyHero(hero, level)
	self:PrepareBattleHero(hero, level)
end

function CDota2RpgDemo:PrepareEnemyCreep(unit)
	unit:SetIdleAcquire(false)
	unit:SetAcquisitionRange(0)
end

-- 敌人 AI：行为模式库预设 → 内部规则格式（与玩家同一引擎）
function CDota2RpgDemo:BuildEnemyRules(aiId)
	local preset = self.dataLoader:GetEnemyAI(aiId)
	if preset == nil then
		preset = self.dataLoader:GetEnemyAI("demo_default")
	end
	local rules = {}
	for _, presetRule in ipairs(preset.rules or {}) do
		local cond = presetRule.cond or {}
		table.insert(rules, {
			action = (presetRule.action and presetRule.action.type) or "attack",
			condition = cond.type or "always",
			value = tonumber(cond.value) or 50,
			target = presetRule.target or "enemy_nearest",
			forced = presetRule.mode == "forced_chase",
		})
	end
	if #rules == 0 then
		rules = CloneDefaultRules()
	end
	return rules
end

function CDota2RpgDemo:PrepareBattleHero(hero, targetLevel)
	local wantedLevel = tonumber(targetLevel) or HERO_LEVEL
	while hero:GetLevel() < wantedLevel do
		hero:HeroLevelUp(false)
	end

	-- 技能加点：满级英雄直接拉满；低级敌方英雄按等级比例加点
	local abilityLevel
	if wantedLevel >= HERO_LEVEL then
		abilityLevel = nil -- 拉满
	else
		abilityLevel = math.max(1, math.floor(wantedLevel / 2))
	end
	for slot = 0, hero:GetAbilityCount() - 1 do
		local ability = hero:GetAbilityByIndex(slot)
		if ability ~= nil and not ability:IsNull() then
			local abilityName = ability:GetAbilityName()
			local isTalent = string.find(abilityName, "special_bonus", 1, true) ~= nil
			if not isTalent and ability:GetMaxLevel() > 0 then
				ability:SetLevel(abilityLevel == nil and ability:GetMaxLevel() or math.min(ability:GetMaxLevel(), abilityLevel))
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

function CDota2RpgDemo:OnSelectLevel(eventSourceIndex, payload)
	if self.phase ~= "setup" or not self.teamsSpawned then
		return
	end

	local levelId = payload ~= nil and tostring(payload.level or "") or ""
	if self.dataLoader:GetLevel(levelId) == nil then
		return
	end

	self.currentLevelId = levelId
	self:SpawnLevelEnemies(levelId)
	self:BroadcastLevelInfo()
	self:BroadcastBattleState()
end

-- 经验全队共享：前端持久化英雄等级，战斗前同步给服务端用于生成玩家英雄
function CDota2RpgDemo:OnHeroLevels(eventSourceIndex, payload)
	if payload == nil or payload.levels == nil then
		return
	end
	for index = 1, #PLAYER_ROSTER do
		local level = tonumber(payload.levels[index]) or tonumber(payload.levels[tostring(index)]) or 1
		self.playerLevels[index] = math.max(1, math.min(HERO_LEVEL, math.floor(level + 0.5)))
	end

	-- 准备阶段可即时按新等级重铸玩家英雄（保留当前规则）
	if self.phase == "setup" and self.teamsSpawned then
		self:RespawnPlayerRoster()
	end
end

function CDota2RpgDemo:RespawnPlayerRoster()
	local battleManager = self.battleManager
	for _, hero in ipairs(battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]) do
		if TacticEngine.IsValidUnit(hero) then
			battleManager.heroStates[hero:GetEntityIndex()] = nil
			hero:RemoveSelf()
		end
	end
	for index, heroName in ipairs(PLAYER_ROSTER) do
		local spawnPosition = GetGroundPosition(TEAM_SPAWNS[DOTA_TEAM_GOODGUYS][index], nil)
		local hero = CreateUnitByName(heroName, spawnPosition, true, nil, nil, DOTA_TEAM_GOODGUYS)
		if TacticEngine.IsValidUnit(hero) then
			FindClearSpaceForUnit(hero, spawnPosition, true)
			self:PrepareBattleHero(hero, self.playerLevels[index] or 1)
			battleManager:RegisterHero(DOTA_TEAM_GOODGUYS, index, hero)
			battleManager.teamRules[DOTA_TEAM_GOODGUYS][index] = self.heroRules[DOTA_TEAM_GOODGUYS][index]
		end
	end
	self:BroadcastHeroInfo()
end

function CDota2RpgDemo:OnStartBattle(eventSourceIndex, payload)
	if self.phase ~= "setup" or not self.teamsSpawned then
		return
	end

	local battlePayload = payload or {}
	for heroIndex = 1, #PLAYER_ROSTER do
		local heroPrefix = string.format("radiant_hero_%d", heroIndex)
		-- 槽数由前端按英雄可用动作上报；缺失时退回默认模板槽数
		local ruleCount = tonumber(battlePayload[heroPrefix .. "_count"]) or RULE_COUNT
		ruleCount = math.max(1, math.min(RULE_COUNT, math.floor(ruleCount + 0.5)))
		self.heroRules[DOTA_TEAM_GOODGUYS][heroIndex] = TacticEngine:ParseRules(
			battlePayload, heroPrefix, ruleCount, self.heroRules[DOTA_TEAM_GOODGUYS][heroIndex]
		)
		self.battleManager.teamRules[DOTA_TEAM_GOODGUYS][heroIndex] = self.heroRules[DOTA_TEAM_GOODGUYS][heroIndex]
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

	self.battleManager:StartBattle(self.battleManager.teamRules)
	self:BroadcastBattleState()
	print("[Dota2Rpg] Battle started on level " .. self.currentLevelId .. ".")
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

	-- 结算：胜利发放关卡奖励（数据驱动）。首通/重复奖励都下发，
	-- 由前端按存档的首通记录决定实际入账（金币+经验）。
	local settlement = {
		level = self.currentLevelId,
		winner = winner,
		first_gold = 0,
		repeat_gold = 0,
		first_xp = 0,
		repeat_xp = 0,
		items = {},
	}
	if winner == "radiant" then
		local level = self.dataLoader:GetLevel(self.currentLevelId)
		local firstReward = level ~= nil and level.first_reward or nil
		local repeatReward = level ~= nil and level.repeat_reward or nil
		settlement.first_gold = tonumber(firstReward ~= nil and firstReward.gold or 0) or 0
		settlement.repeat_gold = tonumber(repeatReward ~= nil and repeatReward.gold or 0) or 0
		settlement.first_xp = tonumber(firstReward ~= nil and firstReward.xp or 0) or 0
		settlement.repeat_xp = tonumber(repeatReward ~= nil and repeatReward.xp or 0) or 0
		settlement.items = (firstReward ~= nil and firstReward.items) or {}
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_settlement", settlement)

	if winnerTeam ~= nil then
		GameRules:GetGameModeEntity():SetContextThink("Dota2RpgDeclareWinner", function()
			GameRules:SetGameWinner(winnerTeam)
			return nil
		end, 1.0)
	end
	print(string.format("[Dota2Rpg] Battle finished. Result=%s FirstGold=%d", winner, settlement.first_gold))
end

-- 把英雄可用动作槽同步给前端，编辑器据此动态生成规则行
function CDota2RpgDemo:BroadcastHeroInfo()
	local info = {}
	for team, heroes in pairs(self.battleManager.teamHeroes) do
		local teamPrefix = team == DOTA_TEAM_GOODGUYS and "radiant" or "dire"
		for index, hero in ipairs(heroes) do
			if TacticEngine.IsValidUnit(hero) then
				info[teamPrefix .. "_" .. index] = {
					actions = BuildHeroActionSlots(hero),
				}
			end
		end
	end
	CustomNetTables:SetTableValue("rpg_rules_config", "heroes", info)
end

function CDota2RpgDemo:BroadcastLevelInfo()
	local list = {}
	for levelId, level in pairs(self.dataLoader:GetAllLevels()) do
		table.insert(list, {
			id = levelId,
			name = level.name or levelId,
			type = level.type or "creep",
			recommended_level = level.recommended_level or 1,
		})
	end
	CustomNetTables:SetTableValue("rpg_rules_config", "levels", {
		levels = list,
		current = self.currentLevelId,
	})
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
		level = self.currentLevelId,
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