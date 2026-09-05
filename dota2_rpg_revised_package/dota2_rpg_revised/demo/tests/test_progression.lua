local root = arg[1] or "../game/scripts/vscripts"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Progression = require("progression/progression")
Progression.Validate()

assert(Progression.LevelForTotalXP(0) == 1)
assert(Progression.LevelForTotalXP(700) == 5)
assert(Progression.LevelForTotalXP(33700) == 30)

local level, price = Progression.GetRecruitOffer(5)
assert(level == 5 and price == 900)
print("progression tests passed")
