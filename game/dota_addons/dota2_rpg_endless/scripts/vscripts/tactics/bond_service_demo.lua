local BondService = {}

local function copyArray(values)
    local result = {}
    for index, value in ipairs(values or {}) do
        result[index] = value
    end
    return result
end

-- 羁绊只根据战斗开始时的上阵英雄生成快照；不写入跨局存档。
function BondService.ComputeSnapshot(lineup, heroTags, definitions)
    local counts = {}
    local seenHeroes = {}

    for _, heroName in ipairs(lineup or {}) do
        heroName = tostring(heroName)
        if not seenHeroes[heroName] then
            seenHeroes[heroName] = true
            local seenTags = {}
            for _, tag in ipairs((heroTags or {})[heroName] or {}) do
                tag = tostring(tag)
                if tag ~= "" and not seenTags[tag] then
                    seenTags[tag] = true
                    counts[tag] = (counts[tag] or 0) + 1
                end
            end
        end
    end

    local active = {}
    for bondId, definition in pairs(definitions or {}) do
        local count = counts[bondId] or 0
        local selected = nil
        for _, threshold in ipairs(definition.thresholds or {}) do
            local needed = math.floor(tonumber(threshold.count) or 0)
            if count >= needed and (selected == nil or needed > selected.count) then
                selected = { count = needed, effects = copyArray(threshold.effects) }
            end
        end
        if selected ~= nil then
            table.insert(active, {
                id = bondId,
                name = definition.name or bondId,
                members = count,
                tier = selected.count,
                effects = selected.effects,
            })
        end
    end

    table.sort(active, function(a, b) return a.id < b.id end)
    return { counts = counts, active = active }
end

function BondService.StartBattleSnapshot(runState, lineup, heroTags, definitions)
    runState.bondSnapshot = BondService.ComputeSnapshot(lineup, heroTags, definitions)
    return runState.bondSnapshot
end

return BondService
