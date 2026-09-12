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

-- 普通装备每关提高价格区间；中立装备按原生 1..5 档递进。
-- 未知关卡保留完整目录，供不带战役关卡的调用使用。
local CHAPTERS_PER_POWER = 6
local MAX_POWER = 5
local stage_pools = {}

function Loot.PowerCeiling(stage)
    local number = tonumber(stage)
    if number == nil or number <= 0 then return nil end
    return math.max(1, math.min(MAX_POWER, math.ceil(number / CHAPTERS_PER_POWER)))
end

function Loot.StageFromLevel(levelId)
    if type(levelId) ~= "string" then return nil end
    local digits = levelId:match("(%d+)%s*$")
    return digits
end

function Loot.PriceRange(stage)
    local number = tonumber(stage)
    if number == nil or number <= 0 then return nil end
    local maximum = math.min(30, math.max(1, math.ceil(number))) * 250
    return math.min(6000, math.max(1, maximum - 1000)), maximum
end

function Loot.PoolForStage(stage)
    local ceiling = Loot.PowerCeiling(stage)
    if ceiling == nil then return Catalog end
    local minimum, maximum = Loot.PriceRange(stage)
    if stage_pools[maximum] ~= nil then return stage_pools[maximum] end
    local pool = {}
    for _, row in ipairs(Catalog) do
        local cost = tonumber(row.cost) or 0
        if (row.category == "standard" and cost >= minimum and cost <= maximum)
            or (row.category ~= "standard" and row.power == ceiling) then
            pool[#pool + 1] = row
        end
    end
    stage_pools[maximum] = pool
    return pool
end

function Loot.IsNeutralName(itemName)
    return itemName ~= nil and NeutralNames[itemName] == true
end

-- Exactly three independent drop gates; progression only changes item selection.
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

-- 超过 6000 的装备属于同一顶级档，避免最高价的大根 5 垄断后期保底。
function Loot.ProgressValue(row)
    return math.min(tonumber(row.cost) or 0, 6000)
end

-- 85% 普通装备，15% 当档中立/特殊奖励，避免零售价物品挤占装备掉落。
-- 普通装备的 90% 走价值保底：优先超过本局最高掉落价值，到达关卡上限则同价。
-- 顶级装备允许同档轮换；其余 10% 在当前价格区间自由抽取，回落不会降低保底。
local function ProgressionPick(pool, random, history)
    local equipment, bonus = {}, {}
    for _, row in ipairs(pool) do
        local target = row.category == "standard" and equipment or bonus
        target[#target + 1] = row
    end
    if #bonus > 0 and (#equipment == 0 or random() >= 0.85) then
        return bonus[random(1, #bonus)]
    end
    local choices = equipment
    if random() < 0.90 then
        local better, equal, best = {}, {}, {}
        local highest = math.min(tonumber(history.highestEquipmentCost) or 0, 6000)
        local bestCost = 0
        for _, row in ipairs(equipment) do
            local value = Loot.ProgressValue(row)
            if value > highest then better[#better + 1] = row
            elseif value == highest then equal[#equal + 1] = row end
            if value > bestCost then bestCost, best = value, {} end
            if value == bestCost then best[#best + 1] = row end
        end
        -- 回选早期关卡时仍遵守该关上限；正常推进总有 >= 历史最高价的候选。
        choices = #better > 0 and better or (#equal > 0 and equal or best)
    end
    local row = choices[random(1, #choices)]
    history.highestEquipmentCost = math.max(tonumber(history.highestEquipmentCost) or 0, row.cost)
    return row
end

function Loot.Roll(config, random, stage, history)
    random = random or NativeRandom
    local rewards = {}
    if type(config) ~= "table" or config.pool ~= "all_items" then return rewards end
    local pool = Loot.PoolForStage(stage)
    local progressing = Loot.PowerCeiling(stage) ~= nil
    history = history or {}
    for index = 1, 3 do
        local entry = (config.items or {})[tostring(index)] or (config.items or {})[index]
        local chance = type(entry) == "table" and tonumber(entry.chance) or 0
        chance = math.max(0, math.min(1, chance or 0))
        if random() < chance then
            rewards[#rewards + 1] = progressing and ProgressionPick(pool, random, history)
                or pool[random(1, #pool)]
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
            -- 关键是两类装备各看自己的容量：中立槽被占用时属于"暂时没位置"，
            -- 不能因为 0..14 有空位就去调用（会被拒绝，再被误判成交付不明而永久扣下）。
            local neutral = Loot.IsNeutralName(reward.delivery)
            local neutral_ready = neutral and stash:GetItemInSlot(NEUTRAL_ITEM_SLOT) == nil
            local can_deliver = neutral and neutral_ready or (not neutral and space)
            if can_deliver then
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
    local state = RunLives.Ensure(game)
    state.pendingCampaignLoot = state.pendingCampaignLoot or {}
    state.campaignLootProgress = state.campaignLootProgress or {}
    for _, row in ipairs(Loot.Roll(config, random, Loot.StageFromLevel(game and game.currentLevelId), state.campaignLootProgress)) do
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
