local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
local T=require('tactics/techies_threats')
local function ability(name,values)
    return {GetAbilityName=function() return name end,GetSpecialValueFor=function(_,k) return values[k] end}
end
local function unit(team,name)
    return {team=team,name=name,seen={[2]=true},pos={x=20,y=30,z=0},mods={},alive=true,reads=0,
        GetTeamNumber=function(s) return s.team end,GetUnitName=function(s) return s.name end,
        IsNull=function() return false end,IsAlive=function(s) return s.alive end,
        CanEntityBeSeenByMyTeam=function(s,o) return o.seen[s.team]==true end,
        GetAbsOrigin=function(s) s.reads=s.reads+1;return s.pos end,
        GetOwnerEntity=function(s) return s.owner end,
        GetCreationTime=function(s) return s.born end,
        FindAllModifiers=function() return {} end,
        FindModifierByName=function(s,n) return s.mods[n] end}
end
local viewer,other=unit(2),unit(4)
local scans,world=0,{}
Entities={FindAllByClassname=function(_,name) assert(name=='npc_dota_techies_mines' or name=='npc_dota_thinker');scans=scans+1;return world end}
local function mine(name,spell,values)
    local m=unit(3,name); local a=ability(spell,values)
    m.owner={FindAbilityByName=function(_,n) if n==spell then return a end end}
    return m
end
local m=mine('npc_dota_techies_land_mine','techies_land_mines',{radius=500,activation_delay=1,proximity_threshold=1})
world={m};m.born=0
T.Observe({viewer,other},2)
local r=assert(T.Threats(viewer,2)[1]);local id=r.id
assert(r.radius==500 and r.active_from==2 and r.active_until>2 and id>1e9)
assert(#T.Threats(other,2)==0)
assert(r.escape_deadline==2.8,'known entry deadline reserves discovery interval')
T.Observe({viewer},2.05);assert(scans==2,'known objects do not trigger full scan')
assert(T.Threats(viewer,2.05)[1].escape_deadline==2.8,'entry deadline never slides with observations')
m.seen[2]=false;m.pos.x=90
local reads=m.reads
T.Observe({viewer},2.1)
assert(m.reads==reads and T.Threats(viewer,2.1)[1].position.x==20,'hidden motion never sampled')
r.position.x=999;assert(T.Threats(viewer,2.1)[1].position.x==20,'defensive copy')
assert(#T.Threats(viewer,5.06)==0,'unseen disappearance is bounded')
T.Reset();world={m};m.alive=true;m.seen[2]=false;T.Observe({viewer},3)
assert(#T.Threats(viewer,3)==0,'never-seen mine is not disclosed')
m.seen[2]=true;T.Observe({viewer},3.21);assert(#T.Threats(viewer,3.21)==1)
m.alive=false;T.Observe({viewer},3.22);assert(#T.Threats(viewer,3.22)==0,'visible destruction removes immediately')
for _,v in ipairs({
 {'npc_dota_techies_remote_mine','techies_remote_mines','radius'},
 {'npc_dota_techies_stasis_trap','techies_stasis_trap','stun_radius'},
 {'npc_dota_techies_snare_trap','techies_snare_trap','effect_radius'},
 {'npc_dota_techies_innate_mine','techies_mutually_assured_destruction','radius'},
}) do
 T.Reset();m=mine(v[1],v[2],{[v[3]]=400});world={m};T.Observe({viewer},4)
 assert(T.Threats(viewer,4)[1].radius==400,v[1]..' actual object independent of planter visibility')
end
T.Reset();world={mine('npc_dota_techies_land_mine','techies_land_mines',{})};T.Observe({viewer},5)
assert(#T.Threats(viewer,5)==0,'missing specials fail closed')
for _,effect in ipairs({{'modifier_techies_sticky_bomb_slow','techies_sticky_bomb'}, {'modifier_techies_reactive_tazer','techies_reactive_tazer'}}) do
 T.Reset();world={}
 local carrier=unit(effect[2]=='techies_sticky_bomb' and 2 or 3)
 local caster=unit(3);caster.seen={}
 local mod={GetAbility=function() return ability(effect[2],{explosion_radius=350}) end,
  GetCaster=function() return caster end,GetRemainingTime=function() return 1 end}
 carrier.mods[effect[1]]=mod
 T.Observe({viewer,other,carrier},10)
 r=assert(T.Threats(viewer,10)[1]);assert(r.impact_at==11 and r.expires_at==11)
 carrier.pos.x=70;T.Observe({viewer,other,carrier},10.1)
 assert(T.Threats(viewer,10.1)[1].position.x==70,'visible carrier moves threat')
 carrier.seen[2]=false;carrier.seen[4]=true;carrier.pos.x=100
 T.Observe({viewer,other,carrier},10.2)
 assert(T.Threats(viewer,10.2)[1].position.x==70 and T.Threats(other,10.2)[1].position.x==100,'separate team snapshots')
 assert(#T.Threats(viewer,11.11)==0,'hidden countdown does not slide')
 carrier.mods={};T.Observe({viewer,other,carrier},10.3)
 assert(#T.Threats(other,10.3)==0,'visible purge removes threat')
end
T.Reset();world={};local carrier=unit(3)
carrier.mods.modifier_techies_sticky_bomb_slow_secondary={GetRemainingTime=function() return 3 end}
T.Observe({viewer,carrier},12);assert(#T.Threats(viewer,12)==0,'post-explosion slow is not a bomb')
T.Reset();m=mine('npc_dota_techies_land_mine','techies_land_mines',{radius=500,activation_delay=1});m.born=20;world={m}
T.Observe({viewer},20);r=T.Threats(viewer,20)[1]
assert(r.active_from==21 and r.active_until>21,'native creation plus arming delay')
T.Observe({viewer},20.1);assert(T.Threats(viewer,20.1)[1].id==r.id and T.Threats(viewer,20.1)[1].released_at==20,'stable observed identity')
T.Reset(m);assert(#T.Threats(viewer,20.1)==0,'object reset')
T.Reset();m.team=2;T.Observe({viewer},21);assert(#T.Threats(viewer,21)==0,'friendly mine excluded')
T.Reset();m.team=nil;T.Observe({viewer},22);assert(#T.Threats(viewer,22)==0,'missing mine team fails closed')
T.Reset();m.team=3;local blind=unit(2);blind.CanEntityBeSeenByMyTeam=function() error('visibility unavailable') end
T.Observe({blind},23);assert(#T.Threats(blind,23)==0,'throwing visibility fails closed')
-- Free Sticky bombs are discovered from actual native phase modifiers on thinkers.
for _,phase in ipairs({'countdown','chase','throw'}) do
 T.Reset();local bomb=unit(3,'npc_dota_thinker');world={bomb}
 local caster=unit(3);local a=ability('techies_sticky_bomb',{explosion_radius=350})
 bomb.mods['modifier_techies_sticky_bomb_'..phase]={GetAbility=function() return a end,
  GetCaster=function() return caster end,GetRemainingTime=function() return 1.2 end}
 T.Observe({viewer},30);local first=assert(T.Threats(viewer,30)[1])
 assert(first.radius==350 and (phase=='countdown' and first.impact_at==31.2 or phase~='countdown' and first.envelope))
 bomb.pos.x=90;T.Observe({viewer},30.05)
 assert(T.Threats(viewer,30.05)[1].position.x==90,'free bomb follows actual visible position')
 bomb.seen[2]=false;bomb.pos.x=150;local count=bomb.reads
 T.Observe({viewer},30.1);assert(bomb.reads==count,'hidden thinker position never read')
end
-- Main threat API merges source observations and resets their state.
local A=require('tactics/aoe_threats')
A.Reset();world={mine('npc_dota_techies_land_mine','techies_land_mines',{radius=500,proximity_threshold=1})}
A.Observe({viewer},40);assert(A.Threats(viewer,40)[1].id>1e9,'engine threat stream includes observed mines')
A.Reset();assert(#A.Threats(viewer,40)==0,'global reset clears object threats')
Entities=nil;T.Reset();T.Observe({viewer},24);assert(#T.Threats(viewer,24)==0,'missing discovery fails closed')
T.Observe({viewer},0/0);assert(#T.Threats(viewer,0/0)==0)
print('techies-threats: passed')
