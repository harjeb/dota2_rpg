local RuntimeLog = {}
local writes = 0

-- Retail VScript may restrict debug facilities. Never let diagnostic formatting
-- interrupt the protected operation or replace its original error.
function RuntimeLog.Traceback(err)
    local okText, text = pcall(tostring, err)
    if not okText then text = "Lua error (message unavailable)" end
    local okTrace, trace = pcall(function()
        if type(debug) == "table" and type(debug.traceback) == "function" then
            return debug.traceback(text, 2)
        end
    end)
    if okTrace and type(trace) == "string" then return trace end
    return text
end

function RuntimeLog.StartSession(build)
    RuntimeLog.Write("BUILD " .. tostring(build) .. "; console=console.log (launch with -condebug)")
    local ok, facility = pcall(function()
        return type(debug) .. "/" .. (type(debug) == "table" and type(debug.traceback) or "unavailable")
    end)
    RuntimeLog.Write("safe-errors-v1 debug/traceback=" .. (ok and facility or "restricted"))
end

-- Reserved for errors already throttled by their lifecycle caller; a late-round
-- failure must remain visible after the ordinary trace budget is exhausted.
function RuntimeLog.WriteCritical(message)
    local time = GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
    local line = string.format("[RPGTrace t=%.2f] %s", time, tostring(message))
    -- Current Dota deprecates AppendToLogFile without throwing an error, and
    -- con_logfile is no longer a supported command. The launcher's -condebug
    -- captures print output and native Lua errors in game/dota/console.log.
    print(line)
end

function RuntimeLog.Write(message)
    if writes >= 1500 then return end
    writes = writes + 1
    RuntimeLog.WriteCritical(message)
end

return RuntimeLog
