local Catalog = require("data.campaign_loot_catalog")
local RunLives = require("battle.run_lives")
local Loot = { Catalog = Catalog }

-- Exactly three independent gates, with one uniform catalog draw per success.
-- Catalog size changes breadth, never the number of reward rolls.
function Loot.Roll(config, random)
    random = random or math.random
    local rewards = {}
    if type(config) ~= "table" or config.pool ~= "all_items" then return rewards end
    for index = 1, 3 do
        local entry = (config.items or {})[tostring(index)] or (config.items or {})[index]
        local chance = type(entry) == "table" and tonumber(entry.chance) or 0
        chance = math.max(0, math.min(1, chance or 0))
        if random() < chance then
            rewards[#rewards + 1] = Catalog[random(1, #Catalog)]
        end
    end
    return rewards
end

local function inventory(stash)
    local snapshot, space = {}, false
    for slot = 0, 14 do
        local item = stash:GetItemInSlot(slot)
        if item == nil then space = true
        else
            snapshot[#snapshot + 1] = tostring(item) .. ":" .. tostring(item:GetCurrentCharges())
        end
    end
    table.sort(snapshot)
    return table.concat(snapshot, ";"), space
end

function Loot.Flush(game)
    local remaining = {}
    for _, reward in ipairs(RunLives.Ensure(game).pendingCampaignLoot or {}) do
        local delivered = false
        local stash = game:GetStashUnit()
        if not reward.uncertain and stash ~= nil and not stash:IsNull() then
            local before, space = inventory(stash)
            if space then
                local ok, accepted = pcall(game.StashAddItem, game, reward.delivery)
                local after = inventory(stash)
                -- Combining/stacking can invalidate the returned native handle.
                -- Inventory change is success evidence; never retry a possibly
                -- consumed native item after an ambiguous callback/exception.
                delivered = (ok and accepted) or before ~= after
                if not delivered then
                    reward.uncertain = true
                    print("[RPG][Loot] delivery ambiguous; retained without automatic retry: " .. reward.delivery)
                end
            end
        end
        if not delivered then remaining[#remaining + 1] = reward end
    end
    RunLives.Ensure(game).pendingCampaignLoot = remaining
    return #remaining
end

function Loot.Award(game, config, random)
    local names = {}
    RunLives.Ensure(game).pendingCampaignLoot = RunLives.Ensure(game).pendingCampaignLoot or {}
    for _, row in ipairs(Loot.Roll(config, random)) do
        names[#names + 1] = row.delivery
        if row.delivery == "item_aegis" then
            -- Native Aegis is not droppable: existing life-reward delivery
            -- explicitly configures transferability and retains the entity.
            local state = RunLives.Ensure(game)
            state.pendingItems[#state.pendingItems + 1] = { name = row.delivery }
        else
            RunLives.Ensure(game).pendingCampaignLoot[#RunLives.Ensure(game).pendingCampaignLoot + 1] = { name = row.name, delivery = row.delivery }
        end
    end
    Loot.Flush(game)
    RunLives.FlushItems(game)
    -- No startup pool traversal or synchronous hundreds-of-items precache.
    -- A single retry worker exists only while this run has earned pending loot.
    local run = RunLives.Ensure(game)
    if GameRules ~= nil and GameRules.GetGameModeEntity ~= nil then
        GameRules:GetGameModeEntity():SetContextThink("CampaignLootDelivery", function()
            if game.runLives ~= run then return nil end
            Loot.Flush(game)
            RunLives.FlushItems(game)
            for _, reward in ipairs(RunLives.Ensure(game).pendingCampaignLoot or {}) do
                if not reward.uncertain then return 1 end
            end
            if #RunLives.Ensure(game).pendingItems > 0 then return 1 end
            return nil
        end, 1)
    end
    -- Settlement lists earned items, including pending inventory-full rewards.
    return names
end

return Loot
