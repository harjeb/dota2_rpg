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

function runHud(options) {
    options = options || {};
    var scheduled = [];
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
    panorama.Schedule = function (delay, callback) {
        if (options.deferTimers) { scheduled.push({ delay: delay, callback: callback }); }
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
        nativeSelections: nativeSelections,
        subscriptions: subscriptions,
        scheduled: scheduled,
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

function serverRules(actions) {
    return actions.map(function (action) {
        return { action: action, enabled: 1, target_team: "enemy", target_priorities: [{type: "nearest"}], use_conditions: [] };
    });
}
var hud = runHud();
// Editing starts after authoritative hero metadata arrives.
hud.subscriptions.rpg_hero_slots({slot_key:"dire_1",hero_name:"npc_dota_hero_lion",hero_index:502,
    actions_text:"ability_1;attack",details_text:"lion_impale;attack",can_edit:1});
var firstMenu = created(hud, "DireActionMenu0");
assert(firstMenu.BHasClass("Hidden"), "fresh action menu starts hidden as a separate class");
created(hud, "DireActionSelect0").events.onactivate();
assert(!firstMenu.BHasClass("Hidden"), "first click opens the action list");
assert(firstMenu.parent.id === "DropdownLayer", "action list escapes editor clipping");
created(hud, "DireActionSelect0").events.onactivate();
assert(firstMenu.BHasClass("Hidden"), "second click closes action list");
var conditionEditor = created(hud, "DireConditionEditor0");
var conditionButton = conditionEditor.FindChildTraverse("ConditionSelect");
var conditionMenu = conditionEditor.FindChildTraverse("ConditionMenu");
conditionButton.position = { x: 1780, y: 1020 };
conditionButton.events.onactivate();
assert(!conditionMenu.BHasClass("Hidden"), "real XML condition menu opens on first click");
assert(conditionMenu.style.marginLeft === "1620px" && conditionMenu.style.marginTop === "740px",
    "menus clamp to viewport edge and flip above bottom-row buttons");
conditionMenu.FindChildTraverse("SelfHpPctOption").events.onactivate();
assert(conditionMenu.BHasClass("Hidden"), "condition selection closes menu");
assert(conditionEditor.FindChildTraverse("ConditionValue").text === "#dota2_rpg_condition_self_hp_pct_lte",
    "real XML condition selection updates visible rule");
conditionButton.position = { x: 360, y: 540 };
hud.panels["#DropdownLayer"].actualuiscale_x = 1.5;
hud.panels["#DropdownLayer"].actualuiscale_y = 1.5;
conditionButton.events.onactivate();
assert(conditionMenu.style.marginLeft === "240px" && conditionMenu.style.marginTop === "388px",
    "menu coordinates account for HUD scale and current button position");
conditionButton.events.onactivate();
hud.panels["#DropdownLayer"].actualuiscale_x = 1;
hud.panels["#DropdownLayer"].actualuiscale_y = 1;
hud = runHud();
assert(hud.getLocalStorageCalls() === 0, "no-save design must not touch LocalStorage");
assert(hud.sentEvents.every(function (e) { return e.name !== "rpg_save_sync"; }),
    "no-save design must not send save sync events");

// 服务端会先推送英雄动作详情，再推送购买后的阵容；图标必须能在阵容刷新后显示。
hud.subscriptions.rpg_enemy_roster({units:[{id:502,name:"npc_dota_hero_lion"}]});
hud.subscriptions.rpg_hero_slots({
    slot_key: "radiant_1",
    hero_name: "npc_dota_hero_axe",
    hero_index: 501,
    actions_text: "ability_1;ability_2;ultimate;attack",
    details_text: "axe_berserkers_call;axe_battle_hunger;axe_culling_blade;attack",
    rules_ready: 1, rules: serverRules(["ability_1", "ability_2", "ultimate", "attack"])
});
hud.subscriptions.rpg_hero_slots({
    slot_key: "dire_1",
    hero_name: "npc_dota_hero_lion",
    hero_index: 502,
    actions_text: "ability_1;attack",
    details_text: "lion_impale;attack",
    rules_ready: 1, rules: serverRules(["ability_1", "attack"])
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
    assert(!created(hud, side + "ActionMenu" + row).BHasClass("Hidden"), "action menu must actually open");
    var images = created(hud, side + "ActionMenu" + row).children.reduce(function (all, option) {
        return all.concat(option.children.filter(function (child) { return child.type === "DOTAAbilityImage"; }));
    }, []);
    assert(images.some(function (image) { return image.abilityname && image.hittest === false; }),
        "ability list must render actual skill icons without intercepting clicks");
    var option = created(hud, "ActionOpt_" + side + row + "_" + action);
    assert(option && option.events.onactivate, "selected hero action must be available on every authored row");
    option.events.onactivate();
}

["Radiant", "Dire"].forEach(function (side) {
    var expectedActions = side === "Radiant" ? ["axe_berserkers_call", "axe_battle_hunger", "axe_culling_blade"] : ["lion_impale"];
    assert(visibleRules(hud, side).length === expectedActions.length + 1, side + " defaults include active skills plus attack");
    expectedActions.forEach(function (name, index) {
        assert(created(hud, side + "ActionAbility" + index).abilityname === name, "active skills precede attack");
        assert(created(hud, side + "ConditionEditor" + index).FindChildTraverse("ConditionValue").text === "#dota2_rpg_condition_always",
            "default skills use the simplest always condition");
    });
    // Reduce to one authored rule for the existing add/delete/scroll regression below.
    for (var row = expectedActions.length; row > 0; row--) { created(hud, side + "DeleteRule" + row).events.onactivate(); }
    var defaultEventStart = hud.sentEvents.length;
    chooseAction(hud, side, 0, "attack"); // Explicit edit sends; metadata/render must not overwrite server rules.
    var defaults = hud.sentEvents.slice(defaultEventStart).filter(function (e) {
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
    assert(hud.panels["#" + side + "Editor"].visible === false, "collapsed editor is hidden as a whole");
    assert(hud.panels["#" + side + "RestoreButton"].visible === true, "external restore control remains visible");
    assert(rootLayout.children.some(function (node) { return node.attrs.id === side + "RestoreButton"; }),
        "restore button must be a root sibling, not a descendant of the hidden editor");
    hud.panels["#" + side + "RestoreButton"].events.onactivate();
    assert(hud.panels["#" + side + "Editor"].visible === true, "external control restores editor");
    assert(hud.panels["#" + side + "RestoreButton"].visible === false, "restore control hides after expanding");
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
assert(hud.panels["#RadiantRules"].style.marginTop === "-10px", "scroll maximum derives from three rows, not ten");
created(hud, "RadiantDeleteRule2").events.onactivate();
created(hud, "RadiantDeleteRule1").events.onactivate();
assert(visibleRules(hud, "Radiant").length === 1, "delete removes rows without padding");
assert(hud.panels["#RadiantRules"].style.marginTop === "0px", "delete clamps stale scroll offset");
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
    hero_entity_indices: { npc_dota_hero_axe: 501, npc_dota_hero_juggernaut: 504, npc_dota_hero_lion: 503 },
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
assert(hud.nativeSelections.at(-1).index === 504 && hud.nativeSelections.at(-1).additive === false,
    "fielded equipment portrait must select the actual native hero for ability training");
assert(hud.panels["#ItemTargetLabel"].text.indexOf("juggernaut") >= 0,
    "changing the equipment target must update in place instead of requiring a re-field click");
var benchTarget = hud.createdPanels.filter(function (p) { return p.id === "ItemTarget_npc_dota_hero_lion"; })[0];
assert(benchTarget && benchTarget.events.onactivate,
    "equipment panel must expose owned standby heroes as direct purchase targets");
benchTarget.events.onactivate();
assert(hud.nativeSelections.at(-1).index === 503,
    "bench equipment portrait must select its native hero, not leave abilities on the commander");
var benchTargetEvent = hud.sentEvents[hud.sentEvents.length - 1];
assert(benchTargetEvent.name === "rpg_native_purchase_target"
    && benchTargetEvent.payload.hero === "npc_dota_hero_lion",
    "standby hero target selection must be sent to the server for native purchases");
var selectionsBeforeRefresh = hud.nativeSelections.length;
hud.subscriptions.rpg_shop_state({
    owned_text: "npc_dota_hero_axe;npc_dota_hero_lion",
    lineup_text: "npc_dota_hero_axe",
    hero_entity_indices: { npc_dota_hero_axe: 601, npc_dota_hero_lion: 603 }
});
assert(hud.nativeSelections.length === selectionsBeforeRefresh,
    "state broadcasts must not steal native selection");
created(hud, "ItemTarget_npc_dota_hero_lion").events.onactivate();
assert(hud.nativeSelections.at(-1).index === 603,
    "a rebuilt bench portrait must select the replacement entity, not the destroyed hero");
hud.subscriptions.rpg_shop_state({ owned_text: "npc_dota_hero_lion", lineup_text: "" });
var selectionsWithoutEntity = hud.nativeSelections.length;
created(hud, "ItemTarget_npc_dota_hero_lion").events.onactivate();
assert(hud.nativeSelections.length === selectionsWithoutEntity,
    "missing entity metadata must not reuse a stale native selection ID");

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

assert(/id="DropdownLayer"[^>]*hittest="false"[^>]*hittestchildren="true"/.test(layoutSource),
    "fullscreen dropdown layer must pass through native shop/ability clicks while menus remain interactive");

var currentSave = runHud();
assert(currentSave.createdPanels.length > 0, "HUD must initialize and create panels");

assert(!/\b(?:hitest|hittest|hittestchildren)\s*:/i.test(fixesCssSource + cssSource),
    "Panorama hit testing is a panel property, never a CSS declaration");
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
assert(/\.RpgTransparentHeroShop #ShopOffer\s*\{[^}]*background-color:\s*transparent !important;[^}]*border:\s*0px !important;[^}]*box-shadow:\s*none !important;/s.test(fixesCssSource)
    && !/background-image\s*:/.test(fixesCssSource),
    "shop root/frame/body and actual multi-offer wrapper must have no opaque or unsupported background declaration");
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

console.log("PASS: live HUD active skill defaults, authored rows, collapse wiring, transparent shop, no-save, transfers, icons and overlay parity");

// Real roster events replace fixed portraits and preserve identity/count across refreshes.
var damageHud = runHud();
damageHud.subscriptions.rpg_enemy_roster({units: {"1": {id: 80, name: "npc_dota_neutral_centaur_khan"}, "2": {id: 81, name: "npc_dota_hero_sniper"}}});
assert(damageHud.panels["#DireHeroStrip"].children.length === 2, "enemy strip follows actual roster count");
assert(damageHud.panels["#DireHeroDyn1"].type === "Button", "neutral receives readable unit label");
assert(damageHud.panels["#DireHeroDyn2"].heroname === "npc_dota_hero_sniper", "actual enemy hero portrait");
damageHud.panels["#DireHeroDyn2"].events.onactivate();
assert(damageHud.panels["#DireSelectedHero"].text.indexOf("sniper") >= 0, "actual enemy selection updates editor");
damageHud.subscriptions.rpg_enemy_roster({units: [{id: 82, name: "npc_dota_hero_lina"}]});
assert(damageHud.panels["#DireHeroStrip"].children.length === 1, "next stage drops stale enemies");
damageHud.subscriptions.rpg_battle_state({phase: "fight", ready: 1});
["Radiant", "Dire"].forEach(function (side) {
    assert(damageHud.panels["#" + side + "Editor"].visible === false, "battle auto collapses " + side);
    assert(damageHud.panels["#" + side + "RestoreButton"].visible === true, "battle keeps restore " + side);
});
damageHud.panels["#DireRestoreButton"].events.onactivate();
damageHud.subscriptions.rpg_battle_state({phase: "fight", ready: 1});
assert(damageHud.panels["#DireEditor"].visible === true, "same-phase update respects manual restore");
var victimA = {id: 80, name: "npc_dota_hero_axe", total: 60};
var victimB = {id: 81, name: "npc_dota_hero_lion", total: 40};
damageHud.subscriptions.rpg_damage_stats({elapsed: 2, units: {"1": {id: 1, name: "npc_dota_hero_sniper", team: 2, total: 100, dps: 50,
    sources: {"1": {name: "attack", total: 60, targets: [victimA]}, "2": {name: "sniper_shrapnel", total: 40, targets: [victimB]}}, targets: [victimA, victimB]},
    "2": {id: 80, name: "npc_dota_hero_axe", team: 3, total: 30, dps: 15, sources: [{name: "attack", total: 30, targets: [{id: 1, name: "npc_dota_hero_sniper", total: 30}]}], targets: [{id: 1, name: "npc_dota_hero_sniper", total: 30}]}}});
assert(!damageHud.panels["#DamagePanel"].BHasClass("Hidden"), "DPS shown in battle");
var unitRow = damageHud.panels["#DamageUnits"].children[0];
assert(unitRow.children[0].text.indexOf("50 DPS") >= 0, "DPS uses server measurement");
var segments = unitRow.children[1].children;
assert(segments.length === 2 && segments[0].style.backgroundColor !== segments[1].style.backgroundColor, "attack and skill get distinct bar colors");
assert(segments[0].style.width === "60%" && segments[1].style.width === "40%", "bar segments preserve source proportions");
assert(damageHud.panels["#DamageTargets"].children.length === 2, "all-source view lists both victims");
damageHud.panels["#DamageSources"].children[2].events.onactivate();
assert(damageHud.panels["#DamageTargets"].children.length === 1 && damageHud.panels["#DamageTargets"].children[0].text.indexOf("lion") >= 0,
    "skill selection filters per-target damage");
damageHud.panels["#DamageEnemy"].events.onactivate();
assert(damageHud.panels["#DamageUnits"].children[0].id === "DamageUnit80", "enemy tab shows actual enemy statistics");
damageHud.subscriptions.rpg_battle_state({phase: "result"});
assert(!damageHud.panels["#DamagePanel"].BHasClass("Hidden"), "result retains final damage panel");
damageHud.subscriptions.rpg_battle_state({phase: "setup", ready: 1});
assert(damageHud.panels["#DamagePanel"].BHasClass("Hidden"), "setup hides previous battle DPS");
console.log("PASS: actual enemy roster, battle collapse, DPS teams, source colors and target filtering");

// Stage transitions retain authored conditions by name and duplicate occurrence.
var persistenceHud = runHud();
function slots(side, index, name, entity) {
    persistenceHud.subscriptions.rpg_hero_slots({slot_key: side.toLowerCase() + "_" + index,
        hero_name: name, hero_index: entity, actions_text: "ability_1;attack", details_text: "lion_impale;attack",
        rules_ready: 1, rules: serverRules(["ability_1", "attack"])});
}
function setHealthCondition(side) {
    var editor = created(persistenceHud, side + "ConditionEditor0");
    var menu = editor.FindChildTraverse("ConditionMenu");
    editor.FindChildTraverse("ConditionSelect").events.onactivate();
    menu.FindChildTraverse("SelfHpPctOption").events.onactivate();
}
function healthCondition(side) {
    return created(persistenceHud, side + "ConditionEditor0").FindChildTraverse("ConditionValue").text
        === "#dota2_rpg_condition_self_hp_pct_lte";
}
var lionName = "npc_dota_hero_lion";
var axeName = "npc_dota_hero_axe";
persistenceHud.subscriptions.rpg_enemy_roster({units: [{id: 101, name: lionName}, {id: 102, name: lionName}]});
slots("Dire", 1, lionName, 101);
slots("Dire", 2, lionName, 102);
setHealthCondition("Dire");
created(persistenceHud, "DireAddRule0").events.onactivate();
persistenceHud.panels["#DireHeroDyn2"].events.onactivate();
assert(!healthCondition("Dire") && visibleRules(persistenceHud, "Dire").length === 2,
    "duplicate enemies have independent authored rules");
persistenceHud.subscriptions.rpg_enemy_roster({units: [{id: 201, name: lionName}, {id: 202, name: lionName}]});
slots("Dire", 1, lionName, 201);
slots("Dire", 2, lionName, 202);
persistenceHud.panels["#DireHeroDyn1"].events.onactivate();
assert(healthCondition("Dire") && visibleRules(persistenceHud, "Dire").length === 3,
    "enemy respawn preserves condition and authored row count by occurrence");
persistenceHud.panels["#DireHeroDyn2"].events.onactivate();
assert(!healthCondition("Dire"), "second duplicate stays independent after respawn");
persistenceHud.subscriptions.rpg_enemy_roster({units: [{id: 301, name: axeName}]});
slots("Dire", 1, axeName, 301);
assert(!healthCondition("Dire") && visibleRules(persistenceHud, "Dire").length === 2,
    "new enemy identity starts with default rules");
slots("Radiant", 1, axeName, 401);
slots("Radiant", 2, lionName, 402);
persistenceHud.subscriptions.rpg_shop_state({lineup_text: axeName + ";" + lionName, owned_text: axeName + ";" + lionName});
setHealthCondition("Radiant");
slots("Radiant", 1, axeName, 501);
assert(healthCondition("Radiant"), "player condition survives replacement entity");
persistenceHud.subscriptions.rpg_shop_state({lineup_text: lionName + ";" + axeName, owned_text: axeName + ";" + lionName});
assert(!healthCondition("Radiant"), "reordered player does not inherit previous slot rules");
slots("Radiant", 1, lionName, 502);
slots("Radiant", 2, axeName, 501);
persistenceHud.panels["#RadiantHeroDyn2"].events.onactivate();
assert(healthCondition("Radiant"), "authored condition follows player hero name after reorder");
assert(!persistenceHud.sentEvents.some(function(event){return event.name==="rpg_update_rule" && event.payload.hero_index===501;}),
    "respawn and portrait selection do not overwrite authoritative rules");
created(persistenceHud,"RadiantRuleSettings0").events.onactivate();
persistenceHud.panels["#RuleSettingsApply"].events.onactivate();
assert(persistenceHud.sentEvents.some(function (event) {
    return event.name === "rpg_update_rule" && event.payload.hero_index === 501
        && event.payload.use_condition_1_type === "self_hp_pct_lte";
}), "explicit update sends retained conditions to the replacement entity");
console.log("PASS: stage rule persistence, duplicate enemy isolation, new enemy defaults and player reorder");

var walletHud = runHud();
walletHud.subscriptions.rpg_shop_state({gold: 500, owned_text: "npc_dota_hero_lion", lineup_text: "", equipped_text: ""});
assert(walletHud.panels["#WalletBalance"].text === "#dota2_rpg_wallet_balance 500", "visible wallet renders server total in preparation");
walletHud.subscriptions.rpg_shop_state({gold: 400, owned_text: "npc_dota_hero_lion", lineup_text: "", equipped_text: ""});
assert(walletHud.panels["#WalletBalance"].text === "#dota2_rpg_wallet_balance 400", "bench purchase updates visible balance without fielding or inventory change");
walletHud.subscriptions.rpg_shop_state({gold: 375, offer_text: {invalid: true}});
assert(walletHud.panels["#WalletBalance"].text === "#dota2_rpg_wallet_balance 375", "wallet update survives optional shop renderer errors");
console.log("PASS: visible authoritative wallet updates independently of lineup and inventory");

var learnedHud = runHud();
var learnedMetadata = {
    slot_key: "radiant_1", hero_name: "npc_dota_hero_lion", hero_index: 501,
    actions_text: "ability_1;ability_2;ultimate;attack", details_text: "lion_impale;lion_voodoo;lion_finger_of_death;attack",
    rules_ready: 1, rules: serverRules(["ability_1", "attack"])
};
learnedHud.subscriptions.rpg_hero_slots(learnedMetadata);
assert(visibleRules(learnedHud, "Radiant").length === 2, "unlearned actions in picker do not become default rules");
learnedMetadata.rules = serverRules(["ability_1", "ability_2", "attack"]);
learnedMetadata.rules[1].target_team = "ally";
learnedHud.subscriptions.rpg_hero_slots(learnedMetadata);
assert(visibleRules(learnedHud, "Radiant").length === 3, "newly learned skills refresh untouched defaults");
chooseAction(learnedHud, "Radiant", 2, "attack");
assert(learnedHud.sentEvents.some(function (event) {
    return event.name === "rpg_update_rule" && event.payload.slot === 3 && event.payload.action_kind === "attack";
}), "basic attack remains last after skill refresh");
created(learnedHud, "RadiantRuleSettings1").events.onactivate();
learnedHud.panels["#RuleSettingsApply"].events.onactivate();
assert(learnedHud.sentEvents.some(function (event) {
    return event.name === "rpg_update_rule" && event.payload.slot === 2 && event.payload.target_team === "ally";
}), "server-selected friendly target survives UI hydration");
learnedMetadata.rules = serverRules(["attack"]);
learnedHud.subscriptions.rpg_hero_slots(learnedMetadata);
assert(visibleRules(learnedHud, "Radiant").length === 3, "later snapshots cannot overwrite locally authored rules");
console.log("PASS: learned skill refresh, authoritative target teams, attack priority and authored protection");

var lootHud = runHud({ deferTimers: true });
var lootPopup = lootHud.panels["#LootPopup"];
function settleLoot(winner, items) {
    lootHud.subscriptions.rpg_settlement({winner: winner, loot_text: items, gold: 100});
}
function latestLootTimer() {
    return lootHud.scheduled.filter(function (timer) { return timer.delay === 3; }).slice(-1)[0];
}
settleLoot("radiant", "item_blink;item_magic_wand;");
assert(!lootPopup.BHasClass("Hidden") && lootPopup.BHasClass("LootPopupShowing"), "victory loot starts popup animation");
var lootCards = lootHud.panels["#LootPopupItems"].children;
assert(lootCards.length === 2 && lootCards[0].children[0].itemname === "item_blink"
    && lootCards[1].children[0].itemname === "item_magic_wand", "popup shows every received item with a native icon");
assert(lootCards[0].children[1].text === "item_blink", "unlocalized item names have a readable fallback");
var oldLootTimer = latestLootTimer();
assert(oldLootTimer, "popup schedules closure at exactly three seconds");
lootHud.panels["#LootPopupConfirm"].events.onactivate();
assert(lootPopup.BHasClass("Hidden"), "confirm immediately dismisses loot");
settleLoot("radiant", "item_branches");
oldLootTimer.callback();
assert(!lootPopup.BHasClass("Hidden"), "previous popup timer cannot dismiss a new reward");
latestLootTimer().callback();
assert(lootPopup.BHasClass("Hidden"), "three second timeout dismisses without confirmation");
settleLoot("radiant", "item_blink");
oldLootTimer = latestLootTimer();
settleLoot("radiant", "item_branches");
assert(lootHud.panels["#LootPopupItems"].children.length === 1, "new settlement replaces old reward cards");
oldLootTimer.callback();
assert(!lootPopup.BHasClass("Hidden"), "replacement settlement gets its own complete timeout");
settleLoot("radiant", "");
assert(lootPopup.BHasClass("Hidden"), "victory without drops does not show empty popup");
settleLoot("dire", "item_blink");
assert(lootPopup.BHasClass("Hidden"), "defeat cannot show loot popup");
settleLoot("timeout", "item_blink");
assert(lootPopup.BHasClass("Hidden"), "timeout cannot show loot popup");
assert(!lootHud.sentEvents.some(function (event) { return /loot|reward|settlement/.test(event.name); }),
    "popup display and confirmation never grant rewards again");
console.log("PASS: victory loot icons, animation state, confirm, 3-second dismissal and stale timer isolation");
