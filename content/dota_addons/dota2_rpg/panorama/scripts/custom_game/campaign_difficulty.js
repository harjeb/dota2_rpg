(function () {
    "use strict";
    var root = $("#CampaignDifficultyRoot");
    if (!root) { return; }
    var state = null, pending = false;
    var draft = root.campaignDifficultyDraft || "default";
    function valid(value) { return ["easy", "default", "hard"].indexOf(value) >= 0; }
    function flag(value) { return value === true || value === 1 || value === "1"; }
    function local(key) { return $.Localize("#dota2_rpg_difficulty_" + key); }
    function create(type, parent, id, css) {
        var p = $.CreatePanel(type, parent, id);
        if (css) { p.AddClass(css); }
        return p;
    }
    function label(parent, id, key) {
        var p = create("Label", parent, id); p.html = false; p.text = local(key); return p;
    }
    var badge = label(root, "CampaignDifficultyBadge", "default");
    var modal = create("Panel", root, "CampaignDifficultyModal", "CampaignDifficultyModal");
    var card = create("Panel", modal, "CampaignDifficultyCard", "CampaignDifficultyCard");
    label(card, "CampaignDifficultyTitle", "title");
    label(card, "CampaignDifficultyHint", "hint");
    var choices = create("Panel", card, "CampaignDifficultyChoices", "CampaignDifficultyChoices");
    var buttons = {};
    ["easy", "default", "hard"].forEach(function (value) {
        var b = create("Button", choices, "CampaignDifficulty_" + value, "CampaignDifficultyButton");
        label(b, "", value);
        b.SetPanelEvent("onactivate", function () {
            if (!b.enabled) { return; }
            draft = value; root.campaignDifficultyDraft = value; render();
        });
        buttons[value] = b;
    });
    label(card, "CampaignDifficultyRanking", "ranking");
    var confirm = create("Button", card, "CampaignDifficultyConfirm", "CampaignDifficultyButton");
    label(confirm, "", "confirm");
    confirm.SetPanelEvent("onactivate", function () {
        if (!confirm.enabled) { return; }
        pending = true; render();
        GameEvents.SendCustomGameEventToServer("rpg_campaign_difficulty_select", { difficulty: draft });
        // A lost response must not strand the modal. The server remains authoritative.
        $.Schedule(2, function () { pending = false; request(); render(); });
    });
    function render() {
        var owner = state && Number(state.owner_player_id) === Players.GetLocalPlayer();
        var campaign = state && flag(state.campaign_active);
        var locked = state && flag(state.difficulty_locked);
        modal.visible = !!owner && campaign && !locked;
        badge.visible = !!state && campaign && locked;
        if (state) { badge.text = local(state.campaign_difficulty) + " · " + local("rewards") + " ×" + state.reward_multiplier; }
        Object.keys(buttons).forEach(function (value) {
            buttons[value].enabled = !!owner && campaign && !locked && !pending;
            buttons[value].SetHasClass("CampaignDifficultySelected", draft === value);
        });
        confirm.enabled = !!owner && campaign && !locked && !pending;
    }
    function request() { GameEvents.SendCustomGameEventToServer("rpg_request_battle_state", {}); }
    GameEvents.Subscribe("rpg_campaign_difficulty", function (data) {
        if (!valid(data.campaign_difficulty)) { return; }
        state = data; pending = false;
        if (flag(data.difficulty_locked)) { draft = data.campaign_difficulty; root.campaignDifficultyDraft = draft; }
        render();
    });
    render(); request();
})();
