-- Install the arena boundary without changing campaign implementations. All
-- public mutation paths still require their existing owner/phase validation.
local Arena = require("battle.arena_mode")
local Integration = {}
local function gate(game, name, allowed)
    local original = game[name]
    if type(original) ~= "function" then return end
    game[name] = function(self, ...)
        if not allowed(self) then return false end
        return original(self, ...)
    end
end
function Integration.Install(game)
    if game.arenaIntegrationInstalled then return end
    game.arenaIntegrationInstalled = true
    Arena.Install(game)
    for _, name in ipairs({"OnShopBuy", "OnShopRefresh", "OnBenchBuy", "OnLineupSet", "PromoteBenchHero",
        "OnSelectLevel", "OnHeroLevels", "OnReplayRun", "OnScrollBuy", "OnScrollUse"}) do
        gate(game, name, Arena.CanCampaign)
    end
    for _, name in ipairs({"OnShardBuy", "OnItemSell"}) do gate(game, name, Arena.CanBuy) end
    for _, name in ipairs({"OnItemEquip", "OnItemUnequip"}) do gate(game, name, Arena.CanEdit) end
    local starting = game.OnStartBattle
    game.OnStartBattle = function(self, ...)
        if not Arena.CanCampaign(self) and not (Arena.IsActive(self) and self.arenaLaunching) then return false end
        return starting(self, ...)
    end
    local ending = game.EndBattle
    game.EndBattle = function(self, winner, team)
        if Arena.IsActive(self) then return Arena.EndBattle(self, winner) end
        return ending(self, winner, team)
    end
    local killed = game.OnEntityKilled
    game.OnEntityKilled = function(self, event)
        if Arena.IsActive(self) and self.phase == "fight" then
            Arena.OnKilled(self, EntIndexToHScript(tonumber(event.entindex_killed) or -1))
        end
        return killed(self, event)
    end
    local state = game.OnRequestBattleState
    game.OnRequestBattleState = function(self, source, payload)
        local result = state(self, source, payload)
        Arena.Publish(self, self:ResolvePlayerId(payload))
        return result
    end
    local spawn = game.SpawnLevelEnemies
    game.SpawnLevelEnemies = function(self, id)
        if Arena.IsActive(self) then return true end -- arena controller owns both teams
        return spawn(self, id)
    end
    local level = game.dataLoader.GetLevel
    game.dataLoader.GetLevel = function(loader, id)
        if Arena.IsActive(game) and id == "arena" then
            return {id="arena",name="Arena",type="arena",time_limit=120,reward={gold=0,xp_pool=0},enemies={}}
        end
        return level(loader, id)
    end
    -- Shared storage uses a separate transfer event and compatibility phase.
    if game.issueFixes and game.issueFixes.inventoryTransfer then
        local transfer = game.issueFixes.inventoryTransfer
        local phase = transfer.get_phase
        transfer.get_phase = function(...)
            if not Arena.CanEdit(game) then return "SETTLE" end
            return phase(...)
        end
    end
end
return Integration
