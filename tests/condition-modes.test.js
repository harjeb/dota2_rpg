"use strict";
const assert=require('assert');
const {runHud,click,panel,choice,input}=require('./condition-ui-v2.test');
const hero='npc_dota_hero_axe';
function setup(rule={}) {
 const hud=runHud();
 const snapshot={slot_key:'radiant_1',hero_index:42,hero_name:hero,rule_key:hero,can_edit:1,rules_ready:1,
  actions_text:'attack;axe_berserkers_call',abilities_text:'axe_berserkers_call',
  rules:[Object.assign({action:'attack',enabled:1,target_team:'enemy',use_conditions:[],target_filters:[],target_priorities:[]},rule)]};
 hud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});hud.subscriptions.rpg_hero_slots(snapshot);hud.sentEvents.length=0;
 return {hud,snapshot};
}
function mode(hud,group,value) {click(hud,'V2_'+group+'ModeOption_'+value);}
function caption(hud,group) {
 const row=panel(hud,'V2_'+group+'ModeRow');
 assert.equal(row.children.length,2,'both modes are directly visible');
 const selected=row.children.filter(button=>button.BHasClass('Selected'));
 assert.equal(selected.length,1,'exactly one mode is highlighted');
 assert(!panel(hud,'V2_'+group+'ModeMenu'),'mode switch has no dropdown');
 return selected[0].GetChild(0).text;
}
function saved(hud) {return hud.sentEvents.filter(e=>e.name==='rpg_update_rule').at(-1).payload;}
for(const um of ['all','priority']) for(const tm of ['all','priority']) {
 const {hud}=setup();click(hud,'RadiantRuleSettings0');
 assert.equal(caption(hud,'use'),'#dota2_rpg_v2_mode_all');assert.equal(caption(hud,'target'),'#dota2_rpg_v2_mode_all');
 choice(hud,'V2_use0','self_hp_pct_lte');input(hud,'V2_use0_value',77);
 mode(hud,'use',um);assert.equal(panel(hud,'V2_use0_value').text,'77','mode changes retain unsaved field readers');
 mode(hud,'target',tm);assert.equal(caption(hud,'use'),'#dota2_rpg_v2_mode_'+um,'switches are independent');
 choice(hud,'V2_target0','hp_pct_lte');input(hud,'V2_target0_value',81);
 click(hud,'RuleSettingsApply');let wire=saved(hud);
 assert.equal(wire.use_conditions_mode,um);assert.equal(wire.target_filters_mode,tm);
 assert.equal(wire.use_condition_1_value,.77);assert.equal(wire.target_filter_1_value,.81);
 click(hud,'RadiantRuleSettings0');assert.equal(caption(hud,'use'),'#dota2_rpg_v2_mode_'+um);assert.equal(caption(hud,'target'),'#dota2_rpg_v2_mode_'+tm);
 click(hud,'RuleSettingsClose');
 click(hud,'RadiantActionSelect0');click(hud,'ActionOpt_Radiant0_axe_berserkers_call');
 assert.equal(caption(hud,'use'),'#dota2_rpg_v2_mode_'+um,'action recommendations preserve combination choices');
 assert.equal(caption(hud,'target'),'#dota2_rpg_v2_mode_'+tm);
 click(hud,'RuleSettingsApply');wire=saved(hud);assert.equal(wire.action_id,'axe_berserkers_call');assert.equal(wire.use_conditions_mode,um);assert.equal(wire.target_filters_mode,tm);
}
{
 const {hud,snapshot}=setup({use_conditions_mode:'priority',target_filters_mode:'all'});
 click(hud,'RadiantRuleSettings0');mode(hud,'target','priority');
 choice(hud,'V2_use0','self_hp_pct_gte');input(hud,'V2_use0_value',82);
 click(hud,'V2RefreshCapability');hud.subscriptions.rpg_hero_slots(JSON.parse(JSON.stringify(snapshot)));
 assert.equal(caption(hud,'target'),'#dota2_rpg_v2_mode_priority','refresh preserves unsaved mode');
 assert.equal(panel(hud,'V2_use0_value').text,'82');click(hud,'RuleSettingsApply');assert.equal(saved(hud).target_filters_mode,'priority');
 click(hud,'RadiantRuleSettings0');mode(hud,'use','all');click(hud,'RuleSettingsClose');click(hud,'RadiantRuleSettings0');
 assert.equal(caption(hud,'use'),'#dota2_rpg_v2_mode_priority','cancel does not mutate saved mode');
 click(hud,'V2ClearConditions');assert.equal(caption(hud,'use'),'#dota2_rpg_v2_mode_priority','clearing conditions does not change combination preference');
 click(hud,'RuleSettingsApply');assert.equal(saved(hud).use_condition_1_type,'');
}
{
 const {hud}=setup(),sync=hud.context.RpgRuleSync,api=hud.context.RpgAbilityCapabilities;
 for(const value of [undefined,null,false,1,{},'garbage','all','priority']) {
  const original={action:'attack',use_conditions_mode:value,target_filters_mode:value,use_conditions:[],target_filters:[]};
  const expected=value==='priority'?'priority':'all';
  for(const normalized of [sync.initialSettings(original),sync.fromServer(original),sync.serialize({rule:original})]) {
   assert.equal(normalized.use_conditions_mode,expected);assert.equal(normalized.target_filters_mode,expected);
  }
 }
 const source={action:'attack',enabled:1,use_conditions_mode:'priority',target_filters_mode:'all',
  use_conditions:[{type:'self_hp_pct_gte',value:.8},{type:'self_hp_pct_lte',value:.2}],target_filters:[]};
 const restored=sync.fromServer(JSON.parse(JSON.stringify(source))),copy=sync.initialSettings(restored);
 copy.use_conditions_mode='all';copy.use_conditions[0].value=90;
 assert.equal(restored.use_conditions_mode,'priority');assert.equal(restored.use_conditions[0].value,80);
 assert(api.validate(restored,null).ok,'priority alternative ranges are valid');
 assert(!api.validate(copy,null).ok,'all still detects contradictory ranges');
 const cross={target_team:'self',use_conditions:[{type:'self_hp_pct_gte',value:80}],target_filters:[{type:'hp_pct_lte',value:20}]};
 assert(!api.validate(cross,null).ok);cross.target_filters_mode='priority';assert(api.validate(cross,null).ok,'no invalid cross-group AND proof across an OR');
 assert(hud.context.RpgConditionCatalog.summary(restored).includes('#dota2_rpg_v2_mode_priority'),'tooltip exposes combination mode');
}
console.log('PASS independent modes: actual HUD controls, apply/reopen/refresh/cancel/clear/action switching, wire/legacy/malformed normalization, copy isolation and compatibility');
