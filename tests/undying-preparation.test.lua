local root=arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path=root.."/?.lua;"..package.path
local Undying=require("issue_fixes/undying")
local Summons=require("battle/summon_behavior")
local function hero(name)
    local h={name=name or "npc_dota_hero_undying"}
    h.innate={cooldown=480,ends=0}
    function h.innate:EndCooldown() self.cooldown=0;self.ends=self.ends+1 end
    function h:GetUnitName() return self.name end
    function h:FindAbilityByName(name)
        assert(name=="undying_ceaseless_dirge","never refresh other abilities")
        return self.innate
    end
    return h
end
local fielded,bench,enemy=hero(),hero(),hero()
local game={phase="setup",battleManager={teamHeroes={[2]={fielded},[3]={enemy}}},benchUnits={undying=bench}}
Undying.RefreshPreparation(game)
assert(fielded.innate.cooldown==0 and bench.innate.cooldown==0 and enemy.innate.cooldown==0)
assert(not Undying.ResetPreparation(game,hero("npc_dota_hero_axe")))
assert(not Undying.ResetPreparation(game,nil))
local pending=hero();pending.innate=nil
assert(not Undying.ResetPreparation(game,pending),"missing/not-yet-initialized innate is safe")
for _,phase in ipairs({"fight","countdown","result","restarting"}) do
    game.phase=phase;fielded.innate.cooldown=480
    assert(not Undying.ResetPreparation(game,fielded))
    Undying.RefreshPreparation(game)
    assert(fielded.innate.cooldown==480,"native combat/reincarnation cooldown is preserved in "..phase)
end
local function summon(name,owner,team)
    local u={name=name,owner=owner,team=team or 2}
    function u:GetUnitName() return self.name end
    function u:GetOwnerEntity() return self.owner end
    function u:GetTeamNumber() return self.team end
    function u:IsControllableByAnyPlayer() return false end
    function u:IsNull() return self.removed==true end
    function u:RemoveSelf() self.removed=true end
    function u:SetIdleAcquire() error("native zombie AI must not be changed") end
    return u
end
local tomb=summon("npc_dota_unit_tombstone1",fielded)
local zombie=summon("npc_dota_unit_undying_zombie",tomb)
local torso=summon("npc_dota_unit_undying_zombie_torso",nil)
local enemyZombie=summon("npc_dota_unit_undying_zombie",nil,3)
local unrelated=summon("native_soldier",fielded)
game.phase="fight"
for _,u in ipairs({tomb,zombie,torso,enemyZombie}) do
    assert(not Summons.OnSpawn(game,u),"cleanup-only summons do not enter order management")
    assert(game.undyingSummons[u] and not u.removed)
end
assert(not Summons.TrackUndyingSummon(game,unrelated))
assert(not game.managedSummons,"no native units get managed AI")
-- A native zombie missed by npc_spawned, far away, without an owner.
local missed=summon("npc_dota_unit_undying_zombie",nil)
Entities={FindAllByClassname=function(_,name)
    if name=="npc_dota_unit_undying_zombie" then return {missed} end
    return {}
end}
local late=summon("npc_dota_unit_undying_zombie_torso",nil)
function tomb:RemoveSelf()
    self.removed=true
    assert(not zombie.removed,"remove the spawner before its zombies")
    Summons.OnSpawn(game,late) -- synchronous native removal callback
end
game.phase="setup"
Summons.OnThink(game)
for _,u in ipairs({tomb,zombie,torso,enemyZombie,missed,late}) do assert(u.removed,u.name.." survives reset") end
assert(not unrelated.removed and next(game.undyingSummons)==nil)
assert(fielded.innate.cooldown==0,"preparation tick clears a late native initial cooldown")
Summons.OnThink(game) -- idempotent with stale world handles
-- All five native tombstone levels are included, but not a similar custom name.
for i=1,5 do assert(Summons.TrackUndyingSummon(game,summon("npc_dota_unit_tombstone"..i))) end
assert(not Summons.TrackUndyingSummon(game,summon("npc_dota_unit_tombstone_custom")))
Summons.Clear(game)
print("undying-preparation.test.lua: passed")
