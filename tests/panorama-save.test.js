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

function createPanel(id) {
    var classes = {};
    return {
        id: id || "",
        text: "",
        enabled: true,
        AddClass: function (name) { classes[name] = true; },
        SetHasClass: function (name, enabled) { classes[name] = Boolean(enabled); },
        BHasClass: function (name) { return Boolean(classes[name]); },
        events: {},
        SetPanelEvent: function (eventName, callback) { this.events[eventName] = callback; },
        BLoadLayoutSnippet: function () {},
        FindChildTraverse: function (childId) { return createPanel(childId); },
        GetChildCount: function () { return 0; },
        GetChild: function () { return createPanel(""); },
        GetAttributeString: function (_, fallback) { return fallback; },
        RemoveAndDeleteChildren: function () {},
        SetParent: function (parent) { this.parent = parent; },
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
    var localStorageCalls = 0;

    // Unknown IDs return null as they do in Panorama; never invent missing live controls.
    for (var match of layoutSource.matchAll(/\bid="([^"]+)"/g)) {
        panels["#" + match[1]] = createPanel(match[1]);
    }
    function panorama(selector) {
        return panels[selector] || null;
    }
    panorama.CreatePanel = function (_, parent, id) {
        var panel = createPanel(id || "");
        panel.parent = parent;
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
        GameUI: { CustomUIConfig: function () { return customConfig; } },
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
        panels: panels,
        createdPanels: createdPanels,
        sentEvents: sentEvents,
        subscriptions: subscriptions,
        getLocalStorageCalls: function () { return localStorageCalls; }
    };
}

function assert(condition, message) {
    if (!condition) {
        throw new Error(message);
    }
}

var ruleSyncContext = {
    Date: Date,
    GameEvents: {
        SendCustomGameEventToServer: function () {}
    }
};
vm.runInNewContext(ruleSyncSource, ruleSyncContext, { filename: ruleSyncPath });
var firstHeroRule = ruleSyncContext.RpgRuleSync.serialize({
    heroIndex: 0,
    heroName: "npc_dota_hero_axe",
    slot: 1,
    actionId: "ability_1",
    actionName: "axe_berserkers_call",
    rule: { action: "ability_1", condition: "always", target: "enemy_distance_nearest" }
});
assert(firstHeroRule.hero_index === 0, "rule sync must not drop the first hero entity index");

var hud = runHud();
assert(hud.getLocalStorageCalls() === 0, "no-save design must not touch LocalStorage");
assert(hud.sentEvents.every(function (e) { return e.name !== "rpg_save_sync"; }),
    "no-save design must not send save sync events");

// 服务端会先推送英雄动作详情，再推送购买后的阵容；图标必须能在阵容刷新后显示。
hud.subscriptions.rpg_hero_slots({
    slot_key: "radiant_1",
    hero_name: "npc_dota_hero_axe",
    hero_index: 501,
    actions_text: "ability_1;ability_2;ultimate;attack",
    details_text: "axe_berserkers_call;axe_battle_hunger;axe_culling_blade;attack"
});
hud.subscriptions.rpg_hero_slots({
    slot_key: "dire_1",
    hero_name: "npc_dota_hero_lion",
    hero_index: 502,
    actions_text: "ability_1;attack",
    details_text: "lion_impale;attack"
});

function created(hud, id) {
    return hud.createdPanels.filter(function (panel) { return panel.id === id; }).slice(-1)[0];
}
function visibleRules(hud, side) {
    return hud.createdPanels.filter(function (panel) {
        return panel.classes.RuleRow && panel.id.indexOf(side) === 0 && !panel.BHasClass("Hidden");
    });
}
function chooseAction(hud, side, row, action) {
    created(hud, side + "ActionSelect" + row).events.onactivate();
    var option = created(hud, "ActionOpt_" + side + row + "_" + action);
    assert(option && option.events.onactivate, "selected hero action must be available on every authored row");
    option.events.onactivate();
}

["Radiant", "Dire"].forEach(function (side) {
    assert(visibleRules(hud, side).length === 1, side + " must have one default rule");
    assert(hud.createdPanels.filter(function (p) { return p.classes.RuleRow && p.id.indexOf(side) === 0; }).length === 1,
        side + " must not preallocate fixed rule rows");
    var defaults = hud.sentEvents.filter(function (e) {
        return e.name === "rpg_update_rule" && e.payload.hero_index === (side === "Radiant" ? 501 : 502)
            && e.payload.enabled === 1;
    });
    assert(defaults.length > 0 && defaults.every(function (e) {
        return e.payload.slot === 1 && e.payload.action_kind === "attack"
            && e.payload.target_team === "enemy" && e.payload.target_priority_1_type === "nearest"
            && e.payload.approach === "range_only";
    }), side + " default must serialize as attack/enemy/nearest/range_only");
    assert(hud.panels["#" + side + "RulesScrollRail"].BHasClass("Hidden"), "single row has no empty scrolling space");
    assert(hud.panels["#" + side + "CollapseLabel"].text === "<", "expanded arrow must be <");
    hud.panels["#" + side + "CollapseButton"].events.onactivate();
    assert(hud.panels["#" + side + "Editor"].BHasClass("RpgActionPanelCollapsed"), "live editor must collapse");
    assert(hud.panels["#" + side + "CollapseLabel"].text === ">", "collapsed arrow must be >");
    hud.panels["#" + side + "CollapseButton"].events.onactivate();
    assert(!hud.panels["#" + side + "Editor"].BHasClass("RpgActionPanelCollapsed"), "live editor must re-expand");
    assert(hud.panels["#" + side + "CollapseLabel"].text === "<", "re-expanded arrow must be <");
});
assert(hud.panels["#ShopPanel"].BHasClass("RpgTransparentHeroShop"), "live shop must receive transparent class");

created(hud, "RadiantAddRule0").events.onactivate();
assert(visibleRules(hud, "Radiant").length === 2, "Add must create exactly one row");
chooseAction(hud, "Radiant", 1, "ability_2");
hud.subscriptions.rpg_hero_slots({
    slot_key: "radiant_1", hero_name: "npc_dota_hero_axe", hero_index: 501,
    actions_text: "ability_1;ability_2;ultimate;item_1;item_2;attack",
    details_text: "axe_berserkers_call;axe_battle_hunger;axe_culling_blade;item_blink;item_force_staff;attack"
});
assert(visibleRules(hud, "Radiant").length === 2, "active skills/items refresh must preserve N authored rules without padding");
assert(created(hud, "RadiantActionAbility1").abilityname === "axe_battle_hunger", "authored action survives slot refresh");
created(hud, "RadiantAddRule0").events.onactivate();
assert(visibleRules(hud, "Radiant").length === 3, "a second Add creates the third rule");
assert(!hud.panels["#RadiantRulesScrollRail"].BHasClass("Hidden"), "rail appears when authored rows overflow");
hud.panels["#RadiantRulesScrollDown"].events.onactivate();
assert(hud.panels["#RadiantRules"].style.marginTop === "-10px;", "scroll maximum derives from three rows, not ten");
created(hud, "RadiantDeleteRule2").events.onactivate();
created(hud, "RadiantDeleteRule1").events.onactivate();
assert(visibleRules(hud, "Radiant").length === 1, "delete removes rows without padding");
assert(hud.panels["#RadiantRules"].style.marginTop === "0px;", "delete clamps stale scroll offset");
assert(hud.panels["#RadiantRulesScrollRail"].BHasClass("Hidden"), "delete hides unnecessary rail");
assert(hud.sentEvents.some(function (e) {
    return e.name === "rpg_update_rule" && e.payload.hero_index === 501 && e.payload.rule_count === 1 && e.payload.slot === 1;
}), "delete must send the reduced rule count to clear stale server slots");
assert(hud.sentEvents.filter(function (e) { return e.name === "rpg_update_rule"; }).every(function (e) {
    return e.payload.rule_count >= 1 && e.payload.slot <= e.payload.rule_count;
}), "rule sync must send actual rows, not disabled padding slots");
chooseAction(hud, "Radiant", 0, "ability_1");
chooseAction(hud, "Dire", 0, "ability_1");

// 服务端状态推送后，首批五个英雄报价与阵容 UI 正常渲染。
hud.subscriptions.rpg_shop_state({
    gold: 500,
    offer_text: [
        "npc_dota_hero_axe|1|common|100",
        "npc_dota_hero_juggernaut|1|common|100",
        "npc_dota_hero_lina|1|fine|120",
        "npc_dota_hero_marci|1|common|100",
        "npc_dota_hero_sven|1|epic|150"
    ].join(";"),
    owned_text: "npc_dota_hero_axe;npc_dota_hero_juggernaut;npc_dota_hero_lion",
    lineup_text: "npc_dota_hero_axe;npc_dota_hero_juggernaut",
    bench_slots: 0,
    refresh_cost: 20,
    scroll_low_remaining: 3,
    scroll_high_remaining: 3,
    scroll_low_stock: 0,
    scroll_high_stock: 0,
    stock_text: "item_magic_wand|9001",
    equipped_text: "npc_dota_hero_axe:item_blink|8001|0,item_force_staff|8002|14;npc_dota_hero_juggernaut:;npc_dota_hero_lion:item_manta|8100|0"
});
assert(hud.createdPanels.some(function (p) { return p.classes.ShopName && p.text === "Lv1 普通"; }),
    "shop offer cards must show recruit level and quality");
assert(hud.createdPanels.filter(function (p) { return p.classes.ShopOfferSlot; }).length === 5,
    "initial shop state must render five hero offer cards");
// 结算奖励完全来自服务端字段，不能在客户端再次分配 XP 或重复加入时间奖励。
hud.subscriptions.rpg_settlement({
    winner: "radiant", level: "ch01", gold: 150,
    xp_per_active_hero: 1000, xp_per_bench_hero: 500, stars: 3, loot_text: "item_blink"
});
assert(hud.panels["#RewardLabel"].text.indexOf("150") >= 0
    && hud.panels["#RewardLabel"].text.indexOf("dota2_rpg_reward_xp") >= 0,
    "settlement UI must render server-authoritative gold and active/bench XP without runtime errors");
var radiantAbility = hud.createdPanels.filter(function (p) { return p.id === "RadiantActionAbility0"; })[0];
var direAbility = hud.createdPanels.filter(function (p) { return p.id === "DireActionAbility0"; })[0];
assert(radiantAbility && radiantAbility.abilityname === "axe_berserkers_call",
    "Radiant action rows must use the real ability icon name");
assert(direAbility && direAbility.abilityname === "lion_impale",
    "Dire action rows must use the real ability icon name");

var itemTarget = hud.panels["#ItemTargetLabel"];
assert(itemTarget && itemTarget.text.indexOf("axe") >= 0,
    "equipment panel must keep a visible selected-hero target");
assert(itemTarget.text.indexOf("1/6") >= 0,
    "equipment target must show the live number of equipped slots");
assert(/id="NativeShopHint"/.test(layoutSource)
    && layoutSource.indexOf("#dota2_rpg_native_shop_hint") >= 0,
    "equipment panel must direct ordinary item purchases to the native Dota shop");
assert(!hud.createdPanels.some(function (p) { return p.id === "BuyEquip0" || p.id === "Store0"; }),
    "scroll-only panel must not expose custom ordinary-item purchase controls");
var scrollBuy = hud.createdPanels.filter(function (p) { return p.id === "ScrollBuyBtn_low"; })[0];
var scrollUse = hud.createdPanels.filter(function (p) { return p.id === "ScrollUseBtn_low"; })[0];
assert(scrollBuy && scrollBuy.events.onactivate && scrollUse && scrollUse.events.onactivate,
    "scroll-only panel must expose buy and use controls for the low scroll");
scrollBuy.events.onactivate();
var scrollBuyEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(scrollBuyEvent.name === "rpg_scroll_buy" && scrollBuyEvent.payload.kind === "low",
    "low scroll purchase must use the existing scroll event");
scrollUse.events.onactivate();
var scrollUseEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(scrollUseEvent.name === "rpg_scroll_use"
    && scrollUseEvent.payload.kind === "low"
    && scrollUseEvent.payload.hero === "npc_dota_hero_axe",
    "low scroll use must target the persistently selected hero");
var stashEquip = hud.createdPanels.filter(function (p) { return p.id === "Equip0"; })[0];
assert(stashEquip && stashEquip.events.onactivate,
    "wisp stash items must retain a one-click equip action");
stashEquip.events.onactivate();
var stashEquipEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(stashEquipEvent.name === "rpg_item_equip"
    && stashEquipEvent.payload.hero === "npc_dota_hero_axe"
    && stashEquipEvent.payload.item === "item_magic_wand"
    && stashEquipEvent.payload.item_index === "9001",
    "stash item transfer must use the same selected hero and exact item entity without map drag/drop");
var unequip = hud.createdPanels.filter(function (p) { return p.id === "Unequip_npc_dota_hero_axe_0"; })[0];
assert(unequip && unequip.events.onactivate,
    "equipped item rows must expose an explicit unequip action");
unequip.events.onactivate();
var unequipEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(unequipEvent.name === "rpg_item_unequip"
    && unequipEvent.payload.item_index === "8001"
    && unequipEvent.payload.slot === 0,
    "unequip requests must identify the exact equipped item entity and slot");
var nativeStashUnequip = hud.createdPanels.filter(function (p) { return p.id === "Unequip_npc_dota_hero_axe_1"; })[0];
assert(nativeStashUnequip && nativeStashUnequip.events.onactivate,
    "hero native stash items must remain visible in the transfer panel");
nativeStashUnequip.events.onactivate();
var nativeStashUnequipEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(nativeStashUnequipEvent.name === "rpg_item_unequip"
    && nativeStashUnequipEvent.payload.item_index === "8002"
    && nativeStashUnequipEvent.payload.slot === 14,
    "hero native stash transfer must preserve the exact entity id and source slot");

var secondTarget = hud.createdPanels.filter(function (p) { return p.id === "ItemTarget_npc_dota_hero_juggernaut"; })[0];
assert(secondTarget && secondTarget.events.onactivate,
    "equipment panel must provide a direct target selector for every fielded hero");
secondTarget.events.onactivate();
assert(hud.panels["#ItemTargetLabel"].text.indexOf("juggernaut") >= 0,
    "changing the equipment target must update in place instead of requiring a re-field click");
var benchTarget = hud.createdPanels.filter(function (p) { return p.id === "ItemTarget_npc_dota_hero_lion"; })[0];
assert(benchTarget && benchTarget.events.onactivate,
    "equipment panel must expose owned standby heroes as direct purchase targets");
benchTarget.events.onactivate();
var benchTargetEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(benchTargetEvent.name === "rpg_native_purchase_target"
    && benchTargetEvent.payload.hero === "npc_dota_hero_lion",
    "standby hero target selection must be sent to the server for native purchases");

assert(/\.EditorBody\s*\{[^}]*height:\s*fill-parent-flow\(1\.0\)/s.test(cssSource),
    "action editor body must fill the remaining panel height");
assert(/\.RulesContainer\s*\{[^}]*height:\s*fill-parent-flow\(1\.0\)[^}]*overflow:\s*squish scroll/s.test(cssSource),
    "action rows must live in a full-height vertical scroll viewport");
assert(/\.RulesContainer VerticalScrollBar[\s\S]*\.ScrollThumb/.test(cssSource),
    "action row viewport must expose a visible scrollbar thumb");
assert(/\.RuleRow\s*\{[^}]*height:\s*130px/s.test(cssSource),
    "action rows must reserve space for the lower condition controls");
assert(/id="RadiantRules"[^>]*hittest="true"/.test(layoutSource) &&
    /id="DireRules"[^>]*hittest="true"/.test(layoutSource),
    "both action lists must accept wheel and pointer input");
assert(/id="NativeShopHint"/.test(layoutSource)
    && /id="ItemTargetLabel"/.test(layoutSource)
    && /id="ItemTargetHeroes"/.test(layoutSource)
    && /id="ItemEquippedList"/.test(layoutSource)
    && /id="ScrollShopList"/.test(layoutSource),
    "equipment UI must expose native-shop guidance, persistent target, and scroll-only management regions");
assert(/\.NativeShopHint\s*\{/.test(cssSource)
    && /\.ItemTargetRow\s*\{/.test(cssSource)
    && /\.ItemUnequipBtn\s*\{/.test(cssSource)
    && /\.ItemScrollBuyBtn\s*\{/.test(cssSource),
    "native-shop hint, target, scroll, and unequip controls must have dedicated visible styles");
assert(/MAX_STASH_SLOTS\s*=\s*15/.test(hudSource)
    && /shopState\.stock\.length\s*<\s*MAX_STASH_SLOTS/.test(hudSource),
    "equipment UI must account for inventory, backpack, and native stash slots 0 through 14");
assert(hud.sentEvents.some(function (event) {
    return event.name === "rpg_native_purchase_target" && event.payload.unit_index === 503;
}), "Panorama must tell the server which active or bench hero is selected for native purchases");
assert(hudSource.indexOf('SendCustomGameEventToServer("rpg_item_buy') < 0
    && hudSource.indexOf('SendCustomGameEventToServer("rpg_item_sell') < 0
    && hudSource.indexOf("rpg_item_equip") >= 0
    && hudSource.indexOf("rpg_item_unequip") >= 0,
    "equipment UI must remove custom ordinary-item buy/sell events and retain exact transfer events");

var currentSave = runHud();
assert(currentSave.createdPanels.length > 0, "HUD must initialize and create panels");

assert(layoutSource.indexOf("styles/custom_game/issue_fixes_ui.css") > layoutSource.indexOf("styles/custom_game/rpg_demo_hud.css"),
    "fix styles must load after base styles in the live HUD, not just a sibling layout");
assert(/\.TeamEditor \.RpgActionPanelArrowButton\s*\{[^}]*width:\s*44px;[^}]*height:\s*44px;/s.test(fixesCssSource),
    "live editor button selector must override both team-specific 26px styles with 44x44");
assert(/\.TeamEditor\.RpgActionPanelCollapsed\s*\{[^}]*width:\s*56px !important;[^}]*height:\s*56px !important;[^}]*padding:\s*0px !important;/s.test(fixesCssSource),
    "collapsed live editor must be 56x56 with no inherited 16px padding");
assert(/\.TeamEditor\.RpgActionPanelCollapsed \.TeamHeader\s*\{[^}]*width:\s*56px;[^}]*height:\s*56px;[^}]*padding:\s*0px;/s.test(fixesCssSource),
    "nested header must fit the collapsed editor without clipping its button");
assert(/\.RpgActionPanelCollapsed \.EditorBody,[\s\S]*visibility:\s*collapse;/.test(fixesCssSource),
    "actual editor body, identity and portraits must be hidden when collapsed");
assert(/\.RpgTransparentHeroShop #ShopOffer\s*\{[^}]*background-color:\s*transparent !important;[^}]*background-image:\s*none !important;[^}]*border:\s*0px !important;[^}]*box-shadow:\s*none !important;/s.test(fixesCssSource),
    "shop root/frame/body and actual multi-offer wrapper must have no opaque mask");
assert(/\.RpgTransparentHeroShop \.ShopOfferSlot\s*\{[^}]*background-color:\s*#11111199;/s.test(fixesCssSource),
    "only individual hero offer cards retain a translucent background");
assert(!/\.RpgTransparentHeroShop \.ShopOffer\s*\{/.test(fixesCssSource),
    "offer strip must not be mistaken for an individual offer card");

[
    [path.join(path.dirname(hudPath), "issue_fixes_ui.js"), "scripts/custom_game/issue_fixes_ui.js"],
    [path.join(path.dirname(cssPath), "issue_fixes_ui.css"), "styles/custom_game/issue_fixes_ui.css"]
].forEach(function (entry) {
    var overlayPath = path.join(repoRoot, "dota2_rpg_issue_fixes", "overlay", "content", "dota_addons", "dota2_rpg", "panorama", entry[1]);
    assert(fs.readFileSync(entry[0]).equals(fs.readFileSync(overlayPath)), "overlay must match live UI: " + entry[1]);
});

console.log("PASS: live HUD single defaults, authored rows, collapse wiring, transparent shop, no-save, transfers, icons and overlay parity");
