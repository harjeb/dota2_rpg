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

function LoadKeyValues(path)
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
PlayerResource = {
	GetGold = function(_, playerId) return nativeWalletGold(playerId) end,
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
local beforeBenchPurchase = equipmentGame:CollectManagedItemIds()
local benchPurchase = wisp:AddItem(makeItem("item_manta"))
equipmentGame.nativePurchaseOrderContexts = {
	{
		recipient_key = "npc_dota_hero_lion",
		before_ids = beforeBenchPurchase,
		item_name = "item_manta",
		created_tick = equipmentGame.nativePurchaseTick or 0,
	}
}
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
}), "prepare order filter must allow an empty-units native purchase during setup")
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
	units = { ["0"] = 503 },
}), "prepare order filter must allow a player-owned bench hero to issue native purchases")
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
local nativeFilter = orderFilterModule.OrderFilter.new({
	get_phase = function() return activePhase end,
	is_battle_unit = function(unit) return unit == fieldedHero end,
	is_inventory_unit = function(unit) return unit == wisp end,
	is_managed_order = function(filterTable) return equipmentGame:IsNativeItemShopOrder(filterTable) end,
	validate_prepare_order = function(filterTable) return equipmentGame:ValidatePrepareOrder(filterTable) end,
})
entities[502] = wisp
entities[stashedWand:GetEntityIndex()] = stashedWand
assert(nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 502 }, entindex_ability = stashedWand:GetEntityIndex(),
}), "OrderFilter must allow a wisp to drop its own item during prepare")
assert(nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
}), "OrderFilter must admit a native purchase with no units during prepare")
activePhase = "FIGHT"
assert(not nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 502 }, entindex_ability = stashedWand:GetEntityIndex(),
}), "OrderFilter must block wisp inventory orders during battle")
assert(not nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
}), "OrderFilter must block empty-units native purchases during battle")

-- 实体被同名物品替换时，签名也必须变化，才能把新 item_index 推给 Panorama。
activePhase = "PREPARE"
local snapshotBeforeReplacement = equipmentGame:BuildEquipmentSnapshot()
wisp:RemoveItem(stashedWand)
local replacementWand = makeItem("item_magic_wand")
wisp:AddItem(replacementWand)
assert(snapshotBeforeReplacement ~= equipmentGame:BuildEquipmentSnapshot(),
	"equipment snapshot must include entity IDs, not only item names and slots")

print("PASS: initial hero shop rolls five unique offers and broadcasts before setup UI; direct equipment, wisp transfer, native pickup sync, and prep item orders work")
