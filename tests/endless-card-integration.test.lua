package.path = 'game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;' .. package.path
local I = require('endless.card_integration')
local function unit(team, hero)
    return {IsNull=function() return false end,IsAlive=function(self) return not self.dead end,
        GetTeamNumber=function() return team end,IsRealHero=function() return hero end}
end
local source = unit(2,true)
local form, animal, dead = unit(2,true),unit(2,false),unit(2,true)
for _,u in ipairs({form,animal,dead}) do u.endlessRebirthForm=true end
form.endlessRebirthSource=source
animal.endlessRebirthSource=unit(2,false)
dead.endlessRebirthSource=source;dead.dead=true
local game={phase='fight',endlessCardCombat={forms={[form]={},[animal]={},[dead]={}}}}
assert(#I.Forms(game,2)==2)
assert(#I.Forms(game,3)==0)
assert(I.HeroFormCount(game,2)==1,'beast souls must not prevent hero wipe')
assert(I.IsForm(game,form) and not I.IsForm(game,dead))
local calls, installs=0,0
local entity={SetDamageFilter=function(_,callback,context) installs=installs+1;game.filter=function(e)return callback(context,e)end end}
GameRules={GetGameModeEntity=function()return entity end}
package.loaded['endless.card_effects']={DamageFilter=function(g,e)assert(g==game);calls=calls+1;e.damage=e.damage*2;return e.damage>0 end}
I.Install(game);I.Install(game)
assert(installs==1)
local e={damage=3};assert(game.filter(e) and e.damage==6 and calls==1)
assert(not game.filter({damage=0}))
game.phase='setup';e={damage=3};assert(game.filter(e) and e.damage==3 and calls==2)
game.endlessCardCombat=nil;assert(#I.Forms(game)==0 and not I.IsForm(game,form))
-- Exercise the real battle manager: the last hero's soul can finish the fight,
-- but ordinary beast souls cannot hold the battle open after it expires.
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3
function class() local c={};c.__index=c;return c end
package.loaded['battle.unit_helpers']={IsValidUnit=function(u)return u and not u:IsNull()end}
package.loaded['tactics/ability_behavior']={}
package.loaded['battle.respawn_policy']={IsReturning=function()return false end}
package.loaded['battle.buyback']={Process=function()end}
require('battle.battle_manager')
source.dead=true;form.dead=false
local enemy=unit(3,true)
game.endlessCardCombat={forms={[form]={},[animal]={}}};game.phase='fight'
function game:EndBattle(winner)self.winner=winner end
local manager=setmetatable({gameMode=game,phase='fight',teamHeroes={[2]={source},[3]={enemy}}},BattleManager)
function manager:GetTimeLeft()return 30 end
assert(manager:GetAliveCount(2,true)==1)
assert(not manager:CheckBattleEnd() and not game.winner)
form.dead=true
assert(manager:CheckBattleEnd() and game.winner=='dire')
print('endless-card-integration: damage boundary and last-hero soul survival PASS')

-- Ownerless den summons use the real neutral spell bridge and cast adapter.
package.loaded['tactics/ability_behavior']=nil
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4;DOTA_UNIT_ORDER_CAST_NO_TARGET=6
GameRules.GetGameTime=function()return 10 end
entity.SetExecuteOrderFilter=function()end
Dynamic_Wrap=function(t,k)return t[k]end
CustomGameEventManager={RegisterListener=function()end}
CustomNetTables={SetTableValue=function()end}
local vectorMT={}
vectorMT.__sub=function(a,b)return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},vectorMT)end
vectorMT.__index={Length2D=function(v)return math.sqrt(v.x*v.x+v.y*v.y)end}
local function actor(id,name,team,hero)
    local u=unit(team,hero)
    function u:entindex()return id end
    function u:GetUnitName()return name end
    function u:GetAbsOrigin()return setmetatable({x=0,y=0,z=0},vectorMT)end
    function u:GetAbilityCount()return #(self.abilities or {})end
    function u:GetAbilityByIndex(i)return self.abilities[i+1]end
    function u:FindAbilityByName(n)for _,a in ipairs(self.abilities or {})do if a:GetAbilityName()==n then return a end end end
    return u
end
local den=actor(30,'npc_dota_neutral_centaur_khan',2,false)
local foe=actor(31,'npc_dota_hero_axe',3,true)
local stomp={GetAbilityName=function()return 'centaur_khan_war_stomp'end,
    GetLevel=function()return 1 end,IsNull=function()return false end,
    IsPassive=function()return false end,IsHidden=function()return false end,
    IsActivated=function()return true end,GetBehavior=function()return 4 end,
    GetAOERadius=function()return 250 end,IsFullyCastable=function()return true end,
    IsCooldownReady=function()return true end,entindex=function()return 40 end}
den.abilities={stomp}
local g={phase='fight',heroRulesByName={},endlessCardCombat={time=10,spawned={[den]={kind='den',expires=30}}},
    battleManager={teamHeroes={[2]={},[3]={foe}},teamRules={[3]={}},GetBattleTime=function()return 10 end}}
require('tactics/tactic_bridge')
local bridge=TacticBridge.new({game_mode=g});bridge:Install()
local engine=bridge.tacticEngine
local function contains(list,u)for _,v in ipairs(list)do if v==u then return true end end return false end
assert(I.IsDenCompanion(g,den) and contains(engine.get_battle_units(),den))
assert(not g.neutralRecruitUnits and #g.battleManager.teamHeroes[2]==0)
local soul=actor(32,'npc_dota_hero_axe',3,true)
soul.endlessRebirthForm=true;soul.endlessRebirthSource=foe
g.endlessCardCombat.forms={[soul]={}}
local authored={{id='authored',action={kind='attack'}}}
g.battleManager.arenaActive=true;foe.arenaRules=authored
assert(contains(engine.get_battle_units(),soul))
assert(bridge.getRules(soul)==authored,'forms preserve source rule inheritance')
g.battleManager.arenaActive=nil;foe.arenaRules=nil
local rules=bridge.getRules(den)
assert(rules[1].action.logical_id=='centaur_khan_war_stomp' and rules[#rules].action.kind=='attack')
local ctx=engine.build_context(den)
assert(contains(ctx.enemies,foe),'ownerless native caster has hostile context')
assert(engine.conditions:EvaluateUseConditions(rules[1].use_conditions,ctx),'near foe enables native stomp')
local orders={}
engine.actions.order_gate={Execute=function(_,o)orders[#orders+1]=o;return true end}
local spec=assert(engine.actions:Resolve(den,rules[1].action,ctx))
local target=engine:ResolveRuleTarget(rules[1],spec,ctx)
assert(engine.actions:Issue(den,spec,target,ctx))
assert(#orders==1 and orders[1].OrderType==6,'native no-target cast dispatch')
local nativeName=den.GetUnitName
den.GetUnitName=function()return 'npc_dota_hero_axe'end
assert(not I.IsDenCompanion(g,den));den.GetUnitName=nativeName
den.IsRealHero=function()return true end;assert(not I.IsDenCompanion(g,den))
den.IsRealHero=function()return false end
den.GetTeamNumber=function()return 4 end;assert(not I.IsDenCompanion(g,den))
den.GetTeamNumber=function()return 2 end
g.endlessCardCombat.spawned[den].kind='hound';assert(not I.IsDenCompanion(g,den))
g.endlessCardCombat.spawned[den].kind='descendant';assert(not I.IsDenCompanion(g,den))
g.endlessCardCombat.spawned[den].native_ai=true
assert(I.IsDenCompanion(g,den) and contains(engine.get_battle_units(),den),'native neutral descendants retain spell AI')
assert(bridge.getRules(den)[1].action.logical_id=='centaur_khan_war_stomp')
g.endlessCardCombat.spawned[den].kind='den';den.dead=true
assert(not contains(engine.get_battle_units(),den))
den.dead=false;g.phase='setup';assert(not contains(engine.get_battle_units(),den))
g.phase='fight';g.endlessCardCombat.time=30;assert(not contains(engine.get_battle_units(),den))
g.endlessCardCombat.time=10
game.endlessCardCombat.spawned={[den]={kind='den',expires=30}}
assert(manager:GetAliveCount(2,true)==0,'living den cannot prevent hero wipe')
assert(I.HeroFormCount(game,2)==0)
print('endless-card-integration: ownerless den native dispatch and hero wipe exclusion PASS')
