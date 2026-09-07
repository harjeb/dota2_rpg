local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
function Vector(x, y, z) return { x = x, y = y, z = z } end
function IsValidEntity(entity) return entity ~= nil and not entity.removed end
function GetGroundPosition(position) return position end
local created, inputs = {}, {}
function CreateTempTree(position, duration)
    local tree = { position = position, duration = duration, standing = true }
    function tree:IsStanding() return self.standing end
    function tree:CutDown(team) self.standing = false; self.cutTeam = team end
    created[#created + 1] = tree
    return tree
end
function UTIL_Remove(tree) tree.removed = true end
function DoEntFire(target, input) inputs[#inputs + 1] = { target, input } end
GridNav = { DestroyTreesAroundPoint = function() error("must never clear unrelated trees") end }
local Arena = require("issue_fixes.arena_controller")
local arena = Arena.new()
arena:StartPrepare({})
assert(#created == 10, "tree row must span the full 900-unit divider")
assert(created[1].position.y == -426 and created[10].position.y == 426, "both ends must be covered")
for index, tree in ipairs(created) do
    assert(tree.position.x == 0 and tree.duration == 86400, "native tree placement and lifetime")
    if index > 1 then
        assert(tree.position.y - created[index - 1].position.y <= 96, "no gaps in divider")
    end
end
arena:StartPrepare({})
arena:EnforceBounds()
assert(#created == 10, "prepare updates must not duplicate trees")
created[5].standing = false
arena:EnforceBounds()
assert(#created == 11 and created[5].removed, "cut preparation tree must be replaced")
arena:StartFight({})
for _, tree in ipairs(created) do assert(tree.removed, "battle must remove every divider tree including row ends") end
assert(next(arena.gate_trees) == nil, "old handles must not carry into next stage")
arena:EnforceBounds()
assert(#created == 11, "fight must not regrow divider")
arena:StartPrepare({})
assert(#created == 21, "next stage restores entire tree divider")
arena:StartFight({})
arena:StartFight({})
for _, input in ipairs(inputs) do
    assert(input[1] == "rpg_mid_gate_nav", "no custom visible gate entity inputs")
end
local uninitialized = Arena.new()
function EntIndexToHScript() return nil end
local order = { order_type = 1, position_x = 9000, position_y = 9000, units = {} }
assert(uninitialized:ValidateOrder(order), "movement validation loads bounds lazily")
assert(order.position_x == 1152 and order.position_y == 402, "movement clamped after lazy load")
print("PASS: native full-length tree divider, prepare repair, fight cleanup, repeat stages, and lazy bounds")
