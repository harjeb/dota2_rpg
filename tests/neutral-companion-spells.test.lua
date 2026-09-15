-- Exercise real bridge admission, native rule generation and allegiance contexts.
local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4;DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8
DOTA_ABILITY_BEHAVIOR_AUTOCAST=4096
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1;DOTA_UNIT_TARGET_TEAM_ENEMY=2
GameRules={GetGameTime=function() return 10 end,GetGameModeEntity=function() return {SetExecuteOrderFilter=function() end} end}
Dynamic_Wrap=function(t,k) return t[k] end
CustomGameEventManager={RegisterListener=function() end}
CustomNetTables={SetTableValue=function() end}
local function unit(id,name,team)
    local u={id=id,name=name,team=team,alive=true,abilities={}}
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:IsRealHero() return self.hero==true end
    function u:GetOwnerEntity() return self.owner end
    function u:GetAbsOrigin() return {x=0,y=0,z=0} end
    function u:GetAbilityCount() return #self.abilities end
    function u:GetAbilityByIndex(i) return self.abilities[i+1] end
    function u:FindAbilityByName(name) for _,a in ipairs(self.abilities) do if a:GetAbilityName()==name then return a end end end
    return u
end
local function spell(name,behavior,passive)
    return {GetAbilityName=function() return name end,GetLevel=function() return 1 end,
        IsNull=function() return false end,IsPassive=function() return passive==true end,
        IsHidden=function() return false end,IsActivated=function() return true end,
        GetBehavior=function() return behavior end,GetAOERadius=function() return 250 end,
        GetAbilityTargetTeam=function() return 1 end}
end
local owner=unit(1,'npc_dota_hero_chen',2);owner.hero=true
local enemy=unit(2,'npc_dota_hero_axe',3);enemy.hero=true
local creep=unit(3,'npc_rpg_recruit_centaur_khan',2);creep.owner=owner
creep.abilities={spell('centaur_khan_war_stomp',4),spell('centaur_khan_endurance_aura',0,true),spell('ogre_magi_frost_armor',4096+8)}
local ordinary=unit(4,'npc_dota_furion_treant',2);ordinary.owner=owner
local game={phase='fight',heroRulesByName={},managedSummons={[creep]={owner=owner,nextOrder=0},[ordinary]={owner=owner,nextOrder=0}},
    neutralRecruitUnits={[creep]={hero=owner}},battleManager={teamHeroes={[2]={owner},[3]={enemy}},teamRules={[3]={}},GetBattleTime=function() return 10 end}}
require('tactics/tactic_bridge')
local bridge=TacticBridge.new({game_mode=game});bridge:Install();game.tacticBridge=bridge
local engine=bridge.tacticEngine
local function contains(list,target) for _,u in ipairs(list) do if u==target then return true end end return false end
assert(contains(engine.get_battle_units(),creep),'recruited caster must join engine')
assert(not contains(engine.get_battle_units(),ordinary),'ordinary summons retain existing AI')
local rules=bridge.getRules(creep)
assert(#rules==3 and rules[1].action.logical_id=='centaur_khan_war_stomp','same native active spells; passive omitted')
assert(rules[1].use_conditions[1].radius==250,'same live neutral stomp radius')
assert(rules[2].action.logical_id=='ogre_magi_frost_armor' and rules[2].target.team=='ally','native autocast buff retained')
assert(rules[3].action.kind=='attack')
local ctx=engine.build_context(creep)
assert(contains(ctx.allies,owner) and contains(ctx.enemies,enemy))
assert(contains(ctx.get_candidates(creep,{}, {team='ally',types={'summon'}}),creep),'companion remains owned summon')
owner.alive=false
assert(contains(engine.get_battle_units(),creep),'owner death must not stop living creep AI')
creep.team=3;creep.owner=enemy
ctx=engine.build_context(creep)
assert(contains(ctx.allies,enemy) and contains(ctx.enemies,owner),'theft uses current native allegiance even in same tick')
assert(ctx.is_owned_by(creep,enemy),'theft updates ownership context')
assert(creep.team==3 and creep.owner==enemy,'AI never rewrites native ownership')
local count=0
for _,u in ipairs(engine.get_battle_units()) do if u==creep then count=count+1 end end
assert(count==1)
creep.rpg_recruit_pending=true;creep.team=4
assert(not contains(engine.get_battle_units(),creep),'reserved target cannot act')
creep.rpg_recruit_pending=nil;creep.team=3;creep.alive=false
assert(not contains(engine.get_battle_units(),creep),'dead target cannot act')
creep.alive=true;game.phase='setup'
assert(not contains(engine.get_battle_units(),creep),'preparation target cannot act')
game.phase='fight';creep.team=4
assert(not contains(engine.get_battle_units(),creep),'expired neutral conversion cannot act')
creep.team=3
assert(require('tactics/neutral_attack').IsNeutral(creep),'aliases share native attack/cast safeguards')
-- A summon tick cannot overwrite a recruited creep cast/approach, even when
-- native IsUsingAbility has not become true yet. Ordinary summons still attack.
local orders={}
bridge.orderGate={Execute=function(_,order) orders[#orders+1]=order;return true end}
DOTA_UNIT_ORDER_ATTACK_TARGET=4;DOTA_UNIT_TARGET_TEAM_ENEMY=2;FIND_CLOSEST=0
FindUnitsInRadius=function(team) return team==3 and {owner} or {enemy} end
owner.alive=true;game.nextSummonScan=100
require('battle/summon_behavior').OnThink(game)
assert(#orders==1 and orders[1].UnitIndex==ordinary.id,'only ordinary summon receives half-second attack order')
print('PASS: recruited neutral native spell rules, admission, ownership/theft, owner death and single order source')
