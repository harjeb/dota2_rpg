"use strict";
const assert = require("assert");
const {runHud, click, panel, choice, input} = require("./condition-ui-v2.test");
const HERO = "npc_dota_hero_axe", OTHER = "npc_dota_hero_lion";
const disk = {};
const localStorage = {GetItem:key=>disk[key], SetItem:(key,value)=>{disk[key]=value;}};
function launch(hero=HERO, entity=42, actions="attack;axe_berserkers_call") {
    const hud = runHud({localStorage});
    hud.subscriptions.rpg_shop_state({lineup_text:hero, owned_text:hero});
    const snapshot = {slot_key:"radiant_1",hero_index:entity,hero_name:hero,rule_key:hero,
        can_edit:1,rules_ready:1,actions_text:actions,abilities_text:actions,
        rules:[{action:"attack",enabled:1,target_team:"enemy",use_conditions:[],target_filters:[],target_priorities:[]}]};
    hud.subscriptions.rpg_hero_slots(snapshot);
    return {hud,snapshot};
}
function updates(hud) {return hud.sentEvents.filter(e=>e.name==="rpg_update_rule");}
function ack(hud, ok=1) {updates(hud).forEach(e=>hud.subscriptions.rpg_rule_update_result({request_id:e.payload.request_id,ok}));}
function edit(hud,value) {
    click(hud,"RadiantRuleSettings0"); choice(hud,"V2_use0","self_hp_pct_gte"); input(hud,"V2_use0_value",value); click(hud,"RuleSettingsApply");
}
let first=launch();
edit(first.hud,77);
assert.equal(first.hud.context.RpgRuleLibrary.count(),0,"unacknowledged changes never saved");
ack(first.hud);
assert.equal(first.hud.context.RpgRuleLibrary.count(),1);
assert.equal(first.hud.context.RpgRuleLibrary.get(HERO)[0].use_conditions[0].value,77);
let next=launch(HERO,99);
assert.equal(updates(next.hud).length,0,"new game keeps server defaults despite a local backup");
next.hud.context.RpgRuleLibrary.importText(first.hud.context.RpgRuleLibrary.exportText());
assert.equal(updates(next.hud).length,1,"only manual import applies saved hero");
assert.equal(updates(next.hud)[0].payload.hero_index,99,"uses current entity");
assert.equal(updates(next.hud)[0].payload.use_condition_1_value,.77,"percent encoded once");
ack(next.hud);
next.hud.subscriptions.rpg_hero_slots(next.snapshot);
assert.equal(updates(next.hud).length,1,"refresh cannot repeatedly restore");
edit(next.hud,66); ack(next.hud,0);
assert.equal(next.hud.context.RpgRuleLibrary.get(HERO)[0].use_conditions[0].value,77,"rejected draft preserves backup");
let other=launch(OTHER,200,"attack;lion_impale");
edit(other.hud,55); ack(other.hud);
assert.equal(other.hud.context.RpgRuleLibrary.count(),2,"all heroes accumulate across reloads");
const doc=JSON.parse(other.hud.context.RpgRuleLibrary.exportText());
assert.equal(doc.heroes[HERO][0].use_conditions[0].value,77);
assert.equal(doc.heroes[OTHER][0].use_conditions[0].value,55);
// Import an unrelated hero must not overwrite or resend the current hero.
const before=updates(other.hud).length;
other.hud.context.RpgRuleLibrary.importText(JSON.stringify({format:doc.format,version:1,heroes:{[HERO]:doc.heroes[HERO]}}));
assert.equal(updates(other.hud).length,before);
// Imports during combat persist, and apply only when preparation resumes.
other.hud.subscriptions.rpg_battle_state({phase:"fight"});
const imported=JSON.parse(JSON.stringify(doc.heroes[OTHER])); imported[0].use_conditions[0].value=33;
other.hud.context.RpgRuleLibrary.importText(JSON.stringify({format:doc.format,version:1,heroes:{[OTHER]:imported}}));
assert.equal(updates(other.hud).length,before);
other.hud.subscriptions.rpg_battle_state({phase:"setup"});
assert.equal(updates(other.hud).at(-1).payload.use_condition_1_value,.33);
ack(other.hud);
// All-or-wait restoration with missing equipment, preserving saved row order.
const equipment=JSON.parse(JSON.stringify(doc.heroes[HERO]));
equipment.unshift({action:"item_blink",enabled:true,forced:false,use_conditions:[],target_filters:[],target_priorities:[]});
other.hud.context.RpgRuleLibrary.importText(JSON.stringify({format:doc.format,version:1,heroes:{[HERO]:equipment}}));
const geared=launch();
assert.equal(updates(geared.hud).length,0,"new run does not apply imported profiles from a previous run");
geared.hud.context.RpgRuleLibrary.importText(other.hud.context.RpgRuleLibrary.exportText());
assert.equal(updates(geared.hud).length,0);
assert(panel(geared.hud,"RuleLibraryNotice").visible);
geared.hud.subscriptions.rpg_hero_slots(Object.assign({},geared.snapshot,{actions_text:"attack;axe_berserkers_call;item_blink"}));
assert.equal(updates(geared.hud).length,2);
assert.equal(updates(geared.hud)[0].payload.action_id,"item_blink");
assert.equal(updates(geared.hud)[1].payload.slot,2);
assert.equal(panel(geared.hud,"RuleLibraryNotice").visible,false);
ack(geared.hud);
// New server generation clears import intent even if the engine reuses the entity index.
const n=updates(geared.hud).length;
geared.hud.subscriptions.rpg_hero_slots(Object.assign({},geared.snapshot,{rule_generation:1,actions_text:"attack;axe_berserkers_call;item_blink"}));
assert.equal(updates(geared.hud).length,n,"new run must keep defaults until another explicit import");
geared.hud.context.RpgRuleLibrary.importText(geared.hud.context.RpgRuleLibrary.exportText());
assert.equal(updates(geared.hud).length,n+2,"manual import still works after generation reset");
console.log("PASS: real HUD accepted backups, manual import with current entity, new-run defaults, percent roundtrip, hero accumulation, rejected backup protection, phase gate, equipment defer and import-intent reset");
