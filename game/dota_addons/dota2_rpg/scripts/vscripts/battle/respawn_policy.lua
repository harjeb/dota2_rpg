-- Native reincarnation needs respawn permission. Ordinary round deaths do not.
local Policy = {}
local Log = require("issue_fixes.runtime_log")
local Undying = require("issue_fixes/undying")
local function write(message) pcall(Log.WriteCritical or Log.Write, message) end
local function query(object, method)
    local ok, value = pcall(function()
        return object and object[method] and object[method](object)
    end)
    if not ok then return "query_error" end
    if value == nil then return "unknown" end
    return tostring(value)
end
local function rosters(game)
    return game.battleManager and game.battleManager.teamHeroes or {}
end
local function member(game, unit)
    if unit == nil then return false end
    for _, units in pairs(rosters(game)) do
        for _, candidate in ipairs(units) do if candidate == unit then return true end end
    end
    return false
end
local function hero(unit)
    return unit ~= nil and not unit:IsNull() and unit.IsRealHero ~= nil and unit:IsRealHero()
        and unit.SetRespawnsDisabled ~= nil
end
local function safe(game, label, callback)
    if game.RunLifecycleStep then return game:RunLifecycleStep("respawn_" .. label, callback) end
    local ok, err = pcall(callback)
    if not ok then write("RespawnPolicy error=" .. tostring(err)) end
    return ok
end
local function trace(game, event, unit, allow)
    local untilRespawn = query(unit, "GetTimeUntilRespawn")
    write("RespawnPolicy event=" .. event .. " phase=" .. tostring(game.phase)
        .. " entity=" .. tostring(unit:GetEntityIndex()) .. " hero=" .. unit:GetUnitName()
        .. " reincarnating=" .. query(unit, "IsReincarnating")
        .. " allow=" .. tostring(allow) .. " disabled=" .. query(unit, "GetRespawnsDisabled")
        .. " global_enabled=" .. query(GameRules, "IsHeroRespawnEnabled") .. " until=" .. untilRespawn
        .. " alive=" .. query(unit, "IsAlive") .. " outofgame=" .. query(unit, "IsOutOfGame")
        .. " undying_return=" .. tostring(Undying.IsReturning(unit)))
    -- Capture native and preparation modifiers without changing their state.
    if unit.GetModifierCount and unit.GetModifierNameByIndex then
        local names = {}
        for index = 0, unit:GetModifierCount() - 1 do
            names[#names + 1] = tostring(unit:GetModifierNameByIndex(index))
        end
        write("RespawnPolicy modifiers event=" .. event .. " entity=" .. tostring(unit:GetEntityIndex())
            .. " names=" .. table.concat(names, ","))
    end
end
function Policy.IsReturning(unit)
    return (unit.IsReincarnating ~= nil and unit:IsReincarnating()) or Undying.IsReturning(unit)
end
function Policy.SetBattleActive(game, active)
    for team, units in pairs(rosters(game)) do
        for index, unit in ipairs(units) do
            -- One stale/failed native handle must not leave the other heroes enabled.
            safe(game, tostring(team) .. "_" .. index, function()
                if hero(unit) and (not active or unit:IsAlive()) then
                    unit:SetRespawnsDisabled(not active)
                end
            end)
        end
    end
end
function Policy.OnKilled(game, unit)
    if not member(game, unit) then return end
    safe(game, "death", function()
        if not hero(unit) then return end
        local allow = game.phase == "fight" and Policy.IsReturning(unit)
        unit.rpgDeathBeforeRespawn = true
        unit.rpgUndyingNativeReturn = allow and Undying.IsReturning(unit) or nil
        -- Native IsReincarnating includes Aegis even after the item is consumed.
        unit:SetRespawnsDisabled(not allow)
        trace(game, "death", unit, allow)
    end)
end
function Policy.OnSpawn(game, unit)
    if not member(game, unit) then return false end
    local handled = false
    safe(game, "spawn", function()
        if not hero(unit) then return end
        handled = true
        local inFight, wasDead = game.phase == "fight", unit.rpgDeathBeforeRespawn
        unit:SetRespawnsDisabled(not inFight)
        unit.rpgDeathBeforeRespawn = nil
        local pendingReturn = unit.rpgUndyingNativeReturn
        unit.rpgUndyingNativeReturn = nil
        if wasDead and pendingReturn and inFight then
            trace(game, "undying_return_before_cleanup", unit, inFight)
            if Undying.FinishNativeReturn(game, unit, pendingReturn) then
                trace(game, "undying_return_after_cleanup", unit, inFight)
            end
        end
        if wasDead and not inFight and unit:IsAlive() then
            -- Contain a late native callback after settlement. Initial preparation
            -- spawns must retain the player's freedom to position the lineup.
            unit:Stop()
            unit:SetIdleAcquire(false)
            for _, name in ipairs({"modifier_invulnerable", "modifier_rooted", "modifier_disarmed", "modifier_silence"}) do
                unit:AddNewModifier(unit, nil, name, {})
            end
        end
        if wasDead then trace(game, "spawn", unit, inFight) end
    end)
    return handled
end
return Policy
