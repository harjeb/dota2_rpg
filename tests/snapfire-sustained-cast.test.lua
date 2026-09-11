-- Real tactic engine/adapter with native API doubles; does not simulate Dota projectiles.
local root=TEST_REPO_ROOT or '.'
local scripts='/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'
package.path=(arg and arg[1]=='overlay' and root..'/dota2_rpg_issue_fixes/overlay'..scripts or '')
    ..root..scripts..root..'/tests/?.lua;'..package.path
local H=require('capability_test_helpers')
local Engine=require('tactics/tactic_engine')
local Movement=require('tactics/persistent_movement')
local Lifecycle=require('tactics/action_lifecycle')
local EnemyRuntime=require('issue_fixes/enemy_runtime')
local hero,enemy=H.unit(2),H.unit(3,1200)
function hero:GetUnitName() return 'npc_dota_hero_snapfire' end
local kisses=H.ability(hero,'snapfire_mortimer_kisses',16);kisses.range=3000;kisses.radius=275
local scatter=H.ability(hero,'snapfire_scatterblast',16);scatter.range=800
local shredder=H.ability(hero,'snapfire_lil_shredder',4)
local item=H.ability(hero,'item_glimmer_cape',8)
local toggle=H.ability(hero,'test_toggle',512)
local modifier='modifier_snapfire_mortimer_kisses'
local orders={};local current=10
GameRules={GetGameTime=function() return current end}
local rules={H.rule(scatter.name),H.rule(kisses.name),H.rule(shredder.name,'self')}
local engine=Engine.new({
    order_gate={Execute=function(_,order)
        orders[#orders+1]=order
        if order.AbilityIndex==kisses.id then
            -- Native sustained cast: no channel or active-ability handle after wind-up.
            kisses.cooldown=false;hero.modifiers[modifier]={}
        end
        return true
    end},
    get_phase=function() return 'FIGHT' end,
    get_battle_units=function() return {hero} end,
    get_rules=function() return rules end,
    build_context=function() return {get_candidates=function() return {enemy} end} end,
})
local state=engine:GetState(hero)
local function tick(t) current=t;engine:EvaluateUnit(hero,state,t) end
local function action(a) return assert(engine.actions:Resolve(hero,{kind='ability',name=a.name,logical_id=a.name},{})) end
-- Enemy is outside Q range, so R starts. It moves into Q range during the barrage.
tick(10)
assert(#orders==1 and orders[1].AbilityIndex==kisses.id,'setup must submit the actual ultimate rule first')
assert(not hero:IsChanneling() and not hero:GetCurrentActiveAbility())
enemy.position=Vector(200)
for _,t in ipairs({10.8,11.3,15.5,25}) do
    tick(t)
    assert(#orders==1,'in-range Scatterblast/Lil Shredder must not replace the active barrage')
end
assert(not Lifecycle.ChannelElapsed(hero,kisses.name,current),'sustained protection must not invent native channel time')
-- Every final submission route also rejects interruption, independent of EvaluateUnit.
local specs={action(scatter),action(shredder),action(item),action(toggle),
    {kind='attack',logical_id='basic_attack',cast_type='attack',target_mode='unit'},
    {kind='move',logical_id='move',target_mode='point'}}
for _,spec in ipairs(specs) do
    local ok,why=engine.actions:CanExecute(hero,spec,{now=current})
    assert(not ok and why=='sustained_cast','direct availability must preserve the barrage')
    ok,why=engine.actions:Issue(hero,spec,enemy,{now=current})
    assert(not ok and why=='sustained_cast','direct orders must preserve the barrage')
    ok,why=engine.actions:IssueApproach(hero,spec,enemy)
    assert(not ok and why=='sustained_cast','approach orders must preserve the barrage')
end
assert(#orders==1)
-- No rules still means no fallback attack, and an old chase remains suspended.
rules={};tick(25.2);assert(#orders==1,'fallback must stay idle')
local chase={rule={action={kind='attack'}},rule_index=1}
state.chase=chase;tick(25.4)
assert(#orders==1 and state.chase==chase,'existing attack chase cannot resume during the barrage')
state.chase=nil
DOTA_UNIT_ORDER_STOP=21
local session={owns_order=true}
Movement.StopOrder(engine,hero,session,{now=current})
assert(#orders==1 and session.owns_order,'movement cleanup cannot issue STOP during the barrage')
local fallback=EnemyRuntime.new({execute_order=function(order) orders[#orders+1]=order;return true end})
fallback.fight_center=Vector(500)
assert(not fallback:CanFallbackOrder(hero))
assert(not fallback:IssueAttack(hero,enemy) and not fallback:IssueAttackMove(hero))
assert(#orders==1,'independent enemy fallback must not interrupt either')
-- A movement session expiring during the barrage must clean up without a STOP.
state.movement={rule={action={}},deadline=current-1,owns_order=true}
Movement.Continue(engine,hero,state,{now=current})
assert(state.movement==nil and #orders==1,'expired movement cannot cancel the barrage')
-- Native end/interruption removes the modifier: resume immediately, without a fixed wait.
hero.modifiers[modifier]=nil
assert(fallback:CanFallbackOrder(hero),'enemy fallback resumes after native end')
rules={H.rule(scatter.name)}
tick(25.6)
assert(#orders==2 and orders[2].AbilityIndex==scatter.id,'next evaluation after native end resumes Q')
hero.modifiers[modifier]={};tick(26);assert(#orders==2,'another native episode protects immediately')
hero.modifiers[modifier]=nil
hero.IsStunned=function() return true end
tick(26.2);assert(#orders==2,'enemy stun still applies after the native barrage ends')
hero.IsStunned=nil;tick(27)
assert(#orders==3 and orders[3].AbilityIndex==scatter.id,'early native interruption leaves no stale lock')
-- Owning/cooling down R, vision helpers, and ordinary buffs are not sustained casts.
hero.modifiers.modifier_snapfire_mortimer_kisses_vision_source={}
hero.modifiers.modifier_snapfire_lil_shredder_buff={}
assert(not engine:IsBusy(hero))
assert(engine.actions:CanExecute(hero,action(scatter),{now=current}))
hero.HasModifier=nil
assert(not engine:IsBusy(hero),'missing observation API cannot invent a sustained cast')
hero.HasModifier=function() error('native observation unavailable') end
assert(not engine:IsBusy(hero),'failed observation cannot leave a timer lock')
print('PASS Snapfire sustained cast: in-range Q/E, items, attacks, fallback/chase/STOP, native end and early interruption ('..tostring(arg and arg[1] or 'live')..')')
