(function () {
    "use strict";
    var root = $("#CampaignDifficultyRoot");
    if (!root) { return; }
    var state = null, pending = false, requestSerial = 0;
    function valid(value) { return ["easy", "default", "hard"].indexOf(value) >= 0; }
    function flag(value) { return value === true || value === 1 || value === "1"; }
    function create(type, parent, id, css) {
        var p = $.CreatePanel(type, parent, id);
        if (css) { p.AddClass(css); }
        return p;
    }
    var modal = create("Panel", root, "CampaignDifficultyModal", "CampaignDifficultyModal");
    var card = create("Panel", modal, "CampaignDifficultyCard", "CampaignDifficultyCard");
    var choices = create("Panel", card, "CampaignDifficultyChoices", "CampaignDifficultyChoices");
    var buttons = {};
    ["easy", "default", "hard"].forEach(function (value) {
        var b = create("Button", choices, "CampaignDifficulty_" + value, "CampaignDifficultyButton");
        var label = create("Label", b, "", "");
        label.html = false; label.text = $.Localize("#dota2_rpg_difficulty_" + value);
        b.SetPanelEvent("onactivate", function () {
            if (!b.enabled) { return; }
            pending = true;
            var serial = ++requestSerial;
            render();
            GameEvents.SendCustomGameEventToServer("rpg_campaign_difficulty_select", { difficulty: value });
            // Recover from a lost response without letting an old timer unlock a newer request.
            $.Schedule(2, function () {
                if (serial !== requestSerial || !pending) { return; }
                pending = false; request(); render();
            });
        });
        buttons[value] = b;
    });
    function render() {
        var owner = state && Number(state.owner_player_id) === Players.GetLocalPlayer();
        var campaign = state && flag(state.campaign_active);
        var locked = state && flag(state.difficulty_locked);
        modal.visible = !!owner && campaign && !locked;
        Object.keys(buttons).forEach(function (value) {
            buttons[value].enabled = !!owner && campaign && !locked && !pending;
        });
    }
    function request() { GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {}); }
    GameEvents.Subscribe("rpg_campaign_difficulty", function (data) {
        if (!valid(data.campaign_difficulty)) { return; }
        state = data;
        if (flag(data.difficulty_locked) || !flag(data.campaign_active)) { pending = false; requestSerial++; }
        render();
    });
    render(); request();
})();
