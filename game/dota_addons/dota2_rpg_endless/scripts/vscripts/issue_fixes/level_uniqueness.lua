-- Validates that each stage uses a distinct enemy composition and repairs the
-- reported duplicated stage 1 / stage 2 composition without touching rewards.

local LevelUniqueness = {}

local function sorted_numeric_values(value)
    if type(value) ~= "table" then return {} end

    local rows = {}
    for key, entry in pairs(value) do
        rows[#rows + 1] = {
            order = tonumber(key) or 1000000,
            key = tostring(key),
            value = entry,
        }
    end
    table.sort(rows, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)

    local result = {}
    for _, row in ipairs(rows) do result[#result + 1] = row.value end
    return result
end

local function get_stage(levels, stage_number)
    local candidates = {
        stage_number,
        tostring(stage_number),
        "stage_" .. tostring(stage_number),
        "stage" .. tostring(stage_number),
        "level_" .. tostring(stage_number),
        "level" .. tostring(stage_number),
        "ch" .. tostring(stage_number),
        string.format("ch%02d", stage_number),
    }

    for _, key in ipairs(candidates) do
        if levels[key] ~= nil then return levels[key], key end
    end
    return nil, nil
end

local function get_enemies(stage)
    if type(stage) ~= "table" then return {} end
    return stage.enemies or stage.enemy_units or stage.units or {}
end

local function entry_name(entry)
    if type(entry) == "string" then return entry end
    if type(entry) ~= "table" then return "unknown" end
    return tostring(
        entry.unit
        or entry.unit_name
        or entry.name
        or entry.npc
        or entry[1]
        or "unknown"
    )
end

local function entry_count(entry)
    if type(entry) ~= "table" then return 1 end
    return math.max(1, math.floor(tonumber(entry.count) or 1))
end

function LevelUniqueness.CompositionSignature(stage)
    local counts = {}
    for _, entry in ipairs(sorted_numeric_values(get_enemies(stage))) do
        local name = entry_name(entry)
        counts[name] = (counts[name] or 0) + entry_count(entry)
    end

    local names = {}
    for name in pairs(counts) do names[#names + 1] = name end
    table.sort(names)

    local result = {}
    for _, name in ipairs(names) do
        result[#result + 1] = name .. "x" .. tostring(counts[name])
    end
    return table.concat(result, "+")
end

function LevelUniqueness.StageTwoEnemies()
    -- Keep every spawn as an explicit entry. The current repository has used
    -- per-entry spawning in several revisions, so this works even when the
    -- loader does not interpret a `count` field.
    return {
        {
            unit = "npc_dota_neutral_centaur_outrunner",
            level = 2,
            ai_profile = "attack_nearest",
            tags = "melee,standard",
        },
        {
            unit = "npc_dota_neutral_centaur_outrunner",
            level = 2,
            ai_profile = "attack_nearest",
            tags = "melee,standard",
        },
        {
            unit = "npc_dota_neutral_centaur_outrunner",
            level = 2,
            ai_profile = "attack_nearest",
            tags = "melee,standard",
        },
        {
            unit = "npc_dota_neutral_centaur_khan",
            level = 2,
            ai_profile = "attack_nearest",
            tags = "melee,leader",
        },
    }
end

function LevelUniqueness.ApplyStageOneTwoFix(levels)
    assert(type(levels) == "table", "levels must be a table")

    local stage_one = get_stage(levels, 1)
    local stage_two = get_stage(levels, 2)
    local one_signature = LevelUniqueness.CompositionSignature(stage_one)
    local two_signature = LevelUniqueness.CompositionSignature(stage_two)

    if stage_one == nil or stage_two == nil then
        return false, "stage_missing"
    end

    if one_signature == "" or one_signature ~= two_signature then
        return false, "already_distinct"
    end

    -- Keep the stage object, rewards, limits and metadata. Replace only enemies.
    stage_two.enemies = LevelUniqueness.StageTwoEnemies()
    stage_two.enemy_units = nil
    stage_two.units = nil
    return true, "stage_2_enemies_replaced"
end

function LevelUniqueness.ValidateAll(levels, max_stage)
    assert(type(levels) == "table", "levels must be a table")
    max_stage = tonumber(max_stage) or 30

    local seen = {}
    local errors = {}
    for stage_number = 1, max_stage do
        local stage = get_stage(levels, stage_number)
        if stage ~= nil then
            local signature = LevelUniqueness.CompositionSignature(stage)
            if signature == "" then
                errors[#errors + 1] = string.format(
                    "stage %d has no enemy composition",
                    stage_number
                )
            elseif seen[signature] ~= nil then
                errors[#errors + 1] = string.format(
                    "stage %d duplicates stage %d: %s",
                    stage_number,
                    seen[signature],
                    signature
                )
            else
                seen[signature] = stage_number
            end
        end
    end

    return #errors == 0, errors
end

return LevelUniqueness
