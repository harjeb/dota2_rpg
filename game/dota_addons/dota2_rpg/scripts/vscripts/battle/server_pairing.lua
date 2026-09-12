local Config = require("data.leaderboard_config")
local Json = require("lib.json")
local Results = require("battle.run_results")
local Pairing = {}
local sequence = 0
local function safeCall(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
end
local function globalCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function eligible()
    return globalCall(IsDedicatedServer) == true
        and globalCall(IsInToolsMode) == false
        and safeCall(GameRules, "IsCheatMode") == false
end
local function owner(game, playerId, steamId)
    return game.playerId == playerId and steamId == Config.pairing_owner_steam_id
        and Results.SteamId(safeCall(PlayerResource, "GetSteamAccountID", playerId)) == steamId
end
local function publish(game, state)
    if game.leaderboardPairing ~= state or not eligible()
        or not owner(game, state.playerId, state.steamId) then return end
    local player = safeCall(PlayerResource, "GetPlayer", state.playerId)
    if player and state.status == "success" then
        safeCall(CustomGameEventManager, "Send_ServerToPlayer", player, "rpg_server_pairing", {
            code = state.code, workshop_id = state.workshopId, status = "awaiting_confirmation",
        })
    end
end

function Pairing.Check(game, playerId, steamId)
    if type(game) ~= "table" or not owner(game, playerId, steamId) or not eligible() then return end
    if type(Config.workshop_id) ~= "string" or not Config.workshop_id:match("^[1-9][0-9]*$")
        or #Config.workshop_id > 20 or type(Config.endpoint) ~= "string"
        or not Config.endpoint:match("^https://[A-Za-z0-9][A-Za-z0-9.%-:]*/*$") then return end
    local state = game.leaderboardPairing
    if state then
        if state.playerId == playerId and state.steamId == steamId then publish(game, state) end
        return
    end
    -- Pairing must prove the Valve key, never a host's local configuration key.
    local key = globalCall(GetDedicatedServerKeyV3, Config.key_salt)
    if type(key) ~= "string" or #key < 16 or #key > 256
        or not key:match("^[A-Za-z0-9_-]+$") or key:match("^0+$")
        or type(CreateHTTPRequestScriptVM) ~= "function" then return end
    local mode = safeCall(GameRules, "GetGameModeEntity")
    if not mode or type(mode.SetContextThink) ~= "function" then return end
    sequence = sequence + 1
    local timerName = "RpgPairingRetry_" .. sequence
    local endpoint = Config.endpoint:gsub("/+$", "") .. "/api/v1/server-pairing"
    local encoded = Json.encode({workshop_id = Config.workshop_id, steam_id = steamId})
    state = {status = "pending", playerId = playerId, steamId = steamId,
        workshopId = Config.workshop_id, attempts = 0}
    game.leaderboardPairing = state
    local send
    local function active()
        return game.leaderboardPairing == state and owner(game, playerId, steamId) and eligible()
    end
    local function finish(response)
        if not active() then state.status = "error"; return end
        local status = type(response) == "table" and tonumber(response.StatusCode) or 0
        status = status or 0
        if status == 404 then state.status = "disabled"; return end
        if status == 200 then
            local ok, data = pcall(Json.decode, response.Body or "")
            if ok and type(data) == "table" and data.success == true
                and type(data.code) == "string" and #data.code == 24 and data.code ~= key
                and data.code:match("^[0-9a-f]+$") and data.workshop_id == state.workshopId
                and data.status == "awaiting_confirmation" then
                state.status, state.code = "success", data.code
                publish(game, state)
                return
            end
        end
        local transient = status == 0 or status == 408 or status == 429
            or (status >= 500 and status <= 599) or status == 200
        if transient and state.attempts < 3 then
            local ok = pcall(mode.SetContextThink, mode, timerName .. "_" .. state.attempts, function()
                send()
                return nil
            end, 2 ^ state.attempts)
            if not ok then state.status = "error" end
        else
            state.status = "error"
        end
    end
    send = function()
        if not active() then state.status = "error"; return end
        state.attempts = state.attempts + 1
        local completed = false
        local function callback(response)
            if completed then return end
            completed = true
            finish(response)
        end
        local ok = pcall(function()
            local request = CreateHTTPRequestScriptVM("POST", endpoint)
            request:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. key)
            request:SetHTTPRequestAbsoluteTimeoutMS(15000)
            request:SetHTTPRequestRawPostBody("application/json", encoded)
            if request:Send(callback) == false then callback({StatusCode = 0}) end
        end)
        if not ok then callback({StatusCode = 0}) end
    end
    send()
end
return Pairing
