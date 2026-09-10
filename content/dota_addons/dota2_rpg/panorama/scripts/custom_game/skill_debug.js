/* Player-operated test session controls. The server owns heroes, money and stats. */
(function () {
    "use strict";
    var modal = $("#SkillDebug"), grid = $("#SkillDebugHeroes"), search = $("#SkillDebugSearch");
    if (!modal || !grid || !search) { return; }
    var zh = typeof $.Language !== "function" || $.Language().indexOf("chinese") >= 0;
    var state = {active: false, phase: "loading"}, heroes = [], selected = "", pending = "", damageDirty = false;
    function t(chinese, english) { return zh ? chinese : english; }
    function yes(value) { return value === true || value === 1 || value === "1"; }
    function send(event, payload) { GameEvents.SendCustomGameEventToServer(event, payload || {}); }
    function nativeName(hero) { return hero.indexOf("npc_dota_hero_") === 0 ? hero : "npc_dota_hero_" + hero; }
    function name(hero) {
        var token = "#" + nativeName(hero), value = $.Localize(token);
        return value && value !== token && value !== token.slice(1) ? value : hero.replace("npc_dota_hero_", "").replace(/_/g, " ");
    }
    function label(parent, text) { var p = $.CreatePanel("Label", parent, ""); p.text = text; p.hittest = false; return p; }
    function error(text) { $("#SkillDebugError").text = text || ""; }
    function busy() { return !!pending || yes(state.pending) || yes(state.loading); }
    function prepare() { return state.phase === "setup" || (state.phase === "result" && yes(state.run_complete)); }
    function damage() {
        var text = String($("#SkillDebugDamage").text || "").trim(), value = Number(text);
        if (!/^\d+$/.test(text) || !isFinite(value) || value < 0 || value > 10000) {
            error(t("攻击力请输入 0～10000 的整数。", "Enter an integer attack damage from 0 to 10000.")); return null;
        }
        return value;
    }
    function renderControls() {
        var active = yes(state.active), ready = !busy();
        $("#SkillDebugButton").SetHasClass("DebugActive", active);
        $("#SkillDebugButtonLabel").text = active ? t("调试中", "Testing") : t("技能调试", "Skill test");
        $("#SkillDebugSelected").text = selected ? name(selected) + t(" · 30 级", " · Level 30") : t("选择一名英雄", "Choose a hero");
        $("#SkillDebugStart").enabled = ready && prepare() && heroes.indexOf(selected) >= 0;
        $("#SkillDebugReset").enabled = ready && active && state.phase !== "fight";
        $("#SkillDebugApplyDamage").enabled = ready && active && state.phase === "setup";
        $("#SkillDebugExit").enabled = (active || yes(state.pending)) && pending !== "exit";
        if ($("#ShopPanel")) { $("#ShopPanel").SetHasClass("DebugHideRecruitment", active); }
        $("#SkillDebugStatus").text = busy() ? t("正在准备，请稍候…", "Preparing, please wait…") :
            state.phase === "fight" ? t("战斗进行中；可退出调试，或等本次测试结束后调整。", "Battle in progress. Exit testing, or adjust after this battle.") :
            active ? t("测试模式已开启。关闭面板即可设置条件、购买装备并开始战斗。", "Testing is active. Close this panel to edit conditions, buy items and start a battle.") :
            prepare() ? t("可开始一局新的技能测试。", "Ready to start a new skill test.") : t("等待准备阶段…", "Waiting for preparation…");
    }
    function renderHeroes() {
        var query = String(search.text || "").toLowerCase().trim(), shown = 0;
        grid.RemoveAndDeleteChildren();
        heroes.forEach(function (hero) {
            if (query && (hero + " " + name(hero)).toLowerCase().indexOf(query) < 0) { return; }
            shown++;
            var button = $.CreatePanel("Button", grid, "DebugHero_" + hero);
            button.AddClass("DebugHero"); button.SetHasClass("DebugSelected", hero === selected);
            var icon = $.CreatePanel("DOTAHeroImage", button, ""); icon.AddClass("DebugHeroIcon");
            icon.heroname = nativeName(hero); icon.heroimagestyle = "landscape"; icon.hittest = false;
            label(button, name(hero));
            button.SetPanelEvent("onactivate", function () { if (busy()) { return; } selected = hero; renderHeroes(); renderControls(); });
        });
        $("#SkillDebugCount").text = t("英雄 ", "Heroes ") + shown + " / " + heroes.length;
        if (!shown) { label(grid, heroes.length ? t("没有找到匹配的英雄。", "No matching heroes.") : t("正在获取英雄列表…", "Loading heroes…")); }
        if (grid.ScrollToTop) { grid.ScrollToTop(); }
    }
    function close() { modal.AddClass("Hidden"); if ($("#SkillDebugButton").SetFocus) { $("#SkillDebugButton").SetFocus(); } }
    function open() { modal.RemoveClass("Hidden"); error(""); renderHeroes(); renderControls(); send("rpg_debug_request"); if (search.SetFocus) { search.SetFocus(); } }
    function request(event, payload, action) { error(""); pending = action; renderControls(); send(event, payload); }
    function serverError(code) {
        var messages = {
            invalid_hero: t("请选择列表中的英雄。", "Choose a hero from the list."),
            invalid_damage: t("攻击力请输入 0～10000 的整数。", "Attack damage must be an integer from 0 to 10000."),
            wrong_phase: t("请在准备阶段进行此操作。", "Use this action during preparation."),
            busy: t("上一个操作仍在准备中。", "The previous request is still preparing."),
            unauthorized: t("只有当前玩家可以操作调试模式。", "Only the current player can control this test."),
            precache_failed: t("英雄资源准备失败，请重试。", "Hero loading failed. Please retry."),
            spawn_failed: t("测试单位创建失败，请重试。", "Test unit creation failed. Please retry.")
        };
        return messages[code] || t("操作未完成，请查看战斗日志后重试。", "The request failed. Check the battle log and retry.");
    }
    GameEvents.Subscribe("rpg_debug_state", function (data) {
        data = data || {};
        Object.keys(data).forEach(function (key) { state[key] = data[key]; });
        if (typeof data.heroes_text === "string") {
            var seen = {};
            heroes = data.heroes_text.split(";").filter(function (hero) {
                if (!/^(npc_dota_hero_)?[a-z0-9_]+$/.test(hero) || seen[hero]) { return false; }
                seen[hero] = true; return true;
            }).sort(function (a, b) { var x = name(a), y = name(b); return x < y ? -1 : x > y ? 1 : 0; });
        }
        if ((!selected || heroes.indexOf(selected) < 0) && heroes.indexOf(state.hero) >= 0) { selected = state.hero; }
        var failed = typeof data.error === "string" && data.error.length > 0;
        if (failed) { pending = ""; error(serverError(data.error)); }
        if (!yes(state.pending) && !yes(state.loading)) {
            var completed = pending;
            pending = "";
            if (!damageDirty || completed === "damage" || completed === "start") {
                if (data.attack_damage !== undefined) { $("#SkillDebugDamage").text = String(data.attack_damage); damageDirty = false; }
            }
            if (!failed && ((completed === "start" && yes(state.active) && state.hero === selected) ||
                (completed === "exit" && !yes(state.active)))) {
                if ($("#RuleSettings")) { $("#RuleSettings").AddClass("Hidden"); }
                close();
            }
        }
        renderHeroes(); renderControls();
    });
    GameEvents.Subscribe("rpg_battle_state", function (data) {
        if (data.phase) { state.phase = data.phase; }
        if (data.run_complete !== undefined) { state.run_complete = data.run_complete; }
        renderControls();
    });
    $("#SkillDebugButton").SetPanelEvent("onactivate", open);
    $("#SkillDebugClose").SetPanelEvent("onactivate", close);
    $("#SkillDebugBackdrop").SetPanelEvent("onactivate", close);
    modal.SetPanelEvent("oncancel", close); search.SetPanelEvent("oncancel", close);
    $("#SkillDebugDamage").SetPanelEvent("oncancel", close);
    search.SetPanelEvent("ontextentrychange", renderHeroes);
    $("#SkillDebugDamage").SetPanelEvent("ontextentrychange", function () { damageDirty = true; });
    $("#SkillDebugStart").SetPanelEvent("onactivate", function () {
        if (!$("#SkillDebugStart").enabled) { return; }
        var value = damage(); if (value === null) { return; }
        request("rpg_debug_start", {hero: selected, attack_damage: value}, "start");
    });
    $("#SkillDebugApplyDamage").SetPanelEvent("onactivate", function () {
        if (!$("#SkillDebugApplyDamage").enabled) { return; }
        var value = damage(); if (value === null) { return; }
        request("rpg_debug_damage", {attack_damage: value}, "damage");
    });
    $("#SkillDebugReset").SetPanelEvent("onactivate", function () { if ($("#SkillDebugReset").enabled) { request("rpg_debug_reset", {}, "reset"); } });
    $("#SkillDebugExit").SetPanelEvent("onactivate", function () { if ($("#SkillDebugExit").enabled) { request("rpg_debug_exit", {}, "exit"); } });
    $("#SkillDebugTitle").text = t("技能条件调试", "Skill condition testing");
    $("#SkillDebugCloseLabel").text = t("关闭 ×", "Close ×");
    $("#SkillDebugIntro").text = t("30 级英雄 ×1 · 金币 99999 · 测试怪生命 50000 · 每次战斗最多 120 秒", "One level-30 hero · 99999 gold · One enemy with 50000 HP · Up to 120 seconds per battle");
    $("#SkillDebugSearchHint").text = t("搜索英雄名称", "Search hero names");
    $("#SkillDebugDamageTitle").text = t("测试怪攻击力（0～10000）", "Enemy attack damage (0–10000)");
    $("#SkillDebugApplyDamageLabel").text = t("应用攻击力", "Apply damage");
    $("#SkillDebugInstructions").text = t("进入后自行学习技能与天赋、购买装备并设置条件。测试怪是普通单位；需要队友、多个目标或仅英雄目标的技能需对应场景。", "Learn skills and talents, buy equipment and edit conditions. The enemy is a basic unit; ally, multi-target and hero-only skills require matching targets.");
    $("#SkillDebugWarning").text = t("开始新的测试会重开当前局。重置测试保留装备与条件；退出调试后开始普通闯关的新局。", "Starting a new test replaces the current run. Reset keeps equipment and conditions. Exit starts a fresh normal run.");
    $("#SkillDebugStartLabel").text = t("开始新测试", "Start new test");
    $("#SkillDebugResetLabel").text = t("重置本次测试", "Reset current test");
    $("#SkillDebugExitLabel").text = t("退出调试", "Exit testing");
    $("#SkillDebugFooter").text = t("敌方行为会写入战斗日志 · 关闭面板不会退出调试 · 阅读时战斗继续", "Enemy behavior is logged · Closing this panel keeps testing active · Battle continues while reading");
    renderControls(); send("rpg_debug_request");
})();
