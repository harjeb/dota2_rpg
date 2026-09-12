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

-- 关卡强度 -> 允许的最高掉落档位：30 章 / 5 档，约每 6 章升一档。
-- 实际抽取在 [档位-1, 档位] 区间内，既贴合关卡强度又保留变化；未知关卡不做过滤，
-- 保持旧行为（例如离线测试里没有关卡号的调用）。
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

function Loot.PoolForStage(stage)
    local ceiling = Loot.PowerCeiling(stage)
    if ceiling == nil then return Catalog end
    if stage_pools[ceiling] ~= nil then return stage_pools[ceiling] end
    local floor = math.max(1, ceiling - 1)
    local pool = {}
    for _, row in ipairs(Catalog) do
        local power = tonumber(row.power) or 1
        if power >= floor and power <= ceiling then
            pool[#pool + 1] = row
        end
    end
    if #pool == 0 then pool = Catalog end
    stage_pools[ceiling] = pool
    return pool
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

function Loot.Roll(config, random, stage)
    random = random or NativeRandom
    local rewards = {}
    if type(config) ~= "table" or config.pool ~= "all_items" then return rewards end
    local pool = Loot.PoolForStage(stage)
    for index = 1, 3 do
        local entry = (config.items or {})[tostring(index)] or (config.items or {})[index]
        local chance = type(entry) == "table" and tonumber(entry.chance) or 0
        chance = math.max(0, math.min(1, chance or 0))
        if random() < chance then
            rewards[#rewards + 1] = pool[random(1, #pool)]
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
    RunLives.Ensure(game).pendingCampaignLoot = RunLives.Ensure(game).pendingCampaignLoot or {}
    for _, row in ipairs(Loot.Roll(config, random, Loot.StageFromLevel(game and game.currentLevelId))) do
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
