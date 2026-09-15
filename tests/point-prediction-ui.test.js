"use strict";
const assert = require('assert');
const {runHud, click, panel, input} = require('./condition-ui-v2.test');
const hero = 'npc_dota_hero_lina';
function setup(action = 'lina_light_strike_array', extra = {}) {
    const hud = runHud();
    const snapshot = {slot_key:'radiant_1', hero_index:42, hero_name:hero, rule_key:hero,
        can_edit:1, rules_ready:1, actions_text:action + ';attack', abilities_text:action,
        rules:[Object.assign({action, enabled:1, target_team:'enemy', use_conditions:[],
            target_filters:[{type:'distance_gte',value:100}], target_priorities:[{type:'farthest'}]},extra)]};
    hud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    hud.subscriptions.rpg_hero_slots(snapshot); hud.sentEvents.length=0;
    return {hud,snapshot};
}
function live(h, id) {
    function visit(p) { return p.id === id || p.children.some(visit); }
    return visit(panel(h,'RuleSettingsBody'));
}
const saved = h => h.sentEvents.filter(e => e.name === 'rpg_update_rule').at(-1).payload;
function prediction(h, value) { click(h,'V2PredictionSelect'); click(h,'V2PredictionSelectOption_prediction_' + value); }
for (const action of ['lina_light_strike_array','item_blink']) {
    const {hud,snapshot} = setup(action);
    click(hud,'RadiantRuleSettings0');
    const body = panel(hud,'RuleSettingsBody');
    assert(body.children.indexOf(panel(hud,'V2PredictionTitle')) > body.children.indexOf(panel(hud,'V2_priority1')), 'prediction follows sorting');
    assert(!panel(hud,'V2_prediction_distance'),'disabled by default');
    prediction(hud,'forward'); assert.equal(panel(hud,'V2_prediction_distance').text,'200');
    input(hud,'V2_prediction_distance',375); click(hud,'RuleSettingsApply');
    let wire = saved(hud);
    assert.equal(wire.prediction_direction,'forward'); assert.equal(wire.prediction_distance,375);
    assert.equal(wire.target_filter_1_type,'distance_gte'); assert.equal(wire.target_priority_1_type,'farthest');
    snapshot.rules=[Object.assign({},wire,{action,enabled:1,target_filters:[{type:'distance_gte',value:100}],target_priorities:[{type:'farthest'}]})];
    hud.subscriptions.rpg_hero_slots(snapshot);
    click(hud,'RadiantRuleSettings0'); assert.equal(panel(hud,'V2_prediction_distance').text,'375','authoritative snapshot roundtrip');
    prediction(hud,'backward'); assert.equal(panel(hud,'V2_prediction_distance').text,'375');
    input(hud,'V2_prediction_distance',0); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).prediction_distance,0); assert.equal(saved(hud).prediction_direction,'backward');
    click(hud,'RadiantRuleSettings0'); prediction(hud,'disabled'); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).prediction_direction,undefined); assert.equal(saved(hud).prediction_distance,undefined);
    click(hud,'RadiantRuleSettings0'); assert(!live(hud,'V2_prediction_distance'),'disable clears saved fields');
    prediction(hud,'forward'); input(hud,'V2_prediction_distance',4000); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).prediction_distance,3000);
    click(hud,'RadiantRuleSettings0'); click(hud,'V2_priority0Select'); click(hud,'V2_priority0SelectOption_destination_target_behind');
    assert(!live(hud,'V2PredictionSelect'),'special destination removes prediction'); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).prediction_direction,undefined);
}
{
    const {hud}=setup('lina_light_strike_array',{prediction_direction:'forward',prediction_distance:600});
    click(hud,'RadiantActionSelect0'); click(hud,'ActionOpt_Radiant0_attack');
    assert(!panel(hud,'V2PredictionSelect')); click(hud,'RuleSettingsApply');
    assert.equal(saved(hud).prediction_direction,undefined); assert.equal(saved(hud).prediction_distance,undefined);
    const sync=hud.context.RpgRuleSync;
    for (const [distance,expected] of [[undefined,200],['',200],['bad',200],[-5,0],[Infinity,200],[9000,3000]]) {
        const rule=sync.fromServer({action:'lina_light_strike_array',prediction_direction:'backward',prediction_distance:distance});
        assert.equal(sync.serialize({rule}).prediction_distance,expected);
        assert.equal(sync.initialSettings(rule).prediction_distance,expected);
    }
    const cap={mode:'point',cast:{point:1},teams:{enemy:1},types:{hero:1}};
    for (const name of ['ember_spirit_fire_remnant','elder_titan_ancestral_spirit']) {
        assert(sync.predictionAllowed({action:name},cap),'ordinary spirit placement supports prediction');
    }
    for (const excluded of [Object.assign({},cap,{mode:'none'}),Object.assign({},cap,{mode:'unit'}),
        Object.assign({},cap,{cast:{point:1,vector:1}}),Object.assign({},cap,{blocked_reason:'tree_target'})]) {
        assert(!sync.predictionAllowed({action:'test_point'},excluded),'unsupported capabilities reject prediction');
    }
    assert(!sync.predictionAllowed({action:'test_point',cast_preference:'unit'},cap));
    assert.equal(sync.serialize({rule:{action:'attack',prediction_direction:'forward',prediction_distance:500}}).prediction_direction,undefined);
    assert.equal(sync.serialize({rule:{action:'lina_light_strike_array',prediction_direction:'invalid',prediction_distance:500}}).prediction_distance,undefined);
}
console.log('point prediction UI roundtrip tests passed');
