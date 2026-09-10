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

var rootLayout = layoutTree.children.filter(function (node) { return node.type === "Panel"; })[0];
var resultLayout = rootLayout.children.filter(function (node) { return node.attrs.id === "BattleResult"; })[0];
if (!resultLayout || !resultLayout.children.some(function (node) { return node.attrs.id === "LootPopup"; })) {
    throw new Error("loot must share the victory settlement card");
}

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
        SetImage: function (src) { this.src = src; },
        BLoadLayoutSnippet: function () {
            throw new Error("Legacy outer editor snippets must not be instantiated");
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
            Subscribe: function (name, callback) {
                var previous = subscriptions[name];
                subscriptions[name] = function (payload) { if (previous) previous(payload); callback(payload); };
            },
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
// Battlefield action references use icons and stable actor keys, including duplicate enemies.
var lion = "npc_dota_hero_lion", axe = "npc_dota_hero_axe";
var pickerHud = runHud();
pickerHud.subscriptions.rpg_shop_state({lineup_text:axe,owned_text:axe});
pickerHud.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:800,hero_name:axe,
    can_edit:1,rules_ready:1,actions_text:"attack"});
pickerHud.subscriptions.rpg_enemy_roster({units:[{id:801,name:lion},{id:802,name:lion}]});
[801,802].forEach(function(entity,index) {
    pickerHud.subscriptions.rpg_hero_slots({slot_key:"dire_"+(index+1),hero_index:entity,hero_name:lion,
        rule_key:"enemy:"+lion+":"+index,actions_text:"lion_impale;item_blink;attack",abilities_text:"lion_impale;lion_finger_of_death"});
});
click(pickerHud,"RadiantRuleSettings0");
["action_elapsed_gte","action_elapsed_lte"].forEach(function(type,index) {
    choice(pickerHud,"V2_use"+index,type); input(pickerHud,"V2_use"+index+"_seconds",2.75);
    click(pickerHud,"V2_use"+index+"_action_id");
    var iconOption=panel(pickerHud,"V2_use"+index+"_action_idOption_2_1");
    assert(iconOption.GetChild(0).type === "DOTAAbilityImage" && iconOption.GetChild(0).abilityname === "lion_finger_of_death", "picker uses actual ability icons");
    click(pickerHud,iconOption.id);
});
click(pickerHud,"RuleSettingsApply");
var picked=latest(pickerHud,axe);
assert(picked.use_condition_1_action_actor === "enemy:"+lion+":1" && picked.use_condition_2_action_actor === picked.use_condition_1_action_actor
    && picked.use_condition_1_action_id === "lion_finger_of_death" && picked.use_condition_2_seconds === 2.75,"U21/U22 save selected actor, ability and seconds");
click(pickerHud,"RadiantRuleSettings0");
choice(pickerHud,"V2_use2","action_succeeded_after"); input(pickerHud,"V2_use2_seconds",1.25);
click(pickerHud,"V2_use2_action_id");
var itemOption = panel(pickerHud,"V2_use2_action_idOption_2_2");
assert(itemOption.GetChild(0).type === "DOTAItemImage" && itemOption.GetChild(0).itemname === "item_blink","duplicate enemy active equipment uses its native item icon");
click(pickerHud,itemOption.id); click(pickerHud,"RuleSettingsApply");
assert(latest(pickerHud,axe).use_condition_3_action_actor === "enemy:"+lion+":1"
    && latest(pickerHud,axe).use_condition_3_action_id === "item_blink"
    && latest(pickerHud,axe).use_condition_3_seconds === 1.25,"U39 saves duplicate enemy equipment, actor and delay from the allied editor");
click(pickerHud,"RadiantRuleSettings0");
assert(panel(pickerHud,"V2_use2_action_id").GetChild(0).itemname === "item_blink","selected enemy equipment survives reopen");
assert(panel(pickerHud,"V2_use0_action_id").GetChild(0).abilityname === "lion_finger_of_death", "selected icon survives reopen");
click(pickerHud,"V2_use0_action_id"); click(pickerHud,"V2_use0_action_idCurrent"); click(pickerHud,"RuleSettingsApply");
assert(!latest(pickerHud,axe).use_condition_1_action_actor && !latest(pickerHud,axe).use_condition_1_action_id,"current action clears both reference fields");
// Remove both a rejected rule and an in-flight request when their unit leaves.
var rejected=latest(pickerHud,axe);
pickerHud.subscriptions.rpg_rule_update_result({request_id:rejected.request_id,ok:0,reason:"invalid_hero"});
assert(panel(pickerHud,"RuleSyncNotice").visible,"current roster rejection is shown");
click(pickerHud,"RadiantRuleSettings0"); click(pickerHud,"RuleSettingsApply");
var delayed=latest(pickerHud,axe);
pickerHud.subscriptions.rpg_shop_state({lineup_text:"",owned_text:""});
assert(!panel(pickerHud,"RuleSyncNotice").visible,"departed roster clears stale failure notice");
pickerHud.subscriptions.rpg_rule_update_result({request_id:delayed.request_id,ok:0,reason:"invalid_hero"});
assert(!panel(pickerHud,"RuleSyncNotice").visible,"late rejection cannot resurrect absent-unit warning");
assert(pickerHud.context.RpgConditionCatalog.abilityLabel("missing_native_token").indexOf("#DOTA") < 0,"missing native localization never leaks token");

// F39: actual HUD -> current opposing roster portraits -> wire -> authoritative reload.
var targetHud = runHud(), targetCaster = "npc_dota_hero_axe";
targetHud.subscriptions.rpg_shop_state({lineup_text:targetCaster,owned_text:targetCaster});
targetHud.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:900,hero_name:targetCaster,
    can_edit:1,rules_ready:1,actions_text:"attack",rules:[{action:"attack",enabled:1,target_team:"enemy"}]});
var targetRoster = [{id:901,name:lion},{id:902,name:lion},{id:903,name:"npc_dota_neutral_centaur_khan"},{id:904,name:"npc_dota_roshan"}];
function feedTargets(level, roster) {
    targetHud.subscriptions.rpg_enemy_roster({units:roster});
    roster.forEach(function(unit,index) {
        targetHud.subscriptions.rpg_hero_slots({slot_key:"dire_"+(index+1),hero_index:unit.id,hero_name:unit.name,
            target_actor:level+":enemy:"+unit.name+":"+index,can_edit:1,rules_ready:1,actions_text:"attack"});
    });
}
feedTargets("ch05",targetRoster);
click(targetHud,"RadiantRuleSettings0"); choice(targetHud,"V2_target0","specified_enemy");
assert(panel(targetHud,"V2_target0Select").GetChild(0).text.indexOf("F39 ")===0,"specified enemy appends F39");
click(targetHud,"RuleSettingsApply");
assert(latest(targetHud,targetCaster).target_filter_1_type==="specified_enemy" && latest(targetHud,targetCaster).target_filter_1_target_actor==="","empty selection keeps fail-closed filter");
click(targetHud,"RadiantRuleSettings0"); click(targetHud,"V2_target0_target_actor");
var targetMenu=panel(targetHud,"V2_target0_target_actorMenu");
assert(targetMenu.children.length===5,"only four current opposing positions plus clear");
assert(targetMenu.children[1].GetChild(0).type==="DOTAHeroImage" && targetMenu.children[2].GetChild(0).heroname===lion,"duplicate heroes have separate portraits");
assert(targetMenu.children[3].GetChild(0).type==="Image" && targetMenu.children[3].GetChild(0).src.indexOf("npc_dota_neutral_centaur_khan.png")>=0,"neutral uses unit image asset");
assert(targetMenu.children[4].GetChild(0).src.indexOf("npc_dota_roshan.png")>=0,"boss has unit portrait");
click(targetHud,"V2_target0_target_actorOption_1"); click(targetHud,"RuleSettingsApply");
var selectedActor="ch05:enemy:"+lion+":1";
assert(latest(targetHud,targetCaster).target_filter_1_target_actor===selectedActor,"duplicate position key saved exactly");
click(targetHud,"RadiantRuleSettings0");
assert(panel(targetHud,"V2_target0_target_actor").GetChild(0).heroname===lion && panel(targetHud,"V2_target0_target_actor").GetChild(1).text.indexOf("2")>=0,"reopen preserves duplicate position");
var targetSync=targetHud.context.RpgRuleSync;
var restoredTarget=targetSync.fromServer({action:"attack",enabled:1,target_team:"enemy",target_filters:{1:{type:"specified_enemy",target_actor:selectedActor}}});
assert(targetSync.serialize({rule:restoredTarget}).target_filter_1_target_actor===selectedActor,"fromServer round trip preserves opaque actor key");
// Changing level with identical enemies must not alias an older snapshot identity.
feedTargets("ch06",targetRoster);
click(targetHud,"RadiantRuleSettings0");
assert(panel(targetHud,"V2_target0_target_actor").BHasClass("V2UnavailableTarget") && panel(targetHud,"V2_target0_target_actor").GetChild(0).text==="#dota2_rpg_v2_unavailable_target","old-level target visibly unavailable");
click(targetHud,"RuleSettingsApply");
assert(latest(targetHud,targetCaster).target_filter_1_target_actor===selectedActor,"missing selection is never silently cleared or retargeted");
click(targetHud,"RadiantRuleSettings0"); click(targetHud,"V2_target0_target_actor");
var removedOption=panel(targetHud,"V2_target0_target_actorOption_1");
feedTargets("ch06",[targetRoster[0]]);
removedOption.events.onactivate();
assert(panel(targetHud,"V2_target0_target_actorMenu").children.length===2,"open menu refresh excludes removed units");
click(targetHud,"RuleSettingsApply");
assert(latest(targetHud,targetCaster).target_filter_1_target_actor===selectedActor,"stale menu click cannot select departed unit");
click(targetHud,"RadiantRuleSettings0"); click(targetHud,"V2_target0_target_actor"); click(targetHud,"V2_target0_target_actorClear"); click(targetHud,"RuleSettingsApply");
assert(latest(targetHud,targetCaster).target_filter_1_type==="" && latest(targetHud,targetCaster).target_filter_1_target_actor===undefined,"clear removes entire filter including key");
click(targetHud,"RadiantRuleSettings0");
assert(panel(targetHud,"V2_target0Select").GetChild(0).text==="#dota2_rpg_v2_none","clear survives reopen");
assert(!panel(targetHud,"DireEditor") && !panel(targetHud,"DireRuleSettings0"),"enemy roster exposes no condition editor even with editable slot metadata");
// A late slot message cannot resurrect an entity replaced in the current roster.
targetHud.subscriptions.rpg_hero_slots({slot_key:"dire_1",hero_index:999,hero_name:lion,target_actor:"ch04:enemy:"+lion+":0"});
click(targetHud,"RadiantRuleSettings0"); choice(targetHud,"V2_target0","specified_enemy"); click(targetHud,"V2_target0_target_actor");
assert(panel(targetHud,"V2_target0_target_actorMenu").children.length===1,"mismatched current entity excludes stale slot metadata");
var beforeFight=targetHud.sentEvents.filter(function(e){return e.name==="rpg_update_rule";}).length;
targetHud.subscriptions.rpg_battle_state({phase:"fight"});
assert(panel(targetHud,"RuleSettings").BHasClass("Hidden"),"fight closes prep picker");
click(targetHud,"RadiantRuleSettings0"); click(targetHud,"RuleSettingsApply");
assert(panel(targetHud,"RuleSettings").BHasClass("Hidden") && targetHud.sentEvents.filter(function(e){return e.name==="rpg_update_rule";}).length===beforeFight,"fight cannot reopen or save prep target selection");
console.log("PASS: F39 current-enemy hero/neutral/boss portraits, duplicate keys, save/reopen, stale targets, clear and fight guards");

var hud = runHud();
function slots(side, index, name, entity, actions, details) {
    hud.subscriptions.rpg_hero_slots({slot_key: side.toLowerCase() + "_" + index,
        hero_name: name, hero_index: entity, actions_text: actions || "lion_impale;lion_finger_of_death;attack", details_text: details || ""});
}
hud.subscriptions.rpg_shop_state({lineup_text:lion + ";" + axe,owned_text:lion + ";" + axe});
slots("Radiant", 1, lion, 101); slots("Radiant", 2, axe, 102);
click(hud, "RadiantRuleSettings0");
assert(!panel(hud, "RuleSettings").BHasClass("Hidden"), "XML settings panel opens from compact row");
assert(panel(hud, "V2_use3Select") && panel(hud, "V2_target3Select") && panel(hud, "V2_priority1Select"), "actual UI renders 4/4/2 slots");
choice(hud, "V2_use0", "self_hp_pct_gte"); input(hud, "V2_use0_value", 67.5);
choice(hud, "V2_use1", "nearby_enemies_gte"); input(hud, "V2_use1_value", 3); input(hud, "V2_use1_radius", 875);
choice(hud, "V2_use2", "elapsed_gte"); input(hud, "V2_use2_seconds", 57.5);
choice(hud, "V2_use3", "action_use_count_lt"); input(hud, "V2_use3_value", 2); click(hud, "V2_use3_action_id"); click(hud, "V2_use3_action_idOption_0_1");
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
click(hud, "RadiantRuleSettings0");
assert(panel(hud, "V2_use2_seconds").text === "57.5", "reopening does not clamp advanced time to legacy 30 seconds");
input(hud, "V2_use2_seconds", 999); click(hud, "RuleSettingsClose");
click(hud, "RadiantRuleSettings0"); assert(panel(hud, "V2_use2_seconds").text === "57.5", "cancel leaves authored rule untouched"); click(hud, "RuleSettingsApply");
click(hud, "RadiantAddRule0");
assert(latest(hud, lion, 2).use_condition_3_seconds === 57.5 && latest(hud, lion, 2).target_filter_2_modifier === "modifier_test", "new row deep-copies advanced options");
click(hud, "RadiantRuleSettings1"); input(hud, "V2_use2_seconds", 7); click(hud, "RuleSettingsApply");
assert(latest(hud, lion).use_condition_3_seconds === 57.5, "editing copied row does not mutate source");
click(hud, "RadiantHeroDyn2");
click(hud,"RadiantRuleSettings0"); click(hud,"RuleSettingsApply");
assert(latest(hud, axe).hero_index === 102 && latest(hud, axe).use_condition_1_type === "always", "allied heroes start independently");
hud.subscriptions.rpg_shop_state({lineup_text:lion + ";" + axe,owned_text:lion + ";" + axe});
slots("Radiant", 1, lion, 201); slots("Radiant", 2, axe, 202); click(hud, "RadiantHeroDyn1");
click(hud,"RadiantRuleSettings0"); click(hud,"RuleSettingsApply");
assert(latest(hud, lion).hero_index === 201 && latest(hud, lion).use_condition_3_seconds === 57.5, "respawn retains authored advanced values");
click(hud, "RadiantHeroDyn2"); click(hud,"RadiantRuleSettings0"); click(hud,"RuleSettingsApply"); assert(latest(hud, axe).hero_index === 202 && latest(hud, axe).use_condition_1_type === "always", "respawn preserves hero isolation");

// Native server action list includes extra dynamic slots and missing metadata.
click(hud, "RadiantHeroDyn1");
slots("Radiant", 1, lion, 201, "lion_impale;lion_voodoo;lion_mana_drain;lion_finger_of_death;lion_extra_action;attack");
click(hud, "RadiantActionSelect0");
assert(panel(hud, "ActionOpt_Radiant0_lion_extra_action"), "extra native skill appears without hardcoded slot cap");
click(hud, "ActionOpt_Radiant0_lion_extra_action");
assert(panel(hud, "RadiantActionAbility0").abilityname === "lion_extra_action", "native name supplies icon without details");
assert(latest(hud, lion).action_id === "lion_extra_action" && latest(hud, lion).action_name === "lion_extra_action", "native name reaches server");
slots("Radiant", 1, lion, 201, "ability_1;attack", "lion_impale;attack");
click(hud, "RadiantActionSelect0"); click(hud, "ActionOpt_Radiant0_ability_1");
assert(panel(hud, "RadiantActionAbility0").abilityname === "lion_impale" && latest(hud, lion).action_id === "lion_impale", "legacy ability slot resolves metadata");

// Malformed fields cannot emit NaN/Infinity; blank action references mean current action.
click(hud, "RadiantRuleSettings0");
input(hud, "V2_use1_value", "NaN"); input(hud, "V2_use1_radius", "Infinity");
click(hud, "V2_use3_action_id"); click(hud, "V2_use3_action_idCurrent"); input(hud, "V2_min_aoe_hits", 100);
choice(hud, "V2_target0", "mana_pct_gte"); input(hud, "V2_target0_value", 800);
choice(hud, "V2Toggle", "toggle_on"); click(hud, "RuleSettingsApply");
var malformed = latest(hud, lion);
assert(Number.isFinite(malformed.use_condition_2_value) && Number.isFinite(malformed.use_condition_2_radius), "malformed numeric inputs become finite");
assert(malformed.target_filter_1_value === 1 && malformed.aoe_radius === undefined && malformed.min_aoe_hits === 20, "bounded inputs clamp consistently");
assert(!Object.prototype.hasOwnProperty.call(malformed, "use_condition_4_action_id"), "blank action ID omitted");
assert(malformed.desired_toggle_state === "1", "explicit on state");
click(hud, "RadiantRuleSettings0"); choice(hud, "V2_use1", ""); choice(hud, "V2Toggle", "toggle_auto"); click(hud, "RuleSettingsApply");
assert(latest(hud, lion).use_condition_2_type === "" && latest(hud, lion).use_condition_2_radius === undefined, "cleared slots remove stale parameters");
assert(latest(hud, lion).desired_toggle_state === undefined, "default toggle omits desired state");

// Target editing is exclusively inside the complete settings panel.
assert(!panel(hud,"RadiantConditionEditor0") && !panel(hud,"RadiantForceToggle0"),"outer editing controls are absent");
click(hud,"RadiantRuleSettings0");
choice(hud,"V2Team","team_ally"); choice(hud,"V2_priority0","farthest");
choice(hud,"V2Approach","approach_chase"); click(hud,"RuleSettingsApply");
assert(latest(hud,lion).target_team === "ally" && latest(hud,lion).target_priority_1_type === "farthest"
    && latest(hud,lion).approach === "allow_approach", "complete settings own target and approach behavior");
click(hud,"RadiantRuleSettings0");
assert(panel(hud,"V2ApproachSelect").GetChild(0).text === "#dota2_rpg_v2_approach_chase","approach survives reopening");
choice(hud,"V2Approach","approach_wait");click(hud,"RuleSettingsApply");
assert(latest(hud,lion).approach === "range_only","approach can be disabled in settings");
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
assert(!panel(fresh,"RadiantConditionEditor0"), "restored rules expose only the settings entry");
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
    assert(latest(fresh,omni).target_team === team && latest(fresh,omni).target_priority_1_type === "prefer_teammate"
        && latest(fresh,omni).target_priority_2_type === "lowest_hp_pct", "team change preserves explicit ranking on wire");

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

var intelligenceHud = runHud();
intelligenceHud.subscriptions.rpg_enemy_roster({units:[{id:702,name:lion}]});
intelligenceHud.subscriptions.rpg_hero_slots({slot_key:"dire_1",hero_index:702,hero_name:lion,can_edit:0,rules_ready:1,
    actions_text:"lion_impale;attack",rules:[{action:"lion_impale",enabled:1,target_team:"enemy",use_conditions:[{type:"elapsed_gte",value:12,seconds:12}]}]});
assert(!panel(intelligenceHud,"DireEditor") && !panel(intelligenceHud,"DireRuleSettings0"),"enemy intelligence has no editing entry");
assert(!panel(intelligenceHud,"RuleSettingsApply").events.onactivate,"enemy intelligence never installs an Apply callback");
assert(!intelligenceHud.sentEvents.some(function(e){return e.name === "rpg_update_rule";}),"enemy intelligence cannot send rule updates");

// Removing a target condition inside settings clears the same wire slot.
click(hud,"RadiantHeroDyn1");
click(hud,"RadiantRuleSettings0");
assert(panel(hud,"V2_use2_seconds").text === "57.5" && panel(hud,"V2_target1_modifier").text === "modifier_test", "reorder and respawn preserve the other hero's complex rule independently");
choice(hud,"V2_target0","is_casting");click(hud,"RuleSettingsApply");
click(hud,"RadiantRuleSettings0");choice(hud,"V2_target0","");click(hud,"RuleSettingsApply");
assert(latest(hud,lion).target_filter_1_type === "","settings removal clears the casting gate");

var retiredUse = "dead_ally_count_gte self_strength_gte self_agility_gte owned_summons_gte owned_summons_lte action_used_within action_not_used_within".split(" ");
var retiredTarget = "not_illusion is_creep is_invulnerable not_invulnerable has_tag not_has_tag".split(" ");
[["use", retiredUse, 32], ["target", retiredTarget, 35], ["priority", [], 14]].forEach(function (spec) {
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
        // Appended contracts must not renumber the prior documented IDs.
        if (def.id === "action_succeeded_after") { assert(def.code === "U39", "successful action trigger appends U39"); return; }
        if (def.id === "specified_enemy") { assert(def.code === "F39", "new target filter appends F39"); return; }
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
                ["type","value","seconds","radius","modifier","action_id","action_actor"].forEach(function(key) {
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
// A user can add an independent follow-up rule before the first spell is cast.
[
    ["dawnbreaker", "dawnbreaker_celestial_hammer", "dawnbreaker_converge"],
    ["phoenix", "phoenix_fire_spirits", "phoenix_launch_fire_spirit"]
].forEach(function (pair) {
    var phaseHud = runHud(), hero = "npc_dota_hero_" + pair[0];
    phaseHud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    var slotData = {slot_key:"radiant_1",hero_index:911,hero_name:hero,rule_key:hero,
        can_edit:1,rules_ready:1,actions_text:pair[1]+";"+pair[2]+";attack",abilities_text:pair[1]+";"+pair[2],
        rules:[{action:pair[1],enabled:1,target_team:"enemy",use_conditions:[{type:"elapsed_gte",value:3,seconds:3}]}]};
    phaseHud.subscriptions.rpg_hero_slots(slotData);
    click(phaseHud,"RadiantAddRule0");
    click(phaseHud,"RadiantActionSelect1");
    [pair[1],pair[2]].forEach(function(name) {
        var option = panel(phaseHud,"ActionOpt_Radiant1_"+name);
        assert(option && option.GetChild(0).abilityname===name,"both native phase icons are selectable: "+name);
    });
    click(phaseHud,"ActionOpt_Radiant1_"+pair[2]);
    click(phaseHud,"RadiantRuleSettings1");
    choice(phaseHud,"V2_use0","action_elapsed_gte"); input(phaseHud,"V2_use0_seconds",1.25);
    click(phaseHud,"V2_use0_action_id"); click(phaseHud,"V2_use0_action_idOption_0_0");
    click(phaseHud,"RuleSettingsApply");
    var follow = latest(phaseHud,hero,2);
    assert(follow.action_id===pair[2] && follow.use_condition_1_action_id===pair[1]
        && follow.use_condition_1_seconds===1.25 && follow.rule_count===2,"follow-up saves separately and can reference the initial cast");
    slotData.actions_text = pair[2]+";"+pair[1]+";attack";
    phaseHud.subscriptions.rpg_hero_slots(slotData);
    assert(!panel(phaseHud,"RadiantActionSelect0").BHasClass("UnavailableAction")
        && !panel(phaseHud,"RadiantActionSelect1").BHasClass("UnavailableAction"),"slot swap keeps both authored actions available");
    click(phaseHud,"RadiantRuleSettings0");
    assert(panel(phaseHud,"V2_use0_seconds").text==="3","first-stage condition is unchanged");
    click(phaseHud,"RuleSettingsClose"); click(phaseHud,"RadiantRuleSettings1");
    assert(panel(phaseHud,"V2_use0_seconds").text==="1.25"
        && panel(phaseHud,"V2_use0_action_id").GetChild(0).abilityname===pair[1],"follow-up condition and reference survive refresh and reopen");
});

// Destination selection and Tiny grab gates survive real editor save/reopen.
var destinationHud = runHud(), emberHero = "npc_dota_hero_ember_spirit";
destinationHud.subscriptions.rpg_shop_state({lineup_text:emberHero,owned_text:emberHero});
destinationHud.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:950,hero_name:emberHero,rule_key:emberHero,
    can_edit:1,rules_ready:1,actions_text:"ember_spirit_activate_fire_remnant;attack",
    rules:[{action:"ember_spirit_activate_fire_remnant",enabled:1,target_team:"enemy",destination:"remnant_nearest"}]});
click(destinationHud,"RadiantRuleSettings0");
choice(destinationHud,"V2Destination","destination_remnant_safe");
click(destinationHud,"RuleSettingsApply");
assert(latest(destinationHud,emberHero).destination==="remnant_safe","destination serializes independently of ordinary target settings");
click(destinationHud,"RadiantRuleSettings0");
assert(panel(destinationHud,"V2DestinationSelect").GetChild(0).text==="#dota2_rpg_v2_destination_remnant_safe","destination survives reopening");
click(destinationHud,"RuleSettingsClose");
var grabHud=runHud(), tinyHero="npc_dota_hero_tiny";
grabHud.subscriptions.rpg_shop_state({lineup_text:tinyHero,owned_text:tinyHero});
grabHud.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:951,hero_name:tinyHero,rule_key:tinyHero,
    can_edit:1,rules_ready:1,actions_text:"tiny_toss;attack",rules:[{action:"tiny_toss",enabled:1,target_team:"enemy"}]});
click(grabHud,"RadiantRuleSettings0");
choice(grabHud,"V2_use0","tiny_grab_is_enemy");
choice(grabHud,"V2_use1","tiny_grab_hp_pct_lte"); input(grabHud,"V2_use1_value",35);
choice(grabHud,"V2_target0","hp_pct_gte"); input(grabHud,"V2_target0_value",80);
click(grabHud,"RuleSettingsApply");
var grabWire=latest(grabHud,tinyHero);
assert(grabWire.use_condition_1_type==="tiny_grab_is_enemy" && grabWire.use_condition_2_value===.35
    && grabWire.target_filter_1_value===.8,"grabbed-unit gates and landing-target gates remain independent");

// Equipment sales use exact entities, never mutate the client wallet, and
// retain retry/duplicate protection across authoritative inventory refreshes.
var saleHud = runHud();
var saleState = {gold:1000,owned_text:axe+";"+lion,lineup_text:axe,
    stock_text:"item_magic_wand|9401;item_magic_wand|9402",
    equipped_text:axe+":item_blink|9301|0,item_force_staff|9302|14;"+lion+":item_manta|9303|6"};
saleHud.subscriptions.rpg_shop_state(saleState);
function saleEvents() { return saleHud.sentEvents.filter(function(e) { return e.name === "rpg_item_sell"; }); }
var saleButton = "Sell_Equipped_"+axe+"_0";
assert(panel(saleHud,saleButton).enabled && panel(saleHud,"Sell_Equipped_"+axe+"_1").enabled,"equipped and native stash slots expose selling");
var oldSaleButton = panel(saleHud,saleButton);
click(saleHud,saleButton); oldSaleButton.events.onactivate();
assert(saleEvents().length===1 && !panel(saleHud,saleButton).enabled,"pending exact entity cannot be sold twice after rerender");
var request = saleEvents()[0].payload;
assert(request.hero===axe && request.item==="item_blink" && request.item_index===9301 && request.request_id>0,"sale locks exact name, entity and carrier");
saleHud.subscriptions.rpg_item_sell_result({request_id:request.request_id,item_index:9301,ok:0,reason:"purchase_pending",refund:0});
assert(panel(saleHud,saleButton).enabled && panel(saleHud,"ItemSellNotice").BHasClass("Error"),"failed sale shows reason and allows retry");
click(saleHud,saleButton);
var retry = saleEvents()[1].payload;
saleHud.subscriptions.rpg_item_sell_result({request_id:request.request_id,item_index:9301,ok:0,reason:"sale_failed",refund:0});
assert(!panel(saleHud,saleButton).enabled,"stale reply cannot unlock a newer request");
var walletBeforeSale = panel(saleHud,"WalletBalance").text;
saleHud.subscriptions.rpg_item_sell_result({request_id:retry.request_id,item_index:9301,ok:1,reason:"sold",refund:225});
assert(panel(saleHud,"ItemSellNotice").BHasClass("Success") && panel(saleHud,"WalletBalance").text===walletBeforeSale,"native sale notice never credits client gold");
saleState.gold=1225; saleState.equipped_text=axe+":item_force_staff|9302|14;"+lion+":item_manta|9303|6";
saleHud.subscriptions.rpg_shop_state(saleState);
assert(panel(saleHud,"WalletBalance").text.indexOf("1225")>=0,"authoritative wallet refresh displays refund once");
click(saleHud,"ItemTarget_"+lion);
assert(panel(saleHud,"Sell_Equipped_"+lion+"_0").enabled,"bench hero backpack can be sold directly");
saleHud.subscriptions.rpg_shop_state({gold:1225,owned_text:"",lineup_text:"",stock_text:saleState.stock_text});
assert(panel(saleHud,"Sell_Stock0").enabled,"shared stash selling does not require a selected hero");
click(saleHud,"Sell_Stock0");
var stockRequest=saleEvents().slice(-1)[0].payload;
assert(stockRequest.hero==="__stash" && stockRequest.item_index===9401 && panel(saleHud,"Sell_Stock1").enabled,"same-name stash copies are independent");
saleHud.subscriptions.rpg_battle_state({phase:"fight"});
var beforeFightSales=saleEvents().length;
click(saleHud,"Sell_Stock1");
assert(!panel(saleHud,"Sell_Stock1").enabled && saleEvents().length===beforeFightSales,"combat cannot emit sale requests");

["marci_companion_run", "marci_bodyguard", "magnataur_empower"].forEach(function (ability) {
    var targetHud=runHud(), hero=ability === "magnataur_empower" ? "npc_dota_hero_magnataur" : "npc_dota_hero_marci";
    targetHud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    targetHud.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:960,hero_name:hero,rule_key:hero,
        can_edit:1,rules_ready:1,actions_text:ability+";attack",rules:[{action:ability,enabled:1,target_team:"enemy"}]});
    click(targetHud,"RadiantRuleSettings0");
    var body=panel(targetHud,"RuleSettingsBody"), teamRow=panel(targetHud,"V2TargetTeamRow");
    assert(body.children.indexOf(teamRow) < body.children.indexOf(panel(targetHud,"V2_use0Select").parent.parent),
        "team choice is visible before detailed filters and positioning");
    choice(targetHud,"V2Team","team_ally"); click(targetHud,"RuleSettingsApply");
    assert(latest(targetHud,hero).target_team==="ally","Marci's selected ally team reaches the server");
    click(targetHud,"RadiantRuleSettings0");
    assert(panel(targetHud,"V2TeamSelect").GetChild(0).text==="#dota2_rpg_v2_team_ally","ally selection survives reopen");
    choice(targetHud,"V2Team","team_self"); click(targetHud,"RuleSettingsApply");
    assert(latest(targetHud,hero).target_team==="self","self is selectable independently of hero/creep filters");
    if (ability !== "marci_companion_run") {
        click(targetHud,"RadiantRuleSettings0");
        assert(panel(targetHud,"V2Preset0").GetChild(0).text === "#dota2_rpg_v2_preset_prefer_teammate"
            && panel(targetHud,"V2Preset1").GetChild(0).text === "#dota2_rpg_v2_preset_allow_self", "support presets have distinct names");
        click(targetHud,"V2Preset0");
        click(targetHud,"RuleSettingsApply");
        var buffWire=latest(targetHud,hero);
        assert(buffWire.target_team==="ally" && buffWire.target_priority_1_type==="prefer_teammate"
            && buffWire.target_priority_2_type==="nearest" && !buffWire.target_filter_1_type,
            ability+" teammate preference replaces stale self targeting and allows fallback on wire");
        assert(!buffWire.target_filter_2_type && !buffWire.use_condition_1_type,
            ability+" buff needs no unrelated enemy proximity gate");
        click(targetHud,"RadiantRuleSettings0");
        assert(panel(targetHud,"V2TeamSelect").GetChild(0).text==="#dota2_rpg_v2_team_ally",
            ability+" teammate preset survives reopen");
        click(targetHud,"V2Preset1");
        click(targetHud,"RuleSettingsApply");
        buffWire=latest(targetHud,hero);
        assert(buffWire.target_team==="ally" && buffWire.target_priority_1_type==="nearest"
            && !buffWire.target_priority_2_type && !buffWire.target_filter_1_type,
            ability+" allow self clears the previous preference and keeps ally selection");
    }
});

var livesHud = runHud();
assert(panel(livesHud,"RunHearts").children.length === 5, "HUD opens with five hearts");
function lifeSnapshot(left, phase) {
    livesHud.subscriptions.rpg_battle_state({phase:phase || "setup", ready:left > 0 ? 1 : 0,
        winner:"dire", lives_remaining:left, max_lives:5, run_failed:left === 0 ? 1 : 0, gold:2500});
    var hearts = panel(livesHud,"RunHearts").children;
    assert(hearts.length === 5 && hearts.filter(function(p) { return !p.BHasClass("RunHeartSpent"); }).length === left,
        "authoritative remaining lives light the matching hearts");
    assert(panel(livesHud,"RunLivesCount").text === left + " / 5", "life counter reflects server snapshot");
}
lifeSnapshot(3, "result");
var relief = {winner:"dire",lives_remaining:3,max_lives:5,life_reward_gold:2000};
livesHud.subscriptions.rpg_settlement(relief);
livesHud.subscriptions.rpg_settlement(relief);
assert(panel(livesHud,"RewardLabel").text.indexOf("2000") >= 0, "third-life gold shown in loss settlement");
assert(panel(livesHud,"WalletBalance").text.indexOf("2500") >= 0, "replayed settlement cannot credit a client wallet twice");
lifeSnapshot(1, "result");
livesHud.subscriptions.rpg_settlement({winner:"timeout",lives_remaining:1,max_lives:5,
    life_reward_items:"item_aegis;item_cheese",life_reward_gold:0});
assert(panel(livesHud,"LootPopupItems").children.map(function(card) { return card.children[0].itemname; }).join(";")
    === "item_aegis;item_cheese", "last-life loss displays both native reward icons");
lifeSnapshot(1, "setup");
assert(panel(livesHud,"StartBattleButton").enabled, "last life still permits a challenge");
lifeSnapshot(0, "result");
assert(!panel(livesHud,"StartBattleButton").enabled
    && panel(livesHud,"BattleStatus").text === "#dota2_rpg_run_failed", "fifth loss displays run end and disables start");
// Sustained movement uses the real action menu and condition modal, never outer controls.
["shukuchi", "trample"].forEach(function (presetName) {
    var moveHud = runHud(), hero = "npc_dota_hero_" + (presetName === "shukuchi" ? "weaver" : "primal_beast");
    var ability = presetName === "shukuchi" ? "weaver_shukuchi" : "primal_beast_trample";
    var sync = moveHud.context.RpgRuleSync;
    moveHud.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    moveHud.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:980,hero_name:hero,rule_key:hero,
        can_edit:1,rules_ready:1,actions_text:"attack;sustained_move;"+ability,details_text:"attack;unknown_movement_metadata;"+ability,
        abilities_text:ability+";item_blink;attack;sustained_move",
        rules:[{action:"attack",enabled:1,target_team:"enemy",use_conditions:[{type:"elapsed_gte",seconds:7,value:7}]}]});
    moveHud.subscriptions.rpg_enemy_roster({units:[{id:981,name:lion}]});
    moveHud.subscriptions.rpg_hero_slots({slot_key:"dire_1",hero_index:981,hero_name:lion,rule_key:"enemy:lion",target_actor:"level:enemy:lion",actions_text:"attack;lion_impale",abilities_text:"lion_impale"});
    click(moveHud,"RadiantAddRule0"); click(moveHud,"RadiantActionSelect1");
    assert(panel(moveHud,"ActionOpt_Radiant1_sustained_move").GetChild(0).text === "#dota2_rpg_action_sustained_move", "unknown movement metadata displays localized action, not ability tooltip");
    click(moveHud,"ActionOpt_Radiant1_sustained_move"); click(moveHud,"RadiantRuleSettings1");
    choice(moveHud,"V2_target0","specified_enemy"); click(moveHud,"V2_target0_target_actorOption_0");
    choice(moveHud,"V2_priority0","farthest");
    click(moveHud,"V2MovementPreset_"+presetName);
    var expected = moveHud.context.RpgConditionCatalog.movementPreset(presetName);
    assert(panel(moveHud,"V2_movement_buff").text === expected.movement_buff, "preset supplies associated native modifier without current buffs");
    assert(panel(moveHud,"V2MovementTrigger").GetChild(0).abilityname === ability, "preset trigger uses ability icon");
    var options = panel(moveHud,"V2MovementTriggerMenu").children.filter(function(p) { return p.BHasClass("V2ActionChoice"); });
    assert(options.length === 1 && options[0].GetChild(0).abilityname === ability, "trigger selector includes only self hero skills, not enemies/items/actions");
    click(moveHud,"RuleSettingsApply");
    var wire = latest(moveHud,hero,2);
    assert(wire.action_kind === "move" && wire.action_id === "sustained_move" && wire.action_name === "", "native movement identity does not leak metadata");
    assert(wire.movement_loop === 1 && wire.movement_duration > 5.5, "buff presets keep cycling until native buff ends, with a later safety deadline");
    Object.keys(expected).forEach(function(key) { assert(wire[key] === (typeof expected[key] === "boolean" ? Number(expected[key]) : expected[key]), "preset full save: "+key); });
    assert(wire.target_filter_1_target_actor === "level:enemy:lion" && wire.target_priority_1_type === "farthest", "movement retains F39 and priority through preset");
    click(moveHud,"RadiantRuleSettings1");
    assert(panel(moveHud,"V2_movement_mode").GetChild(0).text === "#dota2_rpg_v2_movement_mode_"+expected.movement_mode, "movement mode reopens");
    click(moveHud,"V2MovementBuffSelectOption_movement_preset_"+(presetName === "shukuchi" ? "trample" : "shukuchi"));
    assert(panel(moveHud,"V2_movement_buff").text !== expected.movement_buff, "buff selector independent of live buffs");
    input(moveHud,"V2_movement_buff","modifier_custom_native"); input(moveHud,"V2_movement_duration","8.25"); input(moveHud,"V2_movement_distance","240");
    ["movement_retarget","movement_loop","movement_interruptible"].forEach(function(key) { click(moveHud,"V2_"+key+"Option_"+key+"_true"); });
    click(moveHud,"V2_movement_directionOption_movement_direction_ccw"); click(moveHud,"RuleSettingsApply");
    wire = latest(moveHud,hero,2);
    assert(wire.movement_duration === 8.25 && wire.movement_distance === 240 && wire.movement_retarget === 1 && wire.movement_loop === 1 && wire.movement_interruptible === 1 && wire.movement_direction === "ccw", "custom fields and booleans save");
    var server = Object.assign({}, wire, {action:"sustained_move", movement_loop:"true", movement_retarget:"1", movement_interruptible:true,
        use_conditions:[],target_filters:[{type:"specified_enemy",target_actor:wire.target_filter_1_target_actor}],target_priorities:[{type:"farthest"}]});
    var round = sync.serialize({rule:sync.fromServer(server)});
    Object.keys(expected).forEach(function(key) { assert(round[key] === wire[key], "server movement roundtrip: "+key); });
    // Fresh HUD ensures the authoritative server path, not local authored cache, restores controls.
    var reload = runHud(); reload.subscriptions.rpg_shop_state({lineup_text:hero,owned_text:hero});
    reload.subscriptions.rpg_hero_slots({slot_key:"radiant_1",hero_index:980,hero_name:hero,can_edit:1,rules_ready:1,
        actions_text:"sustained_move;attack",abilities_text:ability,rules:[server]});
    click(reload,"RadiantRuleSettings0"); assert(panel(reload,"V2_movement_buff").text === "modifier_custom_native" && panel(reload,"V2_movement_duration").text === "8.25", "authoritative HUD reopen restores custom movement");
    click(reload,"V2ClearConditions"); click(reload,"RuleSettingsApply");
    assert(latest(reload,hero).movement_buff === "" && latest(reload,hero).movement_retarget === 0, "clear resets movement defaults");
    click(moveHud,"RadiantRuleSettings0"); assert(panel(moveHud,"V2_use0_seconds").text === "7", "movement editing cannot mutate original attack rule");
    assert(!panel(moveHud,"RuleSettingsBody").FindChildTraverse("V2_movement_buff"), "attack has no movement controls");
    assert(!panel(moveHud,"RuleSettingsBody").FindChildTraverse("V2_positioning_modeOption_positioning_mode_cast_range"), "attack cannot choose cast range");
    click(moveHud,"V2_positioning_modeOption_positioning_mode_attack_range"); input(moveHud,"V2_positioning_tolerance",65); click(moveHud,"RuleSettingsApply");
    assert(latest(moveHud,hero).positioning_mode === "attack_range" && latest(moveHud,hero).positioning_tolerance === 65, "safe maximum attack-range positioning saves");
    click(moveHud,"RadiantRuleSettings0"); assert(panel(moveHud,"V2_positioning_tolerance").text === "65", "positioning reopens");
    click(moveHud,"RuleSettingsClose");
    [false,0,"0","false"].forEach(function(value) { assert(sync.serialize({rule:{action:"sustained_move",movement_retarget:value,movement_loop:value,movement_interruptible:value}}).movement_retarget === 0, "false wire encodings are not truthy"); });
    var item = sync.serialize({rule:{action:"item_blink",movement_buff:"bad",positioning_mode:"cast_range"}});
    assert(item.movement_buff === undefined && item.positioning_mode === undefined, "unsupported item strips movement and positioning");
    var spell = sync.fromServer({action:ability,positioning_mode:"cast_range",positioning_distance:300,positioning_tolerance:25});
    assert(sync.serialize({rule:spell}).positioning_mode === "cast_range", "ability cast range roundtrips");
    click(moveHud,"RadiantActionSelect1"); click(moveHud,"ActionOpt_Radiant1_"+ability); click(moveHud,"RadiantRuleSettings1");
    assert(!panel(moveHud,"RuleSettingsBody").FindChildTraverse("V2_movement_buff"), "changing to an ability hides stale movement settings");
    click(moveHud,"V2_positioning_modeOption_positioning_mode_cast_range"); input(moveHud,"V2_positioning_distance",320); input(moveHud,"V2_positioning_tolerance",30); click(moveHud,"RuleSettingsApply");
    var spellWire = latest(moveHud,hero,2);
    assert(spellWire.positioning_mode === "cast_range" && spellWire.positioning_distance === 320 && spellWire.movement_buff === undefined, "real ability modal saves positioning without stale movement payload");
    click(moveHud,"RadiantRuleSettings1"); input(moveHud,"V2_positioning_distance",999); click(moveHud,"RuleSettingsClose"); click(moveHud,"RadiantRuleSettings1");
    assert(panel(moveHud,"V2_positioning_distance").text === "320", "cancel does not mutate authored positioning"); click(moveHud,"RuleSettingsClose");
    var malformed = sync.serialize({rule:{action:"sustained_move",movement_mode:"teleport",movement_direction:"up",movement_duration:"NaN",movement_distance:-1,movement_retarget:"bogus"}});
    assert(malformed.movement_mode === "follow" && malformed.movement_direction === "auto" && malformed.movement_duration === 5 && malformed.movement_distance === 0 && malformed.movement_retarget === 0, "invalid movement inputs normalize safely");
    var original = {action:"sustained_move",use_conditions:[{type:"always"}],movement_buff:"modifier_original"};
    var draftCopy = sync.initialSettings(original); draftCopy.use_conditions[0].type = "elapsed_gte";
    assert(original.use_conditions[0].type === "always", "initial settings deep clone prevents accidental rule mutation");
});
console.log("PASS: sustained movement presets, self-only trigger icons, F39, custom buffs, real HUD save/reopen/server roundtrip, safe positioning and boolean wire encodings");
console.log("PASS: five hearts, loss rewards, authoritative wallet and terminal life UI");
console.log("PASS: " + presetCount + " complete template variants, 78 unchanged documented menu IDs plus F39/U39/P14, U13/U14 selection, previews and stale field removal");
console.log("PASS: real XML/UI 4/4/2 conditions, flat serialization, toggles, native actions, malformed inputs, cancellation, copying, 32 rules, respawn/reorder and hero isolation");
