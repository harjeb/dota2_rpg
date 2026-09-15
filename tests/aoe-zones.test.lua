local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
local A=require('tactics/aoe_threats')
local function unit(team,x)
 return {team=team,pos={x=x or 0,y=0,z=0},seen={[2]=true,[4]=true},alive=true,reads=0,
  GetTeamNumber=function(s)return s.team end,IsAlive=function(s)return s.alive end,
  IsNull=function(s)return s.null or false end,
  GetAbsOrigin=function(s)s.reads=s.reads+1;return s.pos end,
  CanEntityBeSeenByMyTeam=function(s,u)return u.seen[s.team]==true end,
  HasShard=function(s)return s.shard==true end}
end
local enemy,v2,v4,target=unit(3),unit(2),unit(4),unit(3,40)
local function ability(name,values)
 return {name=name,values=values,point={x=100,y=0,z=0},target=target,reads=0,
  GetAbilityName=function(s)return s.name end,
  GetSpecialValueFor=function(s,k)return s.values[k] end,
  GetCursorPosition=function(s)s.reads=s.reads+1;return s.point end,
  GetCursorTarget=function(s)return s.target end,
  GetChannelTime=function()return 4 end,
  GetCastPoint=function()error('windup poll forbidden')end}
end
local function reset()
 A.Reset();enemy.alive=true;enemy.seen={[2]=true,[4]=true};enemy.pos.x=0;enemy.shard=false
 target.alive=true;target.seen={[2]=true,[4]=true};target.pos.x=40
 A.Observe({v2,v4,enemy,target},0)
end
local function cast(name,values) local a=ability(name,values);A.OnExecuted(enemy,a,1);return a end
reset()
local a=cast('sniper_shrapnel',{radius=450,damage_delay=1.2,duration=10,slow_duration=99})
local s=assert(A.Threats(v2,1)[1]);assert(s.active_from==2.2 and s.active_until==12.2)
assert(#A.Threats(v2,3)==1 and #A.Threats(v2,12.2)==0,'ground lasts beyond impact, excludes debuff lifetime')
reset();a=cast('jakiro_ice_path',{path_radius=150,path_delay=.2,path_duration=4,stun_duration=99})
s=A.Threats(v2,1)[1];assert(s.shape=='line' and s.position.x==0 and s.endpoint.x==1100 and s.expires_at==5.2)
s.endpoint.x=55;assert(A.Threats(v4,1)[1].endpoint.x==1100,'endpoints copied across consumers/teams')
reset();cast('jakiro_macropyre',{path_width=500,AbilityCastRange=1400,duration=10,linger_duration=99})
s=A.Threats(v2,1)[1];assert(s.radius==250 and s.endpoint.x==1400 and s.expires_at==11)
reset();cast('disruptor_kinetic_field',{radius=350,wall_thickness=100,formation_time=1,duration=4})
s=A.Threats(v2,1)[1];assert(s.shape=='ring' and s.inner_radius==300 and s.radius==400 and s.active_from==2)
reset();cast('mars_arena_of_blood',{radius=550,width=100,spear_distance_from_wall=160,formation_time=.1,duration=5.5})
s=A.Threats(v2,1)[1];assert(s.inner_radius==390 and s.radius==650)
reset();cast('juggernaut_blade_fury',{blade_fury_radius=260,duration=5})
enemy.pos.x=200;enemy.seen[4]=false;A.Observe({v2,v4,enemy},2)
assert(A.Threats(v2,2)[1].position.x==200 and A.Threats(v4,2)[1].position.x==0,'per-team movement')
enemy.seen[2]=false;local reads=enemy.reads;enemy.pos.x=900;A.Observe({v2,v4,enemy},3)
assert(enemy.reads==reads and A.Threats(v2,3)[1].position.x==200,'hidden movement never sampled')
enemy.seen[4]=true;A.Observe({v2,v4,enemy},4);assert(A.Threats(v4,4)[1].position.x==900)
enemy.alive=false;A.Observe({v2,v4,enemy},4.1)
assert(#A.Threats(v4,4.1)==0 and #A.Threats(v2,4.1)==1,'visible death stops moving zone; hidden team frozen')
assert(#A.Threats(v2,6)==0)
reset();a=cast('dark_willow_cursed_crown',{stun_radius=360,delay=4})
target.pos.x=300;target.seen[4]=false;A.Observe({v2,v4,enemy,target},2)
assert(A.Threats(v2,2)[1].position.x==300 and A.Threats(v4,2)[1].position.x==40)
reset();target.seen={[2]=false,[4]=false};reads=target.reads
cast('dark_seer_ion_shell',{radius=275,duration=20})
assert(target.reads==reads and #A.Threats(v2,1)==0,'hidden initial target never sampled')
reset();enemy.seen={[2]=false,[4]=false};a=cast('juggernaut_blade_fury',{blade_fury_radius=260,duration=5})
enemy.seen={[2]=true,[4]=true};A.Observe({v2,v4,enemy},2)
assert(#A.Threats(v2,2)==0,'visible moving caster cannot reveal hidden release')
reset();a=cast('enigma_black_hole',{radius=420,duration=4})
enemy.seen[4]=false;A.OnChannelEnd(enemy,a,2,true)
assert(#A.Threats(v2,2)==0 and #A.Threats(v4,2)==1,'channel stop updates visible teams only')
assert(#A.Threats(v4,5)==0)
reset();a=cast('enigma_black_hole',{radius=420,duration=4})
enemy.IsChanneling=function()return false end
A.Observe({v2,v4,enemy},1.05);assert(#A.Threats(v2,1.05)==1,'native channel startup grace')
enemy.seen[4]=false;A.OnChannelEnd(enemy,a,2,true)
assert(#A.Threats(v4,2)==1,'hidden stop remains frozen')
enemy.seen[4]=true;A.Observe({v2,v4,enemy},2.1)
assert(#A.Threats(v4,2.1)==0,'revisible stopped channel reconciled')
enemy.IsChanneling=nil
reset();a=cast('techies_reactive_tazer',{explosion_radius=400,duration=6})
target.pos.x=600;A.Observe({v2,v4,enemy,target},2)
s=A.Threats(v2,2)[1];assert(s.position.x==600 and s.impact_at==7,'Reactive Tazer follows allied target')
A.OnExecuted(enemy,ability('techies_reactive_tazer_stop',{}),2.1)
assert(#A.Threats(v2,2.1)==0,'visible early detonation consumes scheduled Tazer explosion')
reset();a=cast('techies_suicide',{radius=400,duration=.75,stun_duration=1.4})
s=assert(A.Threats(v2,1)[1]);assert(s.position.x==100 and s.impact_at==1.75 and s.expires_at==1.75,
 'Blast Off estimates released jump landing, not cast point or stun lifetime')
reset();a=cast('warlock_upheaval',{aoe=650,duration=99})
assert(A.Threats(v2,1)[1].expires_at==5,'channel API duration, not lingering slow')
enemy.alive=false;A.Observe({v2,enemy},2);assert(#A.Threats(v2,2)==0,'channel caster death')
reset();a=cast('windrunner_powershot',{arrow_width=125,arrow_range=3000,arrow_speed=3000})
assert(#A.Threats(v2,1)==0 and a.reads==0,'no charge windup or cursor reads')
A.OnChannelEnd(enemy,a,2,true);s=A.Threats(v2,2)[1]
assert(s.released_at==2 and s.shape=='line' and s.expires_at==3 and a.reads==1)
A.OnChannelEnd(enemy,a,2,true);assert(#A.Threats(v2,2)==1 and a.reads==1,'duplicate channel end')
reset();enemy.seen={[2]=false,[4]=false};a=cast('windrunner_powershot',{arrow_width=125,arrow_range=3000,arrow_speed=3000})
enemy.seen={[2]=true,[4]=true};A.OnChannelEnd(enemy,a,2,false)
assert(#A.Threats(v2,2)==0 and a.reads==0,'hidden initial charge not discovered at release')
reset();cast('lina_dragon_slave',{dragon_slave_width_initial=100,dragon_slave_width_end=250,dragon_slave_distance=1200,dragon_slave_speed=1200})
s=A.Threats(v2,1)[1];assert(s.shape=='cone' and s.end_radius==250 and s.envelope and s.expires_at==2)
reset();cast('invoker_chaos_meteor',{area_of_effect=275,land_time=1.3,travel_distance=900,travel_speed=300})
s=A.Threats(v2,1)[1];assert(s.position.x==100 and s.endpoint.x==1000 and s.active_from==2.3 and s.active_until==5.3)
reset();enemy.shard=true
cast('leshrac_split_earth',{radius=210,delay=.35,shard_max_count=2,shard_secondary_delay=5,shard_radius_increase=45})
local all=A.Threats(v2,1);assert(#all==3 and all[2].impact_at==6.35 and all[3].radius==300)
assert(#A.Threats(v2,1.35)==2 and #A.Threats(v2,11.35)==0,'shard repeats remain separate delayed hits')
reset();cast('black_dragon_fireball',{radius=300,duration=8})
enemy.alive=false;enemy.seen={[2]=false,[4]=false};A.Observe({v2},2)
assert(#A.Threats(v2,8.99)==1 and #A.Threats(v2,9)==0,'released neutral ground survives caster death')
reset();cast('crystal_maiden_crystal_nova',{radius=425,duration=4})
assert(#A.Threats(v2,1)==0,'instant damage plus slow is not persistent ground')
for _,interrupted in ipairs({true,'missing',false}) do
 reset();a=cast('item_meteor_hammer',{impact_radius=400,land_time=.5,burn_duration=6})
 assert(#A.Threats(v2,1)==0 and a.reads==0,'Meteor windup is not released')
 local flag=interrupted; if flag=='missing' then flag=nil end
 A.OnChannelEnd(enemy,a,2,flag)
 if interrupted==false then
  s=assert(A.Threats(v2,2)[1]);assert(s.impact_at==2.5 and s.expires_at==2.5)
  assert(#A.Threats(v2,2.5)==0,'Meteor burn is not ground duration')
 else assert(#A.Threats(v2,2)==0 and a.reads==0,'aborted/unknown Meteor completion fails closed') end
end
reset();cast('item_shivas_guard',{blast_radius=825,blast_speed=400,blast_debuff_duration=99})
s=A.Threats(v2,1)[1];assert(s.expires_at==1+825/400 and s.envelope)
reset();cast('item_blood_grenade',{radius=300,speed=1000,debuff_duration=5})
s=A.Threats(v2,1)[1];assert(s.impact_at==1.1 and s.expires_at==1.1)
A.Reset()
print('PASS AoE zones: ground lifetimes, lines/cones/rings, moving team visibility, hidden target reads, channel completion/interruption, charge privacy, shard repeats, neutral zones')
