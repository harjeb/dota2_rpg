"use strict";
const assert = require("assert");
const {runHud, click, panel, choice, input} = require("./condition-ui-v2.test");
const hero = "npc_dota_hero_axe", item = "item_black_king_bar";
function setup(action, actions, details) {
    const hud = runHud();
    const snapshot = {slot_key:"radiant_1", hero_index:42, hero_name:hero, rule_key:hero,
        can_edit:1, rules_ready:1, actions_text:actions, details_text:details,
        rules:[{action, enabled:1, use_conditions:[], target_filters:[], target_priorities:[]}]};
    hud.subscriptions.rpg_shop_state({lineup_text:hero, owned_text:hero});
    hud.subscriptions.rpg_hero_slots(snapshot);
    return {hud, snapshot};
}
function fallback(hud) {
    return panel(hud,"RadiantActionSelect0").children.find(p => p.BHasClass("ActionName")).text;
}
function equipment(hud, identity) {
    assert(!panel(hud,"RadiantActionSelect0").BHasClass("UnavailableAction"));
    assert.notEqual(fallback(hud),"#dota2_rpg_v2_unavailable");
    if (identity) {
        assert.equal(panel(hud,"RadiantActionAbility0").abilityname,identity);
        assert.equal(fallback(hud),"");
    } else {
        assert(fallback(hud),"unresolved legacy slot keeps its identifying label");
    }
    assert(panel(hud,"RadiantRuleSettings0").enabled,"equipment conditions remain editable");
}
// Exercise the actual HUD renderSide branch, including native IDs absent from a
// legacy slot list, slot hydration, removed inventory, and unresolved old slots.
for (const action of [item,"item_1"]) {
    const {hud,snapshot} = setup(action,"item_1;attack",item+";attack");
    equipment(hud,item);
    click(hud,"RadiantRuleSettings0");
    choice(hud,"V2_use0","self_hp_pct_gte"); input(hud,"V2_use0_value",77);
    click(hud,"RuleSettingsApply");
    hud.subscriptions.rpg_hero_slots(Object.assign({},snapshot,{actions_text:"attack",details_text:"attack"}));
    equipment(hud,item);
    click(hud,"RadiantRuleSettings0");
    assert.equal(panel(hud,"V2_use0_value").text,"77");
    click(hud,"RuleSettingsApply");
    const payload = hud.sentEvents.filter(e => e.name === "rpg_update_rule").at(-1).payload;
    assert.equal(payload.action_id,item);
    assert.equal(payload.action_name,item);
    assert.equal(payload.use_condition_1_value,0.77);
    assert.equal(payload.enabled,1,"presentation must not disable the rule");
}
equipment(setup(item,item+";attack",item+";attack").hud,item);
equipment(setup("item_1","attack","attack").hud,null);
const skill = "axe_berserkers_call";
const {hud,snapshot} = setup(skill,"attack","attack");
assert(panel(hud,"RadiantActionSelect0").BHasClass("UnavailableAction"));
assert.equal(fallback(hud),"#dota2_rpg_v2_unavailable","missing skills retain warning");
hud.subscriptions.rpg_hero_slots(Object.assign({},snapshot,{actions_text:skill+";attack",details_text:skill+";attack"}));
assert(!panel(hud,"RadiantActionSelect0").BHasClass("UnavailableAction"));
assert.equal(fallback(hud),"");
assert.equal(fallback(setup("attack","attack","attack").hud),"#dota2_rpg_action_attack");
console.log("PASS equipment condition render: no unavailable overlay, stable identity/edit/save, skill warnings preserved");
