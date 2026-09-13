"use strict";
const assert = require("assert");
const {runHud, click, panel} = require("./condition-ui-v2.test");
const HERO = "npc_dota_hero_lion", FIRST = "lion_impale", SECOND = "lion_finger_of_death";
function rule(action, seconds, enabled = 1) {
    return {action, enabled, target_team:"enemy", use_conditions:seconds ? [{type:"elapsed_gte",seconds,value:seconds}] : [],
        target_filters:[], target_priorities:[{type:"nearest"}]};
}
function setup(rules) {
    const h = runHud();
    h.subscriptions.rpg_shop_state({rule_generation:1,lineup_text:HERO,owned_text:HERO});
    h.subscriptions.rpg_hero_slots({rule_generation:1,slot_key:"radiant_1",hero_index:510,hero_name:HERO,
        rule_key:HERO,can_edit:1,rules_ready:1,actions_text:FIRST+";"+SECOND+";attack",rules});
    return h;
}
function updates(h) { return h.sentEvents.filter(e=>e.name==="rpg_update_rule").map(e=>e.payload); }
function current(h, count) {
    const rows = updates(h).slice(-count);
    assert.deepStrictEqual(rows.map(r=>r.slot),Array.from({length:count},(_,i)=>i+1));
    assert(rows.every(r=>r.rule_count===count && r.hero_index===510));
    return rows;
}
// The initial attack keeps its conditions; selecting the inserted first row
// produces a real skill before it in the server payload, not just the display.
{
    const h = setup([rule("attack",7)]);
    click(h,"RadiantAddRule0");
    const rows=current(h,2);
    assert.strictEqual(rows[0].use_condition_1_type,"");
    assert.strictEqual(rows[1].use_condition_1_seconds,7);
    click(h,"RadiantActionSelect0"); click(h,"ActionOpt_Radiant0_"+FIRST); click(h,"RuleSettingsApply");
    assert.strictEqual(updates(h).at(-1).slot,1);
    assert.strictEqual(updates(h).at(-1).action_id,FIRST);
    assert.strictEqual(panel(h,"RadiantActionAbility0").abilityname,FIRST);
    click(h,"RadiantRuleSettings1"); click(h,"RuleSettingsApply");
    assert.strictEqual(updates(h).at(-1).action_id,"basic_attack");
    assert.strictEqual(updates(h).at(-1).use_condition_1_seconds,7);
}
// Repair a pre-existing attack-first list on addition. Both skill and attack
// groups retain their ordering, enabled flags and authored time conditions.
{
    const h=setup([rule("attack",11,0),rule(FIRST,3),rule("attack",22),rule(SECOND,9)]);
    assert.strictEqual(updates(h).length,0,"hydrating existing/manual order does not rewrite it");
    click(h,"RadiantAddRule0");
    let rows=current(h,5);
    assert.deepStrictEqual(rows.map(r=>r.action_id),[FIRST,SECOND,SECOND,"basic_attack","basic_attack"]);
    assert.deepStrictEqual(rows.map(r=>r.use_condition_1_seconds),[3,9,undefined,11,22]);
    assert.strictEqual(rows[3].enabled,0);
    assert.strictEqual(rows[2].target_filter_1_type,"");
    assert.strictEqual(rows[2].target_priority_1_type,"");
    click(h,"RadiantAddRule0");
    rows=current(h,6);
    assert.deepStrictEqual(rows.map(r=>r.action_id),[FIRST,SECOND,SECOND,SECOND,"basic_attack","basic_attack"]);
    assert.strictEqual(rows[4].use_condition_1_seconds,11);
    assert.strictEqual(rows[5].use_condition_1_seconds,22);
    // Manual priority remains authoritative until the next explicit Add.
    click(h,"RadiantUp4");
    rows=current(h,6);
    assert.strictEqual(rows[3].action_id,"basic_attack");
    assert.strictEqual(rows[4].action_id,SECOND);
}
// No attack means ordinary append; adding never invents a missing fallback.
{
    const h=setup([rule(FIRST,4),rule(SECOND,8)]);
    click(h,"RadiantAddRule0");
    assert.deepStrictEqual(current(h,3).map(r=>r.action_id),[FIRST,SECOND,SECOND]);
}
// At the row limit, even an attack-first authored list is left untouched.
{
    const h=setup([rule("attack",5),...Array.from({length:31},()=>rule(FIRST,2))]);
    assert.strictEqual(panel(h,"RadiantAddRule0").enabled,false);
    const before=updates(h).length;
    panel(h,"RadiantAddRule0").events.onactivate();
    assert.strictEqual(updates(h).length,before);
    click(h,"RadiantRuleSettings0"); click(h,"RuleSettingsApply");
    assert.strictEqual(updates(h).at(-1).action_id,"basic_attack");
}
console.log("PASS added rules precede attacks; actual skill selection, stable settings/order, full server sync, manual priority and row limit");
