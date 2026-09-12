local okHelpers, UnitHelpers = pcall(require, "battle.unit_helpers")
if not okHelpers then
	-- 离线回归脚本可在加载 addon 后注入自己的 helper；正式地图必须成功加载模块。
	UnitHelpers = {
		IsValidUnit = function(unit)
			return _G.TacticEngine ~= nil and _G.TacticEngine.IsValidUnit(unit)
		end,
	}
end
local TacticEngine = UnitHelpers
local DamageStats = require("battle.damage_stats")
local AbilityCatalog = require("tactics/ability_catalog")
local RuleSnapshot = require("tactics/rule_snapshot")
local EnemyScaling = require("battle.enemy_scaling")
local BossScaling = require("battle.boss_scaling")
local StagePrecache = require("battle.stage_precache")
local HeroModelPrecache = require("battle.hero_model_precache")
local RunLives = require("battle.run_lives")
local CampaignLoot = require("battle.campaign_loot")
local TempestDouble = require("battle.tempest_double")
local SpecialTargets = require("tactics/special_targets")
local SummonBehavior = require("battle/summon_behavior")
local TinyTree = require("issue_fixes/tiny_tree")
local EnemyDiagnostics = require("battle.enemy_diagnostics")
local SkillDebug = require("battle.skill_debug")
local RespawnPolicy = require("battle.respawn_policy")
local ItemSales = require("issue_fixes/item_sales")
local ShardPurchase = require("issue_fixes/shard_purchase")
local GrisGris = require("issue_fixes/gris_gris")
local JinadaIncome = require("issue_fixes/jinada_income")
local HeroAbilityPolicy = require("issue_fixes/hero_ability_policy")
local okRuntimeLog, RuntimeLog = pcall(require, "issue_fixes.runtime_log")
if not okRuntimeLog then RuntimeLog = { Write = print } end
local Traceback = RuntimeLog.Traceback or tostring
local okItems = pcall(require, "items") -- item_lua 经验卷轴的 OnSpellStart
local okProgression, ProgressionData = pcall(require, "data.progression_data")
local okRecruitmentPatch, RecruitmentPatch = pcall(require, "patches.recruitment_patch")
local okProgressionPatch, ProgressionPatch = pcall(require, "patches.progression_patch")
local okEnemyItems, EnemyItems = pcall(require, "patches.enemy_items_patch")
local okBridge = pcall(require, "tactics.tactic_bridge")
local okBattle = pcall(require, "battle.battle_manager")
local okData = pcall(require, "data.data_loader")
if not okProgression then ProgressionData = nil end
if not okRecruitmentPatch then RecruitmentPatch = nil end
if not okProgressionPatch then ProgressionPatch = nil end
if not okEnemyItems then EnemyItems = nil end
print(string.format("[Dota2Rpg] requires: helpers=%s items=%s progression=%s recruitment_patch=%s progression_patch=%s enemy_items=%s tactic_bridge=%s battle_manager=%s data_loader=%s",
	tostring(okHelpers), tostring(okItems), tostring(okProgression), tostring(okRecruitmentPatch), tostring(okProgressionPatch), tostring(okEnemyItems), tostring(okBridge), tostring(okBattle), tostring(okData)))

if CDota2RpgDemo == nil then
	_G.CDota2RpgDemo = class({})
end

if okRecruitmentPatch and okProgressionPatch then
	RecruitmentPatch.Install(CDota2RpgDemo)
	ProgressionPatch.Install(CDota2RpgDemo)
end

-- 引擎在地图加载期传给 Precache(context) 的预加载上下文。它是唯一有效的上下文：
-- 地图加载之后任何预加载调用都会被原版拒绝，所以模型只能在这里加载。
local PRECACHE_CONTEXT = nil

-- npc_heroes.txt 的 英雄名 -> 模型路径。只在地图加载期解析一次。
local HERO_MODEL_PATHS = nil

local function HeroModelPaths()
	if HERO_MODEL_PATHS ~= nil then
		return HERO_MODEL_PATHS
	end
	local paths, count = {}, 0
	local kvOk, kv = pcall(LoadKeyValues, "scripts/npc/npc_heroes.txt")
	if kvOk and type(kv) == "table" then
		local root = kv.DOTAHeroes or kv
		for heroName, row in pairs(root) do
			if type(row) == "table" and type(row.Model) == "string" and row.Model ~= "" then
				paths[heroName] = row.Model
				count = count + 1
			end
		end
	end
	HERO_MODEL_PATHS = paths
	print(string.format("[RPGPrecache] hero_model_paths=%d kv_ok=%s", count, tostring(kvOk)))
	return paths
end

local PLAYER_PLACEHOLDER_HERO = "npc_dota_hero_wisp"
local HERO_LEVEL = 30
local THINK_INTERVAL = 0.1
local BATTLE_ACQUISITION_RANGE = 4000
local CARRIER_INVENTORY_LAST_SLOT = 8 -- 0..5 主物品栏，6..8 背包
local NATIVE_STASH_FIRST_SLOT = 9
local NATIVE_STASH_LAST_SLOT = 14
-- 原版专属槽位：15 = 回城卷轴，16 = 中立装备。中立装备每个单位只有一个专属槽，
-- 且不属于物品栏/背包/储藏栏，所以 0..14 的枚举既看不到它，也无法把它转交出去。
local NEUTRAL_ITEM_SLOT = 16
-- 15 = 原版回城卷轴槽。本模式不需要回城卷轴（商店已下架、掉落池已排除），
-- 装备转交面板因此既不列出它，也不允许搬运它。
local NATIVE_TP_SLOT = 15
-- “可搬运槽位”上界：面板、装备快照、阵容重铸与原生拖放都必须覆盖中立槽。
local CARRIER_LAST_SLOT = NEUTRAL_ITEM_SLOT

-- 战场宽度 2400，纵向高度由 900 增至 1350（+50%）。
-- 准备期场上英雄只可在左侧区域排位；小精灵/待命区不受此场地钳制。
local BATTLEFIELD_HALF_WIDTH = 1200
local BATTLEFIELD_HALF_HEIGHT = 675
local BATTLEFIELD_MOVE_MARGIN = 64
local PREPARE_DIVIDER_MARGIN = 150

local function UnwrapKeyValues(data, rootName)
	if type(data) == "table" and type(data[rootName]) == "table" then
		return data[rootName]
	end
	return data
end

-- 所有默认出生点都留出边界和中线安全距离；三单位同槽展开（±220）也不会出界。
local TEAM_SPAWNS = {
	[DOTA_TEAM_GOODGUYS] = {
		Vector(-720, -220, 128),
		Vector(-880, 0, 128),
		Vector(-720, 220, 128),
		Vector(-520, -340, 128),
		Vector(-520, 340, 128),
	},
	[DOTA_TEAM_BADGUYS] = {
		Vector(720, 220, 128),
		Vector(880, 0, 128),
		Vector(720, -220, 128),
		Vector(520, 340, 128),
		Vector(520, -340, 128),
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

-- 战场隔断：覆盖紧凑战场的整条中线，开战瞬间移除。
local BARRIER_X = 0
local BARRIER_HALF_SPAN = BATTLEFIELD_HALF_HEIGHT
local BARRIER_SPACING = 100

-- 招募等级/价格、经验和奖励曲线统一由 data/progression_data.lua 提供。
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
	fine = { "modifier_item_aghanims_shard" },
	epic = { "modifier_item_ultimate_scepter_consumed" },
	legendary = { "modifier_item_aghanims_shard", "modifier_item_ultimate_scepter_consumed" },
}
REFRESH_BASE = 20
REFRESH_STEP = 20
REFRESH_MAX = 200
-- 经验卷轴（DESIGN.md §2.5）：低级 200 金/每关限购 2，高级 1000 金/每关限购 1
SCROLL_COST = { low = 200, high = 1000 }
SCROLL_XP = { low = 500, high = 2000 }
SCROLL_LIMIT_PER_STAGE = { low = 2, high = 1 }
-- 个人升级公式和时间奖励上限由 ProgressionPatch 使用统一数据模块提供。

-- 商店与阵容经济（刷新 20/次，替补格 200/个）
local SHOP_REFRESH_COST = 20
local SHOP_BENCH_SLOT_COST = 200
local BENCH_SLOT_MAX = 5
local LINEUP_MAX = 5

-- 经验卷轴价格/经验/限购见上方 SCROLL_COST / SCROLL_XP / SCROLL_LIMIT_PER_STAGE；
-- 真物品 KV 见 scripts/npc/npc_items_custom.txt（ItemCost 必须与 SCROLL_COST 一致）。
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
	{ action = "ability_1", condition = "always", value = 50, target = "enemy_distance_nearest", forced = false, enabled = true },
	{ action = "ability_2", condition = "always", value = 50, target = "enemy_hp_pct_lowest", forced = false },
	{ action = "ability_3", condition = "self_hp_pct_lte", value = 50, target = "self", forced = false },
	{ action = "ultimate", condition = "always", value = 2, target = "enemy_hp_pct_lowest", forced = true },
	{ action = "attack", condition = "always", value = 50, target = "enemy_distance_nearest", forced = true },
}

-- Legacy consumers receive the same learned-ability defaults as the bridge.
local function BuildDefaultRulesForSlots(_slots, hero)
	local rules = {}
	for _, rule in ipairs(require("issue_fixes.default_rules").CreateForHero(hero)) do
		rules[#rules + 1] = {
			id = rule.id, is_default = true,
			action = rule.action.kind == "attack" and "attack" or rule.action.logical_id,
			condition = "always", value = 50,
			target = rule.target.team == "self" and "self" or (rule.target.team .. "_distance_nearest"),
			forced = false, enabled = true,
		}
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
	return AbilityCatalog.ListActions(hero)
end

function Precache(context)
	PRECACHE_CONTEXT = context
	local started = type(RealTime) == "function" and RealTime() or nil
	local levels = UnwrapKeyValues(LoadKeyValues("scripts/data/levels.kv"), "levels")
	local startup = StagePrecache.Startup(context, levels)
	-- 运行期无法再加载模型，所以全部敌方英雄模型必须在这里准备。
	-- 只加载模型（本体 + 分件目录），不加载整套单位资源，避免回到全量同步预载的耗时。
	local heroResources = HeroModelPrecache.Resources(levels, HeroModelPaths())
	local heroClock = type(os) == "table" and os.clock or nil
	local heroStarted = heroClock and heroClock() or nil
	local heroApplied = HeroModelPrecache.Apply(heroResources, context, PrecacheResource)
	print(string.format("[RPGPrecache] hero_model_precache heroes=%d resources=%d applied=%d elapsed=%s",
		#HeroModelPrecache.HeroNames(levels), #heroResources, heroApplied,
		heroStarted and string.format("%.3f", heroClock() - heroStarted) or "unavailable"))
	print(string.format("[RPGPrecache] startup_complete build=rpg-runtime-v44-20260912 level=%s units=%d items=%d elapsed=%s",
		tostring(startup.levelId), #startup.units, #startup.items,
		started and string.format("%.3f", RealTime() - started) or "unavailable"))
end

function Activate()
	GameRules.Dota2RpgDemo = CDota2RpgDemo()
	GameRules.Dota2RpgDemo:InitGameMode()
end

function CDota2RpgDemo:InitGameMode()
	if RuntimeLog.StartSession ~= nil then RuntimeLog.StartSession("rpg-runtime-v44-20260912") end
	if not (okHelpers and okItems and okProgression and okRecruitmentPatch and okProgressionPatch
		and okEnemyItems and okBridge and okBattle and okData) then
		error("[Dota2Rpg] required gameplay modules failed to load")
	end
	local gameMode = GameRules:GetGameModeEntity()

	self.playerId = -1
	self.placeholderHero = nil
	self.phase = "setup"
	self.winner = ""
	self.runComplete = false
	self.runFailed = false
	self.runLives = nil
	RunLives.Ensure(self)
	self.teamsSpawned = false
	self.currentLevelId = "ch01"
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
	self.currentLevelId = levelIds[1] or "ch01"
	self.stagePrecache = StagePrecache.new(self.dataLoader:GetAllLevels(), {
		-- SetContextThink and this timeout share the game clock. RealTime
		-- is absent in the live Dota Lua VM, despite its DLL registration text.
		now = function() return GameRules:GetGameTime() end,
		log = function(message) RuntimeLog.WriteCritical("StagePrecache " .. message) end,
		schedule = function(callback, delay)
			gameMode:SetContextThink(DoUniqueString("RpgStagePrecache"), function()
				callback()
				return nil
			end, delay)
		end,
		-- 运行期没有可用的同步单位/物品预加载：PrecacheUnitByNameSync 会被原版拒绝
		-- （"must be passed a valid precache context"），引擎给的上下文只在地图加载期有效。
		-- 异步 API 的回调只是"已受理"，不代表资源就绪，所以英雄模型必须单独显式加载：
		-- PrecacheResource 是同步的，返回时模型已经在缓存里，敌方英雄才不会显示 ERROR 模型。
		-- 运行期预加载无法生效（引擎要求地图加载期的上下文），敌方英雄模型已在
		-- Precache(context) 里显式加载。这里只提交单位请求，回调仅代表"已受理"。
		load_unit = function(name, callback)
			return PrecacheUnitByNameAsync(name, callback, math.max(0, self.playerId))
		end,
		load_item = function(name, callback) return PrecacheItemByNameAsync(name, callback) end,
	})

	-- 经济/商店/阵容：项目消费与 Valve 原版商店共用同一个玩家钱包。
	self.initialGold = (ProgressionData and ProgressionData.INITIAL_GOLD) or self.shopCosts.initial_gold or 500
	self.gold = self.initialGold
	self.goldWalletInitialized = false
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
	-- 原版商店实际扣款仍由玩家主英雄（小精灵）执行；记录玩家选中的上阵/待命目标，购买后按实体补转。
	self.nativePurchaseSelectionHero = nil
	self.nativePurchaseOrderContexts = {}
	self.nativePurchaseClaimedIds = {}
	self.nativePurchaseTick = 0
	self.pendingNativePurchases = {}
	self.rosterAbilitySnapshot = nil
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
	GameRules:SetStartingGold(self.initialGold)
	GameRules:SetUseUniversalShopMode(true)
	-- 自定义地图没有标准商店建筑；保留原版 Dota 商店的原价购买与出售体验。
	if gameMode.SetCanSellAnywhere ~= nil then
		gameMode:SetCanSellAnywhere(true)
		print("[Dota2Rpg] Native shop sell-anywhere enabled.")
	else
		print("[Dota2Rpg] WARNING: SetCanSellAnywhere is unavailable; native selling requires a shop range.")
	end
	if GameRules.SetHeroRespawnEnabled ~= nil then
		-- Permit native WK/Aegis rebirth; per-hero round policy suppresses ordinary deaths.
		GameRules:SetHeroRespawnEnabled(true)
	end

	ListenToGameEvent("player_connect_full", Dynamic_Wrap(CDota2RpgDemo, "OnPlayerConnectFull"), self)
	ListenToGameEvent("npc_spawned", Dynamic_Wrap(CDota2RpgDemo, "OnNpcSpawned"), self)
	ListenToGameEvent("game_rules_state_change", Dynamic_Wrap(CDota2RpgDemo, "OnGameRulesStateChange"), self)
	ListenToGameEvent("entity_killed", Dynamic_Wrap(CDota2RpgDemo, "OnEntityKilled"), self)
	ListenToGameEvent("entity_hurt", Dynamic_Wrap(CDota2RpgDemo, "OnEntityHurt"), self)
	ListenToGameEvent("dota_item_picked_up", Dynamic_Wrap(CDota2RpgDemo, "OnItemPickedUp"), self)
	ListenToGameEvent("dota_item_purchased", Dynamic_Wrap(CDota2RpgDemo, "OnNativeItemPurchased"), self)
	ListenToGameEvent("dota_player_update_selected_unit", Dynamic_Wrap(CDota2RpgDemo, "OnPlayerSelectedUnit"), self)

	CustomGameEventManager:RegisterListener("rpg_replay_run", function(eventSourceIndex, payload)
		return self:OnReplayRun(eventSourceIndex, payload)
	end)
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
	-- 普通装备购买/出售统一交给 Valve 原版商店；项目事件只负责小精灵与上阵/待命英雄间的实体转交。
	CustomGameEventManager:RegisterListener("rpg_item_equip", function(eventSourceIndex, payload)
		return self:OnItemEquip(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_item_sell", function(eventSourceIndex, payload)
		return self:OnItemSell(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_item_unequip", function(eventSourceIndex, payload)
		return self:OnItemUnequip(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_native_purchase_target", function(eventSourceIndex, payload)
		return self:OnNativePurchaseTarget(eventSourceIndex, payload)
	end)

	PlayerResource:SetCustomTeamAssignment(0, DOTA_TEAM_GOODGUYS)
	self:InitializeRecruitmentState()
	self:RollShop()
	-- 战术桥接初始化放最后：失败时给出可定位错误并中止初始化
	local okInstall, installErr = pcall(function()
		self.tacticBridge:Install()
	end)
	if not okInstall then
		error("[Dota2Rpg] TacticBridge install failed: " .. tostring(installErr))
	end
	SkillDebug.Install(self)
	RuntimeLog.Write("BUILD rpg-runtime-v44-20260912 neutral-skills-v2 gris-gris-v1 loaded; log=console.log (-condebug)")
	print("[Dota2Rpg] Shop + lineup + TacticEngine initialized.")
end

function CDota2RpgDemo:LoadHeroPool()
	local data = UnwrapKeyValues(LoadKeyValues("scripts/data/heroes.kv"), "heroes")
	if type(data) ~= "table" then
		data = {}
	end
	self.heroPool = { strength = {}, agility = {}, intelligence = {}, universal = {} }
	self.shopCosts = {
		hero = (ProgressionData and ProgressionData.PriceForLevel(1)) or 500,
		refresh = tonumber(data.refresh_cost) or SHOP_REFRESH_COST,
		bench_slot = tonumber(data.bench_slot_cost) or SHOP_BENCH_SLOT_COST,
		bench_slot_max = tonumber(data.bench_slot_max) or BENCH_SLOT_MAX,
		lineup_max = tonumber(data.lineup_max) or LINEUP_MAX,
		initial_gold = (ProgressionData and ProgressionData.INITIAL_GOLD) or 500,
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

function CDota2RpgDemo:ReadNativeGold()
	if not self:HasNativeGoldWallet() then
		return nil
	end
	local total = tonumber(PlayerResource:GetGold(self.playerId))
	if total == nil then
		return nil
	end
	-- GetGold already includes both reliable and unreliable gold.
	return math.max(0, math.floor(total))
end

local function LogGoldWallet(self, action, before, after, detail)
	-- Logging must never interrupt wallet updates, including before engine APIs exist.
	pcall(function()
		RuntimeLog.Write(string.format("[Dota2Rpg] GoldWallet action=%s pid=%s before=%s after=%s initialized=%s detail=%s",
			tostring(action), tostring(self.playerId), tostring(before), tostring(after),
			tostring(self.goldWalletInitialized == true), tostring(detail)))
	end)
end

function CDota2RpgDemo:GetGoldBalance()
	local before = self.gold
	local nativeGold = self:ReadNativeGold()
	if nativeGold ~= nil then
		-- PlayerResource 是唯一真源。项目自己的消费会同步调用 SetGold，
		-- 因而这里直接镜像不会把原版商店扣款或出售返款反写掉。
		self.gold = nativeGold
		self.nativeGoldSnapshot = nativeGold
		if before ~= nativeGold then
			LogGoldWallet(self, "read-change", before, nativeGold, "native")
		end
	end
	return math.max(0, math.floor(tonumber(self.gold) or 0))
end

function CDota2RpgDemo:EnsureGoldWalletInitialized()
	if self.goldWalletInitialized then
		return self:GetGoldBalance()
	end
	local before = self.gold
	local nativeGold = self:ReadNativeGold()
	local decision
	if nativeGold ~= nil and nativeGold > 0 then
		-- Preserve a native starting balance, including entirely unreliable gold.
		self.gold = nativeGold
		self.nativeGoldSnapshot = nativeGold
		self.goldWalletInitialized = true
		decision = "preserve-native"
	elseif nativeGold ~= nil and PlayerResource.SetGold ~= nil then
		-- The live mirror may already have read zero before player connection.
		self:SetGoldBalance(self.initialGold or (ProgressionData and ProgressionData.INITIAL_GOLD)
			or (self.shopCosts and self.shopCosts.initial_gold) or 500)
		decision = "seed-startup"
	else
		-- Retry when the player and native wallet APIs become available.
		decision = "deferred"
	end
	local balance = self:GetGoldBalance()
	LogGoldWallet(self, "init", before, balance, decision)
	return balance
end

function CDota2RpgDemo:SetGoldBalance(amount)
	local before = self:ReadNativeGold()
	if before == nil then before = self.gold end
	local wroteNative = false
	self.gold = math.max(0, math.floor(tonumber(amount) or 0))
	if PlayerResource ~= nil and PlayerResource.SetGold ~= nil
		and self.playerId ~= nil and self.playerId >= 0 then
		-- 用可靠金币承载项目经济，并清空另一钱包，避免 GetGold 与 HUD 出现双份余额。
		PlayerResource:SetGold(self.playerId, self.gold, true)
		PlayerResource:SetGold(self.playerId, 0, false)
		self.nativeGoldSnapshot = self.gold
		self.goldWalletInitialized = true
		wroteNative = true
	end
	LogGoldWallet(self, "write", before, self.gold, wroteNative and "native" or "mirror-only")
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
	self:EnsureGoldWalletInitialized()
	self:ScheduleStateBroadcast(0.5)
end

function CDota2RpgDemo:OnNpcSpawned(event)
	local unit = EntIndexToHScript(event.entindex or -1)
	-- Native doubles are combat summons, never the hidden player commander.
	if TempestDouble.OnSpawn(self, unit, BATTLE_ACQUISITION_RANGE) then return end
    if SpecialTargets.OnSpawn(self, unit) then return end
    -- 敌方召唤物（蛇棒、地狱火等）不参与指令托管，但必须进清理名单，
    -- 否则会活到下一关、甚至打死准备区里的小精灵。
    -- 组装关卡阵容时必须跳过：npc_spawned 在 CreateUnitByName 期间同步触发，
    -- 早于 battleManager:RegisterHero，此刻本关野怪还没登记，会被误判成"敌方召唤物"
    -- 并随准备阶段每 tick 的 Summons.Clear 一起被 RemoveSelf，导致场上没有野怪、开局即胜。
    if not self.stageLoading then
        SummonBehavior.TrackEnemySummon(self, unit)
    end
    if SummonBehavior.OnSpawn(self, unit) then return end
	if RespawnPolicy.OnSpawn(self, unit) then return end
	if not TacticEngine.IsValidUnit(unit) or not unit:IsRealHero() then
		return
	end
	-- 项目生成的上阵/待命英雄是装备载体，不是 PlayerResource 的主英雄。
	if unit.lineupHeroName ~= nil or unit.benchHeroName ~= nil then
		return
	end
	-- npc_spawned 可能早于字段赋值；已拥有的非指挥官英雄名也视为项目生成载体，
	-- 避免引擎在 nil owner 情况下仍暂时报告玩家 owner 时误处理其位置。
	local unitName = unit.GetUnitName ~= nil and unit:GetUnitName() or ""
	if unitName ~= PLAYER_PLACEHOLDER_HERO and self.heroData ~= nil and self.heroData[unitName] ~= nil then
		for _, heroName in ipairs(self.ownedHeroes or {}) do
			if heroName == unitName then
				return
			end
		end
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
		-- 指挥官只是背包/控制载体，全程不应受伤：无敌是常驻状态，
		-- 而不是"战斗中才开"。准备阶段残留的敌方召唤物曾经把它打死。
		self:EnsureCommanderProtected()
		-- The commander is an inventory/control carrier only. Hide it explicitly
		-- instead of relying on the out-of-bounds position.
		if unit.AddNoDraw ~= nil then
			pcall(function() unit:AddNoDraw() end)
		end
	end
	self.playerId = math.max(self.playerId, ownerId)
	-- 玩家英雄就是小精灵：显式同步一次，让 F1 与原版商店的"我的英雄"绑定成立。
	self:EnsureNativePlayerHero()
	-- npc_spawned may precede PlayerResource's starting-gold initialization;
	-- wallet initialization belongs to player_connect_full, never this callback.
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





-- 经验卷轴使用：给当前上阵且由项目拥有的英雄加经验。
-- 项目面板使用虚拟库存；真实 item_lua 路径还必须通过这里的阶段/实体校验。
function CDota2RpgDemo:GrantScrollXPByUnit(unit, xp, item)
	if self.phase ~= "setup" or unit == nil or not TacticEngine.IsValidUnit(unit) then
		return false
	end
	local heroName = unit.lineupHeroName or unit:GetUnitName()
	local data = self.heroData[heroName]
	local lineupUnit = self:FindLineupUnit(heroName)
	if data == nil or lineupUnit ~= unit then
		print("[Dota2Rpg] Scroll used by non-current-lineup unit: " .. tostring(heroName))
		return false
	end
	local realScrollKind = nil
	if item ~= nil then
		local itemName = item.GetAbilityName ~= nil and item:GetAbilityName() or ""
		if SCROLL_XP[itemName] == nil
			or tonumber(SCROLL_XP[itemName]) ~= math.floor(tonumber(xp) or 0)
			or not self:IsItemHeldBy(unit, item, 0, 8) then
			return false
		end
		realScrollKind = itemName == "item_rpg_scroll_high" and "high" or "low"
		if (self.scrollStock[realScrollKind] or 0) <= 0 then
			-- 真实物品不能绕过项目面板的每关库存；正常路径由面板维护 virtual stock。
			return false
		end
	end
	if (tonumber(data.level) or 1) >= HERO_LEVEL then
		return false
	end
	self:AddXpToHero(heroName, xp)
	if realScrollKind ~= nil then
		self.scrollStock[realScrollKind] = self.scrollStock[realScrollKind] - 1
	end
	self:BroadcastShopState()
	print(string.format("[Dota2Rpg] ScrollXP: %s +%d (lv%d, xp=%d, sp=%d)",
		heroName, xp, data.level, data.current_xp, data.skill_points))
	return true
end

-- XP、阵容和无存档状态处理统一由下方最终实现区提供。

------------------------------------------------------------------
-- 商店与阵容
------------------------------------------------------------------

-- The Lua VM starts math.random with a repeatable sequence. Gameplay uses
-- Dota's native RNG; the fallback is only for standalone Lua test runners.
local function ShopRandomInt(minimum, maximum)
	if RandomInt ~= nil then return RandomInt(minimum, maximum) end
	return math.random(minimum, maximum)
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
	local roll = ShopRandomInt(1, math.max(1, total))
	for _, quality in ipairs({ "legendary", "epic", "fine", "common" }) do
		roll = roll - (weights[quality] or 0)
		if roll <= 0 then
			return quality
		end
	end
	return "common"
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
			local heroName = pool[ShopRandomInt(1, #pool)]
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
		local candidate = table.remove(allHeroes, ShopRandomInt(1, #allHeroes))
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
	RuntimeLog.Write(string.format("ShopRoll stage=%s rng=%s offers=%s", tostring(self.currentLevelId),
		RandomInt ~= nil and "native" or "lua-fallback", self.shopOfferText))
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

-- 当前关剩余卷轴限购（低级 2、高级 1，见 SCROLL_LIMIT_PER_STAGE）
function CDota2RpgDemo:GetScrollRemaining(kind)
	local limit = SCROLL_LIMIT_PER_STAGE[kind]
	if limit == nil then
		return 0
	end
	return limit - (self.scrollPurchases[kind] or 0)
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
	if data == nil or (tonumber(data.level) or 1) >= HERO_LEVEL or self:FindLineupUnit(heroName) == nil then
		return -- 只允许当前上阵英雄，且 30 级不能使用
	end
	self.scrollStock[kind] = self.scrollStock[kind] - 1
	self:AddXpToHero(heroName, SCROLL_XP[kind])
	-- 经验卷轴不应为了更新等级而销毁/重建英雄；这样会使原版装备实体 ID、冷却和堆叠状态失效。
	local hero = self:FindLineupUnit(heroName)
	if hero ~= nil and hero.GetLevel ~= nil then
		self:UpdateHeroLevel(hero, data.level)
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

function CDota2RpgDemo:IsBenchUnit(unit)
	if unit == nil then
		return false
	end
	for _, hero in ipairs(self.benchUnits or {}) do
		if hero == unit then
			return true
		end
	end
	return false
end

function CDota2RpgDemo:GetEquipmentHeroName(unit)
	if unit == nil or unit == self:GetStashUnit() then
		return nil
	end
	local heroName = unit.lineupHeroName or unit.benchHeroName
	if heroName ~= nil and self.heroData[heroName] ~= nil then
		return heroName
	end
	if unit.GetUnitName ~= nil then
		heroName = unit:GetUnitName()
		if self.heroData[heroName] ~= nil then
			return heroName
		end
	end
	return nil
end

-- 小精灵、当前上阵英雄和待命英雄都是准备阶段的真实装备载体。
function CDota2RpgDemo:IsEquipmentCarrier(unit)
	return unit ~= nil and (unit == self:GetStashUnit() or self:IsLineupUnit(unit) or self:IsBenchUnit(unit))
end

function CDota2RpgDemo:GetCarrierPlayerOwnerId(unit)
	if unit == nil then
		return nil
	end
	if unit.GetPlayerOwnerID ~= nil then
		local ok, ownerId = pcall(function() return unit:GetPlayerOwnerID() end)
		ownerId = ok and tonumber(ownerId) or nil
		if ownerId ~= nil and ownerId >= 0 then
			return ownerId
		end
	end
	local owner = nil
	if unit.GetOwner ~= nil then
		local ok, value = pcall(function() return unit:GetOwner() end)
		if ok then
			owner = value
		end
	end
	if owner ~= nil and owner ~= unit and owner.GetPlayerOwnerID ~= nil then
		local ok, ownerId = pcall(function() return owner:GetPlayerOwnerID() end)
		ownerId = ok and tonumber(ownerId) or nil
		if ownerId ~= nil and ownerId >= 0 then
			return ownerId
		end
	end
	return nil
end

function CDota2RpgDemo:BindEquipmentCarrierToPlayer(unit)
	if unit == nil or self.playerId == nil or self.playerId < 0 then
		return false
	end
	local beforeBinding = self:ReadNativeGold()
	local owner = self:GetStashUnit()
	if unit ~= owner then
		if owner == nil or unit.SetOwner == nil then
			print(string.format("[Dota2Rpg] WARNING: %s has no player owner binding API.",
				unit.GetUnitName ~= nil and unit:GetUnitName() or "unit"))
			return false
		end
		local ok, err = pcall(function()
			unit:SetOwner(owner)
		end)
		if not ok then
			print(string.format("[Dota2Rpg] WARNING: could not SetOwner for %s: %s.",
				unit.GetUnitName ~= nil and unit:GetUnitName() or "unit", tostring(err)))
			return false
		end
	end
	if unit.SetControllableByPlayer == nil then
		print(string.format("[Dota2Rpg] WARNING: %s has no control binding API.",
			unit.GetUnitName ~= nil and unit:GetUnitName() or "unit"))
		return false
	end
	local ok, err = pcall(function()
		unit:SetControllableByPlayer(self.playerId, true)
	end)
	if not ok then
		print(string.format("[Dota2Rpg] WARNING: could not control %s for player %d: %s.",
			unit.GetUnitName ~= nil and unit:GetUnitName() or "unit", self.playerId, tostring(err)))
		return false
	end
	if unit.SetPlayerID ~= nil then
		local assigned = pcall(unit.SetPlayerID, unit, self.playerId)
		if not assigned then return false end
	end
	local ownerId = self:GetCarrierPlayerOwnerId(unit)
	if ownerId == nil or ownerId ~= self.playerId then
		print(string.format("[Dota2Rpg] WARNING: %s native owner could not be verified for player %d.",
			unit.GetUnitName ~= nil and unit:GetUnitName() or "unit", self.playerId))
		return false
	end
	RuntimeLog.Write(string.format("Wallet carrier_bound player=%d hero=%s native_before=%s native_after=%s",
		self.playerId, unit.GetUnitName ~= nil and unit:GetUnitName() or "unit",
		tostring(beforeBinding), tostring(self:ReadNativeGold())))
	return true
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

function CDota2RpgDemo:FindEmptyCarrierSlot(unit)
	if unit == nil or unit.GetItemInSlot == nil then
		return nil
	end
	for slot = 0, CARRIER_INVENTORY_LAST_SLOT do
		if not self:IsLiveItem(unit:GetItemInSlot(slot)) then
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
	for slot = 0, NATIVE_STASH_LAST_SLOT do
		if not self:IsLiveItem(stash:GetItemInSlot(slot)) then
			return true
		end
	end
	return false
end

-- 某个载体的原版专属中立槽当前持有的实体（没有则返回 nil）。
-- 该槽容量固定为 1，且不占用物品栏/背包/储藏栏。
-- 指挥官（小精灵）全程无敌：它在战场上只是携带金币/装备的载体，被任何来源打死
-- 都会破坏钱包、库存与转交。开战时加、切关/重开时也保持，不再摘掉。
function CDota2RpgDemo:EnsureCommanderProtected()
	local commander = self.placeholderHero
	if commander == nil or not TacticEngine.IsValidUnit(commander) then
		return false
	end
	if commander.AddNewModifier ~= nil then
		pcall(function()
			commander:AddNewModifier(commander, nil, "modifier_invulnerable", {})
		end)
	end
	return true
end

function CDota2RpgDemo:GetNeutralSlotItem(unit)
	if unit == nil or unit.GetItemInSlot == nil then
		return nil
	end
	local item = unit:GetItemInSlot(NEUTRAL_ITEM_SLOT)
	if self:IsLiveItem(item) then
		return item
	end
	return nil
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

-- 从小精灵库存、Dota 原生储藏栏或专属中立槽取出“同一个”物品实体。
-- 原版远程购买会把物品放到 9..14，中立装备由引擎放进专属中立槽 16；
-- 必须覆盖这些槽，否则面板永远无法转交该物品。
function CDota2RpgDemo:TakeStashItem(itemName, expectedItemId)
	local stash = self:GetStashUnit()
	if stash == nil or stash.GetItemInSlot == nil then
		return nil
	end
	local expected = tostring(expectedItemId or "")
	for slot = 0, CARRIER_LAST_SLOT do
		local item = stash:GetItemInSlot(slot)
		if self:IsLiveItem(item) and item:GetAbilityName() == itemName
			and (expected == "" or self:GetItemEntityId(item) == expected) then
			stash:TakeItem(item)
			return item
		end
	end
	return nil
end

function CDota2RpgDemo:TryAttachItem(unit, item)
	if unit == nil or unit.AddItem == nil or not self:IsLiveItem(item) then
		return false, nil
	end
	if self:IsItemHeldBy(unit, item, 0, CARRIER_LAST_SLOT) then
		return true, item
	end
	local itemName = item.GetAbilityName ~= nil and item:GetAbilityName() or ""
	local ok = pcall(function()
		unit:AddItem(item)
	end)
	-- 某些工具版本会在已经完成 AddItem/合并后抛异常；先检查实际槽位，
	-- 不能因为异常文本把同一实体当成丢失物品。
	if self:IsItemHeldBy(unit, item, 0, CARRIER_LAST_SLOT) then
		return true, item
	end
	-- 原版 AddItem 可能把可堆叠物品合并后使传入实体失效；返回合并后的真实实体。
	if not self:IsLiveItem(item) and itemName ~= "" and unit.GetItemInSlot ~= nil then
		for slot = 0, CARRIER_LAST_SLOT do
			local existing = unit:GetItemInSlot(slot)
			if self:IsLiveItem(existing) and existing:GetAbilityName() == itemName then
				return true, existing
			end
		end
	end
	return false, nil
end

-- 任何搬运失败都优先把原实体放回来源载体；若引擎拒绝 AddItem，最后放到来源脚下，绝不销毁或同名重建。
function CDota2RpgDemo:PreserveDetachedItem(item, preferredCarrier, context)
	if not self:IsLiveItem(item) then
		return false
	end
	if self:TryAttachItem(preferredCarrier, item) then
		return true
	end
	local stash = self:GetStashUnit()
	if stash ~= preferredCarrier and self:TryAttachItem(stash, item) then
		return true
	end
	local dropCarrier = preferredCarrier or stash
	if CreateItemOnPositionSync ~= nil and dropCarrier ~= nil and dropCarrier.GetAbsOrigin ~= nil then
		local ok = pcall(function()
			CreateItemOnPositionSync(dropCarrier:GetAbsOrigin(), item)
		end)
		if ok then
			print(string.format("[Dota2Rpg] WARNING: %s; preserved %s on the ground.",
				tostring(context or "item transfer failed"), item:GetAbilityName()))
			self.nativeShopTransactionPending = true
			return true
		end
	end
	print(string.format("[Dota2Rpg] ERROR: %s; could not reattach live item %s.",
		tostring(context or "item transfer failed"), item:GetAbilityName()))
	return false
end

function CDota2RpgDemo:PutItemInStash(item, allowNeutral)
	local stash = self:GetStashUnit()
	if not self:IsLiveItem(item) or stash == nil then
		return false
	end
	-- 中立装备只进专属中立槽，不能因为物品栏/背包/储藏栏满而被拒绝。
	if not allowNeutral and not self:HasFreeStashSlot() then
		return false
	end
	-- 0..8 已满时 Dota 允许把物品放回该玩家的原生储藏栏 9..14；
	-- 中立装备由引擎放回专属中立槽 16。
	return self:TryAttachItem(stash, item)
end

-- 原版商店在地图外/无泉水场景会把购买物品送入单位的原生储藏栏（9..14）。
-- 准备阶段把它原实体移动到 0..8，使其可丢弃、可显示并可通过 Panorama 转交。
function CDota2RpgDemo:PromoteNativeStashItem(unit, item, sourceSlot)
	if not self:IsEquipmentCarrier(unit) or not self:IsLiveItem(item) then
		return false
	end
	local destinationSlot = self:FindEmptyCarrierSlot(unit)
	if destinationSlot == nil then
		return false
	end

	if unit.SwapItems ~= nil then
		local ok = pcall(function()
			unit:SwapItems(sourceSlot, destinationSlot)
		end)
		if ok and unit:GetItemInSlot(destinationSlot) == item then
			return true
		end
	end

	-- TakeItem detaches without deleting; RemoveItem destroys the entity in Dota.
	if unit.TakeItem ~= nil and unit.AddItem ~= nil
		and self:IsItemHeldBy(unit, item, NATIVE_STASH_FIRST_SLOT, NATIVE_STASH_LAST_SLOT) then
		unit:TakeItem(item)
		if self:TryAttachItem(unit, item) then
			-- AddItem 若仍送回原生储藏栏，实体没有丢失；下一次可由面板直接转交。
			return self:IsItemHeldBy(unit, item, 0, CARRIER_INVENTORY_LAST_SLOT)
		end
		self:PreserveDetachedItem(item, unit, "native stash promotion failed")
		return false
	end
	return false
end

function CDota2RpgDemo:NormalizeNativeStashItems()
	local moved = 0
	local seen = {}
	local function normalize(unit)
		if unit == nil or unit.GetItemInSlot == nil or seen[unit] then
			return
		end
		seen[unit] = true
		for slot = NATIVE_STASH_FIRST_SLOT, NATIVE_STASH_LAST_SLOT do
			local item = unit:GetItemInSlot(slot)
			if self:IsLiveItem(item) and self:PromoteNativeStashItem(unit, item, slot) then
				moved = moved + 1
				print(string.format("[Dota2Rpg] Native stash item promoted: %s slot %d -> inventory.",
					item:GetAbilityName(), slot))
			end
		end
	end
	normalize(self:GetStashUnit())
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
		normalize(hero)
	end
	for _, hero in ipairs(self.benchUnits or {}) do
		normalize(hero)
	end
	return moved
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
	local heroName = hero.lineupHeroName or hero.benchHeroName or hero:GetUnitName()
	local data = self.heroData[heroName]
	if data == nil then
		return false
	end
	local inventory = {}
	local states = {}
	local entities = {}
	-- 0..8 是物品栏/背包；原版远程购买可能暂存在 9..14，中立装备常驻专属中立槽 16。
	-- 三者都必须在阵容重铸时保留，否则中立装备会随旧单位一起消失。
	for slot = 0, CARRIER_LAST_SLOT do
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
	for _, hero in ipairs(self.benchUnits or {}) do
		if TacticEngine.IsValidUnit(hero) then
			self:SyncHeroInventoryFromUnit(hero)
		end
	end
end

-- 原版 TRAIN_ABILITY 订单直接修改实体，不会触发项目自定义事件；把实际
-- ability level/points 延迟镜像回 heroData，确保刷新或重铸不会恢复旧技能。
function CDota2RpgDemo:BuildRosterAbilitySnapshot()
	local parts = {}
	local seen = {}
	local function append(hero)
		if hero == nil or not TacticEngine.IsValidUnit(hero) or hero.GetAbilityCount == nil
			or hero.GetAbilityByIndex == nil or seen[hero] then return end
		seen[hero] = true
		local heroName = hero.lineupHeroName or hero.benchHeroName
		if heroName == nil then return end
		local entityId = hero.GetEntityIndex ~= nil and hero:GetEntityIndex()
			or (hero.entindex ~= nil and hero:entindex() or 0)
		local values = { tostring(heroName), tostring(entityId),
			tostring(hero.GetAbilityPoints ~= nil and hero:GetAbilityPoints() or -1) }
		for slot = 0, HeroAbilityPolicy.GetSlotCount(hero) - 1 do
			local ability = hero:GetAbilityByIndex(slot)
			if ability ~= nil and (ability.IsNull == nil or not ability:IsNull()) then
				local name = ability.GetAbilityName ~= nil and ability:GetAbilityName() or ""
				local level = ability.GetLevel ~= nil and ability:GetLevel() or -1
				table.insert(values, tostring(slot) .. "=" .. tostring(name) .. ":" .. tostring(level)
					.. ":" .. tostring(ability.IsHidden ~= nil and ability:IsHidden() or false)
					.. ":" .. tostring(ability.IsActivated == nil or ability:IsActivated()))
			end
		end
		table.insert(parts, table.concat(values, "|"))
	end
	for _, heroName in ipairs(self.lineup or {}) do append(self:FindLineupUnit(heroName)) end
	for _, hero in ipairs(self.benchUnits or {}) do append(hero) end
	table.sort(parts)
	return table.concat(parts, ";")
end

function CDota2RpgDemo:SyncRosterAbilities()
	-- Compare against the previous think's entity state. Comparing snapshots made
	-- before and after CaptureHeroAbilities in the same call can never observe a
	-- native TRAIN_ABILITY mutation, because capture only mirrors the entity.
	local current = self:BuildRosterAbilitySnapshot()
	local changed = self.rosterAbilitySnapshot ~= nil
		and current ~= self.rosterAbilitySnapshot
	local seen = {}
	local function capture(hero)
		if hero == nil or seen[hero] or not TacticEngine.IsValidUnit(hero) then return end
		seen[hero] = true
		self:CaptureHeroAbilities(hero)
	end
	for _, heroName in ipairs(self.lineup or {}) do capture(self:FindLineupUnit(heroName)) end
	for _, hero in ipairs(self.benchUnits or {}) do capture(hero) end
	self.rosterAbilitySnapshot = self:BuildRosterAbilitySnapshot()
	return changed
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
	appendUnit(self:GetStashUnit(), "stash:", CARRIER_LAST_SLOT)
	for _, heroName in ipairs(self.lineup or {}) do
		appendUnit(self:FindLineupUnit(heroName), "hero:" .. heroName .. ":", CARRIER_LAST_SLOT)
	end
	for _, hero in ipairs(self.benchUnits or {}) do
		local heroName = self:GetEquipmentHeroName(hero)
		if heroName ~= nil then
			appendUnit(hero, "bench:" .. heroName .. ":", CARRIER_LAST_SLOT)
		end
	end
	return table.concat(parts, ";")
end

function CDota2RpgDemo:SyncLiveEquipmentState(force)
	if self.phase ~= "setup" then
		return false
	end
	local promoted = self:NormalizeNativeStashItems()
	force = force or promoted > 0
	local snapshot = self:BuildEquipmentSnapshot()
	if not force and snapshot == self.equipmentSnapshot then
		return false
	end
	self:SyncLineupInventories()
	self.equipmentSnapshot = self:BuildEquipmentSnapshot()
	self.nativePurchaseBaseline = self:CollectManagedItemIds()
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

function CDota2RpgDemo:GetNativePurchaseRecipientKey(unit)
	if unit == self:GetStashUnit() then
		return "__wisp"
	end
	return self:GetEquipmentHeroName(unit)
end

function CDota2RpgDemo:ResolveNativePurchaseRecipient(key)
	if key == "__wisp" or key == nil or key == "" then
		return self:GetStashUnit()
	end
	return self:FindOwnedHeroUnit(key)
end

-- 原版商店的购买点击资格由客户端"这个单位是不是玩家自己的英雄"决定。项目用
-- CreateUnitByName 生成的上阵/待命英雄没有经过引擎选人流程，客户端不把它们算作
-- 玩家英雄：选中它们时购买点击完全没有反应，既不产生订单也没有错误提示。
-- 把 PlayerResource 的 selected hero 跟随当前选中的装备载体，客户端就会允许为该
-- 英雄下单。订单仍由 ValidatePrepareOrder 改派给小精灵执行，再按
-- nativePurchaseSelectionHero 交付给同一名英雄，因此价格、库存、合成与扣款规则不变。
function CDota2RpgDemo:SyncNativePlayerHero(unit)
	if PlayerResource == nil or PlayerResource.SetSelectedHero == nil then
		return false
	end
	local playerId = tonumber(self.playerId)
	if playerId == nil or playerId < 0 or not self:IsEquipmentCarrier(unit) then
		return false
	end
	local index = unit.GetEntityIndex ~= nil and tonumber(unit:GetEntityIndex()) or nil
	local unitName = unit.GetUnitName ~= nil and unit:GetUnitName() or ""
	if index == nil or type(unitName) ~= "string" or unitName == "" then
		return false
	end
	-- 只在实体真的换了才调用；阵容重建后实体索引不同，会自动重新同步。
	if self.nativeSelectedHeroIndex == index then
		return true
	end
	local called = pcall(function() PlayerResource:SetSelectedHero(playerId, unitName) end)
	if not called then
		return false
	end
	self.nativeSelectedHeroIndex = index
	-- 读回校验：接口存在但没有生效时必须留下可定位日志，不能假设商店已经放开。
	local verified = true
	if PlayerResource.GetSelectedHeroEntity ~= nil then
		local ok, current = pcall(function() return PlayerResource:GetSelectedHeroEntity(playerId) end)
		verified = ok and current ~= nil and current.GetUnitName ~= nil
			and current:GetUnitName() == unitName
	end
	if verified then
		print(string.format("[Dota2Rpg] Native player hero synced for the native shop: %s index=%d.",
			unitName, index))
	elseif not self.nativeSelectedHeroWarned then
		self.nativeSelectedHeroWarned = true
		print("[Dota2Rpg] WARNING: PlayerResource:SetSelectedHero did not take effect; " ..
			"the native shop may still refuse roster heroes.")
	end
	return verified
end

-- 阵容重建会销毁旧英雄实体。选中目标失效时退回玩家小精灵，避免客户端继续持有
-- 一个已删除的英雄句柄。每个准备阶段 tick 调用一次，实体没换时是常数开销。
function CDota2RpgDemo:EnsureNativePlayerHero()
	local index = tonumber(self.nativeSelectedHeroIndex)
	if index ~= nil then
		local unit = EntIndexToHScript(index)
		local live = unit ~= nil and self:IsEquipmentCarrier(unit)
		if live and IsValidEntity ~= nil then
			live = IsValidEntity(unit) and true or false
		end
		if live then
			return true
		end
		self.nativeSelectedHeroIndex = nil
	end
	return self:SyncNativePlayerHero(self:GetStashUnit())
end

-- 仍然存活的上阵/待命英雄交付目标；选中指挥官不算一次目标变更。
function CDota2RpgDemo:HasLiveNativePurchaseTarget()
	local key = self.nativePurchaseSelectionHero
	if key == nil or key == "" or key == "__wisp" then
		return false
	end
	local hero = self:FindOwnedHeroUnit(key)
	return hero ~= nil and self:IsEquipmentCarrier(hero)
end

function CDota2RpgDemo:SetNativePurchaseSelection(unit)
	if not self:IsEquipmentCarrier(unit) then
		self.nativePurchaseSelectionHero = "__wisp"
		self:SyncNativePlayerHero(self:GetStashUnit())
		return false
	end
	if not self:BindEquipmentCarrierToPlayer(unit) then
		self.nativePurchaseSelectionHero = "__wisp"
		self:SyncNativePlayerHero(self:GetStashUnit())
		return false
	end
	local key = self:GetNativePurchaseRecipientKey(unit)
	-- 选中小精灵是为了让原版商店能点（客户端只认玩家自己的英雄），不代表
	-- "这次购买进小精灵"。只要还选着上阵/待命英雄，就保留它作为交付目标，
	-- 购买后自动交付，不需要再手动转交。
	if key ~= "__wisp" or not self:HasLiveNativePurchaseTarget() then
		self.nativePurchaseSelectionHero = key
	end
	self:SyncNativePlayerHero(unit)
	return true
end

function CDota2RpgDemo:OnNativePurchaseTarget(eventSourceIndex, payload)
	if self.phase ~= "setup" then
		return
	end
	local playerId = self:ResolvePlayerId(payload)
	if (playerId == nil or playerId < 0) and tonumber(eventSourceIndex) ~= nil then
		playerId = tonumber(eventSourceIndex)
	end
	if self.playerId ~= nil and self.playerId >= 0 and playerId ~= self.playerId then
		return
	end
	local heroName = tostring(payload and (payload.hero or payload.hero_name) or "")
	if heroName ~= "" then
		local hero = self:FindOwnedHeroUnit(heroName)
		if hero ~= nil then
			self:SetNativePurchaseSelection(hero)
			return
		end
	end
	local unitIndex = tonumber(payload and (payload.unit_index or payload.entindex or payload.unitindex) or -1) or -1
	local unit = unitIndex > 0 and EntIndexToHScript(unitIndex) or nil
	self:SetNativePurchaseSelection(unit)
end

function CDota2RpgDemo:OnPlayerSelectedUnit(event)
	if self.phase ~= "setup" then
		return
	end
	local playerId = tonumber(event and (event.PlayerID or event.player_id or event.playerid) or -1) or -1
	if self.playerId ~= nil and self.playerId >= 0 and playerId >= 0 and playerId ~= self.playerId then
		return
	end
	local unitIndex = tonumber(event and (event.unit_index or event.unitindex or event.unit or event.entindex or event.selected_entindex) or -1) or -1
	if unitIndex > 0 then
		self:SetNativePurchaseSelection(EntIndexToHScript(unitIndex))
	end
end

function CDota2RpgDemo:GetNativePurchaseClock()
	if GameRules ~= nil and GameRules.GetGameTime ~= nil then
		local ok, gameTime = pcall(function() return GameRules:GetGameTime() end)
		if ok and tonumber(gameTime) ~= nil then
			return tonumber(gameTime)
		end
	end
	return 0
end

function CDota2RpgDemo:GetNativePurchaseItemName(order)
	-- PURCHASE_ITEM carries an item definition ID, not an entity index.
	local definitionId = tonumber(order.entindex_ability)
	if definitionId ~= nil and definitionId > 0 then
		if definitionId ~= math.floor(definitionId) then return "" end
		if self.nativePurchaseItemNames == nil then
			if type(LoadKeyValues) ~= "function" then return "" end
			-- This is the engine's ID registry in dota/pak01_dir.vpk. Item IDs
			-- have their own namespace; never index UnitAbilities here.
			local ok, registry = pcall(LoadKeyValues, "scripts/npc/npc_ability_ids.txt")
			if not ok or type(registry) ~= "table" then return "" end
			registry = registry.DOTAAbilityIDs or registry
			local items = type(registry) == "table" and registry.ItemAbilities or nil
			if type(items) ~= "table" then return "" end
			local names = {}
			local function indexItems(entries)
				for name, value in pairs(entries) do
					if type(value) == "table" then
						indexItems(value)
					elseif type(name) == "string" and string.sub(name, 1, 5) == "item_" then
						local id = tonumber(value)
						if id ~= nil and id > 0 and id == math.floor(id) then
							names[id] = names[id] == nil and name or (names[id] == name and name or false)
						end
					end
				end
			end
			indexItems(items)
			if next(names) == nil then return "" end
			self.nativePurchaseItemNames = names
		end
		return self.nativePurchaseItemNames[definitionId] or ""
	end
	return tostring(order.itemname or order.item_name or order.item or "")
end

function CDota2RpgDemo:GetNativePurchaseCost(itemName, payload)
	local keys = { "itemcost", "item_cost", "gold_cost", "cost" }
	for _, key in ipairs(keys) do
		local value = payload ~= nil and tonumber(payload[key]) or nil
		if value ~= nil and value > 0 then
			return math.floor(value)
		end
	end
	itemName = tostring(itemName or "")
	if itemName ~= "" and type(GetItemCost) == "function" then
		local ok, value = pcall(GetItemCost, itemName)
		value = ok and tonumber(value) or nil
		if value ~= nil and value > 0 then
			return math.floor(value)
		end
	end
	return nil
end

function CDota2RpgDemo:LogNativePurchase(purchase, stage, decision)
	-- Bound diagnostics for long sessions, and never log routing retries per tick.
	self.nativePurchaseLogCount = (self.nativePurchaseLogCount or 0) + 1
	if self.nativePurchaseLogCount > 200 then return end
	RuntimeLog.Write(string.format("[Dota2Rpg] ShopTxn id=%s stage=%s issuer=%s item=%s target=%s location=%s before=%s after=%d decision=%s",
		tostring(purchase.transaction_id or "unmatched"), stage, tostring(purchase.issuer or self.playerId),
		tostring(purchase.item_name), tostring(purchase.recipient_key), tostring(purchase.target_location or "stash"),
		tostring(purchase.gold_before), self:GetGoldBalance(), tostring(decision)))
end

function CDota2RpgDemo:ObserveNativePurchaseItem(item, purchase)
	self.nativePurchaseObservedStates = self.nativePurchaseObservedStates or {}
	local id = self:GetItemEntityId(item)
	local state = self:GetItemPersistentState(item)
	if purchase ~= nil and item.GetInitialCharges ~= nil then
		local ok, initial = pcall(item.GetInitialCharges, item)
		initial = ok and tonumber(initial) or nil
		if initial ~= nil and initial > 0 then
			local before = purchase.before_ids and purchase.before_ids[id]
			local previous = self.nativePurchaseObservedStates[id]
			local base = type(before) == "table" and tonumber(before.charges) or 0
			if previous ~= nil and previous.entity == item then
				base = math.max(base or 0, tonumber(previous.charges) or 0)
			end
			state.charges = math.min(tonumber(state.charges) or 0, (base or 0) + initial)
		end
	end
	state.entity = item
	self.nativePurchaseObservedStates[id] = state
end

function CDota2RpgDemo:ReconcileNativePurchaseOrders()
	-- Extra heroes may receive an item without dota_item_purchased. An accepted
	-- order alone is not proof of success: require a new entity or changed stack.
	self:PruneNativePurchaseOrderContexts()
	-- Event-confirmed results claim their evidence before silent orders inspect it.
	self:RoutePendingNativePurchases()
	self.pendingNativePurchases = self.pendingNativePurchases or {}
	self.nativePurchaseObservedStates = self.nativePurchaseObservedStates or {}
	local observed = self.nativePurchaseObservedStates
	for _, context in ipairs(self.nativePurchaseOrderContexts or {}) do
		local found = not context.reconciled and self:FindNewPurchasedItem(context, observed) or nil
		if found ~= nil then
			self:ObserveNativePurchaseItem(found.item, context)
			context.observed_item_id = found.item_id
			context.reconciled = true
			context.attempts = 0
			table.insert(self.pendingNativePurchases, context)
			self.nativeShopTransactionPending = true
			self:LogNativePurchase(context, "reconcile", "item-observed-without-event")
		end
	end
	-- Consume native wallet coverage once for the whole observed batch.
	self:RoutePendingNativePurchases()
end

function CDota2RpgDemo:PruneNativePurchaseOrderContexts()
	local contexts = self.nativePurchaseOrderContexts or {}
	local now = self:GetNativePurchaseClock()
	local tick = self.nativePurchaseTick or 0
	local fresh = {}
	for _, context in ipairs(contexts) do
		-- 订单过滤到购买事件应在同一帧/很短时间内完成；失败订单不能污染下一次购买。
		local freshByTime = context.created_at == nil or now == 0 or now - context.created_at <= 0.75
		local freshByTick = context.created_tick == nil or tick - context.created_tick <= 3
		if freshByTime and freshByTick then
			table.insert(fresh, context)
		elseif not context.reconciled then
			self:LogNativePurchase(context, "expire", "no-purchase-result")
		end
	end
	self.nativePurchaseOrderContexts = fresh
end

function CDota2RpgDemo:CollectManagedItemIds()
	local ids = {}
	local seenUnits = {}
	local function collect(unit)
		if unit == nil or unit.GetItemInSlot == nil or seenUnits[unit] then
			return
		end
		seenUnits[unit] = true
		for slot = 0, NATIVE_STASH_LAST_SLOT do
			local item = unit:GetItemInSlot(slot)
			local itemId = self:GetItemEntityId(item)
			if itemId ~= "" then
				ids[itemId] = self:GetItemPersistentState(item)
			end
		end
	end
	collect(self:GetStashUnit())
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
		collect(hero)
	end
	for _, hero in ipairs(self.benchUnits or {}) do
		collect(hero)
	end
	return ids
end

function CDota2RpgDemo:ItemPurchaseStateChanged(before, item)
	if type(before) ~= "table" or not self:IsLiveItem(item) then
		return false
	end
	local current = self:GetItemPersistentState(item)
	return before.name == current.name
		and tonumber(current.charges) ~= nil and tonumber(before.charges) ~= nil
		and tonumber(current.charges) > tonumber(before.charges)
end

function CDota2RpgDemo:FindNewPurchasedItem(purchase, observed, forRouting)
	local exact = {}
	local changedExact = {}
	local anyNew = {}
	local seenUnits = {}
	local claimed = self.nativePurchaseClaimedIds or {}
	local function inspect(unit)
		if unit == nil or unit.GetItemInSlot == nil or seenUnits[unit] then
			return
		end
		seenUnits[unit] = true
		for slot = 0, NATIVE_STASH_LAST_SLOT do
			local item = unit:GetItemInSlot(slot)
			local itemId = self:GetItemEntityId(item)
			local before = purchase.before_ids ~= nil and purchase.before_ids[itemId] or nil
			local isNew = itemId ~= "" and before == nil
			local isChanged = itemId ~= "" and before ~= nil
				and item:GetAbilityName() == purchase.item_name
				and self:ItemPurchaseStateChanged(before, item)
			local claim = itemId ~= "" and claimed[itemId] or nil
			local availableForRecipient = (observed ~= nil and not forRouting) or claim == nil or claim == purchase.recipient_key
			local unusedEvidence = purchase.observed_item_id == itemId or observed == nil or observed[itemId] == nil
				or observed[itemId].entity ~= item or self:ItemPurchaseStateChanged(observed[itemId], item)
			if itemId ~= "" and availableForRecipient and unusedEvidence and (isNew or isChanged) then
				local candidate = { holder = unit, item = item, item_id = itemId, changed = isChanged }
				if isNew then
					table.insert(anyNew, candidate)
				end
				if item:GetAbilityName() == purchase.item_name then
					table.insert(exact, candidate)
					if isChanged then
						table.insert(changedExact, candidate)
					end
				end
			end
		end
	end
	inspect(self:GetStashUnit())
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
		inspect(hero)
	end
	for _, hero in ipairs(self.benchUnits or {}) do
		inspect(hero)
	end
	-- 先处理已有实体的 charge 变化，再处理真正新增的实体；否则第二个快速购买
	-- 可能把第一个目标刚得到的新堆误认为本次购买结果。
	if #changedExact > 0 then
		return changedExact[1]
	end
	if #exact > 0 then
		return exact[1]
	end
	-- 没有可按购买名称确认的新实体时不猜测并转移无关物品；合成结果留在原版默认载体，避免误搬运。
	return purchase.item_name == "" and #anyNew == 1 and anyNew[1] or nil
end

function CDota2RpgDemo:FindClaimedPurchaseItem(purchase, recipient)
	local claimed = self.nativePurchaseClaimedIds or {}
	local seenUnits = {}
	local function inspect(unit)
		if unit == nil or unit.GetItemInSlot == nil or seenUnits[unit] then
			return nil
		end
		if recipient ~= nil and unit ~= recipient then
			return nil
		end
		seenUnits[unit] = true
		for slot = 0, NATIVE_STASH_LAST_SLOT do
			local item = unit:GetItemInSlot(slot)
			local itemId = self:GetItemEntityId(item)
			if itemId ~= "" and claimed[itemId] ~= nil
				and (recipient == nil or claimed[itemId] == purchase.recipient_key)
				and self:IsLiveItem(item) and item:GetAbilityName() == purchase.item_name
				and self:ItemPurchaseStateChanged(purchase.before_ids and purchase.before_ids[itemId], item) then
				return { holder = unit, item = item, item_id = itemId,
					claimed_recipient = claimed[itemId] }
			end
		end
		return nil
	end
	if recipient ~= nil then
		return inspect(recipient)
	end
	local found = inspect(self:GetStashUnit())
	if found ~= nil then return found end
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
		found = inspect(hero)
		if found ~= nil then return found end
	end
	for _, hero in ipairs(self.benchUnits or {}) do
		found = inspect(hero)
		if found ~= nil then return found end
	end
	return nil
end

function CDota2RpgDemo:SplitMergedPurchaseStack(purchase, claimed, recipient)
	if claimed == nil or recipient == nil or claimed.item == nil then
		return false, nil
	end
	local before = purchase.before_ids ~= nil and purchase.before_ids[claimed.item_id] or nil
	if type(before) ~= "table" or before.charges == nil
		or claimed.item.GetCurrentCharges == nil or claimed.item.SetCurrentCharges == nil
		or recipient.AddItemByName == nil then
		return false, nil
	end
	local okCurrent, currentCharges = pcall(function() return claimed.item:GetCurrentCharges() end)
	currentCharges = okCurrent and tonumber(currentCharges) or nil
	local previousCharges = tonumber(before.charges)
	if currentCharges == nil or previousCharges == nil or currentCharges <= previousCharges then
		return false, nil
	end

	-- AddItemByName 在原版可能把新购买合并到目标已有同名堆；先记录该堆，
	-- 这样不会把已有的 20 charges 重置成 1。
	local existingChargesById = {}
	if recipient.GetItemInSlot ~= nil then
		for slot = 0, NATIVE_STASH_LAST_SLOT do
			local candidate = recipient:GetItemInSlot(slot)
			if self:IsLiveItem(candidate) and candidate.GetAbilityName ~= nil
				and candidate:GetAbilityName() == purchase.item_name then
				local candidateId = self:GetItemEntityId(candidate)
				local candidateCharges = nil
				if candidate.GetCurrentCharges ~= nil then
					local okExisting, value = pcall(function() return candidate:GetCurrentCharges() end)
					candidateCharges = okExisting and tonumber(value) or nil
				end
				if candidateId ~= "" then
					existingChargesById[candidateId] = candidateCharges
				end
			end
		end
	end

	local added = nil
	local okAdd = pcall(function()
		added = recipient:AddItemByName(purchase.item_name)
	end)
	if not okAdd or not self:IsLiveItem(added) then
		-- 某些 API 在合并后返回失效实体；重新从目标槽位取得真实堆。
		if recipient.GetItemInSlot ~= nil then
			for slot = 0, NATIVE_STASH_LAST_SLOT do
				local candidate = recipient:GetItemInSlot(slot)
				if self:IsLiveItem(candidate) and candidate.GetAbilityName ~= nil
					and candidate:GetAbilityName() == purchase.item_name then
					added = candidate
					break
				end
			end
		end
	end
	if not self:IsLiveItem(added) or added.GetCurrentCharges == nil or added.SetCurrentCharges == nil then
		return false, nil
	end

	local addedId = self:GetItemEntityId(added)
	local existingCharges = addedId ~= "" and existingChargesById[addedId] or nil
	local mergedIntoExisting = existingCharges ~= nil
	local okAddedCurrent, addedCurrent = pcall(function() return added:GetCurrentCharges() end)
	addedCurrent = okAddedCurrent and tonumber(addedCurrent) or nil
	local targetBeforeCharges = mergedIntoExisting and existingCharges or addedCurrent
	local targetCharges = 1
	if mergedIntoExisting then
		-- Dota 可能已经在 AddItemByName 内完成了 +1；不要再加一次。
		targetCharges = (addedCurrent ~= nil and existingCharges ~= nil and addedCurrent > existingCharges)
			and addedCurrent or ((existingCharges or 0) + 1)
	end
	local function rollbackTarget()
		if mergedIntoExisting then
			pcall(function() added:SetCurrentCharges(targetBeforeCharges) end)
		elseif recipient.RemoveItem ~= nil then
			pcall(function() recipient:RemoveItem(added) end)
			if self:IsLiveItem(added) and UTIL_Remove ~= nil then
				pcall(function() UTIL_Remove(added) end)
			end
		end
	end
	if targetBeforeCharges == nil then
		if mergedIntoExisting then
			rollbackTarget()
			return false, nil
		end
		-- 新建实体在部分测试/工具 API 中尚未返回初始 charge；原版购买的一份按 1 处理。
		targetBeforeCharges = 0
	end

	local okTarget = pcall(function()
		added:SetCurrentCharges(targetCharges)
	end)
	if not okTarget then
		rollbackTarget()
		return false, nil
	end
	local okSource = pcall(function()
		claimed.item:SetCurrentCharges(currentCharges - 1)
	end)
	if not okSource then
		-- 两个实体都还活着时尽量恢复到 AddItemByName 之前的精确 charge；
		-- 新建的拆分实体则直接移除，避免回滚失败时凭空多出一件物品。
		rollbackTarget()
		return false, nil
	end

	self:SyncHeroInventoryFromUnit(recipient)
	print(string.format("[Dota2Rpg] Split one %s charge from merged purchase stack to %s.",
		purchase.item_name, tostring(purchase.recipient_key)))
	return true, added
end

function CDota2RpgDemo:GetPendingNativePurchaseReservation()
	self:PruneNativePurchaseOrderContexts()
	local total = 0
	local earliestBefore = nil
	local seen = {}
	local function include(purchase)
		if seen[purchase] then return end
		seen[purchase] = true
		local cost = tonumber(purchase.item_cost or purchase.itemcost or purchase.cost)
		if cost ~= nil and cost > 0 and not purchase.gold_checked and not purchase.gold_failed then
			total = total + math.floor(cost)
		end
		local before = tonumber(purchase.gold_before)
		if before ~= nil and not purchase.gold_checked and not purchase.gold_failed
			and (earliestBefore == nil or before < earliestBefore) then
			earliestBefore = before
		end
	end
	for _, purchase in ipairs(self.nativePurchaseOrderContexts or {}) do include(purchase) end
	for _, purchase in ipairs(self.pendingNativePurchases or {}) do include(purchase) end

	local observed = 0
	if earliestBefore ~= nil then
		observed = math.max(0, earliestBefore - self:GetGoldBalance())
	end
	-- A price check reserves only the part not already debited by the native shop.
	-- This permits a second order after an immediate first native debit without
	-- allowing multiple engine-free orders to consume the same balance.
	return total, math.min(total, observed)
end

function CDota2RpgDemo:CanAffordNativePurchase(itemName, payload)
	local cost = self:GetNativePurchaseCost(itemName, payload)
	if cost == nil or cost <= 0 then
		return false, nil
	end
	local reserved, observed = self:GetPendingNativePurchaseReservation()
	local available = self:GetGoldBalance() - math.max(0, reserved - observed)
	return available >= cost, cost
end

function CDota2RpgDemo:RevertUnpaidNativePurchase(purchase)
	local found = self:FindNewPurchasedItem(purchase)
	if found == nil or found.holder == nil or found.item == nil then
		return false
	end
	local before = purchase.before_ids ~= nil and purchase.before_ids[found.item_id] or nil
	if found.changed and type(before) == "table" and before.charges ~= nil
		and found.item.SetCurrentCharges ~= nil then
		local ok = pcall(function() found.item:SetCurrentCharges(before.charges) end)
		return ok
	end
	if found.holder.RemoveItem ~= nil then
		pcall(function() found.holder:RemoveItem(found.item) end)
	end
	if self:IsLiveItem(found.item) and UTIL_Remove ~= nil then
		pcall(function() UTIL_Remove(found.item) end)
	end
	return true
end

function CDota2RpgDemo:DebitNativePurchase(purchase, walletState)
	if purchase == nil then
		return false
	end
	if purchase.gold_checked then
		return purchase.gold_debit_ok == true
	end
	if purchase.gold_failed then
		return false
	end

	local cost = tonumber(purchase.item_cost or purchase.itemcost or purchase.cost)
	if cost == nil or cost <= 0 then
		cost = self:GetNativePurchaseCost(purchase.item_name, purchase.event)
	end
	if cost == nil or cost <= 0 then
		purchase.gold_failed = true
		print(string.format("[Dota2Rpg] WARNING: native purchase %s had no readable cost; rejecting unpaid result.",
			tostring(purchase.item_name)))
		return false
	end
	cost = math.floor(cost)
	local before = tonumber(purchase.gold_before)
	if before == nil or walletState == nil then
		purchase.gold_failed = true
		print(string.format("[Dota2Rpg] WARNING: native purchase %s had no wallet snapshot; rejecting unpaid result.",
			tostring(purchase.item_name)))
		return false
	end

	-- A single Think can receive several purchase events. Compare the wallet
	-- decrease once for the batch, then consume that observed decrease in order;
	-- the total native coverage is min(observed decrease, total ordered cost), so
	-- mixed-cost batches cannot be overcharged or undercharged.
	local nativeCovered = math.min(walletState.observed_decrease, cost)
	walletState.observed_decrease = walletState.observed_decrease - nativeCovered
	local missing = cost - nativeCovered
	if missing > 0 and not self:SpendGold(missing) then
		purchase.gold_failed = true
		print(string.format("[Dota2Rpg] WARNING: native purchase %s charge failed; rejecting unpaid result.",
			tostring(purchase.item_name)))
		return false
	end

	purchase.gold_checked = true
	purchase.gold_debit_ok = true
	purchase.gold_source = missing > 0
		and (nativeCovered > 0 and "mixed" or "rpg")
		or "native"
	self:LogNativePurchase(purchase, "debit", purchase.gold_source .. ":" .. tostring(missing))
	return true
end

function CDota2RpgDemo:RoutePendingNativePurchases()
	local pending = self.pendingNativePurchases or {}
	self.nativePurchaseObservedStates = self.nativePurchaseObservedStates or {}
	local observed = self.nativePurchaseObservedStates
	local walletState = nil
	for _, purchase in ipairs(pending) do
		local before = tonumber(purchase.gold_before)
		if before ~= nil and not purchase.gold_checked and not purchase.gold_failed then
			local current = self:GetGoldBalance()
			walletState = {
				observed_decrease = math.max(0, before - current),
			}
			break
		end
	end
	local remaining = {}
	for _, purchase in ipairs(pending) do
		purchase.attempts = (purchase.attempts or 0) + 1
		local paid = self:DebitNativePurchase(purchase, walletState)
		local recipient = self:ResolveNativePurchaseRecipient(purchase.recipient_key)
		local routed = false
		if not paid then
			-- Never route an item whose charge was rejected or whose price/snapshot
			-- was unknowable. Remove only the newly created/changed result; an
			-- existing stack is restored to its pre-order charges.
			if purchase.gold_failed and (self:RevertUnpaidNativePurchase(purchase)
				or purchase.attempts >= 10) then
				routed = true
			end
		elseif recipient == nil or not self:IsEquipmentCarrier(recipient) then
			routed = true -- 阵容已变化；保留原版购买结果，不向失效实体搬运。
		elseif recipient == self:GetStashUnit() then
			local found = self:FindNewPurchasedItem(purchase, observed, true)
			if found ~= nil then self:ObserveNativePurchaseItem(found.item, purchase) end
			routed = true -- 小精灵就是原版购买的默认接收者。
		else
			local found = self:FindNewPurchasedItem(purchase, observed, true)
			if found ~= nil then
				purchase.observed_item_id = found.item_id
				self:ObserveNativePurchaseItem(found.item, purchase)
			end
			if found == nil then
				-- 同一目标的后续购买可能继续合并到已路由实体；无需再次搬运。
				found = self:FindClaimedPurchaseItem(purchase, recipient)
				if found ~= nil then
					self:ObserveNativePurchaseItem(found.item, purchase)
					print(string.format("[Dota2Rpg] Native purchase merged into the already routed %s stack.",
						purchase.item_name))
					routed = true
				else
					-- 不同目标各买一份可堆叠物品时，按一次新增 charge 拆出一份，避免整堆错误归属。
					local claimed = self:FindClaimedPurchaseItem(purchase, nil)
					if claimed ~= nil and claimed.holder ~= recipient then
						local split, splitItem = self:SplitMergedPurchaseStack(purchase, claimed, recipient)
						if split then
							self:ObserveNativePurchaseItem(claimed.item)
							self:ObserveNativePurchaseItem(splitItem)
							self.nativePurchaseClaimedIds = self.nativePurchaseClaimedIds or {}
							local splitId = self:GetItemEntityId(splitItem)
							if splitId ~= "" then
								self.nativePurchaseClaimedIds[splitId] = purchase.recipient_key
							end
							routed = true
						end
					end
				end
			end
			if found ~= nil and not routed then
				-- FindNewPurchasedItem 已排除归属另一名英雄的已认领堆；留在这里的
				-- charge 变化仍是本次未认领原版购买实体，应整体转交而非拆掉旧 charge。
				self.nativePurchaseClaimedIds = self.nativePurchaseClaimedIds or {}
				self.nativePurchaseClaimedIds[found.item_id] = purchase.recipient_key
				if found.holder == recipient then
					routed = true
				else
					local itemNameForLog = found.item.GetAbilityName ~= nil and found.item:GetAbilityName() or purchase.item_name
					found.holder:TakeItem(found.item)
					if not self:TryAttachItem(recipient, found.item) then
						local preserved = self:PreserveDetachedItem(found.item, found.holder, "direct purchase routing failed")
						purchase.transfer_decision = preserved and "attachment-failed-preserved" or "attachment-failed"
						self.nativePurchaseClaimedIds[found.item_id] = nil
					else
						local heroName = self:GetEquipmentHeroName(recipient)
						if heroName ~= nil then
							self:SyncHeroInventoryFromUnit(recipient)
						end
						print(string.format("[Dota2Rpg] Native purchase routed: %s -> %s.",
							itemNameForLog, tostring(purchase.recipient_key)))
					end
					routed = true
				end
			end
		end
		if routed or purchase.attempts >= 10 then
			self:LogNativePurchase(purchase, "transfer", purchase.gold_failed and "unpaid-reverted" or purchase.transfer_decision or (routed and "resolved" or "item-not-found"))
		end
		if not routed and purchase.attempts < 10 then
			table.insert(remaining, purchase)
		elseif not routed then
			print(string.format("[Dota2Rpg] WARNING: could not locate purchased item %s for %s; kept native result.",
				tostring(purchase.item_name), tostring(purchase.recipient_key)))
		end
	end
	self.pendingNativePurchases = remaining
	if walletState ~= nil then
		local unspentBaseline = self:GetGoldBalance() + walletState.observed_decrease
		for _, context in ipairs(self.nativePurchaseOrderContexts or {}) do
			if not context.gold_checked and not context.gold_failed and context.gold_before ~= nil then
				context.gold_before = math.min(context.gold_before, unspentBaseline)
			end
		end
	end
end

function CDota2RpgDemo:OnNativeItemPurchased(event)
	local playerId = tonumber(event ~= nil and (event.PlayerID or event.player_id or event.playerid) or -1) or -1
	if self.phase == "setup" and playerId == self.playerId then
		self:PruneNativePurchaseOrderContexts()
		self.nativePurchaseOrderContexts = self.nativePurchaseOrderContexts or {}
		local itemName = tostring(event.itemname or event.item_name or "")
		local contextIndex = nil
		-- 只有订单和事件都带有同一个 item name 时才消费上下文；
		-- 未关联的事件宁可留在小精灵，也不能使用当前选中英雄误路由。
		if itemName ~= "" then
			for index, candidate in ipairs(self.nativePurchaseOrderContexts) do
				if candidate.item_name ~= nil and candidate.item_name ~= ""
					and candidate.item_name == itemName then
					contextIndex = index
					break
				end
			end
		end
		local context = contextIndex ~= nil and table.remove(self.nativePurchaseOrderContexts, contextIndex) or nil
		if context ~= nil and context.reconciled then
			self:LogNativePurchase(context, "event", "already-reconciled")
			return
		end
		if context == nil then
			-- Events have no transaction identifier. Without a live preflight they
			-- cannot distinguish a duplicate/late notification from a new purchase.
			self:LogNativePurchase({ item_name = itemName }, "event", "unmatched-ignored")
			self.nativeShopTransactionPending = true
			return
		end
		context.item_name = itemName
		context.event = event
		context.item_cost = context.item_cost or self:GetNativePurchaseCost(itemName, event)
		context.attempts = 0
		self:LogNativePurchase(context, "event", "queued")
		table.insert(self.pendingNativePurchases, context)
		-- 事件可能在引擎真正扣款/入栏的同一帧触发；下一轮 Think 再定位新实体并同步钱包。
		self.nativeShopTransactionPending = true
	end
end

function CDota2RpgDemo:MoveStashItemToHero(heroName, itemName, itemId)
	local hero = self:FindOwnedHeroUnit(heroName)
	if hero == nil or self.heroData[heroName] == nil then
		return false
	end
	local source = self:GetStashUnit()
	if source == nil then
		return false
	end
	-- 同名装备只能按实体 ID 区分。缺少实体 API 的离线宿主退回名称+ID 的旧路径，
	-- 正式地图一定能解析，届时实体不存在就直接拒绝，不做模糊匹配。
	local item = EntIndexToHScript ~= nil and EntIndexToHScript(tonumber(itemId) or -1) or nil
	local neutral = false
	if self:IsLiveItem(item) then
		if item:GetAbilityName() ~= itemName
			or not self:IsItemHeldBy(source, item, 0, CARRIER_LAST_SLOT) then
			return false
		end
		-- 中立装备只占英雄的专属中立槽（容量 1），不占用物品栏/背包；
		-- 普通装备仍然必须先有 0..8 的空位。槽位判定来自装备当前所在槽，不靠名称猜测。
		neutral = self:IsItemHeldBy(source, item, NEUTRAL_ITEM_SLOT, NEUTRAL_ITEM_SLOT)
	elseif EntIndexToHScript ~= nil then
		return false
	end
	if neutral then
		if self:GetNeutralSlotItem(hero) ~= nil then
			return false
		end
	elseif self:FindEmptyCarrierSlot(hero) == nil then
		return false
	end
	if self.issueFixes ~= nil and self:IsLiveItem(item) then
		return self.issueFixes:TransferWarehouseItem(self.playerId, source, item, hero)
	end
	local taken = self:TakeStashItem(itemName, itemId)
	if taken == nil then
		return false
	end
	local attached = self:TryAttachItem(hero, taken)
	if attached and (self:IsItemHeldBy(hero, taken, 0, CARRIER_LAST_SLOT) or not self:IsLiveItem(taken)) then
		self:SyncHeroInventoryFromUnit(hero)
		return true
	end
	-- AddItem 失败时绝不吞物品：从英雄物品栏/背包/原生储藏栏移除后原样还给小精灵。
	if self:IsItemHeldBy(hero, taken, 0, CARRIER_LAST_SLOT) then
		hero:TakeItem(taken)
	end
	self:PreserveDetachedItem(taken, self:GetStashUnit(), "equip rollback failed")
	return false
end

function CDota2RpgDemo:MoveHeroItemToStash(hero, item)
	if hero == nil or not self:IsLiveItem(item) then
		return false
	end
	local stash = self:GetStashUnit()
	if stash == nil then
		return false
	end
	-- 中立装备回小精灵的专属中立槽；它不占用物品栏/背包/储藏栏，反之亦然。
	local neutral = self:IsItemHeldBy(hero, item, NEUTRAL_ITEM_SLOT, NEUTRAL_ITEM_SLOT)
	if neutral then
		if self:GetNeutralSlotItem(stash) ~= nil then
			return false
		end
	elseif not self:HasFreeStashSlot() then
		return false
	end
	hero:TakeItem(item)
	if self:PutItemInStash(item, neutral) then
		self:SyncHeroInventoryFromUnit(hero)
		return true
	end
	-- 库存移动失败时把原实体归还给原英雄；若引擎仍拒绝，保留在英雄脚下。
	self:PreserveDetachedItem(item, hero, "unequip rollback failed")
	self:SyncHeroInventoryFromUnit(hero)
	return false
end

function CDota2RpgDemo:OnItemEquip(_, payload)
	if payload ~= nil and payload.PlayerID ~= nil
		and tonumber(payload.PlayerID) ~= self.playerId then return end
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

function CDota2RpgDemo:OnItemSell(_, payload)
    -- PlayerID is supplied by the engine, not inferred from client selection.
    if type(payload) ~= "table" or self.playerId == nil or self.playerId < 0
        or tonumber(payload.PlayerID) ~= self.playerId then return end
    local ok, reason, refund = ItemSales.Sell(self, payload)
    if ok then self:SyncLiveEquipmentState(true) end
    local player = PlayerResource:GetPlayer(self.playerId)
    if player ~= nil then
        CustomGameEventManager:Send_ServerToPlayer(player, "rpg_item_sell_result", {
            request_id = tonumber(payload.request_id) or 0,
            item_index = tostring(payload.item_index or ""),
            ok = ok and 1 or 0, reason = reason, refund = refund,
        })
    end
end

function CDota2RpgDemo:OnItemUnequip(_, payload)
	if payload ~= nil and payload.PlayerID ~= nil
		and tonumber(payload.PlayerID) ~= self.playerId then return end
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
	local hero = self:FindOwnedHeroUnit(heroName)
	if hero == nil then
		return
	end
	local item = nil
	if itemName ~= "" then
		-- 面板按装备名称请求，服务端仍从真实槽位寻找，兼容玩家手动调整槽位。
		for candidateSlot = 0, CARRIER_LAST_SLOT do
			local candidate = hero:GetItemInSlot(candidateSlot)
			if self:IsLiveItem(candidate) and candidate:GetAbilityName() == itemName
				and (expectedItemId == "" or self:GetItemEntityId(candidate) == expectedItemId) then
				item = candidate
				break
			end
		end
	elseif slot >= 0 and slot <= CARRIER_LAST_SLOT then
		local candidate = hero:GetItemInSlot(slot)
		if self:IsLiveItem(candidate) and self:GetItemEntityId(candidate) == expectedItemId then
			item = candidate
		end
	end
	if self:IsLiveItem(item) and item:GetAbilityName() == GrisGris.ITEM then return end
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

function CDota2RpgDemo:FindBenchUnit(heroName)
	for _, hero in ipairs(self.benchUnits or {}) do
		if TacticEngine.IsValidUnit(hero) and (hero.benchHeroName or hero:GetUnitName()) == heroName then
			return hero
		end
	end
	return nil
end

function CDota2RpgDemo:FindOwnedHeroUnit(heroName)
	return self:FindLineupUnit(heroName) or self:FindBenchUnit(heroName)
end

------------------------------------------------------------------
-- 战斗速度 1x/2x 与跳过（跳过 = 极限时间缩放快进到结算）
------------------------------------------------------------------





-- XP 结算与升级统一由 patches/progression_patch.lua 提供，避免累计阈值被重复相加。
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
	local selectedSet = {}
	for _, owned in ipairs(self.ownedHeroes) do
		ownedSet[owned] = true
	end
	for _, heroName in ipairs(ReadPayloadList(payload, "lineup_text", "lineup") or {}) do
		heroName = tostring(heroName)
		if ownedSet[heroName] and not selectedSet[heroName] and #lineup < self.shopCosts.lineup_max then
			selectedSet[heroName] = true
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
	-- The issue-fixes arena owns the divider. The old entity row created a
	-- second set of trees (and floating props on some maps).
	if self.issueFixes ~= nil and self.issueFixes.arena ~= nil then
		self.issueFixes.arena:CloseMiddleGate()
		self.barrierUnits = nil
		return
	end
	self:RemoveBattleBarrier()
	self.barrierUnits = {}
	local y = -BARRIER_HALF_SPAN
	while y <= BARRIER_HALF_SPAN do
		local pos = GetGroundPosition(Vector(BARRIER_X, y, 128), nil)
		local ok, tree = pcall(CreateTempTree, pos, 86400)
		if ok and tree ~= nil then
			table.insert(self.barrierUnits, tree)
		else
			break
		end
		y = y + BARRIER_SPACING
	end
	print("[Dota2Rpg] Battle barrier spawned (legacy fallback).")
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
	-- 中立装备由引擎放进专属中立槽 16，不占用物品栏/背包/储藏栏。
	-- 槽位被占用时绝不发起创建：引擎无处安放就会把新实体丢到地上，等于凭空丢奖励。
	if CampaignLoot.IsNeutralName(itemName) then
		if self:GetNeutralSlotItem(stash) ~= nil then
			return false -- 指挥官的中立槽已被占用，转交后再交付
		end
		local item = stash:AddItemByName(itemName)
		if item == nil or item:IsNull() then
			return false
		end
		-- 只有确认它真的落在指挥官身上才算交付，否则等于退回成地面掉落。
		return self:IsItemHeldBy(stash, item, 0, CARRIER_LAST_SLOT)
	end
	-- 物品栏 0..5 + 背包 6..8 + 原生储藏栏 9..14。
	for slot = 0, NATIVE_STASH_LAST_SLOT do
		if stash:GetItemInSlot(slot) == nil then
			local item = stash:AddItemByName(itemName)
			return item ~= nil and not item:IsNull()
		end
	end
	return false -- 小精灵物品栏、背包和原生储藏栏均已满
end

function CDota2RpgDemo:RemoveBattleBarrier()
	if self.issueFixes ~= nil and self.issueFixes.arena ~= nil then
		self.issueFixes.arena:OpenMiddleGate()
		self.barrierUnits = nil
		return
	end
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

function CDota2RpgDemo:CaptureHeroInventoryForRespawn(hero)
	self:CaptureHeroAbilities(hero)
	if not TacticEngine.IsValidUnit(hero) or hero.GetItemInSlot == nil then
		return
	end
	GrisGris.Capture(self, hero)
	self:SyncHeroInventoryFromUnit(hero)
	for slot = 0, CARRIER_LAST_SLOT do
		local item = hero:GetItemInSlot(slot)
		if self:IsLiveItem(item) and hero.TakeItem ~= nil then
			-- 脱离旧单位但保留同一个实体，稍后交给新上阵或新待命实例。
			hero:TakeItem(item)
		end
	end
end

function CDota2RpgDemo:FindHeldItemByName(unit, itemName)
	if unit == nil or unit.GetItemInSlot == nil or itemName == nil or itemName == "" then
		return nil
	end
	for slot = 0, CARRIER_LAST_SLOT do
		local item = unit:GetItemInSlot(slot)
		if self:IsLiveItem(item) and item.GetAbilityName ~= nil and item:GetAbilityName() == itemName then
			return item
		end
	end
	return nil
end

function CDota2RpgDemo:RestoreHeroInventoryToUnit(heroName, hero)
	local heroData = self.heroData[heroName]
	if heroData == nil or hero == nil then
		return
	end
	ShardPurchase.Restore(self, heroName, hero)
	GrisGris.BeforeRestore(self, hero)
	local priorInventory = heroData.inventory or {}
	local priorStates = heroData.inventory_states or {}
	local priorEntities = heroData.inventory_entities or {}
	local restoredInventory = {}
	local restoredStates = {}
	local restoredEntities = {}
	local recordedEntityIds = {}
	for inventoryIndex, itemName in ipairs(priorInventory) do
		local item = priorEntities[inventoryIndex]
		local state = priorStates[inventoryIndex] or { name = itemName }
		local originalItem = item
		local hadLiveEntity = self:IsLiveItem(item)
		local merged = false
		if hadLiveEntity then
			local attached, attachedItem = self:TryAttachItem(hero, item)
			if attached and attachedItem ~= nil then
				item = attachedItem
				merged = item ~= originalItem
			end
		elseif hero.AddItemByName ~= nil then
			-- 只有旧实体已被引擎清理时才允许按名称重建；若原版把它合并到
			-- 新单位已有同名堆，不能再把这一条旧记录的 charges 覆盖到聚合堆上。
			local existingBefore = self:FindHeldItemByName(hero, itemName)
			local recreated = nil
			local okRecreate = pcall(function()
				recreated = hero:AddItemByName(itemName)
			end)
			if okRecreate and self:IsLiveItem(recreated) then
				item = recreated
			else
				item = self:FindHeldItemByName(hero, itemName)
			end
			if existingBefore ~= nil and self:IsLiveItem(item)
				and self:GetItemEntityId(existingBefore) == self:GetItemEntityId(item) then
				merged = true
			end
			print(string.format("[Dota2Rpg] WARNING: missing item entity for %s; recreated once.", itemName))
		end

		if self:IsItemHeldBy(hero, item, 0, CARRIER_LAST_SLOT) then
			local entityId = self:GetItemEntityId(item)
			if entityId ~= "" and not recordedEntityIds[entityId] then
				local stateToStore = merged and self:GetItemPersistentState(item) or state
				if not merged then
					self:RestoreItemPersistentState(item, state)
				end
				recordedEntityIds[entityId] = true
				table.insert(restoredInventory, item:GetAbilityName())
				table.insert(restoredStates, stateToStore)
				table.insert(restoredEntities, item)
			end
		elseif self:IsLiveItem(item) then
			-- 新单位异常拒绝物品时，把原实体退到小精灵或地面，并从个人库存记录移除。
			self:PreserveDetachedItem(item, self:GetStashUnit(),
				"roster respawn could not restore " .. tostring(itemName))
		end
	end
	heroData.inventory = restoredInventory
	heroData.inventory_states = restoredStates
	heroData.inventory_entities = restoredEntities
	-- 以新单位的真实槽位再校准一次，尤其覆盖原版堆叠合并后只剩一个实体的情况。
	GrisGris.Reconcile(self, hero)
	self:SyncHeroInventoryFromUnit(hero)
end

function CDota2RpgDemo:ClearBenchHeroesForRespawn()
	local lifecycle = require("issue_fixes.hero_lifecycle_log")
	for _, unit in ipairs(self.benchUnits or {}) do
		if TacticEngine.IsValidUnit(unit) then
			self:CaptureHeroInventoryForRespawn(unit)
			lifecycle.Remove(self, unit, "bench")
		end
	end
	self.benchUnits = {}
end

-- 生成场下英雄到待命区（无敌/禁足展示，不参与战斗与胜负判定，但可选中并直接购买/管理装备）
function CDota2RpgDemo:SpawnBenchHeroes()
	local lifecycle = require("issue_fixes.hero_lifecycle_log")
	self.benchUnits = self.benchUnits or {}
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
			-- 先以无玩家 owner 创建，避免 npc_spawned 把它误判为玩家主英雄并移到指挥官位置；随后绑定玩家控制权。
			local unit = lifecycle.Create(self, heroName, pos, DOTA_TEAM_GOODGUYS, "bench")
			if TacticEngine.IsValidUnit(unit) then
				FindClearSpaceForUnit(unit, pos, true)
				local data = self.heroData[heroName]
				self.autoAbilityHeroes = self.autoAbilityHeroes or {}
				self.autoAbilityHeroes[unit:GetEntityIndex()] = nil
				unit.benchHeroName = heroName
				self:PrepareBattleHero(unit, data ~= nil and data.level or 1)
				if not self:BindEquipmentCarrierToPlayer(unit) then
					self.autoAbilityHeroes[unit:GetEntityIndex()] = nil
					lifecycle.Remove(self, unit, "bench_unbound")
					print(string.format("[Dota2Rpg] Refused unbound bench hero %s.", heroName))
				else
					self:RestoreHeroInventoryToUnit(heroName, unit)
					if data ~= nil and QUALITY_CONSUMED_MODIFIERS[data.quality] ~= nil then
						for _, modifierName in ipairs(QUALITY_CONSUMED_MODIFIERS[data.quality]) do
							unit:AddNewModifier(unit, nil, modifierName, {})
						end
					end
					table.insert(self.benchUnits, unit)
					lifecycle.Event(self, "ready", "role=bench " .. lifecycle.Snapshot(unit))
				end
			end
		end
	end
end

function CDota2RpgDemo:RespawnPlayerRoster()
	local lifecycle = require("issue_fixes.hero_lifecycle_log")
	if self.phase ~= "setup" then
		return
	end
	RuntimeLog.Write(string.format("Wallet roster_before player=%s native=%s mirror=%s initialized=%s owned=%s lineup=%s",
		tostring(self.playerId), tostring(self:ReadNativeGold()), tostring(self.gold), tostring(self.goldWalletInitialized),
		table.concat(self.ownedHeroes or {}, ","), table.concat(self.lineup or {}, ",")))
	self.heroData = self.heroData or {}
	self:SpawnBenchEnclosure()
	-- 先收回旧待命和旧上阵实体的物品，再按新阵容分别重建，避免同一物品同时绑定两个英雄实例。
	self:ClearBenchHeroesForRespawn()
	local battleManager = self.battleManager
	for _, hero in ipairs(battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]) do
		if TacticEngine.IsValidUnit(hero) then
			-- 重铸前把身上的装备收回个人库存记录，避免随单位销毁。
			self:CaptureHeroInventoryForRespawn(hero)
			lifecycle.Remove(self, hero, "lineup")
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
		-- 先以无玩家 owner 创建，避免 npc_spawned 的玩家本体处理；生成后再绑定到小精灵玩家。
		local hero = lifecycle.Create(self, heroName, spawnPosition, DOTA_TEAM_GOODGUYS, "lineup")
		if TacticEngine.IsValidUnit(hero) then
			FindClearSpaceForUnit(hero, spawnPosition, true)
			local heroData = self:GetHeroData(heroName)
			self.autoAbilityHeroes = self.autoAbilityHeroes or {}
			self.autoAbilityHeroes[hero:GetEntityIndex()] = nil -- 上阵英雄：玩家手动加点
			hero.lineupHeroName = heroName
			self:PrepareBattleHero(hero, heroData ~= nil and heroData.level or 1)
			-- 上阵英雄必须是小精灵的玩家所有单位，才能直接执行原版购买、移动、拾取和物品转移。
			-- 战斗中的玩家订单仍会被 tactic_bridge 的 OrderFilter 拒绝。
			if not self:BindEquipmentCarrierToPlayer(hero) then
				lifecycle.Remove(self, hero, "lineup_unbound")
				print(string.format("[Dota2Rpg] Refused unbound lineup hero %s.", heroName))
			else
				local points = hero:GetAbilityPoints()
				print(string.format("[Dota2Rpg] %s fielded: level=%d skill_points=%d (player picks abilities)",
					heroName, heroData ~= nil and heroData.level or 1, points))
				-- 重新佩戴个人装备；上阵/待命转换继续使用同一物品实体。
				self:RestoreHeroInventoryToUnit(heroName, hero)
				-- 品质内置升级：魔晶/神杖（不占装备栏）
				if heroData ~= nil and QUALITY_CONSUMED_MODIFIERS[heroData.quality] ~= nil then
					for _, modifierName in ipairs(QUALITY_CONSUMED_MODIFIERS[heroData.quality]) do
						hero:AddNewModifier(hero, nil, modifierName, {})
					end
				end
				battleManager:RegisterHero(DOTA_TEAM_GOODGUYS, index, hero)
				-- Rebuild only known generated defaults; authored lists survive respawns.
				if self.heroRulesByName[heroName] == nil
					or require("issue_fixes.default_rules").IsDefaultOnly(self.heroRulesByName[heroName]) then
					self.heroRulesByName[heroName] = BuildDefaultRulesForSlots(BuildHeroActionSlots(hero), hero)
				end
				battleManager.teamRules[DOTA_TEAM_GOODGUYS][index] = self.heroRulesByName[heroName]
				lifecycle.Event(self, "ready", "role=lineup " .. lifecycle.Snapshot(hero))
			end
		else
			print(string.format("[Dota2Rpg] Failed to spawn lineup hero %s.", heroName))
		end
	end
	self:SpawnBenchHeroes()
	-- Restored native handles can retain battle/backpack cooldowns under prepare modifiers.
	require("battle.item_cooldowns").Refresh(self)
	RuntimeLog.Write(string.format("Wallet roster_after player=%s native=%s mirror=%s initialized=%s",
		tostring(self.playerId), tostring(self:ReadNativeGold()), tostring(self.gold), tostring(self.goldWalletInitialized)))
	self.equipmentSnapshot = nil
	self:BroadcastHeroInfo()
end

-- 从 levels.kv 生成关卡敌方阵容（英雄/野怪混编，随关卡切换重建）
function CDota2RpgDemo:InvalidateEnemyPreparation()
	self.enemySpawnRequest = nil
	self.stageLoading, self.stageLoadError = false, nil
end

function CDota2RpgDemo:AwaitEnemyResources(levelId)
	if self.stagePrecache == nil or (self.skillDebug and self.skillDebug.active)
		or self.stagePrecache:IsReady(levelId) then
		self:InvalidateEnemyPreparation()
		return true
	end
	local previous = self.enemySpawnRequest
	if previous and previous.level == levelId and previous.rules == self.ruleGeneration
		and previous.settlement == self.settlementGeneration then return false end
	local request = {level = levelId, rules = self.ruleGeneration, settlement = self.settlementGeneration}
	self.enemySpawnRequest = request
	self.stageLoading, self.stageLoadError = true, nil
	self.stagePrecache:Request(levelId, function(ok, reason)
		if self.enemySpawnRequest ~= request then return end
		self.enemySpawnRequest = nil
		self.stageLoading = false
		if self.currentLevelId ~= levelId or self.phase ~= "setup"
			or self.ruleGeneration ~= request.rules or self.settlementGeneration ~= request.settlement
			or (self.skillDebug and self.skillDebug.active) then
			self:BroadcastBattleState()
			return
		end
		if ok then
			local spawned, err = xpcall(function() self:SpawnLevelEnemies(levelId) end, Traceback)
			if not spawned then
				self.stageLoading, self.stageLoadError = false, "spawn_failed"
				RuntimeLog.WriteCritical("StagePrecache spawn_failed level=" .. tostring(levelId) .. " error=" .. tostring(err))
			end
		else
			self.stageLoadError = reason or "precache_failed"
		end
		self:BroadcastHeroInfo()
		self:BroadcastBattleState()
	end)
	if self.enemySpawnRequest == request then self:BroadcastBattleState() end
	return false
end

function CDota2RpgDemo:PreloadNextLevel(levelId)
	if self.stagePrecache == nil or (self.skillDebug and self.skillDebug.active) then return end
	-- Queue the entire remaining campaign after entry, but do not load it
	-- synchronously. The cache yields between resources and prioritizes demand.
	local upcoming = false
	for _, id in ipairs(self.orderedLevels or {}) do
		if upcoming then self.stagePrecache:Prefetch(id) end
		if id == levelId then upcoming = true end
	end
end

function CDota2RpgDemo:SpawnLevelEnemies(levelId)
	if not self:AwaitEnemyResources(levelId) then return false end
	self.stageLoading = true -- Also guard native spawn callbacks until the whole roster exists.
	self.preparedEnemyLevel = nil
	local created = {}
	local ok, result = xpcall(function() return self:AssembleLevelEnemies(levelId, created) end, Traceback)
	self.stageLoading = false
	if not ok or not result then
		self.stageLoadError = "spawn_failed"
		local lifecycle = require("issue_fixes.hero_lifecycle_log")
		self.pendingEnemyCleanup = self.pendingEnemyCleanup or {}
		for _, unit in ipairs(created) do
			self.pendingEnemyCleanup[#self.pendingEnemyCleanup + 1] = unit
			pcall(lifecycle.Remove, self, unit, "enemy_spawn_failed")
		end
		RuntimeLog.WriteCritical("StagePrecache spawn_failed level=" .. tostring(levelId) .. " error=" .. tostring(result))
		self:BroadcastBattleState()
		return false
	end
	self.preparedEnemyLevel = levelId
	self:PreloadNextLevel(levelId)
	return true
end

function CDota2RpgDemo:AssembleLevelEnemies(levelId, created)
	local lifecycle = require("issue_fixes.hero_lifecycle_log")
	local battleManager = self.battleManager
	for _, unit in ipairs(self.pendingEnemyCleanup or {}) do
		if TacticEngine.IsValidUnit(unit) then lifecycle.Remove(self, unit, "enemy_spawn_failed") end
	end
	self.pendingEnemyCleanup = {}
	for _, unit in ipairs(battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
		if TacticEngine.IsValidUnit(unit) then
			lifecycle.Remove(self, unit, "enemy")
		end
	end
	battleManager.teamHeroes[DOTA_TEAM_BADGUYS] = {}
	battleManager.teamRules[DOTA_TEAM_BADGUYS] = {}

	local level = self.dataLoader:GetLevel(levelId)
	if level == nil then
		self.stageLoading, self.stageLoadError = false, "unknown_level"
		print("[Dota2Rpg] WARNING: level '" .. tostring(levelId) .. "' not found in levels.kv.")
		return false
	end

	local createdCount = 0
	local enemyIndex = 0
	local enemyOccurrences = {}
	local spawnCount = #TEAM_SPAWNS[DOTA_TEAM_BADGUYS]
	for _, entry in pairs(level.enemies or {}) do
		local count = tonumber(entry.count) or 1
		for copyIndex = 1, count do
			enemyIndex = enemyIndex + 1
			local slot = ((enemyIndex - 1) % spawnCount) + 1
			local offset = Vector((copyIndex - 1) * ENEMY_SPAWN_SPACING - (count - 1) * ENEMY_SPAWN_SPACING / 2, 0, 0)
			local spawnPosition = GetGroundPosition(TEAM_SPAWNS[DOTA_TEAM_BADGUYS][slot] + offset, nil)
			local unit = lifecycle.Create(self, entry.unit, spawnPosition, DOTA_TEAM_BADGUYS, "enemy")
			if TacticEngine.IsValidUnit(unit) then
				created[#created + 1] = unit -- Keep it recoverable even if native preparation throws.
				createdCount = createdCount + 1
				FindClearSpaceForUnit(unit, spawnPosition, true)
				if unit:IsRealHero() then
					self:PrepareEnemyHero(unit, tonumber(entry.level) or 1)
				else
					self:PrepareEnemyCreep(unit, tonumber(entry.level) or 1)
					EnemyScaling.Apply(unit, level.multi)
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
						-- levels.kv stores status resistance as a percentage (0..100).
						local statusResistance = math.max(0, math.min(100, tonumber(entry.status_resistance) or 0)) / 100
						unit:SetStatusResistance(statusResistance)
					end
				end
				-- 敌方品质/内置升级：魔晶/神杖
				for _, upgrade in ipairs(entry.quality_upgrades or {}) do
					if upgrade == "shard" then
						unit:AddNewModifier(unit, nil, "modifier_item_aghanims_shard", {})
					elseif upgrade == "scepter" then
						unit:AddNewModifier(unit, nil, "modifier_item_ultimate_scepter_consumed", {})
					end
				end
				if okEnemyItems and EnemyItems ~= nil and EnemyItems.EquipConfiguredItems ~= nil then
					local equipped = EnemyItems.EquipConfiguredItems(unit, entry)
					if equipped > 0 then
						print(string.format("[Dota2Rpg] Enemy %s equipped %d items.", entry.unit, equipped))
					end
				end
				BossScaling.Apply(unit, entry)
				local enemyName = unit:GetUnitName()
				local occurrence = enemyOccurrences[enemyName] or 0
				unit.ruleSnapshotKey = "enemy:" .. enemyName .. ":" .. occurrence
				enemyOccurrences[enemyName] = occurrence + 1
				battleManager:RegisterHero(DOTA_TEAM_BADGUYS, enemyIndex, unit)
				unit.enemyRuleIndex = enemyIndex
				battleManager:RegisterEnemyTags(unit, entry.tags)
				battleManager.teamRules[DOTA_TEAM_BADGUYS][enemyIndex] = self:BuildEnemyRules(entry.ai)
				lifecycle.Event(self, "ready", "role=enemy " .. lifecycle.Snapshot(unit))
			else
				print(string.format("[Dota2Rpg] Failed to spawn enemy %s.", tostring(entry.unit)))
			end
		end
	end
	if createdCount == 0 or createdCount ~= enemyIndex then return false end
	print(string.format("[Dota2Rpg] Level '%s' spawned %d enemy units.", levelId, createdCount))
	return true
end

function CDota2RpgDemo:PrepareEnemyHero(hero, level)
	self.autoAbilityHeroes = self.autoAbilityHeroes or {}
	self.autoAbilityHeroes[hero:GetEntityIndex()] = true
	self:PrepareBattleHero(hero, level)
end

function CDota2RpgDemo:PrepareEnemyCreep(unit, level)
	unit:SetIdleAcquire(false)
	unit:SetAcquisitionRange(0)
	-- 野怪不升级会让原生技能停在 0 级：引擎会拒绝 0 级技能的所有施法指令，
	-- 战术 AI 却照常下发（日志里只见 rule_executed、永远没有真正的 cast），
	-- 表现就是"野怪全都没有技能"。所以这里必须补上 levels.kv 里的等级，
	-- 并把单位 KV 声明的技能点到满级（野怪技能 MaxLevel 基本都是 1）。
	--
	-- 注意：不是所有野怪单位都暴露同一套原生 API。"SetLevel" 在部分
	-- npc_dota_creep_neutral 基类单位上不存在（例如 npc_dota_neutral_gnoll_assassin），
	-- 直接调用会抛 "attempt to call method 'SetLevel' (a nil value)"，
	-- 把整个 AssembleLevelEnemies 干掉 → 触发 enemy_spawn_failed 重试循环。
	-- 所以这里每一步都先探测方法是否存在，缺失时降级而不是中断。
	local wantedLevel = math.max(1, math.floor(tonumber(level) or 1))
	local setLevel = unit.SetLevel
	local getLevel = unit.GetLevel
	if type(setLevel) == "function" and type(getLevel) == "function" then
		local guard = 0
		while unit:GetLevel() < wantedLevel and guard < 100 do
			local before = unit:GetLevel()
			setLevel(unit, before + 1)
			if unit:GetLevel() <= before then break end
			guard = guard + 1
		end
	end
	-- 技能同样逐个尝试：任一单位技能 API 缺失都不该让整关重试。
	local abilityCount = unit.GetAbilityCount ~= nil and (tonumber(unit:GetAbilityCount()) or 0) or 0
	for slot = 0, abilityCount - 1 do
		local ok, ability = pcall(unit.GetAbilityByIndex, unit, slot)
		if ok and ability ~= nil and type(ability.IsNull) == "function" and not ability:IsNull() then
			local maxLevel = type(ability.GetMaxLevel) == "function" and ability:GetMaxLevel() or 0
			-- 天赋与隐藏占位技能不属于野怪技能组，跳过以免误点。
			local abilityName = type(ability.GetAbilityName) == "function" and ability:GetAbilityName() or ""
			local isTalent = string.find(tostring(abilityName), "special_bonus", 1, true) ~= nil
			local currentLevel = type(ability.GetLevel) == "function" and ability:GetLevel() or 0
			if not isTalent and maxLevel > 0 and currentLevel < maxLevel
				and type(ability.SetLevel) == "function" then
				pcall(ability.SetLevel, ability, maxLevel)
			end
		end
	end
end

-- 敌人 AI：行为模式库预设 → 内部规则格式（与玩家同一引擎）
function CDota2RpgDemo:BuildEnemyRules(aiId)
	local preset = self.dataLoader:GetEnemyAI(aiId)
	if preset == nil then
		preset = self.dataLoader:GetEnemyAI("demo_default")
	end
	local rules = {}
	local ordered = {}
	for key, rule in pairs(preset and preset.rules or {}) do
		ordered[#ordered + 1] = { key = tostring(key), order = tonumber(key) or math.huge, rule = rule }
	end
	table.sort(ordered, function(a, b)
		if a.order == b.order then return a.key < b.key end
		return a.order < b.order
	end)
	for _, row in ipairs(ordered) do
		local presetRule = row.rule
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

function CDota2RpgDemo:CaptureHeroAbilities(hero)
	if hero == nil or not hero.rpgAbilitiesRestored or hero.GetAbilityPoints == nil then return end
	local name = hero.lineupHeroName or hero.benchHeroName
	local data = name ~= nil and self.heroData[name] or nil
	if data == nil then return end
	data.ability_levels = {}
	for slot = 0, HeroAbilityPolicy.GetSlotCount(hero) - 1 do
		local ability = hero:GetAbilityByIndex(slot)
		if ability ~= nil and not ability:IsNull() then
			data.ability_levels[ability:GetAbilityName()] = ability:GetLevel()
		end
	end
	-- Progression can award levels before the old entity is rebuilt.
	local earned = math.max(0, (tonumber(data.level) or hero:GetLevel()) - hero:GetLevel())
	data.skill_points = math.max(0, hero:GetAbilityPoints() + earned)
end

-- Updating an existing hero must not reapply preparation modifiers or reset
-- acquisition, health, mana, cooldowns, or the live manual ability build.
function CDota2RpgDemo:UpdateHeroLevel(hero, targetLevel)
	self:CaptureHeroAbilities(hero)
	local wantedLevel = math.max(1, math.min(HERO_LEVEL, math.floor(tonumber(targetLevel) or HERO_LEVEL)))
	while hero:GetLevel() < wantedLevel do
		local before = hero:GetLevel()
		hero:HeroLevelUp(false)
		if hero:GetLevel() <= before then break end
	end
	local name = hero.lineupHeroName or hero.benchHeroName
	local data = name ~= nil and self.heroData[name] or nil
	if data ~= nil then
		local pending = math.max(0, (tonumber(data.level) or hero:GetLevel()) - hero:GetLevel())
		hero:SetAbilityPoints(math.max(0, (data.skill_points or data.level) - pending))
	end
	return wantedLevel
end

function CDota2RpgDemo:PrepareBattleHero(hero, targetLevel)
	JinadaIncome.Attach(self, hero)
	HeroAbilityPolicy.Apply(hero)
	local wantedLevel = self:UpdateHeroLevel(hero, targetLevel)

	-- Only enemies auto-train; both player roster locations retain manual builds.
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
		local heroName = hero.lineupHeroName or hero.benchHeroName
		local data = heroName ~= nil and self.heroData[heroName] or nil
		HeroAbilityPolicy.RestoreManualAbilities(hero, data, wantedLevel)
		hero.rpgAbilitiesRestored = true
	end
	hero:SetRespawnsDisabled(true)
	hero:SetHealth(hero:GetMaxHealth())
	hero:SetMana(hero:GetMaxMana())
	hero:SetIdleAcquire(false)
	hero:SetAcquisitionRange(0)

	-- 上阵英雄不挂禁足：准备阶段玩家需要自由移动它们排位
	-- （移动指令由订单过滤器放行并限制在己方半场）
	local isFielded = self.autoAbilityHeroes ~= nil
		and self.autoAbilityHeroes[hero:GetEntityIndex()] == nil and hero.benchHeroName == nil
	if hero.benchHeroName ~= nil then
		hero:AddNewModifier(hero, nil, "modifier_rpg_prepare_bench", {})
		return
	end
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
	if stash ~= nil and self:IsItemHeldBy(stash, item, 0, CARRIER_LAST_SLOT) then
		return stash
	end
	for _, hero in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
		if self:IsLineupUnit(hero) and self:IsItemHeldBy(hero, item, 0, CARRIER_LAST_SLOT) then
			return hero
		end
	end
	for _, hero in ipairs(self.benchUnits or {}) do
		if self:IsBenchUnit(hero) and self:IsItemHeldBy(hero, item, 0, CARRIER_LAST_SLOT) then
			return hero
		end
	end
	return nil
end

function CDota2RpgDemo:ValidatePrepareOrder(filterTable)
	local issuerPlayerId = tonumber(filterTable.issuer_player_id_const) or -1
	if issuerPlayerId < 0 then
		-- OrderGate 的项目内部订单进入过滤器时已提前放行；到达这里的受管订单必须有真实玩家来源。
		return false
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
	-- A unitless training order is unambiguous only when it names a live ability
	-- whose caster is in our roster. Never infer its source from UI selection.
	if sourceCount == 0 and orderType == DOTA_UNIT_ORDER_TRAIN_ABILITY then
		local abilityIndex = tonumber(filterTable.entindex_ability or filterTable.ability_index) or -1
		local ability = abilityIndex > 0 and EntIndexToHScript(abilityIndex) or nil
		if ability ~= nil and not ability:IsNull() and ability.GetCaster ~= nil then
			local caster = ability:GetCaster()
			if self:IsLineupUnit(caster) or self:IsBenchUnit(caster) then
				source, sourceCount = caster, 1
			end
		end
	end
	-- 原版购买/出售有时是玩家级订单，不携带 units；其余物品操作必须来自一个明确载体。
	if sourceCount > 1 or ((not isPurchase and not isSell and not isDisassemble
		and orderType ~= DOTA_UNIT_ORDER_CONSUME_ITEM) and sourceCount ~= 1) then
		return false
	end
	if isPurchase and source ~= nil then
		if not self:BindEquipmentCarrierToPlayer(source) then
			return false
		end
	end

	if self.phase ~= "setup" then
		return false
	end

	if orderType == DOTA_UNIT_ORDER_TRAIN_ABILITY then
		if source == nil or not (self:IsLineupUnit(source) or self:IsBenchUnit(source)) then return false end
		local abilityIndex = tonumber(filterTable.entindex_ability or filterTable.ability_index) or -1
		for slot = 0, HeroAbilityPolicy.GetSlotCount(source) - 1 do
			local ability = source:GetAbilityByIndex(slot)
			if ability ~= nil and not ability:IsNull() then
				local entityIndex = ability.entindex ~= nil and ability:entindex() or -1
				-- Panorama revisions differ: some submit the ability entity index,
				-- others submit its slot. Accept either only for this source hero.
				if entityIndex == abilityIndex or slot == abilityIndex then return true end
			end
		end
		return false
	end

	if orderType == DOTA_UNIT_ORDER_CONSUME_ITEM then
		local item = EntIndexToHScript(tonumber(filterTable.entindex_ability) or -1)
		if self:IsLiveItem(item) and item:GetAbilityName() == GrisGris.ITEM then
			local holder = self:FindEquipmentItemHolder(item)
			if holder then
				ItemSales.Sell(self, { PlayerID = issuerPlayerId,
					hero = holder:GetUnitName(), item = GrisGris.ITEM,
					item_index = tonumber(filterTable.entindex_ability) })
			end
			return false
		end
	end

	if orderType == DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH
		or orderType == DOTA_UNIT_ORDER_SET_ITEM_COMBINE_LOCK
		or orderType == DOTA_UNIT_ORDER_SET_ITEM_MARK_FOR_SELL
		or orderType == DOTA_UNIT_ORDER_CONSUME_ITEM then
		local item = EntIndexToHScript(tonumber(filterTable.entindex_ability) or -1)
		return source ~= nil and self:IsLiveItem(item)
			and self:IsItemHeldBy(source, item, 0, CARRIER_LAST_SLOT)
	end

	if isPurchase then
		-- 购买订单在部分客户端没有 units；如果引擎同时给出一个单位目标，必须是受管装备载体。
		if target ~= nil and target.GetItemInSlot ~= nil then
			if not self:IsEquipmentCarrier(target) then
				return false
			end
			if not self:BindEquipmentCarrierToPlayer(target) then
				return false
			end
		end
		-- 订单执行前保存全部实体 ID。若原版引擎仍把额外英雄的购买送到主英雄小精灵，
		-- dota_item_purchased 后可安全定位“本次新增实体”并补转到玩家选中的上阵/待命英雄。
		local recipientKey = self.nativePurchaseSelectionHero
		if target ~= nil and target.GetItemInSlot ~= nil then
			recipientKey = self:GetNativePurchaseRecipientKey(target)
		elseif source ~= nil and source ~= self:GetStashUnit() then
			recipientKey = self:GetNativePurchaseRecipientKey(source)
		elseif recipientKey == nil and source ~= nil then
			recipientKey = self:GetNativePurchaseRecipientKey(source)
		end
		self:PruneNativePurchaseOrderContexts()
		self.nativePurchaseOrderContexts = self.nativePurchaseOrderContexts or {}
		local itemName = self:GetNativePurchaseItemName(filterTable)
		if itemName == "" then return false end
		if itemName == "item_aghanims_shard" then
			local bought, message = ShardPurchase.Purchase(self, issuerPlayerId, recipientKey)
			ShardPurchase.Notify(self, message)
			if bought then self:SyncLiveEquipmentState(true) end
			-- Always suppress native execution: Shard auto-consumes on Wisp
			-- before the ordinary post-purchase inventory router can see it.
			return false
		end
		local affordable, itemCost = self:CanAffordNativePurchase(itemName, filterTable)
		if not affordable then
			print(string.format("[Dota2Rpg] Native purchase rejected: item=%s cost=%s balance=%d.",
				itemName, tostring(itemCost), self:GetGoldBalance()))
			return false
		end
		self.nativePurchaseTransactionId = (self.nativePurchaseTransactionId or 0) + 1
		local recipient = self:ResolveNativePurchaseRecipient(recipientKey or "__wisp")
		local context = {
			transaction_id = self.nativePurchaseTransactionId,
			issuer = tonumber(filterTable.issuer_player_id_const),
			target_location = recipient ~= nil and (self:IsBenchUnit(recipient) and "bench"
				or (self:IsLineupUnit(recipient) and "active" or "stash")) or "missing",
			recipient_key = recipientKey or "__wisp",
			before_ids = self:CollectManagedItemIds(),
			item_name = itemName,
			-- dota_item_purchased is not guaranteed to arrive before the next think.
			-- Keep the pre-order wallet so a native shop implementation that does not
			-- debit PlayerResource can still be charged exactly once below.
			gold_before = self:GetGoldBalance(),
			item_cost = itemCost,
			created_at = self:GetNativePurchaseClock(),
			created_tick = self.nativePurchaseTick or 0,
		}
		-- 原版购买事件按提交顺序到达；每个订单都保留独立快照，不能用单一可覆盖字段。
		table.insert(self.nativePurchaseOrderContexts, context)
		self:LogNativePurchase(context, "preflight", "accepted")
		-- The assigned hero owns the native shop wallet. Extra roster heroes are
		-- delivery recipients, not native purchasers; route the order through Wisp
		-- and keep recipient_key for the existing confirmed-item transfer.
		local purchaser = self:GetStashUnit()
		if purchaser ~= nil and purchaser.GetEntityIndex ~= nil then
			filterTable.units = { ["0"] = purchaser:GetEntityIndex() }
			if target ~= nil and target.GetItemInSlot ~= nil then
				filterTable.entindex_target = purchaser:GetEntityIndex()
			end
		end
		return true
	end

	if isSell or isDisassemble then
        -- A sale refund must not conceal a still-unreconciled purchase debit.
        if isSell and (self.itemSaleInProgress or ItemSales.HasPendingPurchase(self)) then return false end
		local itemIndex = tonumber(filterTable.entindex_ability) or -1
		local item = itemIndex > 0 and EntIndexToHScript(itemIndex) or nil
		if not self:IsLiveItem(item) then
			return false
		end
		-- 少数原版出售订单不带 units，按物品在我方可控载体中的真实归属补齐来源。
		local holder = isSell and self:FindEquipmentItemHolder(item)
            or source or self:FindEquipmentItemHolder(item)
		-- 原版物品栏、背包、远程购买储藏栏和专属中立槽都属于该当前上阵载体。
		local lastSlot = CARRIER_LAST_SLOT
        if holder == nil or not self:IsEquipmentCarrier(holder)
            or not self:IsItemHeldBy(holder, item, 0, lastSlot) then return false end
        if isSell and item:GetAbilityName() == GrisGris.ITEM then
            ItemSales.Sell(self, { PlayerID = issuerPlayerId, hero = holder:GetUnitName(),
                item = GrisGris.ITEM, item_index = itemIndex })
            return false
        end
        if isSell then
            -- Native HUD may use the assigned Wisp as issuer even when the
            -- inspected item is held by a roster hero. The exact owned entity,
            -- not UI selection, determines the native sale's actual carrier.
            if not self:BindEquipmentCarrierToPlayer(holder) then return false end
            filterTable.units = { ["0"] = holder:GetEntityIndex() }
            self.nativeShopTransactionPending = true
        end
        return true
	end

	-- 原版 HUD 的拖放、交付与地面拾取：只可在小精灵、当前上阵英雄和待命英雄之间发生。
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
		-- 中立装备在槽 16，原生拖拽必须能把它从指挥官的专属槽交给英雄。
		local lastSlot = CARRIER_LAST_SLOT
		if not isTransferableItem(item) or not self:IsItemHeldBy(source, item, 0, lastSlot) then
			return false
		end
		if item:GetAbilityName() == GrisGris.ITEM and (isDrop or isGive) then return false end
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

	-- 准备阶段允许小精灵和当前上阵英雄移动；待命英雄保持禁足但可购买/管理物品。
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
		if isMoveToPoint and isLineupSource then
			local pos = filterTable.position_2 or filterTable.position
			local hasPosition = filterTable.position_x ~= nil or (pos and pos.x ~= nil)
			if hasPosition then
				-- Lua 边界和默认出生点使用同一紧凑布局：左方 1200×900 准备区。
				local x = tonumber(filterTable.position_x or (pos and pos.x) or 0)
				local y = tonumber(filterTable.position_y or (pos and pos.y) or 0)
				local minX = -BATTLEFIELD_HALF_WIDTH + BATTLEFIELD_MOVE_MARGIN
				local maxX = -PREPARE_DIVIDER_MARGIN
				local minY = -BATTLEFIELD_HALF_HEIGHT + BATTLEFIELD_MOVE_MARGIN
				local maxY = BATTLEFIELD_HALF_HEIGHT - BATTLEFIELD_MOVE_MARGIN
				x = math.max(minX, math.min(maxX, x))
				y = math.max(minY, math.min(maxY, y))
				filterTable.position_x = x
				filterTable.position_y = y
				self.placedPositions = self.placedPositions or {}
				self.placedPositions[source:GetUnitName()] = { x = x, y = y }
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
	self:BroadcastDamageStats()
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
	if self.runComplete or self.phase ~= "setup" or not self.teamsSpawned then
		return
	end
	if self.stageLoading then return end
	if self.stageLoadError or (self.stagePrecache and self.preparedEnemyLevel ~= self.currentLevelId) then
		self:SpawnLevelEnemies(self.currentLevelId)
		self:BroadcastHeroInfo()
		self:BroadcastBattleState()
		return -- A retry prepares the stage; it never starts a fight implicitly.
	end
	if #self.lineup == 0 then
		return -- 必须先购买英雄并上阵
	end

	-- 规则在准备阶段通过 rpg_update_rule 逐条写入当前 Run；这里不再信任客户端
	-- 的整包旧 payload，也不在开战时覆盖 RuleService 的稳定英雄键。
	self.phase = "fight"
	RespawnPolicy.SetBattleActive(self, true)

	for _, heroes in pairs(self.battleManager.teamHeroes) do
		for _, hero in ipairs(heroes) do
			if TacticEngine.IsValidUnit(hero) and hero:IsAlive() then
				hero:RemoveModifierByName("modifier_rpg_prepare_bench")
				for _, modifierName in ipairs(PRE_BATTLE_MODIFIERS) do
					hero:RemoveModifierByName(modifierName)
				end
				hero:SetHealth(hero:GetMaxHealth())
				hero:SetMana(hero:GetMaxMana())
				hero:SetIdleAcquire(not hero.rpg_debug_manual_cast or hero.rpg_debug_auto_acquire == true)
				hero:SetAcquisitionRange(hero.rpg_debug_manual_cast and not hero.rpg_debug_auto_acquire and 0 or BATTLE_ACQUISITION_RANGE)
			end
		end
	end

	-- 野怪关的敌方小怪没有规则行，也要解除开战前的静止状态
	for _, unit in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_BADGUYS]) do
		if TacticEngine.IsValidUnit(unit) and unit:IsAlive() then
			unit:SetIdleAcquire(not unit.rpg_debug_manual_cast or unit.rpg_debug_auto_acquire == true)
			unit:SetAcquisitionRange(unit.rpg_debug_manual_cast and not unit.rpg_debug_auto_acquire and 0 or BATTLE_ACQUISITION_RANGE)
		end
	end

	self:RemoveBattleBarrier()
	-- Open the Hammer gate from the authoritative battle transition too; this
	-- avoids leaving the invisible func_brush solid if the compatibility wrapper
	-- is installed after this method or misses the phase edge.
	if self.issueFixes ~= nil and self.issueFixes.arena ~= nil then
		self.issueFixes.arena:OpenMiddleGate()
	end
	self.tacticBridge:ResetState()
	self.battleManager:ResetBattleStats()
	-- 战斗中玩家小精灵无敌，避免被敌方波及
	self:EnsureCommanderProtected()
	self.damageStats = DamageStats.new()
	local damageUnits = {}
	for _, team in ipairs({ DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }) do
		for _, unit in ipairs(self.battleManager.teamHeroes[team] or {}) do
			table.insert(damageUnits, { unit = unit, team = team })
		end
	end
	self.damageStats:Start(damageUnits, GameRules:GetGameTime())
	self.nextDamageBroadcast = 0
	self.battleManager:StartBattle(self.battleManager.teamRules)
	self:BroadcastDamageStats()
	self:BroadcastBattleState()
	print("[Dota2Rpg] Battle started on level " .. self.currentLevelId .. ".")
end

function CDota2RpgDemo:OnEntityHurt(event)
	self.battleManager:RecordDamage(tonumber(event.entindex_killed or -1))
	if self.phase ~= "fight" or self.damageStats == nil then return end
	local function entity(value)
		local id = tonumber(value)
		if id == nil or id <= 0 then return nil end
		return EntIndexToHScript(id)
	end
	self.damageStats:Record(entity(event.entindex_attacker), entity(event.entindex_killed),
		entity(event.entindex_inflictor), tonumber(event.damage), GameRules:GetGameTime())
end

function CDota2RpgDemo:BroadcastDamageStats()
	if self.damageStats ~= nil then
		local now = GameRules:GetGameTime()
		CustomGameEventManager:Send_ServerToAllClients("rpg_damage_stats", {
			elapsed = math.max(0, (self.damageStats.stoppedAt or now) - self.damageStats.startedAt),
			units = self.damageStats:Snapshot(now),
		})
	end
end

function CDota2RpgDemo:OnEntityKilled(event)
	local killed = EntIndexToHScript(event.entindex_killed or -1)
	-- Classify native death before statistics/broadcasts, including late events.
	RespawnPolicy.OnKilled(self, killed)
	GrisGris.OnKilled(self, killed)
	if self.phase ~= "fight" then
		return
	end

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

-- Native unit handles can fail during death/reincarnation and removal. Keep
-- independent upkeep failures from cancelling the scheduled think or deadline.
function CDota2RpgDemo:RunLifecycleStep(name, callback)
	local ok, result = xpcall(callback, Traceback)
	if not ok then
		self.lifecycleErrors = self.lifecycleErrors or {}
		local now = GameRules:GetGameTime()
		local previous = self.lifecycleErrors[name]
		if previous == nil or previous.message ~= result or now - previous.at >= 5 then
			self.lifecycleErrors[name] = { message = result, at = now }
			local write = RuntimeLog.WriteCritical or RuntimeLog.Write
			write("BattleLifecycle step=" .. name .. " phase=" .. tostring(self.phase)
				.. " level=" .. tostring(self.currentLevelId) .. " error=" .. tostring(result))
		end
	end
	return ok, result
end

function CDota2RpgDemo:OnThink()
	self:RunLifecycleStep("tempest_think", function() TempestDouble.OnThink(self) end)
	self:RunLifecycleStep("summon_think", function() SummonBehavior.OnThink(self) end)
	self:RunLifecycleStep("gris_gris_think", function() GrisGris.OnThink(self) end)
	self:RunLifecycleStep("tiny_tree_think", function() TinyTree.OnThink(self) end)
	self:RunLifecycleStep("enemy_diagnostics", function() EnemyDiagnostics.OnThink(self) end)
	self:RunLifecycleStep("roster_upkeep", function()
		self.nativePurchaseTick = (self.nativePurchaseTick or 0) + 1
		local lives = RunLives.Ensure(self)
		if self.phase ~= "fight" and #lives.pendingItems > 0
			and GameRules:GetGameTime() >= (self.nextLifeRewardAttempt or 0) then
			self.nextLifeRewardAttempt = GameRules:GetGameTime() + 1
			if RunLives.FlushItems(self) > 0 then self:BroadcastShopState() end
		end
		if not self.teamsSpawned then
			local state = GameRules:State_Get()
			if state >= DOTA_GAMERULES_STATE_PRE_GAME then
				self:EnsureBattlefield()
			end
		end

		if self.phase == "setup" then
			self:SyncGoldFromPlayer()
			self:EnsureNativePlayerHero()
			self:ReconcileNativePurchaseOrders()
			-- Capture native TRAIN_ABILITY results before a later roster rebuild.
			local abilitiesChanged = self:SyncRosterAbilities()
			self:SyncLiveEquipmentState(self.nativeShopTransactionPending)
			local walletChanged = self.lastBroadcastGold ~= self:GetGoldBalance()
			if abilitiesChanged or walletChanged then
				self:BroadcastShopState()
			end
			self.nativeShopTransactionPending = nil
		elseif self.lastBroadcastGold ~= self:GetGoldBalance() then
			-- Native combat income (e.g. Jinada/Track) can arrive during a
			-- fight. Publish the authoritative balance without waiting for setup.
			self:BroadcastShopState()
		end
	end)

	if self.phase == "fight" then
		self:RunLifecycleStep("battle_deadline", function() self.battleManager:OnThink() end)
		if self.phase == "fight" then
			self:RunLifecycleStep("tactics", function() self.tacticBridge:OnThink() end)
			self:RunLifecycleStep("damage_broadcast", function()
				local now = GameRules:GetGameTime()
				if now >= (self.nextDamageBroadcast or 0) then
					self:BroadcastDamageStats()
					self.nextDamageBroadcast = now + 0.5
				end
			end)
		end
	end

	return THINK_INTERVAL
end

function CDota2RpgDemo:OnReplayRun(_, payload)
	-- PlayerID is engine metadata. Never accept a client-selected owner or a
	-- request from an earlier result screen, even after another run finishes.
	if type(payload) ~= "table" or self.playerId == nil
		or tonumber(payload.PlayerID) ~= self.playerId
		or tonumber(payload.settlement_generation) ~= self.settlementGeneration
		or self.phase ~= "result" or not self.runComplete
		or (self.skillDebug and (self.skillDebug.active or self.skillDebug.pending)) then return false end
	self.settlementGeneration = self.settlementGeneration + 1
	self.phase = "restarting" -- claim before native callbacks/reentrant events
	local resetOk, resetError = xpcall(function() require("battle.fresh_run").Reset(self) end, Traceback)
	if not resetOk then
		-- Destructive cleanup is intentionally not rolled back. Keep combat
		-- locked and offer a new-generation retry instead of stranding restarting.
		self.phase, self.runComplete = "result", true
		RuntimeLog.Write("[FreshRun] reset_failed " .. tostring(resetError))
		self:BroadcastBattleState()
		return false
	end
	self.currentLevelId = "ch01"
	self.phase = "setup"
	self:EnsureCommanderProtected()
	self:SpawnLevelEnemies(self.currentLevelId)
	self:RespawnPlayerRoster()
	self:SpawnBattleBarrier()
	self:RollShop()
	self:BroadcastLevelInfo()
	self:BroadcastBattleState()
	self:BroadcastHeroInfo()
	self:BroadcastShopState()
	self:BroadcastDamageStats()
	return true
end

function CDota2RpgDemo:EndBattle(winner, winnerTeam)
	if self.phase ~= "fight" then
		return
	end
	-- Claim settlement before any wallet/item/event callback can re-enter.
	self.phase = "result"
	self:RunLifecycleStep("item_cooldowns", function() require("battle.item_cooldowns").Refresh(self) end)
	RespawnPolicy.SetBattleActive(self, false)
	self.settlementGeneration = (self.settlementGeneration or 0) + 1
	local settlementGeneration = self.settlementGeneration
	self:RunLifecycleStep("tempest_clear", function() TempestDouble.Clear(self) end)
	self:RunLifecycleStep("special_targets_clear", function() SpecialTargets.Clear(self) end)
	self:RunLifecycleStep("summon_clear", function() SummonBehavior.Clear(self) end)
	self:RunLifecycleStep("tiny_tree_clear", function() TinyTree.Clear(self) end)
	local lifeReward = { gold = 0, items = {} }
	if winner ~= "radiant" then
		lifeReward = RunLives.Lose(self)
		self:RunLifecycleStep("life_reward_delivery", function() RunLives.FlushItems(self) end)
	end
	local lives = RunLives.Ensure(self)
	self.runFailed = lives.remaining <= 0
	if self.runFailed then self.runComplete = true end

	if self.damageStats ~= nil then
		self:RunLifecycleStep("damage_stop", function() self.damageStats:Stop(GameRules:GetGameTime()) end)
		self:RunLifecycleStep("damage_final_broadcast", function() self:BroadcastDamageStats() end)
	end
	local clearTime = self.battleManager:GetBattleTime()
	local level = self.dataLoader:GetLevel(self.currentLevelId)
	local timeLimit = tonumber(level ~= nil and level.time_limit or 120) or 120
	local reward = level ~= nil and level.reward or nil
	local baseGold = tonumber(reward ~= nil and reward.gold or 0) or 0
	local baseXp = tonumber(reward ~= nil and (reward.xp_per_active_hero or reward.xp_pool) or 0) or 0

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

	-- 时间奖励上限为基础金币的 10%，且只由服务端计算一次。
	local timeBonus = winner == "radiant" and self:CalculateTimeBonus(baseGold, clearTime, timeLimit) or 0
	local activeXp = baseXp
	local benchXp = math.floor(baseXp * ((ProgressionData and ProgressionData.BENCH_XP_RATE) or 0.5))

	-- 唯一一次 loot_table 掉落结算：胜利时按掉落表概率 roll 入共享仓库
	local lootDrops = {}
	if winner == "radiant" then
		local lootId = level ~= nil and level.loot or nil
		local lootTable = lootId ~= nil and self.dataLoader:GetLoot(lootId) or nil
		if lootTable ~= nil then
			lootDrops = CampaignLoot.Award(self, lootTable)
		end
	end

	local settlement = {
		settlement_generation = settlementGeneration,
		level = self.currentLevelId,
		winner = winner,
		gold = winner == "radiant" and (baseGold + timeBonus) or 0,
		base_gold = baseGold,
		time_bonus = timeBonus,
		xp_pool = baseXp, -- 兼容旧客户端；新客户端读取下面两个字段。
		xp_per_active_hero = activeXp,
		xp_per_bench_hero = benchXp,
		stars = stars,
		clear_time = math.floor(clearTime),
		loot_text = table.concat(lootDrops, ";"),
		lives_remaining = lives.remaining,
		max_lives = RunLives.MAX_LIVES,
		life_reward_gold = lifeReward.gold,
		life_reward_items = table.concat(lifeReward.items, ";"),
		life_reward_pending = #lives.pendingItems,
		run_failed = self.runFailed and 1 or 0,
	}
	-- 唯一一次奖励：胜利即入账（金币），按上阵/待命逐英雄发经验。
	if winner == "radiant" then
		self:AddGold(settlement.gold)
		self:AwardStageXp(activeXp)
	end

	local isFinalWin = winner == "radiant"
		and #self.orderedLevels > 0
		and self.currentLevelId == self.orderedLevels[#self.orderedLevels]

	-- Keep campaign terminals inside the custom result phase: an official
	-- SetGameWinner would irreversibly prevent replay in this match.
	self.runComplete = isFinalWin or self.runFailed
	self.phase = "result"
	self.winner = winner
	self:RunLifecycleStep("battle_stop", function() self.battleManager:StopBattle() end)
	self:RunLifecycleStep("result_broadcast", function() self:BroadcastBattleState() end)
	self:RunLifecycleStep("settlement_broadcast", function()
		CustomGameEventManager:Send_ServerToAllClients("rpg_settlement", settlement)
	end)

	-- 闯关推进：胜利指向下一关（进入下一关时重置刷新费用与卷轴限购）。
	-- Terminal replay is explicit; ordinary stage transitions stay automatic.
	if isFinalWin or self.runFailed then
		self.runComplete = true
		self:BroadcastShopState()
		print(self.runFailed and "[Dota2Rpg] Run ended: all five lives lost."
			or "[Dota2Rpg] Run complete: final level cleared.")
		return
	end
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
	local setupPending = true
	GameRules:GetGameModeEntity():SetContextThink("Dota2RpgBackToSetup", function()
		if not setupPending or self.phase ~= "result" or self.runComplete
			or self.settlementGeneration ~= settlementGeneration then
			return nil
		end
		setupPending = false
		local lifecycle = require("issue_fixes.hero_lifecycle_log")
		lifecycle.Event(self, "reset_begin", "from=" .. tostring(settlement.level) .. " to=" .. tostring(self.currentLevelId))
		self.phase = "setup"
		self.winner = ""
		self:EnsureCommanderProtected()
		self:SpawnLevelEnemies(self.currentLevelId)
		self:RespawnPlayerRoster()
		self:SpawnBattleBarrier()
		-- RollShop broadcasts the new offers; automatic rolls never charge gold.
		self:RollShop()
		RuntimeLog.Write(string.format("[Dota2Rpg] ShopTransition result=%s from=%s to=%s free=1 offers=%d refresh_count=%d",
			tostring(winner), tostring(settlement.level), tostring(self.currentLevelId),
			#self.shopOffers, self.refreshCount))
		self:BroadcastLevelInfo()
		self:BroadcastBattleState()
		print("[Dota2Rpg] Back to setup. Next level: " .. self.currentLevelId)
		lifecycle.Event(self, "reset_complete", "from=" .. tostring(settlement.level))
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
	return AbilityCatalog.DescribeAction(hero, action)
end

function CDota2RpgDemo:BroadcastHeroInfo()
	local roster = {}
	for _, unit in ipairs(self.battleManager.teamHeroes[DOTA_TEAM_BADGUYS] or {}) do
		if TacticEngine.IsValidUnit(unit) then
			table.insert(roster, { id = unit:entindex(), name = unit:GetUnitName(),
                target_actor = RuleSnapshot.TargetActor(self.battleManager, self.currentLevelId, unit) or "" })
		end
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_enemy_roster", { rule_generation = self.ruleGeneration or 0, units = roster })
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
				local capRevision = AbilityCatalog.PublishCapabilities(hero, slots, RuleSnapshot.HeroKey(self.battleManager,hero))
				CustomGameEventManager:Send_ServerToAllClients("rpg_hero_slots", {
                    rule_generation = self.ruleGeneration or 0,
                    capability_revision = capRevision,
					slot_key = side.key .. "_" .. index,
					hero_index = hero:entindex(),
					hero_name = hero:GetUnitName(),
					actions_text = table.concat(slots, ";"),
					abilities_text = table.concat(AbilityCatalog.ListAbilities(hero), ";"),
					details_text = table.concat(descriptions, ";"),
                    rule_key = RuleSnapshot.HeroKey(self.battleManager,hero),
                    target_actor = side.team == DOTA_TEAM_BADGUYS
                        and (RuleSnapshot.TargetActor(self.battleManager, self.currentLevelId, hero) or "") or "",
                    can_edit = (side.team == DOTA_TEAM_GOODGUYS or RuleSnapshot.IsDeveloperMode()) and 1 or 0,
                    rules_ready = self.tacticBridge ~= nil and self.tacticBridge.getRules ~= nil and 1 or 0,
                    rules = self.tacticBridge ~= nil and RuleSnapshot.ForHero(self.tacticBridge, hero) or {},
				})
			end
		end
	end
end

-- 兼容旧调用名：同步只能从 PlayerResource 读取，不能把旧 self.gold 写回钱包。
function CDota2RpgDemo:SyncGoldToPlayer()
	return self:SyncGoldFromPlayer()
end

function CDota2RpgDemo:BroadcastShopState()
	-- 先从原版钱包读取，再推送项目 HUD；绝不把旧 self.gold 回写为商店余额。
	local gold = self:GetGoldBalance()
	self.lastBroadcastGold = gold
	-- CEM 载荷一律拍平；英雄数据用 "name:level:xp:quality" 分号串
	local heroEntries = {}
	for _, heroName in ipairs(self.ownedHeroes) do
		local d = self.heroData[heroName]
		table.insert(heroEntries, heroName .. ":" .. (d ~= nil and d.level or 1) .. ":" .. (d ~= nil and d.current_xp or 0) .. ":" .. (d ~= nil and d.quality or "common") .. ":" .. (d ~= nil and (d.skill_points or d.level) or 1) .. ":" .. table.concat((d ~= nil and d.inventory) or {}, ","))
	end
	local stockParts, neutralStockParts = {}, {}
	local freeStashSlots, neutralSlotTaken = 0, false
	local stash = self:GetStashUnit()
	if stash ~= nil then
		for slot = 0, CARRIER_LAST_SLOT do
			-- 回城卷轴不参与装备转交：不发布，客户端也就无从列出或搬运它。
			if slot ~= NATIVE_TP_SLOT then
				local item = stash:GetItemInSlot(slot)
				if item ~= nil and not item:IsNull() then
					local itemName = item:GetAbilityName()
					local itemId = self:GetItemEntityId(item)
					-- UI 操作只需要真实实体 ID；价格与出售均由 Valve 原版商店负责。
					table.insert(stockParts, itemName .. "|" .. itemId)
					-- 中立装备只占专属中立槽，客户端要按独立容量判断能否交付。
					if slot == NEUTRAL_ITEM_SLOT then
						table.insert(neutralStockParts, itemId)
						neutralSlotTaken = true
					end
				elseif slot <= NATIVE_STASH_LAST_SLOT then
					freeStashSlots = freeStashSlots + 1
				end
			end
		end
	end
	local inventoryParts = {}
	local equippedParts = {}
	local heroEntityIndices = {}
	for _, heroName in ipairs(self.ownedHeroes) do
		local d = self.heroData[heroName]
		table.insert(inventoryParts, heroName .. ":" .. table.concat((d ~= nil and d.inventory) or {}, ","))
		local hero = self:FindOwnedHeroUnit(heroName)
		local heroItems = {}
		if hero ~= nil and hero.GetEntityIndex ~= nil then
			heroEntityIndices[heroName] = hero:GetEntityIndex()
		end
		if hero ~= nil and hero.GetItemInSlot ~= nil then
			-- 0..16 都携带真实实体 ID；UI 用槽号计算主动栏容量，并允许把背包/原生储藏物品
			-- 以及专属中立槽里的中立装备卸回小精灵。
			for slot = 0, CARRIER_LAST_SLOT do
				if slot ~= NATIVE_TP_SLOT then
					local item = hero:GetItemInSlot(slot)
					if self:IsLiveItem(item) then
						table.insert(heroItems, item:GetAbilityName() .. "|" .. self:GetItemEntityId(item) .. "|" .. slot)
					end
				end
			end
		end
		table.insert(equippedParts, heroName .. ":" .. table.concat(heroItems, ","))
	end
	CustomGameEventManager:Send_ServerToAllClients("rpg_shop_state", {
		rule_generation = self.ruleGeneration or 0,
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
		stock_neutral_text = table.concat(neutralStockParts, ";"),
		stash_free_slots = freeStashSlots,
		neutral_slot_free = neutralSlotTaken and 0 or 1,
		inventories_text = table.concat(inventoryParts, ";"),
		equipped_text = table.concat(equippedParts, ";"),
		gris_gris_gold = GrisGris.Gold(self),
		hero_entity_indices = heroEntityIndices,
		-- 客户端只为"玩家自己的英雄"下发原版购买订单；HUD 打开商店时需要把选中
		-- 临时切到小精灵，再在关闭时还原，所以必须知道它的实体索引。
		commander_index = (stash ~= nil and stash.GetEntityIndex ~= nil)
			and stash:GetEntityIndex() or -1,
		cost_bench_slot = self.shopCosts.bench_slot,
		bench_slot_max = self.shopCosts.bench_slot_max,
		lineup_max = self.shopCosts.lineup_max,
		free_recruit_choices = self.freeRecruitChoices or 0,
		initial_gold = (ProgressionData and ProgressionData.INITIAL_GOLD) or 500,
		lives_remaining = RunLives.Ensure(self).remaining,
		max_lives = RunLives.MAX_LIVES,
		run_failed = self.runFailed and 1 or 0,
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
	local missingStage = self.stagePrecache ~= nil and self.preparedEnemyLevel ~= self.currentLevelId
	return {
		rule_generation = self.ruleGeneration or 0,
		phase = self.phase,
		ready = (self.teamsSpawned and not self.runComplete and not self.stageLoading and not self.stageLoadError and not missingStage) and 1 or 0,
		stage_loading = self.stageLoading and 1 or 0,
		stage_failed = (self.stageLoadError or (missingStage and self.teamsSpawned and not self.stageLoading)) and 1 or 0,
		replay_available = (self.phase == "result" and self.runComplete
			and not (self.skillDebug and (self.skillDebug.active or self.skillDebug.pending))) and 1 or 0,
		settlement_generation = self.settlementGeneration or 0,
		owner_player_id = self.playerId,
		run_complete = self.runComplete and 1 or 0,
		run_failed = self.runFailed and 1 or 0,
		lives_remaining = RunLives.Ensure(self).remaining,
		max_lives = RunLives.MAX_LIVES,
		radiant_alive = self.battleManager:GetAliveCount(DOTA_TEAM_GOODGUYS),
		dire_alive = self.battleManager:GetAliveCount(DOTA_TEAM_BADGUYS),
		winner = self.winner,
		hide_ui = self.phase ~= "setup",
		battle_time = math.floor(self.battleManager:GetBattleTime()),
		time_limit = 120, -- Match BattleManager's hard deadline in every chapter.
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

-- RPG_ISSUE_FIX_BOOTSTRAP_BEGIN
-- Installed after all class methods are defined and before any module return.
require("issue_fixes.bootstrap").Install(CDota2RpgDemo)
-- RPG_ISSUE_FIX_BOOTSTRAP_END
