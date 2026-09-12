(function () {
    "use strict";

    var ACTION_TOKENS = {
        ultimate: "#dota2_rpg_action_ultimate",
        ability_1: "#dota2_rpg_action_1",
        ability_2: "#dota2_rpg_action_2",
        ability_3: "#dota2_rpg_action_3",
        item_1: "#dota2_rpg_action_item_1",
        item_2: "#dota2_rpg_action_item_2",
        item_3: "#dota2_rpg_action_item_3",
        item_4: "#dota2_rpg_action_item_4",
        item_5: "#dota2_rpg_action_item_5",
        item_6: "#dota2_rpg_action_item_6",
        attack: "#dota2_rpg_action_attack",
        sustained_move: "#dota2_rpg_action_sustained_move"
    };

    // 组合式目标：先选属性，再选阵营与极值
    var TARGET_ATTR_TOKENS = {
        hp: "#dota2_rpg_target_attr_hp",
        hp_pct: "#dota2_rpg_target_attr_hp_pct",
        armor: "#dota2_rpg_target_attr_armor",
        attack: "#dota2_rpg_target_attr_attack",
        mr: "#dota2_rpg_target_attr_mr",
        distance: "#dota2_rpg_target_attr_distance",
        casting: "#dota2_rpg_target_attr_casting",
        controlled: "#dota2_rpg_target_attr_controlled"
    };

    var TARGET_SIDE_TOKENS = {
        enemy_highest: "#dota2_rpg_target_side_enemy_highest",
        enemy_lowest: "#dota2_rpg_target_side_enemy_lowest",
        ally_highest: "#dota2_rpg_target_side_ally_highest",
        ally_lowest: "#dota2_rpg_target_side_ally_lowest",
        nearest: "#dota2_rpg_target_side_nearest",
        farthest: "#dota2_rpg_target_side_farthest",
        ally_nearest: "#dota2_rpg_v2_ally_nearest",
        ally_farthest: "#dota2_rpg_v2_ally_farthest",
        self: "#dota2_rpg_target_self"
    };

    // 由属性+阵营组合出引擎目标 ID
    function composeTarget(attr, side) {
        attr = TARGET_ATTR_TOKENS[attr] ? attr : "hp";
        side = TARGET_SIDE_TOKENS[side] ? side : "enemy_lowest";
        if (side === "self") {
            return "self";
        }
        if (attr === "casting") {
            return "enemy_casting";
        }
        if (attr === "distance") {
            var team = side.indexOf("ally_") === 0 ? "ally" : "enemy";
            return team + "_distance_" + (side === "farthest" || side === "ally_farthest" || side === "ally_highest" || side === "enemy_highest" ? "farthest" : "nearest");
        }
        var parts = side.split("_"); // enemy|ally + highest|lowest
        if (side === "nearest" || side === "farthest") { parts = ["enemy", side === "farthest" ? "highest" : "lowest"]; }
        if (side === "ally_nearest" || side === "ally_farthest") { parts = ["ally", side === "ally_farthest" ? "highest" : "lowest"]; }
        return parts[0] + "_" + attr + "_" + parts[1];
    }

    // 旧 ID / 组合 ID 拆回 (attr, side)，兼容存档
    function decomposeTarget(target) {
        if (target === "self") {
            return { attr: "hp", side: "self" };
        }
        if (target === "enemy_casting") {
            return { attr: "casting", side: "enemy_highest" };
        }
        if (target === "ally_distance_nearest" || target === "ally_distance_farthest") {
            return { attr: "distance", side: target === "ally_distance_nearest" ? "ally_nearest" : "ally_farthest" };
        }
        if (target === "enemy_distance_nearest") {
            return { attr: "distance", side: "nearest" };
        }
        if (target === "enemy_distance_farthest") {
            return { attr: "distance", side: "farthest" };
        }
        var m = String(target).match(/^(enemy|ally)_(hp|hp_pct|armor|attack|mr)_(highest|lowest)$/);
        if (m) {
            return { attr: m[2], side: m[1] + "_" + m[3] };
        }
        return { attr: "hp", side: "enemy_lowest" };
    }

    var HEROES = {
        Radiant: [],  // 动态：由商店/阵容决定（CustomNetTables shop 表）
        Dire: [] // Server-spawned roster, including neutral units.
    };

    // 每个动作槽的默认规则模板（玩家可套用后微调）
    var DEFAULT_RULE_BY_ACTION = {
        ultimate: { condition: "always", value: 2, target_attr: "hp_pct", target_side: "enemy_lowest", forced: true },
        ability_1: { condition: "always", value: 50, target_attr: "distance", target_side: "nearest", forced: false },
        ability_2: { condition: "always", value: 50, target_attr: "hp_pct", target_side: "enemy_lowest", forced: false },
        ability_3: { condition: "self_hp_pct_lte", value: 50, target_attr: "hp", target_side: "self", forced: false },
        attack: { condition: "always", value: 50, target_attr: "distance", target_side: "nearest", forced: false }
    };
    // 主动装备和技能共用同一套规则编辑器；服务端动作列表中的 item_1..item_6
    // 不能因为没有静态模板而被客户端过滤掉。
    for (var defaultItemSlot = 1; defaultItemSlot <= 6; defaultItemSlot++) {
        DEFAULT_RULE_BY_ACTION["item_" + defaultItemSlot] = {
            condition: "always", value: 50, target_attr: "hp_pct", target_side: "enemy_lowest", forced: false
        };
    }

    var MAX_RULE_ROWS = 32;  // Editing limit, not a default row count.
    var heroSlots = {};
    var FALLBACK_SLOT_ACTIONS = ["ability_1", "ability_2", "ability_3", "ultimate", "attack"];

    function canEditHeroRules(side,heroIndex) {
        var entry = heroSlots[side.toLowerCase()+"_"+(heroIndex+1)];
        return phase === "setup" && !!entry && entry.can_edit !== false && entry.rules_ready !== false;
    }
    function getSlotActions(side, heroIndex) {
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var entry = heroSlots ? heroSlots[key] : null;
        var actions = [];
        if (entry && entry.actions_text) {
            var rawActions = splitList(entry.actions_text);
            for (var actionKey = 0; actionKey < rawActions.length; actionKey++) {
                var action = String(rawActions[actionKey]);
                if (/^[a-zA-Z][a-zA-Z0-9_]*$/.test(action) && actions.indexOf(action) < 0) {
                    actions.push(action);
                }
            }
        }
        if (!actions.length && entry && entry.actions_text !== undefined) { return ["attack"]; }
        if (!actions.length) {
            for (var fallbackIndex = 0; fallbackIndex < FALLBACK_SLOT_ACTIONS.length; fallbackIndex++) {
                actions.push(FALLBACK_SLOT_ACTIONS[fallbackIndex]);
            }
        }
        return actions;
    }

    function getActionDetail(side, heroIndex, action) {
        if (action === "sustained_move") { return ""; }
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var entry = heroSlots ? heroSlots[key] : null;
        if (!entry) {
            return ACTION_TOKENS[action] ? "" : String(action || "");
        }
        var actions = splitList(entry.actions_text);
        var details = splitList(entry.details_text);
        for (var index = 0; index < actions.length; index++) {
            if (actions[index] === action && details[index] && details[index] !== action) {
                return details[index];
            }
        }
        // Native action IDs are already ability names. Resolve through the live entity when available.
        if (!ACTION_TOKENS[action]) {
            if (typeof Entities !== "undefined" && Entities.GetAbilityByName && typeof Abilities !== "undefined" && Abilities.GetAbilityName) {
                var ability = Entities.GetAbilityByName(Number(entry.hero_index), action);
                if (ability !== undefined && ability !== null && ability >= 0) { return Abilities.GetAbilityName(ability) || action; }
            }
            return String(action || "");
        }
        return "";
    }

    function targetActors(side, heroIndex) {
        if (!canEditHeroRules(side, heroIndex)) { return []; }
        var team = side === "Radiant" ? "Dire" : "Radiant", result = [];
        (HEROES[team] || []).forEach(function (hero, index) {
            var entry = heroSlots[team.toLowerCase() + "_" + (index + 1)];
            if (!entry || !entry.target_actor || entry.name !== hero.name || entry.hero_index < 0
                || (hero.entityIndex !== undefined && entry.hero_index !== hero.entityIndex)) { return; }
            result.push({actor: entry.target_actor, name: entry.name,
                label: localizeHeroName(entry.name) + " · " + (index + 1)});
        });
        return result;
    }

    function actionHeroes(side, heroIndex) {
        var selected = heroSlots[side.toLowerCase() + "_" + (heroIndex + 1)], result = [];
        ["Radiant", "Dire"].forEach(function (team) {
            (HEROES[team] || []).forEach(function (hero, index) {
                var entry = heroSlots[team.toLowerCase() + "_" + (index + 1)];
                if (!entry || entry.name !== hero.name || entry.hero_index < 0) { return; }
                var abilities = entry.abilities_text !== undefined ? splitList(entry.abilities_text)
                    : getSlotActions(team, index).filter(function (action) { return action !== "attack" && action !== "sustained_move" && action.indexOf("item_") !== 0; })
                        .map(function (action) { return getActionDetail(team, index, action); });
                getSlotActions(team, index).forEach(function (action) {
                    var detail = getActionDetail(team, index, action);
                    if (action.indexOf("item_") === 0 && detail && detail.indexOf("item_") === 0 && abilities.indexOf(detail) < 0) {
                        abilities.push(detail);
                    }
                });
                result.push({ actor: entry === selected ? "" : entry.rule_key,
                    label: $.Localize("#dota2_rpg_v2_team_" + (team === side ? "ally" : "enemy")) + " " + localizeHeroName(entry.name) + " " + (index + 1),
                    abilities: abilities.filter(function (name) { return !!name; }) });
            });
        });
        return result;
    }

    function buildRulesForHero(side, heroIndex) {
        // Wait for the authoritative rules snapshot before showing generated skill rules.
        return [{
            action: "attack", condition: "always", value: 50,
            target_attr: "distance", target_side: "nearest",
            target: "enemy_distance_nearest", forced: false, enabled: true
        }];
    }

    function getRules(side, heroIndex) {
        var heroes = HEROES[side] || [];
        var entry = heroSlots[side.toLowerCase() + "_" + (heroIndex + 1)];
        var name = heroes[heroIndex] ? heroes[heroIndex].name : (entry ? entry.name : "");
        if (!name) { return []; }
        var occurrence = 0;
        for (var index = 0; index < heroIndex; index++) {
            var prior = heroSlots[side.toLowerCase() + "_" + (index + 1)];
            var priorName = heroes[index] ? heroes[index].name : (prior ? prior.name : "");
            if (priorName === name) { occurrence++; }
        }
        // Entity indices and lineup positions change across stages; authored rules do not.
        var identity = name + ":" + occurrence;
        if (!rulesBySide[side][identity]) {
            rulesBySide[side][identity] = buildRulesForHero(side, heroIndex);
        }
        return rulesBySide[side][identity];
    }

    var rulesBySide = { Radiant: {} };
    var selectedHeroIndex = { Radiant: 0 };
    var rowPanels = { Radiant: [] };
    var phase = "setup";
    var itemSellRequestId = 0;
    var pendingItemSales = {};
    var serverReady = false;
    var stageRetryReady = false;
    var lastNativePurchaseTarget = -1;
    var lastNativePurchaseHero = "";
    var selectedEquipmentHeroName = "";
    var heroEntityIndices = {};
    var commanderIndex = -1;
    var ruleGeneration = 0;

    function acceptRuleGeneration(data) {
        if (!data || data.rule_generation === undefined) { return true; }
        var generation = Number(data.rule_generation);
        if (!isFinite(generation) || generation < ruleGeneration || generation !== Math.floor(generation)) { return false; }
        if (generation === ruleGeneration) { return true; }
        ruleGeneration = generation;
        closeEditorMenus();
        RpgConditionCatalog.reset();
        RpgRuleSync.reset();
        rulesBySide = { Radiant: {} };
        heroSlots = {};
        // Fresh hero snapshots can precede the shop lineup. Discard its old names
        // too, so the new hero's defaults are cached under the correct identity.
        HEROES.Radiant = [];
        HEROES.Dire = [];
        enemyRosterSignature = null;
        selectedHeroIndex.Radiant = 0;
        selectedEquipmentHeroName = "";
        heroEntityIndices = {};
        commanderIndex = -1;
        shopPortraitSwap = null;
        shopOpenLast = false;
        lastNativePurchaseTarget = -1;
        lastNativePurchaseHero = "";
        saveData = loadSave();
        shopState.owned = [];
        shopState.lineup = [];
        shopState.offers = [];
        damageState = { elapsed: 0, units: [] };
        selectedDamageUnit = null;
        selectedDamageSource = null;
        closeLootPopup();
        ["ItemSellNotice", "ItemTransferNotice"].forEach(function (id) {
            var notice = $("#" + id);
            if (notice) { notice.text = ""; }
        });
        renderDamage();
        renderShop();
        renderItemShop();
        rowPanels.Radiant.forEach(function (panels) {
            panels.actionMenu.RemoveAndDeleteChildren();
            panels.diagnosticLabel.text = "";
        });
        renderSide("Radiant");
        return true;
    }

    function selectNativeHero(heroName) {
        var unitIndex = Number(heroEntityIndices[heroName] || -1);
        if (phase === "setup" && unitIndex > 0 && GameUI.SelectUnit) {
            GameUI.SelectUnit(unitIndex, false);
        }
    }

    // 实机日志确认：选中上阵/待命英雄时点原版商店购买，客户端连订单都不下发
    // （控制台里没有 Native order signature），选中小精灵才正常。所以在原版商店
    // 打开期间把选中临时切到小精灵，关闭时还原。交付目标由 sendNativePurchaseHero
    // 与服务端保持（服务端不会因为选中小精灵而改写目标），物品仍然进玩家选中的英雄。
    var shopPortraitSwap = null;

    function onNativeShopOpened() {
        if (phase !== "setup" || typeof GameUI === "undefined" || !GameUI.SelectUnit
            || typeof Players === "undefined" || !Players.GetLocalPlayerPortraitUnit) {
            return;
        }
        var portrait = Number(Players.GetLocalPlayerPortraitUnit());
        if (!(commanderIndex > 0) || !(portrait > 0) || portrait === commanderIndex) {
            return;
        }
        // 商店打开后改选英雄也必须重新切换；先同步交付目标，再改变头像。
        syncNativePurchaseTarget(true);
        shopPortraitSwap = portrait;
        GameUI.SelectUnit(commanderIndex, false);
    }

    function onNativeShopClosed() {
        var restore = shopPortraitSwap;
        shopPortraitSwap = null;
        if (restore === null || !(restore > 0) || typeof GameUI === "undefined" || !GameUI.SelectUnit) {
            return;
        }
        // 只在选中仍是小精灵时还原，避免覆盖玩家在商店里自己改选的单位。
        var portrait = typeof Players !== "undefined" && Players.GetLocalPlayerPortraitUnit
            ? Number(Players.GetLocalPlayerPortraitUnit()) : -1;
        if (phase === "setup" && portrait === commanderIndex) {
            GameUI.SelectUnit(restore, false);
        }
    }

    // 原生 HUD 的 DOTAHUDShopOpened/DOTAHUDShopClosed 实机没有派发（用户确认打开商店时
    // 选中没有切换），所以改用引擎自带的查询接口轮询："Ask whether the in game shop is
    // open." 只要它在，无论鼠标点还是快捷键打开商店都能覆盖。
    function shopDiag(message) {
        if (typeof $ !== "undefined" && typeof $.Msg === "function") {
            $.Msg("[Dota2Rpg] " + message);
        }
    }

    // 原生 CSS 用 DOTAHUDShop.ShopOpen 控制 transform/opacity，关闭不会清零网格尺寸。
    // GridMainShop 只是定位锚点，开合必须读取其 DOTAHUDShop 祖先的状态类。
    function nativeShopPanel() {
        try {
            if (typeof $ === "undefined" || !$.GetContextPanel) {
                return null;
            }
            var root = $.GetContextPanel();
            if (!root || !root.GetParent) {
                return null;
            }
            while (root.GetParent && root.GetParent()) {
                root = root.GetParent();
            }
            if (!root.FindChildTraverse) {
                return null;
            }
            var panel = root.FindChildTraverse("GridMainShop");
            while (panel) {
                if (panel.paneltype === "DOTAHUDShop" && panel.BHasClass) {
                    return panel;
                }
                panel = panel.GetParent ? panel.GetParent() : null;
            }
            return null;
        } catch (error) {
            return null;
        }
    }

    function probeBool(object, name) {
        try {
            if (object && typeof object[name] === "function") {
                var value = object[name]();
                return typeof value === "boolean" ? String(value) : "invalid";
            }
            return object ? "missing" : "no-namespace";
        } catch (error) {
            return "threw";
        }
    }

    function shopProbeReport() {
        var shop = nativeShopPanel();
        // Panorama 禁止 eval；直接传命名空间，避免探测本身制造三条 threw。
        return "GameUI=" + probeBool(typeof GameUI !== "undefined" ? GameUI : null, "IsShopOpen")
            + " Game=" + probeBool(typeof Game !== "undefined" ? Game : null, "IsShopOpen")
            + " Players=" + probeBool(typeof Players !== "undefined" ? Players : null, "IsShopOpen")
            + " shopPanel=" + (shop ? "DOTAHUDShop" : "missing")
            + " source=" + (shop ? "ShopOpen-class" : "API");
    }

    function nativeShopIsOpen() {
        var shop = nativeShopPanel();
        if (shop) {
            return shop.BHasClass("ShopOpen");
        }
        var probes = [
            probeBool(typeof GameUI !== "undefined" ? GameUI : null, "IsShopOpen"),
            probeBool(typeof Game !== "undefined" ? Game : null, "IsShopOpen"),
            probeBool(typeof Players !== "undefined" ? Players : null, "IsShopOpen")
        ];
        if (probes.indexOf("true") >= 0) { return true; }
        return probes.indexOf("false") >= 0 ? false : null;
    }

    var shopProbeLogged = false;
    var shopOpenKnown = null;
    var shopOpenLast = false;

    function updateNativeShopState(open) {
        if (phase !== "setup") {
            shopPortraitSwap = null;
            shopOpenLast = false;
            return;
        }
        if (open !== shopOpenLast) {
            shopOpenLast = open;
            shopDiag(open ? "native shop opened" : "native shop closed");
        }
        if (open) {
            // 每次都检查头像：商店打开后点英雄也要保持原生商店可操作。
            onNativeShopOpened();
        } else {
            onNativeShopClosed();
        }
    }

    function watchNativeShop() {
        $.Schedule(0.25, watchNativeShop);
        if (!shopProbeLogged) {
            shopProbeLogged = true;
            shopDiag("shop probe " + shopProbeReport());
        }
        if (phase !== "setup") {
            updateNativeShopState(false);
            return;
        }
        var open = nativeShopIsOpen();
        var available = open !== null;
        if (available !== shopOpenKnown) {
            shopOpenKnown = available;
            shopDiag(available ? "shop state available; selection swap armed"
                : "shop state unavailable; selection swap disabled");
        }
        if (available) {
            updateNativeShopState(open);
        }
    }

    // 原版商店对额外生成的英雄仍可能把物品送到 assigned hero（小精灵）。
    // 把当前世界选择同步给服务端，购买后即可将新增的同一物品实体补转给上阵或待命英雄。
    function syncNativePurchaseTarget(force) {
        if (phase !== "setup" || typeof Players === "undefined" || !Players.GetLocalPlayerPortraitUnit) {
            return;
        }
        var unitIndex = Number(Players.GetLocalPlayerPortraitUnit());
        if (unitIndex > 0 && (force || unitIndex !== lastNativePurchaseTarget)) {
            lastNativePurchaseTarget = unitIndex;
            lastNativePurchaseHero = "";
            GameEvents.SendCustomGameEventToServer("rpg_native_purchase_target", { unit_index: unitIndex });
        }
    }

    function heartbeatNativePurchaseTarget() {
        // 原版选中状态事件会强制刷新；此处只补一次延迟刷新，避免在工具测试的同步 Schedule
        // 实现中递归调用，同时覆盖服务端刚重置目标的短窗口。
        syncNativePurchaseTarget(true);
    }

    function sendNativePurchaseHero(heroName, force) {
        heroName = String(heroName || "");
        if (phase !== "setup" || !heroName || (!force && heroName === lastNativePurchaseHero)) {
            return;
        }
        lastNativePurchaseHero = heroName;
        GameEvents.SendCustomGameEventToServer("rpg_native_purchase_target", { hero: heroName });
    }

    // CEM object keys can arrive in any order; rule/condition/priority arrays keep their order.
    function ruleSnapshot(value) {
        return JSON.stringify(value, function (key, child) {
            if (!child || typeof child !== "object" || Array.isArray(child)) { return child; }
            var ordered = {};
            Object.keys(child).sort().forEach(function (name) { ordered[name] = child[name]; });
            return ordered;
        });
    }

    // Bind to one hero, row and action. Identical refresh snapshots retain row objects;
    // actual replacement, reordering or concurrent edits invalidate this binding.
    function bindRuleEdit(side, heroIndex, index) {
        var entry = heroSlots[side.toLowerCase() + "_" + (heroIndex + 1)];
        var rule = getRules(side, heroIndex)[index];
        var snapshot = ruleSnapshot(rule);
        var actionDetail = rule && getActionDetail(side, heroIndex, rule.action);
        return function () {
            var live = heroSlots[side.toLowerCase() + "_" + (heroIndex + 1)];
            return canEditHeroRules(side, heroIndex) && entry && live && rule
                && live.name === entry.name && live.rule_key === entry.rule_key && live.hero_index === entry.hero_index
                && getRules(side, heroIndex)[index] === rule && ruleSnapshot(rule) === snapshot
                && getActionDetail(side, heroIndex, rule.action) === actionDetail;
        };
    }

    function getSelectedRules(side) {
        return getRules(side, selectedHeroIndex[side]);
    }

    function setAbilityImage(panel, abilityName) {
        if (abilityName && abilityName !== "" && abilityName !== "attack") {
            panel.abilityname = abilityName;
            panel.SetHasClass("Empty", false);
        } else {
            panel.abilityname = "";
            panel.SetHasClass("Empty", true);
        }
    }

    // CEM 事件里的数组会变成 {1:..,2:..} 对象，统一转回数组

    function createLabel(parent, className, text) {
        var label = $.CreatePanel("Label", parent, "");
        label.AddClass(className);
        label.text = text || "";
        return label;
    }


    function localizeFormat(token, value) {
        return $.Localize(token).replace("%s1", String(value));
    }

    function localizeHeroName(heroName) {
        var token = "#" + heroName;
        var localized = $.Localize(token);
        if (localized && localized !== token && localized !== heroName) {
            return localized;
        }
        return heroName.replace("npc_dota_hero_", "").replace(/_/g, " ");
    }

    function createMoveButton(parent, side, index, direction, text) {
        var button = $.CreatePanel("Button", parent, side + direction + index);
        button.AddClass("MoveButton");
        createLabel(button, "MoveGlyph", text);
        button.SetPanelEvent("onactivate", function () {
            moveRule(side, index, direction === "Up" ? -1 : 1);
        });
        return button;
    }

    function getRuleCapability(side, heroIndex, action) {
        if (typeof RpgAbilityCapabilities === "undefined") { return null; }
        var entry=heroSlots[side.toLowerCase()+"_"+(heroIndex+1)];
        return entry ? RpgAbilityCapabilities.get(entry.hero_index,action,entry.rule_key,entry.capability_revision) : null;
    }

    function createRuleRows(side) {
        var container = $("#" + side + "Rules");
        for (var index = rowPanels[side].length; index < getSelectedRules(side).length; index++) {
            var row = $.CreatePanel("Panel", container, side + "Rule" + index);
            row.AddClass("RuleRow");
            (function (idx) {
                var actionIcon = $.CreatePanel("Button", row, side + "ActionSelect" + idx);
                actionIcon.AddClass("ActionIcon");
                var abilityImage = $.CreatePanel("DOTAAbilityImage", actionIcon, side + "ActionAbility" + idx);
                abilityImage.AddClass("ActionAbilityImage");
                abilityImage.hittest = false;
                var actionFallback = createLabel(actionIcon, "ActionName", "");
                actionFallback.hittest = false;
                actionIcon.SetPanelEvent("onactivate", function () {
                    if (canEditHeroRules(side,selectedHeroIndex[side])) {
                        openActionMenu(side, idx);
                    }
                });
                var settingsButton = $.CreatePanel("Button", row, side + "RuleSettings" + idx);
                settingsButton.AddClass("RuleSettingsButton");
                createLabel(settingsButton, "", $.Localize("#dota2_rpg_v2_settings"));
                var diagnosticLabel=createLabel(settingsButton,"RuleDiagnostic","");
                diagnosticLabel.AddClass("RuleDiagnostic");
                settingsButton.SetPanelEvent("onactivate", function () {
                    if (phase !== "setup") { return; }

                    closeEditorMenus();
                    var editingHeroIndex = selectedHeroIndex[side];
                    var editIsCurrent = bindRuleEdit(side, editingHeroIndex, idx);
                    var authored = getRules(side, editingHeroIndex)[idx];
                    RpgConditionCatalog.open(authored, RpgRuleSync.initialSettings(authored), function (draft) {
                        if (!editIsCurrent()) { return false; }
                        delete authored.min_aoe_hits;
                        Object.keys(draft).forEach(function (key) { authored[key] = draft[key]; });
                        if (draft.target !== undefined) {
                            authored.target_attr = "distance";
                            authored.target_side = draft.target === "self" ? "self" : draft.target.indexOf("ally_") === 0 ? "ally_nearest" : "nearest";
                        }
                        var first = draft.use_conditions[0] || {type:"always"};
                        authored.condition = first.type || "always";
                        authored.value = first.seconds !== undefined ? first.seconds : first.value !== undefined ? first.value : 50;
                        renderSide(side);
                        sendRuleToServer(side,editingHeroIndex,idx);
                    }, {getCapability:typeof RpgAbilityCapabilities === "undefined" ? undefined : function() { return getRuleCapability(side,editingHeroIndex,authored.action); },abilityName:getActionDetail(side,editingHeroIndex,authored.action),actionHeroes:actionHeroes(side,editingHeroIndex),targetActors:targetActors(side,editingHeroIndex),getTargetActors:function () { return targetActors(side,editingHeroIndex); },readOnly:!canEditHeroRules(side,editingHeroIndex)});
                });
                var upButton = createMoveButton(row, side, idx, "Up", "^");
                var downButton = createMoveButton(row, side, idx, "Down", "v");
                var deleteButton = $.CreatePanel("Button", row, side + "DeleteRule" + idx);
                deleteButton.AddClass("DeleteRuleButton");
                createLabel(deleteButton, "DeleteGlyph", "X");
                deleteButton.SetPanelEvent("onactivate", function () {
                    if (phase === "setup" && idx > 0) {
                        deleteRule(side, idx);
                    }
                });
                deleteButton.enabled = idx > 0;
                var addButton = $.CreatePanel("Button", row, side + "AddRule" + idx);
                addButton.AddClass("AddRuleButton");
                createLabel(addButton, "AddGlyph", "+");
                addButton.SetPanelEvent("onactivate", function () {
                    if (phase === "setup") {
                        addRuleAtEnd(side);
                    }
                });
                addButton.enabled = idx === 0;
                var actionMenu = $.CreatePanel("Panel", row, side + "ActionMenu" + idx);
                actionMenu.AddClass("ActionMenu");
                actionMenu.AddClass("Hidden");
                rowPanels[side].push({
                    settingsButton: settingsButton,
                    diagnosticLabel:diagnosticLabel,
                    actionSelect: actionIcon,
                    actionMenu: actionMenu,
                    actionAbilityImage: abilityImage,
                    actionFallback: actionFallback,
                    deleteButton: deleteButton,
                    addButton: addButton,
                    row: row,
                    upButton: upButton,
                    downButton: downButton
                });
            }(index));
        }
    }

    function closeEditorMenus() {
        var sides = ["Radiant"];
        for (var sideIndex = 0; sideIndex < sides.length; sideIndex++) {
            var side = sides[sideIndex];
            for (var index = 0; index < rowPanels[side].length; index++) {
                var panels = rowPanels[side][index];
                if (panels.actionMenu) {
                    panels.actionMenu.SetHasClass("Hidden", true);
                }
                panels.row.SetHasClass("MenuOpen", false);
            }
        }
    }

    // Anchor menus to rendered buttons, including HUD scale and rule-list scrolling.
    function positionEditorMenu(menu, layer, anchor) {
        var scaleX = layer.actualuiscale_x || 1;
        var scaleY = layer.actualuiscale_y || 1;
        var origin = layer.GetPositionWithinWindow();
        var position = anchor.GetPositionWithinWindow();
        var width = 300;
        var height = 300;
        var layerWidth = layer.actuallayoutwidth / scaleX;
        var layerHeight = layer.actuallayoutheight / scaleY;
        var left = (position.x - origin.x) / scaleX;
        var top = (position.y - origin.y + anchor.actuallayoutheight) / scaleY;
        if (top + height > layerHeight) {
            top = (position.y - origin.y) / scaleY - height;
        }
        menu.style.marginLeft = Math.max(0, Math.min(left, layerWidth - width)) + "px";
        menu.style.marginTop = Math.max(0, Math.min(top, layerHeight - height)) + "px";
    }

    function openDropdownMenu(side, index) {
        var panels = rowPanels[side][index];
        var menu = panels.actionMenu;
        var layer = $("#DropdownLayer");
        if (!menu || !layer) {
            return menu;
        }
        menu.SetParent(layer);
        positionEditorMenu(menu, layer, panels.actionSelect);
        menu.SetHasClass("Hidden", false);
        return menu;
    }

    var ROW_HEIGHT = 62;

    function openActionMenu(side, index) {
        var panels = rowPanels[side][index];
        var menu = panels.actionMenu;
        if (menu == null) {
            return;
        }
        var layer = $("#DropdownLayer");
        if (layer) {
            menu.SetParent(layer);
        }
        // 动态填充：该英雄全部可用动作（可重复选择）
        menu.RemoveAndDeleteChildren();
        var menuGeneration = ruleGeneration;
        var actions = getSlotActions(side, selectedHeroIndex[side]);
        for (var i = 0; i < actions.length; i++) {
            (function (actionKey) {
                var option = $.CreatePanel("Button", menu, "ActionOpt_" + side + index + "_" + actionKey);
                option.AddClass("ActionOption");
                var detail = getActionDetail(side, selectedHeroIndex[side], actionKey);
                if (actionKey !== "attack" && detail) {
                    var image = $.CreatePanel(detail.indexOf("item_") === 0 ? "DOTAItemImage" : "DOTAAbilityImage", option, "");
                    image.AddClass("ActionOptionImage");
                    image.hittest = false;
                    if (detail.indexOf("item_") === 0) {
                        image.itemname = detail;
                    } else {
                        image.abilityname = detail;
                    }
                }
                var text = actionKey !== "attack" && detail
                    ? RpgConditionCatalog.abilityLabel(detail)
                    : $.Localize(ACTION_TOKENS[actionKey] || actionKey);
                var label = createLabel(option, "ActionOptionLabel", text);
                label.hittest = false;
                option.SetPanelEvent("onactivate", function () {
                    if (menuGeneration !== ruleGeneration) { return; }
                    chooseAction(side, index, actionKey);
                });
            }(actions[i]));
        }
        var shouldOpen = menu.BHasClass("Hidden");
        closeEditorMenus();
        if (shouldOpen) {
            openDropdownMenu(side, index);
        }
        panels.row.SetHasClass("MenuOpen", shouldOpen);
    }

    function chooseAction(side, index, actionKey) {
        var rules = getSelectedRules(side);
        if (!rules[index]) {
            return;
        }
        if (typeof RpgAbilityCapabilities === "undefined") {
            if (rules[index].action !== actionKey) { rules[index].destination = "target"; }
            rules[index].action=actionKey; closeEditorMenus();
            sendRuleToServer(side,selectedHeroIndex[side],index); renderSide(side); return;
        }
        var heroIndex=selectedHeroIndex[side], original=rules[index];
        var editIsCurrent=bindRuleEdit(side,heroIndex,index);
        var chosenActionDetail=getActionDetail(side,heroIndex,actionKey);
        // Selecting an action starts from its recommended configuration, so
        // conditions and switch settings from the previous skill cannot leak.
        var next={action:actionKey,enabled:original.enabled,condition:"always",value:50,
            target:"enemy_distance_nearest",target_team:"enemy",destination:"target",
            use_conditions:[],target_filters:[],target_priorities:[{type:"nearest"}],forced:false,
            cast_preference:"auto",desired_toggle_state:null,desired_autocast_state:null,
            state_policy:"fixed",cast_variant:"default",allow_unverified_modifiers:false};
        var recommended=typeof RpgSkillPresets!=="undefined" && chosenActionDetail
            ? RpgSkillPresets.get(chosenActionDetail) : null;
        if (recommended) { Object.keys(recommended).forEach(function(key) { next[key]=recommended[key]; }); }
        var selectedCapability=getRuleCapability(side,heroIndex,actionKey);
        if (selectedCapability && selectedCapability.teams && selectedCapability.teams[next.target_team]===0) {
            next.target_team=["enemy","ally","self"].filter(function(team) { return selectedCapability.teams[team]===1; })[0] || "enemy";
            next.target=next.target_team==="self" ? "self" : next.target_team+"_distance_nearest";
        }
        delete next.min_aoe_hits;
        closeEditorMenus();
        // A skill switch is a draft, not a saved mutation. Cancelling preserves the old rule.
        RpgConditionCatalog.open(next,RpgRuleSync.initialSettings(next),function(draft) {
            if (!editIsCurrent() || getActionDetail(side,heroIndex,actionKey)!==chosenActionDetail) { return false; }
            Object.keys(draft).forEach(function(key) { next[key]=draft[key]; });
            // Persist a native ability identity, not a slot which can later be replaced.
            var chosenCapability=getRuleCapability(side,heroIndex,actionKey);
            if (/^ability_\d+$/.test(actionKey) || actionKey==="ultimate") {
                if (chosenCapability && chosenCapability.name) { next.action=chosenCapability.name; }
            }
            var first=next.use_conditions[0] || {type:"always"}; next.condition=first.type || "always";
            next.value=first.seconds!==undefined ? first.seconds : first.value!==undefined ? first.value : 50;
            Object.keys(original).forEach(function(key) { delete original[key]; });
            Object.keys(next).forEach(function(key) { original[key]=next[key]; });
            renderSide(side); sendRuleToServer(side,heroIndex,index);
        },{abilityName:getActionDetail(side,heroIndex,actionKey),
            getCapability:function() { return getRuleCapability(side,heroIndex,actionKey); },
            actionHeroes:actionHeroes(side,heroIndex),getTargetActors:function() { return targetActors(side,heroIndex); },
            readOnly:!canEditHeroRules(side,heroIndex)});
    }

    function deleteRule(side, index) {
        var rules = getSelectedRules(side);
        if (rules.length <= 1) {
            return; // 至少保留一条规则（系统兜底始终存在）
        }
        closeEditorMenus();
        rules.splice(index, 1);
        renderSide(side);
        syncHeroRules(side);
    }

    // Keep the convenient action selection, but start every new row unconfigured.
    function addRuleAtEnd(side) {
        var rules = getSelectedRules(side);
        if (rules.length >= MAX_RULE_ROWS) {
            return;
        }
        var last = rules[rules.length - 1];
        rules.push({
            action: last ? last.action : "attack", enabled: true,
            condition: "always", value: 50,
            target_team: last && last.target_team ? last.target_team : "enemy",
            use_conditions: [], target_filters: [], target_priorities: [],
            approach: "range_only", forced: false
        });
        renderSide(side);
        syncHeroRules(side);
    }

    function moveRule(side, index, offset) {
        if (phase !== "setup") {
            return;
        }
        var rules = getSelectedRules(side);
        var nextIndex = index + offset;
        if (nextIndex < 0 || nextIndex >= rules.length) {
            return;
        }

        var current = rules[index];
        rules[index] = rules[nextIndex];
        rules[nextIndex] = current;
        renderSide(side);
        syncHeroRules(side);
    }

    function selectHero(side, index) {
        if (index < 0 || index >= HEROES[side].length) {
            return;
        }
        if (side === "Radiant") {
            selectNativeHero(HEROES.Radiant[index].name);
        }
        if (selectedHeroIndex[side] === index) {
            if (side === "Radiant" && HEROES.Radiant[index]) {
                selectedEquipmentHeroName = HEROES.Radiant[index].name;
                sendNativePurchaseHero(selectedEquipmentHeroName, true);
                renderItemShop();
            }
            return;
        }
        closeEditorMenus();
        selectedHeroIndex[side] = index;
        renderSide(side);
        // 装备目标与行动面板使用同一名上阵英雄；切换头像后无需重新上阵/刷新。
        if (side === "Radiant") {
            selectedEquipmentHeroName = HEROES.Radiant[index] ? HEROES.Radiant[index].name : selectedEquipmentHeroName;
            sendNativePurchaseHero(selectedEquipmentHeroName, true);
            renderItemShop();
        }
    }

    function wireHeroPortraits(side) {
        for (var index = 0; index < HEROES[side].length; index++) {
            (function (heroIndex) {
                $("#" + HEROES[side][heroIndex].panelId).SetPanelEvent("onactivate", function () {
                    selectHero(side, heroIndex);
                });
            }(index));
        }
    }

    function updateHeroSelection(side) {
        var heroes = HEROES[side];
        if (!heroes || !heroes.length) {
            // 尚未购买/上阵英雄时英雄条为空，仅显示提示
            $("#" + side + "SelectedHero").text = side === "Radiant"
                ? $.Localize("#dota2_rpg_no_lineup")
                : "";
            return;
        }
        for (var index = 0; index < heroes.length; index++) {
            $("#" + heroes[index].panelId).SetHasClass("Selected", selectedHeroIndex[side] === index);
        }
        var selectedHero = heroes[selectedHeroIndex[side]];
        if (selectedHero) {
            $("#" + side + "SelectedHero").text = localizeHeroName(selectedHero.name);
        }
    }

    function renderSide(side) {
        if (side !== "Radiant") { return; }
        var locked = !canEditHeroRules(side,selectedHeroIndex[side]);
        var hidePanels = phase !== "setup";
        var rules = getSelectedRules(side);
        createRuleRows(side);
        for (var index = 0; index < rowPanels[side].length; index++) {
            var panels = rowPanels[side][index];
            // Only authored rules occupy the list; unused pooled panels stay hidden.
            panels.row.SetHasClass("Hidden", index >= rules.length);
            if (index >= rules.length) {
                continue;
            }
            var definition = rules[index];
            var heroIndex = selectedHeroIndex[side];
            var detailName = getActionDetail(side, heroIndex, definition.action);
            var available = getSlotActions(side, heroIndex).indexOf(definition.action) >= 0;
            panels.actionSelect.SetHasClass("UnavailableAction", !available);
            if (panels.actionAbilityImage) {
                setAbilityImage(panels.actionAbilityImage,
                    definition.action !== "attack" ? detailName : "");
            }
            if (!available) {
                panels.actionFallback.text = $.Localize("#dota2_rpg_v2_unavailable");
            } else if (definition.action === "attack") {
                panels.actionFallback.text = $.Localize("#dota2_rpg_action_attack");
            } else if (!detailName || detailName === "") {
                panels.actionFallback.text = $.Localize(ACTION_TOKENS[definition.action] || definition.action);
            } else {
                panels.actionFallback.text = "";
            }
            panels.settingsButton.enabled = !hidePanels;
            panels.actionSelect.enabled = !locked;
            panels.settingsButton.SetHasClass("HasAdvancedSettings", Array.isArray(definition.use_conditions));
            if (typeof RpgRuleDiagnostics!=="undefined") {
                var diagEntry=heroSlots[side.toLowerCase()+"_"+(heroIndex+1)];
                if (diagEntry) { RpgRuleDiagnostics.bind(panels.diagnosticLabel,diagEntry.hero_index,diagEntry.rule_key,index+1,detailName || definition.action); }
            }


            panels.upButton.enabled = !locked && index > 0;
            panels.downButton.enabled = !locked && index < rules.length - 1;
            if (panels.deleteButton) {
                panels.deleteButton.enabled = !locked && index > 0;
                panels.deleteButton.SetHasClass("Hidden", index === 0 || phase !== "setup");
            }
            if (panels.addButton) {
                panels.addButton.enabled = !locked && index === 0 && rules.length < MAX_RULE_ROWS;
                panels.addButton.SetHasClass("Hidden", index !== 0 || phase !== "setup");
            }
        }
        $("#" + side + "Editor").SetHasClass("Hidden", hidePanels);
        $("#" + side + "Editor").SetHasClass("Locked", locked);
        updateHeroSelection(side);
        applyRuleScroll(side);
    }

    function sendRuleToServer(side, heroIndex, ruleIndex) {
        if (typeof RpgRuleSync === "undefined" || !canEditHeroRules(side,heroIndex)) {
            return;
        }
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var entry = heroSlots[key];
        if (!entry || entry.hero_index === undefined
                || (HEROES[side][heroIndex] && HEROES[side][heroIndex].name !== entry.name)) {
            return;
        }
        var rules = getRules(side, heroIndex);
        var rule = rules[ruleIndex] || {
            action: "attack",
            condition: "always",
            value: 50,
            target: "enemy_distance_nearest",
            target_attr: "distance",
            target_side: "nearest",
            forced: false,
            enabled: false
        };
        rules._authored = true;
        RpgRuleSync.sendRule({
            heroIndex: entry.hero_index,
            heroName: entry.name,
            heroKey: entry.rule_key,
            slot: ruleIndex + 1,
            ruleCount: rules.length,
            rule: rule,
            actionId: rule.action,
            actionName: rule.action === "attack" ? "" : getActionDetail(side, heroIndex, rule.action)
        });
    }

    function syncHeroRules(side) {
        var heroIndex = selectedHeroIndex[side];
        for (var index=0;index<getRules(side,heroIndex).length;index++) { sendRuleToServer(side,heroIndex,index); }
    }

    function buildPayload() {


        return {};
    }

    function setStatus(token) {
        var text = $.Localize(token);
        $("#BattleStatus").text = text;
        $("#ControlStatus").text = text;
    }

    // CEM 载荷不传输数组：服务端用分号分隔字符串，这里拆回数组
    function splitList(text) {
        if (!text || text === "") {
            return [];
        }
        return String(text).split(";");
    }

    // CEM 事件里的数组会变成 {1:..,2:..} 对象，统一转回数组
    function cemList(t) {
        var out = [];
        if (!t) {
            return out;
        }
        var keys = [];
        for (var k in t) {
            if (t.hasOwnProperty(k)) {
                keys.push(k);
            }
        }
        keys.sort(function (a, b) { return Number(a) - Number(b); });
        for (var i = 0; i < keys.length; i++) {
            out.push(t[keys[i]]);
        }
        return out;
    }

    // ---------------- 英雄商店 + 阵容（服务端权威，事件镜像） ----------------
    // 原版专属槽位：15 = 回城卷轴，16 = 中立装备。中立装备每个单位只有一个专属槽，
    // 不占物品栏/背包/储藏栏，因此它既不能按 0..14 的容量判断，也不能被 0..14 的枚举显示。
    var NEUTRAL_ITEM_SLOT = 16;
    var NATIVE_TP_SLOT = 15; // 回城卷轴槽：本模式不提供该装备，面板也不展示它

    function targetHasNeutralSlot(target) {
        var slots = (target && target.inventorySlots) || [];
        for (var slotIndex = 0; slotIndex < slots.length; slotIndex++) {
            if (Number(slots[slotIndex]) === NEUTRAL_ITEM_SLOT) { return false; }
        }
        return true;
    }
    var shopState = {
        gold: 500,
        offers: [],
        owned: [],
        lineup: [],
        neutralStock: {},
        stashFreeSlots: 0,
        neutralSlotFree: true,
        bench_slots: 0,
        costs: { hero: 500, refresh: 20, bench_slot: 200, bench_slot_max: 5, lineup_max: 5 },
        free_recruit_choices: 2
    };

    function onShopState(data) {
        if (!acceptRuleGeneration(data)) { return; }
        // Publish the authoritative wallet before optional inventory/menu rendering.
        if (data && data.gold !== undefined) { updateWalletLabel(data.gold); }
        updateRunLives(data);
        try {
            onShopStateInner(data);
        } catch (e) {
            $("#ControlStatus").text = "ShopStateErr: " + e;
        }
    }

    function updateRunLives(data) {
        if (!data || data.lives_remaining === undefined) { return; }
        var maximum = Math.max(1, Math.min(5, Math.floor(Number(data.max_lives) || 5)));
        var remaining = Math.max(0, Math.min(maximum, Math.floor(Number(data.lives_remaining) || 0)));
        var hearts = $("#RunHearts");
        hearts.RemoveAndDeleteChildren();
        for (var i = 0; i < maximum; i++) {
            var heart = $.CreatePanel("Label", hearts, "RunHeart" + i);
            heart.AddClass("RunHeart");
            heart.SetHasClass("RunHeartSpent", i >= remaining);
            heart.text = "♥";
            heart.hittest = false;
        }
        $("#RunLivesCount").text = remaining + " / " + maximum;
        $("#RunLivesHint").text = $.Localize(remaining === 0
            ? "#dota2_rpg_run_failed" : "#dota2_rpg_lives_hint");
    }

    function updateWalletLabel(gold) {
        var balance = Math.max(0, Math.floor(Number(gold) || 0));
        $("#WalletBalance").text = $.Localize("#dota2_rpg_wallet_balance") + " " + balance;
        var nativeWallet = GameUI.CustomUIConfig().RpgNativeShopWallet;
        if (nativeWallet) { nativeWallet.updateGold(balance); }
    }

    function updateShopEconomyLabels(gold) {
        updateWalletLabel(gold);
        $("#RefreshShopLabel").text = localizeFormat("#dota2_rpg_shop_refresh", shopState.costs.refresh);
        $("#BenchBuyLabel").text = localizeFormat("#dota2_rpg_bench_buy", shopState.costs.bench_slot);
    }

    function onShopStateInner(data) {
        if (!data) {
            data = shopState;
        }
        shopState.gold = Number(data.gold !== undefined ? data.gold : shopState.gold);
        // 报价："hero|level|quality|price"
        shopState.offers = [];
        var rawOffers = splitList(data.offer_text);
        for (var offerIndex = 0; offerIndex < rawOffers.length; offerIndex++) {
            var offerParts = rawOffers[offerIndex].split("|");
            if (offerParts.length >= 4) {
                shopState.offers.push({
                    hero: offerParts[0], level: Number(offerParts[1]),
                    quality: offerParts[2], price: Number(offerParts[3])
                });
            }
        }
        shopState.owned = splitList(data.owned_text);
        shopState.lineup = splitList(data.lineup_text);
        // Entity indices are replaced on every roster rebuild, including bench units.
        heroEntityIndices = data.hero_entity_indices || {};
        commanderIndex = Number(data.commander_index !== undefined ? data.commander_index : -1);
        if (shopState.lineup.length
            && (!selectedEquipmentHeroName || shopState.owned.indexOf(selectedEquipmentHeroName) < 0)) {
            selectedEquipmentHeroName = shopState.lineup[Math.min(selectedHeroIndex.Radiant, shopState.lineup.length - 1)];
            sendNativePurchaseHero(selectedEquipmentHeroName);
        }
        shopState.bench_slots = Number(data.bench_slots || 0);
        shopState.free_recruit_choices = Number(data.free_recruit_choices !== undefined ? data.free_recruit_choices : shopState.free_recruit_choices);
        // 个人等级/经验："name:level:xp:quality"
        saveData.heroes = saveData.heroes || {};
        var heroEntries = splitList(data.hero_data_text);
        for (var hIndex = 0; hIndex < heroEntries.length; hIndex++) {
            var hParts = heroEntries[hIndex].split(":");
            if (hParts.length >= 5) {
                saveData.heroes[hParts[0]] = {
                    level: Number(hParts[1]), xp: Number(hParts[2]),
                    quality: hParts[3], skill_points: Number(hParts[4])
                };
            }
        }
        if (data.refresh_cost !== undefined) {
            shopState.refresh_cost = Number(data.refresh_cost);
            shopState.costs.refresh = shopState.refresh_cost;
        }
        if (data.cost_bench_slot !== undefined) {
            shopState.costs.bench_slot = Number(data.cost_bench_slot);
        }
        if (data.bench_slot_max !== undefined) {
            shopState.costs.bench_slot_max = Number(data.bench_slot_max);
        }
        if (data.lineup_max !== undefined) {
            shopState.costs.lineup_max = Number(data.lineup_max);
        }
        shopState.scroll_low_remaining = Number(data.scroll_low_remaining || 0);
        shopState.scroll_high_remaining = Number(data.scroll_high_remaining || 0);
        shopState.stock = splitList(data.stock_text);
        // 中立装备按实体 ID 单独标记：面板要靠它决定用哪种容量去判断能否交付。
        shopState.neutralStock = {};
        var neutralStockEntries = splitList(data.stock_neutral_text);
        for (var neutralStockIndex = 0; neutralStockIndex < neutralStockEntries.length; neutralStockIndex++) {
            if (neutralStockEntries[neutralStockIndex]) {
                shopState.neutralStock[neutralStockEntries[neutralStockIndex]] = true;
            }
        }
        shopState.stashFreeSlots = Number(data.stash_free_slots !== undefined ? data.stash_free_slots : 0);
        shopState.neutralSlotFree = Number(data.neutral_slot_free !== undefined ? data.neutral_slot_free : 1) !== 0;
        shopState.grisGrisGold = Math.max(0, Number(data.gris_gris_gold) || 0);
        shopState.inventories = {};
        var invEntries = splitList(data.inventories_text);
        for (var invIndex = 0; invIndex < invEntries.length; invIndex++) {
            var invParts = invEntries[invIndex].split(":");
            if (invParts.length >= 2) {
                saveData.heroes[invParts[0]] = saveData.heroes[invParts[0]] || { level: 1, xp: 0, quality: "common" };
                saveData.heroes[invParts[0]].inventory = invParts[1] === "" ? [] : invParts[1].split(",");
                saveData.heroes[invParts[0]].inventoryIds = [];
                saveData.heroes[invParts[0]].inventorySlots = [];
            }
        }
        // 实体 ID 只用于精确的卸下请求；名称仍用于展示和旧服务器兼容。
        var equippedEntries = splitList(data.equipped_text);
        for (var equippedIndex = 0; equippedIndex < equippedEntries.length; equippedIndex++) {
            var equippedParts = equippedEntries[equippedIndex].split(":");
            if (equippedParts.length >= 2) {
                var equippedHero = equippedParts[0];
                var equippedItems = equippedParts[1] === "" ? [] : equippedParts[1].split(",");
                var names = [];
                var ids = [];
                var slots = [];
                for (var equippedItemIndex = 0; equippedItemIndex < equippedItems.length; equippedItemIndex++) {
                    var equippedItem = equippedItems[equippedItemIndex].split("|");
                    if (equippedItem[0]) {
                        names.push(equippedItem[0]);
                        ids.push(equippedItem[1] || "");
                        slots.push(equippedItem.length >= 3 ? Number(equippedItem[2]) : equippedItemIndex);
                    }
                }
                saveData.heroes[equippedHero] = saveData.heroes[equippedHero] || { level: 1, xp: 0, quality: "common" };
                saveData.heroes[equippedHero].inventory = names;
                saveData.heroes[equippedHero].inventoryIds = ids;
                saveData.heroes[equippedHero].inventorySlots = slots;
            }
        }
        shopState.scroll_low_stock = Number(data.scroll_low_stock || 0);
        shopState.scroll_high_stock = Number(data.scroll_high_stock || 0);
        saveData.gold = shopState.gold;
        saveData.owned = shopState.owned;
        saveData.lineup = shopState.lineup;
        saveData.bench_slots = shopState.bench_slots;
        saveData.scrolls = { low: shopState.scroll_low_stock, high: shopState.scroll_high_stock };
        saveData.item_stock = shopState.stock.map(function (entry) {
            return entry.split("|")[0];
        });
        renderShop();
        renderLineupStrip();
        renderRadiantHeroStrip();
        updateShopEconomyLabels(shopState.gold);
        updateScrollLabels();
        renderItemShop();
        updateTeamLevelLabels();
    }

    function renderShop() {
        try {
            renderShopInner();
        } catch (e) {
            $("#ShopHeader").text = "ShopErr: " + e;
        }
    }

    function renderShopInner() {
        var container = $("#ShopOffer");
        container.RemoveAndDeleteChildren();
        for (var index = 0; index < shopState.offers.length; index++) {
            (function (offer) {
                var heroName = offer.hero;
                var owned = false;
                for (var i = 0; i < shopState.owned.length; i++) {
                    if (shopState.owned[i] === heroName) {
                        owned = true;
                        break;
                    }
                }
                var slot = $.CreatePanel("Button", container, "Shop_" + heroName);
                slot.AddClass("ShopOfferSlot");
                slot.SetHasClass("Owned", owned);
                var portrait = $.CreatePanel("DOTAHeroImage", slot, "");
                portrait.AddClass("ShopPortrait");
                portrait.heroname = heroName;
                portrait.heroimagestyle = "portrait";
                var qualityNames = { common: "普通", fine: "精良", epic: "史诗", legendary: "传说" };
                var qualityColors = { common: "#c8d2d7", fine: "#6fc3ff", epic: "#c88bff", legendary: "#ffcc55" };
                createLabel(slot, "ShopName", "Lv" + offer.level + " " + qualityNames[offer.quality]);
                var isFree = shopState.free_recruit_choices > 0;
                var priceLabel = createLabel(slot, "ShopPrice", isFree ? "免费（余" + shopState.free_recruit_choices + "）" : offer.price + "g");
                priceLabel.style.color = isFree ? "#8ee6a8" : (qualityColors[offer.quality] || "#f2d982");
                if (!owned) {
                    slot.SetPanelEvent("onactivate", function () {
                        GameEvents.SendCustomGameEventToServer("rpg_shop_buy", { hero: heroName });
                    });
                    slot.enabled = isFree || shopState.gold >= offer.price;
                } else {
                    slot.enabled = false;
                }
            }(shopState.offers[index]));
        }
        $("#ShopHeader").text = $.Localize("#dota2_rpg_shop_title");
    }

    function wireShopButtons() {
        var refresh = $("#RefreshShopButton");
        refresh.SetPanelEvent("onactivate", function () {
            GameEvents.SendCustomGameEventToServer("rpg_shop_refresh", {});
        });
        var bench = $("#BenchBuyButton");
        bench.SetPanelEvent("onactivate", function () {
            GameEvents.SendCustomGameEventToServer("rpg_bench_buy", {});
        });
        var fixUi = GameUI.CustomUIConfig().RpgIssueFixUI;
        ["Radiant"].forEach(function (side) {
            fixUi.bindActionPanel({
                panel: $("#" + side + "Editor"),
                button: $("#" + side + "CollapseButton"),
                label: $("#" + side + "CollapseLabel"),
                restoreButton: $("#" + side + "RestoreButton"),
                onToggle: closeEditorMenus
            });
        });
        fixUi.makeHeroShopTransparent($("#ShopPanel"));
    }

    // ---------------- 装备购买与转移：固定目标 + 直接装备 ----------------
    function getSelectedEquipmentTarget() {
        var owned = shopState.owned || [];
        if (!owned.length) {
            return null;
        }
        var lineup = shopState.lineup || [];
        if (!selectedEquipmentHeroName || owned.indexOf(selectedEquipmentHeroName) < 0) {
            selectedEquipmentHeroName = lineup.length ? lineup[0] : owned[0];
        }
        var heroName = selectedEquipmentHeroName;
        sendNativePurchaseHero(heroName);
        var heroData = saveData.heroes[heroName] || {};
        var inventorySlots = heroData.inventorySlots || [];
        var activeCount = 0;
        for (var slotIndex = 0; slotIndex < inventorySlots.length; slotIndex++) {
            if (Number(inventorySlots[slotIndex]) >= 0 && Number(inventorySlots[slotIndex]) <= 5) {
                activeCount += 1;
            }
        }
        return {
            name: heroName,
            index: owned.indexOf(heroName),
            lineupIndex: lineup.indexOf(heroName),
            isBench: lineup.indexOf(heroName) < 0,
            inventory: heroData.inventory || [],
            inventoryIds: heroData.inventoryIds || [],
            inventorySlots: inventorySlots,
            activeCount: activeCount
        };
    }

    function setEquipmentTarget(heroName) {
        heroName = String(heroName || "");
        if (!heroName || (shopState.owned || []).indexOf(heroName) < 0) {
            return;
        }
        selectedEquipmentHeroName = heroName;
        sendNativePurchaseHero(heroName, true);
        var lineupIndex = (shopState.lineup || []).indexOf(heroName);
        if (lineupIndex >= 0 && selectedHeroIndex.Radiant !== lineupIndex) {
            selectHero("Radiant", lineupIndex);
        } else {
            selectNativeHero(heroName);
            renderItemShop();
        }
    }

    function itemDisplayName(itemName) {
        var name = String(itemName || "");
        // 原版物品名有本地化 token（中立装备与附魔同样有）；取不到才退回拆词，
        // 否则转交面板会对着一件原生装备显示英文原名。
        var token = "#DOTA_Tooltip_ability_" + name;
        var localized = $.Localize(token);
        if (localized && localized !== token && localized !== name) { return localized; }
        return name.replace("item_", "").replace(/_/g, " ");
    }

    function createItemIcon(parent, itemName) {
        var icon = $.CreatePanel("DOTAAbilityImage", parent, "");
        icon.AddClass("ItemIcon");
        icon.abilityname = itemName;
        return icon;
    }

    function setItemSellNotice(reason, refund, success) {
        var notice = $("#ItemSellNotice");
        var text = $.Localize("#dota2_rpg_item_sell_" + reason);
        notice.text = success ? text.replace("{refund}", String(refund)) : text;
        notice.SetHasClass("Hidden", false);
        notice.SetHasClass("Success", Boolean(success));
        notice.SetHasClass("Error", reason !== "pending" && !success);
    }

    function createItemSellButton(row, heroName, itemName, itemId) {
        var entityId = Number(itemId);
        var validId = isFinite(entityId) && entityId > 0 && Math.floor(entityId) === entityId;
        var button = $.CreatePanel("Button", row, "Sell_" + row.id);
        button.AddClass("ItemRowBtn");
        button.AddClass("ItemSellBtn");
        createLabel(button, "", $.Localize(itemName === "item_grisgris"
            ? "#dota2_rpg_gris_gris_redeem" : "#dota2_rpg_item_sell"));
        button.enabled = phase === "setup" && validId && !pendingItemSales[entityId];
        button.SetPanelEvent("onactivate", function () {
            if (phase !== "setup" || !validId || pendingItemSales[entityId]) {
                return;
            }
            var requestId = ++itemSellRequestId;
            pendingItemSales[entityId] = requestId;
            button.enabled = false;
            setItemSellNotice("pending", 0, false);
            GameEvents.SendCustomGameEventToServer("rpg_item_sell", {
                hero: heroName,
                item: itemName,
                item_index: entityId,
                request_id: requestId
            });
            renderItemShop();
        });
    }

    function onItemSellResult(data) {
        var requestId = Number(data.request_id);
        var entityId = Number(data.item_index);
        // A duplicate or stale reply must not unlock a newer sale of this item.
        if (pendingItemSales[entityId] !== requestId) {
            return;
        }
        delete pendingItemSales[entityId];
        if (requestId === itemSellRequestId) {
            var success = Number(data.ok) === 1;
            var reasons = ["wrong_phase", "invalid_item", "not_owned", "not_sellable",
                "purchase_pending", "sale_failed", "unavailable"];
            var reason = success ? "sold" : (reasons.indexOf(data.reason) >= 0 ? data.reason : "unavailable");
            // Only the authoritative shop state updates gold; show the native wallet delta verbatim.
            setItemSellNotice(reason, data.refund, success);
        }
        renderItemShop();
    }

    function onItemTransferResult(data) {
        var notice = $("#ItemTransferNotice");
        if (!notice) { return; }
        var success = Number(data.ok) === 1;
        notice.text = success ? $.Localize("#dota2_rpg_item_transfer_done")
            .replace("{hero}", localizeHeroName(String(data.hero_name || "")))
            .replace("{item}", itemDisplayName(data.item_name))
            : String(data.message || $.Localize("#dota2_rpg_item_transfer_failed"));
        notice.SetHasClass("Hidden", false);
        notice.SetHasClass("Success", success);
        notice.SetHasClass("Error", !success);
    }

    function renderItemTarget(target) {
        var label = $("#ItemTargetLabel");
        var heroes = $("#ItemTargetHeroes");
        var equipped = $("#ItemEquippedList");
        heroes.RemoveAndDeleteChildren();
        equipped.RemoveAndDeleteChildren();

        if (!target) {
            label.text = $.Localize("#dota2_rpg_item_target_none");
            label.SetHasClass("Empty", true);
            createLabel(equipped, "ItemRowName", $.Localize("#dota2_rpg_item_target_none"));
            return;
        }

        label.SetHasClass("Empty", false);
        label.text = $.Localize("#dota2_rpg_item_target") + "：" + localizeHeroName(target.name)
            + (target.isBench ? "（待命）" : "") + " " + target.activeCount + "/6";

        for (var heroIndex = 0; heroIndex < shopState.owned.length; heroIndex++) {
            (function (index, heroName) {
                var portrait = $.CreatePanel("DOTAHeroImage", heroes, "ItemTarget_" + heroName);
                portrait.AddClass("ItemTargetPortrait");
                portrait.heroname = heroName;
                portrait.heroimagestyle = "portrait";
                portrait.SetHasClass("Selected", heroName === target.name);
                portrait.SetPanelEvent("onactivate", function () {
                    setEquipmentTarget(heroName);
                });
            }(heroIndex, shopState.owned[heroIndex]));
        }

        if (!target.inventory.length) {
            createLabel(equipped, "ItemRowName", $.Localize("#dota2_rpg_item_equipped_empty"));
            return;
        }

        for (var itemIndex = 0; itemIndex < target.inventory.length; itemIndex++) {
            (function (itemName, itemId, itemSlot, index) {
                // 15 是回城卷轴槽：本模式不需要回城卷轴，面板不展示也不转交它。
                if (!itemName || itemSlot < 0 || itemSlot > NEUTRAL_ITEM_SLOT || itemSlot === NATIVE_TP_SLOT) { return; }
                var row = $.CreatePanel("Panel", equipped, "Equipped_" + target.name + "_" + index);
                row.AddClass("ItemEquippedRow");
                row.AddClass("ItemInventoryCard");
                createItemIcon(row, itemName);
                var slotSuffix = itemSlot === NEUTRAL_ITEM_SLOT ? "（中立）"
                    : (itemSlot >= 9 ? " [储藏栏 " + itemSlot + "]"
                        : (itemSlot >= 6 ? " [背包 " + itemSlot + "]" : ""));
                var itemLabel = itemName === "item_grisgris"
                    ? $.Localize("#dota2_rpg_gris_gris_saved").replace("{gold}", String(shopState.grisGrisGold || 0))
                    : itemDisplayName(itemName) + slotSuffix;
                createLabel(row, "ItemRowName", itemLabel);
                var unequip = $.CreatePanel("Button", row, "Unequip_" + target.name + "_" + index);
                unequip.AddClass("ItemRowBtn");
                unequip.AddClass("ItemUnequipBtn");
                createLabel(unequip, "", $.Localize("#dota2_rpg_item_unequip"));
                unequip.SetPanelEvent("onactivate", function () {
                    GameEvents.SendCustomGameEventToServer("rpg_item_unequip", {
                        hero: target.name,
                        item: itemName,
                        item_index: itemId,
                        slot: itemSlot
                    });
                });
                unequip.enabled = itemName !== "item_grisgris" && phase === "setup" && Boolean(itemId)
                    && (itemSlot === NEUTRAL_ITEM_SLOT ? shopState.neutralSlotFree : shopState.stashFreeSlots > 0);
                createItemSellButton(row, target.name, itemName, itemId);
            }(target.inventory[itemIndex], target.inventoryIds[itemIndex] || "",
                Number(target.inventorySlots[itemIndex] !== undefined ? target.inventorySlots[itemIndex] : itemIndex), itemIndex));
        }
    }

    function renderItemShop() {
        var stock = cemList(shopState.stock);
        var target = getSelectedEquipmentTarget();
        var targetHasSpace = target && target.activeCount < 6;
        var scrollDefs = [
            { kind: "low", label: $.Localize("#dota2_rpg_scroll_low"),
              remaining: shopState.scroll_low_remaining, stockCount: shopState.scroll_low_stock,
              cost: 200 },
            { kind: "high", label: $.Localize("#dota2_rpg_scroll_high"),
              remaining: shopState.scroll_high_remaining, stockCount: shopState.scroll_high_stock,
              cost: 1000 }
        ];

        renderItemTarget(target);

        // Ordinary equipment comes from the native shop; transfer or sell its real instances here.
        var stockList = $("#ItemStockList");
        stockList.RemoveAndDeleteChildren();
        if (!stock.length) {
            createLabel(stockList, "ItemRowName", $.Localize("#dota2_rpg_item_stash_empty"));
        }
        for (var stockIndex = 0; stockIndex < stock.length; stockIndex++) {
            (function (entry, index) {
                var parts = entry.split("|");
                var itemName = parts[0];
                // 新协议是 name|entityId；兼容已热重载但尚未重开地图的旧 name|cost|entityId。
                var itemId = parts.length >= 3 ? parts[2] : (parts[1] || "");
                var isNeutralItem = shopState.neutralStock[itemId] === true;
                var row = $.CreatePanel("Panel", stockList, "Stock" + index);
                row.AddClass("ItemRow");
                row.AddClass("ItemInventoryCard");
                createItemIcon(row, itemName);
                createLabel(row, "ItemRowName", itemDisplayName(itemName) + (isNeutralItem ? "（中立）" : ""));
                var equip = $.CreatePanel("Button", row, "Equip" + index);
                equip.AddClass("ItemRowBtn");
                equip.AddClass("ItemEquipBtn");
                createLabel(equip, "", $.Localize("#dota2_rpg_item_equip"));
                equip.SetPanelEvent("onactivate", function () {
                    if (target) {
                        GameEvents.SendCustomGameEventToServer("rpg_item_equip", {
                            hero: target.name,
                            item: itemName,
                            item_index: itemId
                        });
                    }
                });
                equip.enabled = phase === "setup" && Boolean(target) && Boolean(itemId)
                    && (isNeutralItem ? targetHasNeutralSlot(target) : targetHasSpace);
                createItemSellButton(row, "__stash", itemName, itemId);
            }(stock[stockIndex], stockIndex));
        }

        // Only experience scrolls are purchased here; equipment is bought in the native shop.
        var scrollList = $("#ScrollShopList");
        scrollList.RemoveAndDeleteChildren();
        for (var scrollIndex = 0; scrollIndex < scrollDefs.length; scrollIndex++) {
            (function (def) {
                var row = $.CreatePanel("Panel", scrollList, "Scroll_" + def.kind);
                row.AddClass("ItemRow");
                createLabel(row, "ItemRowName", def.label + " x" + def.stockCount + "（余" + def.remaining + "）");
                createLabel(row, "ItemRowCost", def.cost + "g");
                var buy = $.CreatePanel("Button", row, "ScrollBuyBtn_" + def.kind);
                buy.AddClass("ItemRowBtn");
                buy.AddClass("ItemScrollBuyBtn");
                createLabel(buy, "", $.Localize("#dota2_rpg_scroll_buy"));
                buy.SetPanelEvent("onactivate", function () {
                    GameEvents.SendCustomGameEventToServer("rpg_scroll_buy", { kind: def.kind });
                });
                buy.enabled = phase === "setup" && def.remaining > 0 && shopState.gold >= def.cost;
                var use = $.CreatePanel("Button", row, "ScrollUseBtn_" + def.kind);
                use.AddClass("ItemRowBtn");
                use.AddClass("ItemEquipBtn");
                createLabel(use, "", $.Localize("#dota2_rpg_item_use"));
                use.SetPanelEvent("onactivate", function () {
                    if (target) {
                        GameEvents.SendCustomGameEventToServer("rpg_scroll_use", { kind: def.kind, hero: target.name });
                    }
                });
                use.enabled = phase === "setup" && def.stockCount > 0 && Boolean(target);
            }(scrollDefs[scrollIndex]));
        }
    }

    function updateScrollLabels() {
        // 卷轴购买/使用都已经在装备面板中基于当前装备目标渲染。
    }

    function renderLineupStrip() {
        var container = $("#LineupStrip");
        container.RemoveAndDeleteChildren();
        for (var index = 0; index < shopState.owned.length; index++) {
            (function (heroName) {
                var inLineup = false;
                for (var i = 0; i < shopState.lineup.length; i++) {
                    if (shopState.lineup[i] === heroName) {
                        inLineup = true;
                        break;
                    }
                }
                var portrait = $.CreatePanel("DOTAHeroImage", container, "Lineup_" + heroName);
                portrait.AddClass("HeroPortrait");
                portrait.heroname = heroName;
                portrait.heroimagestyle = "portrait";
                portrait.SetHasClass("Selected", inLineup);
                portrait.SetPanelEvent("onactivate", function () {
                    if (phase !== "setup") {
                        return;
                    }
                    var next = [];
                    var wasIn = false;
                    for (var j = 0; j < shopState.lineup.length; j++) {
                        if (shopState.lineup[j] === heroName) {
                            wasIn = true;
                            continue;
                        }
                        next.push(shopState.lineup[j]);
                    }
                    if (!wasIn && next.length < shopState.costs.lineup_max) {
                        next.push(heroName);
                    }
                    GameEvents.SendCustomGameEventToServer("rpg_lineup_set", { lineup_text: next.join(";") });
                });
            }(shopState.owned[index]));
        }
    }

    function renderRadiantHeroStrip() {
        var container = $("#RadiantHeroStrip");
        if (!container) {
            return;
        }
        container.RemoveAndDeleteChildren();
        HEROES.Radiant = [];
        for (var index = 0; index < shopState.lineup.length; index++) {
            (function (heroIndex, heroName) {
                var portrait = $.CreatePanel("DOTAHeroImage", container, "RadiantHeroDyn" + (heroIndex + 1));
                portrait.AddClass("HeroPortrait");
                portrait.heroname = heroName;
                portrait.heroimagestyle = "portrait";
                portrait.SetPanelEvent("onactivate", function () {
                    selectHero("Radiant", heroIndex);
                });
                HEROES.Radiant.push({ panelId: portrait.id, name: heroName });
            }(index, shopState.lineup[index]));
        }
        Object.keys(heroSlots).forEach(function (key) {
            if (key.indexOf("radiant_") === 0 && shopState.lineup.indexOf(heroSlots[key].name) < 0) {
                RpgRuleSync.forgetHero(heroSlots[key].rule_key);
            }
        });
        if (selectedHeroIndex.Radiant >= shopState.lineup.length) {
            selectedHeroIndex.Radiant = 0;
        }
        renderSide("Radiant");
    }

    // ---------------- 关卡选择（数据来自 CustomNetTables） ----------------
    var saveData = loadSave();
    var levelList = [];
    var currentLevelId = saveData.current_level || "ch01";

    function renderLevelList() {
        // 关卡按顺序推进，不再提供自由选择（进度显示在顶部）
    }

    // ---------------- 经验/挑战次数（无存档：状态仅存服务端内存） ----------------
    // 进度只在当前比赛的服务端内存中；这里仅保存服务端广播的镜像，绝不写入本地存储。
    function loadSave() {
        return {
            gold: 500,
            heroes: {},
            owned: [],
            lineup: [],
            bench_slots: 0,
            scrolls: { low: 0, high: 0 },
            item_stock: [],
            current_level: "ch01"
        };
    }

    // ---------------- 自绘规则列表滚动（按钮/滚轮/滑块） ----------------
    var RULE_VIEW_HEIGHT = 380;
    var RULE_SCROLL_STEP = 130;
    var ruleScroll = { Radiant: 0 };

    function ruleScrollMax(side) {
        return Math.max(0, getSelectedRules(side).length * ROW_HEIGHT - RULE_VIEW_HEIGHT);
    }

    function applyRuleScroll(side) {
        var pos = Math.max(0, Math.min(ruleScrollMax(side), ruleScroll[side]));
        ruleScroll[side] = pos;
        var container = $("#" + side + "Rules");
        if (container) {
            container.style.marginTop = -pos + "px";
            container.style.height = Math.max(RULE_VIEW_HEIGHT, getSelectedRules(side).length * ROW_HEIGHT) + "px";
        }
        var thumb = $("#" + side + "RulesScrollThumb");
        var track = $("#" + side + "RulesScrollTrack");
        if (thumb && track) {
            var maxScroll = ruleScrollMax(side);
            var trackH = 380 - 52 - 4; // 上下按钮占位后的轨道高度
            var thumbH = Math.max(48, Math.floor(trackH * RULE_VIEW_HEIGHT
                / Math.max(RULE_VIEW_HEIGHT, getSelectedRules(side).length * ROW_HEIGHT)));
            thumb.style.height = thumbH + "px";
            var thumbTop = maxScroll > 0 ? Math.floor((pos / maxScroll) * (trackH - thumbH)) : 0;
            thumb.style.marginTop = thumbTop + "px";
        }
        var rail = $("#" + side + "RulesScrollRail");
        if (rail) {
            rail.SetHasClass("Hidden", ruleScrollMax(side) <= 0);
        }
    }

    function scrollRulesBy(side, delta) {
        closeEditorMenus();
        ruleScroll[side] = Math.max(0, Math.min(ruleScrollMax(side), ruleScroll[side] + delta));
        applyRuleScroll(side);
    }

    function setupRuleScroll(side) {
        var up = $("#" + side + "RulesScrollUp");
        var down = $("#" + side + "RulesScrollDown");
        var viewport = $("#" + side + "RulesViewport");
        if (up) {
            up.SetPanelEvent("onactivate", function () {
                scrollRulesBy(side, -RULE_SCROLL_STEP);
            });
        }
        if (down) {
            down.SetPanelEvent("onactivate", function () {
                scrollRulesBy(side, RULE_SCROLL_STEP);
            });
        }
        if (viewport) {
            viewport.SetPanelEvent("onmousewheel", function () {
                scrollRulesBy(side, -RULE_SCROLL_STEP);
            });
        }
        applyRuleScroll(side);
    }

    function sendHeroLevels() {
        // 英雄等级由服务端 shop_state 广播；无需客户端推送或本地保存。
    }

    function updateTeamLevelLabels() {
        // 每名英雄个人等级（上阵英雄）
        var parts = [];
        var lineup = saveData.lineup || [];
        for (var index = 0; index < lineup.length; index++) {
            var hero = saveData.heroes[lineup[index]];
            parts.push(hero ? "Lv" + hero.level : "Lv1");
        }
        if (!parts.length) {
            parts.push($.Localize("#dota2_rpg_no_lineup"));
        }
        $("#RadiantTeamLevel").text = parts.join(" / ");
    }

    // 结算只展示服务端已结算的结果；金币和英雄 XP 不在客户端二次修改。
    function grantSettlement(settlement) {
        if (!settlement || settlement.winner !== "radiant") {
            return null;
        }
        var activeXp = Number(settlement.xp_per_active_hero !== undefined
            ? settlement.xp_per_active_hero : settlement.xp_pool || 0);
        var benchXp = Number(settlement.xp_per_bench_hero || 0);
        var activeCount = (saveData.lineup || []).length;
        var benchCount = Math.max(0, (saveData.owned || []).length - activeCount);
        return {
            gold: Number(settlement.gold || 0),
            activeXp: activeXp,
            benchXp: benchXp,
            activeCount: activeCount,
            benchCount: benchCount,
            totalXp: activeXp * activeCount + benchXp * benchCount
        };
    }

    function updateResult(winner) {
        var resultPanel = $("#BattleResult");
        var resultLabel = $("#BattleResultLabel");
        var token = "#dota2_rpg_result_draw";
        var winnerClass = "";
        if (winner === "radiant") {
            token = "#dota2_rpg_result_radiant";
            winnerClass = "RadiantVictory";
        } else if (winner === "dire" || winner === "timeout") {
            token = winner === "timeout" ? "#dota2_rpg_result_timeout" : "#dota2_rpg_result_dire";
            winnerClass = "DireVictory";
        }
        resultLabel.text = $.Localize(token);
        resultPanel.SetHasClass("RadiantVictory", winnerClass === "RadiantVictory");
        resultPanel.SetHasClass("DireVictory", winnerClass === "DireVictory");
        // Visibility belongs to the settlement lifecycle, not asynchronous phase messages.
    }

    function eventArray(value) {
        if (!value) { return []; }
        if (Array.isArray(value)) { return value; }
        return Object.keys(value).sort(function (a, b) { return Number(a) - Number(b); }).map(function (key) { return value[key]; });
    }
    var enemyRosterSignature = null;
    function onEnemyRoster(data) {
        if (!acceptRuleGeneration(data)) { return; }
        var roster = eventArray(data.units);
        var signature = roster.map(function (u) { return u.id + ":" + u.name; }).join(";");
        if (signature === enemyRosterSignature) { return; }
        enemyRosterSignature = signature;
        // Keep enemy identities for condition target pickers, without an enemy editor.
        Object.keys(heroSlots).forEach(function (key) {
            if (key.indexOf("dire_") !== 0) { return; }
            var unit = roster[Number(key.slice(5)) - 1];
            if (!unit || heroSlots[key].name !== unit.name || heroSlots[key].hero_index !== Number(unit.id)) {
                RpgRuleSync.forgetHero(heroSlots[key].rule_key);
                delete heroSlots[key];
            }
        });
        HEROES.Dire = roster.map(function (unit) {
            return { name: unit.name, entityIndex: Number(unit.id) };
        });

    }
    var damageState = { elapsed: 0, units: [] };
    var damageTeam = 2;
    var selectedDamageUnit = null;
    var selectedDamageSource = null;
    var damageColors = ["#59bceb", "#b486ef", "#f5c05b", "#eb7272", "#70c997", "#ef91cb", "#9ab9ed", "#d7a278"];
    var damageSourceColors = { attack: "#b8bec5", other: "#798691" };
    function damageColor(name) {
        if (!damageSourceColors[name]) { damageSourceColors[name] = damageColors[(Object.keys(damageSourceColors).length - 2) % damageColors.length]; }
        return damageSourceColors[name];
    }
    function damageName(name) {
        if (name === "attack") { return $.Localize("#dota2_rpg_damage_attack"); }
        if (name === "other") { return $.Localize("#dota2_rpg_damage_other"); }
        var token = "#DOTA_Tooltip_ability_" + name;
        var label = $.Localize(token);
        return label === token ? name : label;
    }
    function damageLabel(parent, text) {
        var label = $.CreatePanel("Label", parent, ""); label.text = text; label.hittest = false; return label;
    }
    function renderDamage() {
        var units = eventArray(damageState.units).filter(function (u) { return Number(u.team) === damageTeam; });
        units.sort(function (a, b) { return Number(b.total) - Number(a.total) || Number(a.id) - Number(b.id); });
        var selected = null;
        units.forEach(function (u) { if (String(u.id) === String(selectedDamageUnit)) { selected = u; } });
        if (!selected && units.length) { selected = units[0]; selectedDamageUnit = selected.id; selectedDamageSource = null; }
        $("#DamageTitle").text = "DPS · " + Number(damageState.elapsed || 0).toFixed(1) + "s";
        $("#DamageFriendly").SetHasClass("Selected", damageTeam === 2);
        $("#DamageEnemy").SetHasClass("Selected", damageTeam === 3);
        var container = $("#DamageUnits"); container.RemoveAndDeleteChildren();
        var maxTotal = units.length ? Math.max(1, Number(units[0].total)) : 1;
        units.forEach(function (unit) {
            var row = $.CreatePanel("Button", container, "DamageUnit" + unit.id); row.AddClass("DamageUnit");
            row.SetHasClass("Selected", !!selected && String(selected.id) === String(unit.id));
            damageLabel(row, localizeHeroName(unit.name) + " · " + Math.round(unit.dps || 0) + " DPS · " + Math.round(unit.total || 0));
            var bar = $.CreatePanel("Panel", row, ""); bar.AddClass("DamageBar"); bar.hittest = false;
            eventArray(unit.sources).forEach(function (source) {
                var segment = $.CreatePanel("Panel", bar, ""); segment.AddClass("DamageSegment");
                segment.style.width = Math.max(0, Math.min(100, Number(source.total) / maxTotal * 100)) + "%";
                segment.style.backgroundColor = damageColor(source.name); segment.hittest = false;
            });
            row.SetPanelEvent("onactivate", function () { selectedDamageUnit = unit.id; selectedDamageSource = null; renderDamage(); });
        });
        var sources = $("#DamageSources"); sources.RemoveAndDeleteChildren();
        var targets = $("#DamageTargets"); targets.RemoveAndDeleteChildren();
        $("#DamageSelection").text = selected ? localizeHeroName(selected.name) : $.Localize("#dota2_rpg_damage_empty");
        $("#DamageTargetsTitle").text = $.Localize("#dota2_rpg_damage_targets");
        if (!selected) { return; }
        var buckets = [{ name: "all", total: selected.total, targets: selected.targets }].concat(eventArray(selected.sources));
        var active = buckets[0];
        buckets.forEach(function (source) {
            if (source.name === selectedDamageSource) { active = source; }
            var button = $.CreatePanel("Button", sources, ""); button.AddClass("DamageSource");
            button.SetHasClass("Selected", source.name === (selectedDamageSource || "all"));
            if (source.name !== "all") {
                var swatch = $.CreatePanel("Panel", button, ""); swatch.AddClass("DamageSwatch");
                swatch.style.backgroundColor = damageColor(source.name); swatch.hittest = false;
            }
            damageLabel(button, (source.name === "all" ? $.Localize("#dota2_rpg_damage_all") : damageName(source.name)) + " · " + Math.round(source.total));
            button.SetPanelEvent("onactivate", function () { selectedDamageSource = source.name; renderDamage(); });
        });
        $("#DamageTargetsTitle").text += " · " + (active.name === "all" ? $.Localize("#dota2_rpg_damage_all") : damageName(active.name));
        eventArray(active.targets).sort(function (a, b) { return Number(b.total) - Number(a.total); }).forEach(function (target) {
            damageLabel(targets, localizeHeroName(target.name) + " [" + target.id + "] · " + Math.round(target.total) + " (" +
                (100 * Number(target.total) / Math.max(1, Number(active.total))).toFixed(1) + "%)");
        });
    }
    function onDamageStats(data) {
        damageState = data || { elapsed: 0, units: [] };
        if (phase === "fight" || phase === "battle") {
            updateBattleCountdown({phase: phase, battle_time: damageState.elapsed, time_limit: 120});
        }
        renderDamage();
    }

    function updateBattleCountdown(data) {
        if (data.phase === "result") { return; }
        var limit = Math.max(0, Number(data.time_limit) || 120);
        var remaining = Math.max(0, Math.ceil(limit - Math.max(0, Number(data.battle_time) || 0)));
        if (data.phase === "setup") { remaining = Math.ceil(limit); }
        var seconds = remaining % 60;
        $("#BattleCountdown").text = $.Localize("#dota2_rpg_remaining_time") + " "
            + Math.floor(remaining / 60) + ":" + (seconds < 10 ? "0" : "") + seconds;
        $("#BattleCountdown").SetHasClass("CountdownUrgent", remaining <= 10);
    }

    function wireSidePanel(panelId, bodyId, toggleId, labelId) {
        var minimized = false;
        $("#" + toggleId).SetPanelEvent("onactivate", function () {
            minimized = !minimized;
            $("#" + panelId).SetHasClass("SidePanelMinimized", minimized);
            $("#" + bodyId).SetHasClass("Hidden", minimized);
            $("#" + labelId).text = minimized ? "+" : "−";
        });
    }

    var replayGeneration = -1;
    var replayRequested = -1;
    function updateReplay(data) {
        var generation = Number(data.settlement_generation || 0);
        var owner = typeof Players.GetLocalPlayer === "function" &&
            Players.GetLocalPlayer() === Number(data.owner_player_id);
        var available = data.phase === "result" && Number(data.replay_available) === 1 && owner;
        replayGeneration = generation;
        $("#ReplayRunButton").SetHasClass("Hidden", !available);
        $("#ReplayRunHint").SetHasClass("Hidden", !available);
        $("#BattleResult").SetHasClass("Hidden", !available && $("#SettlementPanel").BHasClass("Hidden"));
        $("#ReplayRunButton").enabled = available && replayRequested !== generation;
        $("#ReplayRunLabel").text = $.Localize("#dota2_rpg_replay_chapter_one");
    }
    $("#ReplayRunButton").SetPanelEvent("onactivate", function () {
        var button = $("#ReplayRunButton");
        if (!button.enabled || button.BHasClass("Hidden") || replayRequested === replayGeneration) { return; }
        replayRequested = replayGeneration;
        button.enabled = false;
        GameEvents.SendCustomGameEventToServer("rpg_replay_run", { settlement_generation: replayGeneration });
    });

    function onBattleState(data) {
        if (!acceptRuleGeneration(data)) { return; }
        if (data.settlement_generation !== undefined &&
            Number(data.settlement_generation) < Math.max(replayGeneration, lastSettlementGeneration)) { return; }
        updateReplay(data);
        updateBattleCountdown(data);
        updateRunLives(data);
        var previousPhase = phase;
        phase = data.phase || "setup";
        if (phase !== "setup") { updateNativeShopState(false); }
        if (phase !== "setup") { $("#RuleSettings").SetHasClass("Hidden", true); }
        var fighting = phase === "fight" || phase === "battle";
        if (fighting && previousPhase !== "fight" && previousPhase !== "battle") {
            ["Radiant"].forEach(function (side) {
                var editor = $("#" + side + "Editor");
                if (editor.RpgSetCollapsed) { editor.RpgSetCollapsed(true); }
            });
        }
        // The server publishes a fresh zero snapshot only when a battle starts.
        // Keep the completed battle available throughout results and preparation.
        serverReady = Number(data.ready || 0) === 1;
        var stageLoading = Number(data.stage_loading || 0) === 1;
        stageRetryReady = phase === "setup" && !stageLoading && Number(data.stage_failed || 0) === 1;
        if (data.gold !== undefined) {
            shopState.gold = Math.max(0, Number(data.gold) || 0);
            saveData.gold = shopState.gold;
        }
        if (data.level) {
            currentLevelId = data.level;
            saveData.current_level = currentLevelId;
        }

        var startButton = $("#StartBattleButton");
        if (phase === "setup") {
            setStatus(stageRetryReady ? "#dota2_rpg_stage_failed" : (stageLoading ? "#dota2_rpg_stage_loading" :
                (serverReady ? "#dota2_rpg_status_ready" : "#dota2_rpg_status_preparing")));
            $("#StartBattleLabel").text = $.Localize(stageRetryReady ? "#dota2_rpg_stage_retry" :
                (stageLoading ? "#dota2_rpg_stage_loading_button" : "#dota2_rpg_start_battle"));
            startButton.enabled = serverReady || stageRetryReady;
            startButton.SetHasClass("Hidden", false);
            $("#BattleResult").SetHasClass("Hidden", true);
            closeLootPopup();
            $("#RewardLabel").text = "";
        } else if (phase === "fight" || phase === "battle") {
            setStatus("#dota2_rpg_status_running");
            startButton.enabled = false;
            startButton.SetHasClass("Hidden", true);
        } else {
            setStatus(Number(data.run_failed || 0) === 1 ? "#dota2_rpg_run_failed" : "#dota2_rpg_status_finished");
            startButton.enabled = false;
            startButton.SetHasClass("Hidden", true);
            updateResult(data.winner || "draw");
        }

        $("#ShopPanel").SetHasClass("Hidden", phase !== "setup");
        // 未分配技能点提示
        var unspent = 0;
        for (var hi = 0; hi < (saveData.lineup || []).length; hi++) {
            var hero = saveData.heroes[saveData.lineup[hi]];
            if (hero && hero.skill_points > 0) {
                unspent += hero.skill_points;
            }
        }
        if (phase === "setup" && serverReady && !stageLoading && !stageRetryReady && unspent > 0) {
            setStatus($.Localize("#dota2_rpg_skill_points_hint").replace("%s1", String(unspent)));
        }
        var battleSpeedRow = $("#BattleSpeedRow");
        if (battleSpeedRow) {
            battleSpeedRow.SetHasClass("Hidden", phase === "setup");
        }
        var levelSection = $("#LevelSection");
        if (levelSection) {
            levelSection.SetHasClass("Hidden", phase !== "setup");
        }
        renderLevelList();
        updateLevelProgress();
        updateShopEconomyLabels(shopState.gold);
        updateScrollLabels();
        renderItemShop();
        updateTeamLevelLabels();

        if (phase !== "setup") {
            closeEditorMenus();
        }

        renderSide("Radiant");
            applyRuleScroll("Radiant");
    }

    function onLevelsState(data) {
        data = data || {};
        currentLevelId = data.current || currentLevelId;
        saveData.current_level = currentLevelId;
        levelList = splitList(data.level_ids);
        updateLevelProgress();
    }

    function updateLevelProgress() {
        var total = Math.max(levelList.length, 1);
        var index = 1;
        for (var i = 0; i < levelList.length; i++) {
            if (String(levelList[i].id || levelList[i]) === String(currentLevelId)) {
                index = i + 1;
                break;
            }
        }
        $("#LevelProgress").text = $.Localize("#dota2_rpg_level_progress")
            .replace("%s1", String(index)).replace("%s2", String(total));
    }

    var lootPopupGeneration = 0;
    var lastSettlementGeneration = -1;

    function closeLootPopup() {
        lootPopupGeneration++;
        $("#LootPopup").SetHasClass("Hidden", true);
        $("#SettlementPanel").SetHasClass("Hidden", true);
        $("#BattleResult").SetHasClass("Hidden", $("#ReplayRunButton").BHasClass("Hidden"));
    }

    function showLootPopup(items) {
        var list = $("#LootPopupItems");
        list.RemoveAndDeleteChildren();
        $("#LootPopup").SetHasClass("Hidden", !items.length);
        items.forEach(function (name) {
            var card = $.CreatePanel("Panel", list, "");
            card.AddClass("LootItemCard");
            var image = $.CreatePanel("DOTAItemImage", card, "");
            image.itemname = name;
            image.hittest = false;
            var label = $.CreatePanel("Label", card, "");
            label.text = damageName(name);
            label.hittest = false;
        });

    }

    function onSettlement(settlement) {
        if (settlement && settlement.settlement_generation !== undefined &&
            Number(settlement.settlement_generation) < replayGeneration) { return; }
        if (!settlement) { return; }
        if (settlement.settlement_generation !== undefined) {
            var settlementGeneration = Number(settlement.settlement_generation);
            if (settlementGeneration <= lastSettlementGeneration) { return; }
            lastSettlementGeneration = settlementGeneration;
        }
        closeLootPopup();
        updateResult(settlement.winner);
        var reward = grantSettlement(settlement);
        var rewardLabel = $("#RewardLabel");
        if (settlement && settlement.winner === "radiant" && reward) {
            var parts = [$.Localize("#dota2_rpg_reward_gold") + " " + reward.gold];
            if (settlement.stars !== undefined) {
                parts.push($.Localize("#dota2_rpg_result_stars").replace("%s1", String(settlement.stars)));
            }
            parts.push($.Localize("#dota2_rpg_reward_xp")
                .replace("%s1", String(reward.totalXp))
                .replace("%s2", String(reward.activeXp))
                .replace("%s3", String(reward.benchXp)));
            var lootDrops = splitList(settlement.loot_text).filter(function (name) { return !!name; });
            showLootPopup(lootDrops);
            rewardLabel.text = parts.join("   ");
        } else if (settlement) {
            updateRunLives(settlement);
            var failureParts = [$.Localize(Number(settlement.run_failed || 0) === 1
                ? "#dota2_rpg_run_failed" : settlement.winner === "timeout"
                    ? "#dota2_rpg_result_timeout" : "#dota2_rpg_result_dire")];
            var reliefGold = Math.max(0, Number(settlement.life_reward_gold || 0));
            var reliefItems = splitList(settlement.life_reward_items).filter(function (name) { return !!name; });
            if (reliefGold > 0) {
                failureParts.push($.Localize("#dota2_rpg_life_reward") + " +" + reliefGold + " " + $.Localize("#dota2_rpg_reward_gold"));
            }
            reliefItems.forEach(function (name) { failureParts.push("+" + damageName(name)); });
            if (Number(settlement.life_reward_pending || 0) > 0) {
                failureParts.push($.Localize("#dota2_rpg_life_reward_pending"));
            }
            showLootPopup(reliefItems);
            rewardLabel.text = failureParts.join("   ");
        }
        $("#SettlementPanel").SetHasClass("Hidden", false);
        $("#BattleResult").SetHasClass("Hidden", false);
        var generation = lootPopupGeneration;
        $.Schedule(3, function () {
            if (generation === lootPopupGeneration) { closeLootPopup(); }
        });
        updateShopEconomyLabels(shopState.gold);
        updateScrollLabels();
        renderItemShop();
        updateTeamLevelLabels();
    }

    updateRunLives({ lives_remaining: 5, max_lives: 5 });
    renderSide("Radiant");
    setupRuleScroll("Radiant");
    wireHeroPortraits("Radiant");
    $("#StartBattleButton").enabled = false;
    $("#StartBattleButton").SetPanelEvent("onactivate", function () {
        if (phase !== "setup" || (!serverReady && !stageRetryReady)) {
            return;
        }
        if (stageRetryReady) {
            stageRetryReady = false;
            $("#StartBattleButton").enabled = false;
        }
        GameEvents.SendCustomGameEventToServer("rpg_start_battle", buildPayload());
    });

    $("#LootPopupConfirm").SetPanelEvent("onactivate", closeLootPopup);
    $("#DamageFriendly").SetPanelEvent("onactivate", function () { damageTeam = 2; selectedDamageUnit = null; selectedDamageSource = null; renderDamage(); });
    $("#DamageEnemy").SetPanelEvent("onactivate", function () { damageTeam = 3; selectedDamageUnit = null; selectedDamageSource = null; renderDamage(); });
    GameEvents.Subscribe("rpg_enemy_roster", onEnemyRoster);
    GameEvents.Subscribe("rpg_damage_stats", onDamageStats);
    GameEvents.Subscribe("rpg_battle_state", onBattleState);
    GameEvents.Subscribe("rpg_settlement", onSettlement);
    GameEvents.Subscribe("dota_player_update_selected_unit", function () {
        syncNativePurchaseTarget(true);
    });
    GameEvents.Subscribe("dota_player_update_query_unit", function () {
        syncNativePurchaseTarget(true);
    });
    // 服务端数据（商店/关卡/动作槽）通过 CEM 事件推送
    GameEvents.Subscribe("rpg_rule_update_result", RpgRuleSync.onResult);
    GameEvents.Subscribe("rpg_item_sell_result", onItemSellResult);
    GameEvents.Subscribe("rpg_inventory_transfer_result", onItemTransferResult);
    GameEvents.Subscribe("rpg_shop_state", onShopState);
    GameEvents.Subscribe("rpg_levels_state", onLevelsState);
    GameEvents.Subscribe("rpg_hero_slots", function (data) {
        if (!data || !data.slot_key || !acceptRuleGeneration(data)) {
            return;
        }
        var slotKey = String(data.slot_key);
        var previousSlot = heroSlots[slotKey];
        if (previousSlot && (previousSlot.hero_index !== Number(data.hero_index) || previousSlot.name !== String(data.hero_name || ""))) {
            RpgRuleSync.forgetHero(previousSlot.rule_key);
        }
        heroSlots[slotKey] = {
            name: String(data.hero_name || ""),
            target_actor: String(data.target_actor || ""),
            rule_key: String(data.rule_key || data.hero_name || "")+ (data.rule_key ? "" : ":"+slotKey),
            hero_index: Number(data.hero_index !== undefined ? data.hero_index : -1),
            actions_text: String(data.actions_text || ""),
            abilities_text: data.abilities_text === undefined ? undefined : String(data.abilities_text),
            details_text: String(data.details_text || ""),
            capability_revision:data.capability_revision===undefined ? undefined : Number(data.capability_revision),
            can_edit: data.can_edit === undefined || Number(data.can_edit) === 1,
            rules_ready: data.rules_ready === undefined || Number(data.rules_ready) === 1
        };
        var match = slotKey.match(/^(radiant|dire)_(\d+)$/);
        if (match && match[1] === "radiant") {
            var side = "Radiant";
            var heroIndex = Math.max(0, Number(match[2]) - 1);
            var current = getRules(side, heroIndex);
            if (Number(data.rules_ready) === 1 && (!current._serverHydrated || !current._authored || heroSlots[slotKey].can_edit === false)) {
                var restored = RpgRuleSync.list(data.rules).map(RpgRuleSync.fromServer);
                if (!restored.length) { restored = buildRulesForHero(side,heroIndex); }
                // A capability refresh sends the same rules again. Preserve their edit
                // identities only when the entire ordered snapshot and hero still match.
                var sameHero = previousSlot && previousSlot.name === heroSlots[slotKey].name
                    && previousSlot.hero_index === heroSlots[slotKey].hero_index
                    && previousSlot.rule_key === heroSlots[slotKey].rule_key;
                if (!sameHero || ruleSnapshot(current) !== ruleSnapshot(restored)) {
                    current.splice(0,current.length);
                    restored.forEach(function(rule) { current.push(rule); });
                }
                current._serverHydrated = true;
            } else if (!current._serverHydrated && !current._authored) {
                current.splice(0,current.length);
                buildRulesForHero(side,heroIndex).forEach(function(rule) { current.push(rule); });
            }
            renderSide(side);
        }
    });
    wireShopButtons();
    if ($.RegisterForUnhandledEvent) {
        // 事件与轮询共用状态处理，重复打开信号不能清掉待还原的英雄。
        $.RegisterForUnhandledEvent("DOTAHUDShopOpened", function () { updateNativeShopState(true); });
        $.RegisterForUnhandledEvent("DOTAHUDShopClosed", function () { updateNativeShopState(false); });
    }
    $.Schedule(0.25, watchNativeShop);
    wireSidePanel("DamagePanel", "DamageBody", "DamageToggle", "DamageToggleLabel");
    wireSidePanel("ItemShopPanel", "EquipmentBody", "EquipmentToggle", "EquipmentToggleLabel");
    renderDamage();
    shopState.gold = saveData.gold;
    updateShopEconomyLabels(shopState.gold);
    updateTeamLevelLabels();
    sendHeroLevels();
    $.Schedule(0.2, function () {
        syncNativePurchaseTarget(true);
        $.Schedule(0.75, heartbeatNativePurchaseTarget);
    });
    GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {});
}());
