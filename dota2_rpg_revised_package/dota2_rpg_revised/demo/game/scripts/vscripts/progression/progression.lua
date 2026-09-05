local Data = require("data/progression_data")

local Progression = {}

local function is_valid_hero(hero)
    return hero ~= nil
        and (hero.IsNull == nil or not hero:IsNull())
        and hero.IsRealHero ~= nil
        and hero:IsRealHero()
end

function Progression.InstallCustomLevels(game_mode_entity)
    game_mode_entity:SetUseCustomHeroLevels(true)
    game_mode_entity:SetCustomHeroMaxLevel(#Data.XP_TO_LEVEL)
    game_mode_entity:SetCustomXPRequiredToReachNextLevel(Data.XP_TO_LEVEL)
end

function Progression.GetXPForStage(stage)
    return tonumber(Data.STAGE_XP[stage] or 0)
end

function Progression.GetGoldForStage(stage)
    return tonumber(Data.STAGE_GOLD[stage] or 0)
end

function Progression.GetRecruitOffer(stage)
    for _, band in ipairs(Data.RECRUIT_BANDS) do
        if stage >= band.from_stage and stage <= band.to_stage then
            return band.level, band.price
        end
    end
    return 1, 500
end

function Progression.LevelForTotalXP(total_xp)
    local level = 1
    for index, required in ipairs(Data.XP_TO_LEVEL) do
        if total_xp >= required then
            level = index
        else
            break
        end
    end
    return level
end

local function award_xp(hero, amount)
    if amount <= 0 or not is_valid_hero(hero) then
        return
    end
    if hero:GetLevel() >= #Data.XP_TO_LEVEL then
        return
    end
    hero:AddExperience(amount, DOTA_ModifyXP_Unspecified, false, true)
end

local function unique_heroes(list)
    local result = {}
    local seen = {}
    for _, hero in ipairs(list or {}) do
        if is_valid_hero(hero) then
            local id = hero:entindex()
            if not seen[id] then
                seen[id] = true
                table.insert(result, hero)
            end
        end
    end
    return result
end

-- add_gold(player_id, amount, reason) is supplied by the current-run state service.
function Progression.AwardStageClear(stage, player_id, active_heroes, bench_heroes, add_gold)
    local active_xp = Progression.GetXPForStage(stage)
    local bench_xp = math.floor(active_xp * 0.5)

    local active = unique_heroes(active_heroes)
    local active_ids = {}
    for _, hero in ipairs(active) do
        active_ids[hero:entindex()] = true
        award_xp(hero, active_xp)
    end

    for _, hero in ipairs(unique_heroes(bench_heroes)) do
        if not active_ids[hero:entindex()] then
            award_xp(hero, bench_xp)
        end
    end

    local gold = Progression.GetGoldForStage(stage)
    if add_gold ~= nil and gold > 0 then
        add_gold(player_id, gold, "stage_clear_" .. tostring(stage))
    end

    return {
        stage = stage,
        active_xp = active_xp,
        bench_xp = bench_xp,
        gold = gold,
    }
end

function Progression.Validate()
    assert(#Data.XP_TO_LEVEL == 30, "XP table must contain 30 levels")
    assert(Data.XP_TO_LEVEL[1] == 0, "level 1 cumulative XP must be zero")
    for level = 2, #Data.XP_TO_LEVEL do
        assert(Data.XP_TO_LEVEL[level] > Data.XP_TO_LEVEL[level - 1], "XP table must be strictly increasing")
    end

    local xp_1_to_29 = 0
    local gold_1_to_29 = 0
    for stage = 1, 29 do
        xp_1_to_29 = xp_1_to_29 + Progression.GetXPForStage(stage)
        gold_1_to_29 = gold_1_to_29 + Progression.GetGoldForStage(stage)
    end
    assert(xp_1_to_29 == 33720, "unexpected stage XP total")
    assert(gold_1_to_29 == 125400, "unexpected stage gold total")
end

return Progression
