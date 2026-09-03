local okEngine = pcall(require, "battle.tactic_engine")
local okBattle = pcall(require, "battle.battle_manager")
local okData = pcall(require, "data.data_loader")
print(string.format("[Dota2Rpg] requires: tactic_engine=%s battle_manager=%s data_loader=%s",
	tostring(okEngine), tostring(okBattle), tostring(okData)))

if CDota2RpgDemo == nil then
	_G.CDota2RpgDemo = class({})
end

local PLAYER_PLACEHOLDER_HERO = "npc_dota_hero_wisp"
local HERO_LEVEL = 30
local THINK_INTERVAL = 0.1

local TEAM_SPAWNS = {
	[DOTA_TEAM_GOODGUYS] = {
		Vector(-1100, -650, 128),
		Vector(-1350, 0, 128),
		Vector(-1100, 650, 128),
		Vector(-750, -850, 128),
		Vector(-750, 850, 128),
	},
	[DOTA_TEAM_BADGUYS] = {
		Vector(1100, 650, 128),
		Vector(1350, 0, 128),
		Vector(1100, -650, 128),
		Vector(750, 850, 128),
		Vector(750, -850, 128),
	},
}

local PRE_BATTLE_MODIFIERS = {
	"modifier_invulnerable",
	"modifier_rooted",
	"modifier_disarmed",
	"modifier_silence",
}

local ENEMY_SPAWN_SPACING = 220

-- 商店与阵容经济（需求：开局 300 金币，英雄 100/个，刷新 20/次，替补格 200/个）
local SHOP_HERO_COST = 100
local SHOP_REFRESH_COST = 20
local SHOP_BENCH_SLOT_COST = 200
local BENCH_SLOT_MAX = 5
local LINEUP_MAX = 5
local INITIAL_GOLD = 300
local SHOP_OFFER_SIZE = 5

-- 默认规则模板（条件 → 动作 → 目标选择器），玩家可套用后微调
local DEFAULT_RULES = {
	{ action = "ability_1", condition = "enemy_exists", value = 50, target = "enemy_nearest", forced = false, enabled = true },
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
			enabled = true,
		})
	end
	return rules
end

-- 规则槽数量 = 主动技能数 + 主动装备数 + 1 条普通攻击（DESIGN.md §2.2）
-- 被动技能不生成规则槽；A 杖/魔晶解锁的新技能、新买入的主动装备会自动增加槽位；
-- item_N 对应物品栏 N-1 的当前物品
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

	if hero.GetItemInSlot ~= nil then
		for slot = 0, 5 do
			local item = hero:GetItemInSlot(slot)
			if item ~= nil and not item:IsNull() and not item:IsHidden() and not item:IsPassive() then
				table.insert(actions, "item_" .. (slot + 1))
			end
		end
	end

	table.insert(actions, "attack")
	return actions
end

function Precache(context)
	PrecacheUnitByNameSync(PLAYER_PLACEHOLDER_HERO, context)
	-- 数据驱动：预缓存英雄池与所有关卡单位
	local sources = { "scripts/data/heroes.kv", "scripts/data/levels.kv" }
	for _, source in ipairs(sources) do
		local data = LoadKeyValues(source)
		if data ~= nil and data ~= "" then
			for _, entry in pairs(data) do
				if type(entry) == "table" then
					if entry.name ~= nil then
						PrecacheUnitByNameSync(entry.name, context)
					end
					local enemies = entry.enemies
					if enemies ~= nil then
						for _, enemy in pairs(enemies) do
							if type(enemy) == "table" and enemy.unit ~= nil then
								PrecacheUnitByNameSync(enemy.unit, context)
							end
						end
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
	self.currentLevelId = "ch01"
	self.battleManager = BattleManager(self)
	self.dataLoader = DataLoader()
	self.dataLoader:Init()
	self:LoadHeroPool()

	-- 有序关卡表（闯关制：胜利自动进入下一关）
	self.orderedLevels = {}
	local levelIds = {}
	for levelId in pairs(self.dataLoader:GetAllLevels()) do
		table.insert(levelIds, levelId)
	end
	table.sort(levelIds)
	self.orderedLevels = levelIds

	-- 经济/商店/阵容（服务端为金币权威，客户端存档仅镜像）
	self.gold = 300
	self.playerLevel = 1
	self.ownedHeroes = {}
	self.lineup = {}
	self.benchSlots = 0
	self.shopOffer = {}
	self.heroRulesByName = {}

	self.battleManager = BattleManager(self)

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
	GameRules:SetCustomGameSetupAutoLaunchDelay(0)
	if GameRules.SetCustomGameSetupEnabled ~= nil then
		-- 单人 PVE：跳过队伍/英雄选择界面，直接进入游戏
		GameRules:SetCustomGameSetupEnabled(false)
	end
	if GameRules.LockCustomGameSetupTeamAssignment ~= nil then
		GameRules:LockCustomGameSetupTeamAssignment(true)
	end
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
	CustomGameEventManager:RegisterListener("rpg_save_sync", function(eventSourceIndex, payload)
		return self:OnSaveSync(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_shop_refresh", function(eventSourceIndex, payload)
		return self:OnShopRefresh(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_shop_buy", function(eventSourceIndex, payload)
		return self:OnShopBuy(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_bench_buy", function(eventSourceIndex, payload)
		return self:OnBenchBuy(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_lineup_set", function(eventSourceIndex, payload)
		return self:OnLineupSet(eventSourceIndex, payload)
	end)

	PlayerResource:SetCustomTeamAssignment(0, DOTA_TEAM_GOODGUYS)
	self:RollShop()
	print("[Dota2Rpg] BUILD rpg-shop-lineup-v2 loaded. Setup disabled, shop enabled.")
	print("[Dota2Rpg] Shop + lineup + TacticEngine initialized.")
end

function CDota2RpgDemo:LoadHeroPool()
	local data = LoadKeyValues("scripts/data/heroes.kv")
	self.heroPool = { strength = {}, agility = {}, intelligence = {}, universal = {} }
	self.shopCosts = {
		hero = tonumber(data.hero_cost) or SHOP_HERO_COST,
		refresh = tonumber(data.refresh_cost) or SHOP_REFRESH_COST,
		bench_slot = tonumber(data.bench_slot_cost) or SHOP_BENCH_SLOT_COST,
		bench_slot_max = tonumber(data.bench_slot_max) or BENCH_SLOT_MAX,
		lineup_max = tonumber(data.lineup_max) or 5,
		initial_gold = tonumber(data.initial_gold) or 300,
	}
	if data ~= nil and data ~= "" then
		for _, category in ipairs({ "strength", "agility", "intelligence", "universal" }) do
			for _, hero in ipairs(data[category] or {}) do
				table.insert(self.heroPool[category], hero.name)
			end
		end
	end
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

	-- 玩家本体的英雄（无论选中谁）都隐藏并停靠到地图外；
	-- 战斗由商店购买的上阵英雄进行，玩家英雄不参战
	local ownerId = unit:GetPlayerOwnerID()
	if ownerId == nil or ownerId < 0 then
		return
	end
	if unit.rpgPlaceholderReady then
		return
	end

	unit.rpgPlaceholderReady = true
	if unit:GetUnitName() == PLAYER_PLACEHOLDER_HERO then
		self.placeholderHero = unit
	end
	self.playerId = math.max(self.playerId, ownerId)
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

------------------------------------------------------------------
-- 商店与阵容
------------------------------------------------------------------

function CDota2RpgDemo:RollShop()
	local offer = {}
	for _, category in ipairs({ "strength", "agility", "intelligence", "universal" }) do
		local pool = self.heroPool[category]
		if #pool > 0 then
			table.insert(offer, pool[math.random(#pool)].name)
		end
	end
	-- 第 5 个：全池随机（可与前 4 重复，重复则补抽）
	local allHeroes = {}
	for _, category in ipairs({ "strength", "agility", "intelligence", "universal" }) do
		for _, hero in ipairs(self.heroPool[category]) do
			table.insert(allHeroes, hero.name)
		end
	end
	for _ = 1, 8 do
		local candidate = allHeroes[math.random(#allHeroes)]
		local isDuplicate = false
		for _, owned in ipairs(offer) do
			if owned == candidate then
				isDuplicate = true
				break
			end
		end
		if not isDuplicate then
			table.insert(offer, candidate)
			break
		end
	end
	if #offer < SHOP_OFFER_SIZE then
		table.insert(offer, allHeroes[math.random(#allHeroes)])
	end
	self.shopOffer = offer
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnShopRefresh(_, payload)
	if self.phase ~= "setup" then
		return
	end
	if self.gold < self.shopCosts.refresh then
		return
	end
	self.gold = self.gold - self.shopCosts.refresh
	self:RollShop()
end

function CDota2RpgDemo:OnShopBuy(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local inOffer = false
	for _, offerName in ipairs(self.shopOffer) do
		if offerName == heroName then
			inOffer = true
			break
		end
	end
	if not inOffer then
		return
	end
	for _, owned in ipairs(self.ownedHeroes) do
		if owned == heroName then
			return -- 已拥有
		end
	end
	if self.gold < self.shopCosts.hero then
		return
	end
	if #self.ownedHeroes >= self.shopCosts.lineup_max + self.shopCosts.bench_slot_max then
		return -- 10 格上限
	end

	self.gold = self.gold - self.shopCosts.hero
	table.insert(self.ownedHeroes, heroName)
	if #self.lineup < self.shopCosts.lineup_max then
		table.insert(self.lineup, heroName)
		self.heroRulesByName[heroName] = self.heroRulesByName[heroName] or CloneDefaultRules()
	else
		-- 购满首发后自动进入替补；替补格子不足时买入失败
		local benchCount = #self.ownedHeroes - #self.lineup
		if benchCount > self.benchSlots then
			table.remove(self.ownedHeroes) -- 撤销购买
			self.gold = self.gold + self.shopCosts.hero
			return
		end
		self.heroRulesByName[heroName] = self.heroRulesByName[heroName] or CloneDefaultRules()
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnBenchBuy(_, payload)
	if self.phase ~= "setup" then
		return
	end
	if self.benchSlots >= self.shopCosts.bench_slot_max then
		return
	end
	if self.gold < self.shopCosts.bench_slot then
		return
	end
	self.gold = self.gold - self.shopCosts.bench_slot
	self.benchSlots = self.benchSlots + 1
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnLineupSet(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local lineup = {}
	local ownedSet = {}
	for _, owned in ipairs(self.ownedHeroes) do
		owned[owned] = true
	end
	for _, heroName in pairs((payload ~= nil and payload.lineup) or {}) do
		heroName = tostring(heroName)
		if owned[heroName] and #lineup < self.shopCosts.lineup_max then
			table.insert(lineup, heroName)
		end
	end
	if #lineup == 0 then
		return
	end
	self.lineup = lineup
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

-- 客户端存档同步（单人 MVP：信任客户端 LocalStorage，覆盖服务端状态）
function CDota2RpgDemo:OnSaveSync(_, payload)
	if self.phase ~= "setup" then
		return
	end
	if payload == nil then
		return
	end
	if payload.gold ~= nil then
		self.gold = math.max(0, math.floor(tonumber(payload.gold) or 0))
	end
	if payload.level ~= nil then
		self.playerLevel = math.max(1, math.min(HERO_LEVEL, math.floor(tonumber(payload.level) or 1)))
	end
	if payload.bench_slots ~= nil then
		self.benchSlots = math.max(0, math.min(self.shopCosts.bench_slot_max, math.floor(tonumber(payload.bench_slots) or 0)))
	end
	if payload.owned ~= nil then
		self.ownedHeroes = {}
		for _, heroName in pairs(payload.owned) do
			table.insert(self.ownedHeroes, tostring(heroName))
		end
	end
	if payload.lineup ~= nil then
		self.lineup = {}
		for _, heroName in pairs(payload.lineup) do
			table.insert(self.lineup, tostring(heroName))
		end
	end
	if payload.current_level ~= nil then
		local levelId = tostring(payload.current_level)
		if self.dataLoader:GetLevel(levelId) ~= nil then
			self.currentLevelId = levelId
			if self.teamsSpawned then
				self:SpawnLevelEnemies(levelId)
			end
		end
	end
	self:RollShop()
	self:RespawnPlayerRoster()
end

function CDota2RpgDemo:OnHeroLevels(_, payload)
	if payload == nil or payload.level == nil then
		return
	end
	self.playerLevel = math.max(1, math.min(HERO_LEVEL, math.floor(tonumber(payload.level) or 1)))
	if self.phase == "setup" and self.teamsSpawned then
		self:RespawnPlayerRoster()
	end
end

------------------------------------------------------------------
-- 战场生成
------------------------------------------------------------------


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
	self:SpawnLevelEnemies(self.currentLevelId)
	self:RespawnPlayerRoster()

	self:BroadcastShopState()
	self:BroadcastLevelInfo()
	self:BroadcastBattleState()
	print("[Dota2Rpg] Battlefield ready for level " .. self.currentLevelId .. ".")
end

-- 玩家阵容：按 lineup 顺序在己方出生点生成，统一等级 self.playerLevel
function CDota2RpgDemo:RespawnPlayerRoster()
	if self.phase ~= "setup" then
		return
	end
	local battleManager = self.battleManager
	for _, hero in ipairs(battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]) do
		if TacticEngine.IsValidUnit(hero) then
			battleManager.heroStates[hero:GetEntityIndex()] = nil
			hero:RemoveSelf()
		end
	end
	battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] = {}
	battleManager.teamRules[DOTA_TEAM_GOODGUYS] = {}

	for index, heroName in ipairs(self.lineup) do
		if index > #TEAM_SPAWNS[DOTA_TEAM_GOODGUYS] then
			break
		end
		local spawnPosition = GetGroundPosition(TEAM_SPAWNS[DOTA_TEAM_GOODGUYS][index], nil)
		local hero = CreateUnitByName(heroName, spawnPosition, true, nil, nil, DOTA_TEAM_GOODGUYS)
		if TacticEngine.IsValidUnit(hero) then
			FindClearSpaceForUnit(hero, spawnPosition, true)
			self:PrepareBattleHero(hero, self.playerLevel)
			battleManager:RegisterHero(DOTA_TEAM_GOODGUYS, index, hero)
			self.heroRulesByName[heroName] = self.heroRulesByName[heroName] or CloneDefaultRules()
			battleManager.teamRules[DOTA_TEAM_GOODGUYS][index] = self.heroRulesByName[heroName]
		else
			print(string.format("[Dota2Rpg] Failed to spawn lineup hero %s.", heroName))
		end
	end
	self:BroadcastHeroInfo()
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
			enabled = true,
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
		abilityLevel = nil
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
	self:BroadcastShopState()
	self:BroadcastLevelInfo()
	self:BroadcastHeroInfo()
end

function CDota2RpgDemo:OnSelectLevel(_, payload)
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

------------------------------------------------------------------
-- 战斗流程
------------------------------------------------------------------

function CDota2RpgDemo:OnStartBattle(_, payload)
	if self.phase ~= "setup" or not self.teamsSpawned then
		return
	end
	if #self.lineup == 0 then
		return -- 必须先购买英雄并上阵
	end

	local battlePayload = payload or {}
	for heroIndex, heroName in ipairs(self.lineup) do
		local heroPrefix = string.format("radiant_hero_%d", heroIndex)
		local ruleCount = tonumber(battlePayload[heroPrefix .. "_count"]) or RULE_COUNT
		ruleCount = math.max(1, math.min(RULE_COUNT, math.floor(ruleCount + 0.5)))
		local existing = self.heroRulesByName[heroName] or CloneDefaultRules()
		self.heroRulesByName[heroName] = TacticEngine:ParseRules(battlePayload, heroPrefix, ruleCount, existing)
		self.battleManager.teamRules[DOTA_TEAM_GOODGUYS][heroIndex] = self.heroRulesByName[heroName]
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

	-- 时间奖励：越快越多（clearTime 越短 → bonus 越大）
	local clearTime = self.battleManager:GetBattleTime()
	local level = self.dataLoader:GetLevel(self.currentLevelId)
	local timeLimit = tonumber(level ~= nil and level.time_limit or 120) or 120
	local timeRate = tonumber(level ~= nil and level.time_bonus_rate or 0) or 0
	local timeBonus = math.floor(math.max(0, timeLimit - self.battleManager:GetBattleTime()) * timeRate + 0.5)

	self.phase = "result"
	self.winner = winner
	self.battleManager:StopBattle()
	self:BroadcastBattleState()

	local settlement = {
		level = self.currentLevelId,
		winner = winner,
		first_gold = 0,
		repeat_gold = 0,
		first_xp = 0,
		repeat_xp = 0,
		time_bonus = winner == "radiant" and timeBonus or 0,
		clear_time = math.floor(self.battleManager:GetBattleTime()),
		items = {},
	}
	if winner == "radiant" and level ~= nil then
		local firstReward = level.first_reward or {}
		local repeatReward = level.repeat_reward or {}
		settlement.first_gold = tonumber(firstReward.gold) or 0
		settlement.repeat_gold = tonumber(repeatReward ~= nil and repeatReward.gold or 0) or 0
		settlement.first_xp = tonumber(firstReward.xp or 0) or 0
		settlement.repeat_xp = tonumber(repeatReward ~= nil and repeatReward.xp or 0) or 0
		settlement.items = firstReward.items or {}
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_settlement", settlement)

	-- 闯关推进：胜利后指向下一关
	if winner == "radiant" then
		for index, levelId in ipairs(self.orderedLevels) do
			if levelId == self.currentLevelId and self.orderedLevels[index + 1] ~= nil then
				self.currentLevelId = self.orderedLevels[index + 1]
				break
			end
		end
	end

	if winnerTeam ~= nil then
		GameRules:GetGameModeEntity():SetContextThink("Dota2RpgDeclareWinner", function()
			GameRules:SetGameWinner(winnerTeam)
			return nil
		end, 1.0)
	end
	print(string.format("[Dota2Rpg] Battle finished. Result=%s ClearTime=%.0f TimeBonus=%d",
		winner, self.battleManager:GetBattleTime(), timeBonus))
end

------------------------------------------------------------------
-- 状态广播
------------------------------------------------------------------

-- 每个英雄的可用动作槽（含主动装备）同步给前端
function CDota2RpgDemo:BroadcastHeroInfo()
	local info = {}
	local heroes = self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]
	for index, hero in ipairs(heroes) do
		if TacticEngine.IsValidUnit(hero) then
			info["radiant_" .. index] = {
				name = self.lineup[index] or "",
				actions_text = table.concat(BuildHeroActionSlots(hero), ";"),
			}
		end
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_hero_slots", { slots = info })
end

function CDota2RpgDemo:BroadcastShopState()
	-- CEM 载荷不传输 Lua 数组（数字键会被丢弃），一律用分隔符字符串
	CustomGameEventManager:Send_ServerToAllClients("rpg_shop_state", {
		gold = self.gold,
		player_level = self.playerLevel,
		offer_text = table.concat(self.shopOffer, ";"),
		owned_text = table.concat(self.ownedHeroes, ";"),
		lineup_text = table.concat(self.lineup, ";"),
		bench_slots = self.benchSlots,
		costs = {
			hero = self.shopCosts.hero,
			refresh = self.shopCosts.refresh,
			bench_slot = self.shopCosts.bench_slot,
			bench_slot_max = self.shopCosts.bench_slot_max,
			lineup_max = self.shopCosts.lineup_max,
		},
	})
end

function CDota2RpgDemo:BroadcastLevelInfo()
	local list = {}
	for _, levelId in ipairs(self.orderedLevels) do
		local level = self.dataLoader:GetLevel(levelId)
		table.insert(list, {
			id = levelId,
			name = (level ~= nil and level.name) or levelId,
			type = (level ~= nil and level.type) or "creep",
			recommended_level = (level ~= nil and level.recommended_level) or 1,
		})
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_levels_state", {
		level_ids = table.concat(self.orderedLevels, ";"),
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
		time_limit = tonumber(self.dataLoader:GetLevel(self.currentLevelId) ~= nil and self.dataLoader:GetLevel(self.currentLevelId).time_limit or 120) or 120,
		level = self.currentLevelId,
		gold = self.gold,
		player_level = self.playerLevel,
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