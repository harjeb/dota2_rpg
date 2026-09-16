(function () {
    "use strict";
    var root = $("#ArenaRoot");
    if (!root) { return; }
    var hudRoot = root.GetParent() || $.GetContextPanel();
    var state = { mode: "select", phase: "preparing", generation: -1, catalog: [], results: [] };
    var owner = false, selected = [], catalog = [], pending = "", pickerOpen = false, confirmingExit = false, selectorOpen = false;
    var strength = "similar";
    function local(key) { return $.Localize("#arena_" + key); }
    function text(panel, value) { panel.html = false; panel.text = String(value === undefined || value === null ? "—" : value); }
    function create(type, parent, id, css) {
        var p = $.CreatePanel(type, parent, id);
        if (css) { css.split(/\s+/).forEach(function (name) { p.AddClass(name); }); }
        return p;
    }
    function label(parent, id, value, css) { var p = create("Label", parent, id, css); text(p, value); p.hittest = false; return p; }
    function button(parent, id, key, callback) {
        var p = create("Button", parent, id, "ArenaButton");
        p.caption = label(p, id + "Label", local(key));
        p.SetPanelEvent("onactivate", function () { if (p.enabled) { callback(); } });
        return p;
    }
    function show(p, yes) { p.SetHasClass("ArenaHidden", !yes); }
    function array(value) {
        if (Array.isArray(value)) { return value; }
        if (!value || typeof value !== "object") { return []; }
        return Object.keys(value).filter(function (k) { return /^\d+$/.test(k); }).sort(function (a, b) { return Number(a) - Number(b); }).map(function (k) { return value[k]; });
    }
    function send(action, data) { GameEvents.SendCustomGameEventToServer("rpg_arena_" + action, data || {}); }
    function mutate(action, data) {
        if (pending || !owner || action === "start" || action === "export") { return; }
        pending = action;
        data = data || {};
        data.generation = state.generation;
        send(action, data);
        render();
    }
    function heroName(hero) { var name = $.Localize("#" + hero); return !name || name === "#" + hero || name === hero ? hero.replace("npc_dota_hero_", "").replace(/_/g, " ") : name; }
    var entry = button(root, "ArenaModeButton", "switch_mode", function () { selectorOpen = true; render(); });
    var hud = create("Panel", root, "ArenaHUD");
    var heading = label(hud, "ArenaHeading", "", "ArenaTitle");
    var opponent = label(hud, "ArenaOpponent", "", "ArenaText");
    var phase = label(hud, "ArenaPhase", "", "ArenaText");
    var instructions = label(hud, "ArenaInstructions", "", "ArenaHint");
    label(hud, "ArenaPositionNote", local("positions"), "ArenaHint");
    var error = label(hud, "ArenaError", "", "ArenaError");
    var actions = create("Panel", hud, "ArenaActions", "ArenaActions");
    var retry = button(actions, "ArenaRetry", "retry", function () { mutate("retry"); });
    var replay = button(actions, "ArenaReplay", "replay", openPicker);
    var exit = button(actions, "ArenaExit", "exit", function () {
        if (state.phase === "finished") { mutate("exit"); }
        else { confirmingExit = true; render(); }
    });
    var testActions = create("Panel", hud, "ArenaTestActions", "ArenaActions");
    var strengthButtons = {};
    ["lower", "similar", "higher"].forEach(function (value) {
        strengthButtons[value] = button(testActions, "ArenaStrength_" + value, "strength_" + value, function () { strength = value; render(); });
    });
    var test = button(testActions, "ArenaTest", "test", function () { mutate("test", { generation: state.generation, strength: strength }); });
    label(hud, "ArenaTestHint", local("test_hint"), "ArenaHint");
    var testResult = label(hud, "ArenaTestResult", "", "ArenaText");

    var selector = create("Panel", root, "ArenaModeSelector", "ArenaModal");
    create("Button", selector, "ArenaSelectorBackdrop", "ArenaBackdrop");
    var selectorCard = create("Panel", selector, "ArenaSelectorCard", "ArenaCard");
    label(selectorCard, "ArenaSelectorTitle", local("select_mode"), "ArenaTitle");
    label(selectorCard, "ArenaSelectorHint", local("select_mode_hint"), "ArenaHint");
    var campaignChoice = button(selectorCard, "ArenaChooseCampaign", "campaign", function () { selectorOpen = false; mutate("campaign"); });
    label(selectorCard, "ArenaCampaignDescription", local("campaign_description"), "ArenaText");
    var ladderChoice = button(selectorCard, "ArenaChooseLadder", "offline_mode", function () { selectorOpen = false; openPicker(); });
    label(selectorCard, "ArenaLadderDescription", local("offline_hint"), "ArenaText");
    var selectorClose = button(selectorCard, "ArenaSelectorClose", "close", function () { selectorOpen = false; render(); });
    var picker = create("Panel", root, "ArenaPicker", "ArenaModal");
    picker.hittest = true; picker.hittestchildren = true;
    var backdrop = create("Button", picker, "ArenaPickerBackdrop", "ArenaBackdrop");
    backdrop.SetPanelEvent("onactivate", closePicker);
    var card = create("Panel", picker, "ArenaPickerCard", "ArenaCard");
    card.hittest = true;
    var pickerHeader = create("Panel", card, "ArenaPickerHeader", "ArenaActions");
    label(pickerHeader, "ArenaPickerTitle", local("choose"), "ArenaTitle");
    button(pickerHeader, "ArenaPickerClose", "close", closePicker);
    label(card, "ArenaPickerHint", local("choose_hint"), "ArenaHint");
    label(card, "ArenaSearchHint", local("search"), "ArenaHint");
    var search = create("TextEntry", card, "ArenaSearch");
    search.text = "";
    search.SetPanelEvent("ontextentrychange", renderHeroes);
    search.SetPanelEvent("oncancel", closePicker);
    var count = label(card, "ArenaSelectedCount", "", "ArenaText");
    var selectedStrip = create("Panel", card, "ArenaSelectedHeroes");
    var heroes = create("Panel", card, "ArenaHeroes");
    var pickerError = label(card, "ArenaPickerError", "", "ArenaError");
    var enter = button(card, "ArenaEnter", "enter", function () {
        if (selected.length === 5) { mutate("enter", { heroes_text: selected.join(";") }); }
    });
    var confirm = create("Panel", root, "ArenaExitConfirm", "ArenaModal");
    confirm.hittest = true;
    create("Button", confirm, "ArenaExitBackdrop", "ArenaBackdrop");
    var confirmCard = create("Panel", confirm, "ArenaExitCard", "ArenaCard");
    label(confirmCard, "ArenaAbandonHint", local("offline_exit_hint"), "ArenaText");
    var abandon = button(confirmCard, "ArenaAbandon", "abandon", function () { confirmingExit = false; mutate("exit"); });
    button(confirmCard, "ArenaKeepPlaying", "cancel", function () { confirmingExit = false; render(); });

    function openPicker() {
        if (!owner || pending || (state.mode === "arena" && state.phase !== "finished")) { return; }
        selected = []; search.text = ""; pickerOpen = true; send("request"); render();
    }
    function closePicker() { pickerOpen = false; if (state.mode !== "arena") { selectorOpen = true; } render(); }
    function toggleHero(hero) {
        if (pending) { return; }
        var i = selected.indexOf(hero);
        if (i >= 0) { selected.splice(i, 1); }
        else if (selected.length < 5) { selected.push(hero); }
        renderHeroes();
    }
    function heroTile(parent, hero, prefix) {
        var tile = create("Button", parent, prefix + hero, "ArenaHero");
        tile.SetHasClass("ArenaSelected", selected.indexOf(hero) >= 0);
        tile.enabled = !pending && (selected.indexOf(hero) >= 0 || selected.length < 5);
        var icon = create("DOTAHeroImage", tile, "", "ArenaHeroIcon");
        icon.heroname = hero; icon.heroimagestyle = "landscape"; icon.hittest = false;
        label(tile, "", (selected.indexOf(hero) >= 0 ? "✓ " : "") + heroName(hero));
        tile.SetPanelEvent("onactivate", function () { if (tile.enabled) { toggleHero(hero); } });
    }
    function renderHeroes() {
        if (!pickerOpen) { return; }
        heroes.RemoveAndDeleteChildren(); selectedStrip.RemoveAndDeleteChildren();
        selected.forEach(function (hero) { heroTile(selectedStrip, hero, "ArenaChosen_"); });
        var query = String(search.text || "").toLowerCase().trim();
        var filtered = catalog.filter(function (hero) { return (heroName(hero) + " " + hero).toLowerCase().indexOf(query) >= 0; });
        filtered.forEach(function (hero) { heroTile(heroes, hero, "ArenaHero_"); });
        if (!filtered.length) { label(heroes, "", local(catalog.length ? "no_matches" : "loading"), "ArenaHint"); }
        text(count, local("selected") + " " + selected.length + " / 5  ·  " + catalog.length);
        enter.enabled = owner && !pending && selected.length === 5;
        text(pickerError, pending ? local("waiting") : errorText());
    }
    function flag(value) { return value === true || value === 1 || value === "1"; }
    function errorText() {
        if (!state.error) { return ""; }
        var key = String(state.error).replace(/^#/, "");
        if (key.indexOf("arena_") !== 0) { key = "arena_" + key; }
        var value = $.Localize("#" + key);
        return !value || value === "#" + key || value === key ? local("error_generic") : value;
    }
    function render() {
        var active = state.mode === "arena";
        var selecting = !pickerOpen && !active && (state.mode === "select" || selectorOpen);
        hudRoot.SetHasClass("ArenaActive", active || state.mode === "select");
        root.SetHasClass("ArenaModalOpen", selecting || pickerOpen || confirmingExit && active);
        hud.SetHasClass("ArenaFighting", state.phase === "fighting");
        show(selector, selecting); show(selectorClose, state.mode !== "select");
        campaignChoice.enabled = ladderChoice.enabled = owner && !pending && state.generation >= 0;
        show(entry, owner && !active && state.mode !== "select"); show(hud, active); show(picker, pickerOpen); show(confirm, confirmingExit && active);
        text(heading, local("offline_mode"));
        text(opponent, local("opponent") + " " + (state.opponent_name || "—") + "  ·  " + (state.opponent_rating === undefined ? "—" : state.opponent_rating));
        var practice = flag(state.practice);
        text(phase, practice ? local("practice") : pending ? local("waiting") : local("phase_" + state.phase));
        text(instructions, local(practice ? "test_hint" : "offline_hint"));
        if (practice) { text(heading, local("practice")); }
        var featureReady = active && owner && !pending && !practice && (state.phase === "preparing" || state.phase === "adjusting" || state.phase === "finished");
        test.enabled = featureReady && flag(state.can_test);
        Object.keys(strengthButtons).forEach(function (value) {
            strengthButtons[value].enabled = test.enabled;
            strengthButtons[value].SetHasClass("ArenaSelected", strength === value);
        });
        var lastTest = state.test_result;
        show(testResult, !!lastTest);
        if (lastTest) {
            var resultStrength = ["lower", "similar", "higher"].indexOf(lastTest.strength) >= 0 ? " · " + local("strength_" + lastTest.strength) : "";
            text(testResult, local("last_test") + " · " + local(flag(lastTest.won) ? "won" : "lost") + " · " + (lastTest.opponent_name || "—") + resultStrength + " · " + local("survivors") + " " + (lastTest.survivors === undefined ? "—" : lastTest.survivors) + " / " + local("deaths") + " " + (lastTest.deaths === undefined ? "—" : lastTest.deaths));
        }
        text(error, errorText());
        show(retry, state.phase === "error"); retry.enabled = owner && !pending && state.phase === "error";
        show(replay, state.phase === "finished"); replay.enabled = owner && !pending && state.phase === "finished";
        exit.enabled = owner && !pending; abandon.enabled = owner && !pending;
        renderHeroes();
    }
    GameEvents.Subscribe("rpg_battle_state", function (data) {
        if (data.owner_player_id !== undefined && typeof Players !== "undefined" && typeof Players.GetLocalPlayer === "function") {
            var wasOwner = owner;
            owner = Players.GetLocalPlayer() === Number(data.owner_player_id);
            if (!owner) { pickerOpen = false; confirmingExit = false; }
            if (owner && !wasOwner) { send("request"); }
            render();
        }
    });
    GameEvents.Subscribe("rpg_arena_state", function (event) {
        var next;
        try { next = JSON.parse(event.state_json); } catch (e) { return; }
        if (!next || ["select", "campaign", "arena"].indexOf(next.mode) < 0 || typeof next.generation !== "number" || !isFinite(next.generation) || Math.floor(next.generation) !== next.generation || next.generation < state.generation) { return; }
        var wasPending = pending;
        state = next;
        if (wasPending === "campaign" && state.mode === "campaign") { selectorOpen = false; pickerOpen = false; }
        pending = "";
        catalog = array(state.catalog).filter(function (hero, index, list) { return typeof hero === "string" && /^npc_dota_hero_[a-z0-9_]+$/.test(hero) && list.indexOf(hero) === index; });
        selected = selected.filter(function (hero) { return catalog.indexOf(hero) >= 0; });
        if ((wasPending === "enter" && state.mode === "arena" && state.phase !== "error") || state.mode === "arena" && state.phase !== "finished" && state.phase !== "error") { pickerOpen = false; }
        if (state.mode !== "arena") { confirmingExit = false; }
        render();
    });
    render(); send("request");
})();
