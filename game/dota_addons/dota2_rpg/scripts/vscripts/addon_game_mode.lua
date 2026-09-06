local okHelpers = pcall(require, "battle.tactic_engine") -- 仅用其 IsValidUnit 等 helper（引擎评估已由修订版模块接管）
local okItems = pcall(require, "items") -- item_lua 经验卷轴的 OnSpellStart
local okBridge = pcall(require, "tactics.tactic_bridge")
local okBattle = pcall(require, "battle.battle_manager")
local okData = pcall(require, "data.data_loader")
print(string.format("[Dota2Rpg] requires: helpers=%s items=%s tactic_bridge=%s battle_manager=%s data_loader=%s",
	tostring(okHelpers), tostring(okItems), tostring(okBridge), tostring(okBattle), tostring(okData)))

if CDota2RpgDemo == nil then
	_G.CDota2RpgDemo = class({})
end

local PLAYER_PLACEHOLDER_HERO = "npc_dota_hero_wisp"
local HERO_LEVEL = 30
local THINK_INTERVAL = 0.1
local BATTLE_ACQUISITION_RANGE = 4000

local TEAM_SPAWNS = {
	[DOTA_TEAM_GOODGUYS] = {
		Vector(-650, -420, 128),
		Vector(-800, 0, 128),
		Vector(-650, 420, 128),
		Vector(-500, -700, 128),
		Vector(-500, 700, 128),
	},
	[DOTA_TEAM_BADGUYS] = {
		Vector(650, 420, 128),
		Vector(800, 0, 128),
		Vector(650, -420, 128),
		Vector(500, 700, 128),
		Vector(500, -700, 128),
	},
}

local PRE_BATTLE_MODIFIERS = {
	"modifier_invulnerable",
	"modifier_rooted",
	"modifier_disarmed",
	"modifier_silence",
}

local ENEMY_SPAWN_SPACING = 220

-- 待命区：围起来的地形，场下英雄在此可视化展示（右键点击可换上场）
local BENCH_AREA_CENTER = Vector(-2300, 0, 128)
local BENCH_AREA_HALF_W = 520
local BENCH_AREA_HALF_H = 380
local BENCH_TREE_SPACING = 140
local BENCH_TREE_DURATION = 999999
local BENCH_GRID_COLS = 3
local BENCH_GRID_SPACING = 260

-- 战场隔断：一排能量屏障单位分隔双方，开战瞬间移除
local BARRIER_X = 0
local BARRIER_HALF_SPAN = 1500
local BARRIER_SPACING = 150

-- 招募体系（DESIGN.md §2.1）：等级概率/品质锚点/价格倍率
RECRUIT_BASE_PRICE = { ["1"] = 100, ["5"] = 300, ["10"] = 500, ["15"] = 800, ["20"] = 1500, ["30"] = 3000 }
RECRUIT_LEVEL_RULES = {
	{ from_stage = 1,  to_stage = 4,  weights = { ["1"] = 100 } },
	{ from_stage = 5,  to_stage = 9,  weights = { ["5"] = 100 } },
	{ from_stage = 10, to_stage = 14, weights = { ["10"] = 100 } },
	{ from_stage = 15, to_stage = 19, weights = { ["10"] = 90, ["15"] = 10 } },
	{ from_stage = 20, to_stage = 30, weights = { ["10"] = 79, ["15"] = 10, ["20"] = 10, ["30"] = 1 } },
}
QUALITY_PRICE_MULTIPLIER = { common = 1.0, fine = 1.2, epic = 1.5, legendary = 2.0 }
QUALITY_ANCHORS = {
	{ stage = 1,  weights = { common = 970, fine = 30,  epic = 0,   legendary = 0 } },
	{ stage = 5,  weights = { common = 940, fine = 55,  epic = 5,   legendary = 0 } },
	{ stage = 10, weights = { common = 890, fine = 90,  epic = 18,  legendary = 2 } },
	{ stage = 15, weights = { common = 820, fine = 130, epic = 45,  legendary = 5 } },
	{ stage = 20, weights = { common = 740, fine = 170, epic = 80,  legendary = 10 } },
	{ stage = 25, weights = { common = 650, fine = 220, epic = 115, legendary = 15 } },
	{ stage = 30, weights = { common = 580, fine = 250, epic = 150, legendary = 20 } },
}
QUALITY_CONSUMED_MODIFIERS = {
	fine = { "modifier_item_aghanims_shard_consumed" },
	epic = { "modifier_item_ultimate_scepter_consumed" },
	legendary = { "modifier_item_aghanims_shard_consumed", "modifier_item_ultimate_scepter_consumed" },
}
REFRESH_BASE = 20
REFRESH_STEP = 20
REFRESH_MAX = 200
-- 经验卷轴（DESIGN.md §2.5）：每关各限购 3 个
SCROLL_COST = { low = 100, high = 1000 }
SCROLL_XP = { low = 500, high = 2000 }
SCROLL_LIMIT_PER_STAGE = 3
-- 个人升级公式（客户端保持一致）
-- 升级曲线见 AddXpToHero 内 XP_TO_LEVEL 表（v1.0：30 级总需求 33700）
TIME_BONUS_CAP = 0.25

-- 商店与阵容经济（需求：开局 300 金币，英雄 100/个，刷新 20/次，替补格 200/个）
local SHOP_HERO_COST = 100
local SHOP_REFRESH_COST = 20
local SHOP_BENCH_SLOT_COST = 200
local BENCH_SLOT_MAX = 5
local LINEUP_MAX = 5
local INITIAL_GOLD = 500

-- 经验卷轴物品（真物品 KV 见 scripts/npc/npc_items_custom.txt）
SCROLL_ITEM_COST = {
	item_rpg_scroll_low = 100,
	item_rpg_scroll_high = 1000,
}
local SHOP_OFFER_SIZE = 5
local SHOP_CATEGORIES = { "strength", "agility", "intelligence", "universal" }

local function ReadPayloadList(payload, textKey, legacyKey)
	if payload == nil then
		return nil
	end
	if payload[textKey] ~= nil then
		local values = {}
		for value in string.gmatch(tostring(payload[textKey]), "([^;]+)") do
			table.insert(values, value)
		end
		return values
	end
	if type(payload[legacyKey]) == "table" then
		local values = {}
		for _, value in pairs(payload[legacyKey]) do
			table.insert(values, tostring(value))
		end
		return values
	end
	return nil
end

-- 默认规则模板（条件 → 动作 → 目标选择器），玩家可套用后微调
local DEFAULT_RULES = {
	{ action = "ability_1", condition = "enemy_exists", value = 50, target = "enemy_distance_nearest", forced = false, enabled = true },
	{ action = "ability_2", condition = "enemy_exists", value = 50, target = "enemy_hp_pct_lowest", forced = false },
	{ action = "ability_3", condition = "self_hp_below", value = 50, target = "self", forced = false },
	{ action = "ultimate", condition = "enemy_count_ge", value = 2, target = "enemy_hp_pct_lowest", forced = true },
	{ action = "attack", condition = "always", value = 50, target = "enemy_distance_nearest", forced = true },
}

local RULE_COUNT = 10  -- 固定 10 条规则槽 + 系统兜底（修订版设计）

-- 按英雄动作列表生成 10 条默认规则：动作循环分配，普攻强制追击
local function BuildDefaultRulesForSlots(actions)
	local rules = {}
	for index = 1, RULE_COUNT do
		local action = actions[((index - 1) % #actions) + 1]
		table.insert(rules, {
			action = action,
			condition = action == "attack" and "always" or "enemy_exists",
			value = 50,
			target = action == "attack" and "enemy_distance_nearest" or "enemy_hp_pct_lowest",
			forced = (action == "attack"),
			enabled = true,
		})
	end
	return rules
end

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
			-- 未学技能（level 0）在 Dota 中 IsHidden 为 true，必须保留槽位以显示图标
			if not isTalent and not ability:IsPassive() and ability:GetMaxLevel() > 0 then
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
	local seenUnits = {}
	local function PrecacheUnit(unitName)
		if type(unitName) ~= "string" or string.sub(unitName, 1, 9) ~= "npc_dota_" or seenUnits[unitName] then
			return
		end
		seenUnits[unitName] = true
		PrecacheUnitByNameSync(unitName, context)
	end

	PrecacheUnit(PLAYER_PLACEHOLDER_HERO)
	-- 经验卷轴（自定义物品）
	PrecacheItemByNameSync("item_rpg_scroll_low", context)
	PrecacheItemByNameSync("item_rpg_scroll_high", context)

	-- 只预缓存可招募子集（全量 112 个同步预缓存会导致加载崩溃）
	local heroData = LoadKeyValues("scripts/data/heroes.kv")
	if type(heroData) == "table" then
		local pool = heroData.recruitable ~= nil and heroData.recruitable or heroData
		for _, categoryName in ipairs(SHOP_CATEGORIES) do
			for _, heroEntry in pairs(pool[categoryName] or {}) do
				-- 与 LoadHeroPool 一致：兼容纯字符串目录和 { name = ... } 数据项。
				local heroName = type(heroEntry) == "string" and heroEntry
					or (type(heroEntry) == "table" and heroEntry.name or nil)
				PrecacheUnit(heroName)
			end
		end
	end

	local levelData = LoadKeyValues("scripts/data/levels.kv")
	if type(levelData) == "table" then
		for _, levelEntry in pairs(levelData) do
			if type(levelEntry) == "table" then
				for _, enemyEntry in pairs(levelEntry.enemies or {}) do
					if type(enemyEntry) == "table" then
						PrecacheUnit(enemyEntry.unit)
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

	-- 经济/商店/阵容：项目消费与 Valve 原版商店共用同一个玩家钱包。
	self.gold = self.shopCosts.initial_gold or INITIAL_GOLD
	self.nativeGoldSnapshot = nil
	self.nativeOrderSignatures = {}
	self.ownedHeroes = {}   -- 名字列表，招募顺序
	-- 个人等级/经验：heroData[name] = { level, current_xp, quality, order }
	self.heroData = {}
	self.heroOrder = 0
	self.scrollPurchases = { low = 0, high = 0 }  -- 当前关已购数量
	self.lineup = {}
	self.benchSlots = 0
	self.shopOffers = {}
	self.shopOfferText = ""
	self.refreshCount = 0
	self.scrollStock = { low = 0, high = 0 }
	self.scrollBought = { low = 0, high = 0 }
	self.attemptBuybacks = 0
	self.encounterSeed = nil
	self.heroRulesByName = {}
	-- 普通装备完全由 Valve 原版商店处理；项目面板只保留双卷轴与真实物品转交。
	self.heroInventories = {}  -- heroData[hero].inventory = { item, ... } 由 heroData 持有
	-- 实物装备可能通过原版拖拽/拾取改变；该快照用于只在变化时刷新 Panorama。
	self.equipmentSnapshot = nil
	self.barrierUnits = nil
	self.placedPositions = {}  -- heroName -> {x, y}（准备阶段玩家排的站位）

	self.battleManager = BattleManager(self)
	self.tacticBridge = TacticBridge.new({ game_mode = self })

	gameMode:SetCustomGameForceHero(PLAYER_PLACEHOLDER_HERO)
	gameMode:SetBuybackEnabled(false)
	gameMode:SetDaynightCycleDisabled(true)
	gameMode:SetFogOfWarDisabled(true)
	gameMode:SetUnseenFogOfWarEnabled(false)
	gameMode:SetCameraDistanceOverride(1500)
	-- 订单过滤由修订版 OrderFilter 安装（tactic_bridge）
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
	GameRules:SetStartingGold(self.gold)
	GameRules:SetUseUniversalShopMode(true)
	-- 自定义地图没有标准商店建筑；保留原版 Dota 商店的原价购买与出售体验。
	if gameMode.SetCanSellAnywhere ~= nil then
		gameMode:SetCanSellAnywhere(true)
		print("[Dota2Rpg] Native shop sell-anywhere enabled.")
	else
		print("[Dota2Rpg] WARNING: SetCanSellAnywhere is unavailable; native selling requires a shop range.")
	end
	if GameRules.SetHeroRespawnEnabled ~= nil then
		GameRules:SetHeroRespawnEnabled(false)
	end

	ListenToGameEvent("player_connect_full", Dynamic_Wrap(CDota2RpgDemo, "OnPlayerConnectFull"), self)
	ListenToGameEvent("npc_spawned", Dynamic_Wrap(CDota2RpgDemo, "OnNpcSpawned"), self)
	ListenToGameEvent("game_rules_state_change", Dynamic_Wrap(CDota2RpgDemo, "OnGameRulesStateChange"), self)
	ListenToGameEvent("entity_killed", Dynamic_Wrap(CDota2RpgDemo, "OnEntityKilled"), self)
	ListenToGameEvent("entity_hurt", Dynamic_Wrap(CDota2RpgDemo, "OnEntityHurt"), self)
	ListenToGameEvent("dota_item_picked_up", Dynamic_Wrap(CDota2RpgDemo, "OnItemPickedUp"), self)
	ListenToGameEvent("dota_item_purchased", Dynamic_Wrap(CDota2RpgDemo, "OnNativeItemPurchased"), self)

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
	CustomGameEventManager:RegisterListener("rpg_scroll_buy", function(eventSourceIndex, payload)
		return self:OnScrollBuy(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_scroll_use", function(eventSourceIndex, payload)
		return self:OnScrollUse(eventSourceIndex, payload)
	end)
	-- 普通装备购买/出售统一交给 Valve 原版商店；仅保留小精灵与英雄之间的转交。
	CustomGameEventManager:RegisterListener("rpg_item_equip", function(eventSourceIndex, payload)
		return self:OnItemEquip(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_item_unequip", function(eventSourceIndex, payload)
		return self:OnItemUnequip(eventSourceIndex, payload)
	end)

	PlayerResource:SetCustomTeamAssignment(0, DOTA_TEAM_GOODGUYS)
	self:GrantStarterHeroes()
	self:RollShop()
	-- 战术桥接初始化放最后：失败时给出可定位错误并中止初始化
	local okInstall, installErr = pcall(function()
		self.tacticBridge:Install()
	end)
	if not okInstall then
		error("[Dota2Rpg] TacticBridge install failed: " .. tostring(installErr))
	end
	print("[Dota2Rpg] BUILD rpg-shop-lineup-v2 loaded. Setup disabled, shop enabled.")
	print("[Dota2Rpg] Shop + lineup + TacticEngine initialized.")
end

-- 开局免费赠送 2 名 1 级英雄（只有开场才有；计入首发/待命体系）
function CDota2RpgDemo:GrantStarterHeroes()
	local pool = {}
	for _, categoryName in ipairs(SHOP_CATEGORIES) do
		for _, heroName in ipairs(self.heroPool[categoryName] or {}) do
			table.insert(pool, heroName)
		end
	end
	local granted = 0
	local used = {}
	while granted < 2 and #pool > 0 do
		local index = math.random(#pool)
		local heroName = pool[index]
		table.remove(pool, index)
		if not used[heroName] then
			used[heroName] = true
			granted = granted + 1
			table.insert(self.ownedHeroes, heroName)
			self.heroOrder = self.heroOrder + 1
			self.heroData[heroName] = {
				level = 1,
				current_xp = 0,
				quality = "common",
				order = self.heroOrder,
				skill_points = 1,
				inventory = {},
			}
		end
	end
	print("[Dota2Rpg] Starter heroes granted: " .. granted)
end

function CDota2RpgDemo:LoadHeroPool()
	local data = LoadKeyValues("scripts/data/heroes.kv")
	if type(data) ~= "table" then
		data = {}
	end
	self.heroPool = { strength = {}, agility = {}, intelligence = {}, universal = {} }
	self.shopCosts = {
		hero = tonumber(data.hero_cost) or SHOP_HERO_COST,
		refresh = tonumber(data.refresh_cost) or SHOP_REFRESH_COST,
		bench_slot = tonumber(data.bench_slot_cost) or SHOP_BENCH_SLOT_COST,
		bench_slot_max = tonumber(data.bench_slot_max) or BENCH_SLOT_MAX,
		lineup_max = tonumber(data.lineup_max) or LINEUP_MAX,
		initial_gold = tonumber(data.initial_gold) or INITIAL_GOLD,
	}
	-- 招募池 = 已通过预缓存验证的子集；全目录条目需逐个验证后才开放（DESIGN §7）
	local sourcePool = data.recruitable ~= nil and data.recruitable or data
	for _, category in ipairs(SHOP_CATEGORIES) do
		for _, hero in pairs(sourcePool[category] or {}) do
			-- 兼容两种目录格式：纯字符串（全英雄目录）或 { name = ... } 表
			local heroName = nil
			if type(hero) == "string" then
				heroName = hero
			elseif type(hero) == "table" and hero.name ~= nil then
				heroName = tostring(hero.name)
			end
			if heroName ~= nil then
				table.insert(self.heroPool[category], heroName)
			end
		end
		table.sort(self.heroPool[category])
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

-- 金币以 PlayerResource 总额为权威：这样 Valve 原版商店、招募与卷轴永远使用同一余额。
-- self.gold 仅保留给已有 HUD/结算载荷的兼容镜像，不能反向覆盖原版商店的扣款。
function CDota2RpgDemo:HasNativeGoldWallet()
	return PlayerResource ~= nil and PlayerResource.GetGold ~= nil
		and self.playerId ~= nil and self.playerId >= 0
end

function CDota2RpgDemo:GetGoldBalance()
	if self:HasNativeGoldWallet() then
		local nativeGold = tonumber(PlayerResource:GetGold(self.playerId))
		if nativeGold ~= nil then
			-- PlayerResource 是唯一真源。项目自己的消费会同步调用 SetGold，
			-- 因而这里直接镜像不会把原版商店扣款或出售返款反写掉。
			self.gold = math.max(0, math.floor(nativeGold))
			self.nativeGoldSnapshot = self.gold
		end
	end
	return math.max(0, math.floor(tonumber(self.gold) or 0))
end

function CDota2RpgDemo:SetGoldBalance(amount)
	self.gold = math.max(0, math.floor(tonumber(amount) or 0))
	if PlayerResource ~= nil and PlayerResource.SetGold ~= nil
		and self.playerId ~= nil and self.playerId >= 0 then
		-- 用可靠金币承载项目经济，并清空另一钱包，避免 GetGold 与 HUD 出现双份余额。
		PlayerResource:SetGold(self.playerId, self.gold, true)
		PlayerResource:SetGold(self.playerId, 0, false)
		self.nativeGoldSnapshot = self.gold
	end
	return self.gold
end

function CDota2RpgDemo:SpendGold(amount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	local balance = self:GetGoldBalance()
	if balance < amount then
		return false
	end
	self:SetGoldBalance(balance - amount)
	return true
end

function CDota2RpgDemo:AddGold(amount)
	amount = math.floor(tonumber(amount) or 0)
	return self:SetGoldBalance(self:GetGoldBalance() + amount)
end

function CDota2RpgDemo:SyncGoldFromPlayer()
	return self:GetGoldBalance()
end

function CDota2RpgDemo:OnPlayerConnectFull(event)
	local playerId = self:ResolvePlayerId(event)
	self.playerId = playerId
	PlayerResource:SetCustomTeamAssignment(playerId, DOTA_TEAM_GOODGUYS)
	if self.nativeGoldSnapshot == nil then
		self:SetGoldBalance(self.gold)
	else
		self:SyncGoldFromPlayer()
	end
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
	-- 明确归还小精灵控制权；某些工具模式不会自动把强制英雄标成可控单位。
	if unit.SetControllableByPlayer ~= nil then
		unit:SetControllableByPlayer(ownerId, true)
	end
	if unit:GetUnitName() == PLAYER_PLACEHOLDER_HERO then
		self.placeholderHero = unit
	end
	self.playerId = math.max(self.playerId, ownerId)
	if self.nativeGoldSnapshot == nil then
		self:SetGoldBalance(self.gold)
	end
	unit:SetRespawnsDisabled(true)
	-- 玩家小精灵 = 可自由移动的"指挥官"：禁攻/禁技能；准备阶段可自由拖拽装备，
	-- 开战后自动进入无敌（敌人无法选中/伤害它）
	unit:AddNewModifier(unit, nil, "modifier_disarmed", {})
	unit:AddNewModifier(unit, nil, "modifier_silence", {})
	FindClearSpaceForUnit(unit, Vector(-1950, -700, 128), true)
	self:EnsureBattlefield()
	print(string.format("[Dota2Rpg] Player commander ready for player %d.", self.playerId))
end

function CDota2RpgDemo:OnGameRulesStateChange()
	local state = GameRules:State_Get()
	if state == DOTA_GAMERULES_STATE_PRE_GAME or state == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		self:EnsureBattlefield()
	end
end

-- 卷轴与装备转交的最终实现位于后面的统一商店/装备实现区。

------------------------------------------------------------------
-- 战斗速度 1x/2x 与跳过（跳过 = 极限时间缩放快进到结算）
------------------------------------------------------------------





-- 经验卷轴使用：给使用该物品的英雄加经验（个人成长，受升级曲线约束）
function CDota2RpgDemo:GrantScrollXPByUnit(unit, xp)
	if unit == nil or not TacticEngine.IsValidUnit(unit) then
		return
	end
	local heroName = unit.lineupHeroName or unit:GetUnitName()
	local data = self.heroData[heroName]
	if data == nil then
		print("[Dota2Rpg] Scroll used by non-owned unit: " .. heroName)
		return
	end
	self:AddXpToHero(heroName, xp)
	self:BroadcastShopState()
	print(string.format("[Dota2Rpg] ScrollXP: %s +%d (lv%d, xp=%d, sp=%d)",
		heroName, xp, data.level, data.current_xp, data.skill_points))
end

-- XP、阵容和无存档状态处理统一由下方最终实现区提供。

------------------------------------------------------------------
-- 商店与阵容
------------------------------------------------------------------

-- 抽取招募等级（按当前关卡区间的权重）
function CDota2RpgDemo:RollRecruitLevel()
	local stage = tonumber(string.match(self.currentLevelId, "ch(%d+)")) or 1
	for _, rule in ipairs(RECRUIT_LEVEL_RULES) do
		if stage >= rule.from_stage and stage <= rule.to_stage then
			local total = 0
			for _, w in pairs(rule.weights) do
				total = total + w
			end
			local roll = math.random(1, total)
			for levelKey, w in pairs(rule.weights) do
				roll = roll - w
				if roll <= 0 then
					return tonumber(levelKey)
				end
			end
			return 1
		end
	end
	return 1
end

-- 品质概率：按关卡锚点线性插值
function CDota2RpgDemo:QualityWeightsForStage(stage)
	local lower, upper
	for i = 1, #QUALITY_ANCHORS do
		if QUALITY_ANCHORS[i].stage <= stage then
			lower = QUALITY_ANCHORS[i]
		elseif upper == nil then
			upper = QUALITY_ANCHORS[i]
		end
	end
	if lower == nil then
		lower = QUALITY_ANCHORS[1]
	end
	if upper == nil then
		return lower.weights
	end
	local span = upper.stage - lower.stage
	local t = (stage - lower.stage) / span
	local weights = {}
	for quality, w in pairs(lower.weights) do
		weights[quality] = math.floor(w + (upper.weights[quality] - w) * t + 0.5)
	end
	return weights
end

function CDota2RpgDemo:RollQuality(stage)
	local weights = self:QualityWeightsForStage(stage)
	local total = 0
	for _, w in pairs(weights) do
		total = total + w
	end
	local roll = math.random(1, math.max(1, total))
	for _, quality in ipairs({ "legendary", "epic", "fine", "common" }) do
		roll = roll - (weights[quality] or 0)
		if roll <= 0 then
			return quality
		end
	end
	return "common"
end

function CDota2RpgDemo:PriceFor(level, quality)
	local base = RECRUIT_BASE_PRICE[tostring(level)] or 100
	return math.floor(base * (QUALITY_PRICE_MULTIPLIER[quality] or 1.0) + 0.5)
end

-- 当前关刷新费用：20/40/.../200
function CDota2RpgDemo:GetRefreshCost()
	return math.min(REFRESH_MAX, REFRESH_BASE + self.refreshCount * REFRESH_STEP)
end

function CDota2RpgDemo:RollShop()
	-- 候选池 = 全部未拥有英雄；按四属性保证多样性，最后 1 个全池随机
	local ownedSet = {}
	for _, heroName in ipairs(self.ownedHeroes) do
		ownedSet[heroName] = true
	end
	local categories = { "strength", "agility", "intelligence", "universal" }
	local offer = {}
	for _, category in ipairs(categories) do
		local pool = {}
		for _, heroName in ipairs(self.heroPool[category]) do
			if not ownedSet[heroName] then
				table.insert(pool, heroName)
			end
		end
		if #pool > 0 then
			local heroName = pool[math.random(#pool)]
			table.insert(offer, heroName)
		end
	end
	local allHeroes = {}
	for _, category in ipairs(categories) do
		for _, heroName in ipairs(self.heroPool[category]) do
			if not ownedSet[heroName] then
				table.insert(allHeroes, heroName)
			end
		end
	end
	while #offer < self.shopCosts.lineup_max and #allHeroes > 0 do
		-- 抽中过前四个属性保底英雄时继续抽，而不是提前 break 导致只显示 4 个报价。
		local candidate = table.remove(allHeroes, math.random(#allHeroes))
		local duplicate = false
		for _, existing in ipairs(offer) do
			if existing == candidate then
				duplicate = true
				break
			end
		end
		if not duplicate then
			table.insert(offer, candidate)
		end
	end

	-- 报价：等级 + 品质 + 最终价格
	local stage = tonumber(string.match(self.currentLevelId, "ch(%d+)")) or 1
	local offers = {}
	for _, heroName in ipairs(offer) do
		local level = self:RollRecruitLevel()
		local quality = self:RollQuality(stage)
		table.insert(offers, {
			hero = heroName,
			level = level,
			quality = quality,
			price = self:PriceFor(level, quality),
		})
	end
	self.shopOffers = offers

	-- 序列化为扁平字符串（CEM 不传嵌套/数组）
	local parts = {}
	for _, o in ipairs(offers) do
		table.insert(parts, o.hero .. "|" .. o.level .. "|" .. o.quality .. "|" .. o.price)
	end
	self.shopOfferText = table.concat(parts, ";")
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnShopRefresh(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local cost = self:GetRefreshCost()
	if not self:SpendGold(cost) then
		return
	end
	self.refreshCount = self.refreshCount + 1
	self:RollShop()
end

function CDota2RpgDemo:FindOffer(heroName)
	for _, o in ipairs(self.shopOffers) do
		if o.hero == heroName then
			return o
		end
	end
	return nil
end

function CDota2RpgDemo:GetHeroData(heroName)
	if self.heroData[heroName] == nil then
		self.heroOrder = self.heroOrder + 1
		self.heroData[heroName] = { level = 1, current_xp = 0, quality = "common", order = self.heroOrder, inventory = {} }
	end
	if self.heroData[heroName].inventory == nil then
		self.heroData[heroName].inventory = {}
	end
	return self.heroData[heroName]
end

function CDota2RpgDemo:OnShopBuy(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local offer = self:FindOffer(heroName)
	if offer == nil then
		return -- 不在本次报价中
	end
	for _, owned in ipairs(self.ownedHeroes) do
		if owned == heroName then
			return -- 每名英雄只能招募一次
		end
	end
	if #self.ownedHeroes >= self.shopCosts.lineup_max + self.shopCosts.bench_slot_max then
		return -- 10 格上限
	end
	if not self:SpendGold(offer.price) then
		return
	end
	table.insert(self.ownedHeroes, heroName)
	local data = self:GetHeroData(heroName)
	data.level = offer.level
	data.current_xp = 0
	data.quality = offer.quality
	self.heroRulesByName[heroName] = self.heroRulesByName[heroName] or CloneDefaultRules()

	-- 购买的英雄默认进待命区；格子经济：首发 5 人额外，每名替补英雄需购买替补格
	local overflow = #self.ownedHeroes - self.shopCosts.lineup_max + 1
	if overflow > self.benchSlots then
		table.remove(self.ownedHeroes)
		self:AddGold(offer.price)
		self.heroData[heroName] = nil
		return -- 替补格子不足（买满 5 名首发后需要替补格）
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

-- 当前关剩余卷轴限购
function CDota2RpgDemo:GetScrollRemaining(kind)
	return SCROLL_LIMIT_PER_STAGE - (self.scrollPurchases[kind] or 0)
end

function CDota2RpgDemo:OnScrollBuy(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local kind = payload ~= nil and tostring(payload.kind or "low") or "low"
	if SCROLL_COST[kind] == nil or self:GetScrollRemaining(kind) <= 0 then
		return
	end
	if not self:SpendGold(SCROLL_COST[kind]) then
		return
	end
	self.scrollPurchases[kind] = (self.scrollPurchases[kind] or 0) + 1
	self.scrollStock[kind] = (self.scrollStock[kind] or 0) + 1
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnScrollUse(_, payload)
	if self.phase ~= "setup" then
		return -- 只允许准备阶段使用，倒计时/战斗/结算均锁定
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local kind = payload ~= nil and tostring(payload.kind or "low") or "low"
	if SCROLL_XP[kind] == nil then
		return
	end
	if (self.scrollStock[kind] or 0) <= 0 then
		return
	end
	local data = self.heroData[heroName]
	if data == nil or data.level >= HERO_LEVEL then
		return -- 30 级不能使用
	end
	self.scrollStock[kind] = self.scrollStock[kind] - 1
	self:AddXpToHero(heroName, SCROLL_XP[kind])
	-- 经验卷轴不应为了更新等级而销毁/重建英雄；这样会使原版装备实体 ID、冷却和堆叠状态失效。
	local hero = self:FindLineupUnit(heroName)
	if hero ~= nil and hero.GetLevel ~= nil then
		self:PrepareBattleHero(hero, data.level)
		self:SyncHeroInventoryFromUnit(hero)
	end
	self:BroadcastHeroInfo()
	self:BroadcastShopState()
end

------------------------------------------------------------------
-- 原版物品商店 + 小精灵/英雄转交：普通装备由 Valve 定价和出售
------------------------------------------------------------------

-- 装备必须在原单位间移动，而不是“删除后按名字重建”。后者会让当前选中的英雄实体被
-- RespawnPlayerRoster 销毁，导致原版 HUD 的物品按钮和 Panorama 的目标按钮一起消失。
function CDota2RpgDemo:IsLiveItem(item)
	return item ~= nil and (item.IsNull == nil or not item:IsNull())
end

function CDota2RpgDemo:GetItemEntityId(item)
	if not self:IsLiveItem(item) then
		return ""
	end
	if item.GetEntityIndex ~= nil then
		return tostring(item:GetEntityIndex())
	end
	if item.entindex ~= nil then
		return tostring(item:entindex())
	end
	return ""
end

function CDota2RpgDemo:IsLineupUnit(unit)
	if unit == nil then
		return false
	end
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
		if hero == unit then
			return true
		end
	end
	return false
end

-- 物品交互只允许玩家小精灵和当前上阵英雄；待命单位仅用于被右键换上场。
function CDota2RpgDemo:IsEquipmentCarrier(unit)
	return unit ~= nil and (unit == self:GetStashUnit() or self:IsLineupUnit(unit))
end

function CDota2RpgDemo:FindEmptyActiveItemSlot(hero)
	if hero == nil or hero.GetItemInSlot == nil then
		return nil
	end
	for slot = 0, 5 do
		if not self:IsLiveItem(hero:GetItemInSlot(slot)) then
			return slot
		end
	end
	return nil
end

function CDota2RpgDemo:HasFreeStashSlot()
	local stash = self:GetStashUnit()
	if stash == nil or stash.GetItemInSlot == nil then
		return false
	end
	for slot = 0, 8 do
		if not self:IsLiveItem(stash:GetItemInSlot(slot)) then
			return true
		end
	end
	return false
end

function CDota2RpgDemo:IsItemHeldBy(unit, item, firstSlot, lastSlot)
	if unit == nil or item == nil or unit.GetItemInSlot == nil then
		return false
	end
	for slot = firstSlot, lastSlot do
		if unit:GetItemInSlot(slot) == item then
			return true
		end
	end
	return false
end

-- 从小精灵库存取出“同一个”物品实体。保留实体可避免拖拽/拾取后的物品残留在地上。
function CDota2RpgDemo:TakeStashItem(itemName, expectedItemId)
	local stash = self:GetStashUnit()
	if stash == nil or stash.GetItemInSlot == nil then
		return nil
	end
	local expected = tostring(expectedItemId or "")
	for slot = 0, 8 do
		local item = stash:GetItemInSlot(slot)
		if self:IsLiveItem(item) and item:GetAbilityName() == itemName
			and (expected == "" or self:GetItemEntityId(item) == expected) then
			stash:RemoveItem(item)
			return item
		end
	end
	return nil
end

function CDota2RpgDemo:PutItemInStash(item)
	local stash = self:GetStashUnit()
	if not self:IsLiveItem(item) or stash == nil or not self:HasFreeStashSlot() then
		return false
	end
	stash:AddItem(item)
	return self:IsItemHeldBy(stash, item, 0, 8)
end

function CDota2RpgDemo:GetItemPersistentState(item)
	local charges = nil
	if self:IsLiveItem(item) and item.GetCurrentCharges ~= nil then
		charges = tonumber(item:GetCurrentCharges())
	end
	return { name = self:IsLiveItem(item) and item:GetAbilityName() or "", charges = charges }
end

function CDota2RpgDemo:RestoreItemPersistentState(item, state)
	if not self:IsLiveItem(item) or type(state) ~= "table" then
		return
	end
	if state.charges ~= nil and item.SetCurrentCharges ~= nil then
		item:SetCurrentCharges(math.max(0, tonumber(state.charges) or 0))
	end
end

function CDota2RpgDemo:SyncHeroInventoryFromUnit(hero)
	if hero == nil or hero.GetUnitName == nil or hero.GetItemInSlot == nil then
		return false
	end
	local heroName = hero.lineupHeroName or hero:GetUnitName()
	local data = self.heroData[heroName]
	if data == nil then
		return false
	end
	local inventory = {}
	local states = {}
	local entities = {}
	for slot = 0, 5 do
		local item = hero:GetItemInSlot(slot)
		if self:IsLiveItem(item) then
			table.insert(inventory, item:GetAbilityName())
			table.insert(states, self:GetItemPersistentState(item))
			table.insert(entities, item)
		end
	end
	-- 完整重建，保留同名物品的重复数量；不能用“是否已记录”去重。
	-- entities 只在当前服务端内存中使用，用于阵容重铸时继续携带同一个 Dota 实体。
	data.inventory = inventory
	data.inventory_states = states
	data.inventory_entities = entities
	return true
end

function CDota2RpgDemo:SyncLineupInventories()
	for _, heroName in ipairs(self.lineup or {}) do
		local hero = self:FindLineupUnit(heroName)
		if hero ~= nil then
			self:SyncHeroInventoryFromUnit(hero)
		end
	end
end

-- 原版 HUD 可以把物品拖到地上、给小精灵或让英雄拾取；这些操作没有 CustomGameEvent。
-- 用很小的库存签名轮询，变化时才向 Panorama 推送，避免陈旧按钮/库存状态。
function CDota2RpgDemo:BuildEquipmentSnapshot()
	local parts = {}
	local function appendUnit(unit, prefix, lastSlot)
		if unit == nil or unit.GetItemInSlot == nil then
			return
		end
		for slot = 0, lastSlot do
			local item = unit:GetItemInSlot(slot)
			if self:IsLiveItem(item) then
				-- 名称/槽位相同但实体已替换时也必须推送，避免客户端保留陈旧 item_index。
				table.insert(parts, prefix .. slot .. "=" .. item:GetAbilityName() .. "|" .. self:GetItemEntityId(item))
			end
		end
	end
	appendUnit(self:GetStashUnit(), "stash:", 8)
	for _, heroName in ipairs(self.lineup or {}) do
		appendUnit(self:FindLineupUnit(heroName), "hero:" .. heroName .. ":", 5)
	end
	return table.concat(parts, ";")
end

function CDota2RpgDemo:SyncLiveEquipmentState(force)
	if self.phase ~= "setup" then
		return false
	end
	local snapshot = self:BuildEquipmentSnapshot()
	if not force and snapshot == self.equipmentSnapshot then
		return false
	end
	self:SyncLineupInventories()
	self.equipmentSnapshot = self:BuildEquipmentSnapshot()
	self:BroadcastHeroInfo()
	self:BroadcastShopState()
	return true
end

function CDota2RpgDemo:OnItemPickedUp(_)
	if self.phase == "setup" then
		self:SyncGoldFromPlayer()
		self:SyncLiveEquipmentState(true)
	end
end

function CDota2RpgDemo:OnNativeItemPurchased(event)
	local playerId = tonumber(event ~= nil and event.PlayerID or -1) or -1
	if self.phase == "setup" and playerId == self.playerId then
		-- 事件可能在引擎真正扣款的同一帧触发；下一轮 Think 再读取钱包最可靠。
		self.nativeShopTransactionPending = true
	end
end

function CDota2RpgDemo:MoveStashItemToHero(heroName, itemName, itemId)
	local hero = self:FindLineupUnit(heroName)
	if hero == nil or self.heroData[heroName] == nil or self:FindEmptyActiveItemSlot(hero) == nil then
		return false
	end
	local item = self:TakeStashItem(itemName, itemId)
	if item == nil then
		return false
	end
	hero:AddItem(item)
	if self:IsItemHeldBy(hero, item, 0, 5) then
		self:SyncHeroInventoryFromUnit(hero)
		return true
	end
	-- AddItem 失败时绝不吞物品：从任何英雄槽移除后原样还给小精灵。
	if self:IsItemHeldBy(hero, item, 0, 8) then
		hero:RemoveItem(item)
	end
	self:PutItemInStash(item)
	return false
end

function CDota2RpgDemo:MoveHeroItemToStash(hero, item)
	if hero == nil or not self:IsLiveItem(item) or not self:HasFreeStashSlot() then
		return false
	end
	hero:RemoveItem(item)
	if self:PutItemInStash(item) then
		self:SyncHeroInventoryFromUnit(hero)
		return true
	end
	-- 库存移动失败时把物品归还给原英雄，保持操作原子性。
	hero:AddItem(item)
	return false
end

function CDota2RpgDemo:OnItemEquip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local itemName = payload ~= nil and tostring(payload.item or "") or ""
	local itemId = payload ~= nil and tostring(payload.item_index or "") or ""
	if itemId == "" then
		return -- 拒绝模糊的同名装备请求
	end
	if self:MoveStashItemToHero(heroName, itemName, itemId) then
		-- 不重生英雄：当前选中状态、物品栏和装备目标都保持不变。
		self:SyncLiveEquipmentState(true)
	end
end

function CDota2RpgDemo:OnItemUnequip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local itemName = payload ~= nil and tostring(payload.item or "") or ""
	local expectedItemId = payload ~= nil and tostring(payload.item_index or "") or ""
	local slot = tonumber(payload and payload.slot or -1) or -1
	if expectedItemId == "" then
		return -- 卸下也必须锁定到具体实体，避免同名装备点错
	end
	local hero = self:FindLineupUnit(heroName)
	if hero == nil then
		return
	end
	local item = nil
	if itemName ~= "" then
		-- 面板按装备名称请求，服务端仍从真实槽位寻找，兼容玩家手动调整槽位。
		for candidateSlot = 0, 5 do
			local candidate = hero:GetItemInSlot(candidateSlot)
			if self:IsLiveItem(candidate) and candidate:GetAbilityName() == itemName
				and (expectedItemId == "" or self:GetItemEntityId(candidate) == expectedItemId) then
				item = candidate
				break
			end
		end
	elseif slot >= 0 and slot <= 5 then
		local candidate = hero:GetItemInSlot(slot)
		if self:IsLiveItem(candidate) and self:GetItemEntityId(candidate) == expectedItemId then
			item = candidate
		end
	end
	if self:MoveHeroItemToStash(hero, item) then
		self:SyncLiveEquipmentState(true)
	end
end

function CDota2RpgDemo:FindLineupUnit(heroName)
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]) do
		if TacticEngine.IsValidUnit(hero) and hero:GetUnitName() == heroName then
			return hero
		end
	end
	return nil
end

------------------------------------------------------------------
-- 战斗速度 1x/2x 与跳过（跳过 = 极限时间缩放快进到结算）
------------------------------------------------------------------





-- 经验池平均分配（含余数按招募顺序补 1）
function CDota2RpgDemo:DistributeXpPool(pool)
	local owned = {}
	for _, heroName in ipairs(self.ownedHeroes) do
		table.insert(owned, heroName)
	end
	if #owned == 0 then
		return
	end
	local base = math.floor(pool / #owned)
	local remainder = pool % #owned
	for _, heroName in ipairs(owned) do
		local extra = 0
		if remainder > 0 then
			extra = 1
			remainder = remainder - 1
		end
		self:AddXpToHero(heroName, base + extra)
	end
end

function CDota2RpgDemo:AddXpToHero(heroName, amount)
	local data = self.heroData[heroName]
	if data == nil or data.level >= HERO_LEVEL then
		return -- 满级经验舍弃
	end
	data.skill_points = data.skill_points or data.level
	local before = data.level
	data.current_xp = data.current_xp + amount
	-- v1.0 升级曲线：到达该等级所需累计经验（30 级总需求 33700）
	local XP_TO_LEVEL = { 0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700,
		3300, 4000, 4800, 5700, 6700, 7800, 9000, 10300, 11700, 13200,
		14800, 16500, 18300, 20200, 22200, 24300, 26500, 28800, 31200 }
	while data.level < HERO_LEVEL do
		local need = XP_TO_LEVEL[data.level + 1] or 33700
		if data.current_xp >= need then
			data.current_xp = data.current_xp - need
			data.level = data.level + 1
			data.skill_points = data.skill_points + 1
		else
			break
		end
	end
	if data.level >= HERO_LEVEL then
		data.current_xp = 0
	end
	print(string.format("[Dota2Rpg] XP: %s +%d (lv%d -> lv%d, sp=%d, xp=%d)",
		heroName, amount, before, data.level, data.skill_points, data.current_xp))
end

function CDota2RpgDemo:OnBenchBuy(_, payload)
	if self.phase ~= "setup" then
		return
	end
	if self.benchSlots >= self.shopCosts.bench_slot_max then
		return
	end
	if not self:SpendGold(self.shopCosts.bench_slot) then
		return
	end
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
		ownedSet[owned] = true
	end
	for _, heroName in ipairs(ReadPayloadList(payload, "lineup_text", "lineup") or {}) do
		heroName = tostring(heroName)
		if ownedSet[heroName] and #lineup < self.shopCosts.lineup_max then
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

-- CEM 载荷列表（分号分隔字符串）拆回 Lua 数组。
function CDota2RpgDemo:ReadPayloadList(payload, fieldName)
	local result = {}
	if payload == nil or payload[fieldName] == nil then
		return result
	end
	for entry in string.gmatch(tostring(payload[fieldName]), "[^;]+") do
		table.insert(result, entry)
	end
	return result
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



function CDota2RpgDemo:EnsureBattlefield()
	if self.teamsSpawned then
		return
	end

	self.teamsSpawned = true
	-- 初次进入时必须先生成一批招募报价；否则只会广播空 offer_text，
	-- Panorama 英雄商店会一直保持空白直到玩家手动刷新。
	if self.shopOffers == nil or #self.shopOffers == 0 then
		self:RollShop()
	end
	self:SpawnLevelEnemies(self.currentLevelId)
	self:RespawnPlayerRoster()
	self:SpawnBattleBarrier()

	self:BroadcastShopState()
	self:BroadcastLevelInfo()
	self:BroadcastBattleState()
	print("[Dota2Rpg] Battlefield ready for level " .. self.currentLevelId .. ".")
end

-- 玩家阵容：按 lineup 顺序在己方出生点生成，统一等级 self.playerLevel
function CDota2RpgDemo:SpawnBattleBarrier()
	self:RemoveBattleBarrier()
	self.barrierUnits = {}
	local y = -BARRIER_HALF_SPAN
	while y <= BARRIER_HALF_SPAN do
		local pos = GetGroundPosition(Vector(BARRIER_X, y, 128), nil)
		-- 树木实体：不可选中/不可摧毁，阻挡中线
		local ok, tree = pcall(SpawnEntityFromTableSynchronous, "ent_dota_tree", { origin = pos })
		if ok and tree ~= nil then
			table.insert(self.barrierUnits, tree)
		else
			break
		end
		y = y + BARRIER_SPACING
	end
	-- 装备仓库 = 玩家自己的小精灵（指挥官），不再生成独立的仓库单位
	print("[Dota2Rpg] Battle barrier spawned.")
end

-- 仓库 = 玩家自己的小精灵（指挥官）：购买的装备直接放在它身上，
-- 玩家可自由拖拽、丢到地上给英雄拾取
function CDota2RpgDemo:GetStashUnit()
	local hero = self.placeholderHero
	if hero ~= nil and TacticEngine.IsValidUnit(hero) then
		return hero
	end
	return nil
end

function CDota2RpgDemo:StashAddItem(itemName)
	local stash = self:GetStashUnit()
	if stash == nil then
		return false
	end
	-- 物品栏 0..5 + 背包 6..8
	for slot = 0, 8 do
		if stash:GetItemInSlot(slot) == nil then
			local item = stash:AddItemByName(itemName)
			return item ~= nil and not item:IsNull()
		end
	end
	return false -- 仓库已满（9 格）
end

function CDota2RpgDemo:RemoveBattleBarrier()
	for _, unit in ipairs(self.barrierUnits or {}) do
		if unit ~= nil and (unit.IsNull == nil or not unit:IsNull()) then
			pcall(function()
				unit:RemoveSelf()
			end)
		end
	end
	self.barrierUnits = nil
end

-- 用树墙围出待命区（树会阻挡移动，形成封闭地形；长持续时间常驻）
function CDota2RpgDemo:SpawnBenchEnclosure()
	if self.benchEnclosureBuilt then
		return
	end
	self.benchEnclosureBuilt = true
	local cx, cy = BENCH_AREA_CENTER.x, BENCH_AREA_CENTER.y
	local hw, hh = BENCH_AREA_HALF_W, BENCH_AREA_HALF_H
	local function plant(x, y)
		CreateTempTree(GetGroundPosition(Vector(x, y, 128), nil), BENCH_TREE_DURATION)
	end
	local cols = math.ceil((hw * 2) / BENCH_TREE_SPACING)
	local rows = math.ceil((hh * 2) / BENCH_TREE_SPACING)
	for i = 0, cols do
		plant(cx - hw + i * BENCH_TREE_SPACING, cy - hh)
		plant(cx - hw + i * BENCH_TREE_SPACING, cy + hh)
	end
	for j = 0, rows do
		plant(cx - hw, cy - hh + j * BENCH_TREE_SPACING)
		plant(cx + hw, cy - hh + j * BENCH_TREE_SPACING)
	end
	print("[Dota2Rpg] Bench enclosure built.")
end

-- 生成场下英雄到待命区（无敌/禁足展示，不参与战斗与胜负判定）
function CDota2RpgDemo:SpawnBenchHeroes()
	-- 清理旧场下单位
	for _, unit in ipairs(self.benchUnits or {}) do
		if TacticEngine.IsValidUnit(unit) then
			unit:RemoveSelf()
		end
	end
	self.benchUnits = {}

	for _, heroName in ipairs(self.ownedHeroes) do
		local onLineup = false
		for _, lineupName in ipairs(self.lineup) do
			if lineupName == heroName then
				onLineup = true
				break
			end
		end
		if not onLineup then
			local count = #self.benchUnits
			local col = count % BENCH_GRID_COLS
			local row = math.floor(count / BENCH_GRID_COLS)
			local pos = GetGroundPosition(Vector(
				BENCH_AREA_CENTER.x - BENCH_GRID_SPACING + col * BENCH_GRID_SPACING,
				BENCH_AREA_CENTER.y - 120 + row * BENCH_GRID_SPACING, 128), nil)
			local unit = CreateUnitByName(heroName, pos, true, nil, nil, DOTA_TEAM_GOODGUYS)
			if TacticEngine.IsValidUnit(unit) then
				FindClearSpaceForUnit(unit, pos, true)
				local data = self.heroData[heroName]
				self.autoAbilityHeroes = self.autoAbilityHeroes or {}
				self.autoAbilityHeroes[unit:GetEntityIndex()] = true
				self:PrepareBattleHero(unit, data ~= nil and data.level or 1)
				unit.benchHeroName = heroName
				if data ~= nil and QUALITY_CONSUMED_MODIFIERS[data.quality] ~= nil then
					for _, modifierName in ipairs(QUALITY_CONSUMED_MODIFIERS[data.quality]) do
						unit:AddNewModifier(unit, nil, modifierName, {})
					end
				end
				table.insert(self.benchUnits, unit)
			end
		end
	end
end

function CDota2RpgDemo:RespawnPlayerRoster()
	if self.phase ~= "setup" then
		return
	end
	self.heroData = self.heroData or {}
	self:SpawnBenchEnclosure()
	self:SpawnBenchHeroes()
	local battleManager = self.battleManager
	for _, hero in ipairs(battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]) do
		if TacticEngine.IsValidUnit(hero) then
			-- 重铸前把身上的装备收回个人库存记录，避免随单位销毁
			local heroName = hero:GetUnitName()
			local data = self.heroData[heroName]
			if data ~= nil and hero.GetItemInSlot ~= nil then
				-- 以真实槽位完整重建，必须保留两把相同装备等合法重复项。
				data.inventory = {}
				data.inventory_states = {}
				data.inventory_entities = {}
				for slot = 0, 5 do
					local item = hero:GetItemInSlot(slot)
					if item ~= nil and not item:IsNull() then
						table.insert(data.inventory, item:GetAbilityName())
						table.insert(data.inventory_states, self:GetItemPersistentState(item))
						table.insert(data.inventory_entities, item)
						if hero.RemoveItem ~= nil then
							-- RemoveItem 脱离持有者但不销毁实体；新上阵单位会重新接管它。
							hero:RemoveItem(item)
						end
					end
				end
			end
			hero:RemoveSelf()
		end
	end
	battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] = {}
	battleManager.teamRules[DOTA_TEAM_GOODGUYS] = {}

	for index, heroName in ipairs(self.lineup) do
		if index > #TEAM_SPAWNS[DOTA_TEAM_GOODGUYS] then
			break
		end
		-- 玩家在准备阶段排的站位优先保留
		local placed = self.placedPositions[heroName]
		local spawnPosition = placed ~= nil
			and GetGroundPosition(Vector(placed.x, placed.y, 128), nil)
			or GetGroundPosition(TEAM_SPAWNS[DOTA_TEAM_GOODGUYS][index], nil)
		local hero = CreateUnitByName(heroName, spawnPosition, true, nil, nil, DOTA_TEAM_GOODGUYS)
		if TacticEngine.IsValidUnit(hero) then
			FindClearSpaceForUnit(hero, spawnPosition, true)
			local heroData = self:GetHeroData(heroName)
			self.autoAbilityHeroes = self.autoAbilityHeroes or {}
			self.autoAbilityHeroes[hero:GetEntityIndex()] = nil -- 上阵英雄：玩家手动加点
			hero.lineupHeroName = heroName
			self:PrepareBattleHero(hero, heroData ~= nil and heroData.level or 1)
			-- 上阵英雄必须可以被玩家选中/下达准备阶段移动、拾取和物品转移指令。
			-- 战斗中的订单仍会被 tactic_bridge 的 OrderFilter 拒绝。
			if self.playerId ~= nil and self.playerId >= 0 and hero.SetControllableByPlayer ~= nil then
				hero:SetControllableByPlayer(self.playerId, true)
			end
			local points = heroData ~= nil and math.max(0, heroData.skill_points or heroData.level) or 1
			hero:SetAbilityPoints(points)
			print(string.format("[Dota2Rpg] %s fielded: level=%d skill_points=%d (player picks abilities)",
				heroName, heroData ~= nil and heroData.level or 1, points))
			-- 重新佩戴个人装备
			heroData.inventory = heroData.inventory or {}
			heroData.inventory_states = heroData.inventory_states or {}
			heroData.inventory_entities = heroData.inventory_entities or {}
			for inventoryIndex, itemName in ipairs(heroData.inventory) do
				if inventoryIndex <= 6 then
					local item = heroData.inventory_entities[inventoryIndex]
					if not self:IsLiveItem(item) then
						item = hero:AddItemByName(itemName)
					else
						hero:AddItem(item)
					end
					if not self:IsItemHeldBy(hero, item, 0, 5) then
						-- 极端情况下实体已被引擎清理，才退回到同名重建并记录日志。
						print(string.format("[Dota2Rpg] WARNING: item entity restore failed for %s; recreating.", itemName))
						item = hero:AddItemByName(itemName)
					end
					self:RestoreItemPersistentState(item, heroData.inventory_states[inventoryIndex])
				end
			end
			-- 品质内置升级：魔晶/神杖（不占装备栏）
			if heroData ~= nil and QUALITY_CONSUMED_MODIFIERS[heroData.quality] ~= nil then
				for _, modifierName in ipairs(QUALITY_CONSUMED_MODIFIERS[heroData.quality]) do
					hero:AddNewModifier(hero, nil, modifierName, {})
				end
			end
			battleManager:RegisterHero(DOTA_TEAM_GOODGUYS, index, hero)
			-- 固定 10 槽：按英雄动作列表生成默认规则（玩家可改）
			self.heroRulesByName[heroName] = self.heroRulesByName[heroName]
				or BuildDefaultRulesForSlots(BuildHeroActionSlots(hero))
			battleManager.teamRules[DOTA_TEAM_GOODGUYS][index] = self.heroRulesByName[heroName]
		else
			print(string.format("[Dota2Rpg] Failed to spawn lineup hero %s.", heroName))
		end
	end
	self.equipmentSnapshot = nil
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
					-- 野怪模板成长：生命/攻击倍率、额外护甲、魔抗、状态抗性
					if entry.hp_multiplier ~= nil then
						local maxHealth = unit:GetMaxHealth()
						unit:SetMaxHealth(math.floor(maxHealth * tonumber(entry.hp_multiplier) + 0.5))
						unit:SetHealth(unit:GetMaxHealth())
					end
					if entry.attack_multiplier ~= nil and unit.SetBaseDamageMin ~= nil then
						local bonus = math.floor(unit:GetAttackDamage() * (tonumber(entry.attack_multiplier) - 1) + 0.5)
						unit:SetBaseDamageMin(unit:GetBaseDamageMin() + bonus)
						unit:SetBaseDamageMax(unit:GetBaseDamageMax() + bonus)
					end
					if entry.bonus_armor ~= nil and unit.SetPhysicalArmorBaseValue ~= nil then
						unit:SetPhysicalArmorBaseValue(unit:GetPhysicalArmorBaseValue() + tonumber(entry.bonus_armor))
					end
					if entry.magic_resistance ~= nil and unit.SetMagicalArmorValue ~= nil then
						unit:SetMagicalArmorValue(tonumber(entry.magic_resistance) / 100)
					end
					if entry.status_resistance ~= nil and unit.SetStatusResistance ~= nil then
						unit:SetStatusResistance(tonumber(entry.status_resistance))
					end
				end
				-- 敌方品质/内置升级：魔晶/神杖
				for _, upgrade in ipairs(entry.quality_upgrades or {}) do
					if upgrade == "shard" then
						unit:AddNewModifier(unit, nil, "modifier_item_aghanims_shard_consumed", {})
					elseif upgrade == "scepter" then
						unit:AddNewModifier(unit, nil, "modifier_item_ultimate_scepter_consumed", {})
					end
				end
				battleManager:RegisterHero(DOTA_TEAM_BADGUYS, enemyIndex, unit)
				unit.enemyRuleIndex = enemyIndex
				battleManager:RegisterEnemyTags(unit, entry.tags)
				battleManager.teamRules[DOTA_TEAM_BADGUYS][enemyIndex] = self:BuildEnemyRules(entry.ai)
			else
				print(string.format("[Dota2Rpg] Failed to spawn enemy %s.", tostring(entry.unit)))
			end
		end
	end
	print(string.format("[Dota2Rpg] Level '%s' spawned %d enemy units.", levelId, enemyIndex))
end

function CDota2RpgDemo:PrepareEnemyHero(hero, level)
	self.autoAbilityHeroes = self.autoAbilityHeroes or {}
	self.autoAbilityHeroes[hero:GetEntityIndex()] = true
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
			target = presetRule.target or "enemy_distance_nearest",
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

	-- 技能加点：敌方/待命区英雄自动加点（普通技能 ceil(lv/2)，大招 6/12/18 级）；
	-- 玩家上阵英雄保留技能点（level-1 点），由玩家在准备阶段自己决定学什么
	local autoAbilities = self.autoAbilityHeroes == nil or self.autoAbilityHeroes[hero:GetEntityIndex()] ~= nil
	if autoAbilities then
		local basicLevel = math.max(1, math.min(4, math.ceil(wantedLevel / 2)))
		local ultimateLevel = 0
		if wantedLevel >= 18 then
			ultimateLevel = 3
		elseif wantedLevel >= 12 then
			ultimateLevel = 2
		elseif wantedLevel >= 6 then
			ultimateLevel = 1
		end
		for slot = 0, hero:GetAbilityCount() - 1 do
			local ability = hero:GetAbilityByIndex(slot)
			if ability ~= nil and not ability:IsNull() then
				local abilityName = ability:GetAbilityName()
				local isTalent = string.find(abilityName, "special_bonus", 1, true) ~= nil
				if not isTalent and ability:GetMaxLevel() > 0 then
					if ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
						ability:SetLevel(math.min(ability:GetMaxLevel(), ultimateLevel))
					else
						ability:SetLevel(math.min(ability:GetMaxLevel(), basicLevel))
					end
				end
			end
		end
		hero:SetAbilityPoints(0)
	else
		hero:SetAbilityPoints(math.max(0, wantedLevel))
	end
	hero:SetRespawnsDisabled(true)
	hero:SetHealth(hero:GetMaxHealth())
	hero:SetMana(hero:GetMaxMana())
	hero:SetIdleAcquire(false)
	hero:SetAcquisitionRange(0)

	-- 上阵英雄不挂禁足：准备阶段玩家需要自由移动它们排位
	-- （移动指令由订单过滤器放行并限制在己方半场）
	local isFielded = self.autoAbilityHeroes ~= nil
		and self.autoAbilityHeroes[hero:GetEntityIndex()] == nil
	for _, modifierName in ipairs(PRE_BATTLE_MODIFIERS) do
		if isFielded and modifierName == "modifier_rooted" then
			-- 上阵英雄保持可移动
		else
			hero:AddNewModifier(hero, nil, modifierName, {})
		end
	end
end

-- 原版商店购买/出售不一定带 units；OrderFilter 需显式把它们送到本校验器，
-- 否则空单位表会绕过 COUNTDOWN/FIGHT/SETTLE 的阶段锁。
function CDota2RpgDemo:IsNativeItemShopOrder(filterTable)
	local orderType = tonumber(filterTable and filterTable.order_type) or 0
	return orderType == DOTA_UNIT_ORDER_PURCHASE_ITEM
		or orderType == DOTA_UNIT_ORDER_SELL_ITEM
		or orderType == DOTA_UNIT_ORDER_DISASSEMBLE_ITEM
end

-- 首次遇到每种原版商店订单时记录完整的标量字段，便于 Workshop Tools 实机确认 Valve 协议。
-- 该诊断不改变订单，也不把日志当作授权依据；真正的白名单仍由 ValidatePrepareOrder 执行。
function CDota2RpgDemo:TraceNativeShopOrder(filterTable)
	if type(filterTable) ~= "table" then
		return
	end
	local fields = {}
	for key, value in pairs(filterTable) do
		if key == "units" and type(value) == "table" then
			local units = {}
			for _, entityIndex in pairs(value) do
				table.insert(units, tostring(entityIndex))
			end
			table.sort(units)
			table.insert(fields, "units=" .. table.concat(units, ","))
		elseif type(value) ~= "table" and type(value) ~= "function" then
			table.insert(fields, tostring(key) .. "=" .. tostring(value))
		end
	end
	table.sort(fields)
	local signature = table.concat(fields, "|")
	self.nativeOrderSignatures = self.nativeOrderSignatures or {}
	if not self.nativeOrderSignatures[signature] then
		self.nativeOrderSignatures[signature] = true
		print("[Dota2Rpg] Native order signature: " .. signature)
	end
end

function CDota2RpgDemo:FindEquipmentItemHolder(item)
	if not self:IsLiveItem(item) then
		return nil
	end
	local stash = self:GetStashUnit()
	if stash ~= nil and self:IsItemHeldBy(stash, item, 0, 8) then
		return stash
	end
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
		if self:IsLineupUnit(hero) and self:IsItemHeldBy(hero, item, 0, 5) then
			return hero
		end
	end
	return nil
end

function CDota2RpgDemo:ValidatePrepareOrder(filterTable)
	local issuerPlayerId = tonumber(filterTable.issuer_player_id_const) or -1
	if issuerPlayerId < 0 then
		return true -- 服务器/引擎内部订单由 OrderGate 单独保护
	end
	if self.playerId ~= nil and self.playerId >= 0 and issuerPlayerId ~= self.playerId then
		return false
	end

	local orderType = tonumber(filterTable.order_type) or 0
	if self:IsNativeItemShopOrder(filterTable) then
		self:TraceNativeShopOrder(filterTable)
	end
	local isPurchase = orderType == DOTA_UNIT_ORDER_PURCHASE_ITEM
	local isSell = orderType == DOTA_UNIT_ORDER_SELL_ITEM
	local isDisassemble = orderType == DOTA_UNIT_ORDER_DISASSEMBLE_ITEM
	local targetIndex = tonumber(filterTable.entindex_target) or -1
	local target = targetIndex > 0 and EntIndexToHScript(targetIndex) or nil

	-- 右键待命区英雄：请求换其上场。
	if target ~= nil and target.benchHeroName ~= nil
		and (orderType == DOTA_UNIT_ORDER_MOVE_TO_TARGET or orderType == DOTA_UNIT_ORDER_ATTACK_TARGET) then
		if self.phase == "setup" then
			self:PromoteBenchHero(target.benchHeroName)
		end
		return false
	end

	local source = nil
	local sourceCount = 0
	for _, unitEntityIndex in pairs(filterTable.units or {}) do
		local candidate = EntIndexToHScript(tonumber(unitEntityIndex) or -1)
		if not self:IsEquipmentCarrier(candidate) then
			return false
		end
		source = candidate
		sourceCount = sourceCount + 1
	end
	-- 原版购买/出售有时是玩家级订单，不携带 units；其余物品操作必须来自一个明确载体。
	if sourceCount > 1 or ((not isPurchase and not isSell and not isDisassemble) and sourceCount ~= 1) then
		return false
	end

	if self.phase ~= "setup" then
		return false
	end

	if isPurchase then
		-- 购买订单在部分客户端没有 units；如果引擎同时给出一个单位目标，
		-- 仍必须确认它是小精灵或当前上阵英雄。目标为空/非单位实体时，
		-- 由 Dota 原版商店自行决定实际购买归属，不能凭项目侧猜测字段。
		if target ~= nil and target.GetItemInSlot ~= nil then
			return self:IsEquipmentCarrier(target)
		end
		-- 若 units 存在，上面的载体白名单已确保只能由小精灵/上阵英雄发起。
		return true
	end

	if isSell or isDisassemble then
		local itemIndex = tonumber(filterTable.entindex_ability) or -1
		local item = itemIndex > 0 and EntIndexToHScript(itemIndex) or nil
		if not self:IsLiveItem(item) then
			return false
		end
		-- 少数原版出售订单不带 units，按物品在我方可控载体中的真实归属补齐来源。
		local holder = source or self:FindEquipmentItemHolder(item)
		local lastSlot = holder == self:GetStashUnit() and 8 or 5
		return holder ~= nil and self:IsEquipmentCarrier(holder)
			and self:IsItemHeldBy(holder, item, 0, lastSlot)
	end

	-- 原版 HUD 的拖放、交付与地面拾取：只可在“小精灵 <-> 当前上阵英雄”之间发生。
	local isDrop = orderType == DOTA_UNIT_ORDER_DROP_ITEM
	local isPickup = orderType == DOTA_UNIT_ORDER_PICKUP_ITEM
	local isGive = orderType == DOTA_UNIT_ORDER_GIVE_ITEM
	local isMoveItem = orderType == DOTA_UNIT_ORDER_MOVE_ITEM
	if isDrop or isPickup or isGive or isMoveItem then
		if source == nil then
			return false
		end
		local function isTransferableItem(item)
			-- 普通装备已改由 Valve 原版商店出售：任何实际物品实体均可按原版规则转交。
			return self:IsLiveItem(item) and item.GetAbilityName ~= nil and item:GetAbilityName() ~= ""
		end
		if isPickup then
			-- 仅接受 Dota 物理掉落物容器，不能把另一单位背包里的物品伪装成 pickup。
			if target == nil or target.GetContainedItem == nil then
				return false
			end
			return isTransferableItem(target:GetContainedItem())
		end
		local itemIndex = tonumber(filterTable.entindex_ability) or -1
		local item = itemIndex > 0 and EntIndexToHScript(itemIndex) or nil
		local lastSlot = source == self:GetStashUnit() and 8 or 5
		if not isTransferableItem(item) or not self:IsItemHeldBy(source, item, 0, lastSlot) then
			return false
		end
		if isDrop then
			return true -- 明确持有的物品才可丢到地面
		end
		if isMoveItem then
			-- Dota MOVE_ITEM 的 TargetIndex 是目标背包槽；严格限制在来源单位自己的可用槽。
			local destinationSlot = tonumber(filterTable.entindex_target)
			return destinationSlot ~= nil and destinationSlot >= 0 and destinationSlot <= lastSlot
		end
		-- give 的 target 必须是另一个受管理的装备载体，不能交给待命/敌方/中立单位。
		return target ~= nil and target ~= source and self:IsEquipmentCarrier(target)
	end

	-- 准备阶段允许小精灵和当前上阵英雄移动；战斗/结算阶段已由 OrderFilter 完全封锁。
	local isLineupSource = self:IsLineupUnit(source)
	local isStashSource = source == self:GetStashUnit()
	if not isLineupSource and not isStashSource then
		return false
	end
	local isMoveToPoint = orderType == DOTA_UNIT_ORDER_MOVE_TO_POINT
		or orderType == DOTA_UNIT_ORDER_MOVE_TO_POSITION
	local isMove = isMoveToPoint
		or orderType == DOTA_UNIT_ORDER_MOVE_TO_TARGET
		or orderType == DOTA_UNIT_ORDER_HOLD_POSITION
	if isMove then
		if isMoveToPoint then
			local pos = filterTable.position_2 or filterTable.position
			local x = tonumber(filterTable.position_x or (pos and pos.x) or 0)
			if x ~= 0 and x > -150 then
				return false -- 不可越过中线排位
			end
			if x ~= 0 and isLineupSource then
				self.placedPositions = self.placedPositions or {}
				self.placedPositions[source:GetUnitName()] = { x = x, y = tonumber(filterTable.position_y or 0) }
			end
		end
		return true
	end

	return false
end

-- 换人：待命英雄进入首发；首发已满时替换最后一名
function CDota2RpgDemo:PromoteBenchHero(heroName)
	if self.phase ~= "setup" then
		return
	end
	for _, lineupName in ipairs(self.lineup) do
		if lineupName == heroName then
			return
		end
	end
	if #self.lineup < self.shopCosts.lineup_max then
		table.insert(self.lineup, heroName)
	else
		table.remove(self.lineup) -- 首发已满：替换最后一名
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
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
				hero:SetAcquisitionRange(BATTLE_ACQUISITION_RANGE)
			end
		end
	end

	-- 野怪关的敌方小怪没有规则行，也要解除开战前的静止状态
	for _, unit in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
		if TacticEngine.IsValidUnit(unit) and unit:IsAlive() then
			unit:SetIdleAcquire(true)
			unit:SetAcquisitionRange(BATTLE_ACQUISITION_RANGE)
		end
	end

	self:RemoveBattleBarrier()
	self.tacticBridge:ResetState()
	self.battleManager:ResetBattleStats()
	if self.placeholderHero ~= nil and TacticEngine.IsValidUnit(self.placeholderHero) then
		-- 战斗中玩家小精灵无敌，避免被敌方波及
		self.placeholderHero:AddNewModifier(self.placeholderHero, nil, "modifier_invulnerable", {})
	end
	self.battleManager:StartBattle(self.battleManager.teamRules)
	self:BroadcastBattleState()
	print("[Dota2Rpg] Battle started on level " .. self.currentLevelId .. ".")
end

function CDota2RpgDemo:OnEntityHurt(event)
	self.battleManager:RecordDamage(tonumber(event.entindex_killed or -1))
end

function CDota2RpgDemo:OnEntityKilled(event)
	if self.phase ~= "fight" then
		return
	end

	local killed = EntIndexToHScript(event.entindex_killed or -1)
	if not TacticEngine.IsValidUnit(killed) then
		return
	end

	-- 我方英雄阵亡计数（供"已阵亡友军 ≥ N"条件使用）
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]) do
		if TacticEngine.IsValidUnit(hero) and hero:GetEntityIndex() == killed:GetEntityIndex() then
			self.battleManager:RecordAllyDeath()
			break
		end
	end

	self:ScheduleStateBroadcast(0.05)
end

function CDota2RpgDemo:OnThink()
	if not self.teamsSpawned then
		local state = GameRules:State_Get()
		if state >= DOTA_GAMERULES_STATE_PRE_GAME then
			self:EnsureBattlefield()
		end
	end

	if self.phase == "setup" then
		-- 原版商店的购买/出售会直接改变 PlayerResource；先吸收余额再推送 UI，
		-- 避免旧 self.gold 把已经扣掉/返还的原版金币覆盖回去。
		self:SyncGoldFromPlayer()
		-- 原版 HUD 的购买、出售、拖放/拾取绕过自定义按钮，也要立即同步到库存与装备面板。
		self:SyncLiveEquipmentState(self.nativeShopTransactionPending)
		self.nativeShopTransactionPending = nil
	end

	if self.phase == "fight" then
		self.battleManager:OnThink() -- 胜负/超时判定
		if self.phase == "fight" then
			self.tacticBridge:OnThink()
		end
	end

	return THINK_INTERVAL
end

function CDota2RpgDemo:EndBattle(winner, winnerTeam)
	if self.phase ~= "fight" then
		return
	end

	local clearTime = self.battleManager:GetBattleTime()
	local level = self.dataLoader:GetLevel(self.currentLevelId)
	local timeLimit = tonumber(level ~= nil and level.time_limit or 120) or 120
	local reward = level ~= nil and level.reward or nil
	local baseGold = tonumber(reward ~= nil and reward.gold or 0) or 0
	local baseXp = tonumber(reward ~= nil and reward.xp_pool or 0) or 0

	-- 星级：3=全员存活 / 2=存活≥1 且 <60s / 1=险胜
	local stars = 1
	if winner == "radiant" then
		local survivors = 0
		for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]) do
			if TacticEngine.IsValidUnit(hero) and hero:IsAlive() then
				survivors = survivors + 1
			end
		end
		if survivors >= math.max(1, #self.lineup) then
			stars = 3
		elseif survivors >= 1 and clearTime < 60 then
			stars = 2
		end
	end

	-- 时间奖励：最多基础金币的 25%
	local timeBonus = 0
	if winner == "radiant" then
		local remaining = math.max(0, timeLimit - clearTime)
		local fullRate = baseGold * 0.25 / timeLimit
		timeBonus = math.min(math.floor(baseGold * TIME_BONUS_CAP + 0.5), math.floor(remaining * fullRate))
	end

	-- 唯一一次 loot_table 掉落结算：胜利时按掉落表概率 roll 入共享仓库
	local lootDrops = {}
	if winner == "radiant" then
		local lootId = level ~= nil and level.loot or nil
		local lootTable = lootId ~= nil and self.dataLoader:GetLoot(lootId) or nil
		if lootTable ~= nil then
			for _, lootEntry in pairs(lootTable.items or {}) do
				if type(lootEntry) == "table" and lootEntry.item ~= nil then
					local chance = tonumber(lootEntry.chance) or 0
					if math.random() < chance then
						if self:StashAddItem(lootEntry.item) then
							table.insert(lootDrops, lootEntry.item)
						end
					end
				end
			end
		end
	end

	local settlement = {
		level = self.currentLevelId,
		winner = winner,
		gold = winner == "radiant" and (baseGold + timeBonus) or 0,
		base_gold = baseGold,
		time_bonus = timeBonus,
		xp_pool = baseXp,
		stars = stars,
		clear_time = math.floor(clearTime),
		loot_text = table.concat(lootDrops, ";"),
	}
	-- 唯一一次奖励：胜利即入账（金币），经验池分配给全部已拥有英雄
	if winner == "radiant" then
		self:AddGold(settlement.gold)
		self:DistributeXpPool(baseXp)
	end

	self.phase = "result"
	self.winner = winner
	self.battleManager:StopBattle()
	self:BroadcastBattleState()
	CustomGameEventManager:Send_ServerToAllClients("rpg_settlement", settlement)

	-- 闯关推进：胜利指向下一关（进入下一关时重置刷新费用与卷轴限购）
	if winner == "radiant" then
		for index, levelId in ipairs(self.orderedLevels) do
			if levelId == self.currentLevelId and self.orderedLevels[index + 1] ~= nil then
				self.currentLevelId = self.orderedLevels[index + 1]
				break
			end
		end
		self.refreshCount = 0
		self.scrollPurchases = { low = 0, high = 0 }
	end

	-- 单人闯关：结算展示 3 秒后回到准备阶段（不结束整局游戏）
	GameRules:GetGameModeEntity():SetContextThink("Dota2RpgBackToSetup", function()
		self.phase = "setup"
		self.winner = ""
		if self.placeholderHero ~= nil and TacticEngine.IsValidUnit(self.placeholderHero) then
			self.placeholderHero:RemoveModifierByName("modifier_invulnerable")
		end
		self:SpawnLevelEnemies(self.currentLevelId)
		self:RespawnPlayerRoster()
		self:SpawnBattleBarrier()
		self:BroadcastShopState()
		self:BroadcastLevelInfo()
		self:BroadcastBattleState()
		print("[Dota2Rpg] Back to setup. Next level: " .. self.currentLevelId)
		return nil
	end, 3.0)

	print(string.format("[Dota2Rpg] Battle finished. Result=%s Stars=%d Gold=%d(+%d) XpPool=%d",
		winner, stars, settlement.gold, timeBonus, baseXp))
end

------------------------------------------------------------------
-- 状态广播
------------------------------------------------------------------

-- 每个英雄的可用动作槽（含主动装备）同步给前端
-- 把 action（ability_N / item_N / ultimate / attack）解析成可显示的名字
local function DescribeAction(hero, action)
	if action == "attack" then
		return "attack", ""
	end
	if action == "ultimate" then
		for slot = 0, hero:GetAbilityCount() - 1 do
			local ability = hero:GetAbilityByIndex(slot)
			if ability ~= nil and not ability:IsNull() and ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
				return "ultimate", ability:GetAbilityName()
			end
		end
		return "ultimate", ""
	end
	local abilitySlot = tonumber(string.match(action, "ability_(%d)"))
	if abilitySlot ~= nil then
		local ability = hero:GetAbilityByIndex(abilitySlot - 1)
		if ability ~= nil and not ability:IsNull() then
			return "ability", ability:GetAbilityName()
		end
		return "ability", ""
	end
	local itemSlot = tonumber(string.match(action, "item_(%d)"))
	if itemSlot ~= nil and hero.GetItemInSlot ~= nil then
		local item = hero:GetItemInSlot(itemSlot - 1)
		if item ~= nil and not item:IsNull() then
			return "item", item:GetAbilityName()
		end
		return "item", ""
	end
	return "attack", ""
end

function CDota2RpgDemo:BroadcastHeroInfo()
	local sides = {
		{ key = "radiant", team = DOTA_TEAM_GOODGUYS },
		{ key = "dire", team = DOTA_TEAM_BADGUYS },
	}
	for _, side in ipairs(sides) do
		local heroes = self.battleManager.teamHeroes[side.team]
		for index, hero in ipairs(heroes) do
			if TacticEngine.IsValidUnit(hero) then
				local descriptions = {}
				local slots = BuildHeroActionSlots(hero)
				for _, action in ipairs(slots) do
					local _, detail = DescribeAction(hero, action)
					table.insert(descriptions, detail ~= "" and detail or action)
				end
				-- 10 槽：动作循环补齐图标映射
				for i = #slots + 1, RULE_COUNT do
					table.insert(descriptions, descriptions[((i - 1) % #slots) + 1])
				end
				CustomGameEventManager:Send_ServerToAllClients("rpg_hero_slots", {
					slot_key = side.key .. "_" .. index,
					hero_name = hero:GetUnitName(),
					actions_text = table.concat(slots, ";"),
					details_text = table.concat(descriptions, ";"),
				})
			end
		end
	end
end

-- 金币写入玩家钱包，Dota 原版 HUD 经济面板即可正常显示。
function CDota2RpgDemo:SyncGoldToPlayer()
	self:SetGoldBalance(self.gold)
end

function CDota2RpgDemo:BroadcastShopState()
	-- 先从原版钱包读取，再推送项目 HUD；绝不把旧 self.gold 回写为商店余额。
	local gold = self:GetGoldBalance()
	-- CEM 载荷一律拍平；英雄数据用 "name:level:xp:quality" 分号串
	local heroEntries = {}
	for _, heroName in ipairs(self.ownedHeroes) do
		local d = self.heroData[heroName]
		table.insert(heroEntries, heroName .. ":" .. (d ~= nil and d.level or 1) .. ":" .. (d ~= nil and d.current_xp or 0) .. ":" .. (d ~= nil and d.quality or "common") .. ":" .. (d ~= nil and (d.skill_points or d.level) or 1) .. ":" .. table.concat((d ~= nil and d.inventory) or {}, ","))
	end
	local stockParts = {}
	local stash = self:GetStashUnit()
	if stash ~= nil then
		for slot = 0, 8 do
			local item = stash:GetItemInSlot(slot)
			if item ~= nil and not item:IsNull() then
				local itemName = item:GetAbilityName()
				-- UI 操作只需要真实实体 ID；价格与出售均由 Valve 原版商店负责。
				table.insert(stockParts, itemName .. "|" .. self:GetItemEntityId(item))
			end
		end
	end
	local inventoryParts = {}
	local equippedParts = {}
	for index, heroName in ipairs(self.lineup) do
		local d = self.heroData[heroName]
		table.insert(inventoryParts, heroName .. ":" .. table.concat((d ~= nil and d.inventory) or {}, ","))
		local hero = self:FindLineupUnit(heroName)
		local heroItems = {}
		if hero ~= nil and hero.GetItemInSlot ~= nil then
			for slot = 0, 5 do
				local item = hero:GetItemInSlot(slot)
				if self:IsLiveItem(item) then
					table.insert(heroItems, item:GetAbilityName() .. "|" .. self:GetItemEntityId(item))
				end
			end
		end
		table.insert(equippedParts, heroName .. ":" .. table.concat(heroItems, ","))
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_shop_state", {
		gold = gold,
		offer_text = self.shopOfferText or "",
		owned_text = table.concat(self.ownedHeroes, ";"),
		hero_data_text = table.concat(heroEntries, ";"),
		lineup_text = table.concat(self.lineup, ";"),
		bench_slots = self.benchSlots,
		refresh_cost = self:GetRefreshCost(),
		scroll_low_remaining = self:GetScrollRemaining("low"),
		scroll_high_remaining = self:GetScrollRemaining("high"),
		scroll_low_stock = self.scrollStock.low or 0,
		scroll_high_stock = self.scrollStock.high or 0,
		stock_text = table.concat(stockParts, ";"),
		inventories_text = table.concat(inventoryParts, ";"),
		equipped_text = table.concat(equippedParts, ";"),
		cost_bench_slot = self.shopCosts.bench_slot,
		bench_slot_max = self.shopCosts.bench_slot_max,
		lineup_max = self.shopCosts.lineup_max,
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
		hide_ui = self.phase ~= "setup",
		battle_time = math.floor(self.battleManager:GetBattleTime()),
		time_limit = tonumber(self.dataLoader:GetLevel(self.currentLevelId) ~= nil and self.dataLoader:GetLevel(self.currentLevelId).time_limit or 120) or 120,
		level = self.currentLevelId,
		gold = self:GetGoldBalance(),
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