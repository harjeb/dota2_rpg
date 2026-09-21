-- Endless runs are match-local. No rankings, persistence, or HTTP transport.
local Results = {}
function Results.Reset(game) game.runResults = nil end
function Results.Invalidate() end
function Results.StartBattle() end
function Results.RecordBattle() end
function Results.Finish() end
function Results.SendTerminal() end
function Results.FlushPublish() end
function Results.Resend() end
return Results
