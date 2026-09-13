package.path = "game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Summons = require("battle/summon_behavior")
local Techies = require("issue_fixes/techies")
local mutations = 0
local function unit(name, team, owner)
    local u = {name=name, team=team, owner=owner, nativeModifier=true}
    function u:IsNull() return self.removed == true end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:GetOwnerEntity() return self.owner end
    function u:IsRealHero() return self.name == "npc_dota_hero_techies" end
    function u:IsControllableByAnyPlayer() return false end
    function u:GetAttackCapability() return 0 end
    function u:RemoveSelf() self.removed = true end
    -- Any interference with native arming, damage or orders is a regression.
    for _, method in ipairs({"SetIdleAcquire", "SetAcquisitionRange", "AddNewModifier",
        "RemoveModifierByName", "ForceKill", "SetControllableByPlayer"}) do
        u[method] = function() mutations = mutations + 1 end
    end
    return u
end
local a, b, bench = unit("npc_dota_hero_techies",2), unit("npc_dota_hero_techies",3), unit("npc_dota_hero_techies",2)
local game = {phase="fight",battleManager={teamHeroes={[2]={a},[3]={b}}},benchUnits={bench}}
local function mine(owner, team) return unit("npc_dota_techies_land_mine",team or 2,owner) end
local player, enemy, late, distant = mine(a), mine(b,3), mine(nil), mine(a)
local unrelated, ownerless, benchMine = mine(unit("npc_dota_hero_techies",2)), mine(nil,3), mine(bench)
local sign = unit("npc_dota_techies_minefield_sign",2,a)
local world = {player,enemy,late,distant,unrelated,ownerless,benchMine,sign}
Entities = {FindAllByClassname=function(_, name) assert(name=="npc_dota_techies_mines" or name:find("undying")); if name=="npc_dota_techies_mines" then return world end return {} end}
assert(Summons.OnSpawn(game,player))
assert(Summons.OnSpawn(game,late))
assert(not Summons.TrackEnemySummon(game,enemy))
assert(not Summons.TrackEnemySummon(game,ownerless))
assert(not (game.enemySummons or {})[enemy])
assert(not (game.managedSummons or {})[player])
Techies.Clear(game,Summons.ResolveOwner)
assert(not player.removed and not enemy.removed, "fight clear must not destroy armed mines")
late.owner=a
Techies.Scan(game,Summons.ResolveOwner)
assert(game.techiesMines[late] and game.techiesMines[distant], "late ownership/world recovery")
-- Owner replacement/null handles cannot erase lifecycle responsibility.
a.removed=true
game.battleManager.teamHeroes[2]={}
game.phase="setup"
Summons.Clear(game)
for _, u in ipairs({player,enemy,late,distant,benchMine}) do assert(u.removed, "owned mine survived preparation") end
for _, u in ipairs({unrelated,ownerless,sign}) do assert(not u.removed, "unrelated unit removed") end
assert(next(game.techiesMines)==nil)
-- Newly spawned preparation mines are recovered on the next preparation tick.
a.removed=false
game.battleManager.teamHeroes[2]={a}
local prep=mine(a)
world[#world+1]=prep
Summons.OnThink(game)
assert(prep.removed)
-- Unknown units sharing the native base class must never qualify by classname alone.
assert(not Techies.IsMine(sign))
assert(mutations == 0, "native arming/modifiers/control must remain untouched")
print("techies-mines: native isolation, both-team owned cleanup, delayed ownership, distant scan, bench, owner replacement, phase guards PASS")
