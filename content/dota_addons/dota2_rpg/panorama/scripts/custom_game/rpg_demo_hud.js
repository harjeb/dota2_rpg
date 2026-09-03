(function () {
    "use strict";

    var ACTION_TOKENS = {
        ultimate: "#dota2_rpg_action_ultimate",
        ability_1: "#dota2_rpg_action_1",
        ability_2: "#dota2_rpg_action_2",
        ability_3: "#dota2_rpg_action_3",
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
        Radiant: [
            { panelId: "RadiantHero1", name: "npc_dota_hero_sven" },
            { panelId: "RadiantHero2", name: "npc_dota_hero_lina" },
            { panelId: "RadiantHero3", name: "npc_dota_hero_dazzle" }
        ],
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
    var FALLBACK_SLOT_ACTIONS = ["ability_1", "ability_2", "ability_3", "ultimate", "attack"];

    function getSlotActions(side, heroIndex) {
        var key = side.toLowerCase() + "_" + (heroIndex + 1);
        var table = CustomNetTables.GetTableValue("rpg_rules_config", "heroes");
        var entry = table ? table[key] : null;
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
        for (var index = 0; index < heroes.length; index++) {
            $("#" + heroes[index].panelId).SetHasClass("Selected", selectedHeroIndex[side] === index);
        }
        var selectedHero = heroes[selectedHeroIndex[side]];
        $("#" + side + "SelectedHero").text = $.Localize("#" + selectedHero.name);
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

    // ---------------- 关卡选择（数据来自 CustomNetTables） ----------------
    var levelList = [];
    var currentLevelId = "demo_3v3";

    function renderLevelList() {
        var container = $("#LevelList");
        container.RemoveAndDeleteChildren();
        for (var index = 0; index < levelList.length; index++) {
            (function (level) {
                var option = $.CreatePanel("Button", container, "Level_" + level.id);
                option.AddClass("LevelOption");
                option.SetHasClass("Selected", level.id === currentLevelId);
                createLabel(option, "LevelOptionLabel", level.name);
                option.SetPanelEvent("onactivate", function () {
                    if (phase !== "setup") {
                        return;
                    }
                    GameEvents.SendCustomGameEventToServer("rpg_select_level", { level: level.id });
                });
            }(levelList[index]));
        }
    }

    // ---------------- 金币存档（LocalStorage，MVP） ----------------
    var SAVE_KEY = "dota2_rpg_save_v1";

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
        return saved;
    }

    function persistSave() {
        try {
            $.LocalStorage.Set(SAVE_KEY, JSON.stringify(saveData));
        } catch (e) {
            // 存档失败不阻断游戏
        }
    }

    function grantSettlement(settlement) {
        if (!settlement || settlement.winner !== "radiant") {
            return;
        }
        saveData.gold += Number(settlement.gold || 0);
        saveData.cleared[settlement.level] = true;
        persistSave();
        $("#GoldLabel").text = $.Localize("#dota2_rpg_gold") + " " + saveData.gold;
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
        $("#RadiantAlive").text = String(data.radiant_alive === undefined ? 3 : data.radiant_alive);
        $("#DireAlive").text = String(data.dire_alive === undefined ? 3 : data.dire_alive);

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

        renderLevelList();

        if (phase !== "setup") {
            closeEditorMenus();
        }

        renderSide("Radiant");
        renderSide("Dire");
    }

    function onLevelsTable(tableName, tableKey) {
        if (tableKey !== "levels") {
            return;
        }
        var table = CustomNetTables.GetTableValue("rpg_rules_config", "levels");
        var data = table || {};
        var rawLevels = data.levels || {};
        currentLevelId = data.current || currentLevelId;
        levelList = [];
        for (var key in rawLevels) {
            var level = rawLevels[key];
            levelList.push({
                id: String(level.id || key),
                name: level.name || String(key),
                type: level.type || "creep"
            });
        }
        levelList.sort(function (a, b) { return a.id < b.id ? -1 : 1; });
        renderLevelList();
    }

    function onSettlement(settlement) {
        grantSettlement(settlement);
        var rewardLabel = $("#RewardLabel");
        if (settlement && settlement.winner === "radiant") {
            rewardLabel.text = $.Localize("#dota2_rpg_reward_gold") + " " + Number(settlement.gold || 0);
        } else {
            rewardLabel.text = "";
        }
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
    // 英雄动作槽/关卡列表就绪后重建对应 UI
    CustomNetTables.SubscribeNetTableListener("rpg_rules_config", function (tableName, tableKey) {
        if (tableKey === "levels") {
            onLevelsTable(tableName, tableKey);
            return;
        }
        if (tableKey === "heroes") {
            rulesBySide.Radiant = [];
            rulesBySide.Dire = [];
            renderSide("Radiant");
            renderSide("Dire");
        }
    });
    $("#GoldLabel").text = $.Localize("#dota2_rpg_gold") + " " + saveData.gold;
    GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {});
}());
