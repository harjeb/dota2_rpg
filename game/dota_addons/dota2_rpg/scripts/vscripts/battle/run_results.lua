local Score = require("battle.run_score")
local Difficulty = require("battle.campaign_difficulty")
local Results = {}
local function now() return GameRules:GetGameTime() end
local function safeCall(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
end

function Results.Reset(game)
    game.runResults = { completed = 0, remainingMs = 0, generations = {}, eligible = true }
end
local function ensure(game)
    if not game.runResults then Results.Reset(game) end
    return game.runResults
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
    if game.runResults ~= run or not run.result or not game.runComplete or game.phase ~= "result" then return end
    player = player or safeCall(PlayerResource, "GetPlayer", game.playerId)
    if player then CustomGameEventManager:Send_ServerToPlayer(player, "rpg_run_result", run.result) end
end
function Results.Resend(game, playerId)
    if playerId ~= game.playerId then return end
    Results.Publish(game, ensure(game), safeCall(PlayerResource, "GetPlayer", playerId))
end
function Results.Finish(game, cleared, settlement)
    local run = ensure(game)
    if run.result then return run.result end
    local summary = Score.Calculate(game.runLives and game.runLives.remaining, run.completed, run.remainingMs, cleared, Difficulty.Name(game))
    summary.settlement_generation = game.settlementGeneration
    summary.status = "disabled"
    for name, value in pairs(Difficulty.Metadata(game)) do summary[name] = value end
    run.result = summary
    settlement.run_complete = 1
    for name, value in pairs(summary) do settlement[name] = value end
    return summary
end
function Results.SendTerminal(game)
    Results.Publish(game, ensure(game))
end
return Results
