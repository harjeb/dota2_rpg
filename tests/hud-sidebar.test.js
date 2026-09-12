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
var settlementLayout = resultLayout.children.find(function (node) { return node.attrs.id === "SettlementPanel"; });
if (!settlementLayout || !settlementLayout.children.some(function (node) { return node.attrs.id === "LootPopup"; })) {
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
    var actualRoot = instantiateSnippet(rootLayout, null);
    function register(node) {
        if (node.id) { panels["#" + node.id] = node; }
        node.children.forEach(register);
    }
    register(actualRoot);
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
    var nativeRoot = createPanel("DotaHud");
    rootPanel.parent = nativeRoot;
    nativeRoot.children.push(rootPanel);
    rootPanel.FindChildTraverse = function (id) { return panorama("#" + id); };
    panorama.GetContextPanel = function () { return rootPanel; };
    panorama.Localize = function (token) {
        if (token === "#dota2_rpg_remaining_time") { return "剩余时间"; }
        return token === "#dota2_rpg_reward_xp" ? "XP %s1 (active %s2 / bench %s3)" : token;
    };
    var timers = [];
    var walletTimers = [];
    panorama.Schedule = function (delay, callback) {
        if (delay === 3) { timers.push(callback); }
        else if (delay === 0.25) { walletTimers.push(callback); }
        else { callback(); }
    };
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
            GetLocalPlayer: function () { return 0; },
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
        nativeRoot: nativeRoot,
        walletTimers: walletTimers,
        timers: timers,
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
assert(/#RightSidebar\s*\{[^}]*height:\s*69%[^}]*margin-top:\s*72px/s.test(cssSource), "sidebar sits below debug controls and reserves bottom HUD space");
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
assert(panel(hud, "BattleCountdown").text === "剩余时间 0:09" && panel(hud, "BattleCountdown").BHasClass("CountdownUrgent"), "countdown uses authoritative battle time");
click(hud, "DamageToggle"); click(hud, "EquipmentToggle");
assert(!panel(hud, "DamageBody").BHasClass("Hidden") && !panel(hud, "EquipmentBody").BHasClass("Hidden"), "both restore independently");
hud.subscriptions.rpg_damage_stats({elapsed: 119.1, units: []});
assert(panel(hud, "BattleCountdown").text === "剩余时间 0:01", "periodic DPS events advance countdown without a phase broadcast");
hud.subscriptions.rpg_damage_stats({elapsed: 121, units: []});
assert(panel(hud, "BattleCountdown").text === "剩余时间 0:00", "countdown clamps at zero");
hud.subscriptions.rpg_battle_state({phase: "result", battle_time: 0, time_limit: 120});
assert(panel(hud, "BattleCountdown").text === "剩余时间 0:00", "settlement does not reset elapsed time");
hud.subscriptions.rpg_battle_state({phase: "setup", battle_time: 130, time_limit: 120});
assert(panel(hud, "BattleCountdown").text === "剩余时间 2:00", "next setup resets countdown");
hud.subscriptions.rpg_enemy_roster({units: [{id: 501, name: "npc_dota_hero_lion"}]});
hud.subscriptions.rpg_hero_slots({slot_key: "dire_1", hero_name: "npc_dota_hero_lion", hero_index: 501, rules_ready: 1, can_edit: 0});
assert(!hud.createdPanels.some(function(p) { return /^Dire/.test(p.id); }), "enemy updates never create editor panels");
hud.subscriptions.rpg_damage_stats({elapsed: 10, units: [{id: 501, team: 3, name: "npc_dota_hero_lion", dps: 25, total: 250, sources: [{name: "attack", total: 250, targets: [{id: 601, name: "npc_dota_hero_axe", total: 250}]}], targets: [{id: 601, name: "npc_dota_hero_axe", total: 250}]}]});
click(hud, "DamageEnemy");
assert(panel(hud, "DamageUnits").children.length === 1, "enemy DPS remains available");
assert(panel(hud, "DamageTargets").children[0].text.indexOf("601") >= 0, "enemy target breakdown remains available");
console.log("HUD sidebar tests passed");

// The native ShopButton subtree matches this installation's decompiled
// dota_hud_quick_buy.xml. Load all actual addon scripts above, not a stub bridge.
function mountNativeShop(h) {
    var controls = createPanel("ShopCourierControls");
    var button = createPanel("ShopButton");
    var label = createPanel("GoldLabel");
    label.text = "500";
    label.AddClass("ShopButtonValueLabel");
    label.SetParent(button);
    button.SetParent(controls);
    controls.SetParent(h.nativeRoot);
    var clicks = 0;
    button.SetPanelEvent("onactivate", function () { clicks++; });
    return { controls: controls, button: button, label: label, clicks: function () { return clicks; } };
}
var walletHud = runHud();
walletHud.subscriptions.rpg_shop_state({gold: 360}); // 500 - a 140-gold purchase
var nativeShop = mountNativeShop(walletHud); // Valve creates the HUD after the broadcast
walletHud.walletTimers.shift()();
assert(nativeShop.label.text === "360" && panel(walletHud, "WalletBalance").text.endsWith(" 360"), "late native shop receives the latest top HUD balance");
[220, 0, 70, 1045].forEach(function (gold) {
    walletHud.subscriptions.rpg_shop_state({gold: gold});
    assert(nativeShop.label.text === String(gold) && panel(walletHud, "WalletBalance").text.endsWith(" " + gold), "purchase, zero balance, sale refund and reward update both displays: " + gold);
});
nativeShop.label.text = "500"; // simulate a native refresh restoring its stale binding
walletHud.walletTimers.shift()();
assert(nativeShop.label.text === "1045", "native refresh cannot leave the old balance visible");
nativeShop.button.events.onactivate();
assert(nativeShop.clicks() === 1 && nativeShop.label.BHasClass("ShopButtonValueLabel"), "native shop click handler and label style survive synchronization");
walletHud.nativeRoot.children = walletHud.nativeRoot.children.filter(function (p) { return p !== nativeShop.controls; });
nativeShop = mountNativeShop(walletHud); // portrait/HUD replacement, no new server message
walletHud.walletTimers.shift()();
assert(nativeShop.label.text === "1045", "rebuilt native HUD uses the cached authoritative balance");
walletHud.subscriptions.rpg_shop_state({gold: 500, rule_generation: 2});
walletHud.subscriptions.rpg_shop_state({gold: 99999, rule_generation: 1});
assert(nativeShop.label.text === "500" && panel(walletHud, "WalletBalance").text.endsWith(" 500"), "new-run wallet updates both displays and stale generations update neither");
console.log("PASS native shop/top wallet: delayed creation, purchases, zero, refund, reward, refresh, rebuild and run generation");

// Execute actual XML controls and all shipped scripts across terminal replays.
[0, 1].forEach(function (failed) {
    var replayHud = runHud();
    var state = {phase: "result", ready: 0, winner: failed ? "dire" : "radiant",
        run_complete: 1, run_failed: failed, replay_available: 1,
        owner_player_id: 0, settlement_generation: 11};
    replayHud.subscriptions.rpg_battle_state(state);
    assert(!panel(replayHud, "ReplayRunButton").BHasClass("Hidden"), "terminal replay visible");
    assert(panel(replayHud, "ReplayRunLabel").text === "#dota2_rpg_replay_chapter_one", "both terminal outcomes restart from chapter one");
    var before = replayHud.sentEvents.length;
    click(replayHud, "ReplayRunButton"); click(replayHud, "ReplayRunButton");
    replayHud.subscriptions.rpg_battle_state(state);
    click(replayHud, "ReplayRunButton");
    assert(replayHud.sentEvents.length === before + 1, "double click and duplicate result cannot replay twice");
    assert(replayHud.sentEvents[before].name === "rpg_replay_run" && replayHud.sentEvents[before].payload.settlement_generation === 11, "server generation sent");
    replayHud.subscriptions.rpg_battle_state({phase: "setup", ready: 1, settlement_generation: 12});
    replayHud.subscriptions.rpg_battle_state(state);
    replayHud.subscriptions.rpg_settlement({winner: "radiant", settlement_generation: 11});
    assert(panel(replayHud, "BattleResult").BHasClass("Hidden") && panel(replayHud, "StartBattleButton").enabled, "setup restored and stale result/settlement ignored");
    assert(panel(replayHud, "ReplayRunButton").BHasClass("Hidden"), "replay hidden during preparation");
    state.settlement_generation = 13; state.owner_player_id = 1;
    replayHud.subscriptions.rpg_battle_state(state);
    assert(panel(replayHud, "ReplayRunButton").BHasClass("Hidden"), "nonowner cannot replay");
    state.owner_player_id = 0;
    replayHud.subscriptions.rpg_battle_state(state);
    assert(panel(replayHud, "ReplayRunButton").enabled, "later terminal can replay again");
    state.replay_available = 0;
    replayHud.subscriptions.rpg_battle_state(state);
    assert(panel(replayHud, "ReplayRunButton").BHasClass("Hidden"), "ordinary and debug results do not expose terminal replay");
});
console.log("PASS actual HUD replay lifecycle: victory/defeat, owner, duplicate clicks, stale events, setup and later replay");

var loadingHud = runHud();
var loadingState = {phase: "setup", ready: 0, stage_loading: 1, level: "ch02"};
loadingHud.subscriptions.rpg_battle_state(loadingState);
var sentBefore = loadingHud.sentEvents.length;
click(loadingHud, "StartBattleButton");
assert(!panel(loadingHud, "StartBattleButton").enabled && loadingHud.sentEvents.length === sentBefore, "loading cannot request battle");
assert(panel(loadingHud, "StartBattleLabel").text === "#dota2_rpg_stage_loading_button", "loading label on actual button");
assert(panel(loadingHud, "BattleStatus").text === "#dota2_rpg_stage_loading", "resource wait explained");
loadingHud.subscriptions.rpg_battle_state({phase: "setup", ready: 0, stage_failed: 1});
assert(panel(loadingHud, "StartBattleButton").enabled && panel(loadingHud, "StartBattleLabel").text === "#dota2_rpg_stage_retry", "failed resource has recovery action");
click(loadingHud, "StartBattleButton"); click(loadingHud, "StartBattleButton");
assert(loadingHud.sentEvents.length === sentBefore + 1, "retry is submitted once before server response");
loadingHud.subscriptions.rpg_battle_state(loadingState);
assert(!panel(loadingHud, "StartBattleButton").enabled, "pending retry stays gated");
loadingHud.subscriptions.rpg_battle_state({phase: "setup", ready: 1});
assert(panel(loadingHud, "StartBattleLabel").text === "#dota2_rpg_start_battle", "ready restores battle action");
click(loadingHud, "StartBattleButton");
assert(loadingHud.sentEvents.length === sentBefore + 2, "ready stage can start");
console.log("PASS actual HUD stage preload: waiting, failure, single retry and readiness");

function visible(h, id) {
    var node = panel(h, id);
    while (node) { if (node.BHasClass("Hidden")) { return false; } node = node.parent; }
    return true;
}
var rewards = runHud();
var victory = {winner:"radiant", settlement_generation:21, gold:123, xp_per_active_hero:45,
    xp_per_bench_hero:12, loot_text:"item_blink;item_branches"};
rewards.subscriptions.rpg_settlement(victory);
assert(visible(rewards,"RewardLabel") && visible(rewards,"LootPopupItems"), "gold XP and equipment visible simultaneously through actual XML ancestors");
assert(panel(rewards,"RewardLabel").text.includes("123") && panel(rewards,"RewardLabel").text.includes("active 45 / bench 12"), "summary contains gold and XP");
assert(panel(rewards,"LootPopupItems").children.length === 2 && rewards.timers.length === 1, "one frame and one timer for all rewards");
var firstTimer = rewards.timers[0];
click(rewards,"LootPopupConfirm");
rewards.subscriptions.rpg_battle_state({phase:"result",winner:"radiant",settlement_generation:21});
rewards.subscriptions.rpg_settlement(victory);
assert(!visible(rewards,"RewardLabel") && !visible(rewards,"LootPopupItems") && rewards.timers.length === 1, "late phase and duplicate settlement cannot resurrect confirmed summary");
rewards.subscriptions.rpg_settlement({winner:"radiant",settlement_generation:22,gold:9,xp_pool:8,loot_text:""});
firstTimer();
assert(visible(rewards,"RewardLabel") && !visible(rewards,"LootPopup"), "stale timer cannot close newer no-loot summary");
rewards.timers[1]();
assert(!visible(rewards,"BattleResult"), "auto-close removes entire nonterminal frame");
rewards.subscriptions.rpg_settlement({winner:"dire",settlement_generation:23,life_reward_gold:77,life_reward_items:"item_branches",life_reward_pending:1});
assert(visible(rewards,"LootPopupItems") && panel(rewards,"RewardLabel").text.includes("77"), "death relief items and gold share defeat summary");
rewards.timers[2]();
rewards.subscriptions.rpg_battle_state({phase:"result",winner:"dire",run_failed:1,replay_available:1,owner_player_id:0,settlement_generation:23});
assert(visible(rewards,"ReplayRunButton") && !visible(rewards,"SettlementPanel"), "late terminal state preserves replay without resurrecting summary");
rewards.subscriptions.rpg_settlement(victory);
assert(!visible(rewards,"SettlementPanel"), "stale settlement ignored even before newer battle generation");
click(rewards,"ReplayRunButton");
assert(rewards.sentEvents.some(function(e) { return e.name === "rpg_replay_run"; }), "replay remains usable after auto-close");
console.log("PASS actual XML unified settlement lifecycle: simultaneous rewards, single timer, confirm, no-loot, relief, terminal and stale messages");

var terminalRewards = runHud();
terminalRewards.subscriptions.rpg_battle_state({phase:"result",winner:"radiant",replay_available:1,owner_player_id:0,settlement_generation:30});
terminalRewards.subscriptions.rpg_settlement({winner:"radiant",settlement_generation:30,gold:50,xp_pool:10,loot_text:"item_blink"});
click(terminalRewards,"LootPopupConfirm");
terminalRewards.timers[0]();
assert(visible(terminalRewards,"ReplayRunButton") && !visible(terminalRewards,"SettlementPanel"), "terminal victory replay survives both confirm and expired timer");
terminalRewards.subscriptions.rpg_battle_state({phase:"setup",settlement_generation:31});
terminalRewards.subscriptions.rpg_settlement({winner:"dire",settlement_generation:32});
assert(visible(terminalRewards,"SettlementPanel") && !visible(terminalRewards,"LootPopup"), "plain defeat has one confirmable summary without equipment");
terminalRewards.subscriptions.rpg_battle_state({phase:"result",settlement_generation:30,winner:"radiant",replay_available:1,owner_player_id:0});
assert(!visible(terminalRewards,"ReplayRunButton"), "stale phase cannot restore previous terminal controls");
terminalRewards.timers[1]();
assert(!visible(terminalRewards,"BattleResult"), "plain defeat auto-closes entire frame");
