-- Permanent score v1: normalized hearts (110%) and stages (100%) multiply.
-- Rank time deliberately sums REMAINING victory time; smaller wins speedrun.
local Score = { VERSION = "hearts-stages-v1", TOTAL_STAGES = 30, MAX_HEARTS = 5, STAGE_TIME_MS = 120000 }
local function integer(value, maximum)
    value = tonumber(value) or 0
    if value ~= value then return 0 end
    return math.floor(math.max(0, math.min(maximum, value)))
end
function Score.Calculate(hearts, stages, remainingMs, cleared)
    hearts = integer(hearts, Score.MAX_HEARTS)
    stages = integer(stages, Score.TOTAL_STAGES)
    remainingMs = integer(remainingMs, stages * Score.STAGE_TIME_MS)
    -- Integer form of 100000 * (1 + 1.1*hearts/5) * (1 + stages/30).
    local core = math.floor(1000 * (50 + 11 * hearts) * (30 + stages) / 15)
    local time = math.floor(remainingMs / 1000) * 10
    local clear = cleared and 1000000 or 0
    return { score = core + time + clear, core_score = core, time_bonus_score = time,
        clear_bonus_score = clear, remaining_hearts = hearts, stage_count = stages,
        total_stages = Score.TOTAL_STAGES, remaining_time_ms = remainingMs, cleared = cleared and 1 or 0 }
end
return Score
