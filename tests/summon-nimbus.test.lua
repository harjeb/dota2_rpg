local root=arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path=root.."/?.lua;"..package.path
local Summons=require("battle/summon_behavior")
local now=0
GameRules={GetGameTime=function() return now end}
local world={}
Entities={FindAllByClassname=function(_,name)
    if name=="npc_dota_zeus_cloud" then return world end
    return {}
end}
-- No radius lookup: native clouds can be invulnerable/unselectable and anywhere.
FindUnitsInRadius=nil
local function unit(name,team,owner,real)
    local u={name=name,team=team,owner=owner,real=real,removals=0}
    function u:IsNull() return self.removed==true end
    function u:IsRealHero() return self.real==true end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:GetOwnerEntity() return self.owner end
    function u:GetAbsOrigin() return {x=12000,y=0,z=0} end
    function u:IsControllableByAnyPlayer() return false end
    function u:GetAttackCapability() return 0 end
    function u:RemoveSelf() self.removals=self.removals+1;self.removed=true end
    function u:SetIdleAcquire() error("Nimbus native acquisition must be preserved") end
    function u:SetAcquisitionRange() error("Nimbus native acquisition must be preserved") end
    function u:ForceKill() error("cleanup must not award bounty or simulate death") end
    return u
end
local function cloud(team,owner) return unit("npc_dota_zeus_cloud",team,owner) end
for _,team in ipairs({2,3}) do
    local hero=unit("npc_dota_hero_zuus",team,nil,true)
    local bench=unit("npc_dota_hero_zuus",team,nil,true)
    local stranger=unit("npc_dota_hero_zuus",team,nil,true)
    local game={phase="fight",battleManager={teamHeroes={[team]={hero}}},benchUnits={bench},
        tacticBridge={orderGate={Execute=function() error("Nimbus must never receive orders") end}}}
    local tracked=cloud(team,hero)
    local missed=cloud(team,hero)
    local delayed=cloud(team,nil)
    local benched=cloud(team,bench)
    local unrelated=cloud(team,stranger)
    local ownerless=cloud(team,nil)
    local mismatch=cloud(team,unit("npc_dota_hero_zuus",5,nil,true))
    game.battleManager.teamHeroes[5]={mismatch.owner}
    local impostor=unit("npc_dota_zeus_cloud",team,hero,true)
    world={tracked,missed,delayed,benched,unrelated,ownerless,mismatch,impostor}
    assert(Summons.OnSpawn(game,tracked) and Summons.OnSpawn(game,delayed))
    for _,u in ipairs({tracked,delayed,unrelated,ownerless,mismatch,impostor}) do
        assert(not Summons.TrackEnemySummon(game,u),"clouds bypass broad enemy cleanup on either team")
    end
    assert(game.nimbusSummons[tracked] and not game.nimbusSummons[delayed])
    Summons.OnThink(game)
    assert(game.nimbusSummons[missed] and game.nimbusSummons[benched],"world scan finds missed and bench-owned clouds")
    assert(not game.managedSummons or next(game.managedSummons)==nil)
    local fightDelayed=cloud(team,nil)
    assert(Summons.OnSpawn(game,fightDelayed) and not game.nimbusSummons[fightDelayed])
    world[#world+1]=fightDelayed
    fightDelayed.owner=hero
    now=now+.5
    Summons.OnThink(game)
    assert(game.nimbusSummons[fightDelayed],"combat world scan resolves delayed native ownership")
    Summons.Clear(game)
    for _,u in ipairs(world) do assert(not u.removed,"fight cleanup preserves native clouds") end
    -- Remember established ownership even after the roster/owner disappears.
    tracked.owner=nil
    game.battleManager.teamHeroes[team]={}
    game.phase="setup"
    Summons.OnThink(game)
    assert(tracked.removed and missed.removed and benched.removed,"both teams' authorized clouds are removed on preparation")
    assert(not delayed.removed,"unknown ownership is not guessed")
    for _,u in ipairs({unrelated,ownerless,mismatch,impostor,hero,bench,stranger}) do
        assert(not u.removed,"unrelated units and heroes survive preparation")
    end
    -- Native ownership can arrive after preparation begins, via an intermediary.
    game.benchUnits={bench,hero}
    delayed.owner=unit("native intermediary",team,hero)
    Summons.OnThink(game)
    assert(delayed.removed,"preparation rescans resolve delayed ownership")
    -- A missed spawn first appearing during preparation is also removed.
    local prepMissed=cloud(team,nil)
    prepMissed.GetOwner=function() return bench end
    world[#world+1]=prepMissed
    Summons.OnThink(game)
    assert(prepMissed.removed,"alternate owner accessor and preparation-only discovery work")
    Summons.OnThink(game)
    for _,u in ipairs({tracked,missed,benched,delayed,prepMissed,fightDelayed}) do
        assert(u.removals==1,"repeated cleanup is idempotent")
    end
    assert(next(game.nimbusSummons)==nil)
    now=now+1
end
print("nimbus cleanup tests passed: both teams, native behavior, missed spawns, delayed owners, bench/roster scope and idempotence")
