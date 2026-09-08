local root = TEST_REPO_ROOT or "."
local log = dofile(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/hero_lifecycle_log.lua")
local originalPrint = print
local lines = {}
print = function(line) lines[#lines + 1] = line end
GameRules = { GetGameTime = function() return 42.125 end }
Time = function() return 90.25 end
local mode = { currentLevelId = "ch15", phase = "setup" }
local removed = false
local unit = {}
local function query(value)
    return function() assert(not removed, "queried removed entity"); return value end
end
unit.IsNull = query(false)
unit.GetEntityIndex = query(123)
unit.GetUnitName = query("npc_dota_hero_phoenix")
unit.IsAlive = query(true)
unit.IsChanneling = query(true)
unit.IsOutOfGame = query(true)
unit.GetModifierCount = query(2)
unit.GetModifierNameByIndex = function(_, index)
    return ({ "modifier_phoenix_supernova_hiding", "modifier_phoenix_sun_ray" })[index + 1]
end
unit.GetCurrentActiveAbility = query({ IsNull = query(false), GetAbilityName = query("phoenix_sun_ray") })
unit.RemoveSelf = function()
    assert(lines[#lines]:find("remove_before", 1, true), "log must precede native removal")
    removed = true
end
log.Remove(mode, unit, "lineup")
assert(#lines == 3)
assert(lines[1]:find("remove_inspect", 1, true))
assert(lines[2]:find("entity=123 name=npc_dota_hero_phoenix alive=true channel=true outofgame=true active=phoenix_sun_ray", 1, true))
assert(lines[2]:find("modifiers=2[modifier_phoenix_supernova_hiding,modifier_phoenix_sun_ray]", 1, true))
assert(lines[3]:find("remove_after", 1, true))
assert(lines[3]:find("t=42.125 real=90.250 level=ch15 phase=setup", 1, true))
local invalid = { IsNull = function() return true end, GetUnitName = function() error("invalid access") end }
assert(log.Snapshot(invalid) == "entity=invalid null=true")
assert(log.Snapshot(nil) == "entity=nil")
assert(log.Snapshot({ IsNull = function() error("stale") end }) == "entity=invalid null=?")
removed = false
local position = {}
CreateUnitByName = function(name, pos, clear, owner, owner2, team)
    assert(lines[#lines]:find("create_before", 1, true))
    assert(name == "phoenix" and pos == position and clear == true and owner == nil and owner2 == nil and team == 2)
    return unit
end
assert(log.Create(mode, "phoenix", position, 2, "lineup") == unit)
assert(lines[#lines - 1]:find("create_returned", 1, true))
assert(lines[#lines]:find("create_after", 1, true))
CreateUnitByName = function() return nil end
assert(log.Create(mode, "missing", position, 2, "bench") == nil)
assert(lines[#lines]:find("entity=nil", 1, true))
unit.RemoveSelf = function() error("native API Lua error") end
assert(not pcall(log.Remove, mode, unit, "lineup"), "must not swallow removal failures")
assert(lines[#lines]:find("remove_before", 1, true), "failed removal must not emit after")
print = originalPrint
print("PASS: lifecycle state, native operation ordering, invalid handles, and failed creation/removal")
