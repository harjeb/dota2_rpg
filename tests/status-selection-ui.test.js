"use strict";
const assert = require('assert'), fs = require('fs'), path = require('path');
const {runHud, click, panel, input} = require('./condition-ui-v2.test');
const hud = runHud(), catalog = hud.context.RpgConditionCatalog;
const translations = {};
const chinese = fs.readFileSync(path.join(__dirname, '../game/dota_addons/dota2_rpg/resource/addon_schinese.txt'), 'utf8');
for (const match of chinese.matchAll(/"([^"\n]+)"\s+"([^"\n]*)"/g)) translations[match[1].toLowerCase()] = match[2];
// Representative native localization responses (game resources are not required by this offline test).
Object.assign(translations, {
    dota_tooltip_modifier_weaver_shukuchi: '缩地',
    dota_tooltip_ability_weaver_shukuchi: '缩地',
    dota_tooltip_ability_item_blade_mail: '刃甲',
    dota_tooltip_modifier_shared_a: '同名效果', dota_tooltip_modifier_shared_b: '同名效果'
});
hud.context.$.Localize = token => translations[token.replace(/^#/, '').toLowerCase()] || token;
const tooltips = [];
hud.context.$.DispatchEvent = (...args) => tooltips.push(args);
const phases = {IDLE:'尚未施放', REQUESTED:'已下达施法指令', CASTING:'施法前摇中', EXECUTED:'已施放',
    CHANNELING:'持续施法中', FINISHED:'持续施法正常完成', INTERRUPTED:'施法被打断', ENDED:'持续施法已结束', UNCONFIRMED:'施法结果未确认'};
for (const [value, label] of Object.entries(phases)) {
    let saved;
    catalog.open({}, {use_conditions:[{type:'action_phase_is', value:'IDLE', action_id:'weaver_shukuchi', action_actor:'ally:1'}]}, draft => { saved = draft; });
    assert.equal(panel(hud, 'V2_use0PhaseOption_' + value).GetChild(0).text, label);
    click(hud, 'V2_use0PhaseOption_' + value);
    assert.equal(panel(hud, 'V2_use0Phase').GetChild(0).text, label);
    click(hud, 'RuleSettingsApply');
    assert.equal(catalog.wire('use', saved.use_conditions[0]).value, value, 'translated phase retains native enum');
    assert.equal(saved.use_conditions[0].action_actor, 'ally:1');
    catalog.open({}, saved, () => {});
    assert.equal(panel(hud, 'V2_use0Phase').GetChild(0).text, label, 'reopen retains translated selection');
    assert(catalog.summary(saved).includes(label));
}
const cap = {version:1, name:'basic_attack', support:'builtin', mode:'attack', role:'trigger',
    cast:{}, teams:{self:1, ally:1, enemy:1}, types:{hero:1, monster:1, summon:1}, cast_preferences:{auto:1},
    modifiers:{modifier_weaver_shukuchi:1, modifier_native_item_effect:1, modifier_unknown:1, modifier_shared_a:1, modifier_shared_b:1},
    modifier_details:{modifier_weaver_shukuchi:{ability:'weaver_shukuchi'}, modifier_native_item_effect:{ability:'item_blade_mail', debuff:1}}};
let saved;
function open(settings) { catalog.open({action:'attack'}, settings, draft => { saved = draft; }, {capability:cap}); }
open({target_team:'enemy', use_conditions:[{type:'self_has_modifier', modifier:'modifier_weaver_shukuchi'}]});
const selected = panel(hud, 'V2_use0Modifier');
assert.equal(selected.GetChild(0).abilityname, 'weaver_shukuchi');
assert.equal(selected.GetChild(1).text, '缩地');
assert.equal(panel(hud, 'V2_use0ModifierOption_modifier_native_item_effect').GetChild(0).itemname, 'item_blade_mail');
assert.equal(panel(hud, 'V2_use0ModifierOption_modifier_native_item_effect').GetChild(1).text, '刃甲 · 减益效果');
assert.equal(panel(hud, 'V2_use0ModifierOption_modifier_unknown').GetChild(0).text, '未命名状态');
assert.notEqual(panel(hud, 'V2_use0ModifierOption_modifier_shared_a').GetChild(0).text,
    panel(hud, 'V2_use0ModifierOption_modifier_shared_b').GetChild(0).text, 'same native caption remains distinguishable');
selected.events.onmouseover();
assert.equal(tooltips.pop()[2], 'modifier_weaver_shukuchi', 'raw identity remains available on hover');
click(hud, 'V2_use0ModifierOption_modifier_native_item_effect'); click(hud, 'RuleSettingsApply');
assert.equal(saved.use_conditions[0].modifier, 'modifier_native_item_effect');
assert.equal(catalog.wire('use', saved.use_conditions[0]).value, 'modifier_native_item_effect');
open(saved); assert.equal(panel(hud, 'V2_use0Modifier').GetChild(1).text, '刃甲 · 减益效果');
assert(!panel(hud, 'V2_use0_modifier'), 'modifier selection has no raw text entry');
click(hud, 'V2_use0ModifierOption_modifier_weaver_shukuchi');
assert.equal(panel(hud, 'V2_use0Modifier').GetChild(1).text, '缩地', 'native dropdown refreshes readable selection');
click(hud, 'RuleSettingsApply'); assert.equal(saved.use_conditions[0].modifier, 'modifier_weaver_shukuchi');
open({target_team:'enemy', use_conditions:[{type:'self_has_modifier', modifier:'modifier_unobserved'}]});
saved = null; click(hud, 'RuleSettingsApply'); assert.equal(saved, null, 'restored unknown modifier cannot silently authorize save');
assert(!panel(hud, 'V2ModifierAck'), 'unknown modifier acknowledgement is not exposed');
click(hud, 'V2_use0ModifierOption_modifier_weaver_shukuchi'); click(hud, 'RuleSettingsApply');
assert.equal(saved.use_conditions[0].modifier, 'modifier_weaver_shukuchi', 'known native choice repairs legacy unknown modifier');
// Older servers provide only the name set; native localized labels still work without icon metadata.
delete cap.modifier_details;
open({target_team:'enemy', target_filters:[{type:'modifier_remaining_lte', modifier:'modifier_weaver_shukuchi', seconds:2}]});
assert.equal(panel(hud, 'V2_target0Modifier').GetChild(0).text, '缩地');
click(hud, 'RuleSettingsApply'); assert.equal(saved.target_filters[0].seconds, 2);
const summaryA = catalog.summary({use_conditions:[{type:'self_has_modifier', modifier:'modifier_manual_a'}]});
const summaryB = catalog.summary({use_conditions:[{type:'self_has_modifier', modifier:'modifier_manual_b'}]});
assert.notEqual(summaryA, summaryB, 'unlocalized modifier summaries retain their distinct identities');
assert(catalog.summary(saved).includes('缩地'));
console.log('PASS Chinese status selection: all lifecycle phases, native modifier names, source icons, duplicate captions, raw wire values, reopen and advanced validation');
