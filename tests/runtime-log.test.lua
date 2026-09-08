local root = TEST_REPO_ROOT or "."
local original_print = print
local lines = {}
print = function(line) lines[#lines + 1] = line end
GameRules = { GetGameTime = function() return 12.5 end }
-- Real Dota reports deprecation without throwing: neither this API nor the
-- removed con_logfile command may be used as evidence of persistent logging.
AppendToLogFile = function() error("deprecated API must not be called") end
SendToServerConsole = function() error("removed con_logfile command must not be sent") end
local path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/runtime_log.lua"
local log = dofile(path)
log.StartSession("test-build")
assert(lines[1]:find("BUILD test-build", 1, true))
assert(lines[1]:find("console=console.log (launch with -condebug)", 1, true))
for i = 1, 1510 do log.Write("test " .. i) end
assert(#lines == 1500, "console diagnostics must be bounded per session")
for _, line in ipairs(lines) do assert(line:find("[RPGTrace t=12.50]", 1, true)) end
GameRules, AppendToLogFile, SendToServerConsole = nil, nil, nil
log = dofile(path)
log.Write("no native APIs")
assert(lines[#lines]:find("[RPGTrace t=0.00] no native APIs", 1, true))
print = original_print
print("PASS: bounded console trace and startup guidance without deprecated file APIs")
