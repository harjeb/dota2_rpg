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

require = function()
	error("Dota modules are not needed by the shop-state test")
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
	hero_cost = "100",
	refresh_cost = "20",
	bench_slot_cost = "200",
	bench_slot_max = "5",
	lineup_max = "5",
	initial_gold = "300",
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
assertEqual(game.shopCosts.initial_gold, 300, "configured initial gold")

game.gold = game.shopCosts.initial_gold
math.randomseed(12345)
game:RollShop()
assertEqual(game.gold, 300, "initial shop gold")
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

-- 首次创建战场时必须自动生成报价，不能只广播空 offer_text。
local initial = newGame({
	teamsSpawned = false,
	shopOffers = {},
	itemCatalog = {},
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

-- 装备路径：玩家应可直接购买并装备，或从小精灵库存稳定转移；不能通过重生英雄破坏选择状态。
TacticEngine = {
	IsValidUnit = function(unit)
		return unit ~= nil and unit.valid ~= false
	end,
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
	function unit:AddItem(item)
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
	return unit
end

UTIL_Remove = function(item)
	item.removed = true
end

local wisp = makeInventoryUnit("npc_dota_hero_wisp", DOTA_TEAM_GOODGUYS, 8)
local fieldedHero = makeInventoryUnit("npc_dota_hero_axe", DOTA_TEAM_GOODGUYS, 5)
local equipmentGame = newGame({
	phase = "setup",
	gold = 3000,
	lineup = { "npc_dota_hero_axe" },
	heroData = { npc_dota_hero_axe = { inventory = {} } },
	itemCatalog = { item_blink = 2250, item_magic_wand = 450 },
	placeholderHero = wisp,
	battleManager = {
		teamHeroes = { [DOTA_TEAM_GOODGUYS] = { fieldedHero }, [DOTA_TEAM_BADGUYS] = {} },
	},
	BroadcastHeroInfo = function(self) self.heroInfoBroadcasts = (self.heroInfoBroadcasts or 0) + 1 end,
	BroadcastShopState = function(self) self.shopBroadcasts = (self.shopBroadcasts or 0) + 1 end,
	RespawnPlayerRoster = function(self) self.unexpectedRespawns = (self.unexpectedRespawns or 0) + 1 end,
})

equipmentGame:OnItemBuyEquip(nil, { hero = "npc_dota_hero_axe", item = "item_blink" })
assertEqual(equipmentGame.gold, 750, "direct buy+equip spends the item cost once")
assertEqual(fieldedHero:GetItemInSlot(0):GetAbilityName(), "item_blink", "direct buy+equip puts the item on the selected fielded hero")
assertEqual(equipmentGame.heroData.npc_dota_hero_axe.inventory[1], "item_blink", "direct buy+equip records the real hero inventory")
assert(equipmentGame.unexpectedRespawns == nil, "equip must not respawn/destroy the selected hero")

-- 先存小精灵再点击装备，必须搬运同一个实体且保持当前英雄，不依赖丢地/拾取。
equipmentGame.gold = 2000
equipmentGame:OnItemBuy(nil, { item = "item_magic_wand" })
local stashedWand = wisp:GetItemInSlot(0)
assert(stashedWand ~= nil, "store purchase puts a real item on the wisp")
equipmentGame:OnItemEquip(nil, {
	hero = "npc_dota_hero_axe", item = "item_magic_wand",
	item_index = tostring(stashedWand:GetEntityIndex())
})
assert(wisp:GetItemInSlot(0) == nil, "one-click equip removes the item from wisp stash")
assert(fieldedHero:GetItemInSlot(1) == stashedWand, "one-click equip moves the exact wisp item entity to the hero")
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

-- 满六格时服务器必须拒绝直接购买且不扣钱。
for slot = 2, 5 do
	fieldedHero.slots[slot] = makeItem("item_dummy_" .. slot)
end
local goldBeforeFullBuy = equipmentGame.gold
equipmentGame:OnItemBuyEquip(nil, { hero = "npc_dota_hero_axe", item = "item_magic_wand" })
assertEqual(equipmentGame.gold, goldBeforeFullBuy, "full hero inventory rejects direct purchase without charging gold")
fieldedHero.slots[2] = nil
fieldedHero.slots[3] = nil
fieldedHero.slots[4] = nil
fieldedHero.slots[5] = nil

-- UI 使用名称卸下，服务端从真实槽位定位；手动调换槽位也不会选错装备。
equipmentGame:OnItemUnequip(nil, {
	hero = "npc_dota_hero_axe", item = "item_magic_wand",
	item_index = tostring(stashedWand:GetEntityIndex())
})
assert(fieldedHero:GetItemInSlot(1) == nil, "unequip removes the selected real hero item")
assert(wisp:GetItemInSlot(0) == stashedWand, "unequip returns the same entity to the wisp stash")
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
local entities = {
	[501] = fieldedHero,
	[502] = wisp,
	[equippedBlink:GetEntityIndex()] = equippedBlink,
	[groundWand:GetEntityIndex()] = groundDrop,
}
EntIndexToHScript = function(index) return entities[index] end
equipmentGame.placedPositions = {}
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
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(), entindex_target = 2,
}), "prepare order filter must allow moving a held item only to a valid own inventory slot")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_ITEM,
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(), entindex_target = 6,
}), "prepare order filter must reject moving a hero item to an out-of-range slot")
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
	validate_prepare_order = function(filterTable) return equipmentGame:ValidatePrepareOrder(filterTable) end,
})
entities[502] = wisp
entities[stashedWand:GetEntityIndex()] = stashedWand
assert(nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 502 }, entindex_ability = stashedWand:GetEntityIndex(),
}), "OrderFilter must allow a wisp to drop its own item during prepare")
activePhase = "FIGHT"
assert(not nativeFilter:Filter({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_DROP_ITEM,
	units = { ["0"] = 502 }, entindex_ability = stashedWand:GetEntityIndex(),
}), "OrderFilter must block wisp inventory orders during battle")

-- 实体被同名物品替换时，签名也必须变化，才能把新 item_index 推给 Panorama。
activePhase = "PREPARE"
local snapshotBeforeReplacement = equipmentGame:BuildEquipmentSnapshot()
wisp:RemoveItem(stashedWand)
local replacementWand = makeItem("item_magic_wand")
wisp:AddItem(replacementWand)
assert(snapshotBeforeReplacement ~= equipmentGame:BuildEquipmentSnapshot(),
	"equipment snapshot must include entity IDs, not only item names and slots")

print("PASS: initial hero shop rolls five unique offers and broadcasts before setup UI; direct equipment, wisp transfer, native pickup sync, and prep item orders work")
