"use strict";
// UI98 uses the actual catalog/HUD scripts and XML, not a reimplementation.
const assert = require("assert"), fs = require("fs"), path = require("path");
const {runHud, click, panel, choice, input} = require("./condition-ui-v2.test");
const hero = "npc_dota_hero_axe", lion = "npc_dota_hero_lion";
function setup() {
    const hud = runHud();
    hud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    hud.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:800,hero_name:hero,rule_key:hero,
        can_edit:1,rules_ready:1,actions_text:"attack",rules:[{action:"attack",enabled:1,target_team:"enemy",use_conditions:[]}]});
    hud.subscriptions.rpg_enemy_roster({units:[{id:801,name:lion}]});
    hud.subscriptions.rpg_hero_slots({slot_key:"dire_1",hero_index:801,hero_name:lion,rule_key:"enemy:lion:1",
        actions_text:"lion_impale;attack",abilities_text:"lion_impale;lion_finger_of_death"});
    click(hud,"RadiantRuleSettings0");
    return hud;
}
const hud = setup();
assert(panel(hud,"RuleSettingsNav_use").BHasClass("Selected"));
assert(panel(hud,"V2TargetTeamRow").BHasClass("FantasyPageHidden"));
assert(!panel(hud,"V2_use0").BHasClass("FantasyPageHidden"));
choice(hud,"V2_use0","self_hp_pct_lte"); input(hud,"V2_use0_value",37.5);
panel(hud,"V2_use0_value").events.ontextentrychange();
assert(panel(hud,"RuleSettingsPreview").text.includes("37.5"),"preview reads the current input");
assert.equal(panel(hud,"RuleSettingsCount_use").text,"1");
click(hud,"RuleSettingsNav_target");
assert(panel(hud,"V2_use0").BHasClass("FantasyPageHidden"));
assert(!panel(hud,"V2TargetTeamRow").BHasClass("FantasyPageHidden"));
choice(hud,"V2_target0","hp_pct_lte"); input(hud,"V2_target0_value",65);
click(hud,"V2_targetModeOption_priority");
assert(panel(hud,"RuleSettingsNav_target").BHasClass("Selected"),"mode rebuild keeps active page");
assert.equal(panel(hud,"V2_use0_value").text,"37.5","hidden page input survives a rebuild");
assert.equal(panel(hud,"V2_target0_value").text,"65");
click(hud,"RuleSettingsNav_action");
assert(panel(hud,"V2ChaseTimeoutRow").BHasClass("Hidden"),"page changes do not unhide conditionally absent controls");
click(hud,"V2ApproachSelect"); click(hud,"V2ApproachSelectOption_approach_chase");
assert(!panel(hud,"V2ChaseTimeoutRow").BHasClass("Hidden"));
input(hud,"V2_chase_timeout",4.25);
click(hud,"RuleSettingsNav_use");
assert(panel(hud,"V2ChaseTimeoutRow").BHasClass("FantasyPageHidden"));
click(hud,"RuleSettingsNav_action");
assert(!panel(hud,"V2ChaseTimeoutRow").BHasClass("Hidden") && !panel(hud,"V2ChaseTimeoutRow").BHasClass("FantasyPageHidden"));
assert.equal(panel(hud,"V2_chase_timeout").text,"4.25");
click(hud,"RuleSettingsApply");
const saved = hud.sentEvents.filter(e=>e.name === "rpg_update_rule").at(-1).payload;
assert.equal(saved.use_condition_1_value,.375); assert.equal(saved.target_filter_1_value,.65);
assert.equal(saved.target_filters_mode,"priority"); assert.equal(saved.chase_timeout,4.25);
assert(!Object.keys(saved).some(k=>/^(page|preview|selectedPage|retainedPage)/.test(k)),"view-only state never enters wire payload");
click(hud,"RadiantRuleSettings0");
assert(panel(hud,"RuleSettingsNav_use").BHasClass("Selected"),"fresh open begins at triggers");
choice(hud,"V2_use0","self_hp_pct_lte"); input(hud,"V2_use0_value",12);
click(hud,"RuleSettingsNav_priority"); click(hud,"RuleSettingsClose"); click(hud,"RadiantRuleSettings0");
assert.equal(panel(hud,"V2_use0_value").text,"37.5","Cancel after page navigation discards draft");
// Regression: preview must never run normalizing save readers, which would
// detach the object captured by the actor/ability picker closures.
choice(hud,"V2_use0","action_elapsed_gte"); input(hud,"V2_use0_seconds",2.75);
panel(hud,"V2_use0_seconds").events.ontextentrychange();
click(hud,"RuleSettingsPreviewRefresh");
click(hud,"V2_use0_action_id"); click(hud,"V2_use0_action_idOption_1_1");
click(hud,"RuleSettingsPreviewRefresh");
click(hud,"RuleSettingsNav_target"); click(hud,"RuleSettingsNav_use");
click(hud,"RuleSettingsApply");
const ref = hud.sentEvents.filter(e=>e.name === "rpg_update_rule").at(-1).payload;
assert.equal(ref.use_condition_1_action_id,"lion_finger_of_death");
assert.equal(ref.use_condition_1_action_actor,"enemy:lion:1");
assert.equal(ref.use_condition_1_seconds,2.75);
// Read-only navigation may show pages, never publish a rule.
const readonly = setup();
let applied = false;
readonly.context.RpgConditionCatalog.open({action:"attack"},{target_team:"enemy"},()=>{applied=true;},{readOnly:true});
click(readonly,"RuleSettingsNav_target"); click(readonly,"RuleSettingsApply");
assert(!applied && !panel(readonly,"RuleSettingsApply").enabled);
console.log("PASS UI98 condition navigation, retained drafts, pure live preview, actor identity, native visibility, cancellation and read-only guards");

const base=path.join(__dirname,"..","content/dota_addons/dota2_rpg/panorama");
const css=fs.readFileSync(path.join(base,"styles/custom_game/fantasy_ui.css"),"utf8");
const xml=fs.readFileSync(path.join(base,"layout/custom_game/rpg_demo_hud.xml"),"utf8");
const code=fs.readFileSync(path.join(base,"scripts/custom_game/condition_catalog.js"),"utf8");
assert(xml.indexOf('styles/custom_game/fantasy_ui.css')>xml.indexOf('styles/custom_game/issue_fixes_ui.css'),"theme overrides load last");
assert(/\.DualRankColumns\s*\{[^}]*flow-children:\s*right/.test(css));
assert(/\.V2Condition\s*\{[^}]*flow-children:\s*right-wrap/.test(css));
assert(!/\b(?:display|grid-template-columns|justify-content|align-items)\s*:|@media|var\(/.test(css),"native Panorama stylesheet, not web CSS");
assert(xml.includes('id="RunRankDetails" class="RankDetails Hidden"'));
assert(!xml.includes('id="RunScoreTab"') && !xml.includes('id="RunSpeedrunTab"'));
assert(code.includes('preview = clone(draft)'),"preview uses a separate copy");
for (const match of (xml+css).matchAll(/file:\/\/\{images\}\/custom_game\/fantasy_ui\/([a-z_]+\.png)/g)) {
    const png=path.join(base,"images/custom_game/fantasy_ui",match[1]);
    assert(fs.existsSync(png),"local artwork exists: "+match[1]);
    const vtex=png.replace(/\.png$/,"_png.vtex");
    assert(fs.existsSync(vtex) && fs.readFileSync(vtex,"utf8").includes('./'+match[1]));
}
for (const lang of ["english","schinese"]) {
    const locale=fs.readFileSync(path.join(__dirname,"..","game/dota_addons/dota2_rpg/resource/addon_"+lang+".txt"),"utf8");
    assert(/"dota2_rpg_build_tag"\s+"[^"\r\n]*98"/.test(locale));
    for (const m of xml.matchAll(/#(dota2_rpg_ui_[a-z_]+)/g)) { assert(locale.includes('"'+m[1]+'"'),"localized "+m[1]+" in "+lang); }
}
const installer=fs.readFileSync(path.join(__dirname,"..","scripts/install-ui.ps1"),"utf8");
assert(installer.includes('*_png.vtex') && installer.includes('fantasy_ui.css') && installer.includes('Get-FileHash'));
console.log("PASS UI98 layout wiring, two columns, collapsed details, local artwork, VTEX descriptors, localization and installer contracts");
