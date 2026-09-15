"use strict";
const assert = require("assert");
const {runHud, click, panel} = require("./condition-ui-v2.test");
const hud = runHud(), hero = "npc_dota_hero_axe";
const sync = hud.context.RpgRuleSync;
const dirty = {action:"buyback",enabled:false,target_team:"enemy",target:"enemy_distance_nearest",forced:true,
    use_conditions:[{type:"self_hp_pct_lte",value:30}],target_filters:[{type:"is_casting"}],target_priorities:[{type:"farthest"}],
    cast_preference:"point",desired_toggle_state:true,destination:"target_behind",destination_distance:700,
    positioning_mode:"fixed",positioning_distance:100,state_policy:"mana_hysteresis",movement_mode:"follow"};
const payload = sync.serialize({rule:dirty,heroName:hero,heroIndex:42,slot:2,ruleCount:2,actionName:"wrong_spell"});
assert.equal(payload.action_kind,"buyback"); assert.equal(payload.action_id,"buyback"); assert.equal(payload.enabled,0);
assert.equal(payload.target_team,"self"); assert.equal(payload.target_mode,"self"); assert.equal(payload.target_types,"hero");
assert.equal(payload.approach,"range_only"); assert.equal(payload.rule_count,2);
assert(!Object.keys(payload).some(k => /^(use_condition_\d|target_filter_\d|target_priority_\d|positioning_|movement_|state_|desired_|destination)/.test(k)));
const restored = sync.fromServer(Object.assign({},dirty,{action_kind:"buyback",enabled:0}));
assert.equal(restored.action,"buyback"); assert.equal(restored.enabled,false); assert.equal(restored.target,"self");
assert.equal(restored.use_conditions.length,0); assert.equal(restored.cast_preference,undefined);
for (const disabled of [false,0,"0"]) assert.equal(sync.serialize({rule:{action:"buyback",enabled:disabled}}).enabled,0);
assert.equal(sync.buybackCost(1),155); assert.equal(sync.buybackCost(30),6100);
for (let level=1; level<=30; level++) assert.equal(sync.buybackCost(level),100+50*level+5*level*level);
const localize = hud.context.$.Localize;
hud.context.$.Localize = token => token === "#dota2_rpg_v2_buyback_cost" ? "Level {level}: {cost} gold" : localize(token);
hud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero,hero_data_text:hero+":12:0:common:0"});
const snapshot = {slot_key:"radiant_1",hero_index:42,hero_name:hero,rule_key:hero,can_edit:1,rules_ready:1,
    actions_text:"buyback;attack",details_text:";attack",rules:[{action:"attack",enabled:1,target_team:"enemy",use_conditions:[]}]};
hud.subscriptions.rpg_hero_slots(snapshot);
hud.sentEvents.length=0;
assert(!hud.createdPanels.some(p => p.id === "RadiantRule1"),"catalog option alone creates no default buyback rule");
click(hud,"RadiantActionSelect0"); click(hud,"ActionOpt_Radiant0_buyback");
assert(panel(hud,"V2BuybackHelp"));
assert.equal(panel(hud,"V2BuybackCost").text,"Level 12: 1420 gold");
const body = panel(hud,"RuleSettingsBody");
assert(!body.children.some(p => /V2Team|V2_use|V2_target|V2_priority|V2Approach|V2_positioning/.test(p.id)),"no combat controls for buyback");
click(hud,"RuleSettingsApply");
let updates = () => hud.sentEvents.filter(e => e.name === "rpg_update_rule");
assert.equal(updates().at(-1).payload.action_kind,"buyback"); assert.equal(updates().at(-1).payload.enabled,1);
click(hud,"RadiantRuleSettings0"); click(hud,"V2BuybackEnabled"); click(hud,"RuleSettingsApply");
assert.equal(updates().at(-1).payload.enabled,0,"buyback can be disabled without deletion");
click(hud,"RadiantRuleSettings0");
assert.equal(panel(hud,"V2BuybackEnabledLabel").text,"#dota2_rpg_v2_buyback_disabled");
click(hud,"RuleSettingsClose");
click(hud,"RadiantActionSelect0"); click(hud,"ActionOpt_Radiant0_attack");
assert(body.children.some(p => p.id === "V2TargetTeamRow"),"switching away restores normal combat editor");
click(hud,"RuleSettingsClose");
const arenaHud = runHud();
arenaHud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
arenaHud.subscriptions.rpg_hero_slots(Object.assign({},snapshot,{actions_text:"attack",details_text:"attack",
    rules:[{action:"buyback",enabled:0,target_team:"self",use_conditions:[]}]}));
click(arenaHud,"RadiantActionSelect0");
assert(!panel(arenaHud,"ActionOpt_Radiant0_buyback"),"ineligible catalog hides buyback from picker");
assert(panel(arenaHud,"RadiantActionSelect0").BHasClass("UnavailableAction"),"saved buyback stays visible as unavailable");
click(arenaHud,"RadiantRuleSettings0");
assert.equal(panel(arenaHud,"V2BuybackEnabledLabel").text,"#dota2_rpg_v2_buyback_disabled","disabled snapshot restores without enabling");
console.log("PASS buyback menu, enable/disable, combat-control exclusion, canonical serialization/restoration and all 30 costs");
