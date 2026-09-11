local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..root..'/tests/?.lua;'..package.path
local H=require('capability_test_helpers');local Adapter=require('tactics/action_adapter')
local S=require('tactics/state_controller');local L=require('tactics/action_lifecycle');local E=require('tactics/tactic_engine')
local O=require('tactics/condition_observation');local D=require('tactics/rule_diagnostics')
GameRules={GetGameTime=function() return 62 end}
local hero=H.unit();local a=H.ability(hero,'drow_ranger_frost_arrows',8+4096)
local orders={};local accept=true;local adapter=Adapter.new({Execute=function(_,order) if not accept then return false end orders[#orders+1]=order;return true end})
local action={kind='ability',name=a.name,logical_id=a.name,desired_autocast_state=true}
local spec=assert(adapter:Resolve(hero,action,{}));assert(spec.cast_type=='autocast')
a.castable=false;a.cooldown=false;a.maxcharges=1;a.charges=0;hero.mana=0
assert(adapter:CanExecute(hero,spec,{now=10}),'state order is not a mana/charge consuming cast')
assert(adapter:Issue(hero,spec,nil,{now=10}));assert(orders[1].OrderType==20 and not orders[1].TargetIndex)
assert(not adapter:CanExecute(hero,spec,{now=10.8}),'wait for acknowledgement before retry')
a.auto=true;assert(not adapter:CanExecute(hero,spec,{now=11}))
action.desired_autocast_state=false;spec=assert(adapter:Resolve(hero,action,{}));assert(adapter:Issue(hero,spec,nil,{now=11}));assert(hero.rpgStateControls[a].desired==false)
a.auto=false;assert(not adapter:Issue(hero,spec,nil,{now=13}),'already off cannot toggle on accidentally')
S.Reset(hero);action.desired_autocast_state=true;action.state_policy='mana_hysteresis';action.state_mana_on=.4;action.state_mana_off=.2
spec=assert(adapter:Resolve(hero,action,{}));hero.mana=30;assert(not S.CanChange(hero,spec,{now=20}));hero.mana=40;assert(S.CanChange(hero,spec,{now=20}))
a.auto=true;hero.mana=30;assert(not S.CanChange(hero,spec,{now=21}));hero.mana=20;assert(S.CanChange(hero,spec,{now=21}) and spec.desired_autocast_state==false)
S.Reset(hero);a.auto=false;hero.mana=50;accept=false;assert(not adapter:Issue(hero,spec,nil,{now=22}));assert(not hero.rpgStateControls,'rejected order leaves no pending ACK')
accept=true;S.Reset(hero)
local parent=H.ability(hero,'keeper_of_the_light_illuminate',16+128);parent.values.radius=100;parent.values.range=1500
local release=H.ability(hero,'keeper_of_the_light_illuminate_end',4)
L.Requested(hero,parent.name,50);assert(L.Phase(hero,parent.name,52.1)=='UNCONFIRMED');assert(not L.ChannelElapsed(hero,parent.name,52.1))
hero.channel=true;hero.active=parent;parent.channelstart=60;L.Observe(hero,61.5);assert(L.ChannelElapsed(hero,parent.name,61.5)==1.5)
local releaseSpec=assert(adapter:Resolve(hero,{kind='ability',name=release.name,logical_id=release.name},{}));assert(L.CanRelease(hero,releaseSpec))
assert(adapter:CanExecute(hero,releaseSpec,{now=61.5}));assert(not adapter:CanExecute(hero,{kind='attack',cast_type='attack'},{}));assert(not adapter:IssueApproach(hero,releaseSpec,Vector(0)))
release.hidden=true;assert(not L.CanRelease(hero,releaseSpec));release.hidden=false
local other=H.ability(hero,'unrelated_end',4);assert(not L.CanRelease(hero,{source=other}))
local r=H.rule(release.name,'self');r.use_conditions={{type='channel_elapsed_gte',seconds=2},{type='release_action_available'}}
local engine=E.new({order_gate={Execute=function(_,o) orders[#orders+1]=o;return true end},get_phase=function() return 'FIGHT' end,get_battle_units=function() return {hero} end,get_rules=function() return {H.rule(a.name),r} end,build_context=function() return {} end})
orders={};engine:EvaluateUnit(hero,engine:GetState(hero),61.5);assert(#orders==0,'release threshold not met; no fallback may interrupt')
engine:EvaluateUnit(hero,engine:GetState(hero),62);assert(#orders==1 and orders[1].AbilityIndex==release.id,'only matching reviewed release executes during channel')
L.ChannelEnded(hero,parent.name,63,nil);hero.channel=false;hero.active=nil;assert(L.Phase(hero,parent.name,63)=='ENDED','unknown interruption is not certified success')
L.ChannelEnded(hero,parent.name,64,false);assert(L.Phase(hero,parent.name,64)=='FINISHED')
local ctx={caster=hero,condition_trace={}};O.Record(ctx,'use',1,{type='self_has_modifier',modifier='missing'},hero,false)
assert(ctx.condition_trace[1].actual=='false','diagnostics retain false rather than unknown')
for i=1,50 do O.Record(ctx,'use',i,{type='always'},hero,true) end;assert(#ctx.condition_trace==24)
local events={};CustomGameEventManager={Send_ServerToAllClients=function(_,name,payload) events[#events+1]={name,payload} end}
D.Reset();D.Publish(hero,'key','rule_skipped',{rule_index=1,reason='test',conditions=ctx.condition_trace},10)
D.Publish(hero,'key','rule_skipped',{rule_index=1,reason='different'},10.1);assert(#events==2,'changing reasons still throttled')
D.Publish(hero,'key','rule_skipped',{rule_index=1,reason='different'},11);assert(#events==3)
print('PASS state/lifecycle: native autocast OFF, hysteresis, ACK/debounce, rejected orders, channel clocks, exact release guard, bounded diagnostic trace')
