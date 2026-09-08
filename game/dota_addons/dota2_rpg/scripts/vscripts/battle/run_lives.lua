local RunLives = { MAX_LIVES = 5 }

function RunLives.Ensure(game)
    if game.runLives == nil then
        game.runLives = { remaining = RunLives.MAX_LIVES, pendingItems = {} }
    end
    return game.runLives
end

-- EndBattle's phase guard owns exactly-once settlement. Only a lost battle or
-- timeout calls Lose; individual hero deaths and native reincarnation do not.
function RunLives.Lose(game)
    local state = RunLives.Ensure(game)
    local reward = { gold = 0, items = {} }
    if state.remaining <= 0 then return reward end
    state.remaining = state.remaining - 1
    if state.remaining == 3 then
        reward.gold = 2000
        game:AddGold(reward.gold)
    elseif state.remaining == 1 then
        reward.items = { "item_aegis", "item_cheese" }
        for _, name in ipairs(reward.items) do
            table.insert(state.pendingItems, { name = name })
        end
    end
    print(string.format("[RPG][RunLives] remaining=%d gold_reward=%d items=%s",
        state.remaining, reward.gold, table.concat(reward.items, ";")))
    return reward
end

local function live(entity)
    return entity ~= nil and (entity.IsNull == nil or not entity:IsNull())
end

local function deliver(game, pending)
    local stash = game:GetStashUnit()
    if not live(stash) then return false end
    -- Keep the actual entity across failed delivery attempts; never create a
    -- second Aegis because the inventory was full or AddItem rejected it.
    if not live(pending.item) then
        if CreateItem == nil then return false end
        local ok, item = pcall(CreateItem, pending.name, stash, nil)
        if not ok or not live(item) then return false end
        pending.item = item
    end
    local item = pending.item
    local configured = pcall(function()
        item:SetDroppable(true)
        item:SetShareability(ITEM_FULLY_SHAREABLE)
        if item.SetPurchaser ~= nil then item:SetPurchaser(nil) end
    end)
    if not configured then return false end
    if game:TryAttachItem(stash, item) then
        print("[RPG][RunLives] reward_delivered=" .. pending.name .. " location=stash transferable=1")
        return true
    end
    -- All fifteen storage slots may be occupied. Preserve the same native item
    -- on the commander's ground instead of silently discarding an earned reward.
    if CreateItemOnPositionSync ~= nil and stash.GetAbsOrigin ~= nil then
        local ok, container = pcall(CreateItemOnPositionSync, stash:GetAbsOrigin(), item)
        if ok and live(container) then
            print("[RPG][RunLives] reward_delivered=" .. pending.name .. " location=ground transferable=1")
            return true
        end
    end
    return false
end

function RunLives.FlushItems(game)
    local state = RunLives.Ensure(game)
    local remaining, delivered = {}, 0
    for _, pending in ipairs(state.pendingItems) do
        if deliver(game, pending) then delivered = delivered + 1
        else remaining[#remaining + 1] = pending end
    end
    state.pendingItems = remaining
    return delivered
end

return RunLives
