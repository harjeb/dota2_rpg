local root = arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = root .. "/?.lua;" .. package.path
local Nevermore = require("issue_fixes/nevermore")
local function hero(capacity)
    local h = {name="npc_dota_hero_nevermore"}
    h.ability = {level=1, dynamic=capacity or 20, resolved=20}
    function h.ability:GetLevel() return self.level end
    function h.ability:GetSpecialValueFor(key)
        if key == "current_max_souls_tooltip" then return self.dynamic end
        assert(key == "necromastery_max_souls", "only native capacity specials")
        return self.resolved
    end
    h.modifier = {stacks=0, writes=0}
    function h.modifier:GetStackCount() return self.stacks end
    function h.modifier:SetStackCount(n) self.stacks=n; self.writes=self.writes+1 end
    function h:GetUnitName() return self.name end
    function h:FindAbilityByName(name)
        assert(name == "nevermore_necromastery"); return self.ability
    end
    function h:FindModifierByName(name)
        assert(name == "modifier_nevermore_necromastery"); return self.modifier
    end
    function h:AddNewModifier() error("must wait for native intrinsic initialization") end
    function h:HasShard() error("do not hardcode shard capacity") end
    function h:HasScepter() error("do not hardcode scepter capacity") end
    return h
end
local fielded, enemy, bench = hero(), hero(25), hero(37)
local game = {phase="setup", battleManager={teamHeroes={[2]={fielded}, [3]={enemy}}}, benchUnits={sf=bench}}
Nevermore.RefreshPreparation(game)
assert(fielded.modifier.stacks == 20 and enemy.modifier.stacks == 25 and bench.modifier.stacks == 37)
Nevermore.RefreshPreparation(game)
assert(fielded.modifier.writes == 1, "full heroes are not repeatedly mutated")
fielded.ability.dynamic=25 -- native talent-adjusted dynamic capacity
Nevermore.RefreshPreparation(game)
assert(fielded.modifier.stacks == 25)
fielded.ability.dynamic=0; fielded.ability.resolved=25
fielded.modifier.stacks=0
assert(Nevermore.ResetPreparation(game, fielded) and fielded.modifier.stacks == 25, "resolved fallback includes native upgrades")
fielded.ability.resolved=20
Nevermore.RefreshPreparation(game)
assert(fielded.modifier.stacks == 20, "capacity reductions use current native cap")
for _, bad in ipairs({0, -1, math.huge, 0/0, "20"}) do
    fielded.ability.dynamic=bad; fielded.ability.resolved=bad
    fielded.modifier.stacks=7
    assert(not Nevermore.ResetPreparation(game, fielded) and fielded.modifier.stacks == 7)
end
fielded.ability.dynamic=20
for _, phase in ipairs({"fight", "countdown", "result", "restarting"}) do
    game.phase=phase
    fielded.modifier.stacks=3; enemy.modifier.stacks=4; bench.modifier.stacks=5
    assert(not Nevermore.ResetPreparation(game, fielded))
    Nevermore.RefreshPreparation(game)
    assert(fielded.modifier.stacks == 3 and enemy.modifier.stacks == 4 and bench.modifier.stacks == 5,
        "no refill outside setup: " .. phase)
end
game.phase="setup"
Nevermore.RefreshPreparation(game)
assert(fielded.modifier.stacks == 20, "retained/restored hero refills on returning to setup")
local pending=hero(); local native=pending.modifier; pending.modifier=nil
game.benchUnits.pending=pending
assert(not Nevermore.ResetPreparation(game, pending))
pending.modifier=native; pending.ability.level=0
assert(not Nevermore.ResetPreparation(game, pending))
pending.ability.level=1
Nevermore.RefreshPreparation(game)
assert(native.stacks == 20, "tick retries native initialization")
pending.ability=nil
assert(not Nevermore.ResetPreparation(game, pending))
local other=hero(); other.name="npc_dota_hero_axe"
assert(not Nevermore.ResetPreparation(game, other) and other.modifier.stacks == 0)
local stale=hero(); function stale:IsNull() return true end
assert(not Nevermore.ResetPreparation(game, stale))
local staleModifier=hero(); function staleModifier.modifier:IsNull() return true end
assert(not Nevermore.ResetPreparation(game, staleModifier))
local broken=hero(); function broken.ability:GetSpecialValueFor() error("native handle invalidated") end
assert(not Nevermore.ResetPreparation(game, broken))
assert(not Nevermore.ResetPreparation(game, nil))
assert(not Nevermore.ResetPreparation(nil, fielded))
Nevermore.RefreshPreparation(nil)
Nevermore.RefreshPreparation({phase="setup"})
print("nevermore-preparation.test.lua: passed")
