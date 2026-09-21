-- Endless owns transitions; the normal shop, combat, AI and roster remain in use.
local Mode = {}
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    -- Native handles are not persistent data (some test handles are tables).
    if value.IsNull or value.entindex then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for k, v in pairs(value) do
        if k ~= "inventory_entities" and k ~= "edda_retained_unit" then out[k] = copy(v, seen) end
    end
    return out
end
local function positive(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value <= 0 then return fallback end
    return value
end
local function owned(game, source, payload)
    if type(payload) ~= "table" or game.playerId == nil or tonumber(payload.PlayerID) ~= game.playerId then return false end
    if not EntIndexToHScript or not tonumber(source) then return false end
    local ok, player = pcall(EntIndexToHScript, tonumber(source))
    if not ok or not player or not player.GetPlayerID then return false end
    local valid, id = pcall(player.GetPlayerID, player)
    return valid and id == game.playerId
end
function Mode.Publish(game, player)
    game:SendStateTo(player, "rpg_endless_state", {
        wave = game.endlessWave, lives = game.runLives.remaining, max_lives = 5,
        phase = game.phase, run_id = game.endlessRunId,
        purchases_left = math.max(0, 3 - (game.endlessPurchases or 0)),
        time_limit = 120,
    })
end
function Mode.Wave(game, wave)
    local id = string.format("ch%02d_endless_r%d", wave, game.endlessRunId)
    local levels = game.dataLoader:GetAllLevels()
    if levels[id] then return id end
    local template = game.endlessTemplates[math.min(wave, #game.endlessTemplates)]
    local level = copy(template)
    -- After the campaign boundary keep the late-game template; never fall back
    -- to level-one enemies at wave 31. Values remain first-playtest settings.
    local scale = math.min(4, 1 + math.max(0, wave - 30) * 0.05)
    level.name, level.time_limit = "Endless " .. wave, 120
    level.multi = positive(level.multi, 1) * scale
    for _, entry in pairs(level.enemies or {}) do
        entry.level = math.min(30, (tonumber(entry.level) or 1) + math.min(29, math.floor((wave - 1) / 30) * 2))
        -- Boss fields are consumed only for genuinely boss-tagged heroes.
        if entry.boss_max_health then entry.boss_max_health = math.min(1000000, tonumber(entry.boss_max_health) * scale) end
        if entry.boss_health_multiplier then entry.boss_health_multiplier = math.min(100, tonumber(entry.boss_health_multiplier) * scale) end
        if entry.boss_bonus_attack_damage then entry.boss_bonus_attack_damage = math.min(10000, tonumber(entry.boss_bonus_attack_damage) * scale) end
        if entry.boss_attack_damage_pct then entry.boss_attack_damage_pct = math.min(1000, (100 + tonumber(entry.boss_attack_damage_pct)) * scale - 100) end
    end
    level.reward = level.reward or {}
    level.reward.xp_pool = math.max(1, math.floor(positive(game.endlessConfig.xp_per_wave, 600)))
    level.reward.gold = math.floor(positive(game.endlessConfig.gold_per_wave, positive(level.reward.gold, 200)))
    -- Never replace this table: StagePrecache captured it during construction.
    levels[id] = level
    return id
end
local fields = {"heroData", "heroInventories", "ownedHeroes", "lineup", "placedPositions", "heroRulesByName",
    "shopOffers", "shopOfferText", "refreshCount", "scrollPurchases", "scrollStock", "scrollBought", "heroOrder", "benchSlots"}
local function live(entity) return entity and (not entity.IsNull or not entity:IsNull()) end
local permanentModifiers = {"modifier_item_moon_shard_consumed", "modifier_item_ultimate_scepter_consumed",
    "modifier_item_aghanims_shard"}
local function roster(game)
    local units, seen = {}, {}
    local function add(unit)
        if live(unit) and not seen[unit] then seen[unit] = true; units[#units + 1] = unit end
    end
    for _, list in ipairs({game.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}, game.benchUnits or {}}) do
        for _, unit in pairs(list) do add(unit) end
    end
    for _, data in pairs(game.heroData or {}) do add(data.edda_retained_unit) end
    return units
end
local function drops()
    return Entities and Entities.FindAllByClassname and Entities:FindAllByClassname("dota_item_physical") or {}
end
local function capturePermanent(unit)
    local state = {modifiers = {}}
    for _, name in ipairs(permanentModifiers) do
        local modifier = unit.FindModifierByName and unit:FindModifierByName(name)
        if modifier then state.modifiers[name] = modifier:GetStackCount() end
    end
    for _, stat in ipairs({"Strength", "Agility", "Intellect"}) do
        if unit["GetBase" .. stat] then state[stat] = unit["GetBase" .. stat](unit) end
    end
    return state
end
local function restorePermanent(unit, state)
    for _, name in ipairs(permanentModifiers) do
        if unit.RemoveModifierByName then unit:RemoveModifierByName(name) end
        if state.modifiers[name] ~= nil then
            local modifier = assert(unit:AddNewModifier(unit, nil, name, {}), "endless retry: permanent modifier failed")
            modifier:SetStackCount(state.modifiers[name])
        end
    end
    for _, stat in ipairs({"Strength", "Agility", "Intellect"}) do
        if state[stat] ~= nil then unit["SetBase" .. stat](unit, state[stat]) end
    end
    if unit.CalculateStatBonus then unit:CalculateStatBonus(true) end
end
local function snapshot(game)
    game:SyncRosterAbilities()
    game:SyncLiveEquipmentState(true)
    local saved = {gold = game:GetGoldBalance(), stash = {}, drops = {}, permanent = {}}
    for _, unit in ipairs(roster(game)) do
        local name = unit.lineupHeroName or unit.benchHeroName
        if name then
            if name == "npc_dota_hero_witch_doctor" then require("issue_fixes.gris_gris").Capture(game, unit) end
            saved.permanent[name] = capturePermanent(unit)
        end
    end
    local commander = game:GetStashUnit()
    if live(commander) then saved.commanderPermanent = capturePermanent(commander) end
    for _, drop in pairs(drops()) do
        if live(drop) and game:IsLiveItem(drop:GetContainedItem()) then
            local item, pos = drop:GetContainedItem(), drop:GetAbsOrigin()
            saved.drops[#saved.drops + 1] = {name = item:GetAbilityName(), state = copy(game:GetItemPersistentState(item)),
                position = {x = pos.x, y = pos.y, z = pos.z}}
        end
    end
    for _, field in ipairs(fields) do saved[field] = copy(game[field]) end
    -- Gris-Gris clocks and native handles must be rebound to the restored hero.
    for _, data in pairs(saved.heroData or {}) do
        if data.grisGris then
            data.grisGris.item, data.grisGris.hero = nil, nil
            data.grisGris.restoring = true
        end
    end
    local stash = game:GetStashUnit()
    if stash and stash.GetItemInSlot then
        for slot = 0, 16 do
            local item = stash:GetItemInSlot(slot)
            if game:IsLiveItem(item) then saved.stash[#saved.stash + 1] = {name = item:GetAbilityName(), state = copy(game:GetItemPersistentState(item)), slot = slot} end
        end
    end
    return saved
end
local function clearItems(unit)
    if not unit or (unit.IsNull and unit:IsNull()) or not unit.GetItemInSlot then return end
    for slot = 0, 16 do
        local item = unit:GetItemInSlot(slot)
        if item and (not item.IsNull or not item:IsNull()) then
            unit:TakeItem(item); item:RemoveSelf()
        end
    end
end
local function restore(game, saved)
    -- Remove failed live units BEFORE assigning data, otherwise Respawn's capture
    -- would overwrite it. Recreate items from serialized charges/permanent state.
    local lifecycle = require("issue_fixes.hero_lifecycle_log")
    for _, unit in ipairs(roster(game)) do
        clearItems(unit)
        lifecycle.Remove(game, unit, "endless_retry")
    end
    -- A failed fight can move an item from any carrier to the floor or vice
    -- versa. Wipe the complete physical-item set before restoring the boundary.
    for _, drop in pairs(drops()) do
        if live(drop) then
            local item = drop:GetContainedItem()
            if live(item) then item:RemoveSelf() end
            if live(drop) then drop:RemoveSelf() end
        end
    end
    -- Inventory capture can detach items before a roster rebuild fails. Such
    -- entities have neither a slot nor a floor container, but still need disposal.
    for _, data in pairs(game.heroData or {}) do
        for _, item in pairs(data.inventory_entities or {}) do
            if live(item) then item:RemoveSelf() end
        end
        local grisItem = data.grisGris and data.grisGris.item
        if live(grisItem) then grisItem:RemoveSelf() end
    end
    game.ruleGeneration = (game.ruleGeneration or 0) + 1
    if game.tacticBridge and game.tacticBridge.ResetState then game.tacticBridge:ResetState() end
    game.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] = {}
    game.battleManager.teamRules[DOTA_TEAM_GOODGUYS] = {}
    game.benchUnits, game.autoAbilityHeroes = {}, {}
    local stash = game:GetStashUnit()
    clearItems(stash)
    for _, field in ipairs(fields) do game[field] = copy(saved[field]) end
    for _, entry in ipairs(saved.stash) do
        local item = CreateItem(entry.name, stash, stash)
        assert(item, "endless retry: stash item creation failed")
        game:RestoreItemPersistentState(item, entry.state)
        stash:AddItem(item)
        if stash.SwapItems and item.GetItemSlot and item:GetItemSlot() ~= entry.slot then stash:SwapItems(item:GetItemSlot(), entry.slot) end
    end
    for _, entry in ipairs(saved.drops or {}) do
        local item = assert(CreateItem(entry.name, nil, nil), "endless retry: world item creation failed")
        game:RestoreItemPersistentState(item, entry.state)
        local p = entry.position
        assert(CreateItemOnPositionSync(Vector(p.x, p.y, p.z), item), "endless retry: world drop creation failed")
    end
    game.endlessRestorePermanent = saved
    game.rosterAbilitySnapshot, game.equipmentSnapshot = nil, nil
    game.pendingNativePurchases, game.nativePurchaseOrderContexts = {}, {}
    game.nativePurchaseBaseline, game.nativePurchaseObservedStates = {}, {}
    game.nativeShopTransactionPending = nil
    game:SetGoldBalance(saved.gold)
end
local function newRun(game)
    game.endlessRunId = (game.endlessRunId or 0) + 1
    game.endlessWave, game.endlessPurchases = 1, 0
    game.runLives = {remaining = 5, pendingItems = {}}
    game.runComplete, game.runFailed, game.endlessSnapshot = false, false, nil
    game.currentLevelId = Mode.Wave(game, 1)
    game.orderedLevels = {game.currentLevelId}
    require("battle.run_results").Invalidate(game)
end
function Mode.Install(game)
    if game.endlessInstalled then return end
    game.endlessInstalled, game.endlessConfig = true, game.endlessConfig or {}
    game.endlessTemplates = {}
    for i = 1, 30 do
        local level = game.dataLoader:GetLevel(string.format("ch%02d", i))
        assert(level, "endless requires campaign template ch" .. i)
        game.endlessTemplates[i] = copy(level)
    end
    game.shopCosts.lineup_max = 8
    newRun(game)
    game.OnSelectLevel = function() return false end
    game.PreloadNextLevel = function(self, levelId)
        if levelId ~= self.currentLevelId then return end
        local nextId = Mode.Wave(self, self.endlessWave + 1)
        if self.stagePrecache then self.stagePrecache:Prefetch(nextId) end
    end
    local broadcast = game.BroadcastBattleState
    game.BroadcastBattleState = function(self, player)
        broadcast(self, player); Mode.Publish(self, player)
    end
    -- Extend the shared serializer locally, so roster, stash and floor items
    -- use the same public native state. Cooldowns follow the preparation reset.
    local itemProperties = {SecondaryCharges = "SecondaryCharges",
        PurchaseTime = "PurchaseTime", ItemSlot = false}
    local captureItem, restoreItem = game.GetItemPersistentState, game.RestoreItemPersistentState
    if captureItem and restoreItem then
        game.GetItemPersistentState = function(self, item)
            local state = captureItem(self, item)
            for getter in pairs(itemProperties) do
                if item["Get" .. getter] then state[getter] = item["Get" .. getter](item) end
            end
            return state
        end
        game.RestoreItemPersistentState = function(self, item, state)
            restoreItem(self, item, state)
            for getter, setter in pairs(itemProperties) do
                if setter and state[getter] ~= nil and item["Set" .. setter] then
                    item["Set" .. setter](item, state[getter])
                end
            end
            -- Stash and world items are not yet attached at this point.
            local owner = item.GetCaster and item:GetCaster()
            if state.ItemSlot ~= nil and live(owner) and owner.SwapItems and item.GetItemSlot
                and item:GetItemSlot() >= 0 and item:GetItemSlot() ~= state.ItemSlot then
                owner:SwapItems(item:GetItemSlot(), state.ItemSlot)
            end
        end
    end
    local respawn = game.RespawnPlayerRoster
    game.RespawnPlayerRoster = function(self, ...)
        respawn(self, ...)
        local saved = self.endlessRestorePermanent
        if not saved then return end
        for _, unit in ipairs(roster(self)) do
            local name = unit.lineupHeroName or unit.benchHeroName
            local state = saved.permanent[name]
            if state then
                -- The project supports one Edda consumption, via ConsumeItem.
                -- Replay on the fresh hero before restoring the captured base stats.
                if saved.heroData[name].edda_consumed then
                    local edda = assert(CreateItem("item_eldwurms_edda", unit, unit))
                    assert(unit.ConsumeItem, "endless retry: native Edda consumption unavailable")
                    local wasSelling = self.itemSaleInProgress
                    self.itemSaleInProgress = true
                    local ok, err = pcall(unit.ConsumeItem, unit, edda)
                    self.itemSaleInProgress = wasSelling
                    assert(ok and not live(edda), "endless retry: native Edda replay failed: " .. tostring(err))
                end
                restorePermanent(unit, state)
            end
        end
        if saved.commanderPermanent then restorePermanent(self:GetStashUnit(), saved.commanderPermanent) end
        self.endlessRestorePermanent = nil
    end
    local start = game.OnStartBattle
    game.OnStartBattle = function(self, source, payload)
        if not owned(self, source, payload) or self.phase ~= "setup" or self.runComplete then return false end
        if not self.teamsSpawned or self.stageLoading or #self.lineup == 0 then return false end
        if self.stageLoadError or (self.stagePrecache and self.preparedEnemyLevel ~= self.currentLevelId) then
            start(self, source, payload); return false
        end
        local saved = snapshot(self)
        start(self, source, payload)
        if self.phase ~= "fight" then return false end
        self.endlessSnapshot = saved
        return true
    end
    game.OnReplayRun = function(self, source, payload)
        if not owned(self, source, payload) or self.phase ~= "result" or not self.runComplete
            or tonumber(payload.settlement_generation) ~= self.settlementGeneration then return false end
        self.phase = "restarting"
        self.settlementGeneration = (self.settlementGeneration or 0) + 1
        local ok, err = pcall(require("battle.fresh_run").Reset, self)
        if not ok then
            self.phase, self.runComplete = "result", true
            self.endlessResetError = tostring(err); self:BroadcastBattleState(); return false
        end
        newRun(self)
        -- Cards can observe run_id or supply this callback; no card internals here.
        if self.OnEndlessNewRun then self:OnEndlessNewRun() end
        self.phase, self.winner = "setup", ""
        self:EnsureCommanderProtected()
        self:SpawnLevelEnemies(self.currentLevelId)
        self:RespawnPlayerRoster(); self:SpawnBattleBarrier(); self:RollShop()
        self:BroadcastLevelInfo(); self:BroadcastBattleState(); self:BroadcastHeroInfo(); self:BroadcastShopState()
        self:BroadcastDamageStats()
        return true
    end
    game.EndBattle = function(self, winner)
        if self.phase ~= "fight" then return false end
        self.phase = "result" -- Exactly-once claim before any callback.
        self.settlementGeneration = (self.settlementGeneration or 0) + 1
        local generation, won = self.settlementGeneration, winner == "radiant"
        local function step(name, fn) self:RunLifecycleStep("endless_" .. name, fn) end
        step("respawn_policy", function() require("battle.respawn_policy").SetBattleActive(self, false) end)
        local elapsed = self.battleManager:GetBattleTime()
        step("battle_stop", function() self.battleManager:StopBattle() end)
        for _, name in ipairs({"battle.tempest_double", "tactics.special_targets", "battle.neutral_recruitment", "battle.summon_behavior", "issue_fixes.tiny_tree"}) do
            step(name, function() require(name).Clear(self, false) end)
        end
        step("issue_fixes", function()
            if self.issueFixes then
                local units = {}
                for _, team in pairs(self.battleManager.teamHeroes) do for _, unit in pairs(team) do units[#units + 1] = unit end end
                for _, unit in pairs(self.benchUnits or {}) do units[#units + 1] = unit end
                self.issueFixes:OnBattleEnded(units)
            end
        end)
        step("cooldowns", function() require("battle.item_cooldowns").Refresh(self) end)
        if self.damageStats then step("damage", function() self.damageStats:Stop(GameRules:GetGameTime()); self:BroadcastDamageStats() end) end
        local reward = self.dataLoader:GetLevel(self.currentLevelId).reward
        local gold, xp, share, count = 0, 0, 0, 0
        if won then
            gold, xp = reward.gold, reward.xp_pool
            self:AddGold(gold)
            share, count = self:AwardStageXp(xp)
        else
            self.runLives.remaining = math.max(0, self.runLives.remaining - 1)
        end
        self.runFailed = self.runLives.remaining == 0
        self.runComplete, self.winner = self.runFailed, winner
        local settlement = {settlement_generation = generation, level = self.currentLevelId, wave = self.endlessWave,
            winner = winner, gold = gold, base_gold = gold, time_bonus = 0, xp_pool = xp,
            xp_per_owned_hero = share or 0, xp_recipient_count = count or 0,
            xp_per_active_hero = share or 0, xp_per_bench_hero = share or 0,
            stars = won and 1 or 0, clear_time = math.floor(elapsed), loot_text = "",
            lives_remaining = self.runLives.remaining, max_lives = 5, life_reward_gold = 0,
            life_reward_items = "", life_reward_pending = 0, run_failed = self.runFailed and 1 or 0}
        self.lastSettlement = settlement
        self:BroadcastBattleState(); self:BroadcastShopState()
        CustomGameEventManager:Send_ServerToAllClients("rpg_settlement", settlement)
        if self.runComplete then return true end
        local pending = true
        GameRules:GetGameModeEntity():SetContextThink("Dota2RpgBackToSetup", function()
            if not pending or self.phase ~= "result" or self.runComplete or self.settlementGeneration ~= generation then return nil end
            pending = false
            local ok, err = pcall(function()
                if won then
                    self.endlessWave = self.endlessWave + 1
                    self.currentLevelId = Mode.Wave(self, self.endlessWave)
                    self.orderedLevels = {self.currentLevelId}
                    self.refreshCount, self.scrollPurchases = 0, {low = 0, high = 0}
                    self.endlessSnapshot = nil
                else
                    assert(self.endlessSnapshot, "endless retry missing successful-start snapshot")
                    restore(self, self.endlessSnapshot)
                end
                self.phase, self.winner = "setup", ""
                self:EnsureCommanderProtected(); self:SpawnLevelEnemies(self.currentLevelId)
                self:RespawnPlayerRoster(); self:SpawnBattleBarrier()
                if won then self:RollShop() end
                self:BroadcastLevelInfo(); self:BroadcastBattleState(); self:BroadcastHeroInfo(); self:BroadcastShopState()
            end)
            if not ok then
                -- Never allow a partially restored roster to start another fight.
                self.phase = "result"
                self.endlessRestoreError = tostring(err)
                self:BroadcastBattleState()
                error(err)
            end
            return nil
        end, 3)
        return true
    end
end
return Mode
