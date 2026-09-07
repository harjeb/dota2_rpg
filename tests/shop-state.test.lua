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
DOTA_UNIT_ORDER_DROP_ITEM = 12
DOTA_UNIT_ORDER_GIVE_ITEM = 13
DOTA_UNIT_ORDER_PICKUP_ITEM = 14
DOTA_UNIT_ORDER_MOVE_ITEM = 19
DOTA_UNIT_ORDER_TRAIN_ABILITY = 11
DOTA_UNIT_ORDER_PURCHASE_ITEM = 16
DOTA_UNIT_ORDER_SELL_ITEM = 17
DOTA_UNIT_ORDER_DISASSEMBLE_ITEM = 18
DOTA_UNIT_ORDER_MOVE_TO_POINT = 1
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
DOTA_UNIT_ORDER_MOVE_TO_TARGET = 2
DOTA_UNIT_ORDER_HOLD_POSITION = 10
DOTA_UNIT_ORDER_ATTACK_TARGET = 4

local moduleRoot = repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
require = function(name)
	local localModules = {
		["battle.enemy_scaling"] = moduleRoot .. "battle/enemy_scaling.lua",
		["battle.damage_stats"] = moduleRoot .. "battle/damage_stats.lua",
		["data.progression_data"] = moduleRoot .. "data/progression_data.lua",
		["patches.recruitment_patch"] = moduleRoot .. "patches/recruitment_patch.lua",
		["patches.progression_patch"] = moduleRoot .. "patches/progression_patch.lua",
		["patches.enemy_items_patch"] = moduleRoot .. "patches/enemy_items_patch.lua",
	}
	if localModules[name] ~= nil then
		return dofile(localModules[name])
	end
	if name == "issue_fixes.bootstrap" then
		return { Install = function() end }
	end
	error("Dota modules are not needed by the shop-state test: " .. tostring(name))
end

local heroData = {
	strength = {
		["1"] = "npc_dota_hero_axe",
		["2"] = "npc_dota_hero_sven",
	},
	agility = {
		["1"] = "npc_dota_hero_juggernaut",
		["2"] = "npc_dota_hero_sniper",
	},
	intelligence = {
		["1"] = "npc_dota_hero_lina",
		["2"] = "npc_dota_hero_lion",
	},
	universal = {
		["1"] = "npc_dota_hero_marci",
		["2"] = "npc_dota_hero_muerta",
	},
	hero_cost = "500",
	refresh_cost = "20",
	bench_slot_cost = "200",
	bench_slot_max = "5",
	lineup_max = "5",
	initial_gold = "500",
}

local nativeIdLoads = 0
local nativeIdRegistry = {
	-- Structure and sample IDs verified in installed dota/pak01_dir.vpk.
	UnitAbilities = { Locked = { axe_berserkers_call = "5007", item_wrong_namespace = "999999" } },
	ItemAbilities = { Locked = { ability_base = "0", item_blink = "1", item_manta = "147",
		item_recipe_magic_wand = "35", item_overwhelming_blink = "600" } },
}
function LoadKeyValues(path)
	if path == "scripts/npc/npc_ability_ids.txt" then
		nativeIdLoads = nativeIdLoads + 1
		return nativeIdRegistry
	end
	assert(path == "scripts/data/heroes.kv", "unexpected data path: " .. tostring(path))
	return heroData
end

local addonPath = repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua"
local loaded, loadError = pcall(dofile, addonPath)
assert(loaded, "failed to load addon_game_mode.lua: " .. tostring(loadError))

local function newGame(values)
	return setmetatable(values or {}, CDota2RpgDemo)
end

local function assertEqual(actual, expected, message)
	assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

-- A native wallet change must publish even with no fielded heroes/inventory changes.
do
	local previousResource = PlayerResource
	local nativeGold, broadcasts = 1000, 0
	PlayerResource = { GetGold = function() return nativeGold end }
	local walletGame = newGame({
		phase = "setup", teamsSpawned = true, playerId = 0, gold = 1000,
		lastBroadcastGold = 1000,
		ReconcileNativePurchaseOrders = function() end,
		SyncRosterAbilities = function() return false end,
		SyncLiveEquipmentState = function() return false end,
		BroadcastShopState = function(self)
			broadcasts = broadcasts + 1
			self.lastBroadcastGold = self:GetGoldBalance()
		end,
	})
	walletGame:OnThink()
	assertEqual(broadcasts, 0, "unchanged wallet does not spam display")
	nativeGold = 750
	walletGame:GetGoldBalance() -- Other readers must not consume the display change.
	walletGame:OnThink()
	assertEqual(broadcasts, 1, "bench purchase publishes wallet without equipment change")
	assertEqual(walletGame.lastBroadcastGold, 750, "display receives native balance")
	walletGame:OnThink()
	assertEqual(broadcasts, 1, "wallet publication is deduplicated")
	nativeGold = 900
	walletGame:OnThink()
	assertEqual(broadcasts, 2, "native refund also publishes")
	PlayerResource = previousResource
end

local game = newGame({
	currentLevelId = "ch01",
	ownedHeroes = {},
	lineup = {},
	benchSlots = 0,
	shopOffers = {},
	shopOfferText = "",
	refreshCount = 0,
	BroadcastShopState = function(self)
		self.broadcastCalled = true
	end,
})
game:LoadHeroPool()
assertEqual(#game.heroPool.strength, 2, "strength pool size")
assertEqual(#game.heroPool.agility, 2, "agility pool size")
assertEqual(#game.heroPool.intelligence, 2, "intelligence pool size")
assertEqual(#game.heroPool.universal, 2, "universal pool size")
assertEqual(game.shopCosts.initial_gold, 500, "configured initial gold")

game.gold = game.shopCosts.initial_gold
math.randomseed(12345)
game:RollShop()
assertEqual(game.gold, 500, "initial shop gold")
assertEqual(#game.shopOffers, 5, "shop offer size")
assert(game.broadcastCalled, "shop state was not broadcast")

local offerCount = 0
local uniqueOffers = {}
for serializedOffer in string.gmatch(game.shopOfferText, "([^;]+)") do
	offerCount = offerCount + 1
	local heroName = string.match(serializedOffer, "^([^|]+)")
	uniqueOffers[heroName] = true
end
local uniqueCount = 0
for _ in pairs(uniqueOffers) do
	uniqueCount = uniqueCount + 1
end
assertEqual(offerCount, 5, "serialized offer size")
assertEqual(uniqueCount, 5, "serialized unique offer size")

-- 开局不是随机赠送：前两次从当前报价免费选择，第三次按 1 级固定 500 金币扣款。
local recruitmentGame = newGame({
	phase = "setup",
	gold = 500,
	freeRecruitChoices = 2,
	ownedHeroes = {},
	lineup = {},
	benchSlots = 0,
	shopCosts = { lineup_max = 5, bench_slot_max = 5 },
	heroData = {},
	heroOrder = 0,
	shopOffers = {
		{ hero = "npc_dota_hero_axe", level = 1, quality = "legendary", price = 500 },
		{ hero = "npc_dota_hero_lina", level = 1, quality = "common", price = 500 },
		{ hero = "npc_dota_hero_sven", level = 1, quality = "fine", price = 500 },
	},
	RespawnPlayerRoster = function(self) self.respawnCount = (self.respawnCount or 0) + 1 end,
	BroadcastShopState = function(self) self.broadcastCount = (self.broadcastCount or 0) + 1 end,
})
recruitmentGame:OnShopBuy(nil, { hero = "npc_dota_hero_axe" })
assertEqual(recruitmentGame.gold, 500, "first recruit choice must be free")
assertEqual(recruitmentGame.freeRecruitChoices, 1, "first recruit consumes exactly one free choice")
assertEqual(recruitmentGame.heroData.npc_dota_hero_axe.level, 1, "free recruit keeps the offered level")
recruitmentGame:OnShopBuy(nil, { hero = "npc_dota_hero_lina" })
assertEqual(recruitmentGame.gold, 500, "second recruit choice must be free")
assertEqual(recruitmentGame.freeRecruitChoices, 0, "second recruit consumes the final free choice")
recruitmentGame:OnShopBuy(nil, { hero = "npc_dota_hero_sven" })
assertEqual(recruitmentGame.gold, 0, "third recruit must charge the fixed level-one price")
assertEqual(#recruitmentGame.ownedHeroes, 3, "player-selected recruits must be retained")
assertEqual(recruitmentGame.heroData.npc_dota_hero_axe.quality, "legendary", "quality changes effects, not the recruit price")

-- XP 使用相邻累计阈值差值；经验按上阵/待命英雄分别发放，时间奖励上限为 10%。
local progressionGame = newGame({
	heroData = {
		active = { level = 1, current_xp = 0, skill_points = 1 },
		bench = { level = 1, current_xp = 0, skill_points = 1 },
	},
	ownedHeroes = { "active", "bench" },
	lineup = { "active" },
})
progressionGame:AddXpToHero("active", 200)
assertEqual(progressionGame.heroData.active.level, 2, "100 accumulated XP must be spent before the next level")
assertEqual(progressionGame.heroData.active.current_xp, 100, "level two must require the 150 XP difference")
local activeXp, benchXp = progressionGame:AwardStageXp(120)
assertEqual(activeXp, 120, "stage XP is per active hero")
assertEqual(benchXp, 60, "bench XP is floor(active XP * 0.5)")
assertEqual(progressionGame.heroData.active.current_xp, 70, "active hero receives the full stage XP and levels with threshold differences")
assertEqual(progressionGame.heroData.bench.current_xp, 60, "bench hero receives half the stage XP")
assertEqual(progressionGame:CalculateTimeBonus(1000, 0, 120), 100, "time bonus cap is 10 percent")

-- 首次创建战场时必须自动生成报价，不能只广播空 offer_text。
local initial = newGame({
	teamsSpawned = false,
	shopOffers = {},
	currentLevelId = "ch01",
	RollShop = function(self)
		self.rollShopCalled = true
		self.shopOffers = { { hero = "npc_dota_hero_axe" } }
	end,
	SpawnLevelEnemies = function(self)
		self.spawnEnemiesCalled = true
	end,
	RespawnPlayerRoster = function(self)
		self.respawnCalled = true
	end,
	SpawnBattleBarrier = function(self)
		self.barrierCalled = true
	end,
	BroadcastShopState = function(self)
		self.broadcastCalled = true
	end,
	BroadcastLevelInfo = function() end,
	BroadcastBattleState = function() end,
})
initial:EnsureBattlefield()
assert(initial.rollShopCalled, "initial battlefield did not roll the hero shop")
assert(initial.spawnEnemiesCalled and initial.respawnCalled and initial.barrierCalled,
	"initial battlefield setup did not finish")
assert(initial.broadcastCalled, "initial populated shop state was not broadcast")

-- 原版商店钱包 + 小精灵转交：普通物品不再由项目目录购买/出售。
TacticEngine = {
	IsValidUnit = function(unit)
		return unit ~= nil and unit.valid ~= false
	end,
}

local nativeWalletReliable = { [0] = 3000 }
local nativeWalletUnreliable = { [0] = 0 }
local function nativeWalletGold(playerId)
	return (nativeWalletReliable[playerId] or 0) + (nativeWalletUnreliable[playerId] or 0)
end
function GetItemCost(itemName)
	if itemName == nil or itemName == "" or itemName == "item_unknown" then return nil end
	return 250
end

PlayerResource = {
	GetGold = function(_, playerId) return nativeWalletGold(playerId) end,
	GetReliableGold = function(_, playerId) return nativeWalletReliable[playerId] or 0 end,
	GetUnreliableGold = function(_, playerId) return nativeWalletUnreliable[playerId] or 0 end,
	SetGold = function(_, playerId, amount, reliable)
		if reliable then
			nativeWalletReliable[playerId] = math.max(0, math.floor(tonumber(amount) or 0))
		else
			nativeWalletUnreliable[playerId] = math.max(0, math.floor(tonumber(amount) or 0))
		end
	end,
	SetCustomTeamAssignment = function() end,
	GetPlayer = function() return nil end,
}

local nextItemEntityIndex = 9000
local function makeItem(name)
	nextItemEntityIndex = nextItemEntityIndex + 1
	return {
		name = name,
		entityIndex = nextItemEntityIndex,
		IsNull = function() return false end,
		GetAbilityName = function(self) return self.name end,
		GetEntityIndex = function(self) return self.entityIndex end,
		GetCurrentCharges = function(self) return self.charges end,
		SetCurrentCharges = function(self, charges) self.charges = charges end,
	}
end

local function makeInventoryUnit(name, team, maxSlot)
	local unit = {
		name = name,
		team = team or DOTA_TEAM_GOODGUYS,
		maxSlot = maxSlot or 5,
		slots = {},
	}
	function unit:GetUnitName() return self.name end
	function unit:GetTeamNumber() return self.team end
	function unit:IsRealHero() return true end
	function unit:IsNull() return false end
	function unit:GetItemInSlot(slot) return self.slots[slot] end
	function unit:SetOwner(owner) self.owner = owner end
	function unit:SetControllableByPlayer(playerId) self.controllingPlayerId = playerId end
	function unit:GetPlayerOwnerID() return self.controllingPlayerId or -1 end
	function unit:GetAbsOrigin() return { x = 0, y = 0, z = 0 } end
	function unit:AddItem(item)
		if self.rejectAdd then
			return nil
		end
		for slot = 0, self.maxSlot do
			if self.slots[slot] == nil then
				self.slots[slot] = item
				item.holder = self
				return item
			end
		end
		return nil
	end
	function unit:AddItemByName(itemName)
		return self:AddItem(makeItem(itemName))
	end
	function unit:RemoveItem(item)
		for slot = 0, self.maxSlot do
			if self.slots[slot] == item then
				self.slots[slot] = nil
				item.holder = nil
				return
			end
		end
	end
	function unit:SwapItems(firstSlot, secondSlot)
		self.slots[firstSlot], self.slots[secondSlot] = self.slots[secondSlot], self.slots[firstSlot]
	end
	return unit
end

UTIL_Remove = function(item)
	item.removed = true
end
local groundItems = {}
CreateItemOnPositionSync = function(position, item)
	table.insert(groundItems, { position = position, item = item })
	return { item = item }
end

local wisp = makeInventoryUnit("npc_dota_hero_wisp", DOTA_TEAM_GOODGUYS, 14)
local fieldedHero = makeInventoryUnit("npc_dota_hero_axe", DOTA_TEAM_GOODGUYS, 14)
fieldedHero.lineupHeroName = "npc_dota_hero_axe"
local benchHero = makeInventoryUnit("npc_dota_hero_lion", DOTA_TEAM_GOODGUYS, 14)
benchHero.benchHeroName = "npc_dota_hero_lion"
local equipmentGame = newGame({
	phase = "setup",
	gold = 3000,
	playerId = 0,
	lineup = { "npc_dota_hero_axe" },
	heroData = {
		npc_dota_hero_axe = { inventory = {} },
		npc_dota_hero_lion = { inventory = {} },
	},
	placeholderHero = wisp,
	benchUnits = { benchHero },
	pendingNativePurchases = {},
	battleManager = {
		teamHeroes = { [DOTA_TEAM_GOODGUYS] = { fieldedHero }, [DOTA_TEAM_BADGUYS] = {} },
	},
	scrollPurchases = { low = 0, high = 0 },
	scrollStock = { low = 0, high = 0 },
	BroadcastHeroInfo = function(self) self.heroInfoBroadcasts = (self.heroInfoBroadcasts or 0) + 1 end,
	BroadcastShopState = function(self) self.shopBroadcasts = (self.shopBroadcasts or 0) + 1 end,
	RespawnPlayerRoster = function(self) self.unexpectedRespawns = (self.unexpectedRespawns or 0) + 1 end,
})
equipmentGame:SetGoldBalance(3000)
assertEqual(equipmentGame:GetGoldBalance(), 3000, "PlayerResource is the shared item/shop wallet")

-- The order filter must reserve accepted native purchases and reject unknown or
-- unaffordable prices before the engine can create a free item.
equipmentGame.nativePurchaseOrderContexts = {}
nativeWalletReliable[0] = 100
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = {}, itemname = "item_affordability_check",
}), "native purchase must fail closed when the current wallet is insufficient")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = {}, itemname = "item_unknown",
}), "native purchase must fail closed when its cost is unknown")
nativeWalletReliable[0] = 3000
equipmentGame.nativePurchaseOrderContexts = {}
-- Native PURCHASE_ITEM uses a definition ID, not an item entity or a name.
GetAbilityNameByID = nil
GetItemNameByID = nil
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = {}, entindex_ability = 1,
}), "native numeric item definition must resolve before cost preflight")
assertEqual(equipmentGame.nativePurchaseOrderContexts[1].item_name, "item_blink",
	"numeric purchase context must retain the resolved name for event matching")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = {}, entindex_ability = 5007,
}), "ability definitions must not be accepted as purchasable items")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = {}, entindex_ability = 999999,
}), "unknown item definition must still fail closed")
assertEqual(equipmentGame:GetNativePurchaseItemName({ entindex_ability = "35" }), "item_recipe_magic_wand",
	"recipe and string definition IDs resolve through the engine registry")
assertEqual(equipmentGame:GetNativePurchaseItemName({ entindex_ability = 600 }), "item_overwhelming_blink",
	"newer item IDs resolve without a maintained hardcoded list")
assertEqual(equipmentGame:GetNativePurchaseItemName({ entindex_ability = 1.5 }), "", "fractional IDs fail closed")
assertEqual(equipmentGame:GetNativePurchaseItemName({ entindex_ability = 999999, itemname = "item_blink" }), "",
	"unknown IDs cannot be overridden by a name payload")
assertEqual(nativeIdLoads, 1, "successful ID registry is cached across orders")
local registryLoader = LoadKeyValues
local retryGame = newGame()
LoadKeyValues = function() error("registry unavailable") end
assertEqual(retryGame:GetNativePurchaseItemName({ entindex_ability = 1 }), "", "registry errors fail closed")
LoadKeyValues = function() return {} end
assertEqual(retryGame:GetNativePurchaseItemName({ entindex_ability = 1 }), "", "missing item namespace fails closed")
LoadKeyValues = function() return { DOTAAbilityIDs = nativeIdRegistry } end
assertEqual(retryGame:GetNativePurchaseItemName({ entindex_ability = 1 }), "item_blink",
	"failed loads are retried and wrapped KV roots are accepted")
LoadKeyValues = registryLoader
equipmentGame.nativePurchaseOrderContexts = {}
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = {}, itemname = "item_reserved_a",
}), "affordable native purchase must pass its authoritative preflight")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = {}, itemname = "item_reserved_b", item_cost = 3000,
}), "pending native reservation must reduce the available balance")
equipmentGame.nativePurchaseOrderContexts = {}
assertEqual(equipmentGame:SyncGoldToPlayer(), 3000, "legacy wallet sync must never restore stale self.gold")

-- Refresh is a project-side debit but must survive the next think/broadcast
-- cycle exactly like a native-shop debit.
local refreshFlow = newGame({
	phase = "setup", playerId = 0, gold = 500, refreshCount = 0,
	shopOffers = {}, pendingNativePurchases = {}, nativePurchaseOrderContexts = {},
	BroadcastShopState = function(self)
		self.refreshBroadcasts = (self.refreshBroadcasts or 0) + 1
		self.lastBroadcastGold = self:GetGoldBalance()
	end,
	RollShop = function(self) self.rolls = (self.rolls or 0) + 1; self:BroadcastShopState() end,
	teamsSpawned = true,
	SyncLiveEquipmentState = function() end,
	SyncRosterAbilities = function() return false end,
})
-- Starting gold may be entirely unreliable. GetGold already includes it.
nativeWalletReliable[0] = 0
nativeWalletUnreliable[0] = 500
assertEqual(refreshFlow:EnsureGoldWalletInitialized(), 500, "unreliable starting gold must not be counted twice")
refreshFlow:OnShopRefresh(nil, {})
assertEqual(nativeWalletGold(0), 480, "refresh must not turn 500 unreliable gold into 980")
assertEqual(refreshFlow:GetGoldBalance(), 480, "refresh must debit the authoritative wallet")
refreshFlow.gold = 999
refreshFlow:OnThink()
assertEqual(refreshFlow:GetGoldBalance(), 480, "refresh charge must persist through the next think")
assertEqual(refreshFlow.refreshCount, 1, "refresh count must advance exactly once")
assertEqual(refreshFlow.refreshBroadcasts, 1, "refresh must broadcast the refreshed shop once")

-- Missing purchase events on managed heroes reconcile from actual item evidence.
do
	local function resetTracePurchase()
		equipmentGame.nativePurchaseOrderContexts = {}
		equipmentGame.pendingNativePurchases = {}
		equipmentGame.nativePurchaseObservedStates = {}
		equipmentGame.nativePurchaseClaimedIds = {}
		equipmentGame.nativePurchaseTick = 0
		equipmentGame:SetGoldBalance(1000)
	end
	local function order(name, recipient)
		assert(equipmentGame:SetNativePurchaseSelection(recipient))
		assert(equipmentGame:ValidatePrepareOrder({ issuer_player_id_const = 0,
			order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {}, itemname = name }))
	end
	resetTracePurchase()
	order("item_trace_bench", benchHero)
	local benchItem = benchHero:AddItem(makeItem("item_trace_bench"))
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 750, "bench item without event must be charged")
	equipmentGame:ReconcileNativePurchaseOrders()
	equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_trace_bench" })
	equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_trace_bench" })
	equipmentGame:RoutePendingNativePurchases()
	assertEqual(equipmentGame:GetGoldBalance(), 750, "retries, late events and duplicate events must not debit twice")
	benchHero:RemoveItem(benchItem)

	resetTracePurchase()
	order("item_trace_active", fieldedHero)
	local activeItem = fieldedHero:AddItem(makeItem("item_trace_active"))
	nativeWalletReliable[0] = 750
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 750, "already charged active item must not be charged again")
	fieldedHero:RemoveItem(activeItem)

	resetTracePurchase()
	order("item_trace_a", benchHero)
	order("item_trace_b", fieldedHero)
	local firstItem = wisp:AddItem(makeItem("item_trace_a"))
	nativeWalletReliable[0] = 750
	equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_trace_a" })
	equipmentGame:RoutePendingNativePurchases()
	local secondItem = wisp:AddItem(makeItem("item_trace_b"))
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 500, "separate event and silent batches cannot reuse native wallet coverage")
	benchHero:RemoveItem(firstItem)
	fieldedHero:RemoveItem(secondItem)

	resetTracePurchase()
	order("item_trace_same", benchHero)
	order("item_trace_same", benchHero)
	local sameA = wisp:AddItem(makeItem("item_trace_same"))
	local sameB = wisp:AddItem(makeItem("item_trace_same"))
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 500, "two silent purchases charge two costs")
	assert(equipmentGame:IsItemHeldBy(benchHero, sameA, 0, 14)
		and equipmentGame:IsItemHeldBy(benchHero, sameB, 0, 14), "same-recipient purchases must claim distinct entities")
	benchHero:RemoveItem(sameA)
	benchHero:RemoveItem(sameB)

	resetTracePurchase()
	order("item_trace_event_first", benchHero)
	order("item_trace_event_first", benchHero)
	local confirmed = wisp:AddItem(makeItem("item_trace_event_first"))
	equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_trace_event_first" })
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 750, "silent order cannot reuse an event-confirmed item")
	assert(not equipmentGame.nativePurchaseOrderContexts[1].reconciled,
		"second order must await its own result")
	benchHero:RemoveItem(confirmed)

	resetTracePurchase()
	local stack = benchHero:AddItem(makeItem("item_trace_stack"))
	stack.charges = 2
	order("item_trace_stack", benchHero)
	stack.charges = 1
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 1000, "consuming charges is not purchase evidence")
	stack.charges = 3
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 750, "increased stack without event is charged once")
	benchHero:RemoveItem(stack)

	resetTracePurchase()
	local mixedStack = benchHero:AddItem(makeItem("item_trace_mixed_stack"))
	mixedStack.charges = 1
	mixedStack.GetInitialCharges = function() return 1 end
	order("item_trace_mixed_stack", benchHero)
	order("item_trace_mixed_stack", benchHero)
	mixedStack.charges = 3
	equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_trace_mixed_stack" })
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 500, "event purchase must leave the second charge increment for silent reconciliation")
	benchHero:RemoveItem(mixedStack)

	resetTracePurchase()
	local merged = benchHero:AddItem(makeItem("item_trace_merged"))
	merged.charges = 1
	merged.GetInitialCharges = function() return 1 end
	order("item_trace_merged", benchHero)
	order("item_trace_merged", benchHero)
	merged.charges = 3
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 500, "two charge increments on one entity prove two silent purchases")
	benchHero:RemoveItem(merged)

	resetTracePurchase()
	order("item_trace_bundle", benchHero)
	order("item_trace_bundle", benchHero)
	local bundle = benchHero:AddItem(makeItem("item_trace_bundle"))
	bundle.charges = 3
	bundle.GetInitialCharges = function() return 3 end
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 750, "one three-charge bundle is one purchase, not three")
	benchHero:RemoveItem(bundle)

	resetTracePurchase()
	order("item_trace_missing", benchHero)
	local unrelated = wisp:AddItem(makeItem("item_trace_unrelated"))
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(equipmentGame:GetGoldBalance(), 1000, "unrelated new items cannot prove a purchase")
	equipmentGame.nativePurchaseTick = 10
	equipmentGame:ReconcileNativePurchaseOrders()
	assertEqual(#equipmentGame.nativePurchaseOrderContexts, 0, "failed orders expire")
	assertEqual(equipmentGame:GetGoldBalance(), 1000, "expired orders must not charge")
	wisp:RemoveItem(unrelated)
	resetTracePurchase()
end

-- Native shop engines differ:  some debit PlayerResource before emitting
-- dota_item_purchased, while others only create the item. Both paths must
-- charge exactly once, and retries must not charge again.
equipmentGame.pendingNativePurchases = {
	{ recipient_key = "__wisp", item_name = "item_engine_charged",
		gold_before = 1000, item_cost = 250 }
}
nativeWalletReliable[0] = 750
nativeWalletUnreliable[0] = 0
equipmentGame:RoutePendingNativePurchases()
assertEqual(equipmentGame:GetGoldBalance(), 750, "engine-charged native purchase must not be double charged")
equipmentGame:RoutePendingNativePurchases()
assertEqual(equipmentGame:GetGoldBalance(), 750, "native purchase retry must remain idempotent")

equipmentGame.pendingNativePurchases = {
	{ recipient_key = "__wisp", item_name = "item_engine_free",
		gold_before = 1000, item_cost = 250 }
}
nativeWalletReliable[0] = 1000
nativeWalletUnreliable[0] = 0
equipmentGame:RoutePendingNativePurchases()
assertEqual(equipmentGame:GetGoldBalance(), 750, "engine-free native purchase must debit the shared wallet")

equipmentGame.pendingNativePurchases = {
	{ recipient_key = "__wisp", item_name = "item_engine_free_a",
		gold_before = 1000, item_cost = 200 },
	{ recipient_key = "__wisp", item_name = "item_engine_free_b",
		gold_before = 1000, item_cost = 500 },
}
nativeWalletReliable[0] = 1000
nativeWalletUnreliable[0] = 0
equipmentGame:RoutePendingNativePurchases()
assertEqual(equipmentGame:GetGoldBalance(), 300,
	"mixed-cost engine-free purchases must charge the exact aggregate cost")

equipmentGame.pendingNativePurchases = {
	{ recipient_key = "__wisp", item_name = "item_engine_mixed_a",
		gold_before = 1000, item_cost = 200 },
	{ recipient_key = "__wisp", item_name = "item_engine_mixed_b",
		gold_before = 1000, item_cost = 500 },
}
nativeWalletReliable[0] = 500
nativeWalletUnreliable[0] = 0
equipmentGame:RoutePendingNativePurchases()
assertEqual(equipmentGame:GetGoldBalance(), 300,
	"mixed native/project debit must charge only the unobserved aggregate cost")

-- A race or a malformed event must not mark a failed debit as paid or leave
-- the newly created native item available for free.
equipmentGame:SetGoldBalance(100)
equipmentGame.pendingNativePurchases = {}
local unpaidBefore = equipmentGame:CollectManagedItemIds()
local unpaidItem = wisp:AddItem(makeItem("item_unpaid"))
local unpaidPurchase = { recipient_key = "__wisp", item_name = "item_unpaid", gold_before = 100,
	item_cost = 250, before_ids = unpaidBefore }
equipmentGame.pendingNativePurchases = { unpaidPurchase }
equipmentGame:RoutePendingNativePurchases()
assert(unpaidItem.holder == nil and unpaidItem.removed == true,
	"failed native debit must remove the unpaid item")
assert(unpaidPurchase.gold_checked ~= true,
	"failed native debit must not mark the purchase as paid")
equipmentGame.pendingNativePurchases = {}
equipmentGame:SetGoldBalance(3000)

-- 模拟原版商店直接给英雄购买；服务端只吸收真实余额与库存，不重建物品。
local nativeBlink = fieldedHero:AddItemByName("item_blink")
nativeWalletReliable[0] = 750
nativeWalletUnreliable[0] = 0
assertEqual(equipmentGame:SyncGoldFromPlayer(), 750, "native store deduction must update project wallet mirror")
equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_blink" })
assert(equipmentGame.nativeShopTransactionPending, "native item purchase must request an inventory/UI sync")
equipmentGame:SyncHeroInventoryFromUnit(fieldedHero)
assertEqual(equipmentGame.heroData.npc_dota_hero_axe.inventory[1], "item_blink", "native direct purchase stays on the selected fielded hero")

-- 原版远程购买会落入 9..14 储藏栏；同步时应把每个槽位的同一实体提升到可用物品栏。
local remotePurchases = {}
for slot = 9, 14 do
	local item = makeItem("item_remote_" .. slot)
	remotePurchases[slot] = item
	wisp.slots[slot] = item
	item.holder = wisp
end
equipmentGame:OnNativeItemPurchased({ player_id = 0, itemname = "item_remote_9" })
assert(equipmentGame.nativeShopTransactionPending, "native purchase must accept lowercase player id fields")
equipmentGame:SyncLiveEquipmentState(true)
for slot = 9, 14 do
	assert(wisp:GetItemInSlot(slot) == nil and wisp:GetItemInSlot(slot - 9) == remotePurchases[slot],
		"remote-purchase stash slot " .. slot .. " must be promoted without recreating the entity")
end

-- 即使 0..8 已满，面板仍须能按实体 ID 直接从原生储藏栏转交给有空位的上阵英雄。
for slot = 0, 8 do
	wisp.slots[slot] = wisp.slots[slot] or makeItem("item_stash_filler_" .. slot)
end
local directFromNativeStash = makeItem("item_force_staff")
wisp.slots[10] = directFromNativeStash
directFromNativeStash.holder = wisp
equipmentGame:OnItemEquip(nil, {
	hero = "npc_dota_hero_axe", item = "item_force_staff",
	item_index = tostring(directFromNativeStash:GetEntityIndex())
})
assert(wisp:GetItemInSlot(10) == nil and fieldedHero:GetItemInSlot(1) == directFromNativeStash,
	"one-click transfer must take the exact entity directly from native stash slots")
for slot = 0, 8 do
	wisp.slots[slot] = nil
end
for _, item in pairs(remotePurchases) do
	item.holder = nil
end
fieldedHero:RemoveItem(directFromNativeStash)

-- 选中待命英雄购买时，原版若把新物品交给 assigned hero 小精灵，下一轮必须补转同一实体。
equipmentGame.pendingNativePurchases = {}
assert(equipmentGame:IsEquipmentCarrier(benchHero), "bench hero must be a managed equipment carrier")
equipmentGame:SetNativePurchaseSelection(benchHero)
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
	entindex_ability = 147,
}), "bench numeric purchase must capture the authoritative preflight wallet snapshot")
assertEqual(equipmentGame.nativePurchaseOrderContexts[1].gold_before, 750,
	"native purchase preflight must retain the wallet snapshot consumed by the event path")
local benchPurchase = wisp:AddItem(makeItem("item_manta"))
equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_manta" })
equipmentGame:RoutePendingNativePurchases()
assert(not equipmentGame:IsItemHeldBy(wisp, benchPurchase, 0, 14)
	and equipmentGame:IsItemHeldBy(benchHero, benchPurchase, 0, 14),
	"bench direct purchase must route the exact newly purchased entity away from the wisp")
assertEqual(equipmentGame.heroData.npc_dota_hero_lion.inventory[1], "item_manta",
	"bench purchase must immediately update persistent current-run inventory")

-- 待命转上阵时继续携带同一实体，而不是清空或重建同名装备。
equipmentGame:CaptureHeroInventoryForRespawn(benchHero)
local promotedLion = makeInventoryUnit("npc_dota_hero_lion", DOTA_TEAM_GOODGUYS, 14)
promotedLion.lineupHeroName = "npc_dota_hero_lion"
equipmentGame:BindEquipmentCarrierToPlayer(promotedLion)
equipmentGame:RestoreHeroInventoryToUnit("npc_dota_hero_lion", promotedLion)
assert(equipmentGame:IsItemHeldBy(promotedLion, benchPurchase, 0, 14),
	"bench-to-lineup rebuild must preserve the exact item entity")
assert(promotedLion.owner == wisp and promotedLion.controllingPlayerId == 0,
	"additional heroes must be owned and controllable by the player for native shop selection")
local savedSetOwner = benchHero.SetOwner
benchHero.SetOwner = function() error("owner binding failure") end
assert(not equipmentGame:SetNativePurchaseSelection(benchHero),
	"native purchase target selection must reject an unbound hero")
benchHero.SetOwner = savedSetOwner
assert(equipmentGame:SetNativePurchaseSelection(benchHero),
	"native purchase target selection must recover after ownership binding succeeds")
promotedLion:RemoveItem(benchPurchase)
equipmentGame.heroData.npc_dota_hero_lion.inventory = {}
equipmentGame.heroData.npc_dota_hero_lion.inventory_states = {}
equipmentGame.heroData.npc_dota_hero_lion.inventory_entities = {}

-- 没有成功购买事件的旧订单不能污染下一次原版购买。
equipmentGame.nativePurchaseTick = 10
equipmentGame.nativePurchaseOrderContexts = {
	{ recipient_key = "npc_dota_hero_lion", before_ids = {}, created_tick = 0 }
}
equipmentGame:PruneNativePurchaseOrderContexts()
assertEqual(#equipmentGame.nativePurchaseOrderContexts, 0,
	"stale native purchase contexts must expire before a later successful purchase")

-- 两次快速购买必须各自保留购买前快照，并按事件顺序把同名/不同名的新实体分配给不同目标。
equipmentGame.pendingNativePurchases = {}
equipmentGame.nativePurchaseOrderContexts = {}
equipmentGame.nativePurchaseClaimedIds = {}
-- Keep the fixture wallet funded for the following real preflight/debit sequence;
-- production receives the corresponding balance from PlayerResource.
nativeWalletReliable[0] = 3000
nativeWalletUnreliable[0] = 0
equipmentGame:SyncGoldFromPlayer()
equipmentGame:SetNativePurchaseSelection(benchHero)
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {}, itemname = "item_rapid",
}), "first rapid purchase must enqueue its own target context")
equipmentGame:SetNativePurchaseSelection(fieldedHero)
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {}, itemname = "item_rapid",
}), "second rapid purchase must enqueue independently")
local rapidBenchItem = wisp:AddItem(makeItem("item_rapid"))
local rapidFieldedItem = wisp:AddItem(makeItem("item_rapid"))
equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_rapid" })
equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_rapid" })
equipmentGame:RoutePendingNativePurchases()
assert(equipmentGame:IsItemHeldBy(benchHero, rapidBenchItem, 0, 14)
	and equipmentGame:IsItemHeldBy(fieldedHero, rapidFieldedItem, 0, 14),
	"rapid same-name purchases must route distinct exact entities to their queued targets")
benchHero:RemoveItem(rapidBenchItem)
fieldedHero:RemoveItem(rapidFieldedItem)

-- 购买可堆叠物品时可能没有新实体 ID；charges 变化也必须触发同一实体转移。
local stackedPurchase = makeItem("item_clarity")
stackedPurchase.charges = 1
wisp:AddItem(stackedPurchase)
equipmentGame:SetNativePurchaseSelection(benchHero)
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {}, itemname = "item_clarity",
}), "stack purchase must capture the pre-purchase item state")
stackedPurchase.charges = 2
equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_clarity" })
equipmentGame:RoutePendingNativePurchases()
assert(equipmentGame:IsItemHeldBy(benchHero, stackedPurchase, 0, 14)
	and stackedPurchase.charges == 2,
	"stacking purchase must route the changed original item entity and preserve charges")

-- 另一目标购买同名堆叠物时只拆出本次增加的 1 个 charge，不把整个旧堆转走。
equipmentGame:SetNativePurchaseSelection(fieldedHero)
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {}, itemname = "item_clarity",
}), "second stack purchase must capture the existing routed stack")
stackedPurchase.charges = 3
equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_clarity" })
equipmentGame:RoutePendingNativePurchases()
assert(stackedPurchase.charges == 2 and equipmentGame:IsItemHeldBy(benchHero, stackedPurchase, 0, 14),
	"split stack purchase must leave the earlier target's charges intact")
local splitStackItem = nil
for slot = 0, 14 do
	local candidate = fieldedHero:GetItemInSlot(slot)
	if candidate ~= nil and candidate:GetAbilityName() == "item_clarity" then
		splitStackItem = candidate
		break
	end
end
assert(splitStackItem ~= nil and splitStackItem:GetCurrentCharges() == 1,
	"split stack purchase must give the second target one charge")

-- 目标已有同名堆时，拆分只能把 +1 合并到旧 charge，不能把旧堆重置成 1。
fieldedHero:RemoveItem(splitStackItem)
local existingTargetStack = makeItem("item_clarity")
existingTargetStack.charges = 5
fieldedHero:AddItem(existingTargetStack)
local originalAddItemByName = fieldedHero.AddItemByName
stackedPurchase.charges = 3
function fieldedHero:AddItemByName(itemName)
	if itemName == "item_clarity" then
		existingTargetStack.charges = existingTargetStack.charges + 1
		return existingTargetStack
	end
	return originalAddItemByName(self, itemName)
end
local splitMerged, splitMergedItem = equipmentGame:SplitMergedPurchaseStack({
	item_name = "item_clarity", recipient_key = "npc_dota_hero_axe",
	before_ids = { [tostring(stackedPurchase:GetEntityIndex())] = { name = "item_clarity", charges = 2 } },
}, { holder = benchHero, item = stackedPurchase, item_id = tostring(stackedPurchase:GetEntityIndex()) }, fieldedHero)
assert(splitMerged and splitMergedItem == existingTargetStack and existingTargetStack.charges == 6
	and stackedPurchase.charges == 2,
	"split into an existing stack must preserve old charges and decrement the source once")
fieldedHero.AddItemByName = originalAddItemByName
fieldedHero:RemoveItem(existingTargetStack)
benchHero:RemoveItem(stackedPurchase)

for slot = 0, 14 do
	local filler = makeItem("item_full_capacity_" .. slot)
	wisp.slots[slot] = filler
	filler.holder = wisp
end
assert(not equipmentGame:HasFreeStashSlot(), "all 15 wisp inventory/backpack/native-stash slots must count as full")
for slot = 0, 14 do
	wisp.slots[slot] = nil
end

-- 目标 AddItem 异常失败时，装备/卸下都必须把同一实体退回来源，不能吞物品或同名重建。
local failedEquip = makeItem("item_failed_equip")
wisp:AddItem(failedEquip)
fieldedHero.rejectAdd = true
equipmentGame:OnItemEquip(nil, {
	hero = "npc_dota_hero_axe", item = "item_failed_equip",
	item_index = tostring(failedEquip:GetEntityIndex())
})
assert(equipmentGame:IsItemHeldBy(wisp, failedEquip, 0, 14),
	"failed equip must return the exact entity to the wisp")
fieldedHero.rejectAdd = false
wisp:RemoveItem(failedEquip)

local failedUnequip = makeItem("item_failed_unequip")
fieldedHero:AddItem(failedUnequip)
wisp.rejectAdd = true
assert(not equipmentGame:MoveHeroItemToStash(fieldedHero, failedUnequip),
	"forced stash insertion failure must report failure")
assert(equipmentGame:IsItemHeldBy(fieldedHero, failedUnequip, 0, 14),
	"failed unequip must return the exact entity to its hero")
wisp.rejectAdd = false
fieldedHero:RemoveItem(failedUnequip)

-- 双方都拒绝 AddItem 时，以同一实体掉落到来源脚下作为最终保险。
local groundFallback = makeItem("item_ground_fallback")
fieldedHero.rejectAdd = true
wisp.rejectAdd = true
assert(equipmentGame:PreserveDetachedItem(groundFallback, fieldedHero, "test rollback"),
	"ground fallback must preserve a live detached item")
assert(groundItems[#groundItems].item == groundFallback,
	"ground fallback must use the exact original entity")
fieldedHero.rejectAdd = false
wisp.rejectAdd = false

local heroNativeStashItem = makeItem("item_hero_native_stash")
fieldedHero.slots[14] = heroNativeStashItem
heroNativeStashItem.holder = fieldedHero
equipmentGame:OnItemUnequip(nil, {
	hero = "npc_dota_hero_axe", item = "item_hero_native_stash",
	item_index = tostring(heroNativeStashItem:GetEntityIndex()), slot = 14
})
assert(equipmentGame:IsItemHeldBy(wisp, heroNativeStashItem, 0, 14),
	"hero native stash slot 14 must remain visible and unloadable by exact entity id")
wisp:RemoveItem(heroNativeStashItem)

-- 自建区域只出售两种卷轴，但必须和原版商店共用同一个 PlayerResource 金额。
-- Reset this independent fixture segment after the native purchase routing cases.
nativeWalletReliable[0] = 750
nativeWalletUnreliable[0] = 0
equipmentGame:SyncGoldFromPlayer()
equipmentGame:OnScrollBuy(nil, { kind = "low" })
assertEqual(nativeWalletGold(0), 650, "scroll purchase must debit the same wallet as the native shop")
assertEqual(equipmentGame.scrollStock.low, 1, "scroll panel must retain the two-scroll stock flow")
local scrollStockBeforeLock = equipmentGame.scrollStock.low
local scrollXpBeforeLock = equipmentGame.heroData.npc_dota_hero_axe.current_xp or 0
equipmentGame.phase = "fight"
equipmentGame:OnScrollUse(nil, { kind = "low", hero = "npc_dota_hero_axe" })
assertEqual(equipmentGame.scrollStock.low, scrollStockBeforeLock,
	"scroll use must be locked during battle")
assertEqual(equipmentGame.heroData.npc_dota_hero_axe.current_xp or 0, scrollXpBeforeLock,
	"battle-phase scroll use must not grant experience")
equipmentGame.phase = "result"
equipmentGame:OnScrollUse(nil, { kind = "low", hero = "npc_dota_hero_axe" })
assertEqual(equipmentGame.scrollStock.low, scrollStockBeforeLock,
	"scroll use must be locked during settlement")
equipmentGame.phase = "setup"

-- 先在原版商店买到小精灵，再点击装备：搬运同一个实体且保持当前英雄。
local stashedWand = makeItem("item_magic_wand")
wisp:AddItem(stashedWand)
equipmentGame:OnItemEquip(nil, {
	hero = "npc_dota_hero_axe", item = "item_magic_wand",
	item_index = tostring(stashedWand:GetEntityIndex())
})
assert(wisp:GetItemInSlot(0) == nil, "one-click equip removes the original item from wisp stash")
assert(fieldedHero:GetItemInSlot(1) == stashedWand, "one-click equip moves the exact native-store item entity to the hero")
assertEqual(equipmentGame.heroData.npc_dota_hero_axe.inventory[2], "item_magic_wand", "one-click equip keeps the inventory mirror current")
assert(equipmentGame.unexpectedRespawns == nil, "stash transfer must not require re-fielding the hero")
-- 即使携带合法 ID，slot 兼容回退也不能移动另一件物品。
local originalSlotZero = fieldedHero:GetItemInSlot(0)
equipmentGame:OnItemUnequip(nil, {
	hero = "npc_dota_hero_axe", item = "", slot = 0,
	item_index = tostring(stashedWand:GetEntityIndex())
})
assert(fieldedHero:GetItemInSlot(0) == originalSlotZero,
	"slot fallback must reject an entity ID that does not match the item in that slot")

-- All nine inventory/backpack slots must be occupied before rejecting a transfer.
for slot = 2, 8 do
	fieldedHero.slots[slot] = makeItem("item_dummy_" .. slot)
end
local secondWand = makeItem("item_magic_wand")
wisp:AddItem(secondWand)
equipmentGame:OnItemEquip(nil, {
	hero = "npc_dota_hero_axe", item = "item_magic_wand",
	item_index = tostring(secondWand:GetEntityIndex())
})
assert(wisp:GetItemInSlot(0) == secondWand, "full hero inventory rejects transfer without losing the native item")
for slot = 2, 8 do
	fieldedHero.slots[slot] = nil
end

-- UI 使用名称卸下，服务端以真实实体 ID 定位；不会按同名物品误选。
equipmentGame:OnItemUnequip(nil, {
	hero = "npc_dota_hero_axe", item = "item_magic_wand",
	item_index = tostring(stashedWand:GetEntityIndex())
})
assert(fieldedHero:GetItemInSlot(1) == nil, "unequip removes the selected real hero item")
assert(equipmentGame:IsItemHeldBy(wisp, stashedWand, 0, 14),
	"unequip returns the same entity to the wisp inventory or native stash")
assertEqual(#equipmentGame.heroData.npc_dota_hero_axe.inventory, 1, "unequip refreshes the recorded hero inventory")

-- 原版 HUD 的地面拾取没有 CustomGameEvent；事件/轮询必须把其结果同步回装备 UI。
fieldedHero:AddItemByName("item_magic_wand")
equipmentGame:OnItemPickedUp({})
assertEqual(#equipmentGame.heroData.npc_dota_hero_axe.inventory, 2, "native item pickup refreshes the hero inventory mirror")

-- 订单过滤器不能再阻断上阵英雄的物品拖放/拾取。
DOTA_UNIT_ORDER_DROP_ITEM = 12
DOTA_UNIT_ORDER_GIVE_ITEM = 13
DOTA_UNIT_ORDER_PICKUP_ITEM = 14
DOTA_UNIT_ORDER_MOVE_ITEM = 19
DOTA_UNIT_ORDER_TRAIN_ABILITY = 11
DOTA_UNIT_ORDER_PURCHASE_ITEM = 16
DOTA_UNIT_ORDER_SELL_ITEM = 17
DOTA_UNIT_ORDER_DISASSEMBLE_ITEM = 18
DOTA_UNIT_ORDER_MOVE_TO_POINT = 1
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
DOTA_UNIT_ORDER_MOVE_TO_TARGET = 2
DOTA_UNIT_ORDER_HOLD_POSITION = 10
DOTA_UNIT_ORDER_ATTACK_TARGET = 4
local groundWand = makeItem("item_magic_wand")
local groundDrop = {
	IsNull = function() return false end,
	GetContainedItem = function() return groundWand end,
}
local equippedBlink = fieldedHero:GetItemInSlot(0)
local nativeStashSale = makeItem("item_ultimate_orb")
wisp.slots[9] = nativeStashSale
nativeStashSale.holder = wisp
local entities = {
	[501] = fieldedHero,
	[502] = wisp,
	[503] = benchHero,
	[equippedBlink:GetEntityIndex()] = equippedBlink,
	[nativeStashSale:GetEntityIndex()] = nativeStashSale,
	[groundWand:GetEntityIndex()] = groundDrop,
}
EntIndexToHScript = function(index) return entities[index] end
equipmentGame.placedPositions = {}
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
	itemname = "item_prepare_empty_units",
}), "prepare order filter must allow an affordable empty-units native purchase during setup")
function wisp:GetEntityIndex() return 502 end
local benchPurchaseOrder = {
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = { ["0"] = 503 }, itemname = "item_prepare_bench",
}
assert(equipmentGame:ValidatePrepareOrder(benchPurchaseOrder), "prepare order filter allows affordable bench delivery")
assertEqual(benchPurchaseOrder.units["0"], 502, "native purchase executes on assigned hero wallet")
assertEqual(equipmentGame.nativePurchaseOrderContexts[#equipmentGame.nativePurchaseOrderContexts].recipient_key,
	"npc_dota_hero_lion", "rerouting purchaser preserves bench delivery target")

-- Skill-up clicks can submit either the ability entity index or its slot.
local skillAbility = {
	level = 0,
	IsNull = function() return false end,
	entindex = function() return 8801 end,
	GetAbilityName = function() return "test_skill" end,
	GetLevel = function(self) return self.level end,
	SetLevel = function(self, value) self.level = value end,
}
function fieldedHero:GetLevel() return self.level or 1 end
function fieldedHero:GetAbilityCount() return 1 end
function fieldedHero:GetAbilityByIndex(index) return index == 0 and skillAbility or nil end
function fieldedHero:GetAbilityPoints() return self.abilityPoints or 0 end
function fieldedHero:SetAbilityPoints(value) self.abilityPoints = value end
fieldedHero.level, fieldedHero.abilityPoints, fieldedHero.rpgAbilitiesRestored = 1, 2, true
equipmentGame.heroData.npc_dota_hero_axe.level = 1
equipmentGame.heroData.npc_dota_hero_axe.skill_points = 2
equipmentGame.heroData.npc_dota_hero_axe.ability_levels = { test_skill = 0 }
assert(not equipmentGame:SyncRosterAbilities(), "initial skill snapshot must be quiet")
skillAbility.level = 1
fieldedHero.abilityPoints = 1
assert(equipmentGame:SyncRosterAbilities(), "deferred skill sync must detect native training")
assertEqual(equipmentGame.heroData.npc_dota_hero_axe.ability_levels.test_skill, 1,
	"deferred skill sync must persist native ability level")
assertEqual(equipmentGame.heroData.npc_dota_hero_axe.skill_points, 1,
	"deferred skill sync must persist remaining skill points")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = { ["0"] = 501 }, entindex_ability = 8801,
}), "fielded hero skill upgrade must pass the native order validator")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = { ["0"] = 501 }, entindex_ability = 0,
}), "slot-based skill upgrade must pass the native order validator")
entities[8801] = skillAbility
function skillAbility:GetCaster() return fieldedHero end
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = {}, entindex_ability = 8801,
}), "unitless skill training must resolve the managed caster from the ability entity")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 1, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = {}, entindex_ability = 8801,
}), "unitless training must reject a foreign issuer")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = {}, entindex_ability = 0,
}), "unitless training must not infer a hero from an ambiguous ability slot")
function skillAbility:GetCaster() return wisp end
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = {}, entindex_ability = 8801,
}), "unitless training must reject a caster outside the player hero roster")
function skillAbility:GetCaster() return fieldedHero end
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = { ["0"] = 501 }, entindex_ability = 9999,
}), "skill upgrade must reject an ability not owned by the source hero")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = -1, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
}), "managed native shop orders without a real player issuer must not bypass phase or ownership checks")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_SELL_ITEM,
	units = {}, entindex_ability = equippedBlink:GetEntityIndex(),
}), "prepare order filter must allow selling an item held by a managed hero")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_SELL_ITEM,
	units = {}, entindex_ability = nativeStashSale:GetEntityIndex(),
}), "prepare order filter must allow selling an item held in native stash slots")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 502 }, entindex_ability = nativeStashSale:GetEntityIndex(),
}), "prepare order filter must not reject a managed item merely because it is in slot 9")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(),
}), "prepare order filter must allow a fielded hero to drop its own tracked item")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PICKUP_ITEM,
	units = { ["0"] = 501 }, entindex_target = groundWand:GetEntityIndex(),
}), "prepare order filter must allow a fielded hero to pick up a tracked ground item")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 501 }, entindex_ability = groundWand:GetEntityIndex(),
}), "prepare order filter must reject dropping an item not held by the selected hero")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_ITEM,
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(), entindex_target = 8,
}), "prepare order filter must allow moving a held item to a valid hero backpack slot")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_ITEM,
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(), entindex_target = 9,
}), "prepare order filter must allow moving a hero item into the native remote-purchase stash")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_ITEM,
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(), entindex_target = 15,
}), "prepare order filter must reject moving a hero item beyond the native stash")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_TO_POINT,
	units = { ["0"] = 502 }, position_x = -200, position_y = 10,
}), "prepare order filter must allow the wisp to move during setup")

-- OrderFilter 也必须锁住非战斗名单中的小精灵，不能在战斗阶段绕过 ValidatePrepareOrder。
local orderFilterModule = assert(loadfile(repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/tactics/order_filter.lua"))()
local activePhase = "PREPARE"
equipmentGame.nativePurchaseOrderContexts = {}
equipmentGame.pendingNativePurchases = {}
local nativeFilter = orderFilterModule.OrderFilter.new({
	get_phase = function() return activePhase end,
	is_battle_unit = function(unit) return unit == fieldedHero end,
	is_inventory_unit = function(unit) return unit == wisp end,
	is_managed_order = function(filterTable) return equipmentGame:IsNativeItemShopOrder(filterTable) end,
	validate_prepare_order = function(filterTable) return equipmentGame:ValidatePrepareOrder(filterTable) end,
	validate_inventory_order = function(filterTable) return equipmentGame:ValidatePrepareOrder(filterTable) end,
})
entities[502] = wisp
entities[stashedWand:GetEntityIndex()] = stashedWand
assert(nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 502 }, entindex_ability = stashedWand:GetEntityIndex(),
}), "OrderFilter must allow a wisp to drop its own item during prepare")
assert(nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
	itemname = "item_filter_prepare",
}), "OrderFilter must admit an affordable native purchase with no units during prepare")
assert(nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = {}, entindex_ability = 8801,
}), "outer filter must route unitless training through roster validation")
assert(not nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = {}, entindex_ability = 9999,
}), "outer filter must not bypass training ownership validation")
activePhase = "FIGHT"
assert(not nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY,
	units = {}, entindex_ability = 8801,
}), "outer filter must block unitless training during combat")
assert(not nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 502 }, entindex_ability = stashedWand:GetEntityIndex(),
}), "OrderFilter must block wisp inventory orders during battle")
assert(not nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
	itemname = "item_filter_fight",
}), "OrderFilter must block empty-units native purchases during battle")

-- 实体被同名物品替换时，签名也必须变化，才能把新 item_index 推给 Panorama。
activePhase = "PREPARE"
local snapshotBeforeReplacement = equipmentGame:BuildEquipmentSnapshot()
wisp:RemoveItem(stashedWand)
local replacementWand = makeItem("item_magic_wand")
wisp:AddItem(replacementWand)
assert(snapshotBeforeReplacement ~= equipmentGame:BuildEquipmentSnapshot(),
	"equipment snapshot must include entity IDs, not only item names and slots")

-- The real shop payload must identify active and bench entities, and refresh
-- those identifiers after a roster rebuild so native HUD selection cannot go stale.
local shopPayload
local priorEvents = CustomGameEventManager
CustomGameEventManager = {
	Send_ServerToAllClients = function(_, name, data)
		assertEqual(name, "rpg_shop_state", "shop broadcast event")
		shopPayload = data
	end,
}
function fieldedHero:GetEntityIndex() return 501 end
function benchHero:GetEntityIndex() return 503 end
local broadcastGame = newGame({
	ownedHeroes = { "npc_dota_hero_axe", "npc_dota_hero_lion" },
	heroData = equipmentGame.heroData,
	lineup = { "npc_dota_hero_axe" }, benchSlots = 1, refreshCount = 0,
	shopCosts = { bench_slot = 200, bench_slot_max = 5, lineup_max = 5 },
	scrollPurchases = {}, scrollStock = {},
	GetGoldBalance = function() return 500 end,
	GetStashUnit = function() return wisp end,
	FindOwnedHeroUnit = function(_, name)
		return name == "npc_dota_hero_axe" and fieldedHero or benchHero
	end,
})
broadcastGame:BroadcastShopState()
assertEqual(shopPayload.hero_entity_indices.npc_dota_hero_axe, 501, "active native selection ID")
assertEqual(shopPayload.hero_entity_indices.npc_dota_hero_lion, 503, "bench native selection ID")
function benchHero:GetEntityIndex() return 603 end
broadcastGame:BroadcastShopState()
assertEqual(shopPayload.hero_entity_indices.npc_dota_hero_lion, 603, "respawn refreshes native selection ID")
CustomGameEventManager = priorEvents

print("PASS: initial hero shop rolls five unique offers and broadcasts before setup UI; direct equipment, wisp transfer, native pickup sync, and prep item orders work")
