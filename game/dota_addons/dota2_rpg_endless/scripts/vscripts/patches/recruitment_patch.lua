local ProgressionData = require("data.progression_data")
local HeroPrecache = require("issue_fixes/hero_precache")

local RecruitmentPatch = {}

-- 调用一次：RecruitmentPatch.Install(CDota2RpgDemo)
function RecruitmentPatch.Install(GameModeClass)
    function GameModeClass:InitializeRecruitmentState()
        self.freeRecruitChoices = ProgressionData.STARTER_FREE_RECRUITS
        self.gold = ProgressionData.INITIAL_GOLD
    end

    function GameModeClass:RollRecruitLevel()
        local stage = ProgressionData.StageNumber(self.currentLevelId)
        return ProgressionData.GetRecruitBand(stage).level
    end

    -- 售价 = 招募等级基础价 × 品质倍率（普通 1.0 / 精良 1.2 / 史诗 1.5 / 传说 2.0）。
    -- 品质自带魔晶/神杖效果，同时体现在价格上；UI 只展示最终售价。
    function GameModeClass:PriceFor(level, quality)
        return ProgressionData.PriceFor(level, quality) or 500
    end

    function GameModeClass:OnShopBuy(_, payload)
        if self.phase ~= "setup" then
            return
        end

        local heroName = payload ~= nil and tostring(payload.hero or "") or ""
        local offer = self:FindOffer(heroName)
        if offer == nil then
            return
        end

        for _, owned in ipairs(self.ownedHeroes) do
            if owned == heroName then
                return
            end
        end

        -- 当前可拥有数量 = 5 个首发位置 + 已购买的替补位置。
        local currentCapacity = self.shopCosts.lineup_max + self.benchSlots
        if #self.ownedHeroes >= currentCapacity then
            return
        end

        if not HeroPrecache.Request(self, heroName, function()
            if self.phase == "setup" and self:FindOffer(heroName) == offer then
                self:OnShopBuy(nil, {hero=heroName})
            end
        end) then return end

        local useFreeChoice = (tonumber(self.freeRecruitChoices) or 0) > 0
        local chargedPrice = useFreeChoice and 0 or math.max(0, math.floor(tonumber(offer.price) or 0))
        if chargedPrice > 0 and not self:SpendGold(chargedPrice) then
            return
        end

        -- 先完成全部服务端校验，再消耗免费次数；失败不会吞次数。
        table.insert(self.ownedHeroes, heroName)
        local data = self:GetHeroData(heroName)
        data.level = math.max(1, math.min(ProgressionData.MAX_LEVEL, math.floor(tonumber(offer.level) or 1)))
        data.current_xp = 0
        data.quality = tostring(offer.quality or "common")
        data.skill_points = data.level
        data.inventory = data.inventory or {}

        if useFreeChoice then
            self.freeRecruitChoices = self.freeRecruitChoices - 1
        end

        -- 不写空规则表；RespawnPlayerRoster/新版 RuleService 应创建默认规则。
        self:RespawnPlayerRoster()
        self:BroadcastShopState()
    end
end

return RecruitmentPatch
