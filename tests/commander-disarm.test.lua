-- Offline regression for commander-only permanent disarm and actual root hooks.
local root = TEST_REPO_ROOT or "."
local base = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"
function class() local c = {}; c.__index = c; return c end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
MODIFIER_STATE_DISARMED = 1
LUA_MODIFIER_MOTION_NONE = 0
local name = "modifier_rpg_commander_disarmed"
local linked = false
function LinkLuaModifier(n, path, motion)
    if n == name then
        assert(path == "modifiers/" .. name and motion == LUA_MODIFIER_MOTION_NONE)
        linked = true
    end
end
local noop = function() end
require = function(n)
    if n == "battle.unit_helpers" then return {IsValidUnit=function(u) return u and not u.invalid end} end
    return {Install=noop, OnSpawn=function() return false end, TrackEnemySummon=noop}
end
dofile(base .. "addon_game_mode.lua")
assert(linked, "commander modifier must be linked")
dofile(base .. "modifiers/" .. name .. ".lua")
local modifier = modifier_rpg_commander_disarmed
assert(modifier:IsHidden() and not modifier:IsPurgable() and not modifier:IsPurgeException())
assert(not modifier:RemoveOnDeath() and modifier:CheckState()[MODIFIER_STATE_DISARMED])
local entities = {}
function EntIndexToHScript(id) return entities[id] end
FindClearSpaceForUnit = noop
local function unit(id)
    local u = {mods={}, adds=0}
    function u:IsRealHero() return true end
    function u:GetUnitName() return "npc_dota_hero_wisp" end
    function u:GetPlayerOwnerID() return 0 end
    function u:HasModifier(n) return self.mods[n] ~= nil end
    function u:AddNewModifier(_, _, n, params)
        if n == name then
            assert(params.duration == nil, "must not expire")
            self.adds = self.adds + 1
        end
        self.mods[n] = params
    end
    u.SetRespawnsDisabled = noop
    entities[id] = u
    return u
end
local g = setmetatable({playerId=0, EnsureNativePlayerHero=noop, EnsureBattlefield=noop}, CDota2RpgDemo)
local commander, recruited, bench = unit(1), unit(2), unit(3)
recruited.lineupHeroName = "npc_dota_hero_wisp"
bench.benchHeroName = "npc_dota_hero_wisp"
g:OnNpcSpawned({entindex=2})
g:OnNpcSpawned({entindex=3})
assert(g.placeholderHero == nil and next(recruited.mods) == nil and next(bench.mods) == nil)
g:OnNpcSpawned({entindex=1})
assert(g.placeholderHero == commander and commander:HasModifier(name))
assert(commander:HasModifier("modifier_silence"), "preserve native silence")
for _, phase in ipairs({"setup", "fight", "result", "setup"}) do
    g.phase = phase
    assert(g:EnsureCommanderProtected())
    assert(commander:HasModifier(name) and commander:HasModifier("modifier_invulnerable"))
end
assert(commander.adds == 1, "protection must be idempotent")
commander.mods[name] = nil -- Defensive recovery if another script explicitly removes it.
g:EnsureCommanderProtected()
assert(commander.adds == 2 and commander:HasModifier(name))
assert(next(recruited.mods) == nil and next(bench.mods) == nil)
local file = assert(io.open(base .. "addon_game_mode.lua", "r"))
local source = file:read("*a"); file:close()
local _, calls = source:gsub("self:EnsureCommanderProtected%(%)", "")
assert(calls >= 4, "spawn/start/stage protection hooks must remain wired")
print("PASS commander permanent disarm: link, state, purge/death, spawn identity, phase protection, idempotence")
