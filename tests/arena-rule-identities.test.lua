local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
local Snapshot = require("tactics/rule_snapshot")
local function hero(name,side)
    return {GetUnitName=function() return name end, GetTeamNumber=function() return side end,IsNull=function() return false end}
end
local a,b,c,d=hero("npc_dota_hero_axe",2),hero("npc_dota_hero_lina",2),hero("npc_dota_hero_axe",3),hero("npc_dota_hero_lina",3)
local manager={arenaActive=true,teamHeroes={[2]={a,b},[3]={c,d}}}
assert(Snapshot.ResolveTargetActor(manager,"arena",a,"arena:enemy:npc_dota_hero_axe:0")==c)
assert(Snapshot.ResolveTargetActor(manager,"arena",c,"arena:enemy:npc_dota_hero_axe:0")==a)
assert(Snapshot.ResolveTargetActor(manager,"arena",c,"ch01:enemy:npc_dota_hero_axe:0")==nil)
assert(Snapshot.ResolveTargetActor(manager,"arena",c,"arena:enemy:npc_dota_hero_axe:1")==nil)
assert(Snapshot.ResolveArenaActionActor(manager,a,"npc_dota_hero_lina")==b)
assert(Snapshot.ResolveArenaActionActor(manager,c,"npc_dota_hero_lina")==d)
assert(Snapshot.ResolveArenaActionActor(manager,a,"enemy:npc_dota_hero_lina:0")==d)
assert(Snapshot.ResolveArenaActionActor(manager,c,"enemy:npc_dota_hero_lina:0")==b)
manager.teamHeroes[3]={c}
assert(Snapshot.ResolveArenaActionActor(manager,c,"npc_dota_hero_lina")==nil,"missing teammate never falls back to the attacker's namesake")
manager.arenaActive=false
assert(Snapshot.ResolveTargetActor(manager,"ch01",a,"ch01:enemy:npc_dota_hero_axe:0")==c)
assert(Snapshot.ResolveTargetActor(manager,"ch01",c,"ch01:enemy:npc_dota_hero_axe:0")==nil)
print("PASS arena relative opposing targets and allied spell prerequisites, same-name isolation and campaign identity")
