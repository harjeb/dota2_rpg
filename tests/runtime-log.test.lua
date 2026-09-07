local root = TEST_REPO_ROOT or "."
local original_print = print
local lines, printed = {}, 0
print = function() printed = printed + 1 end
GameRules = { GetGameTime = function() return 12.5 end }
AppendToLogFile = function(path, line)
    assert(path == "dota2_rpg_runtime.log")
    assert(line:find("[RPGTrace t=12.50]", 1, true))
    lines[#lines + 1] = line
end
local path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/runtime_log.lua"
local log = dofile(path)
for i = 1, 1510 do log.Write("test " .. i) end
assert(#lines == 1500, "file logging must be bounded per session")
assert(printed == 1500, "console diagnostics must be bounded too")
local failures = 0
AppendToLogFile = function() failures = failures + 1; error("read only") end
log = dofile(path)
log.Write("failure")
log.Write("after failure")
assert(failures == 1, "logging errors must not break gameplay or retry every tick")
AppendToLogFile = nil
log = dofile(path)
log.Write("no native API")
print = original_print
print("PASS: bounded persistent runtime trace and nonfatal logging fallback")
