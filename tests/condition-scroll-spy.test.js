"use strict";
// Drive the real catalog with explicit native geometry and a deterministic clock.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {runHud, click, panel, choice, input} = require("./condition-ui-v2.test");
const sections = ["use", "target", "priority", "action"];
function setup() {
    const hud = runHud();
    // Other HUD systems have their own timers; this clock drives only the editor.
    hud.scheduled.splice(0);
    const initial = {target_team:"enemy",use_conditions:[{type:"self_hp_pct_lte",value:.375}],
        target_filters:[{type:"hp_pct_lte",value:.65}],target_priorities:[{type:"lowest_hp_pct"}]};
    const original = JSON.stringify(initial), applied = [];
    function open(readOnly) {
        hud.context.RpgConditionCatalog.open({action:"attack"},initial,draft=>applied.push(draft),{readOnly:!!readOnly});
    }
    open();
    return {hud,initial,original,applied,open};
}
function geometry(hud, positions) {
    panel(hud,"RuleSettingsBody").position.y = 180;
    sections.forEach((section,i)=>{panel(hud,"V2Section_"+section).position.y=positions[i];});
}
function selected(hud, expected) {
    sections.forEach(section=>assert.equal(panel(hud,"RuleSettingsNav_"+section).BHasClass("Selected"),section===expected,"selected section "+section));
    assert.equal(panel(hud,"RuleSettingsSectionTitle").text,"#dota2_rpg_ui_nav_"+expected);
    assert.equal(panel(hud,"RuleSettingsPreviewHint").text,"#dota2_rpg_ui_tip_"+expected);
}
function visibleSections(hud) {
    sections.forEach(section=>{
        const header = panel(hud,"V2Section_"+section);
        assert(header,"stable header anchor "+section);
        assert(panel(hud,"RuleSettingsBody").children.includes(header),"header belongs to scrolling body");
        assert(!header.BHasClass("Hidden") && !header.BHasClass("FantasyPageHidden"),"header accessible "+section);
    });
    ["V2_use0","V2TargetTeamRow","V2_target0","V2_priority0","V2ChaseTimeoutRow"].forEach(id=>{
        assert(!panel(hud,id).BHasClass("FantasyPageHidden"),"navigation does not hide "+id);
    });
}
const state = setup(), {hud} = state;
visibleSections(hud);
selected(hud,"use");
const bodyChildren = panel(hud,"RuleSettingsBody").children.slice();
const useInput = panel(hud,"V2_use0_value"), targetInput = panel(hud,"V2_target0_value");
input(hud,"V2_use0_value",42.5); input(hud,"V2_target0_value",71.25);
const sentBefore = JSON.stringify(hud.sentEvents);
geometry(hud,[180,650,1050,1400]); hud.runScheduled(0);
sections.forEach(section=>{
    const anchor = panel(hud,"V2Section_"+section), before = anchor.scrollRequests.length;
    click(hud,"RuleSettingsNav_"+section);
    assert.deepStrictEqual(anchor.scrollRequests.slice(before),[[0,true]],"nav asks native parent to reveal "+section);
    selected(hud,section); visibleSections(hud);
});
assert(hud.scheduled.length,"open starts a scheduled scroll observer");
// At body top + 24, target becomes current; just below that threshold use remains current.
geometry(hud,[-150,205,650,1050]);
assert(hud.runScheduled()>0,"clock executes pending observer"); selected(hud,"use");
assert(panel(hud,"RuleSettingsPreview").text.includes("42.5"),"scroll reads unsaved trigger input");
geometry(hud,[-150,203,650,1050]); hud.runScheduled(); selected(hud,"target");
assert(panel(hud,"RuleSettingsPreview").text.includes("71.25"),"scroll changes preview to target draft");
geometry(hud,[-750,-350,203,600]); hud.runScheduled(); selected(hud,"priority");
geometry(hud,[-1200,-850,-250,203]); hud.runScheduled(); selected(hud,"action");
// Short sections use content height and remain selectable at the bottom of the document.
const css = fs.readFileSync(path.join(__dirname,"../content/dota_addons/dota2_rpg/panorama/styles/custom_game/fantasy_ui.css"),"utf8");
assert(/\.V2ScrollSection\s*\{[^}]*height:\s*fit-children/.test(css));
assert(!/\.V2ScrollSection\s*\{[^}]*min-height:\s*100%/.test(css),"no full-viewport blank section padding");
panel(hud,"RuleSettingsBody").actuallayoutheight=600;
geometry(hud,[-1200,-850,203,600]); hud.runScheduled(); selected(hud,"action");
panel(hud,"RuleSettingsBody").actuallayoutheight=42;
panel(hud,"RuleSettingsBody").actualuiscale_y=2;
geometry(hud,[-150,227,650,1050]); hud.runScheduled(); selected(hud,"target");
geometry(hud,[-150,229,650,1050]); hud.runScheduled(); selected(hud,"use");
panel(hud,"RuleSettingsBody").actualuiscale_y=1;
geometry(hud,[180,650,1050,1400]); hud.runScheduled(); selected(hud,"use");
bodyChildren.forEach((child,i)=>assert.strictEqual(panel(hud,"RuleSettingsBody").children[i],child,"scroll keeps body children alive"));
assert.strictEqual(panel(hud,"V2_use0_value"),useInput); assert.strictEqual(panel(hud,"V2_target0_value"),targetInput);
assert.equal(useInput.text,"42.5"); assert.equal(targetInput.text,"71.25");
assert.equal(JSON.stringify(state.initial),state.original,"view changes do not mutate caller settings");
assert.equal(JSON.stringify(hud.sentEvents),sentBefore,"scroll/navigation never sends a server update");
assert.equal(state.applied.length,0,"scroll/navigation never applies");
// Applying the same draft with and without scrolling must produce identical settings and wire payloads.
const control = setup(); input(control.hud,"V2_use0_value",42.5); input(control.hud,"V2_target0_value",71.25);
click(control.hud,"RuleSettingsApply"); click(hud,"RuleSettingsApply");
assert.equal(JSON.stringify(state.applied[0]),JSON.stringify(control.applied[0]),"navigation adds no draft fields");
const wire = hud.context.RpgRuleSync.serialize({rule:state.applied[0]});
const controlWire = control.hud.context.RpgRuleSync.serialize({rule:control.applied[0]});
delete wire.request_id; delete controlWire.request_id;
assert.equal(JSON.stringify(wire),JSON.stringify(controlWire),"navigation leaves wire payload unchanged");
// Closing retires pending callbacks; opening establishes a new generation.
hud.runScheduled();
assert.equal(hud.scheduled.length,0,"hidden editor stops scheduling");
state.open(); geometry(hud,[180,650,1050,1400]);
const stale = hud.scheduled.splice(0);
assert(stale.length,"reopen restarts polling");
state.open(); geometry(hud,[-150,203,650,1050]); hud.runScheduled(0);
selected(hud,"target");
const pending = hud.scheduled.length;
stale.forEach(task=>task.callback());
assert.equal(hud.scheduled.length,pending,"old generation cannot restart polling"); selected(hud,"target");
hud.runScheduled(); selected(hud,"target");
click(hud,"RuleSettingsClose"); hud.runScheduled();
assert.equal(hud.scheduled.length,0,"cancel retires observer");
state.open(); hud.runScheduled(0);
hud.context.RpgConditionCatalog.reset(); hud.runScheduled();
assert.equal(hud.scheduled.length,0,"reset invalidates pending observer");
assert.equal(panel(hud,"RuleSettingsBody").GetChildCount(),0,"reset disposes editor controls");
state.open(); panel(hud,"RuleSettings").valid=false;
hud.runScheduled(); assert.equal(hud.scheduled.length,0,"disposed root stops observer");
// Compact categories may already share the viewport: clicking one must not
// immediately be overwritten by the observer until the document moves again.
const compact = setup();
panel(compact.hud,"RuleSettingsBody").actuallayoutheight=600;
geometry(compact.hud,[-600,-200,250,560]); compact.hud.runScheduled(0);
click(compact.hud,"RuleSettingsNav_priority"); compact.hud.runScheduled();
selected(compact.hud,"priority"); compact.hud.runScheduled(); selected(compact.hud,"priority");
geometry(compact.hud,[-620,-220,230,540]); compact.hud.runScheduled(); selected(compact.hud,"action");
// F41 has only its explanation; other parameterless conditions collapse the parameter area.
choice(compact.hud,"V2_target0","facing_enemy");
const facingHint=panel(compact.hud,"V2_target0FacingHint");
assert(facingHint && !facingHint.parent.BHasClass("Hidden"));
assert(panel(compact.hud,"V2_target0Heading").parent===panel(compact.hud,"V2_target0"));
// Priority choices are parameterless and should not leave an empty second row.
assert(panel(compact.hud,"V2_priority0").children[1].BHasClass("Hidden"));
// Read-only inspection permits both anchor navigation and wheel-driven highlighting.
const readonly = setup(); readonly.open(true);
geometry(readonly.hud,[-150,203,650,1050]); readonly.hud.runScheduled(); selected(readonly.hud,"target");
click(readonly.hud,"RuleSettingsNav_action"); selected(readonly.hud,"action");
assert.deepStrictEqual(panel(readonly.hud,"V2Section_action").scrollRequests.at(-1),[0,true]);
visibleSections(readonly.hud); click(readonly.hud,"RuleSettingsApply");
assert(!panel(readonly.hud,"RuleSettingsApply").enabled && readonly.applied.length===0);
assert.equal(JSON.stringify(readonly.initial),readonly.original);
assert(!readonly.hud.sentEvents.some(event=>event.name==="rpg_update_rule"));
console.log("PASS continuous condition scroll: four sections, native anchors, geometry highlights/previews, retained drafts/payloads, lifecycle and read-only navigation");
