-- Offline test-only bootstrap for environments with TexLua (Lua 5.3) but no 5.1.
-- The game addon never loads this file. Prefer plain Lua 5.1 on developer machines.
-- Provide the legacy chunk-environment API used by three existing test fixtures;
-- upvaluejoin avoids changing the environment shared by unrelated closures.
if not setfenv then
    function setfenv(fn, environment)
        assert(type(fn) == "function" and type(environment) == "table")
        local index = 1
        while true do
            local name = debug.getupvalue(fn, index)
            if not name then break end
            if name == "_ENV" then
                local function envcell() return environment end
                debug.upvaluejoin(fn, index, envcell, 1)
                break
            end
            index = index + 1
        end
        return fn
    end
end
loadstring = loadstring or load
local target = assert(arg[1], "Expected a Lua test file")
table.remove(arg, 1)
arg[0] = target
dofile(target)
