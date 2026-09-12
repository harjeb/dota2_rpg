"use strict";
const assert = require("assert");
const {runHud, click, panel, choice, input} = require("./condition-ui-v2.test");
const hero = "npc_dota_hero_axe";
function setup() {
    const hud = runHud();
    const snapshot = {slot_key:"radiant_1", hero_index:42, hero_name:hero, rule_key:hero,
        can_edit:1, rules_ready:1, actions_text:"attack;axe_berserkers_call", abilities_text:"axe_berserkers_call",
        rules:[{action:"attack", enabled:1, target_team:"enemy", min_aoe_hits:4,
            use_conditions:[], target_filters:[], target_priorities:[]}]};
    hud.subscriptions.rpg_shop_state({lineup_text:hero, owned_text:hero});
    hud.subscriptions.rpg_hero_slots(snapshot);
    hud.sentEvents.length = 0;
    return {hud, snapshot};
}
function updates(hud) { return hud.sentEvents.filter(e => e.name === "rpg_update_rule"); }
function edit(hud, switching) {
    if (switching) {
        click(hud,"RadiantActionSelect0"); click(hud,"ActionOpt_Radiant0_axe_berserkers_call");
    } else { click(hud,"RadiantRuleSettings0"); }
    assert(!panel(hud,"V2_min_aoe_hits") && !panel(hud,"V2AoeSelect"), "hit gate is never offered");
    choice(hud,"V2_use0","self_hp_pct_gte"); input(hud,"V2_use0_value",77);
}
function refresh(hud, snapshot) {
    const button = panel(hud,"V2RefreshCapability");
    assert(button && button.visible && button.hittest && button.enabled, "manual refresh is visible and clickable");
    const before = hud.sentEvents.filter(e => e.name === "rpg_request_battle_state").length;
    click(hud,"V2RefreshCapability");
    assert.equal(hud.sentEvents.filter(e => e.name === "rpg_request_battle_state").length, before + 1,
        "refresh requests authoritative battle/capability state exactly once");
    hud.subscriptions.rpg_hero_slots(snapshot);
}
for (const switching of [false,true]) {
    const {hud,snapshot} = setup();
    edit(hud,switching); refresh(hud,JSON.parse(JSON.stringify(snapshot)));
    assert.equal(panel(hud,"V2_use0_value").text,"77", "refresh retains unsaved input");
    click(hud,"RuleSettingsApply");
    assert.equal(updates(hud).length,1, "first Apply after refresh saves exactly once");
    assert.equal(updates(hud)[0].payload.use_condition_1_value,0.77);
    assert.equal(updates(hud)[0].payload.action_id,switching ? "axe_berserkers_call" : "basic_attack");
    assert(!("min_aoe_hits" in updates(hud)[0].payload), "legacy hit gate is stripped on wire");
    click(hud,"RadiantRuleSettings0");
    assert.equal(panel(hud,"V2_use0_value").text,"77", "first save persists when reopened");
}
for (const switching of [false,true]) {
    const {hud,snapshot} = setup();
    snapshot.rules[0].use_conditions = [{type:"self_hp_pct_gte",value:0.5}];
    snapshot.rules[0].target_filters = [{type:"hp_pct_lte",value:0.8}];
    hud.subscriptions.rpg_hero_slots(snapshot);
    edit(hud,switching);
    const equivalent = JSON.parse(JSON.stringify(snapshot));
    equivalent.rules[0].use_conditions = [{value:0.5,type:"self_hp_pct_gte"}];
    equivalent.rules[0].target_filters = [{value:0.8,type:"hp_pct_lte"}];
    refresh(hud,equivalent); click(hud,"RuleSettingsApply");
    assert.equal(updates(hud).length,1, "equivalent condition/filter key order preserves the edit binding");
    assert.equal(updates(hud)[0].payload.use_condition_1_value,0.77);
    assert.equal(updates(hud)[0].payload.target_filter_1_value,switching ? undefined : 0.8,
        "equivalent snapshot keeps existing gates; skill selection replaces them with recommendations");
}
for (const switching of [false,true]) {
    for (const change of ["entity","hero","action","changed-rule","reorder","delete","condition-order","priority-order"]) {
        const {hud,snapshot} = setup();
        if (change === "reorder" || change === "delete") {
            snapshot.rules.push({action:"axe_berserkers_call",enabled:1,target_team:"enemy",use_conditions:[]});
            hud.subscriptions.rpg_hero_slots(snapshot);
        }
        if (change === "condition-order" || change === "priority-order") {
            snapshot.rules[0].use_conditions = [{type:"self_hp_pct_gte",value:0.5},{type:"self_mana_pct_gte",value:0.4}];
            snapshot.rules[0].target_priorities = [{type:"nearest"},{type:"lowest_hp_pct"}];
            hud.subscriptions.rpg_hero_slots(snapshot);
        }
        edit(hud,switching);
        const replaced = JSON.parse(JSON.stringify(snapshot));
        if (change === "entity") replaced.hero_index = 43;
        if (change === "hero") { replaced.hero_name = "npc_dota_hero_lion"; replaced.rule_key = replaced.hero_name; }
        if (change === "action") replaced.rules[0].action = "axe_berserkers_call";
        if (change === "changed-rule") replaced.rules[0].use_conditions = [{type:"self_hp_pct_gte",value:12}];
        if (change === "reorder") replaced.rules.reverse();
        if (change === "delete") replaced.rules.shift();
        if (change === "condition-order") replaced.rules[0].use_conditions.reverse();
        if (change === "priority-order") replaced.rules[0].target_priorities.reverse();
        refresh(hud,replaced); click(hud,"RuleSettingsApply");
        assert.equal(updates(hud).length,0, (switching ? "action-switch" : "settings") + " rejects stale " + change);
        assert(!panel(hud,"RuleSettings").BHasClass("Hidden"), "rejected Apply does not silently close");
        assert(panel(hud,"RuleSettingsError").text, "rejected Apply explains the conflict");
    }
}
{
    const {hud} = setup(), sync = hud.context.RpgRuleSync;
    const legacy = {action:"attack",min_aoe_hits:20,use_conditions:[{type:"nearby_enemies_gte",value:2,radius:800}],
        target_filters:[{type:"nearby_allies_gte",value:1,radius:600}]};
    assert(!("min_aoe_hits" in sync.fromServer(legacy)));
    assert(!("min_aoe_hits" in sync.initialSettings(legacy)));
    let saved;
    hud.context.RpgConditionCatalog.open(legacy,legacy,draft => { saved = draft; });
    click(hud,"RuleSettingsApply");
    assert(!("min_aoe_hits" in saved), "legacy drafts drop the removed field");
    assert.equal(saved.use_conditions[0].type,"nearby_enemies_gte");
    assert.equal(saved.target_filters[0].type,"nearby_allies_gte");
    assert(!hud.context.RpgConditionCatalog.summary(legacy).includes("min_aoe_hits"));
}
// Skill recommendations are a draft; ordinary reopen preserves authored rules.
{
    const hud=runHud(), hero='npc_dota_hero_omniknight', ability='omniknight_purification';
    hud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    hud.subscriptions.rpg_hero_slots({slot_key:'radiant_1',hero_index:77,hero_name:hero,rule_key:hero,
        can_edit:1,rules_ready:1,actions_text:'attack;'+ability,
        rules:[{action:'attack',enabled:0,target_team:'enemy',desired_autocast_state:0,
            use_conditions:[{type:'elapsed_gte',seconds:9,value:9}],
            target_filters:[{type:'distance_gte',value:1234}],target_priorities:[{type:'farthest'}]}]});
    const before=updates(hud).length, preset=hud.context.RpgSkillPresets.get(ability);
    function select() { click(hud,'RadiantActionSelect0'); click(hud,'ActionOpt_Radiant0_'+ability); }
    select();
    assert.equal(updates(hud).length,before,'selection does not save');
    assert.equal(panel(hud,'V2TeamSelect').GetChild(0).text,'#dota2_rpg_v2_team_'+preset.target_team);
    assert(!panel(hud,'V2_use0_seconds'),'old elapsed gate is replaced in draft');
    click(hud,'RuleSettingsClose'); click(hud,'RadiantRuleSettings0');
    assert.equal(panel(hud,'V2_use0_seconds').text,'9','cancel keeps original conditions');
    click(hud,'RuleSettingsApply');
    assert.equal(updates(hud).at(-1).payload.action_id,'basic_attack','cancel keeps original action');
    assert.equal(updates(hud).at(-1).payload.enabled,0,'cancel keeps disabled rule');
    select(); click(hud,'RuleSettingsApply');
    const wire=updates(hud).at(-1).payload;
    const expected=hud.context.RpgRuleSync.serialize({rule:Object.assign({action:ability},preset)});
    assert.equal(wire.action_id,ability); assert.equal(wire.enabled,0,'selection preserves enabled state');
    assert.equal(wire.hero_index,77); assert.equal(wire.hero_name,hero); assert.equal(wire.slot,1);
    for (const key of Object.keys(expected).filter(key=>/^(use_condition_|target_filter_|target_priority_|target_team$)/.test(key))) {
        assert.equal(wire[key],expected[key],'first recommended preset replaces '+key);
    }
    assert.equal(wire.desired_autocast_state,undefined,'unsupported old autocast flag is removed');
    click(hud,'RadiantRuleSettings0'); input(hud,'V2_target0_value',61); click(hud,'RuleSettingsApply');
    click(hud,'RadiantRuleSettings0');
    assert.equal(panel(hud,'V2_target0_value').text,'61','reopen does not reapply recommendation');
    click(hud,'RuleSettingsClose');
}
// Newly equipped item is advertised before its authoritative contract arrives.
{
    const {hud, snapshot} = setup();
    const api = hud.context.RpgAbilityCapabilities, receive = api.receive;
    api.receive = event => { if (event.action_id !== "item_blink") receive(event); };
    snapshot.actions_text += ";item_blink";
    hud.subscriptions.rpg_hero_slots(snapshot);
    api.receive = receive;
    const pending = [];
    hud.context.$.Schedule = (delay, callback) => { pending.push(callback); };
    const flush = () => { while (pending.length) pending.shift()(); };
    click(hud,"RadiantActionSelect0"); click(hud,"ActionOpt_Radiant0_item_blink");
    choice(hud,"V2_use0","self_hp_pct_gte"); input(hud,"V2_use0_value",77);
    assert.equal(panel(hud,"RuleSettingsApply").enabled,false,"new equipment waits for real metadata");
    assert.equal(panel(hud,"RuleSettingsError").text,"capability_unavailable");
    click(hud,"V2RefreshCapability");
    assert.equal(updates(hud).length,0,"refresh never saves a draft");
    const cap = JSON.parse(JSON.stringify(api.get(42,"attack",hero,2)));
    cap.name="item_blink"; cap.mode="point"; cap.support="generic";
    cap.cast.point=1; cap.cast_preferences.point=1;
    const event = {hero_index:42,rule_key:hero,revision:2,action_id:"item_blink",capability:cap};
    hud.subscriptions.rpg_action_capability(Object.assign({},event,{revision:1})); flush();
    assert.equal(panel(hud,"RuleSettingsApply").enabled,false,"old capability cannot unlock new equipment");
    hud.subscriptions.rpg_action_capability(Object.assign({},event,{hero_index:99})); flush();
    assert.equal(panel(hud,"RuleSettingsApply").enabled,false,"another hero cannot unlock new equipment");
    hud.subscriptions.rpg_action_capability(Object.assign({},event,{action_id:"item_force_staff",capability:Object.assign({},cap,{name:"item_force_staff"})})); flush();
    assert.equal(panel(hud,"RuleSettingsApply").enabled,false,"another item cannot unlock this draft");
    hud.subscriptions.rpg_action_capability(Object.assign({},event,{rule_key:"npc_dota_hero_lion"})); flush();
    assert.equal(panel(hud,"RuleSettingsApply").enabled,false,"mixed hero identity cannot unlock this draft");
    hud.subscriptions.rpg_action_capability(event); flush();
    assert.equal(panel(hud,"RuleSettingsApply").enabled,true,"matching response enables the first Apply");
    assert.equal(panel(hud,"RuleSettingsError").text,"");
    assert.equal(panel(hud,"V2_use0_value").text,"77","asynchronous responses preserve unsaved input");
    click(hud,"RuleSettingsApply");
    assert.equal(updates(hud).length,1);
    assert.equal(updates(hud)[0].payload.action_id,"item_blink");
    assert.equal(updates(hud)[0].payload.hero_index,42);
    assert.equal(updates(hud)[0].payload.use_condition_1_value,.77);
    click(hud,"RadiantRuleSettings0");
    assert.equal(panel(hud,"V2_use0_value").text,"77","new equipment draft persists on first save");
    const oldRefresh = panel(hud,"V2RefreshCapability").events.onactivate;
    click(hud,"RuleSettingsClose"); click(hud,"RadiantRuleSettings0");
    const before = hud.sentEvents.length;
    oldRefresh();
    assert.equal(hud.sentEvents.length,before,"a replaced dialog's callback cannot refresh the new dialog");
}
console.log("PASS: first settings/action-switch saves survive equivalent refresh snapshots regardless of object key order; stale hero/action/changed/reordered/deleted rules and condition/priority array order remain protected; legacy hit gate removed and nearby counts preserved");
