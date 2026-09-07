local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
function Vector(x, y, z) return { x = x, y = y, z = z } end
function IsValidEntity(entity) return entity ~= nil and not entity.removed end
local markers = {
    rpg_arena_min = Vector(-1200, -450, 128),
    rpg_arena_max = Vector(1200, 450, 128),
    rpg_arena_center = Vector(0, 0, 128),
}
Entities = { FindByName = function(_, _, name)
    local position = markers[name]
    if position then return { GetAbsOrigin = function() return position end } end
end }
-- Reproduce a legacy clip brush being reported as ground above the flat arena.
function GetGroundPosition(position) return Vector(position.x, position.y, 640) end
local created, inputs = {}, {}
function CreateTempTree(position, duration)
    local tree = { position = position, duration = duration, standing = true }
    function tree:IsStanding() return self.standing end
    function tree:CutDown(team) self.standing = false; self.cutTeam = team; self.navBlocked = false end
    tree.navBlocked = true
    created[#created + 1] = tree
    return tree
end
function UTIL_Remove(tree) tree.removed = true end
function DoEntFire(target, input) inputs[#inputs + 1] = { target, input } end
GridNav = { DestroyTreesAroundPoint = function() error("must never clear unrelated trees") end }
local Arena = require("issue_fixes.arena_controller")
local arena = Arena.new()
local radiant = { GetTeamNumber = function() return DOTA_TEAM_GOODGUYS end }
local dire = { GetTeamNumber = function() return DOTA_TEAM_BADGUYS end }
arena:StartPrepare({})
assert(not arena:Contains(Vector(200, 0, 128), radiant), "prepare keeps Radiant on left")
assert(not arena:Contains(Vector(-200, 0, 128), dire), "prepare keeps Dire on right")
assert(#created == 10, "tree row must span the full 900-unit divider")
assert(created[1].position.y == -426 and created[10].position.y == 426, "both ends must be covered")
for index, tree in ipairs(created) do
    assert(tree.position.x == 0 and tree.duration == 86400, "native tree placement and lifetime")
    assert(tree.position.z == 128, "tree roots use marker ground, never legacy clip-brush height")
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
local first_row = arena.gate_trees
arena:StartFight({})
assert(arena:Contains(Vector(200, 0, 128), radiant), "fight opens logical Radiant crossing")
assert(arena:Contains(Vector(-200, 0, 128), dire), "fight opens logical Dire crossing")
for _, tree in ipairs(first_row) do
    assert(tree.cutTeam == DOTA_TEAM_GOODGUYS and not tree.navBlocked, "cut must release native tree navigation before removal")
end
for _, tree in ipairs(created) do assert(tree.removed, "battle must remove every divider tree including row ends") end
assert(next(arena.gate_trees) == nil, "old handles must not carry into next stage")
arena:EnforceBounds()
assert(#created == 11, "fight must not regrow divider")
arena:StartPrepare({})
assert(#created == 21, "next stage restores entire tree divider")
local standing = arena.gate_trees
-- The main game mode opens directly before the compatibility phase wrapper.
arena:OpenMiddleGate()
assert(arena.phase == "PREPARE", "direct open must be safe before phase wrapper runs")
arena:EnforceBounds()
assert(#created == 21, "bounds think must not regrow a directly opened divider")
for _, tree in ipairs(standing) do
    assert(tree.removed and tree.cutTeam == DOTA_TEAM_GOODGUYS and not tree.navBlocked,
        "opening cuts native navigation and removes all owned handles")
end
arena:StartFight({})
arena:StartFight({})
for _, input in ipairs(inputs) do
    assert(input[1] == "rpg_mid_gate_nav", "no custom visible gate entity inputs")
    assert(input[2] == "Disable" or input[2] == "SetNonsolid", "legacy brush must never be re-enabled")
end
-- Exercise the RemoveSelf fallback and repeated direct close/open calls.
UTIL_Remove = nil
function CreateTempTree(position, duration)
    local tree = { position = position, standing = true }
    function tree:IsStanding() return self.standing end
    function tree:CutDown() self.standing = false end
    function tree:RemoveSelf() assert(not self.standing); self.removed = true end
    return tree
end
arena:CloseMiddleGate()
local fallback = arena.gate_trees
arena:OpenMiddleGate()
for _, tree in ipairs(fallback) do assert(tree.removed, "RemoveSelf cleanup fallback") end
Entities = nil
local uninitialized = Arena.new()
function EntIndexToHScript() return nil end
local order = { order_type = 1, position_x = 9000, position_y = 9000, units = {} }
assert(uninitialized:ValidateOrder(order), "movement validation loads bounds lazily")
assert(order.position_x == 1152 and order.position_y == 402, "movement clamped after lazy load")
print("PASS: marker-height native divider, prepare repair, navigation cuts, direct open, repeated stages, and lazy bounds")
