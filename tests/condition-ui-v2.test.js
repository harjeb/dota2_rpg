"use strict";

var fs = require("fs");
var path = require("path");
var vm = require("vm");

var repoRoot = path.resolve(__dirname, "..");
var hudPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "scripts", "custom_game", "rpg_demo_hud.js");
var ruleSyncPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "scripts", "custom_game", "panorama_rule_sync.js");
var cssPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "styles", "custom_game", "rpg_demo_hud.css");
var layoutPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "layout", "custom_game", "rpg_demo_hud.xml");
var hudSource = fs.readFileSync(hudPath, "utf8");
var ruleSyncSource = fs.readFileSync(ruleSyncPath, "utf8");
var cssSource = fs.readFileSync(cssPath, "utf8");
var layoutSource = fs.readFileSync(layoutPath, "utf8");
var fixesCssSource = fs.readFileSync(path.join(path.dirname(cssPath), "issue_fixes_ui.css"), "utf8");
var layoutTree = JSON.parse(require("child_process").execFileSync("python", ["-c",
    "import json,sys,xml.etree.ElementTree as E; " +
    "encode=lambda e:dict(type=e.tag,attrs=e.attrib,children=[encode(c) for c in e]); " +
    "print(json.dumps(encode(E.parse(sys.argv[1]).getroot())))", layoutPath], { encoding: "utf8" }));
var snippetTree = layoutTree.children.filter(function (node) { return node.type === "snippets"; })[0].children[0];
var rootLayout = layoutTree.children.filter(function (node) { return node.type === "Panel"; })[0];

function instantiateSnippet(node, parent) {
    var panel = createPanel(node.attrs.id || "");
    panel.parent = parent;
    panel.attributes = node.attrs;
    (node.attrs.class || "").split(/\s+/).filter(Boolean).forEach(function (name) { panel.AddClass(name); });
    panel.children = node.children.map(function (child) { return instantiateSnippet(child, panel); });
    return panel;
}

function createPanel(id) {
    var classes = {};
    return {
        id: id || "",
        text: "",
        enabled: true,
        children: [],
        attributes: {},
        actualuiscale_x: 1,
        actualuiscale_y: 1,
        actuallayoutwidth: id === "DropdownLayer" ? 1920 : 300,
        actuallayoutheight: id === "DropdownLayer" ? 1080 : 42,
        position: { x: 120, y: 400 },
        GetPositionWithinWindow: function () { return this.id === "DropdownLayer" ? { x: 0, y: 0 } : this.position; },
        AddClass: function (name) { classes[name] = true; },
        SetHasClass: function (name, enabled) { classes[name] = Boolean(enabled); },
        BHasClass: function (name) { return Boolean(classes[name]); },
        events: {},
        SetPanelEvent: function (eventName, callback) { this.events[eventName] = callback; },
        BLoadLayoutSnippet: function () {
            this.children = snippetTree.children.map(function (child) { return instantiateSnippet(child, this); }, this);
        },
        FindChildTraverse: function (childId) {
            for (var child of this.children) {
                if (child.id === childId) { return child; }
                var found = child.FindChildTraverse(childId);
                if (found) { return found; }
            }
            return null;
        },
        GetChildCount: function () { return this.children.length; },
        GetChild: function (index) { return this.children[index]; },
        GetAttributeString: function (name, fallback) { return this.attributes[name] || fallback; },
        RemoveAndDeleteChildren: function () { this.children = []; },
        SetParent: function (parent) {
            if (this.parent) {
                this.parent.children = this.parent.children.filter(function (child) { return child !== this; }, this);
            }
            this.parent = parent;
            parent.children.push(this);
        },
        GetParent: function () { return this.parent || null; },
        style: {},
        classes: classes
    };
}

function runHud() {
    var panels = {};
    var createdPanels = [];
    var sentEvents = [];
    var subscriptions = {};
    var nativeSelections = [];
    var localStorageCalls = 0;

    // Unknown IDs return null as they do in Panorama; never invent missing live controls.
    for (var match of layoutSource.matchAll(/\bid="([^"]+)"/g)) {
        panels["#" + match[1]] = createPanel(match[1]);
    }
    function panorama(selector) {
        return panels[selector] || null;
    }
    panorama.CreatePanel = function (type, parent, id) {
        var panel = createPanel(id || "");
        panel.type = type;
        panel.parent = parent;
        parent.children.push(panel);
        createdPanels.push(panel);
        if (id) {
            panels["#" + id] = panel;
        }
        return panel;
    };
    var rootPanel = createPanel("HudRoot");
    rootPanel.FindChildTraverse = function (id) { return panorama("#" + id); };
    panorama.GetContextPanel = function () { return rootPanel; };
    panorama.Localize = function (token) { return token; };
    panorama.Schedule = function (_, callback) { callback(); };
    panorama.LocalStorage = {
        Get: function () { localStorageCalls++; return "null"; },
        Set: function () { localStorageCalls++; }
    };

    var customConfig = {};
    var context = {
        GameUI: {
            CustomUIConfig: function () { return customConfig; },
            SelectUnit: function (index, additive) { nativeSelections.push({ index: index, additive: additive }); }
        },
        console: console,
        $: panorama,
        GameEvents: {
            Subscribe: function (name, callback) { subscriptions[name] = callback; },
            SendCustomGameEventToServer: function (name, payload) {
                sentEvents.push({ name: name, payload: payload });
            }
        },
        Players: {
            GetLocalPlayerPortraitUnit: function () { return 503; }
        }
    };
    // Load the scripts in the same order as the real HUD layout.
    var scriptIncludes = layoutSource.matchAll(/<include src="file:\/\/\{resources\}\/scripts\/custom_game\/([^"]+)"/g);
    for (var include of scriptIncludes) {
        var scriptPath = path.join(path.dirname(hudPath), include[1]);
        vm.runInNewContext(fs.readFileSync(scriptPath, "utf8"), context, { filename: scriptPath });
    }

    return {
        context: context,
        panels: panels,
        createdPanels: createdPanels,
        sentEvents: sentEvents,
        nativeSelections: nativeSelections,
        subscriptions: subscriptions,
        getLocalStorageCalls: function () { return localStorageCalls; }
    };
}

function assert(condition, message) {
    if (!condition) {
        throw new Error(message);
    }
}

function panel(hud, id) { return hud.panels["#" + id]; }
function click(hud, id) { var p = panel(hud, id); assert(p && p.events.onactivate, "clickable actual panel " + id); p.events.onactivate(); }
function choice(hud, id, value) {
    click(hud, id + "Select");
    var menu = panel(hud, id + "SelectMenu");
    assert(!menu.BHasClass("Hidden"), "click opens " + id);
    var token = "#dota2_rpg_v2_" + (value || "none");
    var item = menu.children.filter(function (p) { return p.children[0] && p.children[0].text.replace(/^[UFP]\d{2} /, "") === token; })[0];
    assert(item, "localized choice exists: " + value); item.events.onactivate();
    assert(menu.BHasClass("Hidden"), "select closes menu");
}
function input(hud, id, value) { var p = panel(hud, id); assert(p, "real input " + id); p.text = String(value); }
function latest(hud, hero, slot) {
    return hud.sentEvents.filter(function (event) { return event.name === "rpg_update_rule" && event.payload.hero_name === hero && event.payload.slot === (slot || 1); }).slice(-1)[0].payload;
}
var hud = runHud();
var lion = "npc_dota_hero_lion", axe = "npc_dota_hero_axe";
function slots(side, index, name, entity, actions, details) {
    hud.subscriptions.rpg_hero_slots({slot_key: side.toLowerCase() + "_" + index,
        hero_name: name, hero_index: entity, actions_text: actions || "lion_impale;lion_finger_of_death;attack", details_text: details || ""});
}
hud.subscriptions.rpg_enemy_roster({units: [{id: 101, name: lion}, {id: 102, name: lion}]});
slots("Dire", 1, lion, 101); slots("Dire", 2, lion, 102);
click(hud, "DireRuleSettings0");
assert(!panel(hud, "RuleSettings").BHasClass("Hidden"), "XML settings panel opens from compact row");
assert(panel(hud, "V2_use3Select") && panel(hud, "V2_target3Select") && panel(hud, "V2_priority1Select"), "actual UI renders 4/4/2 slots");
choice(hud, "V2_use0", "self_hp_pct_gte"); input(hud, "V2_use0_value", 67.5);
choice(hud, "V2_use1", "nearby_enemies_gte"); input(hud, "V2_use1_value", 3); input(hud, "V2_use1_radius", 875);
choice(hud, "V2_use2", "elapsed_gte"); input(hud, "V2_use2_seconds", 57.5);
choice(hud, "V2_use3", "action_use_count_lt"); input(hud, "V2_use3_value", 2); input(hud, "V2_use3_action_id", "lion_finger_of_death");
choice(hud, "V2_target0", "hp_pct_lte"); input(hud, "V2_target0_value", 35);
choice(hud, "V2_target1", "modifier_stacks_gte"); input(hud, "V2_target1_modifier", "modifier_test"); input(hud, "V2_target1_value", 4);
choice(hud, "V2_target2", "modifier_remaining_lte"); input(hud, "V2_target2_modifier", "modifier_test"); input(hud, "V2_target2_seconds", 1.75);
choice(hud, "V2_target3", "exclude_self");
choice(hud, "V2_priority0", "lowest_attack_damage"); choice(hud, "V2_priority1", "highest_magic_resistance");
input(hud, "V2_min_aoe_hits", 3); choice(hud, "V2Toggle", "toggle_off");
click(hud, "RuleSettingsApply");
var saved = latest(hud, lion);
assert(saved.use_condition_1_value === 0.675 && saved.target_filter_1_value === 0.35, "percentages serialize as fractions");
assert(saved.use_condition_2_value === 3 && saved.use_condition_2_radius === 875, "nearby count and radius serialize independently");
assert(saved.use_condition_3_seconds === 57.5 && saved.use_condition_3_value === 57.5, "time retains numeric precision and value alias");
assert(saved.use_condition_4_action_id === "lion_finger_of_death", "cross-action condition retains native action ID");
assert(saved.target_filter_2_modifier === "modifier_test" && saved.target_filter_2_value === 4, "modifier name and stacks stay distinct");
assert(saved.target_filter_3_seconds === 1.75 && saved.target_filter_3_modifier === "modifier_test", "modifier expiry serialized");
assert(saved.target_filter_4_type === "exclude_self", "fourth filter serialized");
assert(saved.target_priority_1_type === "lowest_attack_damage" && saved.target_priority_2_type === "highest_magic_resistance", "two explicit priorities");
assert(saved.aoe_radius === undefined && saved.min_aoe_hits === 3 && saved.desired_toggle_state === "0", "native radius cannot be overridden; hit gate and false toggle survive serialization");
assert(saved.condition === "self_hp_pct_gte", "compact condition summary follows the first advanced condition");
click(hud, "DireRuleSettings0");
assert(panel(hud, "V2_use2_seconds").text === "57.5", "reopening does not clamp advanced time to legacy 30 seconds");
input(hud, "V2_use2_seconds", 999); click(hud, "RuleSettingsClose");
click(hud, "DireRuleSettings0"); assert(panel(hud, "V2_use2_seconds").text === "57.5", "cancel leaves authored rule untouched"); click(hud, "RuleSettingsApply");
click(hud, "DireAddRule0");
assert(latest(hud, lion, 2).use_condition_3_seconds === 57.5 && latest(hud, lion, 2).target_filter_2_modifier === "modifier_test", "new row deep-copies advanced options");
click(hud, "DireRuleSettings1"); input(hud, "V2_use2_seconds", 7); click(hud, "RuleSettingsApply");
assert(latest(hud, lion).use_condition_3_seconds === 57.5, "editing copied row does not mutate source");
click(hud, "DireHeroDyn2");
click(hud,"DireRuleSettings0"); click(hud,"RuleSettingsApply");
assert(latest(hud, lion).hero_index === 102 && latest(hud, lion).use_condition_1_type === "always", "duplicate heroes start independently");
hud.subscriptions.rpg_enemy_roster({units: [{id: 201, name: lion}, {id: 202, name: lion}]});
slots("Dire", 1, lion, 201); slots("Dire", 2, lion, 202); click(hud, "DireHeroDyn1");
click(hud,"DireRuleSettings0"); click(hud,"RuleSettingsApply");
assert(latest(hud, lion).hero_index === 201 && latest(hud, lion).use_condition_3_seconds === 57.5, "respawn retains first occurrence advanced values");
click(hud, "DireHeroDyn2"); click(hud,"DireRuleSettings0"); click(hud,"RuleSettingsApply"); assert(latest(hud, lion).use_condition_1_type === "always", "respawn preserves duplicate isolation");

// Native server action list includes extra dynamic slots and missing metadata.
click(hud, "DireHeroDyn1");
slots("Dire", 1, lion, 201, "lion_impale;lion_voodoo;lion_mana_drain;lion_finger_of_death;lion_extra_action;attack");
click(hud, "DireActionSelect0");
assert(panel(hud, "ActionOpt_Dire0_lion_extra_action"), "extra native skill appears without hardcoded slot cap");
click(hud, "ActionOpt_Dire0_lion_extra_action");
assert(panel(hud, "DireActionAbility0").abilityname === "lion_extra_action", "native name supplies icon without details");
assert(latest(hud, lion).action_id === "lion_extra_action" && latest(hud, lion).action_name === "lion_extra_action", "native name reaches server");
slots("Dire", 1, lion, 201, "ability_1;attack", "lion_impale;attack");
click(hud, "DireActionSelect0"); click(hud, "ActionOpt_Dire0_ability_1");
assert(panel(hud, "DireActionAbility0").abilityname === "lion_impale" && latest(hud, lion).action_id === "lion_impale", "legacy ability slot resolves metadata");

// Malformed fields cannot emit NaN/Infinity; blank action references mean current action.
click(hud, "DireRuleSettings0");
input(hud, "V2_use1_value", "NaN"); input(hud, "V2_use1_radius", "Infinity");
input(hud, "V2_use3_action_id", ""); input(hud, "V2_min_aoe_hits", 100);
choice(hud, "V2_target0", "mana_pct_gte"); input(hud, "V2_target0_value", 800);
choice(hud, "V2Toggle", "toggle_on"); click(hud, "RuleSettingsApply");
var malformed = latest(hud, lion);
assert(Number.isFinite(malformed.use_condition_2_value) && Number.isFinite(malformed.use_condition_2_radius), "malformed numeric inputs become finite");
assert(malformed.target_filter_1_value === 1 && malformed.aoe_radius === undefined && malformed.min_aoe_hits === 20, "bounded inputs clamp consistently");
assert(!Object.prototype.hasOwnProperty.call(malformed, "use_condition_4_action_id"), "blank action ID omitted");
assert(malformed.desired_toggle_state === "1", "explicit on state");
click(hud, "DireRuleSettings0"); choice(hud, "V2_use1", ""); choice(hud, "V2Toggle", "toggle_auto"); click(hud, "RuleSettingsApply");
assert(latest(hud, lion).use_condition_2_type === "" && latest(hud, lion).use_condition_2_radius === undefined, "cleared slots remove stale parameters");
assert(latest(hud, lion).desired_toggle_state === undefined, "default toggle omits desired state");

// Compact XML controls retain friendly distance targets and basic priority mappings.
var editor = panel(hud, "DireConditionEditor0");
var attrMenu = editor.FindChildTraverse("TargetAttrMenu");
editor.FindChildTraverse("TargetAttrSelect").events.onactivate();
function pickValue(menu, value) { var p = menu.children.filter(function (p) { return p.attributes.value === value; })[0]; assert(p, "XML option " + value); p.events.onactivate(); }
pickValue(attrMenu, "distance");
var sideMenu = editor.FindChildTraverse("TargetSideMenu"); editor.FindChildTraverse("TargetSideSelect").events.onactivate(); pickValue(sideMenu, "ally_farthest");
assert(latest(hud, lion).target_team === "ally" && latest(hud, lion).target_priority_1_type === "farthest", "compact farthest friend stays ally");
var sync = hud.context.RpgRuleSync;
[["enemy_attack_lowest", "lowest_attack_damage"], ["ally_mr_highest", "highest_magic_resistance"], ["ally_distance_nearest", "nearest"]].forEach(function (pair) {
    var payload = sync.serialize({rule: {target: pair[0]}}); assert(payload.target_priority_1_type === pair[1], "legacy priority mapping " + pair[0]);
});

// Player rules follow hero identity across reorder and respawn.
slots("Radiant", 1, axe, 401); slots("Radiant", 2, lion, 402);
hud.subscriptions.rpg_shop_state({lineup_text: axe + ";" + lion, owned_text: axe + ";" + lion});
click(hud, "RadiantRuleSettings0"); choice(hud, "V2_use0", "elapsed_gte"); input(hud, "V2_use0_seconds", 63.25); click(hud, "RuleSettingsApply");
hud.subscriptions.rpg_shop_state({lineup_text: lion + ";" + axe, owned_text: axe + ";" + lion});
slots("Radiant", 1, lion, 502); slots("Radiant", 2, axe, 501); click(hud, "RadiantHeroDyn2");
click(hud,"RadiantRuleSettings0"); click(hud,"RuleSettingsApply");
assert(latest(hud, axe).hero_index === 501 && latest(hud, axe).use_condition_1_seconds === 63.25, "advanced time follows hero without legacy clamping");
for (var n = 1; n < 35; n++) { click(hud, "RadiantAddRule0"); }
assert(latest(hud, axe).rule_count === 32, "UI and wire enforce 32 rules");
assert(!panel(hud, "RadiantAddRule0").enabled, "add control disabled at 32");
assert(sync.serialize({ruleCount: Infinity, rule: {}}).rule_count === 1, "malformed rule counts stay finite");

// A fresh HUD hydrates authoritative rules without sending defaults back.
var fresh = runHud();
var omni = "npc_dota_hero_omniknight";
fresh.subscriptions.rpg_shop_state({lineup_text:omni,owned_text:omni});
fresh.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:701,hero_name:omni,rule_key:omni,
    can_edit:1,rules_ready:1,actions_text:"omniknight_purification;attack",rules:{
        1:{action:"omniknight_purification",enabled:1,target_team:"ally",use_conditions:{1:{type:"self_hp_pct_lte",value:0.5}},target_filters:{1:{type:"hp_pct_lte",value:0.8}},target_priorities:{1:{type:"lowest_hp_pct"}}},
        2:{action:"attack",enabled:1,target_team:"enemy",use_conditions:{1:{type:"always"}}}
    }});
assert(!fresh.sentEvents.some(function(e){return e.name === "rpg_update_rule";}),"hydration/rendering never truncates server rules with defaults");
click(fresh,"RadiantRuleSettings0");
assert(panel(fresh,"V2_use0_value").text === "50" && panel(fresh,"V2_target0_value").text === "80","server percentages converted once for restored editor");
var beforePreset = fresh.sentEvents.length;
assert(panel(fresh,"V2Preset0"),"native skill has an actual preset button");
click(fresh,"V2Preset0");
assert(fresh.sentEvents.length === beforePreset,"preset only changes draft until Apply");
choice(fresh,"V2Cast","cast_unit");
click(fresh,"RuleSettingsApply");
var restored = latest(fresh,omni);
assert(restored.rule_count === 2 && restored.target_team === "ally" && restored.target_filter_1_value === 0.8,"real healing preset selects wounded ally and preserves server row count");
assert(restored.min_aoe_hits === undefined && restored.cast_preference === "unit","default hit gate stays disabled; selected native target mode survives");
fresh.subscriptions.rpg_rule_update_result({request_id:restored.request_id,ok:0,reason:"invalid_numeric_value:hp_pct_lte"});
assert(panel(fresh,"RuleSyncNotice").visible,"server rejection is visible");
click(fresh,"RadiantRuleSettings0");click(fresh,"RuleSettingsApply");
var repaired=latest(fresh,omni);
fresh.subscriptions.rpg_rule_update_result({request_id:repaired.request_id,ok:1});
assert(!panel(fresh,"RuleSyncNotice").visible,"matching successful update clears its failure");
fresh.subscriptions.rpg_rule_update_result({request_id:restored.request_id,ok:0,reason:"wrong_phase"});
assert(!panel(fresh,"RuleSyncNotice").visible,"stale responses cannot replace current acceptance");

// Preset editing survives the actual HUD Apply -> wire -> reopen path.
var restoredEditor = panel(fresh,"RadiantConditionEditor0");
assert(restoredEditor.FindChildTraverse("TargetAttrValue").text === "#dota2_rpg_v2_lowest_hp_pct"
    && restoredEditor.FindChildTraverse("TargetSideValue").text === "#dota2_rpg_v2_team_ally", "compact preset display matches active priority and team");
click(fresh,"RadiantRuleSettings0"); click(fresh,"V2Preset0");
input(fresh,"V2_target0_value",72.5);
choice(fresh,"V2_use0","elapsed_lte"); input(fresh,"V2_use0_seconds",17.25);
choice(fresh,"V2_use1","nearby_enemies_gte"); input(fresh,"V2_use1_value",2); input(fresh,"V2_use1_radius",875);
choice(fresh,"V2_target1","has_modifier"); input(fresh,"V2_target1_modifier","modifier_test");
choice(fresh,"V2Toggle","toggle_off"); input(fresh,"V2_min_aoe_hits",3);
click(fresh,"RuleSettingsApply");
var editedPreset = latest(fresh,omni);
assert(editedPreset.target_filter_1_value === 0.725 && editedPreset.use_condition_1_type === "elapsed_lte"
    && editedPreset.use_condition_1_seconds === 17.25 && editedPreset.use_condition_1_value === 17.25
    && editedPreset.use_condition_2_radius === 875 && editedPreset.use_condition_2_value === 2
    && editedPreset.target_filter_2_modifier === "modifier_test" && editedPreset.desired_toggle_state === "0"
    && editedPreset.min_aoe_hits === 3, "edited preset parameters reach flat server payload");
click(fresh,"RadiantRuleSettings0");
assert(panel(fresh,"V2_target0_value").text === "72.5" && panel(fresh,"V2_use0_seconds").text === "17.25"
    && panel(fresh,"V2_use1_radius").text === "875" && panel(fresh,"V2_target1_modifier").text === "modifier_test"
    && panel(fresh,"V2ToggleSelect").GetChild(0).text === "#dota2_rpg_v2_toggle_off", "edited preset and U14 reopen without loss");
["enemy","self","ally"].forEach(function(team) {
    choice(fresh,"V2Team","team_"+team); click(fresh,"RuleSettingsApply");
    assert(latest(fresh,omni).target_team === team && latest(fresh,omni).target_priority_1_type === "lowest_hp_pct", "team change preserves explicit ranking on wire");
    assert(restoredEditor.FindChildTraverse("TargetSideValue").text === "#dota2_rpg_v2_team_"+team, "compact team matches wire");
    click(fresh,"RadiantRuleSettings0");
    assert(panel(fresh,"V2TeamSelect").GetChild(0).text === "#dota2_rpg_v2_team_"+team, "team survives reopen");
});
click(fresh,"V2ClearConditions"); click(fresh,"RuleSettingsApply");
var cleared = latest(fresh,omni);
assert(!cleared.min_aoe_hits && cleared.desired_toggle_state === undefined, "clear removes hit and toggle gates on wire");
["use_condition","target_filter","target_priority"].forEach(function(prefix) {
    for (var i=1;i<=(prefix==="target_priority"?2:4);i++) { assert(cleared[prefix+"_"+i+"_type"] === "", "clear removes every wire slot"); }
});
click(fresh,"RadiantRuleSettings0");
assert(panel(fresh,"V2_use0Select").GetChild(0).text === "#dota2_rpg_v2_none"
    && panel(fresh,"V2_target0Select").GetChild(0).text === "#dota2_rpg_v2_none"
    && panel(fresh,"V2_min_aoe_hits").text === "0", "cleared editor reopens empty");
click(fresh,"RuleSettingsClose");

fresh.subscriptions.rpg_enemy_roster({units:[{id:702,name:lion}]});
fresh.subscriptions.rpg_hero_slots({slot_key:"dire_1",hero_index:702,hero_name:lion,can_edit:0,rules_ready:1,
    actions_text:"lion_impale;attack",rules:[{action:"lion_impale",enabled:1,target_team:"enemy",use_conditions:[{type:"elapsed_gte",value:12,seconds:12}]}]});
var beforeReadOnly = fresh.sentEvents.length;
click(fresh,"DireRuleSettings0");
assert(panel(fresh,"V2_use0_seconds").text === "12" && !panel(fresh,"RuleSettingsBody").enabled && !panel(fresh,"RuleSettingsApply").enabled,"ordinary enemy intelligence shows real server conditions read-only");
click(fresh,"RuleSettingsApply");
assert(fresh.sentEvents.length === beforeReadOnly,"read-only enemy conditions cannot be sent");

// Replacing a compact casting target clears its old filter, keeping other slots.
editor.FindChildTraverse("TargetAttrSelect").events.onactivate();pickValue(attrMenu,"casting");
click(hud,"DireRuleSettings0");click(hud,"RuleSettingsApply");
editor.FindChildTraverse("TargetAttrSelect").events.onactivate();pickValue(attrMenu,"distance");
assert(latest(hud,lion).target_filter_1_type === "","compact nearest no longer retains an invisible casting gate");

var retiredUse = "dead_ally_count_gte self_strength_gte self_agility_gte owned_summons_gte owned_summons_lte action_used_within action_not_used_within".split(" ");
var retiredTarget = "not_illusion is_creep is_invulnerable not_invulnerable has_tag not_has_tag".split(" ");
[["use", retiredUse, 25], ["target", retiredTarget, 34], ["priority", [], 13]].forEach(function (spec) {
    var catalog = hud.context.RpgConditionCatalog;
    assert(catalog.groups[spec[0]].length === spec[2], "remaining menu count " + spec[0]);
    spec[1].forEach(function (id) {
        assert(!catalog.groups[spec[0]].some(function (entry) { return entry.id === id; }), "removed menu entry " + id);
        assert(catalog.normalize(spec[0], { type: id, value: 1 }).type === "", "retired draft condition cleared " + id);
    });
});
var translations = ["english", "schinese"].map(function (language) {
    var buffer = fs.readFileSync(path.join(repoRoot, "game/dota_addons/dota2_rpg/resource/addon_" + language + ".txt"));
    return buffer[0] === 255 && buffer[1] === 254 ? buffer.toString("utf16le") : buffer.toString("utf8");
});
Object.keys(hud.context.RpgConditionCatalog.groups).forEach(function (group) {
    hud.context.RpgConditionCatalog.groups[group].forEach(function (def) {
        translations.forEach(function (source) {
            assert(source.indexOf('"dota2_rpg_v2_' + def.id + '"') >= 0, "localized condition " + def.id);
            assert(source.indexOf('"dota2_rpg_v2_category_' + def.category + '"') >= 0, "localized category " + def.category);
        });
    });
});
// Exercise the catalog against a live parent/child tree, including deleted fields.
var catalogPanels = {};
["RuleSettings", "RuleSettingsBody", "RuleSettingsError", "RuleSettingsApply", "RuleSettingsClose"].forEach(function (id) { catalogPanels[id] = createPanel(id); });
function catalogUI(selector) { return catalogPanels[selector.substring(1)] || catalogPanels.RuleSettingsBody.FindChildTraverse(selector.substring(1)); }
catalogUI.Localize = function (token) { return token; };
catalogUI.CreatePanel = function (type, parent, id) {
    var p = createPanel(id); p.type = type; p.SetParent(parent); return p;
};
var catalogContext = {$:catalogUI};
var catalogPath = path.join(path.dirname(hudPath), "condition_catalog.js");
var presetSource = fs.readFileSync(path.join(path.dirname(hudPath), "skill_condition_presets.js"), "utf8");
vm.runInNewContext(fs.readFileSync(catalogPath, "utf8"), catalogContext);
vm.runInNewContext(presetSource, catalogContext);
vm.runInNewContext(ruleSyncSource, catalogContext);
var catalog = catalogContext.RpgConditionCatalog;
var docs = fs.readFileSync(path.join(repoRoot, "docs/CONDITION_LIST_ZH.md"), "utf8");
Object.keys(catalog.groups).forEach(function (group) {
    catalog.groups[group].forEach(function (def) {
        assert(docs.split("\n").some(function (line) { return line.indexOf("| " + def.code + " |") === 0 && line.indexOf("`" + def.id + "`") >= 0; }), "stable documented ID " + def.code);
    });
});
function catalogClick(id) { var p = catalogUI("#" + id); assert(p && p.events.onactivate, "catalog button " + id); p.events.onactivate(); }
function verifyMenus() {
    Object.keys(catalog.groups).forEach(function (group) {
        catalogClick("V2_" + group + "0Select");
        var menu = catalogUI("#V2_" + group + "0SelectMenu");
        assert(menu.BHasClass("V2Choices") && !menu.BHasClass("Hidden"), "real scroll menu opens " + group);
        catalog.groups[group].forEach(function (def) {
            var item = menu.FindChildTraverse("V2_" + group + "0SelectOption_" + def.id);
            assert(item && item.GetChild(0).text.indexOf(def.code + " ") === 0 && item.events.onactivate, "reachable coded choice " + def.code);
        });
        catalogClick("V2_" + group + "0Select");
    });
    ["elapsed_gte", "elapsed_lte"].forEach(function (id, index) {
        catalogClick("V2_use0Select"); catalogClick("V2_use0SelectOption_" + id);
        assert(catalogUI("#V2_use0_seconds"), "U" + (13 + index) + " exposes seconds field");
    });
}
var mapping = JSON.parse(presetSource.match(/var mapping = (\{[^\n]+\});/)[1]);
var presetCount = 0, applied;
Object.keys(mapping).forEach(function (ability) {
    catalogContext.RpgSkillPresets.variants(ability).forEach(function (variant, index) {
        var preset = catalogContext.RpgSkillPresets.get(ability, variant);
        catalog.open({}, {use_conditions:[{type:"self_has_modifier",modifier:"stale"}],target_filters:[{type:"distance_gte",value:1234}],target_priorities:[]}, function (draft) { applied = draft; }, {abilityName:ability});
        var before = JSON.stringify(preset), full = catalog.summary(preset);
        assert(before === JSON.stringify(preset), "summary does not mutate " + ability);
        assert(catalogUI("#V2PresetPreview" + index).text === full, "full preview " + ability + "/" + variant);
        catalogClick("V2Preset" + index);
        [["use", "use_conditions", 4], ["target", "target_filters", 4], ["priority", "target_priorities", 2]].forEach(function (spec) {
            for (var slot = 0; slot < spec[2]; slot++) {
                var condition = (preset[spec[1]] || [])[slot] || {type:""};
                var select = catalogUI("#V2_" + spec[0] + slot + "Select");
                assert(select && select.GetChild(0).text.indexOf("#dota2_rpg_v2_" + (condition.type || "none")) >= 0, "template slot rendered " + ability + " " + spec[0] + slot);
                Object.keys(condition).filter(function (key) { return key !== "type"; }).forEach(function (key) {
                    var field = catalogUI("#V2_" + spec[0] + slot + "_" + key);
                    assert(field && field.text === String(condition[key]), "template parameter rendered " + ability + " " + key);
                    assert(full.indexOf(String(condition[key])) >= 0, "summary retains parameter " + key);
                });
            }
        });
        assert(!catalogUI("#V2_use0_modifier"), "template switch deletes stale modifier input");
        assert(catalogUI("#V2TeamSelect").GetChild(0).text === "#dota2_rpg_v2_team_" + preset.target_team, "template team rendered");
        assert(catalogUI("#V2_min_aoe_hits").text === String(preset.min_aoe_hits || 0), "template hit gate rendered");
        assert(catalogUI("#V2CastSelect").GetChild(0).text === "#dota2_rpg_v2_cast_" + (preset.cast_preference || "auto"), "template cast preference rendered");
        assert(catalogUI("#V2ToggleSelect").GetChild(0).text === "#dota2_rpg_v2_toggle_" + (preset.desired_toggle_state === "0" ? "off" : preset.desired_toggle_state === "1" ? "on" : "auto"), "template toggle rendered");
        catalogClick("RuleSettingsApply");
        assert(applied.target_filters.every(function (condition) { return condition.value !== 1234; }), "template switch discards prior distance");
        var wire = catalogContext.RpgRuleSync.serialize({rule:applied,actionId:ability,actionName:ability});
        var server = {action:ability,enabled:1,target_team:wire.target_team,min_aoe_hits:wire.min_aoe_hits,
            desired_toggle_state:wire.desired_toggle_state,cast_preference:wire.cast_preference};
        [["use_conditions","use_condition",4],["target_filters","target_filter",4],["target_priorities","target_priority",2]].forEach(function(spec) {
            server[spec[0]] = {};
            for (var i=1;i<=spec[2];i++) {
                var item = {};
                ["type","value","seconds","radius","modifier","action_id"].forEach(function(key) {
                    if (wire[spec[1]+"_"+i+"_"+key] !== undefined) { item[key] = wire[spec[1]+"_"+i+"_"+key]; }
                });
                if (item.type) { server[spec[0]][i] = item; }
            }
        });
        var hydrated = catalogContext.RpgRuleSync.fromServer(server);
        catalog.open(hydrated,catalogContext.RpgRuleSync.initialSettings(hydrated),function(draft) {
            applied = draft;
            Object.keys(draft).forEach(function(key) { hydrated[key]=draft[key]; });
        },{abilityName:ability});
        catalogClick("RuleSettingsApply");
        var reopenedWire = catalogContext.RpgRuleSync.serialize({rule:hydrated,actionId:ability,actionName:ability});
        Object.keys(wire).filter(function(key) { return /^(use_condition_|target_filter_|target_priority_|target_team$|min_aoe_hits$|desired_toggle_state$|cast_preference$)/.test(key); }).forEach(function(key) {
            assert(wire[key] === reopenedWire[key], "server hydration and reopened template preserve " + ability + "/" + variant + " " + key);
        });
        if (!presetCount) { verifyMenus(); }
        presetCount++;
    });
});
catalogClick("V2ClearConditions"); catalogClick("RuleSettingsApply");
assert(applied.use_conditions.concat(applied.target_filters, applied.target_priorities).every(function (condition) { return !condition.type; }) && applied.min_aoe_hits === 0 && applied.desired_toggle_state === null, "clear removes all conditions and gates");
assert(/\.V2Condition\s*\{[^}]*height: fit-children/.test(cssSource) && /\.V2Selector\s*\{[^}]*height: fit-children/.test(cssSource), "rows and selectors expand around menus");
assert(/\.V2Choices\s*\{[^}]*height: 280px;[^}]*overflow: squish scroll/.test(cssSource), "bounded menu is vertically scrollable");
assert(/\.RuleSettingsBody\s*\{[^}]*overflow: squish scroll/.test(cssSource), "all condition rows reachable by body scroll");
["clear_conditions", "target_team", "team_enemy", "team_ally", "team_self"].forEach(function (token) {
    translations.forEach(function (source) { assert(source.indexOf('"dota2_rpg_v2_' + token + '"') >= 0, "new localized editor token " + token); });
});
catalogClick("V2TeamSelect"); catalogClick("V2TeamSelectOption_team_ally"); catalogClick("RuleSettingsApply");
assert(applied.target_team === "ally" && applied.target === "ally_distance_nearest", "team selector updates both editor and legacy serialization target");
console.log("PASS: " + presetCount + " complete template variants, 72 stable documented menu IDs, U13/U14 selection, previews and stale field removal");
console.log("PASS: real XML/UI 4/4/2 conditions, flat serialization, toggles, native actions, malformed inputs, cancellation, copying, 32 rules, respawn/reorder and duplicate persistence");
