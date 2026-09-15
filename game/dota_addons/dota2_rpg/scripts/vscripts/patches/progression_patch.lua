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
        -- Preserve fractional stage shares; rounding each hero would destroy pool XP.
        data.current_xp = math.max(0, tonumber(data.current_xp) or 0)
        data.skill_points = math.max(0, math.floor(tonumber(data.skill_points) or data.level))
        data.current_xp = data.current_xp + math.max(0, tonumber(amount) or 0)

        while data.level < ProgressionData.MAX_LEVEL do
            local need = ProgressionData.XpNeededForNextLevel(data.level)
            -- Repeated fractional shares can land a few ulps below a threshold.
            if need <= 0 or data.current_xp + 1e-9 < need then
                break
            end
            data.current_xp = math.max(0, data.current_xp - need)
            data.level = data.level + 1
            data.skill_points = data.skill_points + 1
        end

        if data.level >= ProgressionData.MAX_LEVEL then
            data.level = ProgressionData.MAX_LEVEL
            data.current_xp = 0
        end
    end

    -- Settlement-time ownership is authoritative, not combat entity membership.
    -- Dead, benched and capped heroes all count; a capped share is discarded by
    -- AddXpToHero, never redistributed. Missing/stale records cannot dilute XP.
    function GameModeClass:GetStageXpRecipients()
        local recipients, seen = {}, {}
        for _, heroName in ipairs(self.ownedHeroes or {}) do
            if type(heroName) == "string" and not seen[heroName]
                and type((self.heroData or {})[heroName]) == "table" then
                seen[heroName] = true
                recipients[#recipients + 1] = heroName
            end
        end
        return recipients
    end

    -- Total pool, shared equally including the bench. Fractional XP stays in
    -- progression state so neither recruitment order nor roster size loses XP.
    function GameModeClass:AwardStageXp(totalXp)
        totalXp = math.max(0, tonumber(totalXp) or 0)
        local recipients = self:GetStageXpRecipients()
        local count = #recipients
        local share = count > 0 and totalXp / count or 0
        for _, heroName in ipairs(recipients) do
            self:AddXpToHero(heroName, share)
        end
        return share, count
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
