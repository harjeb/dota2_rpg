local AffixService = {}

local function stageBudget(stage)
    stage = math.max(1, math.min(30, math.floor(tonumber(stage) or 1)))
    if stage <= 4 then return 0 end
    if stage <= 9 then return 1 end
    if stage <= 14 then return 2 end
    if stage <= 19 then return 3 end
    if stage <= 24 then return 4 end
    if stage <= 29 then return 5 end
    return 6
end

local function makeRng(seed)
    local state = math.floor(tonumber(seed) or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(maximum)
        state = (state * 48271) % 2147483647
        return (state % maximum) + 1
    end
end

local function shuffled(values, rng)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    for index = #result, 2, -1 do
        local other = rng(index)
        result[index], result[other] = result[other], result[index]
    end
    return result
end

local function tagSet(tags)
    local result = {}
    for _, tag in ipairs(tags or {}) do result[tostring(tag)] = true end
    return result
end

local function allowedForUnit(affix, unit)
    local allowed = affix.allowed_unit_tags or {}
    if #allowed == 0 then return true end
    local tags = tagSet(unit.tags)
    for _, tag in ipairs(allowed) do
        if tags[tostring(tag)] then return true end
    end
    return false
end

local function conflicts(affix, picked)
    for _, other in ipairs(picked or {}) do
        if affix.id == other.id then return true end
        if affix.stacking_group and affix.stacking_group ~= ""
            and affix.stacking_group == other.stacking_group then
            return true
        end
        local excluded = tagSet(affix.excluded_affixes)
        local reverse = tagSet(other.excluded_affixes)
        if excluded[other.id] or reverse[affix.id] then return true end
    end
    return false
end

local function minimumDistinctUnits(stage)
    return stage >= 25 and stage <= 29 and 3 or 0
end

function AffixService.Roll(stage, seed, enemies, definitions)
    local budget = stageBudget(stage)
    if budget == 0 then return {}, 0 end

    local rng = makeRng((tonumber(seed) or 1) + stage * 104729)
    local placements = {}
    for enemyIndex, enemy in ipairs(enemies or {}) do
        for _, affix in ipairs(definitions or {}) do
            local cost = math.floor(tonumber(affix.threat_cost) or 0)
            if cost > 0 and cost <= budget and allowedForUnit(affix, enemy) then
                table.insert(placements, {
                    enemyIndex = enemyIndex, enemy = enemy, affix = affix, cost = cost,
                })
            end
        end
    end
    placements = shuffled(placements, rng)

    local pickedByUnit, selected, usedUnits = {}, {}, {}
    local function search(position, remaining)
        if remaining == 0 then
            local distinct = 0
            for _ in pairs(usedUnits) do distinct = distinct + 1 end
            return distinct >= minimumDistinctUnits(stage)
        end
        if position > #placements then return false end

        for index = position, #placements do
            local placement = placements[index]
            if placement.cost <= remaining then
                local current = pickedByUnit[placement.enemyIndex] or {}
                local tags = tagSet(placement.enemy.tags)
                local maxPerUnit = (tags.boss or tags.final_boss) and 3 or 2
                if #current < maxPerUnit and not conflicts(placement.affix, current) then
                    table.insert(current, placement.affix)
                    pickedByUnit[placement.enemyIndex] = current
                    table.insert(selected, placement)
                    usedUnits[placement.enemyIndex] = (usedUnits[placement.enemyIndex] or 0) + 1
                    if search(index + 1, remaining - placement.cost) then return true end
                    table.remove(selected)
                    table.remove(current)
                    usedUnits[placement.enemyIndex] = usedUnits[placement.enemyIndex] - 1
                    if usedUnits[placement.enemyIndex] == 0 then usedUnits[placement.enemyIndex] = nil end
                end
            end
        end
        return false
    end

    if not search(1, budget) then
        return nil, "没有合法组合能精确使用威胁预算 " .. tostring(budget)
    end

    local result = {}
    for _, placement in ipairs(selected) do
        table.insert(result, {
            unit_index = placement.enemyIndex,
            unit = placement.enemy.unit,
            affix_id = placement.affix.id,
            threat_cost = placement.cost,
        })
    end
    return result, budget
end

function AffixService.GetOrRollForCurrentRun(runState, stage, seed, enemies, definitions)
    runState.rolledAffixes = runState.rolledAffixes or {}
    if runState.rolledAffixes[stage] ~= nil then
        return runState.rolledAffixes[stage]
    end
    local rolled, err = AffixService.Roll(stage, seed, enemies, definitions)
    if rolled == nil then return nil, err end
    runState.rolledAffixes[stage] = rolled
    return rolled
end

AffixService.StageBudget = stageBudget
return AffixService
