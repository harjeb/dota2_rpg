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
        self_hp_pct_lte: "#dota2_rpg_condition_self_hp_pct_lte",
        self_mana_pct_gte: "#dota2_rpg_condition_self_mana_pct_gte",
        alive_enemy_count_gte: "#dota2_rpg_condition_alive_enemy_count_gte",
        elapsed_gte: "#dota2_rpg_condition_elapsed_gte",
        self_recently_damaged: "#dota2_rpg_condition_self_recently_damaged",
        any_ally_recently_damaged: "#dota2_rpg_condition_any_ally_recently_damaged",
        dead_ally_count_gte: "#dota2_rpg_condition_dead_ally_count_gte"
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
        self_hp_pct_lte: "pct",
        self_mana_pct_gte: "pct",
        alive_enemy_count_gte: "count",
        elapsed_gte: "seconds",
        self_recently_damaged: "seconds",
        any_ally_recently_damaged: "seconds",
        dead_ally_count_gte: "count"
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
        ultimate: { condition: "always", value: 2, target_attr: "hp_pct", target_side: "enemy_lowest", forced: true },
        ability_1: { condition: "always", value: 50, target_attr: "distance", target_side: "nearest", forced: false },
        ability_2: { condition: "always", value: 50, target_attr: "hp_pct", target_side: "enemy_lowest", forced: false },
        ability_3: { condition: "self_hp_pct_lte", value: 50, target_attr: "hp", target_side: "self", forced: false },
        attack: { condition: "always", value: 50, target_attr: "distance", target_side: "nearest", forced: true }
    };
    // 主动装备和技能共用同一套规则编辑器；服务端动作列表中的 item_1..item_6
    // 不能因为没有静态模板而被客户端过滤掉。
    for (var defaultItemSlot = 1; defaultItemSlot <= 6; defaultItemSlot++) {
        DEFAULT_RULE_BY_ACTION["item_" + defaultItemSlot] = {
            condition: "always", value: 50, target_attr: "hp_pct", target_side: "enemy_lowest", forced: false
        };
    }

    var MAX_RULE_ROWS = 10;  // 固定 10 条规则槽 + 系统兜底
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

    function getActionDetail(side, heroIndex, action) {
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var entry = heroSlots ? heroSlots[key] : null;
        if (!entry) {
            return "";
        }
        var actions = splitList(entry.actions_text);
        var details = splitList(entry.details_text);
        for (var index = 0; index < actions.length; index++) {
            if (actions[index] === action && details[index] && details[index] !== action) {
                return details[index];
            }
        }
        return "";
    }

    function buildRulesForHero(side, heroIndex) {
        var actions = getSlotActions(side, heroIndex);
        var rules = [];
        for (var index = 0; index < MAX_RULE_ROWS; index++) {
            var action = actions[((index % actions.length) + actions.length) % actions.length];
            var defaults = DEFAULT_RULE_BY_ACTION[action];
            rules.push({
                action: action,
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
    var lastNativePurchaseTarget = -1;
    var lastNativePurchaseHero = "";
    var selectedEquipmentHeroName = "";

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
            (function (idx) {
                var actionIcon = $.CreatePanel("Button", row, side + "ActionSelect" + idx);
                actionIcon.AddClass("ActionIcon");
                var abilityImage = $.CreatePanel("DOTAAbilityImage", actionIcon, side + "ActionAbility" + idx);
                abilityImage.AddClass("ActionAbilityImage");
                var actionFallback = createLabel(actionIcon, "ActionName", "");
                actionIcon.SetPanelEvent("onactivate", function () {
                    if (phase === "setup") {
                        openActionMenu(side, idx);
                    }
                });
                var conditionEditor = createConditionEditor(row, side, idx);
                var forceToggle = createForceToggle(row, side, idx);
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
                actionMenu.AddClass("ActionMenu Hidden");
                rowPanels[side].push({
                    actionMenu: actionMenu,
                    actionAbilityImage: abilityImage,
                    actionFallback: actionFallback,
                    deleteButton: deleteButton,
                    addButton: addButton,
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
            }(index));
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
                if (panels.actionMenu) {
                    panels.actionMenu.SetHasClass("Hidden", true);
                }
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

    // 悬浮下拉：菜单移动到全屏浮层，按行位置覆盖显示（不撑开面板）
    var DROPDOWN_TYPE_OFFSET = {
        condition: 6,
        effect: 6,
        targetAttr: 48,
        targetSide: 48
    };

    function openDropdownMenu(side, index, menuType) {
        var panels = rowPanels[side][index];
        var menu;
        if (menuType === "effect") {
            menu = panels.effectMenu;
        } else if (menuType === "targetAttr") {
            menu = panels.targetAttrMenu;
        } else if (menuType === "targetSide") {
            menu = panels.targetSideMenu;
        } else if (menuType === "action") {
            menu = panels.actionMenu;
        } else {
            menu = panels.conditionMenu;
        }
        if (menu == null) {
            return menu;
        }
        var layer = $("#DropdownLayer");
        if (layer === null || layer === undefined) {
            return menu;
        }
        menu.SetParent(layer);
        menu.SetHasClass("DropRight", side === "Dire");
        menu.style.marginTop = (EDITOR_TOP + index * ROW_HEIGHT + (DROPDOWN_TYPE_OFFSET[menuType] || 0)) + "px;";
        menu.SetHasClass("Hidden", false);
        return menu;
    }

    var EDITOR_TOP = 268;
    var ROW_HEIGHT = 130;

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
        if (shouldOpen) {
            openDropdownMenu(side, index, menuType);
        }
        panels.row.SetHasClass("MenuOpen", shouldOpen);
    }

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
        var actions = getSlotActions(side, index);
        for (var i = 0; i < actions.length; i++) {
            (function (actionKey) {
                var option = $.CreatePanel("Button", menu, "ActionOpt_" + side + index + "_" + actionKey);
                option.AddClass("ConditionOption");
                var detail = getActionDetail(side, index, actionKey);
                var text = detail !== "" ? detail : $.Localize(ACTION_TOKENS[actionKey] || actionKey);
                createLabel(option, "", text);
                option.SetPanelEvent("onactivate", function () {
                    chooseAction(side, index, actionKey);
                });
            }(actions[i]));
        }
        var shouldOpen = menu.BHasClass("Hidden");
        closeEditorMenus();
        if (shouldOpen) {
            openDropdownMenu(side, index, "action");
        }
        panels.row.SetHasClass("MenuOpen", shouldOpen);
    }

    function chooseAction(side, index, actionKey) {
        var rules = getSelectedRules(side);
        if (!rules[index]) {
            return;
        }
        rules[index].action = actionKey;
        closeEditorMenus();
        sendRuleToServer(side, selectedHeroIndex[side], index);
        renderSide(side);
    }

    function deleteRule(side, index) {
        var rules = getSelectedRules(side);
        if (rules.length <= 1) {
            return; // 至少保留一条规则（系统兜底始终存在）
        }
        rules.splice(index, 1);
        renderSide(side);
    }

    // 新增规则：复制最后一个动作，追加到末尾（最多 10 条）
    function addRuleAtEnd(side) {
        var rules = getSelectedRules(side);
        if (rules.length >= MAX_RULE_ROWS) {
            return;
        }
        var last = rules[rules.length - 1];
        var source = last || { action: "attack", condition: "always", value: 50,
            target_attr: "distance", target_side: "nearest",
            target: "enemy_distance_nearest", forced: true };
        rules.push({
            action: source.action,
            condition: source.condition,
            value: source.value,
            target_attr: source.target_attr,
            target_side: source.target_side,
            target: source.target,
            forced: source.forced,
            enabled: true
        });
        renderSide(side);
    }

    function chooseCondition(side, index, condition) {
        var rules = getSelectedRules(side);
        rules[index].condition = CONDITION_TOKENS[condition] ? condition : "always";
        closeEditorMenus();
        updateConditionSelector(side, index, false);
        sendRuleToServer(side, selectedHeroIndex[side], index);
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
        sendRuleToServer(side, selectedHeroIndex[side], index);
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
        sendRuleToServer(side, selectedHeroIndex[side], index);
    }

    function chooseEffect(side, index, effect) {
        var rules = getSelectedRules(side);
        rules[index].effect = EFFECT_TOKENS[effect] ? effect : "magic_immune";
        closeEditorMenus();
        updateConditionSelector(side, index, false);
        sendRuleToServer(side, selectedHeroIndex[side], index);
    }

    function toggleForced(side, index) {
        if (phase !== "setup") {
            return;
        }
        var rule = getSelectedRules(side)[index];
        rule.forced = !rule.forced;
        updateForcedToggle(side, index, false);
        sendRuleToServer(side, selectedHeroIndex[side], index);
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
            return Math.max(1, Math.min(30, Math.round(parsed)));
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
        sendRuleToServer(side, selectedHeroIndex[side], index);
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
        if (index < 0 || index >= HEROES[side].length) {
            return;
        }
        if (selectedHeroIndex[side] === index) {
            if (side === "Radiant" && HEROES.Radiant[index]) {
                selectedEquipmentHeroName = HEROES.Radiant[index].name;
                sendNativePurchaseHero(selectedEquipmentHeroName, true);
                renderItemShop();
            }
            return;
        }
        if (phase === "setup") {
            syncAllRuleInputs(side);
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
            var detailName = getActionDetail(side, heroIndex, definition.action);
            if (panels.actionAbilityImage) {
                setAbilityImage(panels.actionAbilityImage,
                    definition.action !== "attack" ? detailName : "");
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
            if (!locked) {
                sendRuleToServer(side, heroIndex, index);
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
    }

    function sendRuleToServer(side, heroIndex, ruleIndex) {
        if (typeof RpgRuleSync === "undefined") {
            return;
        }
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var entry = heroSlots[key];
        if (!entry || entry.hero_index === undefined) {
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
        RpgRuleSync.sendRule({
            heroIndex: entry.hero_index,
            heroName: entry.name,
            slot: ruleIndex + 1,
            rule: rule,
            actionId: rule.action,
            actionName: rule.action === "attack" ? "" : getActionDetail(side, heroIndex, rule.action)
        });
    }

    function buildPayload() {
        syncAllRuleInputs("Radiant");
        syncAllRulesToServer();
        return {};
    }

    function syncAllRulesToServer() {
        var sides = ["Radiant", "Dire"];
        for (var sideIndex = 0; sideIndex < sides.length; sideIndex++) {
            var side = sides[sideIndex];
            for (var heroIndex = 0; heroIndex < (HEROES[side] || []).length; heroIndex++) {
                for (var ruleIndex = 0; ruleIndex < MAX_RULE_ROWS; ruleIndex++) {
                    sendRuleToServer(side, heroIndex, ruleIndex);
                }
            }
        }
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
    var MAX_STASH_SLOTS = 15; // 0..8 inventory/backpack + 9..14 native remote-purchase stash
    var shopState = {
        gold: 500,
        offers: [],
        owned: [],
        lineup: [],
        bench_slots: 0,
        costs: { hero: 500, refresh: 20, bench_slot: 200, bench_slot_max: 5, lineup_max: 5 },
        free_recruit_choices: 2
    };

    function onShopState(data) {
        try {
            onShopStateInner(data);
        } catch (e) {
            $("#ControlStatus").text = "ShopStateErr: " + e;
        }
    }

    function updateShopEconomyLabels(gold) {
        // 金币显示在 Dota 原版 HUD 钱包，这里只更新价格标签
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
        $("#RadiantCollapseButton").SetPanelEvent("onactivate", function () {
            var editor = $("#RadiantEditor");
            var editorBody = $("#RadiantEditorBody");
            editor.ToggleClass("Collapsed");
            var collapsed = editor.BHasClass("Collapsed");
            editorBody.SetHasClass("Hidden", collapsed);
            $("#RadiantCollapseLabel").text = collapsed ? "v" : "^";
        });
        $("#DireCollapseButton").SetPanelEvent("onactivate", function () {
            var editor = $("#DireEditor");
            var editorBody = $("#DireEditorBody");
            editor.ToggleClass("Collapsed");
            var collapsed = editor.BHasClass("Collapsed");
            editorBody.SetHasClass("Hidden", collapsed);
            $("#DireCollapseLabel").text = collapsed ? "v" : "^";
        });
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
            renderItemShop();
        }
    }

    function itemDisplayName(itemName) {
        return String(itemName || "").replace("item_", "").replace(/_/g, " ");
    }

    function createItemIcon(parent, itemName) {
        var icon = $.CreatePanel("DOTAAbilityImage", parent, "");
        icon.AddClass("ItemIcon");
        icon.abilityname = itemName;
        return icon;
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
                var row = $.CreatePanel("Panel", equipped, "Equipped_" + target.name + "_" + index);
                row.AddClass("ItemEquippedRow");
                createItemIcon(row, itemName);
                var slotSuffix = itemSlot >= 9 ? " [储藏栏 " + itemSlot + "]" : (itemSlot >= 6 ? " [背包 " + itemSlot + "]" : "");
                createLabel(row, "ItemRowName", itemDisplayName(itemName) + slotSuffix);
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
                unequip.enabled = phase === "setup" && shopState.stock.length < MAX_STASH_SLOTS && Boolean(itemId);
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
              cost: 100 },
            { kind: "high", label: $.Localize("#dota2_rpg_scroll_high"),
              remaining: shopState.scroll_high_remaining, stockCount: shopState.scroll_high_stock,
              cost: 1000 }
        ];

        renderItemTarget(target);

        // 普通装备只来自 Valve 原版商店。这里显示小精灵持有的真实实例，并提供一键转交。
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
                var row = $.CreatePanel("Panel", stockList, "Stock" + index);
                row.AddClass("ItemRow");
                createItemIcon(row, itemName);
                createLabel(row, "ItemRowName", itemDisplayName(itemName));
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
                equip.enabled = phase === "setup" && Boolean(target) && targetHasSpace && Boolean(itemId);
            }(stock[stockIndex], stockIndex));
        }

        // 项目面板只出售两种经验卷轴；购买/出售普通物品请使用原版 Dota 商店。
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
    var RULE_CONTENT_HEIGHT = 1300; // 10 行 × 130px
    var RULE_SCROLL_STEP = 130;
    var ruleScroll = { Radiant: 0, Dire: 0 };

    function ruleScrollMax(side) {
        return Math.max(0, RULE_CONTENT_HEIGHT - RULE_VIEW_HEIGHT);
    }

    function applyRuleScroll(side) {
        var pos = Math.max(0, Math.min(ruleScrollMax(side), ruleScroll[side]));
        ruleScroll[side] = pos;
        var container = $("#" + side + "Rules");
        if (container) {
            container.style.marginTop = -pos + "px;";
        }
        var thumb = $("#" + side + "RulesScrollThumb");
        var track = $("#" + side + "RulesScrollTrack");
        if (thumb && track) {
            var maxScroll = ruleScrollMax(side);
            var trackH = 380 - 52 - 4; // 上下按钮占位后的轨道高度
            var thumbH = Math.max(48, Math.floor(trackH * RULE_VIEW_HEIGHT / Math.max(1, RULE_CONTENT_HEIGHT)));
            thumb.style.height = thumbH + "px;";
            var thumbTop = maxScroll > 0 ? Math.floor((pos / maxScroll) * (trackH - thumbH)) : 0;
            thumb.style.marginTop = thumbTop + "px;";
        }
        var rail = $("#" + side + "RulesScrollRail");
        if (rail) {
            rail.SetHasClass("Hidden", ruleScrollMax(side) <= 0);
        }
    }

    function scrollRulesBy(side, delta) {
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
        $("#DireTeamLevel").text = $.Localize("#dota2_rpg_dire_team_label");
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
            saveData.current_level = currentLevelId;
        }

        var startButton = $("#StartBattleButton");
        if (phase === "setup") {
            setStatus(serverReady ? "#dota2_rpg_status_ready" : "#dota2_rpg_status_preparing");
            startButton.enabled = serverReady;
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
        // 未分配技能点提示
        var unspent = 0;
        for (var hi = 0; hi < (saveData.lineup || []).length; hi++) {
            var hero = saveData.heroes[saveData.lineup[hi]];
            if (hero && hero.skill_points > 0) {
                unspent += hero.skill_points;
            }
        }
        if (phase === "setup" && unspent > 0) {
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
        renderSide("Dire");
        applyRuleScroll("Radiant");
        applyRuleScroll("Dire");
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

    function onSettlement(settlement) {
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
            var lootDrops = settlement.loot_text ? settlement.loot_text.split(";") : [];
            for (var li = 0; li < lootDrops.length; li++) {
                if (lootDrops[li]) {
                    parts.push("+" + lootDrops[li].replace("item_", ""));
                }
            }
            rewardLabel.text = parts.join("   ");
        } else if (settlement) {
            rewardLabel.text = settlement.winner === "timeout"
                ? $.Localize("#dota2_rpg_result_timeout")
                : $.Localize("#dota2_rpg_result_dire");
        }
        updateShopEconomyLabels(shopState.gold);
        updateScrollLabels();
        renderItemShop();
        updateTeamLevelLabels();
    }

    createRuleRows("Radiant");
    createRuleRows("Dire");
    setupRuleScroll("Radiant");
    setupRuleScroll("Dire");
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
    GameEvents.Subscribe("dota_player_update_selected_unit", function () {
        syncNativePurchaseTarget(true);
    });
    GameEvents.Subscribe("dota_player_update_query_unit", function () {
        syncNativePurchaseTarget(true);
    });
    // 服务端数据（商店/关卡/动作槽）通过 CEM 事件推送
    GameEvents.Subscribe("rpg_shop_state", onShopState);
    GameEvents.Subscribe("rpg_levels_state", onLevelsState);
    GameEvents.Subscribe("rpg_hero_slots", function (data) {
        if (!data || !data.slot_key) {
            return;
        }
        var slotKey = String(data.slot_key);
        var previous = heroSlots[slotKey];
        heroSlots[slotKey] = {
            name: String(data.hero_name || ""),
            hero_index: Number(data.hero_index !== undefined ? data.hero_index : -1),
            actions_text: String(data.actions_text || ""),
            details_text: String(data.details_text || "")
        };
        var match = slotKey.match(/^(radiant|dire)_(\d+)$/);
        if (match) {
            var side = match[1] === "radiant" ? "Radiant" : "Dire";
            var heroIndex = Math.max(0, Number(match[2]) - 1);
            if (!previous || previous.name !== heroSlots[slotKey].name) {
                rulesBySide[side][heroIndex] = null;
            }
            if (!rulesBySide[side][heroIndex]) {
                rulesBySide[side][heroIndex] = buildRulesForHero(side, heroIndex);
            }
            renderSide(side);
            syncAllRulesToServer();
        }
    });
    wireShopButtons();
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
