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
        battle_time_ge: "#dota2_rpg_condition_battle_time_ge",
        ally_under_attack: "#dota2_rpg_condition_ally_under_attack"
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
        boss: "#dota2_rpg_target_attr_boss",
        healer: "#dota2_rpg_target_attr_healer",
        controlled: "#dota2_rpg_target_attr_controlled"
    };

    var TARGET_SIDE_TOKENS = {
        enemy_highest: "#dota2_rpg_target_side_enemy_highest",
        enemy_lowest: "#dota2_rpg_target_side_enemy_lowest",
        ally_highest: "#dota2_rpg_target_side_ally_highest",
        ally_lowest: "#dota2_rpg_target_side_ally_lowest",
        nearest: "#dota2_rpg_target_side_nearest",
        farthest: "#dota2_rpg_target_side_farthest",
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
            return side === "farthest" ? "enemy_distance_farthest" : "enemy_distance_nearest";
        }
        var parts = side.split("_"); // enemy|ally + highest|lowest
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
        ultimate: { condition: "enemy_count_ge", value: 2, target_attr: "hp_pct", target_side: "enemy_lowest", forced: true },
        ability_1: { condition: "enemy_exists", value: 50, target_attr: "distance", target_side: "nearest", forced: false },
        ability_2: { condition: "enemy_exists", value: 50, target_attr: "hp_pct", target_side: "enemy_lowest", forced: false },
        ability_3: { condition: "self_hp_below", value: 50, target_attr: "hp", target_side: "self", forced: false },
        attack: { condition: "always", value: 50, target_attr: "distance", target_side: "nearest", forced: true }
    };

    var MAX_RULE_ROWS = 5;
    var heroSlots = {};
    var FALLBACK_SLOT_ACTIONS = ["ability_1", "ability_2", "ability_3", "ultimate", "attack"];

    function getSlotActions(side, heroIndex) {
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var entry = heroSlots ? heroSlots[key] : null;
        var actions = [];
        if (entry && entry.actions_text) {
            var rawActions = splitList(entry.actions_text);
            for (var actionKey = 0; actionKey < rawActions.length; actionKey++) {
                var action = String(rawActions[actionKey]);
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
                target_attr: defaults.target_attr,
                target_side: defaults.target_side,
                target: composeTarget(defaults.target_attr, defaults.target_side),
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
        var targetAttrSelect = editor.FindChildTraverse("TargetAttrSelect");
        var targetAttrValue = editor.FindChildTraverse("TargetAttrValue");
        var targetAttrMenu = editor.FindChildTraverse("TargetAttrMenu");
        var targetSideSelect = editor.FindChildTraverse("TargetSideSelect");
        var targetSideValue = editor.FindChildTraverse("TargetSideValue");
        var targetSideMenu = editor.FindChildTraverse("TargetSideMenu");

        selectButton.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "condition");
        });
        effectSelect.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "effect");
        });
        targetAttrSelect.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "targetAttr");
        });
        targetSideSelect.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "targetSide");
        });
        wireValueButtons(menu, function (condition) {
            chooseCondition(side, index, condition);
        });
        wireValueButtons(effectMenu, function (effect) {
            chooseEffect(side, index, effect);
        });
        wireValueButtons(targetAttrMenu, function (attr) {
            chooseTargetAttr(side, index, attr);
        });
        wireValueButtons(targetSideMenu, function (targetSide) {
            chooseTargetSide(side, index, targetSide);
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
            targetAttrSelect: targetAttrSelect,
            targetAttrValue: targetAttrValue,
            targetAttrMenu: targetAttrMenu,
            targetSideSelect: targetSideSelect,
            targetSideValue: targetSideValue,
            targetSideMenu: targetSideMenu
        };
    }

    function createRuleRows(side) {
        var container = $("#" + side + "Rules");
        for (var index = 0; index < MAX_RULE_ROWS; index++) {
            var row = $.CreatePanel("Panel", container, side + "Rule" + index);
            row.AddClass("RuleRow");
            createLabel(row, "PriorityNumber", String(index + 1));
            var actionIcon = $.CreatePanel("Panel", row, side + "ActionIcon" + index);
            actionIcon.AddClass("ActionIcon");
            var abilityImage = $.CreatePanel("DOTAAbilityImage", actionIcon, side + "ActionAbility" + index);
            abilityImage.AddClass("ActionAbilityImage");
            var actionFallback = createLabel(actionIcon, "ActionName", "");
            var conditionEditor = createConditionEditor(row, side, index);
            var forceToggle = createForceToggle(row, side, index);
            var upButton = createMoveButton(row, side, index, "Up", "^");
            var downButton = createMoveButton(row, side, index, "Down", "v");
            rowPanels[side].push({
                actionAbilityImage: abilityImage,
                actionFallback: actionFallback,
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
                targetAttrSelect: conditionEditor.targetAttrSelect,
                targetAttrValue: conditionEditor.targetAttrValue,
                targetAttrMenu: conditionEditor.targetAttrMenu,
                targetSideSelect: conditionEditor.targetSideSelect,
                targetSideValue: conditionEditor.targetSideValue,
                targetSideMenu: conditionEditor.targetSideMenu,
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
                panels.targetAttrMenu.SetHasClass("Hidden", true);
                panels.targetSideMenu.SetHasClass("Hidden", true);
                panels.row.SetHasClass("MenuOpen", false);
                panels.row.SetHasClass("ConditionMenuOpen", false);
                panels.row.SetHasClass("EffectMenuOpen", false);
                panels.row.SetHasClass("TargetMenuOpen", false);
            }
            var editor = $("#" + side + "Editor");
            editor.SetHasClass("ConditionMenuExpanded", false);
            editor.SetHasClass("EffectMenuExpanded", false);
            editor.SetHasClass("TargetMenuExpanded", false);
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
        } else if (menuType === "targetAttr") {
            menu = panels.targetAttrMenu;
        } else if (menuType === "targetSide") {
            menu = panels.targetSideMenu;
        } else {
            menu = panels.conditionMenu;
        }
        var shouldOpen = menu.BHasClass("Hidden");
        closeEditorMenus();
        menu.SetHasClass("Hidden", !shouldOpen);
        panels.row.SetHasClass("MenuOpen", shouldOpen);
        panels.row.SetHasClass("ConditionMenuOpen", shouldOpen && menuType === "condition");
        panels.row.SetHasClass("EffectMenuOpen", shouldOpen && menuType === "effect");
        panels.row.SetHasClass("TargetMenuOpen", shouldOpen && menuType === "target");
        var editor = $("#" + side + "Editor");
        editor.SetHasClass("ConditionMenuExpanded", shouldOpen && menuType === "condition");
        editor.SetHasClass("EffectMenuExpanded", shouldOpen && menuType === "effect");
        editor.SetHasClass("TargetMenuExpanded", shouldOpen && menuType === "target");
    }

    function chooseCondition(side, index, condition) {
        var rules = getSelectedRules(side);
        rules[index].condition = CONDITION_TOKENS[condition] ? condition : "always";
        closeEditorMenus();
        updateConditionSelector(side, index, false);
    }

    function chooseTargetAttr(side, index, attr) {
        var rules = getSelectedRules(side);
        var rule = rules[index];
        rule.target_attr = TARGET_ATTR_TOKENS[attr] ? attr : "hp";
        if ((rule.target_attr === "casting" || rule.target_attr === "boss" || rule.target_attr === "healer" || rule.target_attr === "controlled") && rule.target_side !== "self") {
            rule.target_side = "enemy_highest";
        }
        if (rule.target_attr === "distance" && rule.target_side !== "nearest" && rule.target_side !== "farthest" && rule.target_side !== "self") {
            rule.target_side = "nearest";
        }
        rule.target = composeTarget(rule.target_attr, rule.target_side);
        closeEditorMenus();
        updateConditionSelector(side, index, false);
    }

    function chooseTargetSide(side, index, targetSide) {
        var rules = getSelectedRules(side);
        var rule = rules[index];
        rule.target_side = TARGET_SIDE_TOKENS[targetSide] ? targetSide : "enemy_lowest";
        if (rule.target_side === "self" && rule.target_attr === "casting") {
            rule.target_attr = "hp";
        }
        rule.target = composeTarget(rule.target_attr, rule.target_side);
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
        var attr = rule.target_attr || "hp";
        var tSide = rule.target_side || "enemy_lowest";
        panels.targetAttrValue.text = $.Localize(TARGET_ATTR_TOKENS[attr] || TARGET_ATTR_TOKENS.hp);
        panels.targetSideValue.text = $.Localize(TARGET_SIDE_TOKENS[tSide] || TARGET_SIDE_TOKENS.enemy_lowest);
        if (EFFECT_TOKENS[rule.effect]) {
            panels.effectValue.text = $.Localize(EFFECT_TOKENS[rule.effect]);
        }
        panels.conditionSelect.enabled = !locked;
        panels.targetAttrSelect.enabled = !locked && tSide !== "self";
        panels.targetSideSelect.enabled = !locked && attr !== "casting";

        var valueKind = VALUE_CONDITIONS[rule.condition];
        var usesEffect = Boolean(EFFECT_CONDITIONS[rule.condition]);
        panels.thresholdControls.SetHasClass("Hidden", !valueKind);
        panels.effectSelect.SetHasClass("Hidden", !usesEffect);
        panels.thresholdEntry.enabled = !locked && Boolean(valueKind);
        panels.effectSelect.enabled = !locked && usesEffect;
        panels.conditionEditor.SetHasClass("WideConditionSelect", !valueKind && !usesEffect);
        panels.percentLabel.SetHasClass("Hidden", valueKind !== "pct" && valueKind !== "seconds");
        panels.percentLabel.text = valueKind === "seconds" ? $.Localize("#dota2_rpg_seconds_short") : "%";
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
            $("#" + side + "SelectedHero").text = localizeHeroName(selectedHero.name);
        }
    }

    function renderSide(side) {
        var locked = phase !== "setup";
        var hidePanels = phase !== "setup";
        var rules = getSelectedRules(side);
        for (var index = 0; index < MAX_RULE_ROWS; index++) {
            var panels = rowPanels[side][index];
            // 规则槽数量随英雄可用动作动态变化，多余行隐藏
            panels.row.SetHasClass("Hidden", index >= rules.length);
            if (index >= rules.length) {
                continue;
            }
            var definition = rules[index];
            var heroIndex = selectedHeroIndex[side];
            var slotEntry = heroSlots[side.toLowerCase() + "_" + (heroIndex + 1)];
            var detailName = "";
            if (slotEntry && slotEntry.details_text) {
                var details = splitList(slotEntry.details_text);
                if (details[index]) {
                    detailName = details[index];
                }
            }
            if (panels.actionAbilityImage) {
                if (detailName && detailName !== "" && definition.action !== "attack") {
                    panels.actionAbilityImage.abilityname = detailName;
                    panels.actionAbilityImage.SetHasClass("Empty", false);
                } else {
                    panels.actionAbilityImage.abilityname = "";
                    panels.actionAbilityImage.SetHasClass("Empty", true);
                }
            }
            if (definition.action === "attack") {
                panels.actionFallback.text = $.Localize("#dota2_rpg_action_attack");
            } else if (!detailName || detailName === "") {
                panels.actionFallback.text = $.Localize(ACTION_TOKENS[definition.action] || definition.action);
            } else {
                panels.actionFallback.text = "";
            }
            panels.thresholdEntry.text = String(definition.value);
            updateConditionSelector(side, index, locked);
            updateForcedToggle(side, index, locked);
            panels.upButton.enabled = !locked && index > 0;
            panels.downButton.enabled = !locked && index < rules.length - 1;
        }
        $("#" + side + "Editor").SetHasClass("Hidden", hidePanels);
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

    function updateShopEconomyLabels(gold) {
        var normalizedGold = Number(gold);
        $("#GoldValue").text = String(isFinite(normalizedGold) ? Math.max(0, Math.floor(normalizedGold)) : 0);
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
        shopState.bench_slots = Number(data.bench_slots || 0);
        // 个人等级/经验："name:level:xp:quality"
        saveData.heroes = saveData.heroes || {};
        var heroEntries = splitList(data.hero_data_text);
        for (var hIndex = 0; hIndex < heroEntries.length; hIndex++) {
            var hParts = heroEntries[hIndex].split(":");
            if (hParts.length >= 4) {
                saveData.heroes[hParts[0]] = {
                    level: Number(hParts[1]), xp: Number(hParts[2]), quality: hParts[3]
                };
            }
        }
        if (data.refresh_cost !== undefined) {
            shopState.refresh_cost = Number(data.refresh_cost);
            shopState.costs.refresh = shopState.refresh_cost;
        }
        shopState.scroll_low_remaining = Number(data.scroll_low_remaining || 0);
        shopState.scroll_high_remaining = Number(data.scroll_high_remaining || 0);
        shopState.stock = splitList(data.stock_text);
        shopState.inventories = {};
        var invEntries = splitList(data.inventories_text);
        for (var invIndex = 0; invIndex < invEntries.length; invIndex++) {
            var invParts = invEntries[invIndex].split(":");
            if (invParts.length >= 2) {
                saveData.heroes[invParts[0]] = saveData.heroes[invParts[0]] || { level: 1, xp: 0, quality: "common" };
                saveData.heroes[invParts[0]].inventory = invParts[1] === "" ? [] : invParts[1].split(",");
            }
        }
        shopState.scroll_low_stock = Number(data.scroll_low_stock || 0);
        shopState.scroll_high_stock = Number(data.scroll_high_stock || 0);
        saveData.gold = shopState.gold;
        saveData.owned = shopState.owned;
        saveData.lineup = shopState.lineup;
        saveData.bench_slots = shopState.bench_slots;
        saveData.scrolls = { low: shopState.scroll_low_stock, high: shopState.scroll_high_stock };
        saveData.item_stock = shopState.stock;
        persistSave();
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
                var priceLabel = createLabel(slot, "ShopPrice", offer.price + "g");
                priceLabel.style.color = qualityColors[offer.quality] || "#f2d982";
                if (!owned) {
                    slot.SetPanelEvent("onactivate", function () {
                        GameEvents.SendCustomGameEventToServer("rpg_shop_buy", { hero: heroName });
                    });
                    slot.enabled = shopState.gold >= shopState.costs.hero;
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
        $("#ScrollBuyLow").SetPanelEvent("onactivate", function () {
            GameEvents.SendCustomGameEventToServer("rpg_scroll_buy", { kind: "low" });
        });
        $("#ScrollBuyHigh").SetPanelEvent("onactivate", function () {
            GameEvents.SendCustomGameEventToServer("rpg_scroll_buy", { kind: "high" });
        });
        $("#Speed1Button").SetPanelEvent("onactivate", function () {
            GameEvents.SendCustomGameEventToServer("rpg_battle_speed", { speed: 1 });
        });
        $("#Speed2Button").SetPanelEvent("onactivate", function () {
            GameEvents.SendCustomGameEventToServer("rpg_battle_speed", { speed: 2 });
        });
        $("#SkipBattleButton").SetPanelEvent("onactivate", function () {
            GameEvents.SendCustomGameEventToServer("rpg_battle_skip", {});
        });
        $("#ScrollUseLow").SetPanelEvent("onactivate", function () {
            var target = selectedHeroIndex.Radiant >= 0 && saveData.lineup[selectedHeroIndex.Radiant];
            if (target) {
                GameEvents.SendCustomGameEventToServer("rpg_scroll_use", { kind: "low", hero: target });
            }
        });
        $("#SaveCodeExportButton").SetPanelEvent("onactivate", function () {
            $("#SaveCodeText").text = encodeSaveCode(saveData);
        });
        $("#SaveCodeImportButton").SetPanelEvent("onactivate", function () {
            var code = $("#SaveCodeEntry").text;
            var imported = decodeSaveCode(code);
            if (!imported || typeof imported.gold !== "number") {
                $("#ControlStatus").text = $.Localize("#dota2_rpg_savecode_bad");
                return;
            }
            saveData = imported;
            persistSave();
            syncSaveToServer();
            renderShop();
            renderLineupStrip();
            renderRadiantHeroStrip();
            updateScrollLabels();
            renderItemShop();
            updateShopEconomyLabels(saveData.gold);
            updateTeamLevelLabels();
            updateLevelProgress();
            $("#ControlStatus").text = $.Localize("#dota2_rpg_savecode_ok");
        });
        $("#ScrollUseHigh").SetPanelEvent("onactivate", function () {
            var target = selectedHeroIndex.Radiant >= 0 && saveData.lineup[selectedHeroIndex.Radiant];
            if (target) {
                GameEvents.SendCustomGameEventToServer("rpg_scroll_use", { kind: "high", hero: target });
            }
        });
    }

    function renderItemShop() {
        var stock = cemList(shopState.stock);
        var catalog = cemList(shopState.item_catalog);
        var stockList = $("#ItemStockList");
        stockList.RemoveAndDeleteChildren();
        for (var index = 0; index < stock.length; index++) {
            (function (entry, i) {
                var parts = entry.split("|");
                var row = $.CreatePanel("Panel", stockList, "Stock" + i);
                row.AddClass("ItemRow");
                createLabel(row, "ItemRowName", parts[0].replace("item_", ""));
                var sell = $.CreatePanel("Button", row, "Sell" + i);
                sell.AddClass("ItemRowBtn");
                createLabel(sell, "", $.Localize("#dota2_rpg_item_sell"));
                sell.SetPanelEvent("onactivate", function () {
                    GameEvents.SendCustomGameEventToServer("rpg_item_sell", { index: i + 1 });
                });
                var equip = $.CreatePanel("Button", row, "Eq" + i);
                equip.AddClass("ItemRowBtn");
                createLabel(equip, "", $.Localize("#dota2_rpg_item_equip"));
                equip.SetPanelEvent("onactivate", function () {
                    var hero = saveData.lineup[selectedHeroIndex.Radiant];
                    if (hero) {
                        GameEvents.SendCustomGameEventToServer("rpg_item_equip", { hero: hero, index: i + 1 });
                    }
                });
            }(stock[index], index));
        }
        var catalogList = $("#ItemCatalogList");
        catalogList.RemoveAndDeleteChildren();
        for (var ci = 0; ci < catalog.length; ci++) {
            (function (entry, i) {
                var parts = entry.split("|");
                var row = $.CreatePanel("Panel", catalogList, "Cat" + i);
                row.AddClass("ItemRow");
                createLabel(row, "ItemRowName", parts[0].replace("item_", ""));
                createLabel(row, "ItemRowCost", parts[1] + "g");
                var buy = $.CreatePanel("Button", row, "Buy" + i);
                buy.AddClass("ItemRowBtn");
                createLabel(buy, "", $.Localize("#dota2_rpg_item_buy"));
                buy.SetPanelEvent("onactivate", function () {
                    GameEvents.SendCustomGameEventToServer("rpg_item_buy", { item: parts[0] });
                });
                buy.enabled = phase === "setup" && shopState.gold >= Number(parts[1]);
            }(catalog[ci], ci));
        }
    }

    // 存档码：纯 JS Base64（UTF-8 安全）
    var B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function utf8Encode(str) {
        var bytes = [];
        for (var i = 0; i < str.length; i++) {
            var code = str.charCodeAt(i);
            if (code >= 0xd800 && code <= 0xdbff && i + 1 < str.length) {
                var extra = str.charCodeAt(i + 1);
                if (extra >= 0xdc00 && extra <= 0xdfff) {
                    code = ((code - 0xd800) << 10) + (extra - 0xdc00) + 0x10000;
                    i++;
                }
            }
            if (code < 0x80) {
                bytes.push(code);
            } else if (code < 0x800) {
                bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
            } else if (code < 0x10000) {
                bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
            } else {
                bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f),
                    0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
            }
        }
        return bytes;
    }

    function utf8Decode(bytes) {
        var str = "";
        var i = 0;
        while (i < bytes.length) {
            var b = bytes[i];
            var code;
            if (b < 0x80) {
                code = b;
                i++;
            } else if ((b & 0xe0) === 0xc0) {
                code = ((b & 0x1f) << 6) | (bytes[i + 1] & 0x3f);
                i += 2;
            } else if ((b & 0xf0) === 0xe0) {
                code = ((b & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f);
                i += 3;
            } else {
                code = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) |
                    ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f);
                i += 4;
            }
            if (code > 0xffff) {
                code -= 0x10000;
                str += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff));
            } else {
                str += String.fromCharCode(code);
            }
        }
        return str;
    }

    function encodeSaveCode(save) {
        var bytes = utf8Encode(JSON.stringify(save));
        var out = "";
        for (var i = 0; i < bytes.length; i += 3) {
            var b0 = bytes[i], b1 = i + 1 < bytes.length ? bytes[i + 1] : 0, b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
            out += B64_CHARS[b0 >> 2];
            out += B64_CHARS[((b0 & 3) << 4) | (b1 >> 4)];
            out += i + 1 < bytes.length ? B64_CHARS[((b1 & 15) << 2) | (b2 >> 6)] : "=";
            out += i + 2 < bytes.length ? B64_CHARS[b2 & 63] : "=";
        }
        return "RPGSAVE1:" + out;
    }

    function decodeSaveCode(code) {
        code = String(code || "").trim();
        if (code.indexOf("RPGSAVE1:") !== 0) {
            return null;
        }
        var body = code.substring(9).replace(/=+$/, "");
        var bytes = [];
        var buffer = 0, bits = 0;
        for (var i = 0; i < body.length; i++) {
            var idx = B64_CHARS.indexOf(body[i]);
            if (idx < 0) {
                return null;
            }
            buffer = (buffer << 6) | idx;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                bytes.push((buffer >> bits) & 0xff);
            }
        }
        try {
            return JSON.parse(utf8Decode(bytes));
        } catch (e) {
            return null;
        }
    }

    function updateScrollLabels() {
        $("#ScrollBuyLowLabel").text = $.Localize("#dota2_rpg_scroll_low") +
            " (余" + shopState.scroll_low_remaining + ") 存" + shopState.scroll_low_stock;
        $("#ScrollBuyHighLabel").text = $.Localize("#dota2_rpg_scroll_high") +
            " (余" + shopState.scroll_high_remaining + ") 存" + shopState.scroll_high_stock;
        $("#ScrollUseLowLabel").text = $.Localize("#dota2_rpg_scroll_use_low") + " " + shopState.scroll_low_stock;
        $("#ScrollUseHighLabel").text = $.Localize("#dota2_rpg_scroll_use_high") + " " + shopState.scroll_high_stock;
        $("#ScrollBuyLow").enabled = phase === "setup" && shopState.scroll_low_remaining > 0 && shopState.gold >= 100;
        $("#ScrollBuyHigh").enabled = phase === "setup" && shopState.scroll_high_remaining > 0 && shopState.gold >= 1000;
        $("#ScrollUseLow").enabled = phase === "setup" && shopState.scroll_low_stock > 0;
        $("#ScrollUseHigh").enabled = phase === "setup" && shopState.scroll_high_stock > 0;
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
    var SAVE_VERSION = 2;
    var INITIAL_GOLD = 300;
    var HERO_MAX_LEVEL = 30;
    var XP_BASE = 40;   // 与服务端 XP_TO_NEXT_BASE/STEP 保持一致
    var XP_STEP = 30;
    var MAX_ATTEMPTS = 5;

    // 升到下一级所需经验（经验全队共享、全员统一等级）
    // 首通 1~15 关合计 13500 xp ≈ 累计需求 14210 → 15 关左右满级 30
    function xpToNext(level) {
        return 40 + 30 * level;
    }

    function hasEntries(value) {
        for (var key in value) {
            if (value.hasOwnProperty(key)) {
                return true;
            }
        }
        return false;
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
        var previousVersion = Number(saved.version || 0);
        var parsedGold = Number(saved.gold);
        saved.gold = saved.gold !== undefined && isFinite(parsedGold)
            ? Math.max(0, parsedGold)
            : INITIAL_GOLD;
        if (!saved.cleared || typeof saved.cleared !== "object") {
            saved.cleared = {};
        }
        if (!saved.attempts || typeof saved.attempts !== "object") {
            saved.attempts = {};
        }
        saved.level = Math.max(1, Math.floor(Number(saved.level) || 1)); // 旧统一等级（迁移源）
        if (!saved.heroes || typeof saved.heroes !== "object") {
            // 迁移：统一等级 → 每名已拥有英雄个人等级
            saved.heroes = {};
            var migratedHeroes = saved.owned && saved.owned.length ? saved.owned : [];
            for (var mh = 0; mh < migratedHeroes.length; mh++) {
                saved.heroes[migratedHeroes[mh]] = { level: saved.level, xp: 0, quality: "common" };
            }
        }
        if (!saved.item_stock || typeof saved.item_stock !== "object") {
            saved.item_stock = [];
        }
        if (!saved.scrolls || typeof saved.scrolls !== "object") {
            saved.scrolls = { low: 0, high: 0 };
        }
        if (!saved.stars || typeof saved.stars !== "object") {
            saved.stars = {};
        }
        saved.encounter_seed = Number(saved.encounter_seed || 0);
        if (!saved.owned || typeof saved.owned !== "object") {
            saved.owned = [];   // 英雄池（可含场下英雄）
        } else {
            saved.owned = cemList(saved.owned);
        }
        if (!saved.lineup || typeof saved.lineup !== "object") {
            saved.lineup = [];
        } else {
            saved.lineup = cemList(saved.lineup);
        }
        saved.bench_slots = Math.max(0, Math.floor(Number(saved.bench_slots) || 0)); // 替补格子
        if (!saved.current_level) {
            saved.current_level = "ch01"; // 闯关进度
        }
        // v1 首次存档曾错误写入 0 金币；只修复完全无进度的受影响存档。
        if (previousVersion < SAVE_VERSION && saved.gold === 0 && saved.level === 1 &&
                saved.owned.length === 0 && saved.lineup.length === 0 && saved.bench_slots === 0 &&
                !hasEntries(saved.cleared) && !hasEntries(saved.attempts) && saved.current_level === "ch01") {
            saved.gold = INITIAL_GOLD;
        }
        saved.version = SAVE_VERSION;
        return saved;
    }

    function persistSave() {
        try {
            $.LocalStorage.Set(SAVE_KEY, JSON.stringify(saveData));
        } catch (e) {
            // 存档失败不阻断游戏
        }
    }

    function syncSaveToServer() {
        // CEM 嵌套数组会导致载荷丢失，列表统一拍平成分号分隔字符串。
        var heroEntries = [];
        var heroNames = saveData.owned;
        for (var hi = 0; hi < heroNames.length; hi++) {
            var hero = saveData.heroes[heroNames[hi]] || { level: 1, xp: 0, quality: "common" };
            heroEntries.push(heroNames[hi] + ":" + hero.level + ":" + (hero.xp || 0) + ":" + (hero.quality || "common"));
        }
        GameEvents.SendCustomGameEventToServer("rpg_save_sync", {
            gold: saveData.gold,
            hero_data_text: heroEntries.join(";"),
            owned_text: saveData.owned.join(";"),
            lineup_text: saveData.lineup.join(";"),
            bench_slots: saveData.bench_slots,
            stock_text: (saveData.item_stock || []).join(";"),
            scroll_stock_low: saveData.scrolls.low,
            scroll_stock_high: saveData.scrolls.high,
            current_level: saveData.current_level,
            encounter_seed: saveData.encounter_seed
        });
    }

    function attemptsLeft(levelId) {
        var used = Number(saveData.attempts[levelId] || 0);
        return Math.max(0, MAX_ATTEMPTS - used);
    }

    function sendHeroLevels() {
        // 兼容入口：走 rpg_save_sync 的 hero_data_text
        syncSaveToServer();
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
        $("#DireTeamLevel").text = $.Localize("#dota2_rpg_dire_team_label");
    }

    function updateTeamLevelLabels() {
        $("#RadiantTeamLevel").text = $.Localize("#dota2_rpg_level_unified") + " " + saveData.level;
        $("#DireTeamLevel").text = $.Localize("#dota2_rpg_dire_team_label");
    }

    function addXpToHero(heroName, amount) {
        var hero = saveData.heroes[heroName];
        if (!hero || hero.level >= HERO_MAX_LEVEL) {
            return; // 满级经验舍弃
        }
        hero.xp = (hero.xp || 0) + amount;
        while (hero.level < HERO_MAX_LEVEL) {
            var need = XP_BASE + XP_STEP * hero.level;
            if (hero.xp >= need) {
                hero.xp -= need;
                hero.level++;
            } else {
                break;
            }
        }
        if (hero.level >= HERO_MAX_LEVEL) {
            hero.xp = 0;
        }
    }

    // 经验池平均分配（余数按招募顺序补 1）
    function distributeXpPool(pool) {
        var owned = saveData.owned;
        if (!owned || !owned.length) {
            return 0;
        }
        var base = Math.floor(pool / owned.length);
        var remainder = pool % owned.length;
        for (var index = 0; index < owned.length; index++) {
            var extra = 0;
            if (remainder > 0) {
                extra = 1;
                remainder--;
            }
            addXpToHero(owned[index], base + extra);
        }
        return pool;
    }

    function grantSettlement(settlement) {
        if (!settlement || settlement.winner !== "radiant") {
            return null;
        }
        var gold = Number(settlement.gold || 0);
        var xp = Number(settlement.xp_pool || 0);
        saveData.stars = saveData.stars || {};
        if (settlement.stars !== undefined) {
            saveData.stars[settlement.level] = Number(settlement.stars) || 1;
        }
        if (firstClear) {
            saveData.cleared[settlement.level] = true;
        }
        saveData.attempts[settlement.level] = 0;
        distributeXpPool(xp);
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
        shopState.gold = saveData.gold;
        // 服务端是金币权威，把存档金币推回去
        syncSaveToServer();
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
        if (data.gold !== undefined) {
            shopState.gold = Math.max(0, Number(data.gold) || 0);
            saveData.gold = shopState.gold;
        }
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

        $("#ShopPanel").SetHasClass("Hidden", phase !== "setup");
        $("#BattleSpeedRow").SetHasClass("Hidden", phase === "setup");
        $("#LevelSection").SetHasClass("Hidden", phase !== "setup");
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
        renderSide("Dire");
    }

    function onLevelsState(data) {
        data = data || {};
        currentLevelId = data.current || currentLevelId;
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

    function onSettlement(settlement) {
        var reward = grantSettlement(settlement);
        var rewardLabel = $("#RewardLabel");
        if (settlement && settlement.winner === "radiant" && reward) {
            var parts = [$.Localize("#dota2_rpg_reward_gold") + " " + reward.gold];
            if (settlement.stars !== undefined) {
                parts.push($.Localize("#dota2_rpg_result_stars").replace("%s1", String(settlement.stars)));
            }
            var lootDrops = settlement.loot_text ? settlement.loot_text.split(";") : [];
            for (var li = 0; li < lootDrops.length; li++) {
                parts.push("+" + lootDrops[li].replace("item_", ""));
            }
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
        updateShopEconomyLabels(shopState.gold);
        updateScrollLabels();
        renderItemShop();
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
        if (!data || !data.slot_key) {
            return;
        }
        heroSlots[String(data.slot_key)] = {
            name: String(data.hero_name || ""),
            actions_text: String(data.actions_text || "")
        };
        rulesBySide.Radiant = [];
        rulesBySide.Dire = [];
        renderSide("Radiant");
        renderSide("Dire");
    });
    wireShopButtons();
    shopState.gold = saveData.gold;
    updateShopEconomyLabels(shopState.gold);
    updateTeamLevelLabels();
    sendHeroLevels();
    syncSaveToServer();
    GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {});
}());
