local RuntimeLog = {}
local writes = 0
local file_failed = false

function RuntimeLog.Write(message)
    if writes >= 1500 then return end
    writes = writes + 1
    local time = GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
    local line = string.format("[RPGTrace t=%.2f] %s", time, tostring(message))
    print(line)
    if file_failed then return end
    if AppendToLogFile == nil then
        file_failed = true
        print("[RPGTrace] AppendToLogFile unavailable; console logging only")
        return
    end
    local ok, err = pcall(AppendToLogFile, "dota2_rpg_runtime.log", line .. "\n")
    if not ok then
        file_failed = true
        print("[RPGTrace] file logging unavailable: " .. tostring(err))
    end
end

return RuntimeLog
