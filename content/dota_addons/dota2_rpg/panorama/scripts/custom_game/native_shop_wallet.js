(function () {
    "use strict";

    // Valve's quick-buy ShopButton/GoldLabel uses {u:gold}, independently of
    // rpg_shop_state. Render the same server balance as our top HUD there too.
    // Keep the native label/style/button so shop clicks and tooltips still work.
    var context = $.GetContextPanel();
    var balance = null;

    function isValid(panel) {
        return panel && (!panel.IsValid || panel.IsValid());
    }

    function refresh() {
        if (balance === null || !isValid(context)) { return; }
        var root = context;
        while (root.GetParent && root.GetParent()) { root = root.GetParent(); }
        var controls = root.FindChildTraverse("ShopCourierControls");
        var button = controls && controls.FindChildTraverse("ShopButton");
        var label = button && button.FindChildTraverse("GoldLabel");
        if (isValid(label)) {
            // A literal removes the native dialog-variable binding on this label.
            // Never write the server wallet or infer spending from purchase events.
            if (label.text !== String(balance)) { label.text = String(balance); }
        }
    }

    function updateGold(gold) {
        var value = Number(gold);
        if (gold === null || gold === undefined || !isFinite(value)) { return; }
        balance = Math.max(0, Math.floor(value));
        refresh();
    }

    function watchNativePanel() {
        if (!isValid(context)) { return; }
        refresh();
        // Native HUD can appear later or rebuild when the portrait changes.
        $.Schedule(0.25, watchNativePanel);
    }

    GameUI.CustomUIConfig().RpgNativeShopWallet = { updateGold: updateGold };
    $.Schedule(0.25, watchNativePanel);
}());
