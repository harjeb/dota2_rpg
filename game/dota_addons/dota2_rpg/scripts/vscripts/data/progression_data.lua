local M = {}

-- Cumulative XP required to reach each level. Index 1 means level 1.
M.XP_TO_LEVEL = {
    0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700,
    3300, 4000, 4800, 5700, 6700, 7800, 9000, 10300, 11700, 13200,
    14800, 16500, 18300, 20200, 22200, 24300, 26500, 28800, 31200, 33700,
}

-- Per active hero. Bench heroes receive floor(value * 0.5).
M.STAGE_XP = {
    120, 160, 200, 250, 320,
    360, 420, 480, 540, 650,
    700, 760, 820, 900, 1050,
    1100, 1180, 1260, 1350, 1550,
    1600, 1700, 1800, 1900, 2200,
    2300, 2400, 2600, 3050,
    0, -- Stage 30 is the end of the run.
}

M.STAGE_GOLD = {
    900, 1000, 1100, 1200, 1000,
    3000, 1400, 1600, 1800, 2500,
    5200, 2500, 2800, 3100, 4000,
    7500, 3600, 4000, 4400, 5600,
    9000, 4800, 5300, 5800, 7200,
    12000, 6500, 7600, 9000,
    15000, -- Post-run display reward.
}

M.RECRUIT_BANDS = {
    { from_stage = 1,  to_stage = 4,  level = 1,  price = 500 },
    { from_stage = 5,  to_stage = 9,  level = 5,  price = 900 },
    { from_stage = 10, to_stage = 14, level = 10, price = 1600 },
    { from_stage = 15, to_stage = 19, level = 15, price = 2600 },
    { from_stage = 20, to_stage = 24, level = 20, price = 4000 },
    { from_stage = 25, to_stage = 30, level = 24, price = 5500 },
}

return M
