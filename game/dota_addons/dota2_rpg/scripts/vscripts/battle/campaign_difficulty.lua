-- One server-owned reward policy. Never multiply wallet balances, item stats,
-- purchases, sales or XP restoration. Missing metadata is the legacy default.
local Difficulty = { VERSION = 1 }
local rates = { easy = 1.5, default = 1, hard = 0.7 }
function Difficulty.Valid(value) return type(value) == "string" and rates[value] ~= nil end
function Difficulty.Name(game)
    return Difficulty.Valid(game and game.campaignDifficulty) and game.campaignDifficulty or "default"
end
function Difficulty.Multiplier(game)
    if game and game.arena and game.arena.mode ~= "campaign" then return 1 end
    return rates[Difficulty.Name(game)]
end
function Difficulty.Scale(game, value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, math.floor(value * Difficulty.Multiplier(game) + 0.5))
end
function Difficulty.Ranked(game) return Difficulty.Name(game) == "default" end
function Difficulty.Metadata(game)
    return { campaign_difficulty = Difficulty.Name(game), reward_multiplier = Difficulty.Multiplier(game),
        difficulty_version = Difficulty.VERSION, difficulty_locked = game.campaignDifficultyLocked and 1 or 0 }
end
function Difficulty.Select(game, payload)
    if type(payload) ~= "table" or game.playerId == nil or tonumber(payload.PlayerID) ~= game.playerId
        or not Difficulty.Valid(payload.difficulty) or game.campaignDifficultyLocked
        or game.phase ~= "setup" or (game.arena and game.arena.mode == "arena")
        or (game.leaderboardRun and game.leaderboardRun.startedAt) then return false end
    game.campaignDifficulty = payload.difficulty
    -- Confirmation is the run boundary, BEFORE any earned/preparation income.
    -- Retries, replay and reconnect retain this selection; arena never uses it.
    game.campaignDifficultyLocked = true
    return true
end
local function reasonIn(reason, names)
    for _, name in ipairs(names) do
        if _G[name] ~= nil and tonumber(reason) == _G[name] then return true end
    end
    return false
end
local goldReasons = { "DOTA_ModifyGold_GameTick", "DOTA_ModifyGold_Building", "DOTA_ModifyGold_HeroKill",
    "DOTA_ModifyGold_CreepKill", "DOTA_ModifyGold_RoshanKill", "DOTA_ModifyGold_CourierKill",
    "DOTA_ModifyGold_SharedGold", "DOTA_ModifyGold_AbilityGold", "DOTA_ModifyGold_WardKill",
    "DOTA_ModifyGold_Rune", "DOTA_ModifyGold_BountyRune" }
local xpReasons = { "DOTA_ModifyXP_Unspecified", "DOTA_ModifyXP_HeroKill", "DOTA_ModifyXP_CreepKill",
    "DOTA_ModifyXP_RoshanKill", "DOTA_ModifyXP_Outpost", "DOTA_ModifyXP_WisdomRune" }
local function waiting(game)
    return game.campaignDifficultyInstalled and not game.campaignDifficultyLocked
        and not (game.arena and game.arena.mode == "arena")
end
-- Carry fractional native micro-income (notably 1-gold ticks). Otherwise Hard
-- would round every 0.7 back to 1 forever. Independent reasons never transfer
-- rounding credit to a sale/purchase or another player; arena is a strict no-op.
local function nativeAmount(game, field, reason, value)
    local rate = Difficulty.Multiplier(game)
    if rate == 1 then return value end
    local carry = game[field] or {}; game[field] = carry
    local key = tostring(reason)
    local exact = value * rate + (carry[key] or 0)
    local result = math.max(0, math.floor(exact + .5))
    carry[key] = exact - result
    return result
end
function Difficulty.GoldFilter(game, event)
    if tonumber(event.player_id_const) == game.playerId and (tonumber(event.gold) or 0) > 0
        and reasonIn(event.reason_const, goldReasons) then
        event.gold = waiting(game) and 0 or nativeAmount(game, "difficultyGoldRemainders", event.reason_const, tonumber(event.gold))
    end
    return true
end
function Difficulty.XpFilter(game, event)
    if tonumber(event.player_id_const) == game.playerId and (tonumber(event.experience) or 0) > 0
        and reasonIn(event.reason_const, xpReasons) then
        event.experience = waiting(game) and 0 or nativeAmount(game, "difficultyXpRemainders", event.reason_const, tonumber(event.experience))
    end
    return true
end
function Difficulty.Publish(game, playerId)
    if playerId ~= nil and playerId ~= game.playerId then return end
    if game.playerId == nil or game.playerId < 0 then return end
    local player = PlayerResource:GetPlayer(game.playerId)
    if not player then return end
    local out = Difficulty.Metadata(game)
    out.owner_player_id = game.playerId
    out.campaign_active = not game.arena or game.arena.mode == "campaign"
    CustomGameEventManager:Send_ServerToPlayer(player, "rpg_campaign_difficulty", out)
end
function Difficulty.Install(game)
    if game.campaignDifficultyInstalled then return end
    game.campaignDifficultyInstalled = true
    CustomGameEventManager:RegisterListener("rpg_campaign_difficulty_select", function(_, payload)
        Difficulty.Select(game, payload)
        Difficulty.Publish(game, tonumber(payload and payload.PlayerID))
    end)
    local recovery = game.RequestStateRecovery
    game.RequestStateRecovery = function(self, playerId)
        local result = recovery(self, playerId)
        Difficulty.Publish(self, playerId)
        return result
    end
    for _, name in ipairs({"OnShopBuy", "OnShopRefresh", "OnBenchBuy", "OnLineupSet", "OnScrollBuy", "OnScrollUse",
        "OnShardBuy", "OnSelectLevel", "OnHeroLevels", "ValidatePrepareOrder"}) do
        local original = game[name]
        if type(original) == "function" then
            game[name] = function(self, ...)
                if waiting(self) then return false end
                return original(self, ...)
            end
        end
    end
    local start = game.OnStartBattle
    game.OnStartBattle = function(self, ...)
        if not (self.arena and self.arena.mode == "arena") and not self.campaignDifficultyLocked then
            Difficulty.Publish(self)
            return false
        end
        return start(self, ...)
    end
    local mode = GameRules:GetGameModeEntity()
    mode:SetModifyGoldFilter(function(_, event) return Difficulty.GoldFilter(game, event) end, game)
    mode:SetModifyExperienceFilter(function(_, event) return Difficulty.XpFilter(game, event) end, game)
end
return Difficulty
