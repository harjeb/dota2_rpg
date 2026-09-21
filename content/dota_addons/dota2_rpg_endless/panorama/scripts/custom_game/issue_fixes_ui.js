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
            label.hittest = false;
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

        function applyCollapsed(nextCollapsed) {
            panel.SetHasClass("RpgActionPanelCollapsed", nextCollapsed);
            setArrow(button, nextCollapsed, options.label);
            if (options.restoreButton) {
                panel.visible = !nextCollapsed;
                options.restoreButton.visible = nextCollapsed;
            }
        }

        panel.RpgSetCollapsed = function (value) {
            if (options.onToggle) { options.onToggle(!!value); }
            applyCollapsed(!!value);
        };
        var collapsed = panel.BHasClass("RpgActionPanelCollapsed");
        applyCollapsed(collapsed);

        function toggle() {
            collapsed = !panel.BHasClass("RpgActionPanelCollapsed");
            if (options.onToggle) {
                options.onToggle(collapsed);
            }
            applyCollapsed(collapsed);
            if ($.Msg) {
                $.Msg("[RPG][UI] editor=" + panel.id + " collapsed=" + collapsed
                    + " external_restore=" + !!options.restoreButton);
            }
        }
        button.SetPanelEvent("onactivate", toggle);
        if (options.restoreButton) {
            options.restoreButton.hittest = true;
            options.restoreButton.SetPanelEvent("onactivate", toggle);
        }

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

    // Keep the catalog's readers and draft alive while metadata is refreshed.
    // Reopening the dialog here would discard text not yet read by Apply.
    function installConditionRefresh() {
        if (typeof RpgConditionCatalog === "undefined") { return; }
        var originalOpen = RpgConditionCatalog.open;
        var active = null;
        function update() {
            if (!active || active.root.BHasClass("Hidden")) { return; }
            var current = !active.options.isCurrent || active.options.isCurrent();
            var capability = current && active.options.getCapability();
            active.apply.enabled = !!capability && !active.options.readOnly;
            active.button.enabled = current && !active.options.readOnly;
            if (capability && active.error.text === RpgAbilityCapabilities.message("capability_unavailable")) {
                active.error.text = "";
            }
        }
        RpgConditionCatalog.open = function (rule, initial, onApply, options) {
            originalOpen(rule, initial, onApply, options);
            var apply = $("#RuleSettingsApply");
            var refresh = $("#V2RefreshCapability");
            if (!refresh) {
                refresh = $.CreatePanel("Button", apply.GetParent() || $("#RuleSettings"), "V2RefreshCapability");
                refresh.AddClass("V2Button");
                refresh.AddClass("RpgConditionRefresh");
                var caption = $.CreatePanel("Label", refresh, "");
                caption.text = $.Localize("#dota2_rpg_v2_refresh_capability");
                caption.hittest = false;
                if (apply.GetParent() && apply.GetParent().MoveChildBefore) {
                    apply.GetParent().MoveChildBefore(refresh, apply);
                }
            }
            options = options || {};
            refresh.visible = !!options.getCapability && !options.readOnly;
            refresh.hittest = refresh.visible;
            active = options.getCapability ? {root:$("#RuleSettings"), apply:apply,
                error:$("#RuleSettingsError"), button:refresh, options:options} : null;
            var binding = active;
            refresh.SetPanelEvent("onactivate", function () {
                if (!binding || active !== binding || binding.root.BHasClass("Hidden") || options.readOnly
                    || options.isCurrent && !options.isCurrent()) { return; }
                GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {});
                update();
            });
            update();
        };
        // Run after the HUD has consumed the matching slot revision. The capability
        // cache itself rejects old revisions and checks the hero/rule/action key.
        ["rpg_action_capability", "rpg_hero_slots"].forEach(function (event) {
            GameEvents.Subscribe(event, function () { $.Schedule(0.0, update); });
        });
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

    installConditionRefresh();
    $.Schedule(0.0, installKnownPanels);
}());
