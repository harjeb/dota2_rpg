(function () {
    "use strict";

    var boundButtons = [];
    var attempts = 0;
    var maxAttempts = 30;

    function rootPanel() {
        var panel = $.GetContextPanel();
        while (panel && panel.GetParent()) {
            panel = panel.GetParent();
        }
        return panel;
    }

    function findAny(ids) {
        var root = rootPanel();
        if (!root) {
            return null;
        }
        for (var i = 0; i < ids.length; i += 1) {
            var panel = root.FindChildTraverse(ids[i]);
            if (panel) {
                return panel;
            }
        }
        return null;
    }

    function setArrow(button, collapsed, explicitLabel) {
        if (!button) {
            return;
        }

        var label = explicitLabel || button.FindChildTraverse("ActionPanelCollapseArrow")
            || button.FindChildTraverse("CollapseArrow")
            || button.FindChildTraverse("MinimizeLabel")
            || button.FindChildTraverse("ButtonLabel");

        if (!label && button.GetChildCount && button.GetChildCount() > 0) {
            label = button.GetChild(0);
        }

        if (label && label.text !== undefined) {
            label.text = collapsed ? ">" : "<";
        }
    }

    function bindActionPanel(options) {
        options = options || {};
        var panel = options.panel || findAny([
            "ActionPanel",
            "TacticPanel",
            "TacticsPanel",
            "RulesPanel",
            "RpgActionPanel"
        ]);
        var button = options.button || findAny([
            "ActionPanelMinimizeButton",
            "TacticMinimizeButton",
            "TacticsMinimizeButton",
            "RulesMinimizeButton",
            "MinimizeButton"
        ]);

        if (!panel || !button) {
            return false;
        }

        if (boundButtons.indexOf(button) >= 0) {
            return true;
        }
        boundButtons.push(button);

        panel.AddClass("RpgFixedActionPanel");
        button.AddClass("RpgActionPanelArrowButton");
        button.hittest = true;

        var collapsed = panel.BHasClass("RpgActionPanelCollapsed");
        setArrow(button, collapsed, options.label);

        button.SetPanelEvent("onactivate", function () {
            collapsed = !panel.BHasClass("RpgActionPanelCollapsed");
            if (options.onToggle) {
                options.onToggle(collapsed);
            }
            panel.SetHasClass("RpgActionPanelCollapsed", collapsed);
            setArrow(button, collapsed, options.label);
        });

        return true;
    }

    function makeHeroShopTransparent(panel) {
        panel = panel || findAny([
            "HeroShop",
            "HeroShopPanel",
            "RecruitShop",
            "RecruitmentPanel",
            "ShopPanel"
        ]);
        if (!panel) {
            return false;
        }

        panel.AddClass("RpgTransparentHeroShop");
        return true;
    }

    function hasAction(rule) {
        if (!rule || !rule.action) {
            return false;
        }
        if (typeof rule.action === "string") {
            return rule.action.length > 0;
        }
        return !!(
            rule.action.kind
            || rule.action.type
            || rule.action.logical_id
            || rule.action.name
        );
    }

    function createSingleDefaultRule() {
        return {
            id: "default_attack_nearest",
            enabled: true,
            action: { kind: "attack" },
            target_filters: { team: "enemy" },
            target_priorities: ["nearest"],
            use_conditions: [],
            approach: "range_only",
            is_default: true
        };
    }

    function normalizeDefaultRules(rules) {
        var output = [];
        rules = rules || [];

        for (var i = 0; i < rules.length; i += 1) {
            var rule = rules[i];
            if (rule
                && rule.is_padding !== true
                && rule.placeholder !== true
                && hasAction(rule)) {
                output.push(rule);
            }
        }

        if (output.length === 0) {
            output.push(createSingleDefaultRule());
        }
        return output;
    }

    function installKnownPanels() {
        var actionBound = bindActionPanel({});
        var shopBound = makeHeroShopTransparent(null);

        attempts += 1;
        if ((!actionBound || !shopBound) && attempts < maxAttempts) {
            $.Schedule(0.5, installKnownPanels);
        }
    }

    var api = {
        bindActionPanel: bindActionPanel,
        makeHeroShopTransparent: makeHeroShopTransparent,
        createSingleDefaultRule: createSingleDefaultRule,
        normalizeDefaultRules: normalizeDefaultRules
    };

    if (GameUI && GameUI.CustomUIConfig) {
        GameUI.CustomUIConfig().RpgIssueFixUI = api;
    }

    $.Schedule(0.0, installKnownPanels);
}());
