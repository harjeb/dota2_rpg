-- Explicit panel selling uses native transactions; Gris-Gris is a consumable
-- savings bank with roster persistence and a shared-wallet redemption adapter.
local Sales = {}
local neutralPrices
local neutralTierPrices = { 100, 200, 400, 800, 1600 }

-- One line per user transaction, independent of the general trace budget.
function Sales.LogResult(game, payload, ok, reason, refund)
    pcall(function()
        payload = type(payload) == "table" and payload or {}
        print(string.format("[RPGItemSale v=71] request=%s player=%s phase=%s item=%s entity=%s holder=%s ok=%s reason=%s refund=%s",
            tostring(payload.request_id), tostring(payload.PlayerID), tostring(game.phase),
            tostring(payload.item), tostring(payload.item_index), tostring(payload.hero),
            tostring(ok), tostring(reason), tostring(refund)))
    end)
end

function Sales.NeutralPrice(itemName)
    if neutralPrices == nil then
        neutralPrices = {}
        for _, entry in ipairs(require("data.campaign_loot_catalog")) do
            if entry.neutral == true and entry.category == "neutral" then
                neutralPrices[entry.name] = neutralTierPrices[tonumber(entry.power)]
            end
        end
    end
    return neutralPrices[itemName]
end

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
    if payload.item == "item_eldwurms_edda" then
        if not game:BindEquipmentCarrierToPlayer(holder) then return false, "not_owned", 0 end
        return require("issue_fixes/eldwurms_edda").Consume(game, holder, item)
    end
    local neutralPrice = Sales.NeutralPrice(payload.item)
    if neutralPrice ~= nil then
        if holder.RemoveItem == nil then return false, "unavailable", 0 end
        if not game:BindEquipmentCarrierToPlayer(holder) then return false, "not_owned", 0 end
        game.itemSaleInProgress = true
        local called, removalError = pcall(holder.RemoveItem, holder, item)
        -- Some native inventories refuse RemoveItem on protected neutral slots.
        -- The user authorized destruction of this exact verified entity. Use
        -- explicit entity removal only if it is STILL in that same inventory;
        -- never follow an item moved to someone else during a callback.
        if game:IsLiveItem(item) and game:IsItemHeldBy(holder, item, 0, 16)
            and type(UTIL_Remove) == "function" then
            called, removalError = pcall(UTIL_Remove, item)
        end
        game.itemSaleInProgress = nil
        pcall(function()
            print(string.format("[RPGItemSale v=71] neutral_remove item=%s entity=%d price=%d called=%s live=%s held=%s error=%s",
                payload.item, itemIndex, neutralPrice, tostring(called), tostring(game:IsLiveItem(item)),
                tostring(game:IsItemHeldBy(holder, item, 0, 16)), called and "none" or tostring(removalError)))
        end)
        -- Native neutrals are unsellable. Pay the configured resale only after
        -- the exact entity has been destroyed, never merely detached or moved.
        if not called or game:IsLiveItem(item) then return false, "sale_failed", 0 end
        game:AddGold(neutralPrice)
        game.nativeShopTransactionPending = true
        print(string.format("[Dota2Rpg] Neutral item sold: item=%s id=%d holder=%s refund=%d.",
            payload.item, itemIndex, tostring(payload.hero), neutralPrice))
        return true, "sold", neutralPrice
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
