local Catalog = require("data.campaign_loot_catalog")
local RunLives = require("battle.run_lives")
local Loot = { Catalog = Catalog }

-- 原版专属槽位：16 = 中立装备。它不属于物品栏 0..5／背包 6..8／原生储藏栏 9..14，
-- 因此 0..14 的枚举既看不到掉落的中立装备，也不能把它算成“仓库有空位”。
local NEUTRAL_ITEM_SLOT = 16
local LAST_STANDARD_SLOT = 14

-- 中立装备名称集合：交付前必须知道名称是否为中立，否则无法判断该占哪个槽。
local NeutralNames = {}
for _, row in ipairs(Catalog) do
    if row.neutral then
        NeutralNames[row.name] = true
        NeutralNames[row.delivery] = true
    end
end

function Loot.IsNeutralName(itemName)
    return itemName ~= nil and NeutralNames[itemName] == true
end

-- Exactly three independent gates, with one uniform catalog draw per success.
-- Catalog size changes breadth, never the number of reward rolls.
-- 原版 Lua VM 的 math.random 起手就是可重复序列（与 addon_game_mode.lua 里商店
-- 随机数同一原因），所以掉落过去每局都是同一条顺序。战斗逻辑统一走引擎原生 RandomInt，
-- 只有独立的 Lua 测试宿主才退回 math.random；调用方显式传入的 random 仍然优先。
local function NativeRandom(first, last)
    if last ~= nil then
        if RandomInt ~= nil then return RandomInt(first, last) end
        return math.random(first, last)
    end
    -- [0, 1) 浮点：整数格点足以表达 kv 里 0..1 的概率。
    if RandomInt ~= nil then return RandomInt(0, 65535) / 65536 end
    return math.random()
end

function Loot.Roll(config, random)
    random = random or NativeRandom
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

local function describe(item)
    return tostring(item) .. ":" .. tostring(item:GetCurrentCharges())
end

-- 交付证据必须覆盖中立槽，否则一件成功入中立槽的奖励在前后快照里没有差异。
-- “有空位”只按 0..14 判断：中立槽放不下普通装备，不能冒充普通空间。
local function inventory(stash)
    local snapshot, space = {}, false
    for slot = 0, LAST_STANDARD_SLOT do
        local item = stash:GetItemInSlot(slot)
        if item == nil then space = true
        else
            snapshot[#snapshot + 1] = describe(item)
        end
    end
    local neutral = stash:GetItemInSlot(NEUTRAL_ITEM_SLOT)
    if neutral ~= nil then
        snapshot[#snapshot + 1] = describe(neutral)
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
            -- 中立装备进的是专属中立槽，0..14 满不等于它没位置；反之普通装备
            -- 也不能靠中立槽凑数，否则引擎会把无处安放的实体丢到地上。
            local neutral_ready = Loot.IsNeutralName(reward.delivery)
                and stash:GetItemInSlot(NEUTRAL_ITEM_SLOT) == nil
            if space or neutral_ready then
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
