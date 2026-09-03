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
        RemoveAndDeleteChildren: function () {}
    };
}

function runHud(savedValue) {
    var panels = {};
    var sentEvents = [];
    var persistedValue = null;

    function panorama(selector) {
        if (!panels[selector]) {
            panels[selector] = createPanel(selector);
        }
        return panels[selector];
    }
    panorama.CreatePanel = function (_, parent, id) {
        return createPanel(id || "");
    };
    panorama.Localize = function (token) { return token; };
    panorama.LocalStorage = {
        Get: function () { return savedValue === null ? null : JSON.stringify(savedValue); },
        Set: function (_, value) { persistedValue = value; }
    };

    var context = {
        console: console,
        $: panorama,
        GameEvents: {
            Subscribe: function () {},
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
    return { payload: saveSync, persistedValue: persistedValue };
}

function assert(condition, message) {
    if (!condition) {
        throw new Error(message);
    }
}

var fresh = runHud(null);
assert(fresh.payload.gold === 300, "fresh save must start with 300 gold");
assert(fresh.payload.owned_text === "", "fresh owned list must be serialized as an empty string");
assert(fresh.payload.lineup_text === "", "fresh lineup must be serialized as an empty string");
assert(fresh.payload.owned === undefined && fresh.payload.lineup === undefined,
    "save sync must not contain nested list fields");

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
assert(progressedV1.payload.owned_text === "npc_dota_hero_axe", "owned heroes must use the flat payload field");
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
assert(objectLists.payload.owned_text === "npc_dota_hero_axe;npc_dota_hero_sven",
    "object-shaped owned list must be normalized without data loss");
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

console.log("PASS: Panorama save initialization, v1 migration, and flat CEM payloads");
