"use strict";

const assert = require("assert");
const {runHud, click, panel, input} = require("./condition-ui-v2.test");
const WK = "npc_dota_hero_skeleton_king", ULT = "skeleton_king_reincarnation";
const AXE = "npc_dota_hero_axe";
const attack = {action:"attack", enabled:1, target_team:"enemy", use_conditions:{}, target_filters:{}, target_priorities:{}};
const ultimate = {action:ULT, enabled:1, target_team:"self", use_conditions:{}, target_filters:{}, target_priorities:{}};
const timedUltimate = Object.assign({}, ultimate, {use_conditions:{1:{type:"elapsed_gte", value:120, seconds:120}}});
function updates(h) { return h.sentEvents.filter(e => e.name === "rpg_update_rule").map(e => e.payload); }
function shop(h, generation, hero=WK) {
    h.subscriptions.rpg_shop_state({rule_generation:generation, lineup_text:hero, owned_text:hero});
}
function slots(h, generation, entity=346, hero=WK, rules={1:ultimate, 2:attack}) {
    h.subscriptions.rpg_hero_slots({rule_generation:generation, slot_key:"radiant_1", hero_index:entity,
        hero_name:hero, rule_key:hero, can_edit:1, rules_ready:1, actions_text:ULT+";attack", rules});
}
function edit(h, row) { click(h, "RadiantRuleSettings"+row); click(h, "RuleSettingsApply"); return updates(h).at(-1); }
function authored() {
    const h = runHud();
    shop(h, 1);
    slots(h, 1, 346, WK, {1:attack, 2:timedUltimate});
    const saved = edit(h, 1);
    assert.strictEqual(saved.action_id, ULT);
    assert.strictEqual(saved.use_condition_1_seconds, 120);
    h.subscriptions.rpg_rule_update_result({request_id:saved.request_id, ok:1});
    return h;
}

// Native failure: new test of the same hero has [unrestricted ult, attack],
// but the old UI kept showing [attack, timed ult] and only sent slot 2.
for (const order of ["hero_first", "shop_first"]) {
    const h = authored(), before = updates(h).length;
    if (order === "shop_first") shop(h, 2);
    slots(h, 2, 396);
    shop(h, 2);
    assert.strictEqual(updates(h).length, before, "hydration never sends old rules back to the server");
    assert.strictEqual(panel(h, "RadiantActionAbility0").abilityname, ULT, "visible first row matches new server default");
    const first = edit(h, 0), second = edit(h, 1);
    assert.strictEqual(first.action_id, ULT);
    assert(!first.use_condition_1_type, "old elapsed condition is gone from fresh default");
    assert.strictEqual(second.action_id, "basic_attack", "editing row 2 cannot resend the old timed ultimate");
    assert.strictEqual(second.rule_count, 2);
}

// A generation change also clears open drafts, menus and failure notices.
{
    const h = authored();
    const rejected = edit(h, 1);
    h.subscriptions.rpg_rule_update_result({request_id:rejected.request_id, ok:0, reason:"wrong_phase"});
    assert.strictEqual(panel(h, "RuleSyncNotice").visible, true);
    const pending = edit(h, 1);
    click(h, "RadiantRuleSettings1"); input(h, "V2_use0_seconds", 89);
    const staleApply = panel(h, "RuleSettingsApply").events.onactivate;
    const before = updates(h).length;
    shop(h, 2, "");
    assert(panel(h, "RuleSettings").BHasClass("Hidden"), "new run closes the old draft");
    assert.strictEqual(panel(h, "RuleSettingsBody").GetChildCount(), 0, "old draft controls are removed");
    assert.strictEqual(panel(h, "RuleSettingsApply").enabled, false);
    assert.strictEqual(panel(h, "RuleSyncNotice").visible, false);
    assert(panel(h, "RadiantRule0").BHasClass("Hidden"), "empty new lineup shows no old rules");
    click(h, "RuleSettingsApply");
    slots(h, 2, 346); shop(h, 2); // native entity index may be reused
    staleApply();
    h.subscriptions.rpg_rule_update_result({request_id:pending.request_id, ok:0, reason:"invalid_hero"});
    assert.strictEqual(updates(h).length, before, "old callbacks cannot author the new run");
    assert.strictEqual(panel(h, "RuleSettingsError").text, "", "old drafts cannot restore an error");
    assert.strictEqual(panel(h, "RuleSyncNotice").visible, false, "late replies cannot restore old failures");
    const fresh = edit(h, 0);
    assert.notStrictEqual(fresh.request_id, pending.request_id, "reset keeps request IDs unique");
    assert.strictEqual(fresh.action_id, ULT);
}

// Same-generation respawns (normal stages and test reset) retain authored rules.
{
    const h = authored();
    slots(h, 1, 400); shop(h, 1);
    assert.strictEqual(edit(h, 0).action_id, "basic_attack");
    click(h, "RadiantRuleSettings1"); input(h, "V2_use0_seconds", 75);
    slots(h, 1, 400); shop(h, 1); // repeated snapshot/capability refresh
    assert(!panel(h, "RuleSettings").BHasClass("Hidden"));
    click(h, "RuleSettingsApply");
    assert.strictEqual(updates(h).at(-1).use_condition_1_seconds, 75);
}

// Both slot and shop snapshots can arrive first for a different selected hero.
for (const order of ["hero_first", "shop_first"]) {
    const h = authored();
    if (order === "shop_first") shop(h, 2, AXE);
    slots(h, 2, 500, AXE, {1:attack}); shop(h, 2, AXE);
    assert(panel(h, "RadiantRule1").BHasClass("Hidden"));
    assert.strictEqual(edit(h, 0).hero_name, AXE);
    // Leave the sandbox with an empty normal roster; recruiting WK starts fresh.
    shop(h, 3, "");
    assert(panel(h, "RadiantRule0").BHasClass("Hidden"));
    shop(h, 3); slots(h, 3, 600);
    assert.strictEqual(edit(h, 0).action_id, ULT);
}

// Battle/roster snapshots may precede the shop and must carry the same epoch.
for (const firstEvent of ["rpg_battle_state", "rpg_enemy_roster"]) {
    const h = authored();
    click(h, "RadiantActionSelect0");
    assert(!panel(h, "RadiantActionMenu0").BHasClass("Hidden"));
    const staleAction = panel(h, "ActionOpt_Radiant0_attack").events.onactivate;
    h.subscriptions[firstEvent]({rule_generation:2, phase:"setup", ready:1, units:[{id:700, name:AXE}]});
    assert(panel(h, "RadiantActionMenu0").BHasClass("Hidden"));
    assert.strictEqual(panel(h, "RadiantActionMenu0").GetChildCount(), 0);
    assert(panel(h, "RadiantRule0").BHasClass("Hidden"));
    slots(h, 2, 600); shop(h, 2);
    const before = updates(h).length;
    staleAction(); click(h, "RuleSettingsApply");
    assert(panel(h, "RuleSettings").BHasClass("Hidden"), "old action options cannot reopen the editor");
    assert.strictEqual(updates(h).length, before, "old action choices cannot modify new rules");
    assert.strictEqual(edit(h, 0).action_id, ULT);
    // Delayed snapshots from an older run cannot reinstate old actors or rules.
    slots(h, 1, 346, WK, {1:attack, 2:timedUltimate}); shop(h, 1, AXE);
    h.subscriptions.rpg_battle_state({rule_generation:1, phase:"fight", ready:0});
    assert.strictEqual(edit(h, 0).hero_index, 600);
    assert.strictEqual(updates(h).at(-1).action_id, ULT);
}
// A fresh replay generation must clear equipment selection, warehouse rows and
// result notices immediately, even when the battle snapshot precedes the shop.
{
    const h = authored();
    panel(h, "ItemSellNotice").text = "Old sale";
    panel(h, "ItemTransferNotice").text = "Old transfer";
    h.subscriptions.rpg_battle_state({rule_generation:2, phase:"setup", ready:0, settlement_generation:9});
    assert.strictEqual(panel(h, "ItemSellNotice").text, "");
    assert.strictEqual(panel(h, "ItemTransferNotice").text, "");
    assert(panel(h, "RadiantRule0").BHasClass("Hidden"));
    h.subscriptions.rpg_shop_state({rule_generation:2, gold:500, owned_text:"", lineup_text:"", free_recruit_choices:2});
    assert(panel(h, "WalletBalance").text.includes("500"));
    slots(h, 1, 346, WK, {1:attack, 2:timedUltimate});
    assert(panel(h, "RadiantRule0").BHasClass("Hidden"), "old hero snapshots cannot repopulate a fresh run");
}
console.log("PASS: fresh test/exit clear authored rules, draft controls, menus and pending results; same-run respawns preserve edits; reordered snapshots and reused entities stay consistent");
