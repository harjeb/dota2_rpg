local Score = require("battle.run_score")
local Json = require("lib.json")
local Config = require("data.leaderboard_config")
local Results = {}
local function now() return GameRules:GetGameTime() end
local function flag(value) return value == true or value == 1 end
local function safeCall(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
end

-- Add the 32-bit account ID as decimal digits; a Lua double cannot represent
-- SteamID64. Do not tonumber(GetSteamID()) or add the 64-bit base numerically.
function Results.SteamId(account)
    if type(account) ~= "number" or account <= 0 or account > 4294967295 or account ~= math.floor(account) then return nil end
    local base, carry, digits = "76561197960265728", account, {}
    for i = #base, 1, -1 do
        local value = tonumber(base:sub(i, i)) + carry % 10
        carry = math.floor(carry / 10) + math.floor(value / 10)
        table.insert(digits, 1, tostring(value % 10))
    end
    return table.concat(digits)
end

function Results.Reset(game)
    game.leaderboardRun = { completed = 0, remainingMs = 0, generations = {}, eligible = true }
end
local function ensure(game)
    if not game.leaderboardRun then Results.Reset(game) end
    return game.leaderboardRun
end
function Results.Invalidate(game) ensure(game).eligible = false end
function Results.StartBattle(game)
    local run = ensure(game)
    if not run.startedAt then run.startedAt = now() end
    local expected = string.format("ch%02d", run.completed + 1)
    if game.currentLevelId ~= expected or #(game.orderedLevels or {}) ~= Score.TOTAL_STAGES
        or (game.skillDebug and (game.skillDebug.active or game.skillDebug.pending))
        or (IsInToolsMode and IsInToolsMode()) or (GameRules.IsCheatMode and GameRules:IsCheatMode()) then
        run.eligible = false
    end
end
function Results.RecordBattle(game, won, elapsed, remaining)
    local run = ensure(game)
    local generation = game.settlementGeneration
    if run.generations[generation] then return end
    run.generations[generation] = true
    if game.currentLevelId ~= string.format("ch%02d", run.completed + 1)
        or (IsInToolsMode and IsInToolsMode()) or (GameRules.IsCheatMode and GameRules:IsCheatMode()) then run.eligible = false end
    if not run.startedAt then run.startedAt = now() - math.max(0, elapsed or 0) end
    if won then
        run.completed = run.completed + 1
        run.remainingMs = run.remainingMs + math.floor(math.max(0, math.min(120, remaining or (120 - elapsed))) * 1000 + .5)
    end
end
function Results.Publish(game, run, player)
    if game.leaderboardRun ~= run or not run.result or not game.runComplete or game.phase ~= "result" then return end
    player = player or safeCall(PlayerResource, "GetPlayer", game.playerId)
    if player then CustomGameEventManager:Send_ServerToPlayer(player, "rpg_leaderboard_result", run.result) end
end
function Results.Resend(game, playerId)
    if playerId ~= game.playerId then return end
    Results.Publish(game, ensure(game), safeCall(PlayerResource, "GetPlayer", playerId))
end

local function secret()
    -- Optional server-host file lives in game/dota/cfg, OUTSIDE the addon and
    -- Workshop package. Official dedicated servers use Valve's per-addon key.
    if LoadKeyValues then
        local ok, settings = pcall(LoadKeyValues, "cfg/rpg_leaderboard.kv")
        if ok and type(settings) == "table" then
            settings = settings.Leaderboard or settings
            if type(settings.submit_key) == "string" and #settings.submit_key >= 16 then return settings.submit_key end
        end
    end
    if GetDedicatedServerKeyV3 then
        local ok, value = pcall(GetDedicatedServerKeyV3, Config.key_salt)
        if ok and type(value) == "string" and #value >= 16 and not value:match("^0+$") then return value end
    end
end

local function acceptResponse(run, data)
    if type(data) ~= "table" or data.submission_id ~= run.payload.submission_id then return false end
    -- The backend contract is mapped in one place; no bearer or response body
    -- is sent to clients or logs.
    local boards = data.rankings
    if type(boards) ~= "table" or type(boards.score) ~= "table" or not tonumber(boards.score.rank) then return false end
    for _, name in ipairs({"score", "speedrun"}) do
        local board = boards[name]
        if type(board) == "table" then
            run.result[name .. "_rank"] = tonumber(board.rank) or 0
            run.result[name .. "_total"] = tonumber(board.total) or 0
            run.result[name .. "_personal_record"] = flag(board.personal_record) and 1 or 0
            run.result[name .. "_global_record"] = flag(board.global_record) and 1 or 0
            run.result[name .. "_first_entry"] = flag(board.first_entry) and 1 or 0
        end
    end
    return true
end

function Results.Submit(game, run)
    if run.submitted then return end
    run.submitted = true
    local key = secret()
    if type(Config.endpoint) ~= "string" or not Config.endpoint:match("^https://") or not key or not CreateHTTPRequestScriptVM then
        run.result.status = "disabled"
        Results.Publish(game, run)
        return
    end
    local encoded = Json.encode(run.payload)
    local attempt = 0
    local send
    local function finish(response)
        local code = tonumber(response and response.StatusCode) or 0
        if code == 200 or code == 201 then
            local ok, data = pcall(Json.decode, response.Body or "")
            if ok and acceptResponse(run, data) then
                run.result.status = "success"
                Results.Publish(game, run)
                return
            end
        elseif code >= 400 and code < 500 and code ~= 408 and code ~= 429 then
            run.result.status = "error"
            Results.Publish(game, run)
            return
        end
        if attempt < 4 then
            GameRules:GetGameModeEntity():SetContextThink("RpgRankRetry_" .. run.payload.submission_id, function()
                send()
                return nil
            end, 2 ^ attempt)
        else
            run.result.status = "error"
            Results.Publish(game, run)
        end
    end
    send = function()
        attempt = attempt + 1
        local completed = false
        local function callback(response)
            if completed then return end
            completed = true
            finish(response)
        end
        local ok = pcall(function()
            local request = CreateHTTPRequestScriptVM("POST", Config.endpoint .. "/api/v1/runs")
            request:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. key)
            request:SetHTTPRequestAbsoluteTimeoutMS(15000)
            request:SetHTTPRequestRawPostBody("application/json", encoded)
            request:Send(callback)
        end)
        if not ok then callback({StatusCode = 0}) end
    end
    send()
end

function Results.Finish(game, cleared, settlement)
    local run = ensure(game)
    if run.result then return run.result end
    local summary = Score.Calculate(game.runLives and game.runLives.remaining, run.completed, run.remainingMs, cleared)
    summary.settlement_generation = game.settlementGeneration
    summary.status = "pending"
    run.result = summary
    settlement.run_complete = 1
    for name, value in pairs(summary) do settlement[name] = value end
    local account = safeCall(PlayerResource, "GetSteamAccountID", game.playerId)
    local steamId = Results.SteamId(account)
    if not steamId or not run.eligible or (cleared and run.completed ~= Score.TOTAL_STAGES) then
        summary.status = "ineligible"
        settlement.status = summary.status
        return summary
    end
    local random = RandomInt or math.random
    local unique = (DoUniqueString and DoUniqueString("rpg") or tostring(now()))
        .. ":" .. tostring(random(1, 1000000000)) .. ":" .. tostring(random(1, 1000000000))
    local submissionId = (steamId .. ":" .. unique .. ":" .. game.settlementGeneration):gsub("[^%w._:-]", "_")
    summary.submission_id = submissionId
    run.payload = {
        submission_id = submissionId, steam_id = steamId,
        player_name = safeCall(PlayerResource, "GetPlayerName", game.playerId) or steamId,
        score = summary.score, cleared = cleared == true,
        run_duration_ms = math.max(1, math.floor((now() - (run.startedAt or now())) * 1000 + .5)),
        speedrun_time_ms = cleared and summary.remaining_time_ms or nil,
        stage_count = summary.stage_count, game_version = Config.game_version,
        remaining_hearts = summary.remaining_hearts, remaining_time_ms = summary.remaining_time_ms,
        score_version = Score.VERSION,
    }
    return summary
end
function Results.SendTerminal(game)
    local run = ensure(game)
    Results.Publish(game, run)
    if run.payload then Results.Submit(game, run) end
end
return Results
