-- Death-only campaign action. Process before wipe detection, using the shared wallet.
local RespawnPolicy = require("battle.respawn_policy")
local B = {}
local priceMultipliers = {easy = 0.75, default = 1, hard = 1.25}
function B.Cost(level, difficulty)
    level = math.max(1, math.min(30, math.floor(tonumber(level) or 1)))
    local base = 100 + 50 * level + 5 * level * level
    return math.floor(base * (priceMultipliers[difficulty] or 1) / 5 + 0.5) * 5
end
local function valid(hero)
    return hero ~= nil and not hero:IsNull() and hero.IsRealHero and hero:IsRealHero()
end
function B.IsEligible(game, hero)
    local manager = game.battleManager
    if not manager or manager.arenaActive or (game.arena and game.arena.mode == "arena")
        or not valid(hero) then return false end
    if hero:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then return false end
    for _, member in ipairs(manager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
        if member == hero then return true end
    end
    return false
end
function B.Enabled(game, hero)
    local bridge = game.tacticBridge
    if not bridge or not bridge.getRules then return false end
    for _, rule in ipairs(bridge.getRules(hero) or {}) do
        if rule.enabled ~= false and rule.enabled ~= 0 and rule.enabled ~= "0"
            and rule.action and rule.action.kind == "buyback" then return true end
    end
    return false
end
local function hardQuota(game)
    if game.campaignDifficulty ~= "hard" then return nil end
    local quota = game.hardBuybackState
    if not quota or quota.chapter ~= game.currentLevelId then
        quota = {chapter = game.currentLevelId, used = false, processing = false}
        game.hardBuybackState = quota
    end
    return quota
end
function B.BeginBattle(game)
    hardQuota(game)
    game.battleManager.buybackState = {}
    for _, hero in ipairs(game.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
        if valid(hero) then
            game.battleManager.buybackState[hero] = {position = hero:GetAbsOrigin()}
        end
    end
end
local function cooldowns(hero)
    local entries = {}
    local function capture(source)
        if source and not source:IsNull() and source.GetCooldownTimeRemaining then
            entries[#entries + 1] = {source = source, remaining = source:GetCooldownTimeRemaining()}
        end
    end
    for slot = 0, hero:GetAbilityCount() - 1 do capture(hero:GetAbilityByIndex(slot)) end
    for slot = 0, 16 do capture(hero:GetItemInSlot(slot)) end
    return entries
end
function B.Process(game)
    local manager = game.battleManager
    if not manager or manager.phase ~= "fight" or game.phase ~= "fight" or manager.arenaActive then return end
    local quota = hardQuota(game)
    if quota and (quota.used or quota.processing) then return end
    local states = manager.buybackState or {}
    manager.buybackState = states
    -- Stable lineup order also defines priority when only one buyback is affordable.
    for _, hero in ipairs(manager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
        if B.IsEligible(game, hero) then
            local state = states[hero] or {position = hero:GetAbsOrigin()}
            states[hero] = state
            if hero:IsAlive() then
                state.failed = nil
            elseif not state.used and not state.failed and not state.processing and not RespawnPolicy.IsReturning(hero)
                and B.Enabled(game, hero) and hero.RespawnHero then
                local cost = B.Cost(hero:GetLevel(), game.campaignDifficulty)
                if game:GetGoldBalance() >= cost then
                    local saved = cooldowns(hero)
                    state.processing = true
                    if quota then quota.processing = true end
                    if game:SpendGold(cost) then
                        local ok, err = pcall(function()
                            -- A death followed by buyback can occur between two tactic ticks.
                            -- Explicitly drop chase/wait/movement state before this same entity returns.
                            if game.tacticBridge.ResetUnit then game.tacticBridge:ResetUnit(hero) end
                            hero.rpgDeathBeforeRespawn = true
                            hero:SetRespawnsDisabled(false)
                            hero:SetRespawnPosition(state.position)
                            hero:RespawnHero(false, false)
                            assert(hero:IsAlive(), "RespawnHero did not revive hero")
                            state.used = true
                            if quota then quota.used = true end
                            -- Respawn policy handles the native spawn event. Restore the combat
                            -- acquisition settings and resources without refreshing cooldowns.
                            hero:SetRespawnsDisabled(false)
                            -- Native RespawnHero can grant persistent fountain protection,
                            -- which prevents normal combat outside the stock respawn flow.
                            hero:RemoveModifierByName("modifier_fountain_invulnerability")
                            hero:Stop()
                            hero:SetHealth(hero:GetMaxHealth())
                            hero:SetMana(hero:GetMaxMana())
                            for _, entry in ipairs(saved) do
                                if not entry.source:IsNull() then
                                    entry.source:EndCooldown()
                                    if entry.remaining > 0 then entry.source:StartCooldown(entry.remaining) end
                                end
                            end
                            if FindClearSpaceForUnit then FindClearSpaceForUnit(hero, state.position, true) end
                            local acquire = not hero.rpg_debug_manual_cast or hero.rpg_debug_auto_acquire == true
                            hero:SetIdleAcquire(acquire)
                            hero:SetAcquisitionRange(acquire and 4000 or 0)
                            hero.rpgDeathBeforeRespawn = nil
                        end)
                        state.processing = nil
                        if hero:IsAlive() then
                            -- Even a later cleanup error must not grant another paid revival.
                            state.used = true
                            if quota then quota.used = true end
                        else
                            state.failed = true
                            game:AddGold(cost)
                            hero:SetRespawnsDisabled(true)
                        end
                        if not ok then
                            print("[RPGBuyback] revive failed: " .. tostring(err))
                        end
                    end
                    state.processing = nil
                    if quota then
                        quota.processing = false
                        if quota.used then return end
                    end
                end
            end
        end
    end
end
return B
