local M = {}

-- 已确认的开局规则。
M.INITIAL_GOLD = 500
M.STARTER_FREE_RECRUITS = 2
M.TIME_BONUS_CAP = 0.10
M.BENCH_XP_RATE = 0.50
M.MAX_LEVEL = 30

-- 到达对应等级所需的累计经验；索引 1 代表 1 级。
M.XP_TO_LEVEL = {
    0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700,
    3300, 4000, 4800, 5700, 6700, 7800, 9000, 10300, 11700, 13200,
    14800, 16500, 18300, 20200, 22200, 24300, 26500, 28800, 31200, 33700,
}

-- 每名上阵英雄获得的经验；待命英雄获得 floor(value * 0.5)。
M.STAGE_XP = {
    120, 160, 200, 250, 320,
    360, 420, 480, 540, 650,
    700, 760, 820, 900, 1050,
    1100, 1180, 1260, 1350, 1550,
    1600, 1700, 1800, 1900, 2200,
    2300, 2400, 2600, 3050,
    0, -- 第 30 关为 Run 结束后的展示奖励，不再用于继续养成。
}

M.STAGE_GOLD = {
    900, 1000, 1100, 1200, 1000,
    3000, 1400, 1600, 1800, 2500,
    5200, 2500, 2800, 3100, 4000,
    7500, 3600, 4000, 4400, 5600,
    9000, 4800, 5300, 5800, 7200,
    12000, 6500, 7600, 9000,
    15000,
}

-- 价格只由招募等级决定。品质仍决定魔晶/神杖效果，但不再乘价格倍率。
M.RECRUIT_BANDS = {
    { from_stage = 1,  to_stage = 4,  level = 1, price = 500 },
    { from_stage = 5,  to_stage = 9,  level = 5, price = 900 },
    { from_stage = 10, to_stage = 14, level = 10, price = 1600 },
    { from_stage = 15, to_stage = 19, level = 15, price = 2600 },
    { from_stage = 20, to_stage = 24, level = 20, price = 4000 },
    { from_stage = 25, to_stage = 30, level = 24, price = 5500 },
}

function M.StageNumber(level_id)
    if type(level_id) == "number" then
        return math.max(1, math.min(30, math.floor(level_id)))
    end
    local value = tonumber(string.match(tostring(level_id or ""), "ch(%d+)")) or 1
    return math.max(1, math.min(30, math.floor(value)))
end

function M.GetRecruitBand(stage)
    stage = M.StageNumber(stage)
    for _, band in ipairs(M.RECRUIT_BANDS) do
        if stage >= band.from_stage and stage <= band.to_stage then
            return band
        end
    end
    return M.RECRUIT_BANDS[1]
end

function M.PriceForLevel(level)
    level = math.floor(tonumber(level) or 1)
    for _, band in ipairs(M.RECRUIT_BANDS) do
        if band.level == level then
            return band.price
        end
    end
    return nil
end

function M.XpNeededForNextLevel(level)
    level = math.floor(tonumber(level) or 1)
    if level < 1 or level >= M.MAX_LEVEL then
        return 0
    end
    return M.XP_TO_LEVEL[level + 1] - M.XP_TO_LEVEL[level]
end

return M
