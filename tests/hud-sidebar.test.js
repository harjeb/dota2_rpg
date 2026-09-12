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
    var lastPortraitUnit = 503;
    var unhandledEvents = {};
    var messages = [];
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
    var nativeRootTraverse = nativeRoot.FindChildTraverse;
    nativeRoot.FindChildTraverse = function (id) {
        return panorama("#" + id) || nativeRootTraverse.call(this, id);
    };
    panorama.Msg = function (message) { messages.push(message); };
    panorama.GetContextPanel = function () { return rootPanel; };
    panorama.RegisterForUnhandledEvent = function (name, callback) { unhandledEvents[name] = callback; };
    panorama.Localize = function (token) {
        if (token === "#dota2_rpg_remaining_time") { return "剩余时间"; }
        return token === "#dota2_rpg_reward_xp" ? "XP %s1 (active %s2 / bench %s3)" : token;
    };
    var timers = [];
    var walletTimers = [];
    var closeTimers = [];
    panorama.Schedule = function (delay, callback) {
        if (delay === 3) { timers.push(callback); }
        else if (delay === 0.25) { walletTimers.push(callback); }
        else if (delay === 0.15) { closeTimers.push(callback); }
        else { callback(); }
    };
    panorama.LocalStorage = {
        Get: function () { localStorageCalls++; return "null"; },
        Set: function () { localStorageCalls++; }
    };

    var customConfig = {};
    var context = {
        eval: function () { throw new Error("Code generation from strings disallowed"); },
        GameUI: {
            CustomUIConfig: function () { return customConfig; },
            SelectUnit: function (index, additive) {
                nativeSelections.push({ index: index, additive: additive });
                lastPortraitUnit = index;
            }
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
            GetLocalPlayerPortraitUnit: function () { return lastPortraitUnit; }
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
        closeTimers: closeTimers,
        timers: timers,
        context: context,
        panels: panels,
        createdPanels: createdPanels,
        sentEvents: sentEvents,
        nativeSelections: nativeSelections,
        unhandledEvents: unhandledEvents,
        messages: messages,
        setPortraitUnit: function (index) { lastPortraitUnit = index; },
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
function setPortrait(hud, index) { hud.setPortraitUnit(index); }
// 0.25 秒定时器现在同时包含钱包同步和商店开合轮询，按顺序单个取用不再可靠；
// 统一跑完当前这一批，语义仍是"一次刷新"。
function poll(hud) { hud.walletTimers.splice(0).forEach(function (callback) { callback(); }); }
function finishClose(hud) { hud.closeTimers.splice(0).forEach(function (callback) { callback(); }); }
function tick(hud) { poll(hud); finishClose(hud); }
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
// 实机日志确认：选中非小精灵单位时客户端不下发原版购买订单。打开原版商店期间必须
// 临时选中小精灵，关闭时还原；交付目标由面板目标与服务端保持，物品仍进英雄。
var shopHud = runHud();
shopHud.subscriptions.rpg_battle_state({ phase: "setup" });
shopHud.subscriptions.rpg_shop_state({
    rule_generation: 1, gold: 500, lineup_text: "npc_dota_hero_axe",
    owned_text: "npc_dota_hero_axe", hero_entity_indices: { npc_dota_hero_axe: 501 },
    commander_index: 502
});
shopHud.nativeSelections.length = 0;
shopHud.unhandledEvents.DOTAHUDShopOpened();
assert(shopHud.nativeSelections.length === 1 && shopHud.nativeSelections[0].index === 502,
    "opening the native shop must temporarily select the commander");
shopHud.unhandledEvents.DOTAHUDShopClosed();
assert(shopHud.nativeSelections.length === 1, "close event must not restore inside the native event stack");
finishClose(shopHud);
assert(shopHud.nativeSelections.length === 2 && shopHud.nativeSelections[1].index === 503,
    "closing the native shop must restore the previously selected unit");
shopHud.nativeSelections.length = 0;
shopHud.unhandledEvents.DOTAHUDShopOpened();
shopHud.unhandledEvents.DOTAHUDShopClosed();
finishClose(shopHud);
assert(shopHud.nativeSelections.length === 2 && shopHud.nativeSelections[0].index === 502
    && shopHud.nativeSelections[1].index === 503, "the shop selection swap must be repeatable");
// 已经选中小精灵时不做切换；战斗阶段一律不动选中单位。
setPortrait(shopHud, 502);
shopHud.nativeSelections.length = 0;
shopHud.unhandledEvents.DOTAHUDShopOpened();
shopHud.unhandledEvents.DOTAHUDShopClosed();
assert(shopHud.nativeSelections.length === 0, "an already selected commander must not be swapped");
shopHud.subscriptions.rpg_battle_state({ phase: "fight" });
setPortrait(shopHud, 503);
shopHud.nativeSelections.length = 0;
shopHud.unhandledEvents.DOTAHUDShopOpened();
assert(shopHud.nativeSelections.length === 0, "no selection swap outside preparation");
console.log("PASS native shop selection swap: open selects the commander, close restores the hero, setup only");

// 实机里 DOTAHUDShopOpened/DOTAHUDShopClosed 没有派发，主判定改成轮询引擎的 IsShopOpen。
var pollHud = runHud();
pollHud.subscriptions.rpg_battle_state({ phase: "setup" });
pollHud.subscriptions.rpg_shop_state({
    rule_generation: 1, gold: 500, lineup_text: "npc_dota_hero_axe",
    owned_text: "npc_dota_hero_axe", hero_entity_indices: { npc_dota_hero_axe: 501 },
    commander_index: 502
});
setPortrait(pollHud, 503);
var shopOpenNow = false;
pollHud.context.GameUI.IsShopOpen = function () { return shopOpenNow; };
pollHud.nativeSelections.length = 0;
tick(pollHud);
assert(pollHud.nativeSelections.length === 0, "a closed shop must not swap the selection");
shopOpenNow = true;
tick(pollHud);
assert(pollHud.nativeSelections.length === 1 && pollHud.nativeSelections[0].index === 502,
    "polling an open shop must select the commander");
shopOpenNow = false;
tick(pollHud);
assert(pollHud.nativeSelections.length === 2 && pollHud.nativeSelections[1].index === 503,
    "polling a closed shop must restore the hero");
setPortrait(pollHud, 502);
pollHud.nativeSelections.length = 0;
shopOpenNow = true;
tick(pollHud);
assert(pollHud.nativeSelections.length === 0, "an already selected commander is never re-swapped");
// 查询接口缺失时不做任何切换，也不能抛错。
var blindHud = runHud();
blindHud.subscriptions.rpg_battle_state({ phase: "setup" });
blindHud.subscriptions.rpg_shop_state({ rule_generation: 1, commander_index: 502 });
blindHud.nativeSelections.length = 0;
tick(blindHud);
assert(blindHud.nativeSelections.length === 0, "a missing shop query must not change the selection");
console.log("PASS native shop poll: IsShopOpen swap, restore, repeat and missing API");

// Valve's actual shop CSS hides the root with transform/opacity. Grid size can stay
// positive while closed, or zero on another tab while open. Only ShopOpen is relevant.
function mountShopState(h) {
    var shop = createPanel("shop");
    shop.paneltype = "DOTAHUDShop";
    shop.SetParent(h.nativeRoot);
    var main = createPanel("Main");
    main.SetParent(shop);
    var grid = createPanel("GridMainShop");
    grid.SetParent(main);
    return { shop: shop, grid: grid };
}
var gridHud = runHud();
gridHud.subscriptions.rpg_battle_state({ phase: "setup" });
gridHud.subscriptions.rpg_shop_state({
    rule_generation: 1, lineup_text: "npc_dota_hero_axe", owned_text: "npc_dota_hero_axe",
    hero_entity_indices: { npc_dota_hero_axe: 501 }, commander_index: 502
});
// First poll before Valve mounts the shop must recover on a later poll.
tick(gridHud);
assert(gridHud.messages.some(function (m) { return m.indexOf("GameUI=missing") >= 0; }),
    "diagnostics must not use eval, which Panorama disables");
var statePanel = mountShopState(gridHud);
setPortrait(gridHud, 503);
gridHud.nativeSelections.length = 0;
tick(gridHud);
assert(gridHud.nativeSelections.length === 0, "a closed root with a laid-out grid must not swap");
assert(gridHud.messages.some(function (m) { return m.indexOf("selection swap armed") >= 0; }),
    "late native HUD creation must recover from unavailable state");
// Reproduce unavailable APIs, without relying on them to observe the shop.
function unavailableShopApi() { throw new Error("native query unavailable"); }
gridHud.context.GameUI.IsShopOpen = unavailableShopApi;
gridHud.context.Game = { IsShopOpen: unavailableShopApi };
gridHud.context.Players.IsShopOpen = unavailableShopApi;
statePanel.shop.AddClass("ShopOpen");
statePanel.grid.actuallayoutwidth = 0;
statePanel.grid.actuallayoutheight = 0;
tick(gridHud);
assert(gridHud.nativeSelections.length === 1 && gridHud.nativeSelections[0].index === 502,
    "ShopOpen must select commander even with collapsed main tab and throwing APIs");
// Event + poll duplication must not erase the saved hero when commander is selected.
gridHud.unhandledEvents.DOTAHUDShopOpened();
tick(gridHud);
statePanel.shop.SetHasClass("ShopOpen", false);
statePanel.grid.actuallayoutwidth = 420;
statePanel.grid.actuallayoutheight = 300;
tick(gridHud);
assert(gridHud.nativeSelections.length === 2 && gridHud.nativeSelections[1].index === 503,
    "close restores the hero despite duplicate opens and unchanged positive grid size");
// The actual panel state wins over a stale API result in either direction.
gridHud.context.GameUI.IsShopOpen = function () { return false; };
statePanel.shop.AddClass("ShopOpen");
tick(gridHud);
assert(gridHud.nativeSelections[2].index === 502, "ShopOpen overrides stale API false");
setPortrait(gridHud, 501);
gridHud.sentEvents.length = 0;
tick(gridHud);
assert(gridHud.nativeSelections[3].index === 502,
    "selecting another hero while open must keep the shop usable and closable");
assert(gridHud.sentEvents.some(function (e) {
    return e.name === "rpg_native_purchase_target" && e.payload.unit_index === 501;
}), "the newly selected hero must be published as recipient before swapping to commander");
gridHud.context.GameUI.IsShopOpen = function () { return true; };
statePanel.shop.SetHasClass("ShopOpen", false);
tick(gridHud);
assert(gridHud.nativeSelections[4].index === 501, "closing restores the latest hero despite stale API true");
// A player selection made during close must survive restoration.
statePanel.shop.AddClass("ShopOpen");
tick(gridHud);
setPortrait(gridHud, 504);
var selectionCount = gridHud.nativeSelections.length;
statePanel.shop.SetHasClass("ShopOpen", false);
tick(gridHud);
assert(gridHud.nativeSelections.length === selectionCount, "closing cannot override a manual selection");
statePanel.shop.AddClass("ShopOpen");
tick(gridHud);
gridHud.subscriptions.rpg_battle_state({ phase: "fight" });
statePanel.shop.SetHasClass("ShopOpen", false);
gridHud.unhandledEvents.DOTAHUDShopClosed();
selectionCount = gridHud.nativeSelections.length;
gridHud.subscriptions.rpg_battle_state({ phase: "setup" });
tick(gridHud);
assert(gridHud.nativeSelections.length === selectionCount, "phase changes discard stale restoration");
statePanel.shop.AddClass("ShopOpen");
setPortrait(gridHud, 501);
tick(gridHud);
gridHud.subscriptions.rpg_shop_state({ rule_generation: 2, commander_index: 602 });
statePanel.shop.SetHasClass("ShopOpen", false);
setPortrait(gridHud, 602);
selectionCount = gridHud.nativeSelections.length;
tick(gridHud);
assert(gridHud.nativeSelections.length === selectionCount, "new runs cannot restore an old hero entity");
console.log("PASS native shop root: real ShopOpen class, API failures, repeat, reselection, restore and lifecycle");

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
// Exercise one button click with a native close transition still in flight. A selection
// during that transition reopens this simulated native shop, exposing the old race.
function closeFixture(suppressNativeEvents) {
    var h = runHud();
    h.subscriptions.rpg_battle_state({ phase: "setup" });
    h.subscriptions.rpg_shop_state({ rule_generation: 1, commander_index: 502 });
    var state = mountShopState(h);
    var controls = mountNativeShop(h);
    var dispatched = [];
    var closing = false;
    var select = h.context.GameUI.SelectUnit;
    h.context.GameUI.SelectUnit = function (index, additive) {
        if (closing) { state.shop.AddClass("ShopOpen"); }
        select(index, additive);
    };
    h.context.$.DispatchEvent = function (name) {
        dispatched.push(name);
        if (name === "DOTAShopHideShop") {
            closing = true;
            // Some event sources notify before changing the panel's state class.
            if (!suppressNativeEvents) { h.unhandledEvents.DOTAHUDShopClosed(); }
            state.shop.SetHasClass("ShopOpen", false);
        } else if (name === "DOTAHUDToggleShop") {
            state.shop.SetHasClass("ShopOpen", !state.shop.BHasClass("ShopOpen"));
        }
    };
    poll(h);
    controls.button.events.onactivate();
    poll(h);
    assert(dispatched[0] === "DOTAHUDToggleShop" && h.context.Players.GetLocalPlayerPortraitUnit() === 502,
        "closed native button retains Valve's open action and selects commander");
    return { h: h, state: state, controls: controls, dispatched: dispatched,
        endAnimation: function () { closing = false; } };
}
var once = closeFixture();
once.controls.button.events.onactivate();
assert(once.dispatched.join(",") === "DOTAHUDToggleShop,DOTAShopHideShop",
    "one close click must issue exactly one explicit native hide");
poll(once.h);
assert(once.h.nativeSelections.length === 1 && !once.state.shop.BHasClass("ShopOpen"),
    "close polling must not restore selection during the native transition");
once.endAnimation();
finishClose(once.h);
assert(once.h.nativeSelections.length === 2 && once.h.nativeSelections[1].index === 503
    && !once.state.shop.BHasClass("ShopOpen"), "animation finishes with shop closed and original hero restored");
poll(once.h); finishClose(once.h);
assert(once.h.nativeSelections.length === 2, "duplicate close observations cannot restore twice");
once.h.unhandledEvents.DOTAHUDShopOpened();
assert(once.h.nativeSelections.length === 2, "late opened event cannot override a closed root");
["manual", "reopen", "phase", "generation"].forEach(function (scenario) {
    var f = closeFixture();
    f.controls.button.events.onactivate();
    poll(f.h);
    f.endAnimation();
    var count = f.h.nativeSelections.length;
    if (scenario === "manual") { setPortrait(f.h, 504); }
    if (scenario === "reopen") {
        f.controls.button.events.onactivate();
        // No intervening poll: the delayed callback must re-read the actual root.
    }
    if (scenario === "phase") {
        f.h.subscriptions.rpg_battle_state({ phase: "fight" });
        f.h.subscriptions.rpg_battle_state({ phase: "setup" });
    }
    if (scenario === "generation") {
        f.h.subscriptions.rpg_shop_state({ rule_generation: 2, commander_index: 502 });
    }
    finishClose(f.h);
    assert(f.h.nativeSelections.length === count, "pending restore respects " + scenario);
    if (scenario === "reopen") {
        poll(f.h);
        f.controls.button.events.onactivate(); poll(f.h);
        f.endAnimation(); finishClose(f.h);
        assert(f.h.nativeSelections.length === count + 1 && f.h.nativeSelections[count].index === 503,
            "reopening preserves the recipient for the next completed close");
    }
});
// Live builds may emit no shop events. Reopen and close between polls must not reuse
// the first close's timer during a second native animation.
var rapid = closeFixture(true);
rapid.controls.button.events.onactivate();
poll(rapid.h);
rapid.endAnimation();
rapid.controls.button.events.onactivate();
rapid.controls.button.events.onactivate();
finishClose(rapid.h);
assert(rapid.h.nativeSelections.length === 1 && !rapid.state.shop.BHasClass("ShopOpen"),
    "no-event rapid reopen/close invalidates the first close timer");
poll(rapid.h);
rapid.endAnimation();
finishClose(rapid.h);
assert(rapid.h.nativeSelections.length === 2 && rapid.h.nativeSelections[1].index === 503,
    "second no-event close gets its own delay and restores the saved hero");
// A new HUD button gets wired, and its tooltip/right-click callbacks survive.
var rebuilt = closeFixture();
rebuilt.h.nativeRoot.children = rebuilt.h.nativeRoot.children.filter(function (p) { return p !== rebuilt.controls.controls; });
var replacement = mountNativeShop(rebuilt.h);
var rightClicks = 0;
replacement.button.SetPanelEvent("oncontextmenu", function () { rightClicks++; });
poll(rebuilt.h);
replacement.button.events.oncontextmenu();
replacement.button.events.onactivate();
assert(rightClicks === 1 && rebuilt.dispatched[1] === "DOTAShopHideShop", "rebuilt button closes once and retains other events");
rebuilt.h.subscriptions.rpg_battle_state({ phase: "fight" });
replacement.button.events.onactivate();
assert(rebuilt.dispatched[2] === "DOTAHUDToggleShop", "outside setup use Valve's original toggle action");
console.log("PASS native shop single close: explicit hide, deferred restore, stale events, reopen, lifecycle and rebuilt button");

var walletHud = runHud();
walletHud.subscriptions.rpg_shop_state({gold: 360}); // 500 - a 140-gold purchase
var nativeShop = mountNativeShop(walletHud); // Valve creates the HUD after the broadcast
tick(walletHud);
assert(nativeShop.label.text === "360" && panel(walletHud, "WalletBalance").text.endsWith(" 360"), "late native shop receives the latest top HUD balance");
[220, 0, 70, 1045].forEach(function (gold) {
    walletHud.subscriptions.rpg_shop_state({gold: gold});
    assert(nativeShop.label.text === String(gold) && panel(walletHud, "WalletBalance").text.endsWith(" " + gold), "purchase, zero balance, sale refund and reward update both displays: " + gold);
});
nativeShop.label.text = "500"; // simulate a native refresh restoring its stale binding
tick(walletHud);
assert(nativeShop.label.text === "1045", "native refresh cannot leave the old balance visible");
nativeShop.button.events.onactivate();
assert(nativeShop.clicks() === 1 && nativeShop.label.BHasClass("ShopButtonValueLabel"), "native shop click handler and label style survive synchronization");
walletHud.nativeRoot.children = walletHud.nativeRoot.children.filter(function (p) { return p !== nativeShop.controls; });
nativeShop = mountNativeShop(walletHud); // portrait/HUD replacement, no new server message
tick(walletHud);
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
