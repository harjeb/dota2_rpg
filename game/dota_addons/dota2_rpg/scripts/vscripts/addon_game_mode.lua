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
XP_TO_NEXT_BASE = 40
XP_TO_NEXT_STEP = 30
TIME_BONUS_CAP = 0.25

-- 商店与阵容经济（需求：开局 300 金币，英雄 100/个，刷新 20/次，替补格 200/个）
local SHOP_HERO_COST = 100
local SHOP_REFRESH_COST = 20
local SHOP_BENCH_SLOT_COST = 200
local BENCH_SLOT_MAX = 5
local LINEUP_MAX = 5
local INITIAL_GOLD = 300
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
	local seenUnits = {}
	local function PrecacheUnit(unitName)
		if type(unitName) ~= "string" or string.sub(unitName, 1, 9) ~= "npc_dota_" or seenUnits[unitName] then
			return
		end
		seenUnits[unitName] = true
		PrecacheUnitByNameSync(unitName, context)
	end

	PrecacheUnit(PLAYER_PLACEHOLDER_HERO)

	-- 官方英雄资源在游戏 VPK 内，无需逐个同步预缓存（112 个会拖慢加载）

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

	-- 经济/商店/阵容（服务端为金币权威，客户端存档仅镜像）
	self.gold = self.shopCosts.initial_gold
	self.ownedHeroes = {}   -- 名字列表，招募顺序
	-- 个人等级/经验：heroData[name] = { level, current_xp, quality, order }
	self.heroData = {}
	self.heroOrder = 0
	self.scrollPurchases = { low = 0, high = 0 }  -- 当前关已购数量
	self.lineup = {}
	self.benchSlots = 0
	self.shopOffer = {}
	self.refreshCount = 0
	self.scrollStock = { low = 0, high = 0 }
	self.scrollBought = { low = 0, high = 0 }
	self.attemptBuybacks = 0
	self.encounterSeed = nil
	self.heroRulesByName = {}
	-- 装备商店：目录价格（运行时读取当前 Dota 物价）+ 队伍共享库存池
	self.itemCatalog = {}
	self.itemStock = {}
	self.heroInventories = {}  -- heroData[hero].inventory = { item, ... } 由 heroData 持有

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
	ListenToGameEvent("entity_hurt", Dynamic_Wrap(CDota2RpgDemo, "OnEntityHurt"), self)

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
	CustomGameEventManager:RegisterListener("rpg_scroll_buy", function(eventSourceIndex, payload)
		return self:OnScrollBuy(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_scroll_use", function(eventSourceIndex, payload)
		return self:OnScrollUse(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_item_buy", function(eventSourceIndex, payload)
		return self:OnItemBuy(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_item_sell", function(eventSourceIndex, payload)
		return self:OnItemSell(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_item_equip", function(eventSourceIndex, payload)
		return self:OnItemEquip(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_item_unequip", function(eventSourceIndex, payload)
		return self:OnItemUnequip(eventSourceIndex, payload)
	end)

	PlayerResource:SetCustomTeamAssignment(0, DOTA_TEAM_GOODGUYS)
	self:RollShop()
	print("[Dota2Rpg] BUILD rpg-shop-lineup-v2 loaded. Setup disabled, shop enabled.")
	print("[Dota2Rpg] Shop + lineup + TacticEngine initialized.")
end

-- 读取当前 Dota 物品价格（目录内逐件创建临时物品取价）
function CDota2RpgDemo:BuildItemPrices()
	local data = LoadKeyValues("scripts/data/items.kv")
	if data == nil or data.catalog == nil then
		print("[Dota2Rpg] WARNING: items.kv catalog missing.")
		return
	end
	-- 静态价格表（随 Dota 版本物价更新 items.kv）；运行时 CreateItemByName 在工具环境不可用
	for _, entry in pairs(data.catalog) do
		if type(entry) == "table" and type(entry.name) == "string" then
			self.itemCatalog[entry.name] = tonumber(entry.cost) or 0
		end
	end
	print("[Dota2Rpg] Item prices loaded: " .. self:CountTable(self.itemCatalog) .. " items.")
end

function CDota2RpgDemo:CountTable(t)
	local count = 0
	for _ in pairs(t or {}) do
		count = count + 1
	end
	return count
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
	for _, category in ipairs(SHOP_CATEGORIES) do
		for _, hero in pairs(data[category] or {}) do
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
	while #offer < self.shopCosts.lineup_max + 0 and #allHeroes > #offer do
		local candidate = allHeroes[math.random(#allHeroes)]
		local duplicate = false
		for _, existing in ipairs(offer) do
			if existing == candidate then
				duplicate = true
				break
			end
		end
		if not duplicate then
			table.insert(offer, candidate)
		else
			break
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
	if self.gold < cost then
		return
	end
	self.gold = self.gold - cost
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
	if self.gold < offer.price then
		return
	end
	if #self.ownedHeroes >= self.shopCosts.lineup_max + self.shopCosts.bench_slot_max then
		return -- 10 格上限
	end

	self.gold = self.gold - offer.price
	table.insert(self.ownedHeroes, heroName)
	local data = self:GetHeroData(heroName)
	data.level = offer.level
	data.current_xp = 0
	data.quality = offer.quality
	self.heroRulesByName[heroName] = self.heroRulesByName[heroName] or CloneDefaultRules()

	if #self.lineup < self.shopCosts.lineup_max then
		table.insert(self.lineup, heroName)
	else
		local benchCount = #self.ownedHeroes - #self.lineup
		if benchCount > self.benchSlots then
			table.remove(self.ownedHeroes)
			self.gold = self.gold + offer.price
			self.heroData[heroName] = nil
			return
		end
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
	if self.gold < SCROLL_COST[kind] then
		return
	end
	self.gold = self.gold - SCROLL_COST[kind]
	self.scrollPurchases[kind] = (self.scrollPurchases[kind] or 0) + 1
	self.scrollStock[kind] = (self.scrollStock[kind] or 0) + 1
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnScrollUse(_, payload)
	if self.phase == "fight" then
		return -- 战斗中不可使用
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
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

------------------------------------------------------------------
-- 装备商店：原价购买 / 50% 回收 / 队伍共享库存 / 准备阶段穿脱
------------------------------------------------------------------

function CDota2RpgDemo:GetItemCost(itemName)
	return self.itemCatalog[itemName] or 0
end

function CDota2RpgDemo:OnItemBuy(_, payload)
	if self.phase ~= "setup" then
		return -- 战斗进行中关闭装备购买
	end
	local itemName = payload ~= nil and tostring(payload.item or "") or ""
	local cost = self:GetItemCost(itemName)
	if cost <= 0 or self.gold < cost then
		return
	end
	self.gold = self.gold - cost
	table.insert(self.itemStock, itemName)
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemSell(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local index = tonumber(payload ~= nil and payload.index or 0) or 0
	local itemName = self.itemStock[index]
	if itemName == nil then
		return
	end
	table.remove(self.itemStock, index)
	self.gold = self.gold + math.floor(self:GetItemCost(itemName) * 0.5)
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemEquip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local index = tonumber(payload.index or 0) or 0
	local itemName = self.itemStock[index]
	if itemName == nil or self.heroData[heroName] == nil then
		return
	end
	local heroUnit = self:FindLineupUnit(heroName)
	if heroUnit == nil then
		return
	end
	-- 找空物品栏（0..5，不含中立/储备）
	for slot = 0, 5 do
		if heroUnit:GetItemInSlot(slot) == nil then
			local item = heroUnit:AddItemByName(itemName)
			if item ~= nil and not item:IsNull() then
				table.remove(self.itemStock, index)
				table.insert(self.heroData[heroName].inventory, itemName)
			end
			break
		end
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemUnequip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local slot = tonumber(payload.slot or -1) or -1
	local heroUnit = self:FindLineupUnit(heroName)
	if heroUnit == nil or slot < 0 or slot > 5 then
		return
	end
	local item = heroUnit:GetItemInSlot(slot)
	if item == nil then
		return
	end
	table.insert(self.itemStock, item:GetAbilityName())
	UTIL_Remove(item)
	for i, name in ipairs(self.heroData[heroName].inventory) do
		if name == item:GetAbilityName() then
			table.remove(self.heroData[heroName].inventory, i)
			break
		end
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
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
	data.current_xp = data.current_xp + amount
	while data.level < HERO_LEVEL do
		local need = XP_TO_NEXT_BASE + XP_TO_NEXT_STEP * data.level
		if data.current_xp >= need then
			data.current_xp = data.current_xp - need
			data.level = data.level + 1
		else
			break
		end
	end
	if data.level >= HERO_LEVEL then
		data.current_xp = 0
	end
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

-- 客户端存档同步（单人 MVP：信任客户端 LocalStorage，覆盖服务端状态）
-- CEM 载荷列表（分号分隔字符串）拆回 Lua 数组
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

function CDota2RpgDemo:OnSaveSync(_, payload)
	if self.phase ~= "setup" or payload == nil then
		return
	end
	if payload.gold ~= nil then
		self.gold = math.max(0, math.floor(tonumber(payload.gold) or 0))
	end
	if payload.hero_data_text ~= nil then
		self.ownedHeroes = {}
		self.heroData = {}
		self.heroOrder = 0
		self.lineup = {}
		for entry in string.gmatch(tostring(payload.hero_data_text), "[^;]+") do
			local name, level, xp, quality, itemsText = string.match(entry, "^(.+):(%d+):(%d+):(%a+):?(.*)$")
			if name ~= nil then
				table.insert(self.ownedHeroes, name)
				self.heroOrder = self.heroOrder + 1
				local inventory = {}
				for itemName in string.gmatch(itemsText or "", "[^,]+") do
					table.insert(inventory, itemName)
				end
				self.heroData[name] = {
					level = math.max(1, math.min(HERO_LEVEL, tonumber(level) or 1)),
					current_xp = math.max(0, tonumber(xp) or 0),
					quality = quality,
					order = self.heroOrder,
					inventory = inventory,
				}
			end
		end
	end
	local savedLineup = self:ReadPayloadList(payload, "lineup_text")
	if #savedLineup > 0 then
		self.lineup = savedLineup
	end
	if payload.bench_slots ~= nil then
		self.benchSlots = math.max(0, math.min(self.shopCosts.bench_slot_max, math.floor(tonumber(payload.bench_slots) or 0)))
	end
	if payload.refresh_count ~= nil then
		self.refreshCount = math.max(0, math.floor(tonumber(payload.refresh_count) or 0))
	end
	if payload.stock_text ~= nil then
		self.itemStock = self:ReadPayloadList(payload, "stock_text")
	end
	if payload.scroll_stock_low ~= nil then
		self.scrollStock.low = math.max(0, math.floor(tonumber(payload.scroll_stock_low) or 0))
	end
	if payload.scroll_stock_high ~= nil then
		self.scrollStock.high = math.max(0, math.floor(tonumber(payload.scroll_stock_high) or 0))
	end
	if payload.current_level ~= nil then
		local levelId = tostring(payload.current_level)
		if self.dataLoader:GetLevel(levelId) ~= nil then
			self.currentLevelId = levelId
		end
	end
	-- 遭遇种子：首次解锁生成并持久化，重试不更换
	if payload.encounter_seed ~= nil and tonumber(payload.encounter_seed) ~= 0 then
		self.encounterSeed = tonumber(payload.encounter_seed)
	elseif self.encounterSeed == nil then
		self.encounterSeed = math.random(1, 2147483647)
	end
	math.randomseed(self.encounterSeed)
	self:RollShop()
	self:RespawnPlayerRoster()
end

function CDota2RpgDemo:OnScrollBuy(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local kind = payload ~= nil and tostring(payload.kind or "low") or "low"
	if SCROLL_COST[kind] == nil or self:GetScrollRemaining(kind) <= 0 then
		return
	end
	if self.gold < SCROLL_COST[kind] then
		return
	end
	self.gold = self.gold - SCROLL_COST[kind]
	self.scrollPurchases[kind] = (self.scrollPurchases[kind] or 0) + 1
	self.scrollStock[kind] = (self.scrollStock[kind] or 0) + 1
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnScrollUse(_, payload)
	if self.phase == "fight" then
		return -- 战斗中不可使用
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
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

------------------------------------------------------------------
-- 装备商店：原价购买 / 50% 回收 / 队伍共享库存 / 准备阶段穿脱
------------------------------------------------------------------

function CDota2RpgDemo:GetItemCost(itemName)
	return self.itemCatalog[itemName] or 0
end

function CDota2RpgDemo:OnItemBuy(_, payload)
	if self.phase ~= "setup" then
		return -- 战斗进行中关闭装备购买
	end
	local itemName = payload ~= nil and tostring(payload.item or "") or ""
	local cost = self:GetItemCost(itemName)
	if cost <= 0 or self.gold < cost then
		return
	end
	self.gold = self.gold - cost
	table.insert(self.itemStock, itemName)
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemSell(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local index = tonumber(payload ~= nil and payload.index or 0) or 0
	local itemName = self.itemStock[index]
	if itemName == nil then
		return
	end
	table.remove(self.itemStock, index)
	self.gold = self.gold + math.floor(self:GetItemCost(itemName) * 0.5)
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemEquip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local index = tonumber(payload.index or 0) or 0
	local itemName = self.itemStock[index]
	if itemName == nil or self.heroData[heroName] == nil then
		return
	end
	local heroUnit = self:FindLineupUnit(heroName)
	if heroUnit == nil then
		return
	end
	-- 找空物品栏（0..5，不含中立/储备）
	for slot = 0, 5 do
		if heroUnit:GetItemInSlot(slot) == nil then
			local item = heroUnit:AddItemByName(itemName)
			if item ~= nil and not item:IsNull() then
				table.remove(self.itemStock, index)
				table.insert(self.heroData[heroName].inventory, itemName)
			end
			break
		end
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemUnequip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local slot = tonumber(payload.slot or -1) or -1
	local heroUnit = self:FindLineupUnit(heroName)
	if heroUnit == nil or slot < 0 or slot > 5 then
		return
	end
	local item = heroUnit:GetItemInSlot(slot)
	if item == nil then
		return
	end
	table.insert(self.itemStock, item:GetAbilityName())
	UTIL_Remove(item)
	for i, name in ipairs(self.heroData[heroName].inventory) do
		if name == item:GetAbilityName() then
			table.remove(self.heroData[heroName].inventory, i)
			break
		end
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
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
	data.current_xp = data.current_xp + amount
	while data.level < HERO_LEVEL do
		local need = XP_TO_NEXT_BASE + XP_TO_NEXT_STEP * data.level
		if data.current_xp >= need then
			data.current_xp = data.current_xp - need
			data.level = data.level + 1
		else
			break
		end
	end
	if data.level >= HERO_LEVEL then
		data.current_xp = 0
	end
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

-- 客户端存档同步（单人 MVP：信任客户端 LocalStorage，覆盖服务端状态）
-- CEM 载荷列表（分号分隔字符串）拆回 Lua 数组
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
	local owned = ReadPayloadList(payload, "owned_text", "owned")
	if owned ~= nil then
		self.ownedHeroes = owned
	end
	local lineup = ReadPayloadList(payload, "lineup_text", "lineup")
	if lineup ~= nil then
		self.lineup = lineup
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

-- 客户端存档迁移：heroes_text = "name:level:xp:quality;..."
function CDota2RpgDemo:OnHeroLevels(_, payload)
	if payload == nil or payload.heroes_text == nil then
		return
	end
	self.ownedHeroes = {}
	self.heroData = {}
	self.lineup = {}
	for entry in string.gmatch(tostring(payload.heroes_text), "[^;]+") do
		local name, level, xp, quality = string.match(entry, "^(.+):(%d+):(%d+):(%a+)$")
		if name ~= nil then
			table.insert(self.ownedHeroes, name)
			self.heroOrder = self.heroOrder + 1
			self.heroData[name] = {
				level = math.max(1, math.min(HERO_LEVEL, tonumber(level) or 1)),
				current_xp = math.max(0, tonumber(xp) or 0),
				quality = quality,
				order = self.heroOrder,
			}
		end
	end
	if payload.lineup ~= nil then
		for _, heroName in pairs(payload.lineup) do
			table.insert(self.lineup, tostring(heroName))
		end
	end
	if self.phase == "setup" and self.teamsSpawned then
		self:RespawnPlayerRoster()
	end
end


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
	while #offer < self.shopCosts.lineup_max + 0 and #allHeroes > #offer do
		local candidate = allHeroes[math.random(#allHeroes)]
		local duplicate = false
		for _, existing in ipairs(offer) do
			if existing == candidate then
				duplicate = true
				break
			end
		end
		if not duplicate then
			table.insert(offer, candidate)
		else
			break
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
	if self.gold < cost then
		return
	end
	self.gold = self.gold - cost
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
	if self.gold < offer.price then
		return
	end
	if #self.ownedHeroes >= self.shopCosts.lineup_max + self.shopCosts.bench_slot_max then
		return -- 10 格上限
	end

	self.gold = self.gold - offer.price
	table.insert(self.ownedHeroes, heroName)
	local data = self:GetHeroData(heroName)
	data.level = offer.level
	data.current_xp = 0
	data.quality = offer.quality
	self.heroRulesByName[heroName] = self.heroRulesByName[heroName] or CloneDefaultRules()

	if #self.lineup < self.shopCosts.lineup_max then
		table.insert(self.lineup, heroName)
	else
		local benchCount = #self.ownedHeroes - #self.lineup
		if benchCount > self.benchSlots then
			table.remove(self.ownedHeroes)
			self.gold = self.gold + offer.price
			self.heroData[heroName] = nil
			return
		end
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
	if self.gold < SCROLL_COST[kind] then
		return
	end
	self.gold = self.gold - SCROLL_COST[kind]
	self.scrollPurchases[kind] = (self.scrollPurchases[kind] or 0) + 1
	self.scrollStock[kind] = (self.scrollStock[kind] or 0) + 1
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnScrollUse(_, payload)
	if self.phase == "fight" then
		return -- 战斗中不可使用
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
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

------------------------------------------------------------------
-- 装备商店：原价购买 / 50% 回收 / 队伍共享库存 / 准备阶段穿脱
------------------------------------------------------------------

function CDota2RpgDemo:GetItemCost(itemName)
	return self.itemCatalog[itemName] or 0
end

function CDota2RpgDemo:OnItemBuy(_, payload)
	if self.phase ~= "setup" then
		return -- 战斗进行中关闭装备购买
	end
	local itemName = payload ~= nil and tostring(payload.item or "") or ""
	local cost = self:GetItemCost(itemName)
	if cost <= 0 or self.gold < cost then
		return
	end
	self.gold = self.gold - cost
	table.insert(self.itemStock, itemName)
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemSell(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local index = tonumber(payload ~= nil and payload.index or 0) or 0
	local itemName = self.itemStock[index]
	if itemName == nil then
		return
	end
	table.remove(self.itemStock, index)
	self.gold = self.gold + math.floor(self:GetItemCost(itemName) * 0.5)
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemEquip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local index = tonumber(payload.index or 0) or 0
	local itemName = self.itemStock[index]
	if itemName == nil or self.heroData[heroName] == nil then
		return
	end
	local heroUnit = self:FindLineupUnit(heroName)
	if heroUnit == nil then
		return
	end
	-- 找空物品栏（0..5，不含中立/储备）
	for slot = 0, 5 do
		if heroUnit:GetItemInSlot(slot) == nil then
			local item = heroUnit:AddItemByName(itemName)
			if item ~= nil and not item:IsNull() then
				table.remove(self.itemStock, index)
				table.insert(self.heroData[heroName].inventory, itemName)
			end
			break
		end
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
end

function CDota2RpgDemo:OnItemUnequip(_, payload)
	if self.phase ~= "setup" then
		return
	end
	local heroName = payload ~= nil and tostring(payload.hero or "") or ""
	local slot = tonumber(payload.slot or -1) or -1
	local heroUnit = self:FindLineupUnit(heroName)
	if heroUnit == nil or slot < 0 or slot > 5 then
		return
	end
	local item = heroUnit:GetItemInSlot(slot)
	if item == nil then
		return
	end
	table.insert(self.itemStock, item:GetAbilityName())
	UTIL_Remove(item)
	for i, name in ipairs(self.heroData[heroName].inventory) do
		if name == item:GetAbilityName() then
			table.remove(self.heroData[heroName].inventory, i)
			break
		end
	end
	self:RespawnPlayerRoster()
	self:BroadcastShopState()
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
	data.current_xp = data.current_xp + amount
	while data.level < HERO_LEVEL do
		local need = XP_TO_NEXT_BASE + XP_TO_NEXT_STEP * data.level
		if data.current_xp >= need then
			data.current_xp = data.current_xp - need
			data.level = data.level + 1
		else
			break
		end
	end
	if data.level >= HERO_LEVEL then
		data.current_xp = 0
	end
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

-- 客户端存档同步（单人 MVP：信任客户端 LocalStorage，覆盖服务端状态）
-- CEM 载荷列表（分号分隔字符串）拆回 Lua 数组
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
	local owned = ReadPayloadList(payload, "owned_text", "owned")
	if owned ~= nil then
		self.ownedHeroes = owned
	end
	local lineup = ReadPayloadList(payload, "lineup_text", "lineup")
	if lineup ~= nil then
		self.lineup = lineup
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



function CDota2RpgDemo:EnsureBattlefield()
	if self.teamsSpawned then
		return
	end

	self.teamsSpawned = true
	if next(self.itemCatalog) == nil then
		pcall(function()
			self:BuildItemPrices()
		end)
	end
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
			-- 重铸前把身上的装备收回个人库存记录，避免随单位销毁
			local heroName = hero:GetUnitName()
			local data = self.heroData[heroName]
			if data ~= nil then
				data.inventory = data.inventory or {}
				for slot = 0, 5 do
					local item = hero:GetItemInSlot(slot)
					if item ~= nil and not item:IsNull() then
						local itemName = item:GetAbilityName()
						local alreadyRecorded = false
						for _, recorded in ipairs(data.inventory) do
							if recorded == itemName then
								alreadyRecorded = true
								break
							end
						end
						if not alreadyRecorded then
							table.insert(data.inventory, itemName)
						end
						UTIL_Remove(item)
					end
				end
			end
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
			local heroData = self.heroData[heroName]
			self:PrepareBattleHero(hero, heroData ~= nil and heroData.level or 1)
			-- 重新佩戴个人装备
			heroData.inventory = heroData.inventory or {}
			for _, itemName in ipairs(heroData.inventory) do
				if #heroData.inventory <= 6 then
					hero:AddItemByName(itemName)
				end
			end
			-- 品质内置升级：魔晶/神杖（不占装备栏）
			if heroData ~= nil and QUALITY_CONSUMED_MODIFIERS[heroData.quality] ~= nil then
				for _, modifierName in ipairs(QUALITY_CONSUMED_MODIFIERS[heroData.quality]) do
					hero:AddNewModifier(hero, nil, modifierName, {})
				end
			end
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

	-- 技能加点：与正常模式一致——普通技能可用等级=ceil(level/2)，大招需 6/12/18 级；
	-- 加点后清空技能点，避免 1 级英雄带满技能+剩余点数
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

	self.battleManager:ResetBattleStats()
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
						table.insert(self.itemStock, lootEntry.item)
						table.insert(lootDrops, lootEntry.item)
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
		self.gold = self.gold + settlement.gold
		self:DistributeXpPool(baseXp)
		self:SyncGoldToPlayer()
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
		self:SpawnLevelEnemies(self.currentLevelId)
		self:RespawnPlayerRoster()
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
	local heroes = self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]
	for index, hero in ipairs(heroes) do
		if TacticEngine.IsValidUnit(hero) then
			local descriptions = {}
			for _, action in ipairs(BuildHeroActionSlots(hero)) do
				local _, detail = DescribeAction(hero, action)
				table.insert(descriptions, detail ~= "" and detail or action)
			end
			CustomGameEventManager:Send_ServerToAllClients("rpg_hero_slots", {
				slot_key = "radiant_" .. index,
				hero_name = self.lineup[index] or "",
				actions_text = table.concat(BuildHeroActionSlots(hero), ";"),
				details_text = table.concat(descriptions, ";"),
			})
		end
	end
end

-- 金币写入玩家钱包，Dota 原版 HUD 经济面板即可正常显示
function CDota2RpgDemo:SyncGoldToPlayer()
	if self.playerId >= 0 then
		PlayerResource:SetGold(self.playerId, self.gold, true)
	end
end

function CDota2RpgDemo:BroadcastShopState()
	self:SyncGoldToPlayer()
	-- CEM 载荷一律拍平；英雄数据用 "name:level:xp:quality" 分号串
	local heroEntries = {}
	for _, heroName in ipairs(self.ownedHeroes) do
		local d = self.heroData[heroName]
		table.insert(heroEntries, heroName .. ":" .. (d ~= nil and d.level or 1) .. ":" .. (d ~= nil and d.current_xp or 0) .. ":" .. (d ~= nil and d.quality or "common") .. ":" .. table.concat((d ~= nil and d.inventory) or {}, ","))
	end
	local stockParts = {}
	for _, itemName in ipairs(self.itemStock) do
		table.insert(stockParts, itemName .. "|" .. self:GetItemCost(itemName))
	end
	local catalogParts = {}
	for itemName, cost in pairs(self.itemCatalog) do
		table.insert(catalogParts, itemName .. "|" .. cost)
	end
	table.sort(catalogParts)
	local inventoryParts = {}
	for index, heroName in ipairs(self.lineup) do
		local d = self.heroData[heroName]
		table.insert(inventoryParts, heroName .. ":" .. table.concat((d ~= nil and d.inventory) or {}, ","))
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_shop_state", {
		gold = self.gold,
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
		item_catalog = table.concat(catalogParts, ";"),
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