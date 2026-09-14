"use strict";

// Exercise the shipped scripts/layout, not a copy of targetActors.
const assert = require("assert");
const {runHud, click, panel, choice} = require("./condition-ui-v2.test");
const axe = "npc_dota_hero_axe", lion = "npc_dota_hero_lion";
const field = "V2_target0_target_actor";
function roster(chapter) {
    return [lion, lion, "npc_dota_neutral_centaur_khan", "npc_dota_roshan"].map((name, i) =>
        ({id: 901 + i, name, target_actor: chapter + ":enemy:" + name + ":" + i}));
}
function setup(generation = 1, action = "attack") {
    const h = runHud();
    h.subscriptions.rpg_shop_state({rule_generation:generation,lineup_text:axe,owned_text:axe});
    h.subscriptions.rpg_hero_slots({rule_generation:generation,slot_key:"radiant_1",hero_index:900,hero_name:axe,
        rule_key:axe,can_edit:1,rules_ready:1,actions_text:action,rules:[{action,enabled:1,target_team:action === "attack" ? "enemy" : "ally"}]});
    return h;
}
function sendRoster(h, units, generation = 1) {
    h.subscriptions.rpg_enemy_roster({rule_generation:generation,units});
}
function slots(h, units, indices, generation = 1) {
    indices.forEach((slot, i) => h.subscriptions.rpg_hero_slots({rule_generation:generation,
        slot_key:"dire_" + slot,hero_index:units[i].id,hero_name:units[i].name,
        rule_key:"capability:" + i,target_actor:"slot-must-not-win:" + i,
        actions_text:"attack;lion_impale",abilities_text:"lion_impale"}));
}
function open(h, kind = "specified_enemy") {
    click(h,"RadiantRuleSettings0"); choice(h,"V2_target0",kind); click(h,field);
    return panel(h,field + "Menu");
}
function latest(h) {
    return h.sentEvents.filter(e => e.name === "rpg_update_rule").slice(-1)[0].payload;
}
for (const indices of [[], [1,2], [1,2,3,4], [1,2,4,5]]) {
    for (const order of ["before", "after"]) {
        const h = setup(), units = roster("ch05");
        if (order === "before") slots(h,units,indices);
        // Numeric-key CustomGameEvent arrays are the server's wire representation.
        sendRoster(h,Object.fromEntries(units.map((u,i) => [String(i+1),u])));
        if (order === "after") slots(h,units,indices);
        assert.strictEqual(open(h).children.length,5,`${order} slots ${indices}: all roster targets`);
        assert.strictEqual(panel(h,field + "Option_1").GetChild(0).heroname,lion);
        assert.strictEqual(panel(h,field + "Option_2").GetChild(0).type,"Image");
        for (let i = 0; i < units.length; i++) {
            if (i) { click(h,"RadiantRuleSettings0"); click(h,field); }
            click(h,field + "Option_" + i); click(h,"RuleSettingsApply");
            assert.strictEqual(latest(h).target_filter_1_target_actor,units[i].target_actor,
                "roster actor wins over absent/mismatched slot actor; duplicate names stay distinct");
        }
    }
}
const h = setup(), old = roster("ch05"), next = roster("ch06");
sendRoster(h,old); open(h);
click(h,field + "Option_1"); click(h,"RuleSettingsApply");
click(h,"RadiantRuleSettings0"); click(h,field);
const stale = panel(h,field + "Option_1");
sendRoster(h,next); // Same IDs/names, only actor changed: signature must not skip this.
stale.events.onactivate();
assert(!panel(h,field + "Menu").BHasClass("Hidden"),"stale click refreshes rather than selects");
assert(panel(h,field).BHasClass("V2UnavailableTarget"),"old chapter selection unavailable");
click(h,"RuleSettingsApply");
assert.strictEqual(latest(h).target_filter_1_target_actor,old[1].target_actor,"never silently retarget");
click(h,"RadiantRuleSettings0"); click(h,field);
const removed = panel(h,field + "Option_3");
sendRoster(h,[next[0]]); removed.events.onactivate();
assert.strictEqual(panel(h,field + "Menu").children.length,2,"removed target refreshes open menu");
click(h,field + "Option_0"); click(h,"RuleSettingsApply");
assert.strictEqual(latest(h).target_filter_1_target_actor,next[0].target_actor);
// Stale slot messages cannot replace roster-owned identities.
slots(h,old,[1,2]);
assert.strictEqual(open(h).children.length,2);
click(h,field + "Option_0"); click(h,"RuleSettingsApply");
assert.strictEqual(latest(h).target_filter_1_target_actor,next[0].target_actor);

const fresh = setup(2);
sendRoster(fresh,next,2);
for (const invalid of [1, -1, 1.5, "bad"]) sendRoster(fresh,old,invalid);
slots(fresh,old,[1,2],1);
assert.strictEqual(open(fresh).children.length,5,"reconnect/current generation rejects stale/invalid events");
click(fresh,field + "Option_1"); click(fresh,"RuleSettingsApply");
assert.strictEqual(latest(fresh).target_filter_1_target_actor,next[1].target_actor);
click(fresh,"RadiantRuleSettings0"); click(fresh,field);
const priorGeneration = panel(fresh,field + "Option_1");
sendRoster(fresh,roster("ch07"),3);
assert(panel(fresh,"RuleSettings").BHasClass("Hidden"),"new generation closes editor");
const writes = fresh.sentEvents.filter(e => e.name === "rpg_update_rule").length;
priorGeneration.events.onactivate(); click(fresh,"RuleSettingsApply");
assert.strictEqual(fresh.sentEvents.filter(e => e.name === "rpg_update_rule").length,writes,"old generation cannot save");

const ally = setup(1,"sustained_move");
sendRoster(ally,next);
assert.strictEqual(open(ally,"specified_ally").children.length,2,"ally still requires authorized slot rule key");
click(ally,field + "Option_0"); click(ally,"RuleSettingsApply");
assert.strictEqual(latest(ally).target_filter_1_target_actor,axe,"ally uses stable rule key, not enemy actor");
// Action-reference ability choices still require independently supplied capability slots.
const abilities = setup();
sendRoster(abilities,next);
click(abilities,"RadiantRuleSettings0"); choice(abilities,"V2_use0","action_elapsed_gte");
click(abilities,"V2_use0_action_id");
assert(!panel(abilities,"V2_use0_action_idOption_1_0"),"roster alone fabricates no enemy abilities");
slots(abilities,next,[1]);
click(abilities,"RadiantRuleSettings0"); choice(abilities,"V2_use0","action_elapsed_gte");
click(abilities,"V2_use0_action_id");
assert.strictEqual(panel(abilities,"V2_use0_action_idOption_1_0").GetChild(0).abilityname,"lion_impale",
    "action-reference picker retains slot-provided abilities");
const missing = setup();
sendRoster(missing,[{id:901,name:lion},{id:-1,name:lion,target_actor:"invalid"}]);
assert.strictEqual(open(missing).children.length,1,"no guessed actors or invalid entities");
console.log("PASS: roster-owned enemy targets, event ordering, sparse slots, duplicate actors, chapter refresh and generation guards");
