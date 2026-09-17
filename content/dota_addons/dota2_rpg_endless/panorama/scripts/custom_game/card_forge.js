(function () {
    "use strict";
    var root = $("#CardForgeRoot"), M = GameUI.CustomUIConfig().CardForgeModel;
    if (!root || !M) { return; }
    // This gallery deliberately has no server mutation transport. All assets are preview fixtures.
    var state = M.initial(), selected = "H-lina", faction = "all", kind = "all", query = "", descending = true;
    var history = [], drag = null, noticeGeneration = 0, modalKind = "", open = false;
    var slots = {}, cards = {}, types = ["all", "hero", "buff", "charge", "field"];
    var validFactions = Object.keys(M.factions);
    var errorKeys = {
        "专属槽只能装备该英雄的专属卡":"wrong_hero", "英雄专属卡需要对应英雄的专属槽":"wrong_slot",
        "卡库已满，无法退回被替换卡；请先腾出位置":"full", "卡库已满，请先腾出位置":"full", "卡库已满，无法获得新卡":"full",
        "卡牌已经在该槽位":"already", "该装载等级尚未解锁":"level_locked", "构筑已锁定，请先返回准备":"locked",
        "只有专属卡可以熔炼":"smelt_only", "请先卸下这张专属卡":"unequip_first", "需要 3 点对应阵营印记":"marks_needed",
        "本波购买次数已用完":"purchases_used", "金币不足":"gold_needed", "COST 超出预算，请降低装载等级或卸卡":"over_budget"
    };
    function local(key) { return $.Localize("#cf_" + key); }
    function heroName(id) { return $.Localize("#npc_dota_hero_" + id); }
    function cardName(card) { return local("card_" + card.id.replace(/-/g, "_")); }
    function factionName(id) { return local("faction_" + id); }
    function fmt(key, values) {
        var result = local(key);
        Object.keys(values || {}).forEach(function (name) { result = result.split("{" + name + "}").join(String(values[name])); });
        return result;
    }
    function panel(type, parent, id, classes) {
        var p = $.CreatePanel(type, parent, id || "");
        (classes || "").split(" ").filter(Boolean).forEach(function (css) { p.AddClass(css); });
        return p;
    }
    function label(parent, id, value, css) { var p = panel("Label", parent, id, css); p.html = false; p.text = value; p.hittest = false; return p; }
    function button(parent, id, value, css, callback) {
        var p = panel("Button", parent, id, css); label(p, "", value);
        p.SetPanelEvent("onactivate", function () { if (p.enabled) { callback(); } }); return p;
    }
    function show(p, yes) { p.SetHasClass("CfHidden", !yes); }
    function image(parent, hero, css) {
        var p = panel("DOTAHeroImage", parent, "", css); p.heroname = "npc_dota_hero_" + hero;
        p.heroimagestyle = "portrait"; p.hittest = false; return p;
    }
    function background(p, f) { p.style.backgroundImage = 'url("file://{images}/custom_game/card_forge/' + f + '_png.vtex")'; }
    function notify(message, error) {
        var notice = $("#CfNotice"), generation = ++noticeGeneration;
        notice.text = message; notice.SetHasClass("CfError", !!error); show(notice, true);
        $.Schedule(3.5, function () { if (generation === noticeGeneration) { show(notice, false); } });
    }
    function errorMessage(error) { return local(errorKeys[error] || "invalid"); }
    function execute(action, message) {
        var result = M.apply(state, action);
        if (result.error) { notify(errorMessage(result.error), true); return false; }
        if (["buy", "exchange", "smelt", "confirm", "return"].indexOf(action.type) < 0) {
            history.push(state); if (history.length > 30) { history.shift(); }
        } else { history = []; }
        state = result.state;
        // Native DragEnd must run on the original source panel before it is destroyed.
        if (!drag) { render(); }
        if (message) { notify(local(message), false); } return true;
    }
    function cardView(parent, card, detail) {
        var p = panel("Panel", parent, "", "CfCard"); background(p, card.faction);
        var well = panel("Panel", p, "", "CfArtWell"); well.hittest = false; well.hittestchildren = false;
        image(well, card.art, "CfCardArt"); panel("Panel", well, "", "CfCardShade").hittest = false;
        var copy = panel("Panel", p, "", "CfCardCopy"); copy.hittest = false; copy.hittestchildren = false;
        label(copy, "", cardName(card), "CfCardName"); label(copy, "", factionName(card.faction) + " · " + local("type_" + card.type), "CfCardType");
        label(copy, "", "◆".repeat(card.level) + "◇".repeat(3 - card.level), "CfCardLevel");
        label(p, "", String(M.cost(card)), "CfCardCost");
        if (!detail) {
            cards[card.id] = p; p.SetHasClass("CfSelected", selected === card.id);
            p.SetPanelEvent("onactivate", function () { selected = card.id; renderSelection(); });
            attachDrag(p, card.id);
        }
        return p;
    }
    function attachDrag(p, id) {
        p.SetDraggable(state.phase === "prepare");
        $.RegisterEventHandler("DragStart", p, function (source, callback) {
            if (!open || state.phase !== "prepare" || drag) { return false; }
            selected = id; var ghost = cardView(root, M.get(state, id), true);
            ghost.AddClass("CfDragGhost"); ghost.hittest = false; ghost.hittestchildren = false;
            drag = { id: id, display: ghost, consumed: false };
            callback.displayPanel = ghost; callback.offsetX = 65; callback.offsetY = 85;
            renderSelection(); return true;
        });
        $.RegisterEventHandler("DragEnd", p, function () {
            if (drag) { drag.display.DeleteAsync(0); drag = null; }
            $("#CfInventory").RemoveClass("CfDropHover");
            render(); return true;
        });
    }
    function dropTarget(p, key) {
        $.RegisterEventHandler("DragEnter", p, function (target, display) {
            if (!drag || display !== drag.display) { return false; }
            var error = key ? M.eligibility(state, drag.id, key) : null;
            p.SetHasClass("CfDropHover", !error); p.SetHasClass("CfDropInvalid", !!error);
            if (key) { preview(key); } return !error;
        });
        $.RegisterEventHandler("DragLeave", p, function () { p.RemoveClass("CfDropHover"); p.RemoveClass("CfDropInvalid"); return true; });
        $.RegisterEventHandler("DragDrop", p, function (target, display) {
            if (!drag || drag.consumed || display !== drag.display) { return false; }
            drag.consumed = true;
            var success = key ? execute({type:"equip", id:drag.id, slot:key}, "equipped") : execute({type:"unequip", id:drag.id}, "unequipped");
            p.RemoveClass("CfDropHover"); p.RemoveClass("CfDropInvalid"); return success;
        });
    }
    function preview(key) {
        var id = drag ? drag.id : selected;
        if (!id || !M.get(state, id)) { return; }
        var result = M.apply(state, {type:"equip", id:id, slot:key});
        $("#CfDropHint").text = result.error ? errorMessage(result.error) : fmt("drop_preview", {hero:heroName(key.split(":")[0]), before:M.used(state), after:M.used(result.state)});
    }
    function renderSelection() {
        Object.keys(cards).forEach(function (id) { cards[id].SetHasClass("CfSelected", id === selected); });
        Object.keys(slots).forEach(function (key) {
            var active = !!selected && !!M.get(state, selected) && state.phase === "prepare";
            var allowed = active && !M.eligibility(state, selected, key);
            slots[key].SetHasClass("CfEligible", !!allowed); slots[key].SetHasClass("CfIneligible", !!active && !allowed);
        });
        renderInspector();
    }
    function renderGrid() {
        var grid = $("#CfGrid"); grid.RemoveAndDeleteChildren(); cards = {};
        var list = M.inventory(state).filter(function (c) {
            var text = cardName(c) + " " + factionName(c.faction) + " " + (c.hero ? heroName(c.hero) : "");
            return (faction === "all" || c.faction === faction) && (kind === "all" || c.type === kind) && text.toLowerCase().indexOf(query.toLowerCase()) >= 0;
        });
        list.sort(function (a, b) { return (descending ? b.level - a.level : a.level - b.level) || a.id.localeCompare(b.id); });
        list.forEach(function (card) { cardView(grid, card, false); });
        show($("#CfEmpty"), list.length === 0);
    }
    function renderInspector() {
        var target = $("#CfInspector"); target.RemoveAndDeleteChildren();
        var c = M.get(state, selected);
        if (!c) { label(target, "", local("select_hint"), "CfDetailText"); return; }
        label(target, "", local("detail"), "CfEyebrow");
        cardView(target, c, true).AddClass("CfShowcase");
        label(target, "", cardName(c), "CfDetailTitle"); panel("Panel", target, "", "CfDetailRule");
        label(target, "", c.hero ? fmt("hero_only", {hero:heroName(c.hero)}) : local("general_any"), "CfDetailText");
        label(target, "", local("all_allies"), "CfDetailText");
        label(target, "", c.type === "charge" ? fmt("charges", {n:c.load}) : local(c.type === "field" ? "field_lifecycle" : "battle_lifecycle"), "CfDetailText");
        label(target, "", fmt("owned_level", {n:c.level, copies:c.copies}), "CfSmall");
        var row = panel("Panel", target, "", "CfLevelRow");
        [1,2,3].forEach(function (n) {
            var b = button(row, "CfLevel" + n, "Lv." + n, "CfLevel", function () { execute({type:"level", id:c.id, level:n}, "level_changed"); });
            label(b, "", M.curves[c.tier][n-1] + " COST", "CfSmall");
            b.enabled = n <= c.level && state.phase === "prepare"; b.SetHasClass("CfActive", n === c.load);
        });
        var actions = panel("Panel", target, "", "CfDetailActions"), location = M.location(state, c.id);
        var equip = button(actions, "CfDetailEquip", local(location ? "unequip" : "select_slot"), "CfMetal", function () {
            if (location) { execute({type:"unequip", id:c.id}, "unequipped"); } else { notify(local("select_slot_hint")); }
        }); equip.enabled = state.phase === "prepare";
        if (c.type === "hero") {
            var smelt = button(actions, "CfDetailSmelt", local("smelt"), "CfMetal", function () { showSmelt(c.id); }); smelt.enabled = !location && state.phase === "prepare";
        }
        label(target, "", location ? fmt("equipped_on", {hero:heroName(location.split(":")[0])}) : local("drag_hint"), "CfSmall");
        label(target, "", local("effects_pending"), "CfSmall");
    }
    function renderRoster() {
        var roster = $("#CfRoster"); roster.RemoveAndDeleteChildren(); slots = {};
        state.heroes.forEach(function (h) {
            var unit = panel("Panel", roster, "", "CfHeroUnit"), portrait = panel("Panel", unit, "", "CfHeroPortrait");
            image(portrait, h.id, "CfHeroArt"); panel("Panel", portrait, "", "CfCardShade").hittest = false;
            label(portrait, "", heroName(h.id), "CfHeroName"); label(portrait, "", "Lv." + h.level, "CfHeroLevel");
            var row = panel("Panel", unit, "", "CfSlots");
            ["hero", "general"].forEach(function (type) {
                var key = h.id + ":" + type, c = M.get(state, state.slots[key]);
                var slot = panel("Panel", row, "CfSlot_" + h.id + "_" + type, "CfSlot"); slots[key] = slot;
                if (c) { image(slot, c.art, "CfSlotArt"); attachDrag(slot, c.id); }
                var copy = panel("Panel", slot, "", "CfSlotCopy"); copy.hittest = false; copy.hittestchildren = false;
                label(copy, "", c ? cardName(c) : local("slot_" + type));
                label(copy, "", c ? "Lv." + c.load + " · " + M.cost(c) + " COST" : "◇", "CfSmall");
                slot.SetPanelEvent("onactivate", function () {
                    if (state.phase !== "prepare") { notify(local("locked"), true); return; }
                    if (selected && M.get(state, selected) && selected !== state.slots[key]) { execute({type:"equip", id:selected, slot:key}, "equipped"); }
                    else if (c) { selected = c.id; renderSelection(); }
                });
                slot.SetPanelEvent("oncontextmenu", function () { if (c) { selected = c.id; renderSelection(); } });
                slot.SetPanelEvent("onmouseover", function () { preview(key); });
                slot.SetPanelEvent("onmouseout", function () { $("#CfDropHint").text = local("drag_hint"); });
                dropTarget(slot, key);
            });
        });
    }
    function render() {
        $("#CfCapacity").text = M.inventory(state).length + " / 24";
        $("#CfWallet").text = "◈ " + state.gold;
        $("#CfCost").text = "COST  " + M.used(state) + " / " + M.budget(state);
        $("#CfCost").SetHasClass("CfOver", M.used(state) > M.budget(state));
        $("#CfBudgetBar").max = M.budget(state); $("#CfBudgetBar").value = Math.min(M.used(state), M.budget(state));
        $("#CfBudgetBar").SetHasClass("CfOver", M.used(state) > M.budget(state));
        $("#CfConfirm").enabled = state.phase === "prepare" && M.used(state) <= M.budget(state);
        $("#CfUndo").enabled = history.length > 0 && state.phase === "prepare";
        var ledger = $("#CfLedger"), tabs = $("#CfFactions"); ledger.RemoveAndDeleteChildren(); tabs.RemoveAndDeleteChildren();
        validFactions.forEach(function (f) { var row = panel("Panel", ledger, "", "CfLedgerRow"); label(row, "", M.factions[f].glyph + "  " + factionName(f)); label(row, "", String(state.points[f]), "CfLedgerCount"); });
        ["all"].concat(validFactions).forEach(function (f) {
            var tab = button(tabs, "CfFaction_" + f, f === "all" ? local("all") : factionName(f), "CfFactionTab", function () { faction = f; render(); });
            tab.SetHasClass("CfActive", f === faction);
        });
        $("#CfType").RemoveAndDeleteChildren(); label($("#CfType"), "", local("type_" + kind));
        $("#CfSort").RemoveAndDeleteChildren(); label($("#CfSort"), "", local("level") + (descending ? " ↓" : " ↑"));
        renderGrid(); renderRoster(); renderSelection();
    }
    function openModal(title, hint, name) {
        modalKind = name; var content = $("#CfModalContent"); content.RemoveAndDeleteChildren();
        label(content, "", title, "CfHeading"); if (hint) { label(content, "", hint, "CfHint"); }
        show($("#CfModal"), true); return content;
    }
    function closeModal() {
        show($("#CfModal"), false); modalKind = "";
        if (state.phase === "locked") { execute({type:"return"}); }
    }
    function showOffers() {
        var parent = openModal(local("offers"), fmt("offer_hint", {n:3-state.purchases, gold:state.gold}), "offers");
        var row = panel("Panel", parent, "", "CfOfferRow");
        state.offers.forEach(function (id, index) {
            var c = M.definitions.find(function (item) { return item.id === id; }), bought = state.bought.indexOf(index) >= 0;
            var col = panel("Panel", row, "", "CfOffer");
            if (bought) { cardView(col, M.get(state, id), true); }
            else { var back = panel("Panel", col, "", "CfCard"); background(back, c.faction); label(back, "", factionName(c.faction) + " · " + local("type_" + c.type), "CfBackType"); }
            var buy = button(col, "CfBuy" + index, local(bought ? "revealed" : "buy"), "CfMetal", function () { if (execute({type:"buy", index:index}, "acquired")) { showOffers(); } });
            buy.enabled = !bought && state.purchases < 3 && state.gold >= 100 && state.phase === "prepare";
        });
        label(parent, "", local("offer_note"), "CfHint");
    }
    function showForge() {
        var parent = openModal(local("forge"), local("forge_hint"), "forge"), columns = panel("Panel", parent, "", "CfForgeRows");
        [true, false].forEach(function (smelting) {
            var column = panel("Panel", columns, "", "CfForgeColumn"); label(column, "", local(smelting ? "smelt" : "exchange"), "CfSectionTitle");
            var scroll = panel("Panel", column, "", "CfForgeScroll");
            var list = smelting ? M.inventory(state).filter(function (c) { return c.type === "hero"; }) : M.definitions.filter(function (c) { return c.type !== "hero"; });
            list.forEach(function (c) {
                var row = panel("Panel", scroll, "", "CfForgeRow");
                label(row, "", cardName(c) + "\n" + factionName(c.faction) + "  " + (smelting ? c.copies + " " + local("copies") : state.points[c.faction] + " / 3"), "CfDetailText");
                var action = button(row, (smelting ? "CfSmelt_" : "CfExchange_") + c.id, local(smelting ? "smelt" : "exchange"), "CfMetal", function () {
                    if (smelting) { showSmelt(c.id); } else if (execute({type:"exchange", id:c.id}, "acquired")) { showForge(); }
                }); action.enabled = state.phase === "prepare" && (smelting || state.points[c.faction] >= 3);
            });
        });
    }
    function showSmelt(id) {
        var c = M.get(state, id); if (!c) { return; }
        var parent = openModal(local("smelt_confirm"), cardName(c), "smelt");
        label(parent, "", fmt("smelt_warning", {before:c.copies, after:c.copies-1, level:Math.min(3,c.copies-1), faction:factionName(c.faction)}), "CfHelpText");
        var actions = panel("Panel", parent, "", "CfModalActions");
        button(actions, "CfSmeltCancel", local("cancel"), "CfMetal", closeModal);
        button(actions, "CfSmeltConfirm", local("smelt_one"), "CfPrimary", function () { if (execute({type:"smelt", id:id}, "smelted")) { showForge(); } });
    }
    function showHelp() {
        var parent = openModal(local("help_title"), local("shared"), "help");
        ["help_drag", "help_slots", "help_cost", "help_storage"].forEach(function (key) { label(parent, "", local(key), "CfHelpText"); });
        label(parent, "", local("preview_notice"), "CfHint");
    }
    function openGallery() { open = true; show($("#CardForgeOverlay"), true); render(); $("#CfWindow").SetFocus(); }
    function closeGallery() {
        if (drag) { drag.consumed = true; }
        closeModal(); open = false; show($("#CardForgeOverlay"), false);
    }
    $("#CardForgeEntry").SetPanelEvent("onactivate", openGallery);
    $("#CfClose").SetPanelEvent("onactivate", closeGallery);
    $("#CfWindow").SetPanelEvent("oncancel", function () {
        if (drag) { drag.consumed = true; selected = null; renderSelection(); }
        else if (modalKind) { closeModal(); }
        else if (selected) { selected = null; renderSelection(); }
        else { closeGallery(); }
    });
    $("#CfSearch").SetPanelEvent("ontextentrychange", function () { query = $("#CfSearch").text.trim(); renderGrid(); });
    $("#CfType").SetPanelEvent("onactivate", function () { kind = types[(types.indexOf(kind)+1)%types.length]; render(); });
    $("#CfSort").SetPanelEvent("onactivate", function () { descending = !descending; render(); });
    $("#CfHelp").SetPanelEvent("onactivate", showHelp);
    $("#CfLibraryTab").SetPanelEvent("onactivate", function () { closeModal(); $("#CfSearch").SetFocus(); });
    $("#CfOffersTab").SetPanelEvent("onactivate", showOffers);
    $("#CfForgeTab").SetPanelEvent("onactivate", showForge);
    $("#CfModalClose").SetPanelEvent("onactivate", closeModal);
    $("#CfUndo").SetPanelEvent("onactivate", function () { if (history.length && state.phase === "prepare") { state = history.pop(); render(); notify(local("undone")); } });
    $("#CfConfirm").SetPanelEvent("onactivate", function () {
        if (!execute({type:"confirm"})) { return; }
        var parent = openModal(local("sealed"), fmt("sealed_hint", {n:Object.keys(state.slots).length, used:M.used(state), max:M.budget(state)}), "confirm");
        label(parent, "", local("preview_notice"), "CfHelpText");
        button(parent, "CfReturn", local("return"), "CfPrimary", closeModal);
    });
    dropTarget($("#CfInventory"), null);
    // Dedicated endless addon currently hosts only this gallery, with no campaign dependencies.
    show($("#CardForgeEntry"), true);
    if (Game.AddCommand) { Game.AddCommand("rpg_card_ui_preview", openGallery, "Open the local card UI gallery", 0); }
    openGallery();
})();
