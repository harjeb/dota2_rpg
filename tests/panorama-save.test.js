"use strict";

var fs = require("fs");
var path = require("path");
var vm = require("vm");

var repoRoot = path.resolve(__dirname, "..");
var hudPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "scripts", "custom_game", "rpg_demo_hud.js");
var cssPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "styles", "custom_game", "rpg_demo_hud.css");
var layoutPath = path.join(repoRoot, "content", "dota_addons", "dota2_rpg", "panorama", "layout", "custom_game", "rpg_demo_hud.xml");
var hudSource = fs.readFileSync(hudPath, "utf8");
var cssSource = fs.readFileSync(cssPath, "utf8");
var layoutSource = fs.readFileSync(layoutPath, "utf8");

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
    panorama.Localize = function (token) { return token; };
    panorama.LocalStorage = {
        Get: function () { localStorageCalls++; return "null"; },
        Set: function () { localStorageCalls++; }
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

var hud = runHud();
assert(hud.getLocalStorageCalls() === 0, "no-save design must not touch LocalStorage");
assert(hud.sentEvents.every(function (e) { return e.name !== "rpg_save_sync"; }),
    "no-save design must not send save sync events");

// 服务端会先推送英雄动作详情，再推送购买后的阵容；图标必须能在阵容刷新后显示。
hud.subscriptions.rpg_hero_slots({
    slot_key: "radiant_1",
    hero_name: "npc_dota_hero_axe",
    actions_text: "ability_1;ability_2;ultimate;attack",
    details_text: "axe_berserkers_call;axe_battle_hunger;axe_culling_blade;attack"
});
hud.subscriptions.rpg_hero_slots({
    slot_key: "dire_1",
    hero_name: "npc_dota_hero_lion",
    actions_text: "ability_1;attack",
    details_text: "lion_impale;attack"
});

// 服务端状态推送后，首批五个英雄报价与阵容 UI 正常渲染。
hud.subscriptions.rpg_shop_state({
    gold: 300,
    offer_text: [
        "npc_dota_hero_axe|1|common|100",
        "npc_dota_hero_juggernaut|1|common|100",
        "npc_dota_hero_lina|1|fine|120",
        "npc_dota_hero_marci|1|common|100",
        "npc_dota_hero_sven|1|epic|150"
    ].join(";"),
    owned_text: "npc_dota_hero_axe;npc_dota_hero_juggernaut",
    lineup_text: "npc_dota_hero_axe;npc_dota_hero_juggernaut",
    bench_slots: 0,
    refresh_cost: 20,
    scroll_low_remaining: 3,
    scroll_high_remaining: 3,
    scroll_low_stock: 0,
    scroll_high_stock: 0,
    stock_text: "item_magic_wand|450|9001",
    equipped_text: "npc_dota_hero_axe:item_blink|8001;npc_dota_hero_juggernaut:",
    item_catalog: "item_blink|2250"
});
assert(hud.createdPanels.some(function (p) { return p.classes.ShopName && p.text === "Lv1 普通"; }),
    "shop offer cards must show recruit level and quality");
assert(hud.createdPanels.filter(function (p) { return p.classes.ShopOfferSlot; }).length === 5,
    "initial shop state must render five hero offer cards");
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
var directBuy = hud.createdPanels.filter(function (p) { return p.id === "BuyEquip0"; })[0];
assert(directBuy && directBuy.events.onactivate,
    "each catalog item must expose a direct buy-and-equip action");
directBuy.events.onactivate();
var directBuyEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(directBuyEvent.name === "rpg_item_buy_equip"
    && directBuyEvent.payload.hero === "npc_dota_hero_axe"
    && directBuyEvent.payload.item === "item_blink",
    "direct item purchase must target the persistently selected fielded hero");
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
    && unequipEvent.payload.item_index === "8001",
    "unequip requests must identify the exact equipped item entity");

var secondTarget = hud.createdPanels.filter(function (p) { return p.id === "ItemTarget_npc_dota_hero_juggernaut"; })[0];
assert(secondTarget && secondTarget.events.onactivate,
    "equipment panel must provide a direct target selector for every fielded hero");
secondTarget.events.onactivate();
assert(hud.panels["#ItemTargetLabel"].text.indexOf("juggernaut") >= 0,
    "changing the equipment target must update in place instead of requiring a re-field click");

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
assert(/id="ItemTargetLabel"/.test(layoutSource)
    && /id="ItemTargetHeroes"/.test(layoutSource)
    && /id="ItemEquippedList"/.test(layoutSource),
    "equipment UI must expose a persistent target and equipped-item management region");
assert(/\.ItemTargetRow\s*\{/.test(cssSource)
    && /\.ItemDirectBuyBtn\s*\{/.test(cssSource)
    && /\.ItemUnequipBtn\s*\{/.test(cssSource),
    "equipment target, direct-buy, and unequip controls must have dedicated visible styles");
assert(hudSource.indexOf("rpg_item_buy_equip") >= 0
    && hudSource.indexOf("rpg_item_unequip") >= 0,
    "equipment UI must wire direct equip and unequip server events");

var currentSave = runHud();
assert(currentSave.createdPanels.length > 0, "HUD must initialize and create panels");

console.log("PASS: no-save design, initial hero shop, scrollable action panels, and real ability icons render");
