"use strict";
const assert = require("assert");
const {runHud, click, panel, choice, input} = require("./condition-ui-v2.test");
const hero = "npc_dota_hero_axe";
const first = "item_black_king_bar", second = "item_blade_mail";
function updates(hud) { return hud.sentEvents.filter(e => e.name === "rpg_update_rule"); }
function setup(action) {
    const hud = runHud();
    const snapshot = {slot_key:"radiant_1", hero_index:42, hero_name:hero, rule_key:hero,
        can_edit:1, rules_ready:1, actions_text:"item_1;attack", details_text:first + ";attack",
        rules:[{action, enabled:1, target_team:"enemy", use_conditions:[], target_filters:[], target_priorities:[]},
            {action:"attack", enabled:1, use_conditions:[]}]};
    hud.subscriptions.rpg_shop_state({lineup_text:hero, owned_text:hero});
    hud.subscriptions.rpg_hero_slots(snapshot);
    hud.sentEvents.length = 0;
    return {hud, snapshot};
}
for (const source of [first, "item_1", "attack"]) {
    const {hud, snapshot} = setup(source);
    if (source === "attack") {
        click(hud,"RadiantActionSelect0"); click(hud,"ActionOpt_Radiant0_item_1");
    } else { click(hud,"RadiantRuleSettings0"); }
    choice(hud,"V2_use0","self_hp_pct_gte"); input(hud,"V2_use0_value",77);
    click(hud,"RuleSettingsApply");
    assert.equal(updates(hud).at(-1).payload.action_id,first);
    // Purchase/repacking inserts the second item before the first. The server
    // snapshot is ignored for authored rows, exactly as in a live HUD session.
    const refreshed = Object.assign({}, snapshot, {actions_text:"item_1;item_2;attack",
        details_text:second + ";" + first + ";attack"});
    hud.subscriptions.rpg_hero_slots(refreshed);
    click(hud,"RadiantRuleSettings0");
    assert.equal(panel(hud,"V2_use0_value").text,"77", "purchase retains authored conditions");
    click(hud,"RuleSettingsApply");
    assert.equal(updates(hud).at(-1).payload.action_id,first, "purchase must not retarget conditions to the new occupant");
    assert.equal(updates(hud).at(-1).payload.action_name,first);
    assert.equal(updates(hud).at(-1).payload.use_condition_1_value,0.77);
    // Reordering sends every rule, which previously persisted the accidental retarget.
    click(hud,"RadiantUp1");
    const reordered = updates(hud).slice(-2).map(e => e.payload);
    assert.deepEqual(reordered.map(p => p.action_id),["basic_attack",first]);
    assert.equal(reordered[1].use_condition_1_value,0.77);
    // Removing the original item cannot make its authored rule inherit another item.
    hud.subscriptions.rpg_hero_slots(Object.assign({}, refreshed, {actions_text:"item_1;attack", details_text:second + ";attack"}));
    click(hud,"RadiantRuleSettings1"); click(hud,"RuleSettingsApply");
    assert.equal(updates(hud).at(-1).payload.action_id,first);
}
{
    const {hud, snapshot} = setup("attack");
    click(hud,"RadiantActionSelect0"); click(hud,"ActionOpt_Radiant0_item_1");
    choice(hud,"V2_use0","self_hp_pct_gte"); input(hud,"V2_use0_value",61);
    hud.subscriptions.rpg_hero_slots(Object.assign({}, snapshot, {actions_text:"item_1;item_2;attack",
        details_text:second + ";" + first + ";attack"}));
    click(hud,"RuleSettingsApply");
    assert.equal(updates(hud).length,1,"an inventory refresh preserves a draft bound to the selected item");
    assert.equal(updates(hud)[0].payload.action_id,first);
    assert.equal(updates(hud)[0].payload.use_condition_1_value,0.61);
}
console.log("PASS item rule identity across native/legacy hydration, selection, purchase, reordering and removal");
