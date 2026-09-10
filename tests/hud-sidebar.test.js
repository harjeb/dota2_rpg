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

var hud = runHud();
assert(!panel(hud, "DireEditor") && !panel(hud, "DireRestoreButton"), "enemy editor is absent from the actual XML");
var sidebar = rootLayout.children.filter(function (node) { return node.attrs.id === "RightSidebar"; })[0];
assert(sidebar.children[0].attrs.id === "DamagePanel" && sidebar.children[1].attrs.id === "ItemShopPanel", "equipment follows DPS in the same sidebar");
assert(!/Hidden/.test(sidebar.children[0].attrs.class), "DPS defaults visible");
assert(!/Hidden/.test(sidebar.children[1].attrs.class), "equipment defaults visible");
assert(/height:\s*66%/.test(cssSource) && /margin-top:\s*100px/.test(cssSource), "sidebar reserves bottom HUD space");
assert(/\.SidePanelBody\s*\{[^}]*overflow:\s*squish scroll/s.test(cssSource), "both bodies scroll");
["setup", "battle", "fight", "finished", "setup"].forEach(function (phase) {
    hud.subscriptions.rpg_battle_state({phase: phase, ready: 1, battle_time: 17, time_limit: 120});
    assert(!panel(hud, "DamagePanel").BHasClass("Hidden"), "DPS visible through " + phase);
    assert(!panel(hud, "ItemShopPanel").BHasClass("Hidden"), "equipment visible through " + phase);
});
click(hud, "EquipmentToggle");
assert(panel(hud, "EquipmentBody").BHasClass("Hidden"), "equipment minimizes");
assert(!panel(hud, "DamageBody").BHasClass("Hidden"), "DPS remains expanded");
click(hud, "DamageToggle");
hud.subscriptions.rpg_battle_state({phase: "fight", battle_time: 111, time_limit: 120});
assert(panel(hud, "DamageBody").BHasClass("Hidden") && panel(hud, "EquipmentBody").BHasClass("Hidden"), "phase update respects both minimized states");
assert(panel(hud, "BattleCountdown").text === "0:09" && panel(hud, "BattleCountdown").BHasClass("CountdownUrgent"), "countdown uses authoritative battle time");
click(hud, "DamageToggle"); click(hud, "EquipmentToggle");
assert(!panel(hud, "DamageBody").BHasClass("Hidden") && !panel(hud, "EquipmentBody").BHasClass("Hidden"), "both restore independently");
hud.subscriptions.rpg_damage_stats({elapsed: 119.1, units: []});
assert(panel(hud, "BattleCountdown").text === "0:01", "periodic DPS events advance countdown without a phase broadcast");
hud.subscriptions.rpg_damage_stats({elapsed: 121, units: []});
assert(panel(hud, "BattleCountdown").text === "0:00", "countdown clamps at zero");
hud.subscriptions.rpg_battle_state({phase: "result", battle_time: 0, time_limit: 120});
assert(panel(hud, "BattleCountdown").text === "0:00", "settlement does not reset elapsed time");
hud.subscriptions.rpg_battle_state({phase: "setup", battle_time: 130, time_limit: 120});
assert(panel(hud, "BattleCountdown").text === "2:00", "next setup resets countdown");
hud.subscriptions.rpg_enemy_roster({units: [{id: 501, name: "npc_dota_hero_lion"}]});
hud.subscriptions.rpg_hero_slots({slot_key: "dire_1", hero_name: "npc_dota_hero_lion", hero_index: 501, rules_ready: 1, can_edit: 0});
assert(!hud.createdPanels.some(function(p) { return /^Dire/.test(p.id); }), "enemy updates never create editor panels");
hud.subscriptions.rpg_damage_stats({elapsed: 10, units: [{id: 501, team: 3, name: "npc_dota_hero_lion", dps: 25, total: 250, sources: [{name: "attack", total: 250, targets: [{id: 601, name: "npc_dota_hero_axe", total: 250}]}], targets: [{id: 601, name: "npc_dota_hero_axe", total: 250}]}]});
click(hud, "DamageEnemy");
assert(panel(hud, "DamageUnits").children.length === 1, "enemy DPS remains available");
assert(panel(hud, "DamageTargets").children[0].text.indexOf("601") >= 0, "enemy target breakdown remains available");
console.log("HUD sidebar tests passed");
