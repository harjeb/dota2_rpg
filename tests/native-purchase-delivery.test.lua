-- 已付款的购买必须最终落到目标英雄手上：目标满格时保留订单继续重试；配件齐全时
-- 用“合成辅助交付”让原版在目标身上完成合成，而不是把散件永久留在别的载体上。
-- 复用 shop-state 的原版 API 替身与 addon 加载器，并在其上覆盖配方 KV 与合成引擎。
dofile((TEST_REPO_ROOT or ".") .. "/tests/shop-state.test.lua")

-- 原版 items.txt / npc_items_custom.txt 的替身：两件套（无卷轴）与三件套（含卷轴）。
LoadKeyValues = function(path)
	if path == "scripts/npc/items.txt" then
		return { DOTAAbilities = {
			item_recipe_focus = { ItemRecipe = "1", ItemCost = "0", ItemResult = "item_focus",
				ItemRequirements = { ["01"] = "item_alpha;item_beta" } },
			item_recipe_heavy = { ItemRecipe = "1", ItemCost = "400", ItemResult = "item_heavy",
				ItemRequirements = { ["01"] = "item_focus;item_gamma" } },
			item_recipe_ghost = { ItemRecipe = "1", ItemCost = "0", ItemResult = "item_ghost",
				ItemRequirements = { ["01"] = "item_alpha;item_beta" } },
		} }
	end
	if path == "scripts/npc/npc_items_custom.txt" then
		return { DOTAAbilities = {} }
	end
	error("unexpected KV " .. path)
end

-- 原版引擎的合成替身：主物品栏 0..5 同时凑齐配方即消费配件并生成结果。
local combineRules = {
	{ result = "item_focus", parts = { item_alpha = 1, item_beta = 1 } },
	{ result = "item_heavy", parts = { item_focus = 1, item_gamma = 1, item_recipe_heavy = 1 } },
}

local nextEntityId = 80000
local function makeItem(name)
	nextEntityId = nextEntityId + 1
	local item = { name = name, entityIndex = nextEntityId, removed = false }
	function item:IsNull() return self.removed == true end
	function item:GetAbilityName() return self.name end
	function item:GetEntityIndex() return self.entityIndex end
	function item:GetCurrentCharges() return self.charges end
	function item:SetCurrentCharges(charges) self.charges = charges end
	return item
end

local function makeUnit(name, lastSlot)
	local unit = { name = name, slots = {}, moves = 0, combines = 0, lastSlot = lastSlot or 8 }
	function unit:GetItemInSlot(slot) return self.slots[slot] end
	function unit:GetUnitName() return self.name end
	function unit:IsNull() return false end
	function unit:GetAbsOrigin() return { x = 0, y = 0, z = 0 } end
	function unit:TakeItem(item)
		self.moves = self.moves + 1
		for slot, value in pairs(self.slots) do
			if value == item then
				self.slots[slot] = nil
				item.holder = nil
			end
		end
	end
	function unit:RemoveItem(item)
		self:TakeItem(item)
		item.removed = true
	end
	function unit:SwapItems(firstSlot, secondSlot)
		self.slots[firstSlot], self.slots[secondSlot] = self.slots[secondSlot], self.slots[firstSlot]
	end
	-- 原版 AddItem：先填主物品栏 0..5，再填背包/储藏栏，随后按配方自动合成。
	function unit:AddItem(item)
		if self.rejectAdd or item == nil or item:IsNull() then
			return nil
		end
		local placed = nil
		for slot = 0, self.lastSlot do
			if self.slots[slot] == nil then
				placed = slot
				break
			end
		end
		if placed == nil then
			return nil
		end
		self.slots[placed] = item
		item.holder = self
		self:Combine()
		if self.slots[placed] == item then
			return item
		end
		return nil
	end
	function unit:Combine()
		local progress = true
		while progress do
			progress = false
			for _, recipe in ipairs(combineRules) do
				local needed, found = {}, {}
				for part, count in pairs(recipe.parts) do needed[part] = count end
				for slot = 0, 5 do
					local held = self.slots[slot]
					local heldName = held ~= nil and not held:IsNull() and held:GetAbilityName() or nil
					if heldName ~= nil and (needed[heldName] or 0) > 0 then
						needed[heldName] = needed[heldName] - 1
						table.insert(found, slot)
					end
				end
				local complete = #found > 1
				for _, count in pairs(needed) do
					if count > 0 then complete = false end
				end
				if complete then
					local result = makeItem(recipe.result)
					for _, slot in ipairs(found) do
						local consumed = self.slots[slot]
						self.slots[slot] = nil
						if consumed.holder == self then consumed.holder = nil end
						consumed.removed = true
					end
					for slot = 0, 5 do
						if self.slots[slot] == nil then
							self.slots[slot] = result
							result.holder = self
							break
						end
					end
					self.combines = self.combines + 1
					progress = true
				end
			end
		end
	end
	return unit
end
local function place(unit, slot, name)
	local item = makeItem(name)
	unit.slots[slot] = item
	item.holder = unit
	return item
end

local function countHeld(unit, firstSlot, lastSlot)
	local total = 0
	for slot = firstSlot, lastSlot do
		if unit:GetItemInSlot(slot) ~= nil then
			total = total + 1
		end
	end
	return total
end

local function countLiveItems(units)
	local total = 0
	for _, unit in ipairs(units) do
		for slot = 0, unit.lastSlot do
			local item = unit:GetItemInSlot(slot)
			if item ~= nil and not item:IsNull() then
				total = total + 1
			end
		end
	end
	return total
end

local function heldName(unit, name)
	for slot = 0, unit.lastSlot do
		local item = unit:GetItemInSlot(slot)
		if item ~= nil and not item:IsNull() and item:GetAbilityName() == name then
			return item, slot
		end
	end
	return nil, nil
end

local function game()
	local wisp = makeUnit("npc_dota_hero_wisp", 14)
	local axe = makeUnit("npc_dota_hero_axe", 8)
	local lion = makeUnit("npc_dota_hero_lion", 8)
	axe.lineupHeroName = "npc_dota_hero_axe"
	lion.benchHeroName = "npc_dota_hero_lion"
	local g = setmetatable({
		phase = "setup", playerId = 0, gold = 10000,
		placeholderHero = wisp,
		lineup = { "npc_dota_hero_axe" },
		heroData = { npc_dota_hero_axe = { inventory = {} }, npc_dota_hero_lion = { inventory = {} } },
		battleManager = { teamHeroes = { [DOTA_TEAM_GOODGUYS] = { axe }, [DOTA_TEAM_BADGUYS] = {} } },
		benchUnits = { lion },
		pendingNativePurchases = {}, nativePurchaseOrderContexts = {}, nativePurchaseClaimedIds = {},
		nativePurchaseObservedStates = {}, nativePurchaseSwapReturns = {}, nativePurchaseTick = 0,
		GetStashUnit = function() return wisp end,
		GetGoldBalance = function(self) return self.gold end,
		SetGoldBalance = function(self, value) self.gold = value return value end,
		LogNativePurchase = function() end,
		SyncHeroInventoryFromUnit = function() end,
		SyncLiveEquipmentState = function() end,
		BroadcastShopState = function() end,
	}, CDota2RpgDemo)
	return g, wisp, axe
end

-- 订单先建立（before_ids 记录此刻库存），物品稍后才由原版交付到小精灵。
local function order(g, name, recipientKey, cost)
	local context = {
		item_name = name, item_cost = cost or 100, recipient_key = recipientKey or "npc_dota_hero_axe",
		issuer = 0, before_ids = g:CollectManagedItemIds(), gold_before = g.gold,
		created_at = 1, created_tick = 1,
	}
	table.insert(g.pendingNativePurchases, context)
	return context
end

-- 目标满格：主物品栏 6 格 + 背包 3 格全部占满。
local function makeFullHeroExtra()
	local extra = {}
	for index = 1, 5 do extra[index] = "item_unrelated_" .. index end
	for index = 1, 3 do extra[5 + index] = "item_backpack_" .. index end
	return extra
end


-- 1) 目标满格时订单保留并重试；腾出格子后交付同一个实体，且只扣一次钱。
do
	local g, wisp, axe = game()
	axe.rejectAdd = true
	local purchase = order(g, "item_delta", "npc_dota_hero_axe", 100)
	local item = makeItem("item_delta")
	wisp:AddItem(item)
	g:ReconcileNativePurchaseOrders()
	assert(g.gold == 9900, "a retained purchase is still charged exactly once")
	assert(purchase.awaiting_delivery == true, "an undeliverable paid purchase stays pending")
	assert(purchase.transfer_decision == "attachment-failed-preserved", "the failed attempt is reported honestly")
	assert(g.pendingNativePurchases[1] == purchase, "the order is retained for retry")
	assert(g:IsItemHeldBy(wisp, item, 0, 16), "the paid item stays with its source carrier")
	assert(not g:IsItemHeldBy(axe, item, 0, 16), "the target must not report a delivery it never received")
	g:ReconcileNativePurchaseOrders()
	assert(g.gold == 9900, "retries cannot charge twice")
	axe.rejectAdd = false
	g:ReconcileNativePurchaseOrders()
	assert(g:IsItemHeldBy(axe, item, 0, 8), "the exact paid entity arrives once the target has room")
	assert(#g.pendingNativePurchases == 0, "a resolved delivery leaves no pending order")
	assert(purchase.awaiting_delivery == nil, "resolution clears the awaiting state")
	assert(g.gold == 9900, "delivery retries never change the wallet")
end

-- 2) 目标满格但到货即可合成：临时腾格 → 交付 → 原版在目标身上合成 → 装备放回。
do
	local g, wisp, axe = game()
	local alpha = place(axe, 0, "item_alpha")
	for index, name in ipairs(makeFullHeroExtra()) do
		place(axe, index, name)
	end
	assert(countHeld(axe, 0, 8) == 9, "fixture starts with a completely full hero")
	local purchase = order(g, "item_beta", "npc_dota_hero_axe", 100)
	local beta = makeItem("item_beta")
	wisp:AddItem(beta)
	g:ReconcileNativePurchaseOrders()
	local focus = heldName(axe, "item_focus")
	assert(focus ~= nil, "the arriving part completes the recipe on the target hero")
	assert(not g:IsItemHeldBy(wisp, beta, 0, 16), "the purchased entity left the source carrier")
	assert(alpha.removed and beta.removed, "the recipe consumed the arriving part and its partner")
	assert(#g.pendingNativePurchases == 0 and purchase.awaiting_delivery == nil, "the purchase is resolved")
	assert(purchase.transfer_decision == "delivered-after-assist", "the resolved path is recorded")
	assert(#g.nativePurchaseSwapReturns == 0, "temporarily moved equipment returns immediately")
	assert(countHeld(axe, 0, 8) == 9, "the hero keeps every unrelated item after the combination")
	assert(heldName(axe, "item_unrelated_1") ~= nil, "the temporarily moved equipment is back on the hero")
end
-- 3) 没有配方证据时不得搬动玩家其他装备（避免每个 think 反复搬动的抖动）。
do
	local g, wisp, axe = game()
	axe.rejectAdd = true
	place(axe, 0, "item_unrelated_1")
	local moves = axe.moves
	local purchase = order(g, "item_zeta", "npc_dota_hero_axe", 100)
	local plain = makeItem("item_zeta")
	wisp:AddItem(plain)
	for _ = 1, 4 do g:ReconcileNativePurchaseOrders() end
	assert(purchase.awaiting_delivery == true, "a plain item stays pending while the hero is full")
	assert(axe.moves == moves, "unproven swaps never move unrelated equipment")
	assert(g:IsItemHeldBy(wisp, plain, 0, 16), "the paid item still waits with the source carrier")
	assert(g.gold == 9900 and #g.pendingNativePurchases == 1, "one charge, one pending order")
end

-- 4) 配件躺在背包里原版不会合成：腾出主物品栏格并完成合成。
do
	local g, wisp, axe = game()
	for index = 0, 4 do place(axe, index, "item_unrelated_" .. index) end
	local alpha = makeItem("item_alpha")
	axe.slots[6] = alpha
	alpha.holder = axe
	place(axe, 7, "item_backpack_1")
	assert(axe:GetItemInSlot(5) == nil and countHeld(axe, 0, 8) == 7, "fixture keeps one main slot free")
	local purchase = order(g, "item_beta", "npc_dota_hero_axe", 100)
	local beta = makeItem("item_beta")
	wisp:AddItem(beta)
	g:ReconcileNativePurchaseOrders()
	assert(heldName(axe, "item_focus") ~= nil, "the backpack part is promoted and combined on the hero")
	assert(alpha.removed and beta.removed, "the promoted part and the purchased part are consumed by the recipe")
	assert(#g.pendingNativePurchases == 0, "the purchase is resolved")
	assert(#g.nativePurchaseSwapReturns == 0, "temporarily moved equipment returns immediately")
	assert(g:IsItemHeldBy(wisp, axe:GetItemInSlot(0), 0, 16) == false, "fixture sanity: nothing stays with the source")
	assert(heldName(axe, "item_unrelated_0") ~= nil, "the temporarily moved equipment is back on the hero")
	assert(countHeld(axe, 0, 8) == 7, "no item is lost or duplicated by the assembly assist")
end

-- 5) 合成预测失败时必须整体回滚：购买的装备回到来源，临时装备回到英雄，绝不丢失。
do
	local g, wisp, axe = game()
	place(axe, 0, "item_alpha")
	for index, name in ipairs(makeFullHeroExtra()) do
		place(axe, index, name)
	end
	local purchase = order(g, "item_beta", "npc_dota_hero_axe", 100)
	local beta = makeItem("item_beta")
	wisp:AddItem(beta)
	local before = countLiveItems({ wisp, axe })
	-- 配方数据仍在，但原版引擎在本场景不会真的合成。
	local saved = combineRules
	combineRules = {}
	g:ReconcileNativePurchaseOrders()
	g:ReconcileNativePurchaseOrders()
	combineRules = saved
	assert(countLiveItems({ wisp, axe }) == before, "a failed combination attempt never loses an item")
	assert(#g.nativePurchaseSwapReturns == 0, "temporarily moved equipment returns to the hero")
	assert(g:IsItemHeldBy(wisp, beta, 0, 16), "the purchased entity is back with the source carrier")
	assert(heldName(axe, "item_unrelated_1") ~= nil, "the temporarily moved equipment is back on the hero")
	assert(purchase.awaiting_delivery == true, "the undeliverable purchase stays tracked for retry")
	assert(g.pendingNativePurchases[1] == purchase, "the retained order keeps retrying")
end

print("native-purchase-delivery tests passed")


