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
    var selectionTimers = [];
    panorama.Schedule = function (delay, callback) {
        if (delay === 3) { timers.push(callback); }
        else if (delay === 0.25) { walletTimers.push(callback); }
        else if (delay === 0.15) { closeTimers.push(callback); }
        else if (delay === 0.2) { selectionTimers.push(callback); }
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
        selectionTimers: selectionTimers,
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
function finishSelection(hud) { hud.selectionTimers.splice(0).forEach(function (callback) { callback(); }); }
function tick(hud) { poll(hud); finishSelection(hud); finishClose(hud); }
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
finishSelection(shopHud);
shopHud.unhandledEvents.DOTAHUDShopClosed();
assert(shopHud.nativeSelections.length === 1, "close event must not restore inside the native event stack");
finishClose(shopHud);
assert(shopHud.nativeSelections.length === 2 && shopHud.nativeSelections[1].index === 503,
    "closing the native shop must restore the previously selected unit");
shopHud.nativeSelections.length = 0;
shopHud.unhandledEvents.DOTAHUDShopOpened();
finishSelection(shopHud);
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

// UI59 passed the older fixtures because SelectUnit never closed their native shop.
// Model the user's observed sequence, including reentrant and next-frame notifications.
function selectionCloseFixture(eventOrder, reopenMode) {
    var h = runHud();
    h.subscriptions.rpg_battle_state({ phase: "setup" });
    h.subscriptions.rpg_shop_state({ rule_generation: 1, commander_index: 502 });
    var state = mountShopState(h);
    var select = h.context.GameUI.SelectUnit;
    var delayedSelection = null;
    var requests = 0;
    function close() {
        if (eventOrder === "before") { h.unhandledEvents.DOTAHUDShopClosed(); }
        state.shop.SetHasClass("ShopOpen", false);
        if (eventOrder === "after") { h.unhandledEvents.DOTAHUDShopClosed(); }
    }
    h.context.GameUI.SelectUnit = function (index, additive) {
        if (index !== 502) { select(index, additive); return; }
        var hero = h.context.Players.GetLocalPlayerPortraitUnit();
        assert(h.sentEvents.some(function (e) {
            return e.name === "rpg_native_purchase_target" && e.payload.unit_index === hero;
        }), "publish delivery hero before automatic selection");
        function apply() {
            select(index, additive);
            h.subscriptions.dota_player_update_selected_unit({});
            close();
        }
        if (eventOrder === "deferred" || eventOrder === "late" || eventOrder === "refused") {
            delayedSelection = apply;
        } else { apply(); }
    };
    h.context.$.DispatchEvent = function (name) {
        assert(name === "DOTAHUDToggleShop", "only the installed native shop event is supported");
        assert(!state.shop.BHasClass("ShopOpen"), "never toggle a shop that is already open");
        assert(h.context.Players.GetLocalPlayerPortraitUnit() === 502, "reopen only after commander selection");
        requests++;
        if (reopenMode === "throw") { throw new Error("native event unavailable"); }
        if (reopenMode === "noop") { return; }
        state.shop.AddClass("ShopOpen");
        h.unhandledEvents.DOTAHUDShopOpened();
    };
    state.shop.AddClass("ShopOpen");
    poll(h);
    if (eventOrder === "late") {
        finishSelection(h);
        assert(h.selectionTimers.length === 1 && requests === 0,
            "original portrait at first check must wait for delayed selection");
    }
    if (eventOrder === "refused") {
        for (var check = 0; check < 5; check++) { finishSelection(h); }
        assert(h.selectionTimers.length === 0 && requests === 0,
            "rejected selection must stop waiting after a bounded number of checks");
        close(); tick(h);
        assert(h.nativeSelections.length === 0, "rejected selection must leave original hero alone");
        return;
    }
    if (delayedSelection) { delayedSelection(); }
    poll(h); finishClose(h);
    assert(h.nativeSelections.length === 1 && h.nativeSelections[0].index === 502,
        "selection-induced close must not bounce back to hero before settlement");
    return { h: h, state: state, close: close, requests: function () { return requests; } };
}
selectionCloseFixture("refused");
["before", "after", "none", "deferred", "late"].forEach(function (order) {
    var f = selectionCloseFixture(order);
    finishSelection(f.h); tick(f.h);
    assert(f.state.shop.BHasClass("ShopOpen") && f.requests() === 1
        && f.h.nativeSelections.length === 1, "selection-induced close recovers once: " + order);
    f.h.subscriptions.rpg_shop_state({ rule_generation: 1, commander_index: 502, gold: 360 });
    tick(f.h);
    assert(f.state.shop.BHasClass("ShopOpen") && f.requests() === 1,
        "purchase updates keep recovered shop open without another request");
    f.close(); tick(f.h); tick(f.h);
    assert(!f.state.shop.BHasClass("ShopOpen") && f.requests() === 1
        && f.h.nativeSelections.length === 2 && f.h.nativeSelections[1].index === 503,
        "one later user close restores original hero without automatic reopening");
});
["manual", "phase", "generation", "already-open"].forEach(function (scenario) {
    var f = selectionCloseFixture("after");
    if (scenario === "manual") { setPortrait(f.h, 504); }
    if (scenario === "phase") {
        f.h.subscriptions.rpg_battle_state({ phase: "fight" });
        f.h.subscriptions.rpg_battle_state({ phase: "setup" });
    }
    if (scenario === "generation") {
        f.h.subscriptions.rpg_shop_state({ rule_generation: 2, commander_index: 502 });
    }
    if (scenario === "already-open") { f.state.shop.AddClass("ShopOpen"); }
    finishSelection(f.h); tick(f.h);
    assert(f.requests() === 0 && f.h.nativeSelections.length === 1,
        "selection recovery cancels or skips safely: " + scenario);
});
["throw", "noop"].forEach(function (mode) {
    var f = selectionCloseFixture("after", mode);
    finishSelection(f.h); tick(f.h); tick(f.h);
    assert(f.requests() === 1 && !f.state.shop.BHasClass("ShopOpen")
        && f.h.nativeSelections.length === 2 && f.h.nativeSelections[1].index === 503,
        "failed recovery must stop after one request and allow restoration: " + mode);
});
var reselection = selectionCloseFixture("after");
finishSelection(reselection.h); tick(reselection.h);
setPortrait(reselection.h, 501);
tick(reselection.h);
assert(reselection.requests() === 2 && reselection.state.shop.BHasClass("ShopOpen"),
    "a new hero selected while shopping gets its own bounded selection recovery");
reselection.close(); tick(reselection.h);
assert(reselection.h.nativeSelections[reselection.h.nativeSelections.length - 1].index === 501,
    "reselection preserves the newest recipient for restoration");
console.log("PASS selection-induced shop close: synchronous/deferred, recipient, bounded recovery, user close and cancellation");

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

// Inventory rows contain two fixed cells, including an odd last item. Scrollbar
// width no longer decides whether a 50%-wide card wraps onto a separate line.
{
    const equipment = runHud();
    const axe = "npc_dota_hero_axe", lion = "npc_dota_hero_lion";
    const state = {rule_generation:1, gold:5000, lineup_text:axe, owned_text:axe+";"+lion,
        hero_entity_indices:{[axe]:501,[lion]:503}, commander_index:502,
        stock_text:"item_branches|101;item_blink|102;item_blade_mail|103",
        equipped_text:axe+":item_branches|201|0,item_tpscroll|999|15,item_blink|202|1,item_blade_mail|203|2;"+lion+":",
        stash_free_slots:9, shard_cost:1400, shard_heroes_text:""};
    equipment.subscriptions.rpg_battle_state({phase:"setup"});
    equipment.subscriptions.rpg_shop_state(state);
    for (const id of ["ItemStockList","ItemEquippedList"]) {
        const pairs = panel(equipment,id).children;
        assert(pairs.length===2 && pairs.every(p=>p.BHasClass("ItemInventoryPair") && p.children.length===2),
            "three displayed items occupy two explicit two-column rows: "+id);
        assert(pairs[0].children.every(cell=>cell.children.length===1) && pairs[1].children[0].children.length===1
            && pairs[1].children[1].children.length===0,"odd inventory keeps its empty second cell");
    }
    click(equipment,"Equip1");
    const transfer = equipment.sentEvents.filter(e=>e.name==="rpg_item_equip").at(-1);
    assert(transfer.payload.hero===axe && transfer.payload.item_index==="102","nested cards retain the exact item transfer target");
    assert(panel(equipment,"ShardBuyButton").enabled,"selected hero can purchase Shard with enough gold");
    click(equipment,"ShardBuyButton"); click(equipment,"ShardBuyButton");
    let buys = equipment.sentEvents.filter(e=>e.name==="rpg_shard_buy");
    assert(buys.length===1 && buys[0].payload.hero===axe && !('price' in buys[0].payload),"explicit selected-hero purchase sends no client price and guards double click");
    equipment.subscriptions.rpg_shop_state(Object.assign({},state,{gold:3600,shard_heroes_text:axe}));
    assert(!panel(equipment,"ShardBuyButton").enabled && panel(equipment,"ShardBuyButton").children[0].text==="#dota2_rpg_shard_owned", "authoritative upgrade disables duplicate purchase");
    click(equipment,"ItemTarget_"+lion);
    assert(panel(equipment,"ShardBuyButton").enabled,"a bench hero has its own upgrade state");
    click(equipment,"ShardBuyButton");
    buys = equipment.sentEvents.filter(e=>e.name==="rpg_shard_buy");
    assert(buys.length===2 && buys[1].payload.hero===lion,"bench selection purchases for that hero, never commander");
    equipment.subscriptions.rpg_shop_state(Object.assign({},state,{gold:1399,shard_heroes_text:axe}));
    assert(!panel(equipment,"ShardBuyButton").enabled,"unaffordable upgrade is disabled");
    equipment.subscriptions.rpg_battle_state({phase:"fight"}); click(equipment,"ShardBuyButton");
    assert(equipment.sentEvents.filter(e=>e.name==="rpg_shard_buy").length===2,"no combat purchase");
}
console.log("PASS explicit two-column inventory and selected hero Shard purchase");

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
// Keep native default activation separate from a script callback. The previous fixture
// modeled ONLY the replacement callback, hiding UI58's possible second shop action.
// Both activation orders are exercised; this is a regression model, not engine tracing.
function closeFixture(suppressNativeEvents, callbackFirst) {
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
    function activate(button) {
        if (callbackFirst) { button.events.onactivate(); }
        var wasOpen = state.shop.BHasClass("ShopOpen");
        closing = wasOpen;
        if (wasOpen && !suppressNativeEvents) { h.unhandledEvents.DOTAHUDShopClosed(); }
        state.shop.SetHasClass("ShopOpen", !wasOpen);
        if (!callbackFirst) { button.events.onactivate(); }
    }
    var originalActivate = controls.button.events.onactivate;
    poll(h);
    activate(controls.button);
    assert(state.shop.BHasClass("ShopOpen"), "one native opening click must stay open after activation");
    poll(h); finishSelection(h); finishClose(h); poll(h);
    assert(state.shop.BHasClass("ShopOpen") && h.context.Players.GetLocalPlayerPortraitUnit() === 502,
        "one native opening click must stay open through selection swap and later polls");
    assert(controls.button.events.onactivate === originalActivate && dispatched.length === 0,
        "addon must preserve original activation and never dispatch a second shop action");
    return { h: h, state: state, controls: controls, dispatched: dispatched,
        activate: activate, click: function () { activate(controls.button); },
        endAnimation: function () { closing = false; } };
}
var once = closeFixture();
once.h.subscriptions.rpg_shop_state({ rule_generation: 1, commander_index: 502, gold: 360 });
poll(once.h); finishClose(once.h);
assert(once.state.shop.BHasClass("ShopOpen") && once.controls.label.text === "360",
    "purchase wallet update must leave the shop open");
once.click();
assert(once.controls.clicks() === 2 && once.dispatched.length === 0,
    "opening and closing each use exactly the native activation without addon shop dispatch");
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
    f.click();
    poll(f.h);
    f.endAnimation();
    var count = f.h.nativeSelections.length;
    if (scenario === "manual") { setPortrait(f.h, 504); }
    if (scenario === "reopen") {
        f.click();
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
        f.click(); poll(f.h);
        f.endAnimation(); finishClose(f.h);
        assert(f.h.nativeSelections.length === count + 1 && f.h.nativeSelections[count].index === 503,
            "reopening preserves the recipient for the next completed close");
    }
});
// Cover live builds with no opened/closed events, and either default/callback order.
[false, true].forEach(function (callbackFirst) {
    var nativeOnly = closeFixture(true, callbackFirst);
    nativeOnly.click(); poll(nativeOnly.h);
    assert(nativeOnly.h.nativeSelections.length === 1, "no-event close still defers restoration");
    nativeOnly.endAnimation(); finishClose(nativeOnly.h);
    assert(nativeOnly.h.nativeSelections[1].index === 503 && nativeOnly.dispatched.length === 0,
        "no-event close restores without any scripted shop action");
});
// Native HUD replacement must also leave activation, tooltip and right-click untouched.
var rebuilt = closeFixture();
rebuilt.h.nativeRoot.children = rebuilt.h.nativeRoot.children.filter(function (p) { return p !== rebuilt.controls.controls; });
var replacement = mountNativeShop(rebuilt.h);
var rightClicks = 0;
replacement.button.SetPanelEvent("oncontextmenu", function () { rightClicks++; });
var replacementActivate = replacement.button.events.onactivate;
poll(rebuilt.h);
replacement.button.events.oncontextmenu();
rebuilt.activate(replacement.button);
assert(rightClicks === 1 && replacement.clicks() === 1 && rebuilt.dispatched.length === 0
    && replacement.button.events.onactivate === replacementActivate,
    "rebuilt native button retains activation and other events");
rebuilt.endAnimation();
rebuilt.h.subscriptions.rpg_battle_state({ phase: "fight" });
rebuilt.activate(replacement.button);
assert(replacement.clicks() === 2 && rebuilt.state.shop.BHasClass("ShopOpen"),
    "native activation also remains untouched outside setup");
console.log("PASS native shop activation preserved: stays open, purchase update, deferred restore, events, lifecycle and HUD rebuild");

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

var ranked = runHud();
ranked.subscriptions.rpg_battle_state({phase:"result",winner:"radiant",run_complete:1,replay_available:1,owner_player_id:0,settlement_generation:40});
var summary = {winner:"radiant",run_complete:1,cleared:1,settlement_generation:40,status:"pending",score:1456000,
    core_score:420000,time_bonus_score:36000,clear_bonus_score:1000000,remaining_hearts:5,stage_count:30,total_stages:30,remaining_time_ms:3600000};
ranked.subscriptions.rpg_settlement(summary);
assert(visible(ranked,"RunLeaderboard") && panel(ranked,"RunScoreValue").text === "1456000", "terminal summary displays authoritative score");
assert(ranked.timers.length === 0 && panel(ranked,"RunRankStatus").text === "#dota2_rpg_rank_pending", "terminal does not auto-hide while awaiting network");
var accepted = Object.assign({}, summary, {status:"success",score_rank:1,score_total:10,score_global_record:1,speedrun_rank:3,speedrun_total:8,speedrun_personal_record:1});
ranked.subscriptions.rpg_leaderboard_result(accepted);
assert(visible(ranked,"RunRecordMessage") && panel(ranked,"RunRecordMessage").text.includes("rank_global_record") && panel(ranked,"RunRecordMessage").text.includes("rank_personal_record"), "global and personal records congratulate only after accepted reply");
ranked.subscriptions.rpg_leaderboard_result(summary);
assert(panel(ranked,"RunRankStatus").text === "#dota2_rpg_rank_success", "late pending event does not downgrade successful result");
click(ranked,"LootPopupConfirm");
assert(visible(ranked,"RunLeaderboard") && visible(ranked,"ReplayRunButton"), "closing loot preserves terminal ranks and replay");
ranked.subscriptions.rpg_battle_state({phase:"setup",settlement_generation:41});
ranked.subscriptions.rpg_leaderboard_result(accepted);
assert(!visible(ranked,"RunLeaderboard") && !visible(ranked,"BattleResult"), "fresh run rejects previous HTTP result");
var reconnected = runHud();
reconnected.subscriptions.rpg_battle_state({phase:"result",run_complete:1,winner:"radiant",settlement_generation:40});
reconnected.subscriptions.rpg_leaderboard_result(accepted);
assert(visible(reconnected,"RunLeaderboard"), "owner reconnect restores summary from cached result without replaying rewards");
reconnected.subscriptions.rpg_battle_state({phase:"result",run_complete:1,winner:"dire",settlement_generation:42});
reconnected.subscriptions.rpg_leaderboard_result(Object.assign({}, summary, {settlement_generation:42,cleared:0,status:"error"}));
assert(panel(reconnected,"RunSpeedrunRank").text.includes("rank_clear_only") && !visible(reconnected,"RunRecordMessage"), "failed runs stay off speedrun and network errors cannot invent records");
console.log("PASS terminal leaderboard UI: persistence, authoritative response, records, late events, reconnect and failure");

var localHost = runHud();
assert(!localHost.subscriptions.rpg_server_pairing, "automatic uploads have no pairing or authorization interaction");
var initialRequests = localHost.sentEvents.filter(function(e) { return e.name === "rpg_request_battle_state"; }).length;
localHost.subscriptions.rpg_battle_state({phase:"setup",ready:0,owner_player_id:-1});
localHost.subscriptions.rpg_battle_state({phase:"setup",ready:1,owner_player_id:0});
localHost.subscriptions.rpg_battle_state({phase:"setup",ready:1,owner_player_id:0});
assert(localHost.sentEvents.filter(function(e) { return e.name === "rpg_request_battle_state"; }).length === initialRequests + 1, "late owner assignment requests cached state once without a broadcast loop");
console.log("PASS automatic local-host uploads: no pairing prompt and owner state recovery");

// Exercise the actual HUD script and XML with the flat accepted-snapshot contract.
function boardSnapshot(data, board, ranks, ownRank, values) {
    data[board + "_list_available"] = 1;
    data[board + "_list_total"] = ranks.length ? 40 : 0;
    data[board + "_list_player_rank"] = ownRank;
    data[board + "_list_count"] = ranks.length;
    ranks.forEach(function (rank, i) {
        var prefix = board + "_row_" + (i + 1) + "_";
        data[prefix + "rank"] = rank;
        data[prefix + "name"] = rank === ownRank ? '<b>你 & "player"</b>' : "玩家 " + rank;
        data[prefix + "value"] = values ? values[i] : 100000 - rank;
        data[prefix + "is_self"] = rank === ownRank ? 1 : 0;
    });
    return data;
}
function tableRows(hud) {
    return panel(hud, "RunRankRows").children.filter(function (row) { return row.BHasClass("RankTableRow"); });
}
var tables = runHud();
tables.subscriptions.rpg_battle_state({phase:"result",settlement_generation:60});
var details = boardSnapshot(Object.assign({}, accepted, {settlement_generation:60}), "score", [1,2,3,4,5,18,19,20,21,22], 20);
boardSnapshot(details, "speedrun", [1,2,3,4,5,6,7], 5, [61002,61001,60000,59999,0,0,0]);
tables.subscriptions.rpg_leaderboard_result(details);
assert(tableRows(tables).map(function(row) { return row.children[0].text; }).join(",") === "1,2,3,4,5,18,19,20,21,22", "top5 and distant self neighbors retain real server ranks");
assert(panel(tables,"RunRankRows").children.filter(function(row) { return row.BHasClass("RankGap") && row.text === "…"; }).length === 1, "one ellipsis marks skipped ranks");
[1,2,3].forEach(function(rank) { assert(tableRows(tables)[rank-1].BHasClass("RankPodium" + rank), "podium rank styled " + rank); });
var selfRow = tableRows(tables)[7];
assert(selfRow.BHasClass("RankSelf") && selfRow.children[2].text === "#dota2_rpg_rank_you", "self best has highlight and localized badge");
assert(selfRow.children[1].text === '<b>你 & "player"</b>' && selfRow.children[1].html === false, "UTF8 player markup remains literal");
assert(cssSource.includes("text-overflow: ellipsis") && layoutSource.includes("#dota2_rpg_rank_snapshot"), "compact names and acceptance-snapshot explanation exist");
selfRow.children[1].events.onmouseover();
assert(visible(tables,"RunRankNameTooltip") && panel(tables,"RunRankNameTooltip").text === selfRow.children[1].text && panel(tables,"RunRankNameTooltip").html === false, "full name tooltip is literal without HTML dispatch");
selfRow.children[1].events.onmouseout();
assert(!visible(tables,"RunRankNameTooltip"), "full name tooltip hides on mouseout");
var eventsBeforeTabs = tables.sentEvents.length;
click(tables,"RunSpeedrunTab");
assert(tableRows(tables).length === 7 && panel(tables,"RunRankRows").children.length === 7, "overlapping server union renders once per row without gap");
assert(tableRows(tables)[0].children[3].text === "01:01.002" && tableRows(tables)[1].children[3].text === "01:01.001", "milliseconds distinguish close times");
assert(tableRows(tables)[4].children[3].text === "00:00.000", "zero remaining time is a valid displayed value");
assert(panel(tables,"RunSpeedrunTab").BHasClass("RankTabSelected") && !panel(tables,"RunScoreTab").BHasClass("RankTabSelected"), "only one selected board");
tables.subscriptions.rpg_leaderboard_result(details);
assert(tableRows(tables)[0].children[3].text === "01:01.002", "accepted refresh preserves selected tab");
click(tables,"RunScoreTab");
assert(tableRows(tables).length === 10 && tables.sentEvents.length === eventsBeforeTabs, "tabs reuse snapshot without server requests");
var restoredTables = runHud();
restoredTables.subscriptions.rpg_battle_state({phase:"result",settlement_generation:60});
restoredTables.subscriptions.rpg_leaderboard_result(details);
click(restoredTables,"RunSpeedrunTab");
assert(tableRows(restoredTables).length === 7, "reconnected snapshot supports both tabs");
click(tables,"RunSpeedrunTab");
tables.subscriptions.rpg_battle_state({phase:"setup",settlement_generation:61});
assert(!visible(tables,"RunLeaderboard") && tableRows(tables).length === 0, "setup hides and clears table");
tables.subscriptions.rpg_leaderboard_result(details);
assert(tableRows(tables).length === 0, "old accepted snapshot cannot restore rows after reset");
tables.subscriptions.rpg_battle_state({phase:"result",settlement_generation:62});
var failedHistory = Object.assign({}, details, {settlement_generation:62,cleared:0,score_global_record:0,score_first_entry:0,score_personal_record:0});
tables.subscriptions.rpg_leaderboard_result(failedHistory);
assert(panel(tables,"RunScoreTab").BHasClass("RankTabSelected"), "new terminal defaults to score");
assert(panel(tables,"RunSpeedrunRank").text.includes("rank_position") && panel(tables,"RunSpeedrunRank").text.includes("rank_current_not_qualified"), "failed run preserves accepted historical speed rank");
assert(!visible(tables,"RunRecordMessage"), "failed speedrun does not congratulate even with record flag");
click(tables,"RunSpeedrunTab");
assert(tableRows(tables).length === 7 && panel(tables,"RunRankTableStatus").text.includes("rank_current_not_qualified"), "historical table labels current failed run");
var noHistory = boardSnapshot(Object.assign({}, failedHistory), "speedrun", [1,2,3], 0);
tables.subscriptions.rpg_leaderboard_result(noHistory);
assert(panel(tables,"RunRankTableStatus").text.includes("rank_not_ranked") && panel(tables,"RunSpeedrunRank").text.includes("rank_clear_only"), "failed player without previous clear stays unranked");
var empty = boardSnapshot(Object.assign({}, noHistory), "speedrun", [], 0);
tables.subscriptions.rpg_leaderboard_result(empty);
assert(!tableRows(tables).length && panel(tables,"RunRankTableStatus").text.includes("rank_empty"), "empty board clears prior rows");
tables.subscriptions.rpg_leaderboard_result(Object.assign({}, failedHistory, {speedrun_list_available:0}));
assert(!tableRows(tables).length && panel(tables,"RunRankTableStatus").text === "#dota2_rpg_rank_detail_unavailable", "unavailable details cannot expose stale payload rows");
["pending","error","disabled","ineligible"].forEach(function(status, i) {
    var generation = 63 + i;
    tables.subscriptions.rpg_battle_state({phase:"result",settlement_generation:generation});
    tables.subscriptions.rpg_leaderboard_result(Object.assign({}, details, {settlement_generation:generation,status:status}));
    assert(!tableRows(tables).length && panel(tables,"RunRankTableStatus").text === "#dota2_rpg_rank_" + status, "no stale rows for " + status);
    assert(!visible(tables,"RunRecordMessage"), "no invented records for " + status);
});
console.log("PASS leaderboard snapshot tables: gaps, union, tabs, literal names, milliseconds, historical rank, reconnect and reset");
