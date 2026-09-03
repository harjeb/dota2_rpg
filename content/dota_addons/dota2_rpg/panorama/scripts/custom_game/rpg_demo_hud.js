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
        attack: "#dota2_rpg_action_attack"
    };

    var CONDITION_TOKENS = {
        always: "#dota2_rpg_condition_always",
        self_hp_below: "#dota2_rpg_condition_self_hp_below",
        self_mp_above: "#dota2_rpg_condition_self_mp_above",
        enemy_exists: "#dota2_rpg_condition_enemy_exists",
        ally_exists: "#dota2_rpg_condition_ally_exists",
        enemy_count_ge: "#dota2_rpg_condition_enemy_count_ge",
        battle_time_ge: "#dota2_rpg_condition_battle_time_ge"
    };

    var TARGET_TOKENS = {
        enemy_hp_lowest: "#dota2_rpg_target_enemy_hp_lowest",
        enemy_hp_pct_lowest: "#dota2_rpg_target_enemy_hp_pct_lowest",
        enemy_hp_highest: "#dota2_rpg_target_enemy_hp_highest",
        enemy_hp_pct_highest: "#dota2_rpg_target_enemy_hp_pct_highest",
        enemy_nearest: "#dota2_rpg_target_enemy_nearest",
        enemy_farthest: "#dota2_rpg_target_enemy_farthest",
        enemy_attack_highest: "#dota2_rpg_target_enemy_attack_highest",
        enemy_casting: "#dota2_rpg_target_enemy_casting",
        ally_hp_lowest: "#dota2_rpg_target_ally_hp_lowest",
        ally_hp_pct_lowest: "#dota2_rpg_target_ally_hp_pct_lowest",
        self: "#dota2_rpg_target_self"
    };

    var EFFECT_TOKENS = {
        magic_immune: "#dota2_rpg_effect_magic_immune",
        stunned: "#dota2_rpg_effect_stunned",
        silenced: "#dota2_rpg_effect_silenced",
        rooted: "#dota2_rpg_effect_rooted"
    };

    // 条件参数语义：pct 显示 %，count/seconds 显示纯数字
    var VALUE_CONDITIONS = {
        self_hp_below: "pct",
        self_mp_above: "pct",
        enemy_count_ge: "count",
        battle_time_ge: "seconds"
    };

    var EFFECT_CONDITIONS = {}; // v1 条件为单一条件，状态类条件 v2 预留

    var HEROES = {
        Radiant: [],  // 动态：由商店/阵容决定（CustomNetTables shop 表）
        Dire: [
            { panelId: "DireHero1", name: "npc_dota_hero_axe" },
            { panelId: "DireHero2", name: "npc_dota_hero_lion" },
            { panelId: "DireHero3", name: "npc_dota_hero_crystal_maiden" }
        ]
    };

    // 每个动作槽的默认规则模板（玩家可套用后微调）
    var DEFAULT_RULE_BY_ACTION = {
        ultimate: { condition: "enemy_count_ge", value: 2, target: "enemy_hp_pct_lowest", forced: true },
        ability_1: { condition: "enemy_exists", value: 50, target: "enemy_nearest", forced: false },
        ability_2: { condition: "enemy_exists", value: 50, target: "enemy_hp_pct_lowest", forced: false },
        ability_3: { condition: "self_hp_below", value: 50, target: "self", forced: false },
        attack: { condition: "always", value: 50, target: "enemy_nearest", forced: false }
    };

    var MAX_RULE_ROWS = 5;
    var heroSlots = {};
    var FALLBACK_SLOT_ACTIONS = ["ability_1", "ability_2", "ability_3", "ultimate", "attack"];

    function getSlotActions(side, heroIndex) {
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var entry = heroSlots ? heroSlots[key] : null;
        var actions = [];
        if (entry && entry.actions) {
            for (var actionKey in entry.actions) {
                var action = String(entry.actions[actionKey]);
                if (DEFAULT_RULE_BY_ACTION[action]) {
                    actions.push(action);
                }
            }
        }
        if (!actions.length) {
            for (var fallbackIndex = 0; fallbackIndex < FALLBACK_SLOT_ACTIONS.length; fallbackIndex++) {
                actions.push(FALLBACK_SLOT_ACTIONS[fallbackIndex]);
            }
        }
        return actions;
    }

    function buildRulesForHero(side, heroIndex) {
        var actions = getSlotActions(side, heroIndex);
        var rules = [];
        for (var index = 0; index < actions.length; index++) {
            var defaults = DEFAULT_RULE_BY_ACTION[actions[index]];
            rules.push({
                action: actions[index],
                condition: defaults.condition,
                value: defaults.value,
                target: defaults.target,
                forced: defaults.forced
            });
        }
        return rules;
    }

    function getRules(side, heroIndex) {
        if (!rulesBySide[side][heroIndex]) {
            rulesBySide[side][heroIndex] = buildRulesForHero(side, heroIndex);
        }
        return rulesBySide[side][heroIndex];
    }

    var rulesBySide = {
        Radiant: [],
        Dire: []
    };
    var selectedHeroIndex = {
        Radiant: 0,
        Dire: 0
    };
    var rowPanels = {
        Radiant: [],
        Dire: []
    };
    var phase = "setup";
    var serverReady = false;

    function getSelectedRules(side) {
        return getRules(side, selectedHeroIndex[side]);
    }

    function createLabel(parent, className, text) {
        var label = $.CreatePanel("Label", parent, "");
        label.AddClass(className);
        label.text = text || "";
        return label;
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

    function createForceToggle(parent, side, index) {
        var button = $.CreatePanel("Button", parent, side + "ForceToggle" + index);
        button.AddClass("ForceToggle");
        var valueLabel = createLabel(button, "ForceToggleValue", "");
        button.SetPanelEvent("onactivate", function () {
            toggleForced(side, index);
        });
        return {
            button: button,
            valueLabel: valueLabel
        };
    }

    function wireValueButtons(panel, callback) {
        for (var childIndex = 0; childIndex < panel.GetChildCount(); childIndex++) {
            var child = panel.GetChild(childIndex);
            var value = child.GetAttributeString("value", "");
            if (value) {
                (function (button, selectedValue) {
                    button.SetPanelEvent("onactivate", function () {
                        callback(selectedValue);
                    });
                }(child, value));
            }
            wireValueButtons(child, callback);
        }
    }

    function createConditionEditor(parent, side, index) {
        var editor = $.CreatePanel("Panel", parent, side + "ConditionEditor" + index);
        editor.BLoadLayoutSnippet("RpgConditionEditor");
        var selectButton = editor.FindChildTraverse("ConditionSelect");
        var valueLabel = editor.FindChildTraverse("ConditionValue");
        var menu = editor.FindChildTraverse("ConditionMenu");
        var thresholdControls = editor.FindChildTraverse("ThresholdControls");
        var thresholdEntry = editor.FindChildTraverse("ThresholdEntry");
        var percentLabel = editor.FindChildTraverse("PercentLabel");
        var effectSelect = editor.FindChildTraverse("EffectSelect");
        var effectValue = editor.FindChildTraverse("EffectValue");
        var effectMenu = editor.FindChildTraverse("EffectMenu");
        var targetSelect = editor.FindChildTraverse("TargetSelect");
        var targetValue = editor.FindChildTraverse("TargetValue");
        var targetMenu = editor.FindChildTraverse("TargetMenu");

        selectButton.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "condition");
        });
        effectSelect.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "effect");
        });
        targetSelect.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "target");
        });
        wireValueButtons(menu, function (condition) {
            chooseCondition(side, index, condition);
        });
        wireValueButtons(effectMenu, function (effect) {
            chooseEffect(side, index, effect);
        });
        wireValueButtons(targetMenu, function (target) {
            chooseTarget(side, index, target);
        });
        thresholdEntry.SetPanelEvent("oninputsubmit", function () {
            syncThreshold(side, index, true);
        });
        return {
            editor: editor,
            selectButton: selectButton,
            valueLabel: valueLabel,
            menu: menu,
            thresholdControls: thresholdControls,
            thresholdEntry: thresholdEntry,
            percentLabel: percentLabel,
            effectSelect: effectSelect,
            effectValue: effectValue,
            effectMenu: effectMenu,
            targetSelect: targetSelect,
            targetValue: targetValue,
            targetMenu: targetMenu
        };
    }

    function createRuleRows(side) {
        var container = $("#" + side + "Rules");
        for (var index = 0; index < MAX_RULE_ROWS; index++) {
            var row = $.CreatePanel("Panel", container, side + "Rule" + index);
            row.AddClass("RuleRow");
            createLabel(row, "PriorityNumber", String(index + 1));
            var actionLabel = createLabel(row, "ActionName", "");
            var conditionEditor = createConditionEditor(row, side, index);
            var forceToggle = createForceToggle(row, side, index);
            var upButton = createMoveButton(row, side, index, "Up", "^");
            var downButton = createMoveButton(row, side, index, "Down", "v");
            rowPanels[side].push({
                actionLabel: actionLabel,
                row: row,
                conditionEditor: conditionEditor.editor,
                conditionSelect: conditionEditor.selectButton,
                conditionValue: conditionEditor.valueLabel,
                conditionMenu: conditionEditor.menu,
                thresholdControls: conditionEditor.thresholdControls,
                thresholdEntry: conditionEditor.thresholdEntry,
                percentLabel: conditionEditor.percentLabel,
                effectSelect: conditionEditor.effectSelect,
                effectValue: conditionEditor.effectValue,
                effectMenu: conditionEditor.effectMenu,
                targetSelect: conditionEditor.targetSelect,
                targetValue: conditionEditor.targetValue,
                targetMenu: conditionEditor.targetMenu,
                forceToggle: forceToggle.button,
                forceToggleValue: forceToggle.valueLabel,
                upButton: upButton,
                downButton: downButton
            });
        }
        renderSide(side);
    }

    function closeEditorMenus() {
        var sides = ["Radiant", "Dire"];
        for (var sideIndex = 0; sideIndex < sides.length; sideIndex++) {
            var side = sides[sideIndex];
            for (var index = 0; index < rowPanels[side].length; index++) {
                var panels = rowPanels[side][index];
                panels.conditionMenu.SetHasClass("Hidden", true);
                panels.effectMenu.SetHasClass("Hidden", true);
                panels.targetMenu.SetHasClass("Hidden", true);
                panels.row.SetHasClass("MenuOpen", false);
            }
            $("#" + side + "Editor").SetHasClass("MenuExpanded", false);
        }
    }

    function toggleEditorMenu(side, index, menuType) {
        if (phase !== "setup") {
            return;
        }
        var panels = rowPanels[side][index];
        var menu;
        if (menuType === "effect") {
            menu = panels.effectMenu;
        } else if (menuType === "target") {
            menu = panels.targetMenu;
        } else {
            menu = panels.conditionMenu;
        }
        var shouldOpen = menu.BHasClass("Hidden");
        closeEditorMenus();
        menu.SetHasClass("Hidden", !shouldOpen);
        panels.row.SetHasClass("MenuOpen", shouldOpen);
        $("#" + side + "Editor").SetHasClass("MenuExpanded", shouldOpen);
    }

    function chooseCondition(side, index, condition) {
        var rules = getSelectedRules(side);
        rules[index].condition = CONDITION_TOKENS[condition] ? condition : "always";
        closeEditorMenus();
        updateConditionSelector(side, index, false);
    }

    function chooseTarget(side, index, target) {
        var rules = getSelectedRules(side);
        rules[index].target = TARGET_TOKENS[target] ? target : "enemy_nearest";
        closeEditorMenus();
        updateConditionSelector(side, index, false);
    }

    function chooseEffect(side, index, effect) {
        var rules = getSelectedRules(side);
        rules[index].effect = EFFECT_TOKENS[effect] ? effect : "magic_immune";
        closeEditorMenus();
        updateConditionSelector(side, index, false);
    }

    function toggleForced(side, index) {
        if (phase !== "setup") {
            return;
        }
        var rule = getSelectedRules(side)[index];
        rule.forced = !rule.forced;
        updateForcedToggle(side, index, false);
    }

    function updateForcedToggle(side, index, locked) {
        var panels = rowPanels[side][index];
        var forced = Boolean(getSelectedRules(side)[index].forced);
        panels.forceToggleValue.text = $.Localize(forced ? "#dota2_rpg_force_enabled" : "#dota2_rpg_force_disabled");
        panels.forceToggle.SetHasClass("Forced", forced);
        panels.forceToggle.enabled = !locked;
    }

    function updateConditionSelector(side, index, locked) {
        var panels = rowPanels[side][index];
        var rule = getSelectedRules(side)[index];
        panels.conditionValue.text = $.Localize(CONDITION_TOKENS[rule.condition] || CONDITION_TOKENS.always);
        panels.targetValue.text = $.Localize(TARGET_TOKENS[rule.target] || TARGET_TOKENS.enemy_nearest);
        if (EFFECT_TOKENS[rule.effect]) {
            panels.effectValue.text = $.Localize(EFFECT_TOKENS[rule.effect]);
        }
        panels.conditionSelect.enabled = !locked;
        panels.targetSelect.enabled = !locked;

        var valueKind = VALUE_CONDITIONS[rule.condition];
        var usesEffect = Boolean(EFFECT_CONDITIONS[rule.condition]);
        panels.thresholdControls.SetHasClass("Hidden", !valueKind);
        panels.effectSelect.SetHasClass("Hidden", !usesEffect);
        panels.thresholdEntry.enabled = !locked && Boolean(valueKind);
        panels.effectSelect.enabled = !locked && usesEffect;
        panels.percentLabel.SetHasClass("Hidden", valueKind !== "pct");
        panels.percentLabel.text = valueKind === "seconds" ? "s" : "%";
    }

    function clampValue(value, fallback, kind) {
        var parsed = Number(value);
        if (!isFinite(parsed)) {
            return fallback;
        }
        if (kind === "count") {
            return Math.max(1, Math.min(10, Math.round(parsed)));
        }
        if (kind === "seconds") {
            return Math.max(1, Math.min(300, Math.round(parsed)));
        }
        return Math.max(1, Math.min(100, Math.round(parsed)));
    }

    function syncThreshold(side, index, normalizeText) {
        var rule = getSelectedRules(side)[index];
        var entry = rowPanels[side][index].thresholdEntry;
        rule.value = clampValue(entry.text, rule.value || 50, VALUE_CONDITIONS[rule.condition]);
        if (normalizeText) {
            entry.text = String(rule.value);
        }
    }

    function syncAllRuleInputs(side) {
        var rules = getSelectedRules(side);
        for (var index = 0; index < rules.length; index++) {
            syncThreshold(side, index, true);
        }
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

        syncAllRuleInputs(side);
        var current = rules[index];
        rules[index] = rules[nextIndex];
        rules[nextIndex] = current;
        renderSide(side);
    }

    function selectHero(side, index) {
        if (index < 0 || index >= HEROES[side].length || selectedHeroIndex[side] === index) {
            return;
        }
        if (phase === "setup") {
            syncAllRuleInputs(side);
        }
        closeEditorMenus();
        selectedHeroIndex[side] = index;
        renderSide(side);
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
            $("#" + side + "SelectedHero").text = $.Localize("#" + selectedHero.name);
        }
    }

    function renderSide(side) {
        var locked = phase !== "setup";
        var rules = getSelectedRules(side);
        for (var index = 0; index < MAX_RULE_ROWS; index++) {
            var panels = rowPanels[side][index];
            // 规则槽数量随英雄可用动作动态变化，多余行隐藏
            panels.row.SetHasClass("Hidden", index >= rules.length);
            if (index >= rules.length) {
                continue;
            }
            var definition = rules[index];
            panels.actionLabel.text = $.Localize(ACTION_TOKENS[definition.action]);
            panels.thresholdEntry.text = String(definition.value);
            updateConditionSelector(side, index, locked);
            updateForcedToggle(side, index, locked);
            panels.upButton.enabled = !locked && index > 0;
            panels.downButton.enabled = !locked && index < rules.length - 1;
        }
        $("#" + side + "Editor").SetHasClass("Locked", locked);
        updateHeroSelection(side);
    }

    function buildPayload() {
        var payload = {};
        var sides = ["Radiant", "Dire"];
        for (var sideIndex = 0; sideIndex < sides.length; sideIndex++) {
            var side = sides[sideIndex];
            syncAllRuleInputs(side);
            for (var heroIndex = 0; heroIndex < HEROES[side].length; heroIndex++) {
                var rules = getRules(side, heroIndex);
                var prefix = side.toLowerCase() + "_hero_" + (heroIndex + 1);
                payload[prefix + "_count"] = rules.length;
                for (var ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
                    payload[prefix + "_action_" + (ruleIndex + 1)] = rules[ruleIndex].action;
                    payload[prefix + "_condition_" + (ruleIndex + 1)] = rules[ruleIndex].condition;
                    payload[prefix + "_value_" + (ruleIndex + 1)] = rules[ruleIndex].value;
                    payload[prefix + "_target_" + (ruleIndex + 1)] = rules[ruleIndex].target;
                    payload[prefix + "_forced_" + (ruleIndex + 1)] = rules[ruleIndex].forced ? 1 : 0;
                }
            }
        }
        return payload;
    }

    function setStatus(token) {
        var text = $.Localize(token);
        $("#BattleStatus").text = text;
        $("#ControlStatus").text = text;
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
    var shopState = {
        gold: 300,
        offer: [],
        owned: [],
        lineup: [],
        bench_slots: 0,
        costs: { hero: 100, refresh: 20, bench_slot: 200, bench_slot_max: 5, lineup_max: 5 }
    };

    function onShopState(data) {
        try {
            onShopStateInner(data);
        } catch (e) {
            $("#ControlStatus").text = "ShopStateErr: " + e;
        }
    }

    function onShopStateInner(data) {
        if (!data) {
            data = shopState;
        }
        shopState.gold = Number(data.gold !== undefined ? data.gold : shopState.gold);
        shopState.offer = cemList(data.offer);
        shopState.owned = cemList(data.owned);
        shopState.lineup = cemList(data.lineup);
        shopState.bench_slots = Number(data.bench_slots || 0);
        if (data.costs) {
            shopState.costs = data.costs;
        }
        saveData.gold = shopState.gold;
        saveData.owned = shopState.owned;
        saveData.lineup = shopState.lineup;
        saveData.bench_slots = shopState.bench_slots;
        persistSave();
        renderShop();
        renderLineupStrip();
        renderRadiantHeroStrip();
        $("#GoldLabel").text = $.Localize("#dota2_rpg_gold") + " " + shopState.gold;
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
        for (var index = 0; index < shopState.offer.length; index++) {
            (function (heroName) {
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
                var nameLabel = createLabel(slot, "ShopName", heroName.replace("npc_dota_hero_", ""));
                createLabel(slot, "ShopPrice", "100g");
                if (!owned) {
                    slot.SetPanelEvent("onactivate", function () {
                        GameEvents.SendCustomGameEventToServer("rpg_shop_buy", { hero: heroName });
                    });
                    slot.enabled = shopState.gold >= shopState.costs.hero;
                } else {
                    slot.enabled = false;
                }
            }(shopState.offer[index]));
        }
        $("#ShopHeader").text = $.Localize("#dota2_rpg_shop_title") +
            "  [offer=" + shopState.offer.length + " owned=" + shopState.owned.length + "]";
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
                    GameEvents.SendCustomGameEventToServer("rpg_lineup_set", { lineup: next });
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
        if (selectedHeroIndex.Radiant >= shopState.lineup.length) {
            selectedHeroIndex.Radiant = 0;
        }
    }

    // ---------------- 关卡选择（数据来自 CustomNetTables） ----------------
    var levelList = [];
    var currentLevelId = saveData ? saveData.current_level || "ch01" : "ch01";

    function renderLevelList() {
        // 关卡按顺序推进，不再提供自由选择（进度显示在顶部）
    }

    // ---------------- 金币/经验/挑战次数存档（LocalStorage，MVP） ----------------
    var SAVE_KEY = "dota2_rpg_save_v1";
    var HERO_MAX_LEVEL = 30;
    var MAX_ATTEMPTS = 5;

    // 升到下一级所需经验（经验全队共享、全员统一等级）
    // 首通 1~15 关合计 13500 xp ≈ 累计需求 14210 → 15 关左右满级 30
    function xpToNext(level) {
        return 40 + 30 * level;
    }

    function loadSave() {
        var saved = null;
        try {
            saved = JSON.parse($.LocalStorage.Get(SAVE_KEY) || "null");
        } catch (e) {
            saved = null;
        }
        if (!saved || typeof saved !== "object") {
            saved = {};
        }
        if (!saved.gold) {
            saved.gold = 0;
        }
        if (!saved.cleared || typeof saved.cleared !== "object") {
            saved.cleared = {};
        }
        if (!saved.attempts || typeof saved.attempts !== "object") {
            saved.attempts = {};
        }
        if (!saved.level) {
            saved.level = 1; // 全队统一等级
        }
        if (!saved.owned || typeof saved.owned !== "object") {
            saved.owned = [];   // 英雄池（可含场下英雄）
        }
        if (!saved.lineup || typeof saved.lineup !== "object") {
            saved.lineup = [];
        }
        if (!saved.bench_slots) {
            saved.bench_slots = 0; // 替补格子（需金币购买）
        }
        if (!saved.current_level) {
            saved.current_level = "ch01"; // 闯关进度
        }
        return saved;
    }

    function persistSave() {
        try {
            $.LocalStorage.Set(SAVE_KEY, JSON.stringify(saveData));
        } catch (e) {
            // 存档失败不阻断游戏
        }
    }

    function attemptsLeft(levelId) {
        var used = Number(saveData.attempts[levelId] || 0);
        return Math.max(0, MAX_ATTEMPTS - used);
    }

    function sendHeroLevels() {
        GameEvents.SendCustomGameEventToServer("rpg_hero_levels", { level: saveData.level });
    }

    function updateTeamLevelLabels() {
        $("#RadiantTeamLevel").text = $.Localize("#dota2_rpg_level_unified") + " " + saveData.level;
        $("#DireTeamLevel").text = $.Localize("#dota2_rpg_dire_team_label");
    }

    function applySharedXp(xp) {
        var pool = Number(xp || 0);
        var levelUps = 0;
        var level = saveData.level;
        while (level < HERO_MAX_LEVEL && pool >= xpToNext(level)) {
            pool -= xpToNext(level);
            level++;
            levelUps++;
        }
        saveData.level = level;
        return levelUps;
    }

    function grantSettlement(settlement) {
        if (!settlement || settlement.winner !== "radiant") {
            return null;
        }
        var firstClear = !saveData.cleared[settlement.level];
        var gold = Number(firstClear ? settlement.first_gold : settlement.repeat_gold) || 0;
        var xp = Number(firstClear ? settlement.first_xp : settlement.repeat_xp) || 0;
        if (firstClear) {
            saveData.cleared[settlement.level] = true;
        }
        saveData.attempts[settlement.level] = 0;
        // 闯关推进：存档指向下一关
        for (var li = 0; li < levelList.length; li++) {
            var lid = String(levelList[li].id || levelList[li]);
            if (lid === String(settlement.level) && levelList[li + 1]) {
                saveData.current_level = String(levelList[li + 1].id || levelList[li + 1]);
                break;
            }
        }
        var levelUps = applySharedXp(xp);
        // 时间奖励：越快越多（服务端已算好 time_bonus）
        gold += Number(settlement.time_bonus || 0);
        saveData.gold += gold;
        // 服务端是金币权威，把存档金币推回去
        GameEvents.SendCustomGameEventToServer("rpg_save_sync", {
            gold: saveData.gold,
            level: saveData.level,
            bench_slots: saveData.bench_slots,
            owned: saveData.owned,
            lineup: saveData.lineup,
            current_level: saveData.current_level
        });
        persistSave();
        return { gold: gold, xp: xp, levelUps: levelUps, firstClear: firstClear };
    }

    function registerFailure(levelId) {
        saveData.attempts[levelId] = Math.min(MAX_ATTEMPTS, Number(saveData.attempts[levelId] || 0) + 1);
        persistSave();
    }

    var saveData = loadSave();

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
        resultPanel.SetHasClass("Hidden", false);
    }

    function onBattleState(data) {
        phase = data.phase || "setup";
        serverReady = Number(data.ready || 0) === 1;
        if (data.level) {
            currentLevelId = data.level;
        }

        var startButton = $("#StartBattleButton");
        if (phase === "setup") {
            var attempts = attemptsLeft(currentLevelId);
            if (attempts <= 0) {
                setStatus("#dota2_rpg_no_attempts");
                startButton.enabled = false;
            } else {
                setStatus(serverReady ? "#dota2_rpg_status_ready" : "#dota2_rpg_status_preparing");
                startButton.enabled = serverReady;
            }
            startButton.SetHasClass("Hidden", false);
            $("#BattleResult").SetHasClass("Hidden", true);
            $("#RewardLabel").text = "";
        } else if (phase === "fight" || phase === "battle") {
            setStatus("#dota2_rpg_status_running");
            startButton.enabled = false;
            startButton.SetHasClass("Hidden", true);
        } else {
            setStatus("#dota2_rpg_status_finished");
            startButton.enabled = false;
            startButton.SetHasClass("Hidden", true);
            updateResult(data.winner || "draw");
        }

        renderLevelList();
        updateLevelProgress();
        $("#GoldLabel").text = $.Localize("#dota2_rpg_gold") + " " + saveData.gold;
        updateTeamLevelLabels();

        if (phase !== "setup") {
            closeEditorMenus();
        }

        renderSide("Radiant");
        renderSide("Dire");
    }

    function onLevelsState(data) {
        data = data || {};
        currentLevelId = data.current || currentLevelId;
        levelList = cemList(data.levels);
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

    function onSettlement(settlement) {
        var reward = grantSettlement(settlement);
        var rewardLabel = $("#RewardLabel");
        if (settlement && settlement.winner === "radiant" && reward) {
            var parts = [$.Localize("#dota2_rpg_reward_gold") + " " + reward.gold];
            if (reward.levelUps > 0) {
                parts.push($.Localize("#dota2_rpg_reward_level_up") + " " + reward.levelUps);
            }
            rewardLabel.text = parts.join("   ");
        } else if (settlement) {
            registerFailure(settlement.level);
            rewardLabel.text = attemptsLeft(settlement.level) > 0
                ? $.Localize("#dota2_rpg_attempts_left") + " " + attemptsLeft(settlement.level)
                : $.Localize("#dota2_rpg_no_attempts");
        }
        $("#GoldLabel").text = $.Localize("#dota2_rpg_gold") + " " + saveData.gold;
        updateTeamLevelLabels();
    }

    createRuleRows("Radiant");
    createRuleRows("Dire");
    wireHeroPortraits("Radiant");
    wireHeroPortraits("Dire");
    $("#StartBattleButton").enabled = false;
    $("#StartBattleButton").SetPanelEvent("onactivate", function () {
        if (phase !== "setup" || !serverReady) {
            return;
        }
        GameEvents.SendCustomGameEventToServer("rpg_start_battle", buildPayload());
    });

    GameEvents.Subscribe("rpg_battle_state", onBattleState);
    GameEvents.Subscribe("rpg_settlement", onSettlement);
    // 服务端数据（商店/关卡/动作槽）通过 CEM 事件推送
    GameEvents.Subscribe("rpg_shop_state", onShopState);
    GameEvents.Subscribe("rpg_levels_state", onLevelsState);
    GameEvents.Subscribe("rpg_hero_slots", function (data) {
        heroSlots = (data && data.slots) || {};
        rulesBySide.Radiant = [];
        rulesBySide.Dire = [];
        renderSide("Radiant");
        renderSide("Dire");
    });
    wireShopButtons();
    $("#GoldLabel").text = $.Localize("#dota2_rpg_gold") + " " + saveData.gold;
    updateTeamLevelLabels();
    sendHeroLevels();
    GameEvents.SendCustomGameEventToServer("rpg_save_sync", {
        gold: saveData.gold,
        level: saveData.level,
        bench_slots: saveData.bench_slots,
        owned: saveData.owned,
        lineup: saveData.lineup,
        current_level: saveData.current_level
    });
    GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {});
}());
