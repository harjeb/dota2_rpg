-- Explicit panel selling uses native transactions; Gris-Gris is a consumable
-- savings bank with roster persistence and a shared-wallet redemption adapter.
local Sales = {}

function Sales.HasPendingPurchase(game)
    for _, queue in ipairs({game.nativePurchaseOrderContexts or {}, game.pendingNativePurchases or {}}) do
        for _, purchase in ipairs(queue) do
            if not purchase.gold_checked and not purchase.gold_failed then return true end
        end
    end
    return false
end

function Sales.Sell(game, payload)
    local playerId = tonumber(game.playerId)
    if type(payload) ~= "table" or playerId == nil or playerId < 0
        or tonumber(payload.PlayerID) ~= playerId then return false, "not_owned", 0 end
    if game.phase ~= "setup" then return false, "wrong_phase", 0 end
    if game.itemSaleInProgress or Sales.HasPendingPurchase(game) then return false, "purchase_pending", 0 end

    local itemIndex = tonumber(payload.item_index)
    if itemIndex == nil or itemIndex < 1 or itemIndex > 2147483647 or itemIndex ~= math.floor(itemIndex)
        or type(payload.item) ~= "string" or payload.item == "" then return false, "invalid_item", 0 end
    local item = EntIndexToHScript(itemIndex)
    if not game:IsLiveItem(item) or item:GetAbilityName() ~= payload.item then return false, "invalid_item", 0 end
    local holder = payload.hero == "__stash" and game:GetStashUnit()
        or (type(payload.hero) == "string" and game:FindOwnedHeroUnit(payload.hero) or nil)
    if holder == nil or not game:IsEquipmentCarrier(holder)
        or not game:IsItemHeldBy(holder, item, 0, 16) then return false, "not_owned", 0 end
    if game:IsItemHeldBy(holder, item, 15, 15) then return false, "not_owned", 0 end
    if payload.item == "item_grisgris" then
        if not game:BindEquipmentCarrierToPlayer(holder) then return false, "not_owned", 0 end
        return require("issue_fixes/gris_gris").Redeem(game, holder, item)
    end
    if item.IsSellable == nil or holder.SellItem == nil then return false, "unavailable", 0 end
    local checked, sellable = pcall(item.IsSellable, item)
    if not checked or not sellable then return false, "not_sellable", 0 end
    if not game:BindEquipmentCarrierToPlayer(holder) then return false, "not_owned", 0 end

    local before = game:GetGoldBalance()
    game.itemSaleInProgress = true
    local called = pcall(holder.SellItem, holder, item)
    game.itemSaleInProgress = nil
    -- SellItem returns void. A successful call alone does not prove that the
    -- native engine accepted it; the exact entity must actually be destroyed.
    if not called or game:IsLiveItem(item) then return false, "sale_failed", 0 end
    local after = game:GetGoldBalance()
    game.nativeShopTransactionPending = true
    print(string.format("[Dota2Rpg] Native item sold: item=%s id=%d holder=%s gold_before=%d gold_after=%d.",
        payload.item, itemIndex, tostring(payload.hero), before, after))
    return true, "sold", math.max(0, after - before)
end

return Sales
