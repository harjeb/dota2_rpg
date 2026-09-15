/* Read-only tutorial browser. It never changes or submits a hero's rules. */
(function () {
    "use strict";
    var data = typeof RpgConditionHelpData !== "undefined" ? RpgConditionHelpData : {categories: [], basics: []};
    var modal = $("#ConditionHelp"), nav = $("#ConditionHelpNav"), body = $("#ConditionHelpBody");
    var search = $("#ConditionHelpSearch"), selected = "intro", query = "";
    if (!modal || !nav || !body || !search) { return; }
    var chinese = typeof $.Language !== "function" || $.Language().indexOf("chinese") >= 0;
    function words(value) {
        if (typeof value === "string") { return value; }
        return value ? (chinese ? value.zh || value.en : value.en || value.zh) || "" : "";
    }
    function t(zh, en) { return chinese ? zh : en; }
    function heroName(example) {
        if (example.hero_label) { return words(example.hero_label); }
        if (!example.hero) { return ""; }
        var token = "#" + example.hero;
        var name = typeof $.Localize === "function" ? $.Localize(token) : token;
        return name && name !== token && name !== example.hero ? name : example.hero.replace("npc_dota_hero_", "").replace(/_/g, " ");
    }
    function label(parent, text, className) {
        var p = $.CreatePanel("Label", parent, ""); p.text = words(text);
        if (className) { p.AddClass(className); } p.hittest = false; return p;
    }
    function section(text) { label(body, text, "HelpSectionTitle"); }
    function lines(values, numbered) {
        (values || []).forEach(function (value, index) {
            label(body, (numbered ? (index + 1) + ". " : "• ") + words(value), "HelpParagraph");
        });
    }
    function button(parent, id, title, callback) {
        var p = $.CreatePanel("Button", parent, id); p.AddClass("HelpNavButton");
        label(p, title, "HelpNavLabel"); p.SetPanelEvent("onactivate", callback); return p;
    }
    function showIntro() {
        label(body, t("从一条规则开始", "Start with one rule"), "HelpArticleTitle");
        label(body, t("选择英雄 → 选择技能或装备 → 条件设置 → 参考模板 → 应用。", "Select a hero → choose a skill or item → Condition settings → follow a template → Apply."), "HelpLead");
        section(t("设置顺序", "Setup order"));
        lines(data.basics, true);
        section(t("怎么使用这份教程", "Using this guide"));
        lines([
            t("左侧按技能用途浏览，也可以搜索示例技能或英雄名称。模板中的数值是起点，可按阵容和关卡调整。", "Browse by purpose or search for an example skill or hero. Template values are starting points; tune them for your lineup and stage."),
            t("选择动作时会载入可用的技能预设，随后在条件设置中编辑并应用；也可按完整索引查找条件编号和参数。", "Selecting an action loads an available skill preset; edit it in Condition settings and Apply. The complete indexes list condition codes and parameters."),
            t("使用条件和目标筛选分别选择“同时满足”或“按优先级”；需要共同成立的门槛用同时满足。引擎先尝试非普攻规则，再尝试普攻。", "Use conditions and target filters independently select Match all or Priority. Use Match all for combined requirements. The engine tries non-attack rules before attacks."),
            t("教程不会自动修改你的规则。阅读后关闭帮助，回到对应技能的设置中应用。", "The guide does not change your rules. Close it and apply your settings to the relevant skill.")
        ]);
        if (data.summary && data.summary.note) { section(t("覆盖范围", "Coverage")); label(body, data.summary.note, "HelpParagraph"); }
    }
    function showCategory(category) {
        label(body, category.title, "HelpArticleTitle");
        label(body, category.description, "HelpLead");
        if (category.examples && category.examples.length) {
            section(t("参考技能", "Example skills"));
            var examples = $.CreatePanel("Panel", body, ""); examples.AddClass("HelpExamples");
            category.examples.forEach(function (example) {
                var row = $.CreatePanel("Panel", examples, ""); row.AddClass("HelpExample");
                if (example.ability) {
                    var item = example.ability.indexOf("item_") === 0;
                    var icon = $.CreatePanel(item ? "DOTAItemImage" : "DOTAAbilityImage", row, ""); icon.AddClass("HelpSkillIcon");
                    if (item) { icon.itemname = example.ability; } else { icon.abilityname = example.ability; }
                }
                label(row, (heroName(example) ? heroName(example) + " · " : "") + words(example.label), "HelpExampleLabel");
            });
        }
        if (category.settings && category.settings.length) {
            section(category.coverage_role === "reference" ? t("条件与参数", "Conditions and parameters") : t("条件模板", "Condition template"));
            category.settings.forEach(function (setting) {
                var row = $.CreatePanel("Panel", body, ""); row.AddClass("HelpSettingRow");
                label(row, setting.label, "HelpSettingKey"); label(row, setting.value, "HelpSettingValue");
            });
        }
        if (category.steps && category.steps.length) { section(t("操作步骤", "Steps")); lines(category.steps, true); }
        if (category.notes && category.notes.length) { section(t("调整与注意", "Adjustments and notes")); lines(category.notes); }
    }
    function renderArticle() {
        body.RemoveAndDeleteChildren();
        var category = (data.categories || []).filter(function (entry) { return entry.id === selected; })[0];
        if (category) { showCategory(category); } else { showIntro(); }
        if (body.ScrollToTop) { body.ScrollToTop(); }
    }
    function matching(category) {
        return !query || (JSON.stringify(category) + " " + (category.examples || []).map(heroName).join(" ")).toLowerCase().indexOf(query) >= 0;
    }
    function renderNav() {
        nav.RemoveAndDeleteChildren();
        button(nav, "HelpIntro", t("快速入门", "Quick start"), function () { selected = "intro"; renderNav(); renderArticle(); }).SetHasClass("HelpNavSelected", selected === "intro");
        var matches = (data.categories || []).filter(matching);
        $("#ConditionHelpCount").text = t("教程章节 ", "Guide chapters ") + matches.length + " / " + (data.categories || []).length;
        matches.forEach(function (category) {
            button(nav, "HelpCategory_" + category.id, category.title, function () {
                selected = category.id; renderNav(); renderArticle();
            }).SetHasClass("HelpNavSelected", selected === category.id);
        });
        if (!matches.length) { label(nav, t("没有找到。试试“治疗”“位移”或“连招”。", "No matches. Try healing, mobility or combo."), "HelpEmpty"); }
    }
    function close() { modal.AddClass("Hidden"); if ($("#ConditionHelpButton").SetFocus) { $("#ConditionHelpButton").SetFocus(); } }
    function open() {
        modal.RemoveClass("Hidden"); renderNav(); renderArticle();
        if (search.SetFocus) { search.SetFocus(); }
    }
    $("#ConditionHelpButton").SetPanelEvent("onactivate", open);
    $("#ConditionHelpClose").SetPanelEvent("onactivate", close);
    $("#ConditionHelpBackdrop").SetPanelEvent("onactivate", close);
    modal.SetPanelEvent("oncancel", close);
    search.SetPanelEvent("oncancel", close);
    search.SetPanelEvent("ontextentrychange", function () { query = String(search.text || "").toLowerCase().trim(); renderNav(); });
    $("#ConditionHelpClear").SetPanelEvent("onactivate", function () { search.text = ""; query = ""; renderNav(); });
    $("#ConditionHelpTitle").text = t("技能条件指南", "Skill condition guide");
    $("#ConditionHelpSubtitle").text = t("按用途找模板，再到技能的“条件设置”中填写。", "Find a template by purpose, then enter it in the skill's Condition settings.");
    $("#ConditionHelpSearchHint").text = t("搜索条件编号、参数、技能或英雄", "Search condition codes, parameters, skills or heroes");
    $("#ConditionHelpFooter").text = t("帮助仅供参考 · 战斗不会暂停 · Esc 或点击右上角关闭", "Reference guide · Battle continues · Esc or the top-right button closes this page");
    $("#ConditionHelpCloseLabel").text = t("关闭 ×", "Close ×");
    $("#ConditionHelpClearLabel").text = t("清空", "Clear");
})();
