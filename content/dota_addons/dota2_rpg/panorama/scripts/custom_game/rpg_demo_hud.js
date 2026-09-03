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
        enemy_below: "#dota2_rpg_condition_enemy_below",
        self_below: "#dota2_rpg_condition_self_below",
        ally_below: "#dota2_rpg_condition_ally_below",
        enemy_in_range: "#dota2_rpg_condition_enemy_in_range",
        enemy_highest_hp: "#dota2_rpg_condition_enemy_highest_hp",
        enemy_lowest_hp: "#dota2_rpg_condition_enemy_lowest_hp",
        enemy_nearest: "#dota2_rpg_condition_enemy_nearest",
        enemy_farthest: "#dota2_rpg_condition_enemy_farthest",
        enemy_has_effect: "#dota2_rpg_condition_enemy_has_effect",
        enemy_lacks_effect: "#dota2_rpg_condition_enemy_lacks_effect",
        enemy_channeling: "#dota2_rpg_condition_enemy_channeling"
    };

    var EFFECT_TOKENS = {
        magic_immune: "#dota2_rpg_effect_magic_immune",
        stunned: "#dota2_rpg_effect_stunned",
        silenced: "#dota2_rpg_effect_silenced",
        rooted: "#dota2_rpg_effect_rooted"
    };

    var HP_CONDITIONS = {
        enemy_below: true,
        self_below: true,
        ally_below: true
    };

    var EFFECT_CONDITIONS = {
        enemy_has_effect: true,
        enemy_lacks_effect: true
    };

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

    function buildDefaultRules() {
        return [
            { action: "ultimate", condition: "always", threshold: 50, effect: "magic_immune" },
            { action: "ability_1", condition: "enemy_below", threshold: 50, effect: "magic_immune" },
            { action: "ability_2", condition: "always", threshold: 50, effect: "magic_immune" },
            { action: "ability_3", condition: "self_below", threshold: 50, effect: "magic_immune" },
            { action: "attack", condition: "always", threshold: 50, effect: "magic_immune" }
        ];
    }

    function buildHeroRuleSets() {
        return [buildDefaultRules(), buildDefaultRules(), buildDefaultRules()];
    }

    var rulesBySide = {
        Radiant: buildHeroRuleSets(),
        Dire: buildHeroRuleSets()
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
        return rulesBySide[side][selectedHeroIndex[side]];
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
        var effectSelect = editor.FindChildTraverse("EffectSelect");
        var effectValue = editor.FindChildTraverse("EffectValue");
        var effectMenu = editor.FindChildTraverse("EffectMenu");

        selectButton.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "condition");
        });
        effectSelect.SetPanelEvent("onactivate", function () {
            toggleEditorMenu(side, index, "effect");
        });
        wireValueButtons(menu, function (condition) {
            chooseCondition(side, index, condition);
        });
        wireValueButtons(effectMenu, function (effect) {
            chooseEffect(side, index, effect);
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
            effectSelect: effectSelect,
            effectValue: effectValue,
            effectMenu: effectMenu
        };
    }

    function createRuleRows(side) {
        var container = $("#" + side + "Rules");
        for (var index = 0; index < 5; index++) {
            var row = $.CreatePanel("Panel", container, side + "Rule" + index);
            row.AddClass("RuleRow");
            createLabel(row, "PriorityNumber", String(index + 1));
            var actionLabel = createLabel(row, "ActionName", "");
            var conditionEditor = createConditionEditor(row, side, index);
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
                effectSelect: conditionEditor.effectSelect,
                effectValue: conditionEditor.effectValue,
                effectMenu: conditionEditor.effectMenu,
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
                rowPanels[side][index].conditionMenu.SetHasClass("Hidden", true);
                rowPanels[side][index].effectMenu.SetHasClass("Hidden", true);
                rowPanels[side][index].row.SetHasClass("MenuOpen", false);
            }
            $("#" + side + "Editor").SetHasClass("MenuExpanded", false);
        }
    }

    function toggleEditorMenu(side, index, menuType) {
        if (phase !== "setup") {
            return;
        }
        var panels = rowPanels[side][index];
        var menu = menuType === "effect" ? panels.effectMenu : panels.conditionMenu;
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

    function chooseEffect(side, index, effect) {
        var rules = getSelectedRules(side);
        rules[index].effect = EFFECT_TOKENS[effect] ? effect : "magic_immune";
        closeEditorMenus();
        updateConditionSelector(side, index, false);
    }

    function updateConditionSelector(side, index, locked) {
        var panels = rowPanels[side][index];
        var rule = getSelectedRules(side)[index];
        panels.conditionValue.text = $.Localize(CONDITION_TOKENS[rule.condition] || CONDITION_TOKENS.always);
        panels.effectValue.text = $.Localize(EFFECT_TOKENS[rule.effect] || EFFECT_TOKENS.magic_immune);
        panels.conditionSelect.enabled = !locked;

        var usesThreshold = Boolean(HP_CONDITIONS[rule.condition]);
        var usesEffect = Boolean(EFFECT_CONDITIONS[rule.condition]);
        panels.thresholdControls.SetHasClass("Hidden", !usesThreshold);
        panels.effectSelect.SetHasClass("Hidden", !usesEffect);
        panels.thresholdEntry.enabled = !locked && usesThreshold;
        panels.effectSelect.enabled = !locked && usesEffect;
    }

    function clampThreshold(value, fallback) {
        var parsed = Number(value);
        if (!isFinite(parsed)) {
            return fallback;
        }
        return Math.max(1, Math.min(100, Math.round(parsed)));
    }

    function syncThreshold(side, index, normalizeText) {
        var rule = getSelectedRules(side)[index];
        var entry = rowPanels[side][index].thresholdEntry;
        rule.threshold = clampThreshold(entry.text, rule.threshold || 50);
        if (normalizeText) {
            entry.text = String(rule.threshold);
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
        if (index < 0 || index >= rulesBySide[side].length || selectedHeroIndex[side] === index) {
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
        for (var index = 0; index < rules.length; index++) {
            var definition = rules[index];
            var panels = rowPanels[side][index];
            panels.actionLabel.text = $.Localize(ACTION_TOKENS[definition.action]);
            panels.thresholdEntry.text = String(definition.threshold);
            updateConditionSelector(side, index, locked);
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
            for (var heroIndex = 0; heroIndex < rulesBySide[side].length; heroIndex++) {
                var rules = rulesBySide[side][heroIndex];
                var prefix = side.toLowerCase() + "_hero_" + (heroIndex + 1);
                for (var ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
                    payload[prefix + "_action_" + (ruleIndex + 1)] = rules[ruleIndex].action;
                    payload[prefix + "_condition_" + (ruleIndex + 1)] = rules[ruleIndex].condition;
                    payload[prefix + "_threshold_" + (ruleIndex + 1)] = rules[ruleIndex].threshold;
                    payload[prefix + "_effect_" + (ruleIndex + 1)] = rules[ruleIndex].effect;
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

    function updateResult(winner) {
        var resultPanel = $("#BattleResult");
        var resultLabel = $("#BattleResultLabel");
        if (winner === "radiant") {
            resultLabel.text = $.Localize("#dota2_rpg_result_radiant");
            resultPanel.SetHasClass("RadiantVictory", true);
            resultPanel.SetHasClass("DireVictory", false);
        } else if (winner === "dire") {
            resultLabel.text = $.Localize("#dota2_rpg_result_dire");
            resultPanel.SetHasClass("RadiantVictory", false);
            resultPanel.SetHasClass("DireVictory", true);
        } else {
            resultLabel.text = $.Localize("#dota2_rpg_result_draw");
            resultPanel.SetHasClass("RadiantVictory", false);
            resultPanel.SetHasClass("DireVictory", false);
        }
        resultPanel.SetHasClass("Hidden", false);
    }

    function onBattleState(data) {
        phase = data.phase || "setup";
        serverReady = Number(data.ready || 0) === 1;
        $("#RadiantAlive").text = String(data.radiant_alive === undefined ? 3 : data.radiant_alive);
        $("#DireAlive").text = String(data.dire_alive === undefined ? 3 : data.dire_alive);

        var startButton = $("#StartBattleButton");
        if (phase === "setup") {
            setStatus(serverReady ? "#dota2_rpg_status_ready" : "#dota2_rpg_status_preparing");
            startButton.enabled = serverReady;
            startButton.SetHasClass("Hidden", false);
        } else if (phase === "battle") {
            setStatus("#dota2_rpg_status_running");
            startButton.enabled = false;
            startButton.SetHasClass("Hidden", true);
        } else {
            setStatus("#dota2_rpg_status_finished");
            startButton.enabled = false;
            startButton.SetHasClass("Hidden", true);
            updateResult(data.winner || "draw");
        }

        if (phase !== "setup") {
            closeEditorMenus();
        }

        renderSide("Radiant");
        renderSide("Dire");
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
    GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {});
}());
