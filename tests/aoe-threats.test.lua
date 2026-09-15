local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
local A=require('tactics/aoe_threats')
local function unit(team)
    return {team=team,alive=true,visible=true,
        GetTeamNumber=function(s) return s.team end,
        IsAlive=function(s) return s.alive end,
        IsNull=function(s) return s.null or false end,
        GetCurrentActiveAbility=function() error('must not poll active ability') end,
        CanEntityBeSeenByMyTeam=function(s,enemy) return enemy.visible and s.team==2 end}
end
local function ability(name)
    return {name=name,reads=0,point={x=10,y=20,z=0},values={radius=250,delay=.5,light_strike_array_aoe=250,light_strike_array_delay_time=.5},
        GetAbilityName=function(s) return s.name end,
        GetSpecialValueFor=function(s,k) return s.values[k] end,
        GetCursorPosition=function(s) s.reads=s.reads+1;if s.throw then error('no cursor') end return s.point end,
        GetCastPoint=function() error('must not sample windup') end,
        IsInAbilityPhase=function() error('must not poll phase') end}
end
local viewer,enemy=unit(2),unit(3)
assert(A.OnStart==nil,'no windup API')
for _,name in ipairs({'lina_light_strike_array','leshrac_split_earth','kunkka_torrent'}) do
    A.Reset();enemy.alive=true;enemy.visible=true;enemy.null=false
    local a=ability(name)
    A.Observe({viewer,enemy,unit(4)},10)
    assert(#A.Threats(viewer,10)==0 and a.reads==0,'observation never samples pre-release')
    A.OnExecuted(enemy,a,10.04)
    local r=assert(A.Threats(viewer,10.04)[1]);local id=r.id
    assert(r.phase=='released' and r.radius==250 and r.impact_at==10.54)
    enemy.visible=false;a.point.x=99
    A.OnExecuted(enemy,a,10.04)
    A.Observe({},10.05)
    assert(#A.Threats(viewer,10.05)==1 and a.reads==1,'duplicate release cannot resample')
    r.position.x=123
    r=A.Threats(viewer,10.05)[1]
    assert(r.id==id and r.position.x==10,'released position remains a snapshot')
    local teammate=unit(2);teammate.CanEntityBeSeenByMyTeam=nil
    assert(#A.Threats(teammate,10.05)==1,'knowledge belongs to the observing team')
    assert(#A.Threats(unit(3),10.05)==0 and #A.Threats(unit(4),10.05)==0,'allies and unobserved teams excluded')
    enemy.alive=false;require('tactics/native_events').Detach(enemy)
    enemy.null=true;enemy.team=nil;A.Observe({},10.1)
    assert(#A.Threats(viewer,10.1)==1,'known release survives hiding, death, detach and invalid caster')
    assert(#A.Threats(viewer,10.54)==0,'circle expires exactly at impact')
    enemy.team=3
end
for _,mode in ipairs({'hidden','missing visibility','throwing visibility','missing team','missing enemy team','no roster','removed viewer','dead viewer'}) do
    A.Reset();viewer=unit(2);enemy=unit(3)
    local a=ability('kunkka_torrent')
    if mode=='hidden' then enemy.visible=false
    elseif mode=='missing visibility' then viewer.CanEntityBeSeenByMyTeam=nil
    elseif mode=='throwing visibility' then viewer.CanEntityBeSeenByMyTeam=function() error('unavailable') end
    elseif mode=='missing team' then viewer.team=nil
    elseif mode=='missing enemy team' then enemy.team=nil
    elseif mode=='dead viewer' then viewer.alive=false end
    if mode~='no roster' then A.Observe({viewer,enemy},20) end
    if mode=='removed viewer' then A.Observe({enemy},20.01) end
    A.OnExecuted(enemy,a,20.04)
    assert(#A.Threats(viewer,20.04)==0 and a.reads==0,mode..' fails closed at release')
    enemy.visible=true;enemy.team=3;viewer=unit(2);a.point.x=999
    A.Observe({viewer,enemy},20.05);A.OnExecuted(enemy,a,20.04)
    assert(#A.Threats(viewer,20.1)==0 and a.reads==0,mode..' never acquires retrospective knowledge')
    A.OnExecuted(enemy,a,20.2)
    assert(A.Threats(viewer,20.2)[1].position.x==999,'a distinct visible release is observable')
end
for _,bad in ipairs({'unsupported','position','radius','delay','numeric','nan','infinite','throw'}) do
    A.Reset();viewer=unit(2);enemy=unit(3)
    local a=ability('lina_light_strike_array')
    if bad=='unsupported' then a.name='unreviewed_native_aoe'
    elseif bad=='position' then a.point=nil
    elseif bad=='radius' then a.values.light_strike_array_aoe=0
    elseif bad=='delay' then a.values.light_strike_array_delay_time=nil
    elseif bad=='numeric' then a.values.light_strike_array_delay_time='0.5'
    elseif bad=='nan' then a.point.x=0/0
    elseif bad=='infinite' then a.values.light_strike_array_aoe=math.huge
    else a.throw=true end
    A.Observe({viewer,enemy},30);A.OnExecuted(enemy,a,30.04)
    assert(#A.Threats(viewer,30.04)==0,bad..' must fail closed')
end
A.Reset();viewer=unit(2);enemy=unit(3)
local a,b=ability('kunkka_torrent'),ability('leshrac_split_earth')
A.Observe({viewer,enemy},35)
A.OnExecuted(enemy,a,35);A.OnExecuted(enemy,b,35);A.OnExecuted(enemy,a,35)
assert(#A.Threats(viewer,35)==2,'interleaved duplicate events are suppressed')
A.Reset(enemy);assert(#A.Threats(viewer,35)==0,'unit reset clears its released records')
A.OnExecuted(enemy,a,35.1);assert(#A.Threats(viewer,35.1)==1,'unit reset clears deduplication')
A.Reset();A.OnExecuted(enemy,a,35.2)
assert(#A.Threats(viewer,35.2)==0,'global reset also clears registered viewers')
A.Observe({viewer,enemy},36);A.OnExecuted(enemy,a,nil);A.OnExecuted(enemy,a,0/0)
assert(#A.Threats(viewer,36)==0 and #A.Threats(viewer,nil)==0,'invalid clocks fail closed')
-- Native modifier routes only its parent and retains success recording.
class=function(t) return t end;IsServer=function() return true end
MODIFIER_EVENT_ON_ATTACK=1;MODIFIER_EVENT_ON_ATTACK_START=2
MODIFIER_EVENT_ON_ABILITY_EXECUTED=3;MODIFIER_EVENT_ON_ABILITY_START=4
MODIFIER_EVENT_ON_ABILITY_END_CHANNEL=5
GameRules={GetGameTime=function() return 40 end}
require('modifiers/modifier_rpg_tactics_events')
local modifier=setmetatable({GetParent=function() return enemy end},{__index=modifier_rpg_tactics_events})
assert(modifier.OnAbilityStart==nil)
local declared={};for _,event in ipairs(modifier:DeclareFunctions()) do declared[event]=true end
assert(declared[3] and declared[5] and not declared[4],'execution/channel hooks retained; ability start removed')
A.Reset();a=ability('kunkka_torrent');A.Observe({viewer,enemy},39.95)
require('tactics/native_events').Attach(enemy)
modifier:OnAbilityExecuted({unit=viewer,ability=a});assert(#A.Threats(viewer,40)==0)
modifier:OnAbilityExecuted({unit=enemy,ability=a})
assert(A.Threats(viewer,40)[1].phase=='released')
assert(enemy.rpgTacticsEvents.casts.kunkka_torrent==1,'existing native success hook retained')
A.Observe({viewer,enemy},40.05);assert(#A.Threats(viewer,40.05)==1)
A.Reset()
print('PASS native AoE threats: releases only, team snapshots, hidden releases, death/detach, expiry, resets, duplicates, modifier hooks')
