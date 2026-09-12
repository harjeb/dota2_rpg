-- Destructive run boundary. Resource loaders/caches and the connected player
-- survive; no roster, authored rule, native purchase or progression does.
local Fresh = {}
local function valid(u) return u ~= nil and (not u.IsNull or not u:IsNull()) end
function Fresh.Reset(game)
    require("battle.run_results").Reset(game)
    -- Invalidate closures BEFORE removing entities (native removal can re-enter).
    game.ruleGeneration = (game.ruleGeneration or 0) + 1
    -- Hero precache callbacks capture this exact table: remove pending intents
    -- in place so an old purchase cannot attach to an identical fresh offer.
    for name, state in pairs(game.recruitPrecache or {}) do
        if state ~= "ready" then game.recruitPrecache[name] = nil end
    end
    game.enemySpawnRequest = nil
    game.stageLoading, game.stageLoadError = false, nil
    if game.skillDebug then
        game.skillDebug.serial = (game.skillDebug.serial or 0) + 1
        game.skillDebug.pending = false
    end
    require("battle.respawn_policy").SetBattleActive(game, false)
    for _, name in ipairs({"battle.tempest_double", "tactics.special_targets", "battle.summon_behavior", "issue_fixes.tiny_tree"}) do
        require(name).Clear(game)
    end
    game.battleManager:StopBattle()
    local units = {}
    for _, team in pairs(game.battleManager.teamHeroes or {}) do
        for _, unit in pairs(team) do units[#units + 1] = unit end
    end
    for _, list in ipairs({game.benchUnits or {}, game.pendingEnemyCleanup or {}}) do
        for _, unit in pairs(list) do units[#units + 1] = unit end
    end
    if game.issueFixes then game.issueFixes:OnBattleEnded(units) end
    local function removeItem(item)
        if valid(item) then item:RemoveSelf() end
    end
    local function clearItems(unit)
        if not valid(unit) or not unit.GetItemInSlot then return end
        for slot = 0, 16 do
            local item = unit:GetItemInSlot(slot)
            if valid(item) then
                if unit.TakeItem then unit:TakeItem(item) end
                removeItem(item)
            end
        end
    end
    local removed = {}
    for _, unit in ipairs(units) do
        if valid(unit) and not removed[unit] then
            removed[unit] = true
            clearItems(unit)
            require("issue_fixes.hero_lifecycle_log").Remove(game, unit, "fresh_run_reset")
        end
    end
    clearItems(game:GetStashUnit())
    -- Failed reward delivery can own an entity not in any slot or container.
    for _, pending in pairs(game.runLives and game.runLives.pendingItems or {}) do
        removeItem(pending.item)
    end
    if Entities and Entities.FindAllByClassname then
        for _, drop in pairs(Entities:FindAllByClassname("dota_item_physical") or {}) do
            if valid(drop) then
                if drop.GetContainedItem then removeItem(drop:GetContainedItem()) end
                if valid(drop) then drop:RemoveSelf() end
            end
        end
    end
    local battle = game.battleManager
    battle.teamHeroes = {[DOTA_TEAM_GOODGUYS]={}, [DOTA_TEAM_BADGUYS]={}}
    battle.teamRules = {[DOTA_TEAM_GOODGUYS]={}, [DOTA_TEAM_BADGUYS]={}}
    battle.heroStates, battle.enemyTags = {}, {}
    battle.battleStartedAt, battle.phase = nil, "prepare"
    battle:ResetBattleStats()
    if game.damageStats then game.damageStats:Stop(GameRules:GetGameTime()) end
    game.damageStats = nil
    for _, field in ipairs({"ownedHeroes", "lineup", "benchUnits", "pendingEnemyCleanup", "heroData",
        "heroRulesByName", "heroInventories", "autoAbilityHeroes", "placedPositions", "shopOffers",
        "pendingNativePurchases", "nativePurchaseOrderContexts", "nativePurchaseClaimedIds",
        "nativeOrderSignatures", "nativePurchaseBaseline", "nativePurchaseObservedStates", "lifecycleErrors"}) do game[field] = {} end
    for _, field in ipairs({"nativePurchaseSelectionHero", "nativeShopTransactionPending", "rosterAbilitySnapshot",
        "equipmentSnapshot", "nativeGoldSnapshot", "lastBroadcastGold", "preparedEnemyLevel", "encounterSeed",
        "shardPurchaseBusy", "shardRestockAt", "nextDamageBroadcast", "playerLevel"}) do game[field] = nil end
    for _, field in ipairs({"heroOrder", "benchSlots", "refreshCount", "attemptBuybacks", "nativePurchaseTick",
        "nativePurchaseTransactionId", "nativePurchaseLogCount", "nextLifeRewardAttempt"}) do game[field] = 0 end
    game.scrollStock, game.scrollPurchases, game.scrollBought = {low=0, high=0}, {low=0, high=0}, {low=0, high=0}
    game.shopOfferText, game.winner = "", ""
    game.runComplete, game.runFailed, game.runLives = false, false, nil
    require("battle.run_lives").Ensure(game)
    local bridge = game.tacticBridge
    if bridge.ruleService then bridge.ruleService.state.rules = {} end
    bridge:ResetState()
    -- A slot wipe cannot remove consumed Moon Shard/Blessing, permanent stat
    -- consumables, XP or native upgrade flags. Recreate the assigned commander
    -- rather than guessing every native permanent modifier name.
    if valid(game.placeholderHero) then
        local oldCommander = game.placeholderHero
        local commander = PlayerResource:ReplaceHeroWith(game.playerId, "npc_dota_hero_wisp", 0, 0)
        assert(valid(commander) and commander ~= oldCommander, "fresh commander replacement failed")
        game.placeholderHero = commander
        clearItems(commander) -- native starting TP/neutral slots are not old rewards
        game:OnNpcSpawned({entindex=commander:entindex()})
    end
    game:InitializeRecruitmentState()
    game.goldWalletInitialized = false
    game:SetGoldBalance(game.initialGold or 500)
end
return Fresh
