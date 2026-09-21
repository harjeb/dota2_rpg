(function () {
    "use strict";
    var root = $("#ArenaRoot");
    if (!root) { return; }
    var hudRoot = root.GetParent() || $.GetContextPanel();
    var state = { mode: "select", phase: "preparing", generation: -1, catalog: [], results: [] };
    var owner = false, selected = [], catalog = [], pending = "", pickerOpen = false, confirmingExit = false, selectorOpen = false;
    var strength = "similar", exportUrl = "", exportFilename = "", exportStatus = "";
    // Match the configured public Worker exactly; reject alternate origins and URL syntax.
    var exportPrefix = "https://dota2-rpg-leaderboard-api.dota2-rpg-leaderboard-worker.workers.dev/api/v1/arena/exports/";
    function validExportUrl(url) {
        if (typeof url !== "string" || url.indexOf(exportPrefix) !== 0) { return false; }
        var token = url.slice(exportPrefix.length);
        return token.length >= 16 && token.length <= 256 && !/[^A-Za-z0-9_-]/.test(token);
    }
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
        if (pending || !owner) { return; }
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
    var chips = create("Panel", hud, "ArenaResultsChips");
    var instructions = label(hud, "ArenaInstructions", "", "ArenaHint");
    label(hud, "ArenaPositionNote", local("positions"), "ArenaHint");
    var error = label(hud, "ArenaError", "", "ArenaError");
    var actions = create("Panel", hud, "ArenaActions", "ArenaActions");
    var start = button(actions, "ArenaStart", "start", function () { mutate("start"); });
    var retry = button(actions, "ArenaRetry", "retry", function () { mutate("retry"); });
    var replay = button(actions, "ArenaReplay", "replay", openPicker);
    var exit = button(actions, "ArenaExit", "exit", function () {
        if (state.phase === "finished") { mutate("exit"); }
        else { confirmingExit = true; render(); }
    });
    var featureActions = create("Panel", hud, "ArenaFeatureActions", "ArenaActions");
    var exportButton = button(featureActions, "ArenaExport", "export", function () {
        exportUrl = ""; exportFilename = ""; exportStatus = "exporting"; mutate("export");
    });
    var download = button(featureActions, "ArenaDownload", "download", function () {
        if (validExportUrl(exportUrl)) { $.DispatchEvent("ExternalBrowserGoToURL", exportUrl); }
    });
    var exportNote = label(hud, "ArenaExportStatus", "", "ArenaHint");
    var testActions = create("Panel", hud, "ArenaTestActions", "ArenaActions");
    var strengthButtons = {};
    ["lower", "similar", "higher"].forEach(function (value) {
        strengthButtons[value] = button(testActions, "ArenaStrength_" + value, "strength_" + value, function () { strength = value; render(); });
    });
    var test = button(testActions, "ArenaTest", "test", function () { mutate("test", { generation: state.generation, strength: strength }); });
    label(hud, "ArenaTestHint", local("test_hint"), "ArenaHint");
    var testResult = label(hud, "ArenaTestResult", "", "ArenaText");
    var summary = create("Panel", hud, "ArenaSummary");
    label(summary, "ArenaSummaryTitle", local("summary"), "ArenaTitle");
    var scores = label(summary, "ArenaScores", "", "ArenaText");
    var bonus = label(summary, "ArenaPerfectBonus", "", "ArenaText");
    label(summary, "ArenaResultsHeading", local("results_heading"), "ArenaHint");
    var rows = create("Panel", summary, "ArenaSummaryRows");
    var saveStatus = label(summary, "ArenaSaveStatus", "", "ArenaText");

    var selector = create("Panel", root, "ArenaModeSelector", "ArenaModal");
    create("Button", selector, "ArenaSelectorBackdrop", "ArenaBackdrop");
    var selectorCard = create("Panel", selector, "ArenaSelectorCard", "ArenaCard");
    label(selectorCard, "ArenaSelectorTitle", local("select_mode"), "ArenaTitle");
    label(selectorCard, "ArenaSelectorHint", local("select_mode_hint"), "ArenaHint");
    var campaignChoice = button(selectorCard, "ArenaChooseCampaign", "campaign", function () { selectorOpen = false; mutate("campaign"); });
    label(selectorCard, "ArenaCampaignDescription", local("campaign_description"), "ArenaText");
    var ladderChoice = button(selectorCard, "ArenaChooseLadder", "ladder", function () { selectorOpen = false; openPicker(); });
    label(selectorCard, "ArenaLadderDescription", local("ladder_description"), "ArenaText");
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
    label(confirmCard, "ArenaAbandonHint", local("abandon_hint"), "ArenaText");
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
    function signed(value) { return value === undefined || value === null ? "—" : (Number(value) > 0 ? "+" : "") + String(value); }
    function render() {
        var active = state.mode === "arena", completed = array(state.results).slice(0, 7);
        var selecting = !pickerOpen && !active && (state.mode === "select" || selectorOpen);
        hudRoot.SetHasClass("ArenaActive", active || state.mode === "select");
        root.SetHasClass("ArenaModalOpen", selecting || pickerOpen || confirmingExit && active);
        hud.SetHasClass("ArenaFighting", state.phase === "fighting");
        show(selector, selecting); show(selectorClose, state.mode !== "select");
        campaignChoice.enabled = ladderChoice.enabled = owner && !pending && state.generation >= 0;
        show(entry, owner && !active && state.mode !== "select"); show(hud, active); show(picker, pickerOpen); show(confirm, confirmingExit && active);
        text(heading, local("mode") + "  ·  R " + (state.round || 1) + " / 7  ·  " + local("rating") + " " + (state.rating === undefined ? 1500 : state.rating) + "  ·  " + local("wins") + " " + (state.wins || 0));
        text(opponent, local("opponent") + " " + (state.opponent_name || "—") + "  ·  " + (state.opponent_rating === undefined ? "—" : state.opponent_rating));
        var practice = flag(state.practice);
        text(phase, practice ? local("practice") : pending ? local("waiting") : local("phase_" + state.phase));
        text(instructions, local(practice ? "test_hint" : state.phase === "preparing" && flag(state.can_buy) ? "prepare_hint" : state.phase === "adjusting" ? "adjust_hint" : "series_hint"));
        if (practice) { text(heading, local("practice")); }
        var featureReady = active && owner && !pending && !practice && (state.phase === "preparing" || state.phase === "adjusting" || state.phase === "finished");
        exportButton.enabled = featureReady && flag(state.can_export);
        test.enabled = featureReady && flag(state.can_test);
        Object.keys(strengthButtons).forEach(function (value) {
            strengthButtons[value].enabled = test.enabled;
            strengthButtons[value].SetHasClass("ArenaSelected", strength === value);
        });
        download.enabled = featureReady && flag(state.can_export) && validExportUrl(exportUrl);
        show(download, !!exportUrl);
        text(exportNote, exportStatus ? local(exportStatus) + (exportUrl && exportFilename ? "  ·  " + exportFilename : "") : "");
        exportNote.SetHasClass("ArenaError", exportStatus === "export_failed" || exportStatus === "export_invalid_url");
        var lastTest = state.test_result;
        show(testResult, !!lastTest);
        if (lastTest) {
            var resultStrength = ["lower", "similar", "higher"].indexOf(lastTest.strength) >= 0 ? " · " + local("strength_" + lastTest.strength) : "";
            text(testResult, local("last_test") + " · " + local(flag(lastTest.won) ? "won" : "lost") + " · " + (lastTest.opponent_name || "—") + resultStrength + " · " + local("survivors") + " " + (lastTest.survivors === undefined ? "—" : lastTest.survivors) + " / " + local("deaths") + " " + (lastTest.deaths === undefined ? "—" : lastTest.deaths));
        }
        text(error, errorText());
        var canStart = owner && !pending && !practice && flag(state.can_start) && flag(state.can_edit) && (state.phase === "preparing" || state.phase === "adjusting");
        start.enabled = canStart;
        text(start.caption, local(state.phase === "adjusting" ? "continue" : "start"));
        show(start, state.phase === "preparing" || state.phase === "adjusting" || state.phase === "matching" || state.phase === "fighting" || state.phase === "transition");
        show(retry, state.phase === "error"); retry.enabled = owner && !pending && state.phase === "error";
        show(replay, state.phase === "finished"); replay.enabled = owner && !pending && state.phase === "finished";
        exit.enabled = owner && !pending; abandon.enabled = owner && !pending;
        chips.RemoveAndDeleteChildren();
        completed.forEach(function (result, index) { label(chips, "", (index + 1) + " " + local(flag(result.won) ? "won" : "lost"), flag(result.won) ? "ArenaChip ArenaWon" : "ArenaChip ArenaLost"); });
        show(chips, !practice);
        var finalView = !practice && (state.phase === "finished" || state.phase === "saving" || (state.phase === "error" && completed.length === 7));
        show(summary, finalView); hud.SetHasClass("ArenaFinal", finalView);
        if (finalView) {
            text(scores, local("rating") + " " + (state.rating_before === undefined ? "—" : state.rating_before) + " → " + (state.rating_after === undefined ? "—" : state.rating_after) + " (" + signed(state.rating_change) + ")");
            text(bonus, local("perfect_bonus") + " " + signed(state.perfect_bonus));
            text(saveStatus, local(state.phase === "finished" ? "saved" : state.phase === "saving" ? "saving" : "save_error"));
            rows.RemoveAndDeleteChildren();
            for (var i = 0; i < 7; i++) {
                var result = completed[i];
                label(rows, "ArenaResult" + (i + 1), result ? (i + 1) + "  ·  " + (result.opponent_name || "—") + " (" + (result.opponent_rating === undefined ? "—" : result.opponent_rating) + ")  ·  " + local(flag(result.won) ? "won" : "lost") + "  ·  " + local("survivors") + " " + (result.survivors === undefined ? "—" : result.survivors) + "  /  " + local("deaths") + " " + (result.deaths === undefined ? "—" : result.deaths) + "  ·  " + signed(result.delta) : (i + 1) + "  —", "ArenaResultRow");
            }
        }
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
    GameEvents.Subscribe("rpg_arena_export_result", function (event) {
        if (!event || event.generation !== state.generation || pending !== "export") { return; }
        pending = "";
        exportUrl = ""; exportFilename = "";
        if (event.error) { exportStatus = "export_failed"; }
        else if (!validExportUrl(event.url)) { exportStatus = "export_invalid_url"; }
        else { exportUrl = event.url; exportFilename = typeof event.filename === "string" ? event.filename : ""; exportStatus = "export_ready"; }
        render();
    });
    GameEvents.Subscribe("rpg_arena_state", function (event) {
        var next;
        try { next = JSON.parse(event.state_json); } catch (e) { return; }
        if (!next || ["select", "campaign", "arena"].indexOf(next.mode) < 0 || typeof next.generation !== "number" || !isFinite(next.generation) || Math.floor(next.generation) !== next.generation || next.generation < state.generation) { return; }
        var wasPending = pending;
        var newGeneration = next.generation !== state.generation;
        if (newGeneration) { exportUrl = ""; exportFilename = ""; exportStatus = ""; }
        state = next;
        if (wasPending === "campaign" && state.mode === "campaign") { selectorOpen = false; pickerOpen = false; }
        // Same-generation broadcasts must not unlock an export still awaiting its result.
        pending = wasPending === "export" && !newGeneration && !state.error ? "export" : "";
        if (wasPending === "export" && !newGeneration && state.error) { exportStatus = "export_failed"; }
        catalog = array(state.catalog).filter(function (hero, index, list) { return typeof hero === "string" && /^npc_dota_hero_[a-z0-9_]+$/.test(hero) && list.indexOf(hero) === index; });
        selected = selected.filter(function (hero) { return catalog.indexOf(hero) >= 0; });
        if ((wasPending === "enter" && state.mode === "arena" && state.phase !== "error") || state.mode === "arena" && state.phase !== "finished" && state.phase !== "error") { pickerOpen = false; }
        if (state.mode !== "arena") { confirmingExit = false; }
        render();
    });
    render(); send("request");
})();
