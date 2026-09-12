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

local walletLogs = {}
local failWalletLog = false
local moduleRoot = repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
require = function(name)
    if name == "battle.run_results" then return {StartBattle=function() end, RecordBattle=function() end, Finish=function() end, SendTerminal=function() end, Resend=function() end, Invalidate=function() end, Reset=function() end} end
	if name == "battle.skill_debug" then return { Install = function() end } end
	if name == "issue_fixes.runtime_log" then
		return { Write = function(message)
			if failWalletLog then error("test logger unavailable") end
			walletLogs[#walletLogs + 1] = message
		end }
	end
	local localModules = {
		["tactics/ability_catalog"] = moduleRoot .. "tactics/ability_catalog.lua",
		["tactics/rule_snapshot"] = moduleRoot .. "tactics/rule_snapshot.lua",
		["battle.enemy_scaling"] = moduleRoot .. "battle/enemy_scaling.lua",
		["battle.stage_precache"] = moduleRoot .. "battle/stage_precache.lua",
        ["battle.campaign_loot"] = moduleRoot .. "battle/campaign_loot.lua",
        ["data.campaign_loot_catalog"] = moduleRoot .. "data/campaign_loot_catalog.lua",
		["battle.boss_scaling"] = moduleRoot .. "battle/boss_scaling.lua",
		["battle.run_lives"] = moduleRoot .. "battle/run_lives.lua",
		["battle.respawn_policy"] = moduleRoot .. "battle/respawn_policy.lua",
		["battle/summon_behavior"] = moduleRoot .. "battle/summon_behavior.lua",
		["issue_fixes/tiny_tree"] = moduleRoot .. "issue_fixes/tiny_tree.lua",
        ["issue_fixes/gris_gris"] = moduleRoot .. "issue_fixes/gris_gris.lua",
        ["issue_fixes/jinada_income"] = moduleRoot .. "issue_fixes/jinada_income.lua",
        ["issue_fixes/shard_purchase"] = moduleRoot .. "issue_fixes/shard_purchase.lua",
        ["issue_fixes/item_sales"] = moduleRoot .. "issue_fixes/item_sales.lua",
		["issue_fixes/hero_precache"] = moduleRoot .. "issue_fixes/hero_precache.lua",
		["tactics/special_targets"] = moduleRoot .. "tactics/special_targets.lua",
		["battle.tempest_double"] = moduleRoot .. "battle/tempest_double.lua",
		["issue_fixes/hero_ability_policy"] = moduleRoot .. "issue_fixes/hero_ability_policy.lua",
		["battle.damage_stats"] = moduleRoot .. "battle/damage_stats.lua",
		["battle.enemy_diagnostics"] = moduleRoot .. "battle/enemy_diagnostics.lua",
		["data.progression_data"] = moduleRoot .. "data/progression_data.lua",
		["patches.recruitment_patch"] = moduleRoot .. "patches/recruitment_patch.lua",
		["patches.progression_patch"] = moduleRoot .. "patches/progression_patch.lua",
		["patches.enemy_items_patch"] = moduleRoot .. "patches/enemy_items_patch.lua",
		["battle.hero_model_precache"] = moduleRoot .. "battle/hero_model_precache.lua",
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

-- Initialization must survive pre-connect reads and retry unavailable wallets.
do
	local previousResource = PlayerResource
	local nativeGold, writes = 0, 0
	local resource = {
		GetGold = function() return nativeGold end,
		SetGold = function(_, _, amount, reliable)
			writes = writes + 1
			if reliable then nativeGold = amount end
		end,
	}
	PlayerResource = resource
	local wallet = newGame({ playerId = 0, initialGold = 725, gold = 725, goldWalletInitialized = false })
	assertEqual(wallet:GetGoldBalance(), 0, "pre-connect read sees native zero")
	assertEqual(wallet.initialGold, 725, "read preserves configured startup entitlement")
	assertEqual(wallet:EnsureGoldWalletInitialized(), 725, "initialization seeds immutable startup amount")
	assertEqual(writes, 2, "startup writes reliable and clears unreliable once")
	assertEqual(wallet.goldWalletInitialized, true, "successful seed initializes wallet")
	nativeGold = 0
	assertEqual(wallet:EnsureGoldWalletInitialized(), 0, "repeated initialization never refills spent wallet")
	assertEqual(writes, 2, "spent wallet does not trigger writes")
	for _, invalidId in ipairs({ -1, false }) do
		local retry = newGame({ initialGold = 500, gold = 500, goldWalletInitialized = false })
		if invalidId ~= false then retry.playerId = invalidId end
		retry:EnsureGoldWalletInitialized()
		assertEqual(retry.goldWalletInitialized, false, "invalid or missing pid remains pending")
		retry.playerId = 0
		nativeGold = 0
		assertEqual(retry:EnsureGoldWalletInitialized(), 500, "valid pid retries startup seeding")
	end
	local preserve = newGame({ playerId = 0, initialGold = 500, gold = 500 })
	nativeGold = 123
	local writesBefore = writes
	assertEqual(preserve:EnsureGoldWalletInitialized(), 123, "positive native balance is preserved")
	assertEqual(writes, writesBefore, "preserving native balance never writes")
	assertEqual(preserve.goldWalletInitialized, true, "positive native balance completes initialization")
	local retry = newGame({ playerId = 0, initialGold = 500, gold = 500, goldWalletInitialized = false })
	PlayerResource = nil
	retry:EnsureGoldWalletInitialized()
	assertEqual(retry.goldWalletInitialized, false, "missing native API remains pending")
	PlayerResource = { GetGold = resource.GetGold }
	nativeGold = 0
	retry:EnsureGoldWalletInitialized()
	assertEqual(retry.goldWalletInitialized, false, "missing setter remains pending")
	PlayerResource = resource
	failWalletLog = true
	assertEqual(retry:EnsureGoldWalletInitialized(), 500, "logger failure cannot prevent initialization")
	assertEqual(retry:SetGoldBalance(25), 25, "logger failure cannot prevent write")
	nativeGold = 10
	assertEqual(retry:GetGoldBalance(), 10, "logger failure cannot prevent native read")
	failWalletLog = false
	local logs = table.concat(walletLogs, "\n")
	assert(logs:find("action=read-change pid=0 before=725 after=0 initialized=false", 1, true), "read trace exposes pid and balances")
	assert(logs:find("action=write pid=0 before=0 after=725 initialized=true", 1, true), "write trace exposes initialized status")
	assert(logs:find("detail=deferred", 1, true), "deferred initialization is traced")
	assert(logs:find("detail=seed-startup", 1, true), "startup initialization is traced")
	assert(logs:find("detail=preserve-native", 1, true), "preserved initialization is traced")
	PlayerResource = previousResource
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
	local previousRules = GameRules
	GameRules = {GetGameTime = function() return 10 end}
	walletGame.battleManager = {OnThink = function() end}
	walletGame.tacticBridge = {OnThink = function() end}
	walletGame.BroadcastDamageStats = function() end
	walletGame.phase = "fight"
	walletGame.ReconcileNativePurchaseOrders = function() error("no shop reconciliation during combat") end
	nativeGold = nativeGold + 36 -- Simulated native Jinada credit, NOT proof of a proc.
	walletGame:OnThink()
	assertEqual(broadcasts, 3, "native combat income publishes before the next setup")
	assertEqual(walletGame.lastBroadcastGold, 936, "combat display receives native credit exactly once")
	walletGame:OnThink()
	assertEqual(broadcasts, 3, "unchanged combat balance cannot generate another reward or broadcast")
	nativeGold = nativeGold + 320 -- Simulated native Track credit.
	walletGame:OnThink()
	assertEqual(walletGame.lastBroadcastGold, 1256, "subsequent native combat income is retained")
	walletGame.phase = "result"
	nativeGold = nativeGold + 50
	walletGame:OnThink()
	assertEqual(walletGame.lastBroadcastGold, 1306, "late native payout remains visible during settlement")
	GameRules = previousRules
	PlayerResource = previousResource
end

-- Both native gold buckets survive reads and subsequent custom rewards/spending.
-- This verifies receipt only; the native ability must actually award the gold.
do
	local previousResource = PlayerResource
	local reliable, unreliable, writes = 500, 0, 0
	PlayerResource = {
		GetGold = function() return reliable + unreliable end,
		SetGold = function(_, pid, amount, isReliable)
			assertEqual(pid, 0, "wallet belongs to the RPG player")
			writes = writes + 1
			if isReliable then reliable = amount else unreliable = amount end
		end,
	}
	local wallet = newGame({playerId = 0, gold = 500, goldWalletInitialized = true})
	unreliable = 36
	assertEqual(wallet:GetGoldBalance(), 536, "native unreliable credit enters authoritative balance")
	reliable = reliable + 320
	assertEqual(wallet:GetGoldBalance(), 856, "native reliable credit also enters balance")
	assertEqual(writes, 0, "reading incoming native gold never overwrites the engine")
	assertEqual(wallet:AddGold(100), 956, "custom reward preserves both native incoming amounts")
	assert(wallet:SpendGold(50), "native earnings can be spent")
	assertEqual(wallet:GetGoldBalance(), 906, "spending cannot replay a native reward")
	assertEqual(unreliable, 0, "custom writes retain existing reliable-only wallet policy")
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

-- Native RNG must drive both hero selection and quality; a fresh Lua seed
-- cannot force the opening shop when the engine supplies a different stream.
local savedRandom = math.random
local nativeCalls = 0
math.random = function() error("shop must use the engine RNG when available") end
local function rollWithNativeEndpoint(high)
	RandomInt = function(minimum, maximum)
		assert(minimum == 1 and maximum >= minimum, "native random bounds")
		nativeCalls = nativeCalls + 1
		return high and maximum or minimum
	end
	math.randomseed(12345)
	game:RollShop()
	local selected = {}
	for _, offer in ipairs(game.shopOffers) do
		assert(not selected[offer.hero], "native draws must be unique")
		assert(offer.hero ~= "npc_dota_hero_axe", "owned heroes must be excluded")
		assertEqual(offer.level, 1, "opening recruit level preserved")
		-- 售价 = 等级基础价 × 品质倍率（普通 1.0 / 精良 1.2 / 史诗 1.5 / 传说 2.0）。
		local multipliers = { common = 1.0, fine = 1.2, epic = 1.5, legendary = 2.0 }
		local expected = 500 * (multipliers[offer.quality] or 1.0)
		assertEqual(offer.price, math.floor(expected + 0.5),
			"opening recruit price must include the quality multiplier")
		assert(offer.quality == "common" or offer.price > 500,
			"a non-common opening offer must cost more than the common base price")
		selected[offer.hero] = true
	end
	assertEqual(#game.shopOffers, 5, "native shop fills all five offers")
	return game.shopOfferText
end
game.ownedHeroes = { "npc_dota_hero_axe" }
local firstNativeShop = rollWithNativeEndpoint(false)
local secondNativeShop = rollWithNativeEndpoint(true)
assert(firstNativeShop ~= secondNativeShop, "native entropy changes the opening shop despite identical Lua seeds")
assert(nativeCalls >= 20, "both draws and five quality rolls use native RNG")
math.random, RandomInt = savedRandom, nil
game.ownedHeroes = {}

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
		IsNull = function(self) return self.removed == true end,
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
		if self.rejectAdd or item:IsNull() then
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
	function unit:TakeItem(item)
		for slot = 0, self.maxSlot do
			if self.slots[slot] == item then
				self.slots[slot] = nil
				item.holder = nil
				return item
			end
		end
	end
	-- Native RemoveItem deletes the entity; only TakeItem supports transfers.
	function unit:RemoveItem(item)
		self:TakeItem(item)
		item.removed = true
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
	-- Live report: three 140-gold purchases for a bench hero must retain all
	-- three original entities, including when the hero is subsequently fielded.
	resetTracePurchase()
	equipmentGame:SetGoldBalance(500)
	local purchased = {}
	for index = 1, 3 do
		assert(equipmentGame:SetNativePurchaseSelection(benchHero))
		assert(equipmentGame:ValidatePrepareOrder({ issuer_player_id_const = 0,
			order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, units = {},
			itemname = "item_gauntlets", item_cost = 140 }))
		local item = wisp:AddItem(makeItem("item_gauntlets"))
		purchased[index] = item
		equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_gauntlets" })
		equipmentGame:RoutePendingNativePurchases()
		assertEqual(equipmentGame:GetGoldBalance(), 500 - index * 140, "each gauntlet costs exactly 140")
		assert(not item:IsNull() and equipmentGame:IsItemHeldBy(benchHero, item, 0, 8),
			"paid gauntlet must reach the bench hero as the original live entity")
	end
	equipmentGame:CaptureHeroInventoryForRespawn(benchHero)
	local replacement = makeInventoryUnit(benchHero.name, DOTA_TEAM_GOODGUYS, 14)
	equipmentGame:RestoreHeroInventoryToUnit(benchHero.name, replacement)
	for _, item in ipairs(purchased) do
		assert(not item:IsNull() and equipmentGame:IsItemHeldBy(replacement, item, 0, 8),
			"fielding must preserve each purchased entity without recreating it")
		replacement:RemoveItem(item)
	end
	equipmentGame:SyncHeroInventoryFromUnit(benchHero)

	resetTracePurchase()
	order("item_attachment_rejected", benchHero)
	local rejectedItem = wisp:AddItem(makeItem("item_attachment_rejected"))
	equipmentGame:OnNativeItemPurchased({ PlayerID = 0, itemname = "item_attachment_rejected" })
	local rejectedPurchase = equipmentGame.pendingNativePurchases[1]
	benchHero.rejectAdd = true
	equipmentGame:RoutePendingNativePurchases()
	benchHero.rejectAdd = false
	assert(not rejectedItem:IsNull() and equipmentGame:IsItemHeldBy(wisp, rejectedItem, 0, 14),
		"rejected attachment must preserve the paid original item on the source")
	assertEqual(rejectedPurchase.transfer_decision, "attachment-failed-preserved",
		"rejected attachment must not report a resolved transfer")
	assertEqual(equipmentGame.nativePurchaseClaimedIds[tostring(rejectedItem:GetEntityIndex())], nil,
		"rejected attachment must not claim the item for the recipient")
	wisp:RemoveItem(rejectedItem)

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
-- 低级卷轴 200 金（DESIGN.md §2.5）；扣款必须和原版商店共用同一钱包。
assertEqual(equipmentGame:GetScrollRemaining("low"), 2, "low scroll limit is 2 per stage")
assertEqual(equipmentGame:GetScrollRemaining("high"), 1, "high scroll limit is 1 per stage")
equipmentGame:OnScrollBuy(nil, { kind = "low" })
assertEqual(nativeWalletGold(0), 550, "scroll purchase must debit the same wallet as the native shop")
assertEqual(equipmentGame.scrollStock.low, 1, "scroll panel must retain the two-scroll stock flow")
-- 低级卷轴每关只能买 2 个：第二次成功，第三次被限购拒绝且不再扣款。
equipmentGame:OnScrollBuy(nil, { kind = "low" })
assertEqual(nativeWalletGold(0), 350, "second low scroll debits again")
assertEqual(equipmentGame:GetScrollRemaining("low"), 0, "low scrolls exhausted after two buys")
equipmentGame:OnScrollBuy(nil, { kind = "low" })
assertEqual(nativeWalletGold(0), 350, "third low scroll is rejected without charging")
assertEqual(equipmentGame.scrollStock.low, 2, "third low scroll never enters stock")
-- 高级卷轴每关只能买 1 个。
nativeWalletReliable[0] = 5000
equipmentGame:OnScrollBuy(nil, { kind = "high" })
assertEqual(nativeWalletGold(0), 4000, "high scroll costs 1000")
assertEqual(equipmentGame:GetScrollRemaining("high"), 0, "high scrolls exhausted after one buy")
assertEqual(equipmentGame.scrollStock.high, 1, "high scroll stock grew once")
equipmentGame:OnScrollBuy(nil, { kind = "high" })
assertEqual(nativeWalletGold(0), 4000, "second high scroll is rejected without charging")
assertEqual(equipmentGame.scrollStock.high, 1, "second high scroll never enters stock")
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
function fieldedHero:GetEntityIndex() return 501 end
function wisp:GetEntityIndex() return 502 end

-- 原版商店的购买点击资格取决于客户端是否把选中单位当作"玩家自己的英雄"。
-- 项目生成的英雄不经过引擎选人流程，不同步的话选中它们时点击购买不会产生任何订单
-- （用户反馈：点了完全没反应）。这里锁定 小精灵 <-> 当前载体 的同步契约。
function benchHero:GetEntityIndex() return 503 end
local nativeSelectedHero = nil
local selectedHeroCalls = {}
PlayerResource.SetSelectedHero = function(_, playerId, heroName)
	selectedHeroCalls[#selectedHeroCalls + 1] = { playerId = playerId, name = heroName }
	nativeSelectedHero = { GetUnitName = function() return heroName end }
end
PlayerResource.GetSelectedHeroEntity = function() return nativeSelectedHero end
assert(equipmentGame:SyncNativePlayerHero(fieldedHero),
	"selecting a roster hero must publish it as the player's own native hero")
assertEqual(selectedHeroCalls[#selectedHeroCalls].name, "npc_dota_hero_axe",
	"the native shop must follow the selected roster hero")
assertEqual(selectedHeroCalls[#selectedHeroCalls].playerId, 0, "native hero sync must use the authoritative player id")
assert(equipmentGame:SyncNativePlayerHero(fieldedHero) and #selectedHeroCalls == 1,
	"re-selecting the same entity must not repeat the native call")
assert(equipmentGame:EnsureNativePlayerHero(), "a live selection must survive the per-tick upkeep check")
equipmentGame:SetNativePurchaseSelection(benchHero)
assertEqual(equipmentGame.nativePurchaseSelectionHero, "npc_dota_hero_lion",
	"purchase selection still tracks the delivery recipient")
assertEqual(selectedHeroCalls[#selectedHeroCalls].name, "npc_dota_hero_lion",
	"purchase target selection must also sync the native shop hero")
-- 阵容重建会销毁旧实体；此时必须退回玩家小精灵，而不是留下失效句柄。
entities[503] = nil
assert(equipmentGame:EnsureNativePlayerHero(), "destroyed roster entities must fall back to the commander")
assertEqual(selectedHeroCalls[#selectedHeroCalls].name, "npc_dota_hero_wisp",
	"the fallback native hero must be the player's commander")
assert(not equipmentGame:SyncNativePlayerHero(nil),
	"an invalid carrier must never be published as the player's hero")
assert(equipmentGame:EnsureNativePlayerHero(), "missing carriers must not wedge the upkeep fallback")
-- 恢复实体映射，后续既有的原版购买用例仍依赖 503 指向待命英雄。
entities[503] = benchHero
-- 选中小精灵只是为了能点开原版商店，不能把已选定的英雄交付目标清掉，
-- 否则用户依然要"先买给小精灵再手动转交"。
assert(equipmentGame:SetNativePurchaseSelection(wisp), "the commander must remain a valid shop carrier")
assertEqual(equipmentGame.nativePurchaseSelectionHero, "npc_dota_hero_lion",
	"selecting the commander must not clear the chosen hero delivery target")
assertEqual(selectedHeroCalls[#selectedHeroCalls].name, "npc_dota_hero_wisp",
	"the commander selection still has to publish the native shop hero")
-- 没有存活英雄目标时才回落到指挥官。
local savedBench, savedTeamHeroes = equipmentGame.benchUnits,
	equipmentGame.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS]
equipmentGame.benchUnits = {}
equipmentGame.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] = {}
assert(equipmentGame:SetNativePurchaseSelection(wisp), "commander shopping must survive an empty roster")
assertEqual(equipmentGame.nativePurchaseSelectionHero, "__wisp",
	"an empty roster must fall back to the commander as the delivery target")
equipmentGame.benchUnits = savedBench
equipmentGame.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] = savedTeamHeroes
assert(equipmentGame:SetNativePurchaseSelection(benchHero),
	"hero delivery target must be selectable again after the roster returns")
assertEqual(equipmentGame.nativePurchaseSelectionHero, "npc_dota_hero_lion",
	"a roster hero selection must always win over the commander fallback")
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
local saleOrder = {
    issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_SELL_ITEM,
    units = {}, entindex_ability = equippedBlink:GetEntityIndex(),
}
equipmentGame.nativePurchaseOrderContexts = {{gold_before=1000}}
assert(not equipmentGame:ValidatePrepareOrder(saleOrder), "refund cannot hide an unconfirmed purchase debit")
equipmentGame.nativePurchaseOrderContexts = {}
equipmentGame.pendingNativePurchases = {}
assert(equipmentGame:ValidatePrepareOrder(saleOrder), "prepare order filter must allow selling an item held by a managed hero")
assert(saleOrder.units["0"] == fieldedHero:GetEntityIndex(), "unitless native sale receives the actual holder, not merely validation")
for _, sourceId in ipairs({502, 501}) do
    local rightClick = {issuer_player_id_const=0, order_type=DOTA_UNIT_ORDER_SELL_ITEM,
        units={["0"]=sourceId}, entindex_ability=equippedBlink:GetEntityIndex()}
    assert(equipmentGame:ValidatePrepareOrder(rightClick), "right-click sale accepts assigned hero or actual holder")
    assert(rightClick.units["0"]==501, "right-click sale executes on exact item's actual holder")
    rightClick.issuer_player_id_const=1
    assert(not equipmentGame:ValidatePrepareOrder(rightClick), "foreign player cannot reroute sale")
    rightClick.issuer_player_id_const=0
    equipmentGame.phase="fight"
    assert(not equipmentGame:ValidatePrepareOrder(rightClick), "right-click sale remains blocked during combat")
    equipmentGame.phase="setup"
end
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
assert(equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_ITEM,
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(), entindex_target = 16,
}), "prepare order filter must allow moving into the dedicated neutral slot 16")
assert(not equipmentGame:ValidatePrepareOrder({
	issuer_player_id_const = 0, order_type = DOTA_UNIT_ORDER_MOVE_ITEM,
	units = { ["0"] = 501 }, entindex_ability = equippedBlink:GetEntityIndex(), entindex_target = 17,
}), "prepare order filter must reject moving a hero item beyond the carrier slots")
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
assertEqual(shopPayload.rule_generation, 0, "shop generation defaults to zero")
assertEqual(shopPayload.hero_entity_indices.npc_dota_hero_axe, 501, "active native selection ID")
assertEqual(shopPayload.hero_entity_indices.npc_dota_hero_lion, 503, "bench native selection ID")
function benchHero:GetEntityIndex() return 603 end
broadcastGame.ruleGeneration = 9
broadcastGame:BroadcastShopState()
assertEqual(shopPayload.rule_generation, 9, "shop publishes current generation")
assertEqual(shopPayload.hero_entity_indices.npc_dota_hero_lion, 603, "respawn refreshes native selection ID")
broadcastGame.ownedHeroes, broadcastGame.lineup = {}, {}
broadcastGame.battleManager = {
	GetAliveCount = function() return 0 end,
	GetBattleTime = function() return 0 end,
}
for _, generation in ipairs({0, 9}) do
	if generation == 0 then broadcastGame.ruleGeneration = nil else broadcastGame.ruleGeneration = generation end
	broadcastGame:BroadcastShopState()
	assertEqual(shopPayload.rule_generation, generation, "empty lineup shop generation")
	assertEqual(shopPayload.lineup_text, "", "empty lineup shop snapshot")
	assertEqual(next(shopPayload.hero_entity_indices), nil, "empty roster has no stale selection IDs")
	local battle = broadcastGame:BuildBattleState()
	assertEqual(battle.rule_generation, generation, "empty lineup battle generation")
	assertEqual(battle.radiant_alive, 0, "empty lineup battle snapshot")
end
CustomGameEventManager = priorEvents

-- Life rewards use the real storage helpers and retain native item entities.
do
    local Lives = dofile(moduleRoot .. "battle/run_lives.lua")
    local previousCreate, previousDrop = CreateItem, CreateItemOnPositionSync
    ITEM_FULLY_SHAREABLE = 0
    local function rewards(full)
        local stash = makeInventoryUnit("npc_dota_hero_wisp", 2, 14)
        local recipient = makeInventoryUnit("npc_dota_hero_dawnbreaker", 2, 14)
        local created, dropped = {}, {}
        local rejectDrop = full
        if full then
            for slot = 0, 14 do stash.slots[slot] = makeItem("item_branches") end
        end
        CreateItem = function(name)
            local item = makeItem(name)
            function item:SetDroppable(value) self.droppable = value end
            function item:SetShareability(value) self.shareability = value end
            function item:SetPurchaser(value) self.purchaser = value end
            created[#created + 1] = item
            return item
        end
        CreateItemOnPositionSync = function(_, item)
            if rejectDrop then return nil end
            dropped[#dropped + 1] = item
            return { item = item }
        end
        local game = newGame({
            gold = 0, GetStashUnit = function() return stash end,
            AddGold = function(self, amount) self.gold = self.gold + amount end,
        })
        assertEqual(Lives.Ensure(game).remaining, 5, "new run has five lives")
        for left = 4, 1, -1 do
            Lives.Lose(game)
            assertEqual(game.runLives.remaining, left, "one lost battle per life")
            assertEqual(game.gold, left <= 3 and 2000 or 0, "third-life gold credited once")
        end
        assertEqual(#game.runLives.pendingItems, 2, "last life earns two native items")
        local delivered = Lives.FlushItems(game)
        assertEqual(#created, 2, "one entity created per reward")
        if full then
            assertEqual(delivered, 0, "failed inventory and ground delivery remains pending")
            assertEqual(Lives.FlushItems(game), 0, "retry can remain blocked")
            assertEqual(#created, 2, "blocked retries reuse both entities")
            rejectDrop = false
            assertEqual(Lives.FlushItems(game), 2, "full inventory falls back to ground")
            assertEqual(#dropped, 2, "both ground rewards retained")
            assertEqual(dropped[1], created[1], "ground Aegis is original entity")
            for slot = 0, 14 do assertEqual(stash.slots[slot].name, "item_branches", "existing inventory preserved") end
        else
            assertEqual(delivered, 2, "both rewards placed in shared storage")
            local aegis = game:TakeStashItem("item_aegis", game:GetItemEntityId(created[1]))
            assertEqual(aegis, created[1], "transfer selects original Aegis")
            assert(game:TryAttachItem(recipient, aegis), "native Aegis transferred to hero")
            recipient:TakeItem(aegis)
            assert(game:PutItemInStash(aegis), "same Aegis can be returned to shared storage")
        end
        assertEqual(created[1].name, "item_aegis", "native Aegis reward")
        assertEqual(created[2].name, "item_cheese", "native Cheese reward")
        for _, item in ipairs(created) do
            assertEqual(item.droppable, true, "reward can be dropped")
            assertEqual(item.shareability, ITEM_FULLY_SHAREABLE, "reward can be shared")
            assertEqual(item.purchaser, nil, "reward is not purchaser-bound")
        end
        Lives.Lose(game); Lives.Lose(game)
        assertEqual(game.runLives.remaining, 0, "lives cannot fall below zero")
        assertEqual(game.gold, 2000, "no duplicate gold on exhausted run")
        assertEqual(Lives.FlushItems(game), 0, "delivered rewards do not repeat")
        assertEqual(#created, 2, "no duplicate native items")
    end
    rewards(false)
    rewards(true)
    CreateItem, CreateItemOnPositionSync = previousCreate, previousDrop
end

-- Exercise the actual panel handler, native wallet and inventory synchronization.
do
    local previousEvents, previousGetPlayer = CustomGameEventManager, PlayerResource.GetPlayer
    local player, replies = {}, {}
    PlayerResource.GetPlayer = function() return player end
    CustomGameEventManager = {Send_ServerToPlayer=function(_, recipient, event, payload)
        assert(recipient==player and event=="rpg_item_sell_result")
        replies[#replies+1]=payload
    end}
    equipmentGame.phase="setup"
    equipmentGame.nativePurchaseOrderContexts, equipmentGame.pendingNativePurchases = {}, {}
    equipmentGame:SetGoldBalance(1000)
    local sold = makeItem("item_belt_of_strength")
    function sold:IsSellable() return true end
    entities[sold:GetEntityIndex()] = sold
    fieldedHero.slots[14] = sold
    local nativeSales = 0
    function fieldedHero:SellItem(item)
        nativeSales = nativeSales + 1
        self:RemoveItem(item)
        nativeWalletReliable[0] = nativeWalletReliable[0] + 225
    end
    local broadcasts = equipmentGame.shopBroadcasts or 0
    local payload = {hero="npc_dota_hero_axe",item=sold.name,item_index=sold:GetEntityIndex(),request_id=71}
    equipmentGame:OnItemSell(nil,payload)
    assert(nativeSales==0 and #replies==0,"missing engine player identity cannot sell")
    payload.PlayerID=0
    equipmentGame:OnItemSell(nil,payload)
    assert(nativeSales==1 and sold:IsNull() and fieldedHero.slots[14]==nil,"real handler removes the exact native item")
    assertEqual(equipmentGame:GetGoldBalance(),1225,"native sale credits shared authoritative wallet once")
    assert((equipmentGame.shopBroadcasts or 0)>broadcasts and replies[1].ok==1 and replies[1].refund==225
        and replies[1].request_id==71,"inventory broadcast and correlated sale result reach the client")
    equipmentGame:OnItemSell(nil,payload)
    assert(nativeSales==1 and replies[2].ok==0 and equipmentGame:GetGoldBalance()==1225,"replayed request cannot refund twice")
    CustomGameEventManager, PlayerResource.GetPlayer = previousEvents, previousGetPlayer
end

print("PASS: initial hero shop, native inventory transfers, five lives, native equipment sales and exactly-once transferable life rewards")
