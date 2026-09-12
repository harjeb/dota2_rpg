-- Physical shop access without tools-only/free-buy configuration. Native item
-- transaction/recipient/phase behavior is exercised by shop-state.test.lua.
package.path = "game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
function Vector(x, y, z) return { x = x, y = y, z = z } end
function IsValidEntity(entity) return entity ~= nil and not entity.removed end
function UTIL_Remove(entity) entity.removed = true end
DOTA_SHOP_HOME = 0
local universal
GameRules = { SetUseUniversalShopMode = function(_, enabled) universal = enabled end }
SendToServerConsole = function() error("shop access must not invoke cheats/free purchases") end
local Roster = require("issue_fixes.roster_access")
Roster.EnableNativeShop()
assert(universal == true)

local state, calls = {}, 0
assert(not Roster.EnsureNativeShopRange(state), "missing API must not pretend shop range exists")
SpawnDOTAShopTriggerRadiusApproximate = function() error("world is not ready") end
assert(not Roster.EnsureNativeShopRange(state))
SpawnDOTAShopTriggerRadiusApproximate = function() return nil end
assert(not Roster.EnsureNativeShopRange(state))
local failed
SpawnDOTAShopTriggerRadiusApproximate = function()
    failed = { SetShopType = function() error("failed") end }
    return failed
end
assert(not Roster.EnsureNativeShopRange(state) and failed.removed)
assert(state.nativeShopTrigger == nil, "failed trigger must remain retryable")
SpawnDOTAShopTriggerRadiusApproximate = function(origin, radius)
    calls = calls + 1
    return { origin = origin, radius = radius,
        SetShopType = function(self, value) self.shopType = value end }
end
assert(Roster.EnsureNativeShopRange(state))
local trigger = state.nativeShopTrigger
assert(trigger.shopType == DOTA_SHOP_HOME and state.nativeShopRangeError == nil)
-- Existing arena bounds, all five bench slots, and hidden assigned hero.
for _, point in ipairs({{-1950,-700}, {-2560,-120}, {-2300,-120}, {-2040,-120},
    {-2560,140}, {-2300,140}, {-1200,-675}, {-1200,675}, {1200,-675}, {1200,675}}) do
    local dx, dy = point[1] - trigger.origin.x, point[2] - trigger.origin.y
    assert(dx*dx + dy*dy < trigger.radius*trigger.radius, "shop must cover every equipment carrier")
end
assert(Roster.EnsureNativeShopRange(state) and calls == 1, "stage rebuild must reuse physical shop")
trigger.removed = true
assert(Roster.EnsureNativeShopRange(state) and calls == 2, "removed trigger must be recreated")

-- Exercise the actual install/preparation lifecycle entry points, including
-- retry after an early install cannot spawn entities. No heroes are fabricated.
local IssueFixes = require("issue_fixes.init")
local instance = setmetatable({
    inventory = { InstallEventListener = function() end },
    arena = { LoadBounds = function() end, InstallThink = function() end,
        StartPrepare = function() end },
}, IssueFixes)
local spawn = SpawnDOTAShopTriggerRadiusApproximate
SpawnDOTAShopTriggerRadiusApproximate = function() return nil end
instance:Install()
assert(instance.installed and instance.nativeShopTrigger == nil)
SpawnDOTAShopTriggerRadiusApproximate = spawn
instance:PrepareRoster(0, {}, {})
assert(instance.nativeShopTrigger ~= nil)
local installed = instance.nativeShopTrigger
instance:PrepareRoster(0, {}, {})
instance:Install()
assert(instance.nativeShopTrigger == installed and calls == 3)
-- The live bootstrap wraps RespawnPlayerRoster directly; it does not call the
-- compatibility PrepareRoster method above. Exercise that production path too.
local Bootstrap = require("issue_fixes.bootstrap")
local mode = { InitGameMode = function() end,
    RespawnPlayerRoster = function() return "roster-result", 42 end }
Bootstrap.Install(mode)
local game = setmetatable({ issueFixes = instance,
    rpgIssueFixCompat = { GetPhase = function() return "PREPARE" end },
    battleManager = { teamHeroes = { [2] = {} } },
}, { __index = mode })
instance.nativeShopTrigger.removed = true
SpawnDOTAShopTriggerRadiusApproximate = function() return nil end
local result, extra = game:RespawnPlayerRoster()
assert(result == "roster-result" and extra == 42, "wrapper preserves original results")
SpawnDOTAShopTriggerRadiusApproximate = spawn
game:RespawnPlayerRoster()
local recovered = instance.nativeShopTrigger
assert(recovered ~= installed and not recovered.removed and calls == 4)
game:RespawnPlayerRoster()
assert(instance.nativeShopTrigger == recovered and calls == 4)
print("PASS: native physical shop coverage, ordinary-client configuration, lifecycle reuse and failure retry")
