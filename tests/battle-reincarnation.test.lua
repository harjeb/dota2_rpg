local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
function class()
    local result = {}; result.__index = result; return result
end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
function IsValidEntity(unit) return unit ~= nil and not unit.invalid end
local now = 10
GameRules = { GetGameTime = function() return now end }
require("battle.battle_manager")
local function unit(alive, reviving)
    return { alive = alive, reviving = reviving,
        IsNull = function(self) return self.invalid == true end,
        IsAlive = function(self) return self.alive end,
        IsReincarnating = function(self) return self.reviving end }
end
local result
local game = { EndBattle = function(_, winner) result = winner end }
local manager = setmetatable({}, BattleManager)
manager:constructor(game)
manager.phase, manager.battleStartedAt = "fight", 0
local ally, enemy = unit(false, true), unit(true, false)
manager.teamHeroes = { [2] = { ally }, [3] = { enemy } }
assert(manager:GetAliveCount(2) == 0, "dead Aegis holder is not a live target")
assert(not manager:CheckBattleEnd() and result == nil, "wait for allied native Aegis reincarnation")
ally.alive, ally.reviving = true, false
assert(not manager:CheckBattleEnd(), "battle continues after native rebirth")
enemy.alive, enemy.reviving = false, true
assert(not manager:CheckBattleEnd(), "enemy Wraith King also gets his native reincarnation")
ally.alive, ally.reviving = false, true
assert(not manager:CheckBattleEnd(), "two reincarnating teams are not a draw")
now = 121
assert(manager:CheckBattleEnd() and result == "timeout", "reincarnation cannot bypass battle timeout")
now, result = 10, nil
ally.reviving = false
assert(manager:CheckBattleEnd() and result == "dire", "no allied survivor or pending reincarnation is a defeat")
ally.alive = true; enemy.reviving = false
assert(manager:CheckBattleEnd() and result == "radiant", "ordinary enemy wipe is a victory")
ally.alive = false
assert(manager:CheckBattleEnd() and result == "draw", "ordinary mutual wipe is a draw")
ally.invalid, ally.reviving = true, true
assert(manager:GetAliveCount(2, true) == 0, "invalid handle cannot keep a battle alive")
manager.teamHeroes[2] = { { IsNull = function() return false end, IsAlive = function() return false end } }
assert(manager:GetAliveCount(2, true) == 0, "units without a native reincarnation API are not revived")
print("PASS: native Aegis/Wraith King reincarnation postpones wipe, with ordinary death and timeout preserved")
