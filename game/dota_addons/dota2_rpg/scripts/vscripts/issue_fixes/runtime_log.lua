local RuntimeLog = {}
local writes = 0

function RuntimeLog.StartSession(build)
    RuntimeLog.Write("BUILD " .. tostring(build) .. "; console=console.log (launch with -condebug)")
end

function RuntimeLog.Write(message)
    if writes >= 1500 then return end
    writes = writes + 1
    local time = GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
    local line = string.format("[RPGTrace t=%.2f] %s", time, tostring(message))
    -- Current Dota deprecates AppendToLogFile without throwing an error, and
    -- con_logfile is no longer a supported command. The launcher's -condebug
    -- captures print output and native Lua errors in game/dota/console.log.
    print(line)
end

return RuntimeLog
