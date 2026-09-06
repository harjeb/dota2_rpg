local ProgressionData = require("data.progression_data")

local ProgressionPatch = {}

function ProgressionPatch.Install(GameModeClass)
    function GameModeClass:AddXpToHero(heroName, amount)
        local data = self.heroData[heroName]
        if data == nil then
            return
        end

        data.level = math.max(1, math.min(ProgressionData.MAX_LEVEL, math.floor(tonumber(data.level) or 1)))
        if data.level >= ProgressionData.MAX_LEVEL then
            return
        end
        data.current_xp = math.max(0, math.floor(tonumber(data.current_xp) or 0))
        data.skill_points = math.max(0, math.floor(tonumber(data.skill_points) or data.level))
        data.current_xp = data.current_xp + math.max(0, math.floor(tonumber(amount) or 0))

        while data.level < ProgressionData.MAX_LEVEL do
            local need = ProgressionData.XpNeededForNextLevel(data.level)
            if need <= 0 or data.current_xp < need then
                break
            end
            data.current_xp = data.current_xp - need
            data.level = data.level + 1
            data.skill_points = data.skill_points + 1
        end

        if data.level >= ProgressionData.MAX_LEVEL then
            data.level = ProgressionData.MAX_LEVEL
            data.current_xp = 0
        end
    end

    -- 参数是“每名上阵英雄经验”，不是全队共享池。
    function GameModeClass:AwardStageXp(xpPerActiveHero)
        local fullXp = math.max(0, math.floor(tonumber(xpPerActiveHero) or 0))
        local benchXp = math.floor(fullXp * ProgressionData.BENCH_XP_RATE)
        local lineupSet = {}
        for _, heroName in ipairs(self.lineup or {}) do
            lineupSet[heroName] = true
        end

        for _, heroName in ipairs(self.ownedHeroes or {}) do
            self:AddXpToHero(heroName, lineupSet[heroName] and fullXp or benchXp)
        end
        return fullXp, benchXp
    end

    function GameModeClass:CalculateTimeBonus(baseGold, elapsed, timeLimit)
        baseGold = math.max(0, math.floor(tonumber(baseGold) or 0))
        elapsed = math.max(0, tonumber(elapsed) or 0)
        timeLimit = math.max(1, tonumber(timeLimit) or 120)
        local remainingRate = math.max(0, math.min(1, (timeLimit - elapsed) / timeLimit))
        return math.floor(baseGold * ProgressionData.TIME_BONUS_CAP * remainingRate + 0.5)
    end
end

return ProgressionPatch
