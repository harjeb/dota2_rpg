-- Run from repository root: lua tests/endless-mode.test.lua
package.path = "game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
local callbacks, events, cleared = {}, {}, {}
GameRules = {GetGameTime = function() return 42 end, GetGameModeEntity = function() return {
    SetContextThink = function(_, name, fn, delay) assert(delay == 3); callbacks[name] = fn end,
} end}
CustomGameEventManager = {Send_ServerToAllClients = function(_, event, data) events[#events + 1] = {event, data} end}
EntIndexToHScript = function(index) return {GetPlayerID = function() return index == 10 and 0 or 1 end} end
for _, name in ipairs({"battle.tempest_double", "tactics.special_targets", "battle.neutral_recruitment", "battle.summon_behavior", "issue_fixes.tiny_tree"}) do
    local module = name
    package.loaded[name] = {Clear = function() cleared[module] = (cleared[module] or 0) + 1 end}
end
package.loaded["battle.respawn_policy"] = {SetBattleActive = function(g, value) g.active = value end}
package.loaded["battle.item_cooldowns"] = {Refresh = function(g) g.refreshed = true end}
package.loaded["issue_fixes.hero_lifecycle_log"] = {Remove = function(_, unit) unit.removed = true end}
package.loaded["battle.run_results"] = {Invalidate = function(g) g.ineligible = true end}
package.loaded["battle.fresh_run"] = {Reset = function(g) g.gold = 1500; g.ownedHeroes = {}; g.lineup = {} end}
local Mode = require("endless.mode")
local function eq(a,b, message) assert(a == b, (message or "mismatch") .. ": " .. tostring(a) .. " != " .. tostring(b)) end
local function fixture(config)
    local levels = {}
    for i = 1, 30 do levels[string.format("ch%02d", i)] = {name = "template", type = "creep", multi = 1,
        enemies = {{unit = "enemy" .. i, level = i}}, reward = {gold = 100 + i, xp_pool = 0}} end
    local g = {phase = "setup", playerId = 0, teamsSpawned = true, shopCosts = {}, endlessConfig = config,
        lineup = {"a"}, ownedHeroes = {"a", "b"}, heroData = {a = {level = 3, current_xp = 5,
            inventory = {"wand"}, inventory_states = {{name = "wand", charges = 7}}, abilities = {spell = 2}}},
        placedPositions = {a = {x = 10, y = 20}}, heroInventories = {}, heroRulesByName = {},
        benchUnits = {}, shopOffers = {{hero = "offer"}}, shopOfferText = "offer", refreshCount = 2,
        gold = 500, rolls = 0, xpCalls = 0, goldCalls = 0,
        dataLoader = {GetAllLevels = function() return levels end, GetLevel = function(_, id) return levels[id] end},
        battleManager = {teamHeroes = {[2] = {}, [3] = {}}, teamRules = {[2] = {}, [3] = {}},
            GetBattleTime = function() return 15 end, StopBattle = function(self) self.stopped = true end},
        stagePrecache = {Prefetch = function(self, id) self.last = id; self.calls = (self.calls or 0) + 1 end}}
    function g:SendStateTo(_, event, data) self.published = data end
    function g:RunLifecycleStep(_, fn) fn() end
    function g:BroadcastBattleState() end
    function g:BroadcastLevelInfo() end
    function g:BroadcastShopState() end
    function g:BroadcastHeroInfo() end
    function g:BroadcastDamageStats() end
    function g:EnsureCommanderProtected() end
    function g:SpawnBattleBarrier() self.barrier = true end
    function g:SpawnLevelEnemies(id) self.spawned = id; self.preparedEnemyLevel = id end
    function g:RespawnPlayerRoster() self.respawned = (self.respawned or 0) + 1 end
    function g:RollShop() self.rolls = self.rolls + 1 end
    function g:SyncRosterAbilities() end
    function g:SyncLiveEquipmentState() end
    function g:GetStashUnit() return nil end
    function g:GetGoldBalance() return self.gold end
    function g:SetGoldBalance(value) self.gold = value end
    function g:AddGold(value) self.goldCalls = self.goldCalls + 1; self.gold = self.gold + value end
    function g:AwardStageXp(value) self.xpCalls = self.xpCalls + 1; self.xp = value; return value / 2, 2 end
    function g:OnStartBattle() if self.stageLoadError then self:SpawnLevelEnemies(self.currentLevelId); return end; self.phase = "fight" end
    g.issueFixes = {OnBattleEnded = function() g.issueEnded = (g.issueEnded or 0) + 1 end}
    Mode.Install(g); g.preparedEnemyLevel = g.currentLevelId
    return g, levels
end
local function start(g) assert(g:OnStartBattle(10, {PlayerID = 0})) end
local function advance() local fn = assert(callbacks.Dota2RpgBackToSetup); fn(); return fn end
local g, levels = fixture()
eq(g.shopCosts.lineup_max, 8); eq(g.runLives.remaining, 5); eq(g.endlessWave, 1)
eq(g:OnSelectLevel(10, {level = "ch30"}), false)
eq(g:OnStartBattle(11, {PlayerID = 0}), false)
eq(g:OnStartBattle(10, {PlayerID = 1}), false)
eq(g:OnStartBattle(nil, {PlayerID = 0}), false)
g.stageLoading = true; eq(g:OnStartBattle(10, {PlayerID = 0}), false); eq(g.endlessSnapshot, nil); g.stageLoading = false
g:PreloadNextLevel(g.currentLevelId); eq(g.stagePrecache.calls, 1); eq(g.dataLoader:GetAllLevels(), levels)
local first = g.currentLevelId
start(g); g:EndBattle("radiant"); eq(g.phase, "result"); eq(g.endlessWave, 1)
eq(g.xpCalls, 1); eq(g.xp, 600); eq(g.goldCalls, 1); eq(g.gold, 601)
eq(g:EndBattle("radiant"), false); eq(g.goldCalls, 1); eq(g.issueEnded, 1)
eq(g.active, false); assert(g.battleManager.stopped)
local oldCallback = advance(); eq(g.endlessWave, 2); eq(g.rolls, 1); eq(g.phase, "setup")
oldCallback(); eq(g.endlessWave, 2); eq(g.rolls, 1)
-- Failure restores pre-fight assets and keeps enemy definition/offers; no consolation reward.
local waveId, definition = g.currentLevelId, levels[g.currentLevelId]
g.endlessPurchases = 2
start(g)
g.gold = 9999; g.heroData.a.level = 20; g.heroData.a.inventory_states[1].charges = 0
g.heroData.a.abilities.spell = 4; g.placedPositions.a.x = 999; g.shopOffers[1].hero = "mutated"
g.battleManager.teamHeroes[2] = {{GetItemInSlot = function() return nil end}}
g:EndBattle("dire"); eq(g.runLives.remaining, 4); eq(g.xpCalls, 1); eq(g.goldCalls, 1)
advance(); eq(g.gold, 601); eq(g.heroData.a.level, 3); eq(g.heroData.a.inventory_states[1].charges, 7)
eq(g.heroData.a.abilities.spell, 2); eq(g.placedPositions.a.x, 10); eq(g.shopOffers[1].hero, "offer")
eq(g.currentLevelId, waveId); eq(levels[waveId], definition); eq(g.rolls, 1); eq(g.endlessPurchases, 2)
-- Five failures terminate; no timer or campaign terminal/network path.
for i = 1, 4 do start(g); g:EndBattle("dire"); if i < 4 then advance() end end
eq(g.runLives.remaining, 0); eq(g.runComplete, true); eq(g.phase, "result")
eq(g.lastSettlement.life_reward_gold, 0); eq(#g.runLives.pendingItems, 0)
eq(g:OnReplayRun(11, {PlayerID = 0, settlement_generation = g.settlementGeneration}), false)
eq(g:OnReplayRun(10, {PlayerID = 0, settlement_generation = g.settlementGeneration - 1}), false)
local resets = 0; g.OnEndlessNewRun = function() resets = resets + 1 end
assert(g:OnReplayRun(10, {PlayerID = 0, settlement_generation = g.settlementGeneration}))
eq(resets, 1); eq(g.endlessRunId, 2); eq(g.endlessWave, 1); eq(g.runLives.remaining, 5); eq(g.endlessPurchases, 0)
assert(first ~= g.currentLevelId); eq(levels[first].enemies[1].unit, "enemy1")
-- Real progression crosses the campaign boundary and prefetch remains constant-sized.
local h, hlevels = fixture({xp_per_wave = 45})
for i = 1, 35 do start(h); h:EndBattle("radiant"); advance() end
eq(h.endlessWave, 36); eq(h.runComplete, false); eq(h.xpCalls, 35); eq(h.xp, 45)
eq(#h.orderedLevels, 1); eq(hlevels[h.currentLevelId].enemies[1].unit, "enemy30")
eq(hlevels[h.currentLevelId].multi, 1.3); eq(hlevels.ch30.multi, 1)
local far = Mode.Wave(h, 100000); eq(hlevels[far].multi, 4); eq(hlevels[far].enemies[1].level, 30)
eq(hlevels[far].time_limit, 120); eq(hlevels[far].type, "creep")
-- Stash items are rebuilt from immutable data rather than mutated native handles.
local s = fixture()
local stash = {items = {}}
function stash:GetItemInSlot(slot) return self.items[slot] end
function stash:TakeItem(item) self.items[item.slot] = nil end
function stash:AddItem(item) item.slot = 0; self.items[0] = item end
function stash:SwapItems(a, b) self.items[a], self.items[b] = self.items[b], self.items[a]; if self.items[b] then self.items[b].slot = b end end
local function item(name, charges, slot)
    return {name = name, charges = charges, slot = slot, IsNull = function(self) return self.removed == true end,
        GetAbilityName = function(self) return self.name end, GetItemSlot = function(self) return self.slot end,
        RemoveSelf = function(self) self.removed = true end}
end
local original = item("item_magic_wand", 8, 4); stash.items[4] = original
CreateItem = function(name) return item(name, 0) end
function s:GetStashUnit() return stash end
function s:IsLiveItem(value) return value ~= nil and not value:IsNull() end
function s:GetItemPersistentState(value) return {name = value.name, charges = value.charges} end
function s:RestoreItemPersistentState(value, state) value.charges = state.charges end
start(s); original.charges = 0
s:EndBattle("dire"); advance()
assert(original.removed); eq(stash.items[4].name, "item_magic_wand"); eq(stash.items[4].charges, 8)
assert(stash.items[4] ~= original)
local fractional = fixture({xp_per_wave = 0.1}); eq(fractional.dataLoader:GetLevel(fractional.currentLevelId).reward.xp_pool, 1)
h:BroadcastBattleState(); eq(h.published.wave, 36); eq(h.published.time_limit, 120); eq(h.published.phase, "setup")
print("endless-mode: lifecycle, ownership, retry snapshot, replay and 35-wave progression passed")
