local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
local Engine=require('tactics/tactic_engine')
local Rules=require('issue_fixes/enemy_rules')
local Objectives=require('tactics/enemy_attack_objectives')
DOTA_UNIT_ORDER_ATTACK_TARGET=4; DOTA_UNIT_ORDER_MOVE_TO_TARGET=2
DOTA_UNIT_ORDER_MOVE_TO_POSITION=1
local vm={}
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
vm.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=0},vm) end
local time=0
GameRules={GetGameTime=function() return time end}
local entities={}
local function unit(id,team,x,name)
    local u={id=id,team=team,x=x,name=name,alive=true}
    function u:entindex() return self.id end
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return self.alive end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:GetAbsOrigin() return setmetatable({x=self.x,y=0,z=0},vm) end
    function u:IsRealHero() return self.name=='npc_dota_hero_axe' end
    function u:GetAbilityCount() return 0 end
    function u:GetAttackCapability() return 1 end
    function u:Script_GetAttackRange() return 150 end
    function u:GetSecondsPerAttack() return 1 end
    function u:IsChanneling() return self.channel or false end
    function u:IsInAbilityPhase() return self.casting or false end
    function u:IsDisarmed() return self.disarmed or false end
    function u:IsInvulnerable() return self.invuln or false end
    function u:IsAttackImmune() return self.immune or false end
    function u:IsOutOfGame() return self.out or false end
    function u:IsInvisible() return self.invisible or false end
    function u:CanEntityBeSeenByMyTeam(target) return target.unseen ~= true end
    function u:GetHealth() return 100 end
    function u:GetMaxHealth() return 100 end
    entities[id]=u; return u
end
EntIndexToHScript=function(id) return entities[id] end
local caster=unit(1,3,0,'npc_dota_hero_axe')
local hero=unit(2,2,20,'npc_dota_hero_axe')
local egg=unit(3,2,100,'npc_dota_phoenix_sun')
local tomb=unit(4,2,100,'npc_dota_unit_tombstone5')
local pool={tomb,egg}
local scans=0
FindUnitsInRadius=function(team,origin,cache,radius,side,types,flags)
    scans=scans+1
    assert(team==3 and radius==1200 and side==2 and types==55 and flags==400)
    return pool
end
local rules=Rules.CreateForUnit(caster,{})
assert(Objectives.IsRule(rules[1]) and #rules==2)
assert(#Rules.CreateForUnit(tomb,{})==1,'creeps do not receive hero policy')
assert(#require('issue_fixes/default_rules').CreateForHero(caster)==1,'player defaults unchanged')
-- Real Resolve/CanExecute/selector/Issue pipeline, with a ready native spell.
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4; DOTA_UNIT_ORDER_CAST_NO_TARGET=8
local spell={GetAbilityName=function() return 'centaur_hoof_stomp' end,
    IsNull=function() return false end, GetBehavior=function() return 4 end,
    GetLevel=function() return 1 end, IsFullyCastable=function() return true end,
    IsCooldownReady=function() return true end, GetCastPoint=function() return 0 end,
    GetAOERadius=function() return 315 end, entindex=function() return 90 end}
caster.FindAbilityByName=function(_,name) if name=='centaur_hoof_stomp' then return spell end end
local ready={action={kind='ability',logical_id='centaur_hoof_stomp'},target={team='self'},use_conditions={},target_filters={}}
table.insert(rules,2,ready)
local orders={}
local engine=Engine.new({order_gate={Execute=function(_,order) orders[#orders+1]=order; return true end},
    get_phase=function() return 'FIGHT' end,get_battle_units=function() return {caster} end,
    get_rules=function() return rules end,
    build_context=function() return {resolve_action_name=function(_,id) return id end,
        get_candidates=function() return {hero} end} end})
local function tick()
    time=time+.4; engine:EvaluateUnit(caster,engine:GetState(caster),time)
end
local function reset() engine:Reset(); orders={} end
local function target() return orders[#orders] and orders[#orders].TargetIndex end
tick()
assert(target()==egg.id and orders[1].OrderType==4,'objective basic attack precedes ready non-attack; native search bypasses hero-only roster')
egg.x=120; reset(); tick(); assert(target()==tomb.id,'nearest beats egg/tomb kind')
for level=1,5 do tomb.name='npc_dota_unit_tombstone'..level; reset(); tick(); assert(target()==tomb.id) end
for _,field in ipairs({'invuln','immune','out','removed','invisible','unseen'}) do
    tomb[field]=true; reset(); tick(); assert(target()==egg.id,field); tomb[field]=nil
end
tomb.alive=false; reset(); tick(); assert(target()==egg.id); tomb.alive=true
tomb.team=3; reset(); tick(); assert(target()==egg.id,'allies ignored'); tomb.team=2
tomb.x=1201; egg.x=1201; reset(); tick()
assert(#orders==1 and orders[1].OrderType==8,'bounded search falls through to ready native spell')
table.remove(rules,2); reset(); tick(); assert(target()==hero.id,'normal attack resumes after objectives leave')
tomb.x=100; egg.x=120
for _,field in ipairs({'channel','casting','disarmed'}) do
    caster[field]=true; reset(); tick(); assert(#orders==0,'preserve '..field); caster[field]=nil
end
-- Existing normal hero chase must yield; special chase retains its deadline.
hero.x=900; pool={}; reset(); tick(); assert(engine:GetState(caster).chase)
pool={tomb,egg}; tick(); assert(target()==tomb.id,'objective preempts normal chase')
tomb.x=600; egg.x=700; reset(); tick()
local deadline=engine:GetState(caster).chase.deadline
tick(); assert(engine:GetState(caster).chase.deadline==deadline,'objective chase is not restarted each tick')
tomb.alive=false; egg.x=100; tick(); assert(target()==egg.id,'dead chase target reselects another live objective immediately')
egg.alive=false; hero.x=20; tick(); assert(target()==hero.id,'dead chase objectives fall back')
assert(scans>0)
print('enemy-attack-objectives: real engine/selector/adapter priority, safety, native acquisition and chase passed')
