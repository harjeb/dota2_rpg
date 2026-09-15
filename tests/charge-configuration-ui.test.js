"use strict";
const assert = require('assert');
const {runHud, click, panel, input} = require('./condition-ui-v2.test');
const ids = ['windrunner_powershot','keeper_of_the_light_illuminate','monkey_king_primal_spring','ringmaster_tame_the_beasts','primal_beast_onslaught','hoodwink_sharpshooter','alchemist_unstable_concoction','oracle_fortunes_end'];
function setup(action, extra={}) {
    const hud=runHud(), hero='npc_dota_hero_windrunner';
    const snapshot={slot_key:'radiant_1',hero_index:42,hero_name:hero,rule_key:hero,can_edit:1,rules_ready:1,
        actions_text:action+';attack',abilities_text:action,rules:[Object.assign({action,enabled:1,target_team:'enemy',use_conditions:[],target_filters:[],target_priorities:[]},extra)]};
    hud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    hud.subscriptions.rpg_hero_slots(snapshot); hud.sentEvents.length=0;
    return {hud,snapshot};
}
const saved=h=>h.sentEvents.filter(e=>e.name==='rpg_update_rule').at(-1).payload;
const select=(h,v)=>{click(h,'V2ChargeSelect');click(h,'V2ChargeSelectOption_charge_'+v);};
for(const action of ids) {
    const {hud,snapshot}=setup(action);
    click(hud,'RadiantRuleSettings0'); assert(panel(hud,'V2ChargeSelect'));
    select(hud,'time'); assert.equal(panel(hud,'V2_charge_time').text,'1');
    input(hud,'V2_charge_time',1.25); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).charge_mode,'time'); assert.equal(saved(hud).charge_time,1.25);
    snapshot.rules=[Object.assign({},saved(hud),{action,enabled:1,use_conditions:[],target_filters:[],target_priorities:[]})];
    hud.subscriptions.rpg_hero_slots(snapshot);
    click(hud,'RadiantRuleSettings0'); assert.equal(panel(hud,'V2_charge_time').text,'1.25');
    select(hud,'max'); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).charge_mode,'max'); assert.equal(saved(hud).charge_time,undefined);
    click(hud,'RadiantRuleSettings0'); select(hud,'disabled'); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).charge_mode,undefined); assert.equal(saved(hud).charge_time,undefined);
    click(hud,'RadiantRuleSettings0'); select(hud,'time'); input(hud,'V2_charge_time',0); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).charge_time,0);
    click(hud,'RadiantRuleSettings0'); click(hud,'V2ClearConditions'); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).charge_mode,undefined);
}
for(const action of ['pudge_dismember','bane_fiends_grip','crystal_maiden_freezing_field','windrunner_powershot_release','attack','item_blink']) {
    const {hud}=setup(action,{charge_mode:'time',charge_time:2});
    click(hud,'RadiantRuleSettings0'); assert(!panel(hud,'V2ChargeSelect'),action);
    click(hud,'RuleSettingsApply'); assert.equal(saved(hud).charge_mode,undefined);
}
{
    const {hud}=setup(ids[0],{charge_mode:'max'});
    click(hud,'RadiantActionSelect0'); click(hud,'ActionOpt_Radiant0_attack'); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).charge_mode,undefined);
    const sync=hud.context.RpgRuleSync;
    for(const [value,expected] of [[undefined,1],['bad',1],[Infinity,1],[-1,0],[200,120]]) {
        const rule=sync.fromServer({action:ids[0],charge_mode:'time',charge_time:value});
        assert.equal(sync.initialSettings(rule).charge_time,expected);
        assert.equal(sync.serialize({rule}).charge_time,expected);
    }
    assert.equal(sync.serialize({rule:{action:'ability_0',charge_mode:'max'},actionName:ids[0]}).charge_mode,'max');
}
console.log('charge configuration UI roundtrip tests passed');
