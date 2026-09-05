"use strict";

var fs = require("fs");
var path = require("path");
var vm = require("vm");

var repoRoot = path.resolve(__dirname, "..");
var hudPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "scripts", "custom_game", "rpg_demo_hud.js");
var brokenV1Path = path.join(repoRoot, "tests", "fixtures", "save-v1-zero-gold.json");
var hudSource = fs.readFileSync(hudPath, "utf8");

function createPanel(id) {
    var classes = {};
    return {
        id: id || "",
        text: "",
        enabled: true,
        AddClass: function (name) { classes[name] = true; },
        SetHasClass: function (name, enabled) { classes[name] = Boolean(enabled); },
        BHasClass: function (name) { return Boolean(classes[name]); },
        SetPanelEvent: function () {},
        BLoadLayoutSnippet: function () {},
        FindChildTraverse: function (childId) { return createPanel(childId); },
        GetChildCount: function () { return 0; },
        GetChild: function () { return createPanel(""); },
        GetAttributeString: function (_, fallback) { return fallback; },
        RemoveAndDeleteChildren: function () {},
        classes: classes
    };
}

function runHud(savedValue) {
    var panels = {};
    var createdPanels = [];
    var sentEvents = [];
    var subscriptions = {};
    var persistedValue = null;

    function panorama(selector) {
        if (!panels[selector]) {
            panels[selector] = createPanel(selector);
        }
        return panels[selector];
    }
    panorama.CreatePanel = function (_, parent, id) {
        var panel = createPanel(id || "");
        createdPanels.push(panel);
        return panel;
    };
    panorama.Localize = function (token) {
        var localized = {
            "#npc_dota_hero_axe": "Localized Axe",
            "#dota2_rpg_shop_title": "Hero Shop",
            "#dota2_rpg_shop_gold": "Gold: %s1",
            "#dota2_rpg_shop_price": "%s1 gold",
            "#dota2_rpg_shop_refresh": "Refresh (%s1 gold)",
            "#dota2_rpg_bench_buy": "Buy bench slot (%s1 gold)"
        };
        return localized[token] || token;
    };
    panorama.LocalStorage = {
        Get: function () { return savedValue === null ? null : JSON.stringify(savedValue); },
        Set: function (_, value) { persistedValue = value; }
    };

    var context = {
        console: console,
        $: panorama,
        GameEvents: {
            Subscribe: function (name, callback) { subscriptions[name] = callback; },
            SendCustomGameEventToServer: function (name, payload) {
                sentEvents.push({ name: name, payload: payload });
            }
        }
    };
    vm.runInNewContext(hudSource, context, { filename: hudPath });

    var saveSync = null;
    for (var index = 0; index < sentEvents.length; index++) {
        if (sentEvents[index].name === "rpg_save_sync") {
            saveSync = sentEvents[index].payload;
            break;
        }
    }
    if (!saveSync) {
        throw new Error("HUD did not send rpg_save_sync during initialization");
    }
    return {
        payload: saveSync,
        persistedValue: persistedValue,
        panels: panels,
        createdPanels: createdPanels,
        subscriptions: subscriptions
    };
}

function assert(condition, message) {
    if (!condition) {
        throw new Error(message);
    }
}

var fresh = runHud(null);
assert(fresh.payload.gold === 300, "fresh save must start with 300 gold");
assert(fresh.payload.hero_data_text === "", "fresh hero data must be serialized as an empty string");
assert(fresh.payload.lineup_text === "", "fresh lineup must be serialized as an empty string");
assert(fresh.payload.owned === undefined && fresh.payload.lineup === undefined,
    "save sync must not contain nested list fields");

fresh.subscriptions.rpg_shop_state({
    gold: 300,
    offer_text: "npc_dota_hero_axe|1|common|100",
    owned_text: "",
    lineup_text: "",
    bench_slots: 0,
    cost_hero: 100,
    cost_refresh: 20,
    cost_bench_slot: 200,
    bench_slot_max: 5,
    lineup_max: 5
});
assert(fresh.panels["#RefreshShopLabel"].text === "Refresh (20 gold)",
    "refresh label must be localized with the server-configured cost");
var levelQualityFound = fresh.createdPanels.some(function (panel) {
    return panel.classes.ShopName && panel.text === "Lv1 普通";
});
assert(levelQualityFound, "shop offer labels must show recruit level and quality");
var priceFound = fresh.createdPanels.some(function (panel) {
    return panel.classes.ShopPrice && panel.text === "100g";
});
assert(priceFound, "shop offer labels must show the composed price");

fresh.subscriptions.rpg_battle_state({ phase: "setup", ready: 1, gold: 180, level: "ch01" });

var brokenV1 = runHud(JSON.parse(fs.readFileSync(brokenV1Path, "utf8")));
assert(brokenV1.payload.gold === 300, "empty v1 save affected by the zero-gold bug must migrate to 300 gold");

var progressedV1 = runHud({
    gold: 0,
    level: 2,
    cleared: { ch01: true },
    attempts: {},
    owned: ["npc_dota_hero_axe"],
    lineup: ["npc_dota_hero_axe"],
    bench_slots: 0,
    current_level: "ch02"
});
assert(progressedV1.payload.gold === 0, "a progressed save that legitimately has zero gold must stay at zero");
assert(progressedV1.payload.hero_data_text === "npc_dota_hero_axe:2:0:common:2",
    "unified level must migrate into per-hero level/xp/quality/skill-point data");
assert(progressedV1.payload.lineup_text === "npc_dota_hero_axe", "lineup must use the flat payload field");

var objectLists = runHud({
    gold: 100,
    level: "1",
    cleared: {},
    attempts: {},
    owned: { 1: "npc_dota_hero_axe", 2: "npc_dota_hero_sven" },
    lineup: { 1: "npc_dota_hero_sven" },
    bench_slots: "0",
    current_level: "ch01"
});
assert(objectLists.payload.gold === 100, "object-shaped old lists must not reset gold");
assert(objectLists.payload.hero_data_text === "npc_dota_hero_axe:1:0:common:1;npc_dota_hero_sven:1:0:common:1",
    "object-shaped owned list must be normalized into per-hero data without loss");
assert(objectLists.payload.lineup_text === "npc_dota_hero_sven",
    "object-shaped lineup must be normalized without data loss");

var currentSave = runHud({
    version: 2,
    gold: 0,
    level: 1,
    cleared: {},
    attempts: {},
    owned: [],
    lineup: [],
    bench_slots: 0,
    current_level: "ch01"
});
assert(currentSave.payload.gold === 0, "current-version zero gold must not be migrated again");

console.log("PASS: Panorama save migration, localized shop rendering, and authoritative gold display");
