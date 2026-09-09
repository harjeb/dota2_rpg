local root = TEST_REPO_ROOT or "."
local Double = dofile(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/battle/tempest_double.lua")
local function unit(isDouble)
    return {
        IsNull=function(self) return self.removed or false end,
        IsTempestDouble=function() return isDouble end,
        SetIdleAcquire=function(self, value) self.acquire=value end,
        SetAcquisitionRange=function(self, value) self.range=value end,
        RemoveSelf=function(self) assert(not self.removed); self.removed=true end,
    }
end
local game={phase="fight"}
local original, copy = unit(false), unit(true)
assert(not Double.OnSpawn(game,original) and original.acquire==nil, "real hero is untouched")
assert(Double.OnSpawn(game,copy,4000) and copy.acquire and copy.range==4000, "double uses native auto-acquisition")
assert(game.tempestDoubles[copy], "temporary handles tracked outside hero roster")
Double.OnThink(game)
assert(not copy.removed, "active battle preserves native summon lifetime")
local expired=unit(true)
Double.OnSpawn(game,expired)
expired.removed=true
Double.Clear(game)
assert(copy.removed and not original.removed and next(game.tempestDoubles)==nil, "settlement cleans only tracked living handles")
Double.Clear(game)
game.phase="setup"
local early=unit(true)
Double.OnSpawn(game,early)
assert(early.acquire==false and early.range==0 and not early.removed, "out-of-battle spawn is inert until callback returns")
Double.OnThink(game)
assert(early.removed, "preparation cannot retain a fighting clone")
assert(not Double.OnSpawn(game,nil) and not Double.OnSpawn(game,expired), "invalid handles ignored")
print("tempest-double tests passed")
