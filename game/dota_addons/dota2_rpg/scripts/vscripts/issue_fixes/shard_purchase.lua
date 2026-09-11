-- Shard is consumed by the assigned hero before purchase events can route it.
-- This narrow order-time exception uses the native consumed modifier, not an
-- inventory surrogate. Native KV: cost 1400, stock max 1, restock 1 second;
-- UI39 supplies initial stock 1 at time 0. Other shop items remain native.
local Shards = {}
local MODIFIER = "modifier_item_aghanims_shard"
local COST, RESTOCK = 1400, 1

local function hasShard(hero)
    if hero.HasShard ~= nil then return hero:HasShard() == true end
    return hero:HasModifier(MODIFIER)
end

function Shards.Restore(game, name, hero)
    local data = game.heroData and game.heroData[name]
    if data and data.purchased_shard and not hasShard(hero) then
        hero:AddNewModifier(hero, nil, MODIFIER, {})
    end
end

function Shards.Purchase(game, issuer, recipientKey)
    if game.phase ~= "setup" or issuer ~= game.playerId or issuer == nil or issuer < 0 then
        return false, "购买魔晶只能在准备阶段进行。"
    end
    if game.shardPurchaseBusy then return false, "魔晶购买正在处理。" end
    local hero = recipientKey and recipientKey ~= "__wisp" and game:FindOwnedHeroUnit(recipientKey) or nil
    local data = game.heroData and game.heroData[recipientKey or ""]
    if hero == nil or hero:IsNull() or data == nil or hero == game:GetStashUnit()
        or not (game:IsLineupUnit(hero) or game:IsBenchUnit(hero))
        or hero:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS
        or game:GetCarrierPlayerOwnerId(hero) ~= issuer then
        return false, "请先选中一名己方上阵或待命英雄，再购买魔晶。"
    end
    if hero.HasModifier == nil or hero.AddNewModifier == nil then
        return false, "该英雄暂时无法获得魔晶。"
    end
    if data.purchased_shard or hasShard(hero) then return false, "该英雄已拥有魔晶，未扣除金币。" end
    -- An unresolved native debit must finish before this synchronous transaction.
    for _, list in ipairs({ game.nativePurchaseOrderContexts or {}, game.pendingNativePurchases or {} }) do
        for _, purchase in ipairs(list) do
            if not purchase.gold_checked and not purchase.gold_failed then
                return false, "请等待上一笔装备购买完成。"
            end
        end
    end
    local now = game:GetNativePurchaseClock()
    if now < (game.shardRestockAt or 0) then return false, "魔晶正在补货，请稍后购买。" end
    -- Do not accept order payload prices. Fail closed if the installed native
    -- definition no longer matches this explicitly bounded exception.
    if type(GetItemCost) ~= "function" or GetItemCost("item_aghanims_shard") ~= COST then
        return false, "魔晶价格校验失败，未扣除金币。"
    end
    local balance = game:GetGoldBalance()
    if balance < COST then return false, "金币不足，需要1400金币。" end
    game.shardPurchaseBusy = true
    -- No item is created on Wisp, no native purchase is accepted, and no native
    -- purchase context is queued. Check actual upgrade state before charging.
    local ok = pcall(function() hero:AddNewModifier(hero, nil, MODIFIER, {}) end)
    local granted = hasShard(hero)
    if granted then
        game:SetGoldBalance(balance - COST)
        data.purchased_shard = true
        game.shardRestockAt = now + RESTOCK
    end
    game.shardPurchaseBusy = nil
    if not granted then
        -- A modifier handle alone is not proof of the native Shard flag. Remove
        -- only our failed new grant so an uncharged attempt cannot block retry.
        if hero.RemoveModifierByName then pcall(hero.RemoveModifierByName, hero, MODIFIER) end
        return false, ok and "魔晶未能生效，未扣除金币。" or "魔晶授予失败，未扣除金币。"
    end
    return true, "魔晶已给予选中的英雄。"
end

function Shards.Notify(game, message)
    local player = PlayerResource and PlayerResource:GetPlayer(game.playerId)
    if player and CustomGameEventManager then
        CustomGameEventManager:Send_ServerToPlayer(player, "dota_hud_error_message", {reason=80, message=message})
    end
end
return Shards
