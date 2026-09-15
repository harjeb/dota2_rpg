-- Offline native observation contracts; no claim to simulate native spell code.
local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..root..'/tests/?.lua;'..package.path
local H=require('capability_test_helpers')
local Charge=require('tactics/charge_control')
local Engine=require('tactics/tactic_engine')
DOTA_UNIT_ORDER_STOP=21
GameRules={GetGameTime=function() return 0 end}
local hero,enemy=H.unit(2),H.unit(3,100)
local orders={};local rules={}
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o;return true end},
 get_phase=function() return 'FIGHT' end,get_rules=function() return rules end,
 get_battle_units=function() return {hero} end,
 build_context=function() return {get_candidates=function() return {enemy} end} end})
local state=engine:GetState(hero)
local function begin(name,mode,seconds,t)
 local p=Charge.Profile(name)
 local ability=H.ability(hero,name,p and p.channel and 144 or 16)
 ability.channelstart=t;function ability:GetChannelTime() return 2 end
 if p and p.maximum then ability.values[p.maximum]=3 end
 local rule=H.rule(name);rule.action.charge_mode=mode;rule.action.charge_time=seconds
 rules={rule}
 Charge.Requested(hero,state,rule,{source=ability},t)
 return ability,rule
end
local function tick(t) engine:EvaluateUnit(hero,state,t) end
local function modifier(name,a,t)
 local m={GetCreationTime=function() return t end,GetAbility=function() return a end}
 hero.modifiers[name]=m;return m
end
-- Submission/windup is not charge elapsed. Fallback and recasts stay suspended.
local a=begin('windrunner_powershot','time',.5,10)
tick(10.4);assert(#orders==0)
hero.channel=true;hero.active=a;a.channelstart=10.5
tick(10.9);assert(#orders==0)
tick(11);assert(#orders==1 and orders[1].OrderType==21)
tick(11.1);assert(#orders==1,'wait for release confirmation without immediate duplicate')
hero.channel=false;hero.active=nil
assert(not Charge.Continue(engine,hero,state,{now=11.6}) and not state.charge)
-- Old charge cannot be adopted, nor can another channel be cancelled.
a=begin('windrunner_powershot','time',0,20);hero.channel=true;hero.active=a;a.channelstart=19
assert(not Charge.Continue(engine,hero,state,{now=20}) and not state.charge)
a=begin('windrunner_powershot','time',0,21);hero.active=H.ability(hero,'bane_fiends_grip',128)
assert(not Charge.Continue(engine,hero,state,{now=21}) and #orders==1)
hero.channel=false;hero.active=nil
-- A new episode between samples invalidates the original deadline.
a=begin('windrunner_powershot','time',1,30);hero.channel=true;hero.active=a
tick(30.2);a.channelstart=30.3
assert(not Charge.Continue(engine,hero,state,{now=32}) and #orders==1)
hero.channel=false;hero.active=nil
-- Unsupported channels and Skewer are never charging profiles.
for _,name in ipairs({'bane_fiends_grip','pugna_life_drain','snapfire_mortimer_kisses','magnataur_skewer'}) do
 assert(not Charge.Profile(name));begin(name,'max',nil,35);assert(not state.charge)
end
-- All reviewed channel release buttons and modifier charges use native maxima.
for name,p in pairs(Charge.profiles) do
 if name~='windrunner_powershot' and not p.targeted then
  a=begin(name,'max',nil,40)
  local r=p.release and H.ability(hero,p.release,4)
  if p.channel then hero.channel=true;hero.active=a else modifier(p.modifier,a,40) end
  local max=Charge.Maximum(a);local n=#orders
  tick(40+max-.01);assert(#orders==n,name..' waits for full native power')
  tick(40+max);assert(#orders==n+1 and (p.stop and orders[#orders].OrderType==21
   or r and orders[#orders].AbilityIndex==r.id),name..' correct release')
  tick(40+max+.1);assert(#orders==n+1)
  hero.modifiers={};hero.channel=false;hero.active=nil
  Charge.Continue(engine,hero,state,{now=45});assert(not state.charge)
 end
end
-- Brew maximum is brew_time, not the self explosion deadline; select a legal target.
a=begin('alchemist_unstable_concoction','max',nil,50);a.values.brew_time=5;a.values.brew_explosion=5.5
local throw=H.ability(hero,'alchemist_unstable_concoction_throw',8)
modifier(Charge.Profile(a.name).modifier,a,50)
local n=#orders
tick(54.99);assert(#orders==n)
throw.hidden=true;tick(55);assert(#orders==n,'hidden throw cannot release')
throw.hidden=false;enemy.position=Vector(2000);tick(55.1);assert(#orders==n,'cannot chase/cancel charge for out of range target')
enemy.position=Vector(100);tick(55.2)
assert(#orders==n+1 and orders[#orders].AbilityIndex==throw.id and orders[#orders].TargetIndex==enemy.id)
-- Native order acceptance cannot consume the brew when the throw is interrupted.
function hero:IsStunned() return self.stunned==true end
throw.winding=true;tick(55.25);assert(#orders==n+1,'protect throw cast point')
throw.winding=false;hero.stunned=true;tick(55.4);assert(#orders==n+1,'controlled cannot retry')
hero.stunned=false;tick(55.41);assert(#orders==n+2,'retry an interrupted throw after recovery')
require('tactics/native_events').RecordSuccess(hero,throw.name,55.42)
tick(55.8);assert(#orders==n+2,'confirmed release does not repeat even before modifier removal')
hero.modifiers={};Charge.Continue(engine,hero,state,{now=56})
-- Modifier removal/interruption and replacement leave no stale release.
a=begin('hoodwink_sharpshooter','time',2,60)
local p=Charge.Profile(a.name);modifier(p.modifier,a,60)
tick(60.5);hero.modifiers={}
assert(not Charge.Continue(engine,hero,state,{now=61}) and not state.charge)
a=begin('hoodwink_sharpshooter','time',2,62);modifier(p.modifier,a,62)
tick(62.1);modifier(p.modifier,a,62.5)
assert(not Charge.Continue(engine,hero,state,{now=65}) and not state.charge)
-- Reject invalid settings and abandon unconfirmed submission without issuing release.
for _,v in ipairs({-1,math.huge,0/0,'bad'}) do begin('windrunner_powershot','time',v,70);assert(not state.charge) end
a=begin('windrunner_powershot','max',nil,70)
assert(not Charge.Continue(engine,hero,state,{now=72.1}) and not state.charge)
-- Editing/disabling/removing a rule abandons automatic release ownership.
a=begin('windrunner_powershot','time',1,75);rules[1].enabled=false
assert(not Charge.Continue(engine,hero,state,{now=75},rules) and not state.charge)
a=begin('windrunner_powershot','time',1,75);rules[1].action.charge_time=2
assert(not Charge.Continue(engine,hero,state,{now=75},rules) and not state.charge)
a=begin('windrunner_powershot','time',1,75)
assert(not Charge.Continue(engine,hero,state,{now=75},{}) and not state.charge)
-- Max with unavailable native timing must never fall back to stale time configuration.
a=begin('windrunner_powershot','max',.1,76);a.GetChannelTime=nil
hero.channel=true;hero.active=a;local count=#orders
tick(77);assert(#orders==count)
hero.channel=false;hero.active=nil;Charge.Continue(engine,hero,state,{now=78})
-- Actual engine order integration arms the state only for accepted parent casts.
hero.modifiers={};hero.channel=false;hero.active=nil
local rule;a,rule=begin('windrunner_powershot','time',.25,80);state.charge=nil
local ctx=engine:BuildContext(hero,80);local spec=assert(engine.actions:Resolve(hero,rule.action,ctx))
assert(engine:IssueAction(hero,state,ctx,rule,1,spec,enemy,enemy) and state.charge)
state.charge=nil;engine.actions.Issue=function() return false,'rejected' end
ctx.now=81;assert(not engine:IssueAction(hero,state,ctx,rule,1,spec,enemy,enemy) and not state.charge)
print('PASS charge control: eight native profiles, exact episodes, native maxima, target legality, confirmed release and interruption retries, engine integration')
