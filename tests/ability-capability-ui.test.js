"use strict";
const assert=require('assert'), fs=require('fs'),path=require('path'),vm=require('vm');
const helpers=require('./condition-ui-v2.test');const {runHud,click,panel,choice,input}=helpers;
const hud=runHud(), hero='npc_dota_hero_omniknight';
hud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
hud.subscriptions.rpg_hero_slots({slot_key:'radiant_1',hero_index:42,hero_name:hero,rule_key:hero,can_edit:1,rules_ready:1,
 actions_text:'omniknight_purification;attack',rules:[{action:'omniknight_purification',enabled:1,target_team:'enemy',use_conditions:[],target_filters:[]}]});
const api=hud.context.RpgAbilityCapabilities;
const cap={version:1,name:'omniknight_purification',mode:'unit',role:'native_unit',support:'partial',
 teams:{self:1,ally:1,enemy:0},types:{hero:1,monster:0,summon:1},
 cast:{unit:1,point:0,none:0,toggle:0,autocast:0,vector:0},cast_preferences:{auto:1,unit:1,point:0},variants:{default:1,alternate:0},
 modifiers:{},release_parent:'',
 magic_immune_enemy:0,magic_immune_ally:1};
cap.native_unit_contract={teams:cap.teams,types:cap.types,magic_immune_enemy:0,magic_immune_ally:1};
api.receive({hero_index:42,rule_key:hero,revision:1,action_id:cap.name,capability:cap});
function updates(){return hud.sentEvents.filter(e=>e.name==='rpg_update_rule');}
click(hud,'RadiantRuleSettings0');
assert(!panel(hud,'V2TeamSelectOption_team_enemy').enabled,'native enemy choice disabled');
assert(!panel(hud,'V2ToggleSelectOption_toggle_on').enabled,'toggle cannot be assigned to heal');
assert(!panel(hud,'V2AutocastSelectOption_autocast_off').enabled,'autocast cannot be assigned to heal');
assert(!panel(hud,'V2CastSelectOption_cast_point').enabled,'unit spell cannot be forced to point');
assert(!panel(hud,'V2VariantSelectOption_alternate').enabled,'unimplemented alternate variant is explicit');
assert(!panel(hud,'V2AoeSelectOption_2'),'unproven splash count is unavailable');
assert(panel(hud,'RuleSettingsError').text.includes('target_team_incompatible'));
click(hud,'RuleSettingsApply');assert.equal(updates().length,0,'invalid restored rule is not silently rewritten/saved');
choice(hud,'V2Team','team_ally');click(hud,'RuleSettingsApply');assert.equal(updates()[0].payload.target_team,'ally');
click(hud,'RadiantRuleSettings0');choice(hud,'V2_use0','self_hp_pct_gte');input(hud,'V2_use0_value',80);
choice(hud,'V2_use1','self_hp_pct_lte');input(hud,'V2_use1_value',20);
click(hud,'RuleSettingsApply');assert.equal(updates().length,1);assert(panel(hud,'RuleSettingsError').text.includes('contradictory_conditions'));
click(hud,'RuleSettingsClose');click(hud,'RadiantRuleSettings0');assert.equal(panel(hud,'V2_use0Select').GetChild(0).text,'#dota2_rpg_v2_none','cancel preserves original gates');
choice(hud,'V2_use0','self_has_modifier');input(hud,'V2_use0_modifier','modifier_never_seen');click(hud,'RuleSettingsApply');
assert.equal(updates().length,1);assert(panel(hud,'RuleSettingsError').text.includes('unverified_modifier_requires_ack'));
click(hud,'V2ModifierAck');click(hud,'V2ModifierAckOption_yes');click(hud,'RuleSettingsApply');
assert.equal(updates().length,2);assert.equal(updates()[1].payload.allow_unverified_modifiers,1);
const beforeIcon=panel(hud,'RadiantActionAbility0').abilityname;
click(hud,'RadiantActionSelect0');click(hud,'ActionOpt_Radiant0_attack');click(hud,'RuleSettingsClose');
assert.equal(panel(hud,'RadiantActionAbility0').abilityname,beforeIcon,'cancel skill switch leaves old identity intact');assert.equal(updates().length,2);
click(hud,'RadiantRuleSettings0');
api.receive({hero_index:42,rule_key:hero,revision:2,action_id:cap.name,capability:cap});
click(hud,'RuleSettingsApply');assert.equal(updates().length,2,'stale modal revision cannot authorize save');
assert(panel(hud,'RuleSettingsError').text.includes('capability_unavailable'));
assert.equal(api.get(42,cap.name,hero,1),null);assert(api.get(42,cap.name,hero,2));
api.receive({hero_index:42,rule_key:hero,revision:1,action_id:cap.name,capability:cap});assert(api.get(42,cap.name,hero,2),'late old revision ignored');
assert.equal(api.get(42,'__proto__',hero,2),null,'prototype key is not a registered action');
const malformedModifier={target_team:'ally',use_conditions:[{type:'self_has_modifier',modifier:'__proto__'}],target_filters:[]};
assert(!api.validate(malformedModifier,cap).ok,'prototype name cannot bypass modifier acknowledgement');
const auto=JSON.parse(JSON.stringify(cap));auto.name='viper_poison_attack';auto.cast.autocast=1;auto.teams={self:0,ally:0,enemy:1};auto.native_unit_contract.teams=auto.teams;
const rule={target_team:'ally',target_types:['hero'],desired_autocast_state:false,state_policy:'mana_hysteresis',state_mana_on:.4,state_mana_off:.2,state_hold_seconds:.75,use_conditions:[],target_filters:[]};
assert(api.validate(rule,auto).ok,'managed autocast uses observation targets, not offensive spell targets');
assert(!api.validate({...rule,desired_autocast_state:null,state_policy:'fixed'},auto).ok,'manual cast restores native enemy constraint');
const sync=hud.context.RpgRuleSync,payload=sync.serialize({actionId:auto.name,actionName:auto.name,rule:rule});
assert.equal(payload.desired_autocast_state,'0');assert.equal(payload.target_team,'ally');assert.equal(payload.target_types,'hero');
const restored=sync.fromServer({...payload,action:auto.name});assert.equal(restored.desired_autocast_state,false);assert.equal(sync.serialize({rule:restored}).desired_autocast_state,'0');
assert(!api.validate({...rule,state_mana_on:.2},auto).ok,'empty hysteresis interval blocked');
const release=JSON.parse(JSON.stringify(auto));release.release_parent='keeper_of_the_light_illuminate';
assert(api.validate({target_team:'enemy',use_conditions:[{type:'channel_elapsed_gte',seconds:2}],target_filters:[]},release).ok);
assert(!api.validate({target_team:'ally',use_conditions:[{type:'channel_elapsed_gte',seconds:2}],target_filters:[]},cap).ok,'ordinary action cannot cast during its own channel');
console.log('PASS strict capability UI: disabled native choices, preserved invalid rules, contradictions, modifier acknowledgement, cancel, stale revisions, false autocast serialization, channel restrictions');

// The deployment compiler must include every UI module, including new dependencies.
{
    const fs = require("fs");
    const path = require("path");
    const root = path.resolve(__dirname, "..");
    const install = fs.readFileSync(path.join(root, "scripts/install-addon.ps1"), "utf8");
    const scripts = fs.readdirSync(path.join(root, "content/dota_addons/dota2_rpg/panorama/scripts/custom_game"));
    scripts.filter(name => name.endsWith(".js")).forEach(name => {
        require("assert").ok(install.includes("custom_game\\" + name), "Installer must compile " + name);
    });
}
