local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Sales = dofile(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/item_sales.lua")
local entities, balance, nativeCalls, nextId = {}, 1000, 0, 100
function EntIndexToHScript(id) return entities[id] end
local function carrier(name)
    local unit = {name=name, slots={}}
    function unit:SellItem(item)
        nativeCalls = nativeCalls + 1
        if self.reenter then self.reenter() end
        if self.fail == "error" then error("native rejected") end
        if self.fail == "noop" then return end
        for slot, value in pairs(self.slots) do if value == item then self.slots[slot] = nil end end
        item.null = true
        balance = balance + item.nativeRefund
    end
    return unit
end
local active, bench, stash, enemy = carrier("active"), carrier("bench"), carrier("__stash"), carrier("enemy")
local game = {playerId=0, phase="setup"}
function game:GetStashUnit() return stash end
function game:FindOwnedHeroUnit(name) return name == "active" and active or name == "bench" and bench or nil end
function game:IsLiveItem(item) return item ~= nil and item.kind == "item" and not item.null end
function game:IsEquipmentCarrier(unit) return unit == active or unit == bench or unit == stash end
function game:IsItemHeldBy(unit, item, first, last)
    for slot=first,last do if unit.slots[slot] == item then return true end end
    return false
end
function game:BindEquipmentCarrierToPlayer(unit) return unit.bind ~= false end
function game:GetGoldBalance() return balance end
function game:AddGold() error("Lua must not credit an extra refund") end
local function itemFor(unit, slot, refund)
    nextId = nextId + 1
    local item = {kind="item", name="item_belt_of_strength", id=nextId, nativeRefund=refund or 225, sellable=true}
    function item:GetAbilityName() return self.name end
    function item:IsSellable() return self.sellable end
    function item:GetCost() error("do not replace native selling with cost / 2") end
    entities[nextId], unit.slots[slot] = item, item
    return item, {PlayerID=0,hero=unit.name,item=item.name,item_index=nextId}
end
local function rejected(payload, reason)
    local before, calls = balance, nativeCalls
    local ok, actual, refund = Sales.Sell(game,payload)
    assert(not ok and actual == reason and refund == 0, tostring(actual).." expected "..reason)
    assert(balance == before and nativeCalls == calls, "invalid request cannot call native sale or change wallet")
end
-- Exact native entities in main inventory, backpack and native stash; same-name
-- copies remain intact. Native engine chooses the refund, including zero.
for _, location in ipairs({{active,0,450},{active,6,123},{active,9,225},{active,14,0},{bench,2,317},{stash,0,225}}) do
    local unit, slot, expected = location[1],location[2],location[3]
    local item, payload = itemFor(unit,slot,expected)
    local other = itemFor(unit,slot==0 and 1 or 0,225)
    local before, calls = balance, nativeCalls
    local ok, reason, refund = Sales.Sell(game,payload)
    assert(ok and reason=="sold" and refund==expected and balance==before+expected)
    assert(nativeCalls==calls+1 and item.null and not other.null, "sell exact entity once, not every matching name")
    rejected(payload,"invalid_item")
    unit.slots = {}
end
local item, payload = itemFor(active,0)
payload.PlayerID = nil; rejected(payload,"not_owned")
payload.PlayerID = 1; rejected(payload,"not_owned")
payload.PlayerID = 0
for _, phase in ipairs({"fight","result"}) do game.phase=phase; rejected(payload,"wrong_phase") end
game.phase="setup"
payload.hero="enemy"; rejected(payload,"not_owned")
payload.hero="__stash"; rejected(payload,"not_owned")
payload.hero="active"
payload.item="item_blink"; rejected(payload,"invalid_item"); payload.item=item.name
for _, id in ipairs({-1,0,0.5,math.huge,"oops",999999}) do payload.item_index=id; rejected(payload,"invalid_item") end
payload.item_index=item.id
item.sellable=false; rejected(payload,"not_sellable"); item.sellable=true
active.bind=false; rejected(payload,"not_owned"); active.bind=true
active.slots[0],active.slots[15]=nil,item; rejected(payload,"not_owned")
active.slots[15],active.slots[0]=nil,item
for _, key in ipairs({"nativePurchaseOrderContexts","pendingNativePurchases"}) do
    game[key]={{gold_before=1000}}
    rejected(payload,"purchase_pending")
    game[key][1].gold_checked=true
    assert(not Sales.HasPendingPurchase(game),"settled purchases do not block sale")
    game[key][1].gold_checked=nil; game[key][1].gold_failed=true
    assert(not Sales.HasPendingPurchase(game),"rejected purchases do not block sale forever")
    game[key]={}
end
for _, failure in ipairs({"noop","error"}) do
    active.fail=failure
    local before=balance
    local ok, reason, refund=Sales.Sell(game,payload)
    assert(not ok and reason=="sale_failed" and refund==0 and balance==before and not item.null,
        "successful pcall is not a successful sale; never invent a fallback refund")
    assert(not game.itemSaleInProgress,"native exception releases sale guard")
end
active.fail=nil
active.reenter=function() rejected(payload,"purchase_pending") end
assert(Sales.Sell(game,payload),"retry works after native rejection")
assert(item.null)
-- Neutral resale uses the server catalog, including inventory/backpack/stash
-- placements; a native unsellable flag is expected for these items.
do
    local oldAddGold = game.AddGold
    function game:AddGold(amount) balance = balance + amount end
    local function remove(unit, item)
        if unit.reenter then unit.reenter() end
        if unit.fail == "error" then error("remove failed") end
        if unit.fail == "noop" then return end
        for slot, value in pairs(unit.slots) do if value == item then unit.slots[slot] = nil end end
        if unit.fail ~= "detach" then item.null = true end
    end
    for _, unit in ipairs({active, bench, stash}) do unit.RemoveItem = remove; unit.reenter = nil end
    local cases = {
        {active,16,"item_chipped_vest",100}, {bench,16,"item_defiant_shell",200},
        {stash,16,"item_cloak_of_flames",400}, {active,6,"item_conjurers_catalyst",800},
        {stash,0,"item_desolator_2",1600},
    }
    for _, case in ipairs(cases) do
        local unit, slot, name, price = unpack(case)
        local neutral, request = itemFor(unit,slot)
        neutral.name, request.item, neutral.sellable = name, name, false
        request.price, request.tier, request.refund = 999999, 5, 999999
        local before, calls = balance, nativeCalls
        unit.reenter = function() rejected(request,"purchase_pending") end
        local ok, reason, refund = Sales.Sell(game,request)
        unit.reenter = nil
        assert(ok and reason=="sold" and refund==price and balance==before+price and neutral.null)
        assert(nativeCalls==calls,"neutral resale never invokes native SellItem")
        rejected(request,"invalid_item")
    end
    for _, failure in ipairs({"error","noop","detach"}) do
        local neutral, request = itemFor(active,16)
        neutral.name, request.item, neutral.sellable = "item_chipped_vest", "item_chipped_vest", false
        active.fail=failure
        rejected(request,"sale_failed")
        assert(not neutral.null and not game.itemSaleInProgress,"failed removal cannot pay or lock later sales")
    end
    active.fail=nil
    local neutral, request = itemFor(active,16)
    neutral.name, request.item, neutral.sellable = "item_chipped_vest", "item_chipped_vest", false
    request.PlayerID=1; rejected(request,"not_owned"); request.PlayerID=0
    request.hero="__stash"; rejected(request,"not_owned"); request.hero="active"
    game.phase="fight"; rejected(request,"wrong_phase"); game.phase="setup"
    game.pendingNativePurchases={{}}; rejected(request,"purchase_pending"); game.pendingNativePurchases={}
    assert(Sales.NeutralPrice("item_belt_of_strength")==nil
        and Sales.NeutralPrice("item_enhancement_alert")==nil
        and Sales.NeutralPrice("item_unknown_neutral")==nil,"ordinary/enchanted/unknown items cannot forge neutral tier prices")
    -- Native slot removal can be a no-op; exact entity deletion may still work.
    local previousRemove = UTIL_Remove
    active.fail = "noop"
    local fallback, fallbackRequest = itemFor(active,16)
    fallback.name, fallbackRequest.item, fallback.sellable = "item_foragers_kit", "item_foragers_kit", false
    local beforeFallback, fallbackCalls = balance, 0
    UTIL_Remove = function(exact)
        fallbackCalls = fallbackCalls + 1
        assert(exact == fallback and game.itemSaleInProgress, "explicit removal locked to requested entity")
        rejected(fallbackRequest, "purchase_pending")
        active.slots[16] = nil
        exact.null = true
    end
    assert(Sales.Sell(game, fallbackRequest) and balance == beforeFallback + 100 and fallbackCalls == 1,
        "neutral slot RemoveItem no-op can use verified exact entity removal")
    rejected(fallbackRequest,"invalid_item")
    local failed, failedRequest = itemFor(active,16)
    failed.name, failedRequest.item, failed.sellable = "item_pogo_stick", "item_pogo_stick", false
    UTIL_Remove = function() error("entity deletion unavailable") end
    rejected(failedRequest,"sale_failed")
    assert(not failed.null,"failed native removal cannot pay")
    UTIL_Remove = function() error("must not destroy detached items") end
    active.fail = "detach"
    rejected(failedRequest,"sale_failed")
    active.fail = nil
    UTIL_Remove = previousRemove
    game.AddGold=oldAddGold
end
print("item-sales tests passed (native transaction mocked; no gameplay claim)")
