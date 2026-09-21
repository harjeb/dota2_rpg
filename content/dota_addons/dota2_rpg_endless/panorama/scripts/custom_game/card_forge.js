(function () {
    "use strict";
    var root = $("#CardForgeRoot"), M = GameUI.CustomUIConfig().CardForgeModel;
    if (!root || !M) { return; }
    var state = M.initial(), selected = null, faction = "all", kind = "all", query = "", descending = true;
    var catalog = false, inspectLevel = 1, chosenFactions = {};
    var requestSerial = 0, pending = false, combatActive = false, drag = null, noticeGeneration = 0, modalKind = "", open = false;
    var slots = {}, cards = {}, types = ["all", "hero", "buff", "charge", "field"];
    var validFactions = Object.keys(M.factions);
    var errorKeys = {
        "专属槽只能装备该英雄的专属卡":"wrong_hero", "英雄专属卡需要对应英雄的专属槽":"wrong_slot",
        "卡库已满，无法退回被替换卡；请先腾出位置":"full", "卡库已满，请先腾出位置":"full", "卡库已满，无法获得新卡":"full",
        "卡牌已经在该槽位":"already", "该装载等级尚未解锁":"level_locked", "构筑已锁定，请先返回准备":"locked",
        "只有专属卡可以熔炼":"smelt_only", "请先卸下这张专属卡":"unequip_first", "需要 3 点对应阵营印记":"marks_needed",
        "触发数值超出范围":"trigger_invalid", "该卡已满级":"card_maxed", "本波购买次数已用完":"purchases_used", "金币不足":"gold_needed", "COST 超出预算，请降低装载等级或卸卡":"over_budget"
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
    function requestState() { GameEvents.SendCustomGameEventToServer("rpg_card_request_state", {}); }
    function execute(action) {
        if (combatActive || pending || (drag && (drag.revision !== state.revision || drag.run_id !== state.run_id))) {
            requestState(); return false;
        }
        var result = M.apply(state, action);
        if (result.error) { notify(errorMessage(result.error), true); return false; }
        result.intent.request_id = String(Game.GetLocalPlayerID()) + ":" + String(Date.now()) + ":" + (++requestSerial);
        pending = true;
        GameEvents.SendCustomGameEventToServer("rpg_card_action", result.intent);
        closeModal();
        // Recover if a response was dropped; the request itself never changes the view.
        $.Schedule(2, function () { if (pending) { requestState(); } });
        return true;
    }
    function receiveState(payload) {
        var next;
        try { next = M.snapshot(payload); } catch (e) { notify(local("loading"), true); return; }
        if (next.run_id === state.run_id && next.revision < state.revision) { return; }
        var wasLocked = state.phase === "locked";
        state = next; pending = false; combatActive = state.phase === "locked"; closeModal();
        if (state.phase === "locked" && !wasLocked) { closeGallery(); }
        // Preserve the native drag source until DragEnd; revision checks cancel stale drops.
        if (!drag) { render(); }
    }
    function cardView(parent, card, detail) {
        var p = panel("Panel", parent, "", "CfCard CfKind_" + card.type); background(p, card.faction);
        var well = panel("Panel", p, "", "CfArtWell"); well.hittest = false; well.hittestchildren = false;
        if (card.type === "hero") { image(well, card.art, "CfCardArt"); }
        else { label(well, "", {buff:"＋", charge:"◆", field:"◎"}[card.type], "CfKindGlyph"); }
        panel("Panel", well, "", "CfCardShade").hittest = false;
        label(p, "", local(M.supported(state, card.id) ? "supported" : "unimplemented"), "CfSupportBadge");
        if (card.axis && card.axis !== "—") { label(p, "", card.axis, "CfAxisBadge"); }
        var copy = panel("Panel", p, "", "CfCardCopy"); copy.hittest = false; copy.hittestchildren = false;
        label(copy, "", cardName(card), "CfCardName"); label(copy, "", factionName(card.faction) + " · " + local("type_" + card.type), "CfCardType");
        label(copy, "", catalog ? "Lv.1 / 2 / 3" : "Lv." + card.load + " / " + card.level, "CfCardLevel");
        if (card.type === "charge") {
            var live = (state.combat.cards || []).find(function (item) { return item.id === card.id; });
            label(copy, "", live ? "× " + live.remaining : catalog ? "1 / 2 / 3" : "× " + card.load, "CfChargeCount");
        }
        if (!catalog) { label(p, "", String(M.cost(card)), "CfCardCost"); }
        if (!detail) {
            cards[card.id] = p; p.SetHasClass("CfSelected", selected === card.id);
            p.SetPanelEvent("onactivate", function () { selected = card.id; inspectLevel = 1; renderSelection(); });
            if (!catalog) { attachDrag(p, card.id); }
        }
        return p;
    }
    function attachDrag(p, id) {
        p.SetDraggable(state.phase === "prepare");
        $.RegisterEventHandler("DragStart", p, function (source, callback) {
            if (!open || catalog || state.phase !== "prepare" || drag) { return false; }
            selected = id; var ghost = cardView(root, M.get(state, id), true);
            ghost.AddClass("CfDragGhost"); ghost.hittest = false; ghost.hittestchildren = false;
            drag = { id: id, display: ghost, consumed: false, revision: state.revision, run_id: state.run_id };
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
            if (catalog || !drag || display !== drag.display) { return false; }
            var error = key ? M.eligibility(state, drag.id, key) : null;
            p.SetHasClass("CfDropHover", !error); p.SetHasClass("CfDropInvalid", !!error);
            if (key) { preview(key); } return !error;
        });
        $.RegisterEventHandler("DragLeave", p, function () { p.RemoveClass("CfDropHover"); p.RemoveClass("CfDropInvalid"); return true; });
        $.RegisterEventHandler("DragDrop", p, function (target, display) {
            if (catalog || !drag || drag.consumed || display !== drag.display) { return false; }
            drag.consumed = true;
            var success = key ? execute({type:"equip", id:drag.id, slot:key}, "equipped") : execute({type:"unequip", id:drag.id}, "unequipped");
            p.RemoveClass("CfDropHover"); p.RemoveClass("CfDropInvalid"); return success;
        });
    }
    function preview(key) {
        if (catalog) { return; }
        var id = drag ? drag.id : selected;
        if (!id || !M.get(state, id)) { return; }
        var result = M.apply(state, {type:"equip", id:id, slot:key});
        $("#CfDropHint").text = result.error ? errorMessage(result.error) : fmt("drop_preview", {hero:heroName(key.split(":")[0]), before:M.used(state), after:M.used(state) - M.cost(M.get(state, state.slots[key])) + (M.location(state, id) ? 0 : M.cost(M.get(state, id)))});
    }
    function renderSelection() {
        Object.keys(cards).forEach(function (id) { cards[id].SetHasClass("CfSelected", id === selected); });
        Object.keys(slots).forEach(function (key) {
            var active = !catalog && !!selected && !!M.get(state, selected) && state.phase === "prepare";
            var allowed = active && !M.eligibility(state, selected, key);
            slots[key].SetHasClass("CfEligible", !!allowed); slots[key].SetHasClass("CfIneligible", !!active && !allowed);
        });
        renderInspector();
    }
    function renderGrid() {
        if (drag) { return; }
        var grid = $("#CfGrid"); grid.RemoveAndDeleteChildren(); cards = {};
        var list = (catalog ? M.definitions.filter(function (c) { return c.type !== "hero"; }) : M.inventory(state)).filter(function (c) {
            var text = c.id + " " + cardName(c) + " " + factionName(c.faction) + " " + (c.axis || "") + " " + (c.hero ? heroName(c.hero) : "");
            return (faction === "all" || c.faction === faction) && (kind === "all" || c.type === kind) && text.toLowerCase().indexOf(query.toLowerCase()) >= 0;
        });
        list.sort(function (a, b) { return (descending ? b.level - a.level : a.level - b.level) || a.id.localeCompare(b.id); });
        list.forEach(function (card) { cardView(grid, card, false); });
        show($("#CfEmpty"), list.length === 0);
    }
    function renderInspector() {
        var target = $("#CfInspector"); target.RemoveAndDeleteChildren();
        var c = catalog ? M.definitions.find(function (item) { return item.id === selected; }) : M.get(state, selected);
        if (!c) { label(target, "", local("select_hint"), "CfDetailText"); return; }
        label(target, "", local("detail"), "CfEyebrow");
        cardView(target, c, true).AddClass("CfShowcase");
        label(target, "", cardName(c), "CfDetailTitle"); panel("Panel", target, "", "CfDetailRule");
        label(target, "", c.hero ? fmt("hero_only", {hero:heroName(c.hero)}) : local("general_any"), "CfDetailText");
        label(target, "", local("all_allies"), "CfDetailText");
        label(target, "", c.type === "charge" ? fmt("charges", {n:catalog ? inspectLevel : c.load}) : local(c.type === "field" ? "field_lifecycle" : "battle_lifecycle"), "CfDetailText");
        if (c.axis && c.axis !== "—") { label(target, "", fmt("axis", {axis:c.axis}), "CfSmall"); }
        if (c.condition) {
            label(target, "", local("condition"), "CfDetailCaption");
            label(target, "", c.condition.replace(/\*\*/g, ""), "CfDetailText");
        }
        if (!catalog && c.trigger_default) {
            var trigger = c.trigger || c.trigger_default, timeTrigger = trigger.type === "time";
            label(target, "", local("trigger_" + trigger.type), "CfSmall");
            var entry = panel("TextEntry", target, "CfTriggerValue", "CfTriggerValue");
            entry.text = String(timeTrigger ? trigger.first : Math.round(trigger.threshold * 100));entry.enabled = state.phase === "prepare";
            var triggerActions = panel("Panel", target, "", "CfLevelRow");
            var saveTrigger = button(triggerActions, "CfTriggerSave", local("trigger_save"), "CfMetal", function () {
                execute({type:"trigger", id:c.id, value:entry.text.trim() === "" ? -1 : Number(entry.text)});
            }); saveTrigger.enabled = state.phase === "prepare";
            var resetTrigger = button(triggerActions, "CfTriggerReset", local("trigger_default"), "CfMetal", function () { execute({type:"trigger", id:c.id, value:"default"}); });
            resetTrigger.enabled = state.phase === "prepare" && !!c.trigger;
            label(target, "", local("trigger_cooldown"), "CfSmall");
        }
        if (c.effect) {
            label(target, "", local("effect"), "CfDetailCaption");
            label(target, "", c.effect.replace(/\*\*/g, ""), "CfEffectText");
        }
        var combat = (state.combat.cards || []).find(function (item) { return item.id === c.id; });
        if (combat) {
            if (combat.remaining !== undefined) { label(target, "", fmt("combat_remaining", {n:combat.remaining}), "CfSmall"); }
            var active = M.countdown(state, combat.active_until), next = M.countdown(state, combat.next_trigger);
            if (active > 0) { label(target, "", fmt("combat_active_remaining", {n:active}), "CfSmall"); }
            if (combat.remaining > 0 && next !== null) { label(target, "", next > 0 ? fmt("combat_ready_in", {n:next}) : local("combat_waiting"), "CfSmall"); }
        }
        label(target, "", local(M.supported(state, c.id) ? "supported" : "unimplemented"), "CfSmall");
        if (state.unsupported[c.id]) { label(target, "", String(state.unsupported[c.id]), "CfDetailText"); }
        label(target, "", catalog ? local("catalog_level") : fmt("owned_level", {n:c.level, copies:c.copies}), "CfSmall");
        var row = panel("Panel", target, "", "CfLevelRow");
        [1,2,3].forEach(function (n) {
            var b = button(row, "CfLevel" + n, "Lv." + n, "CfLevel", function () { if (catalog) { inspectLevel = n; renderInspector(); } else { execute({type:"level", id:c.id, level:n}, "level_changed"); } });
            label(b, "", (M.curves[c.tier] || M.curves["普通"])[n-1] + " COST", "CfSmall");
            b.enabled = catalog || (n <= c.level && state.phase === "prepare"); b.SetHasClass("CfActive", n === (catalog ? inspectLevel : c.load));
        });
        label(target, "", local("cost_sample"), "CfSmall");
        if (catalog) { label(target, "", local("catalog_readonly"), "CfDetailText"); return; }
        var actions = panel("Panel", target, "", "CfDetailActions"), location = M.location(state, c.id);
        var equip = button(actions, "CfDetailEquip", local(location ? "unequip" : "select_slot"), "CfMetal", function () {
            if (location) { execute({type:"unequip", id:c.id}, "unequipped"); } else { notify(local("select_slot_hint")); }
        }); equip.enabled = state.phase === "prepare";
        if (c.type === "hero") {
            var smelt = button(actions, "CfDetailSmelt", local("smelt"), "CfMetal", function () { showSmelt(c.id); }); smelt.enabled = !location && state.phase === "prepare";
        }
        label(target, "", location ? fmt("equipped_on", {hero:heroName(location.split(":")[0])}) : local("drag_hint"), "CfSmall");

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
                if (c) { if (c.type === "hero") { image(slot, c.art, "CfSlotArt"); } else { background(slot, c.faction); } if (!catalog) { attachDrag(slot, c.id); } }
                var copy = panel("Panel", slot, "", "CfSlotCopy"); copy.hittest = false; copy.hittestchildren = false;
                label(copy, "", c ? cardName(c) : local("slot_" + type));
                label(copy, "", c ? "Lv." + c.load + " · " + M.cost(c) + " COST" : "◇", "CfSmall");
                slot.SetPanelEvent("onactivate", function () {
                    if (state.phase !== "prepare") {
                        if (c) { catalog = false; selected = c.id; render(); }
                        else { notify(local("locked"), true); }
                        return;
                    }
                    if (!catalog && selected && M.get(state, selected) && selected !== state.slots[key]) { execute({type:"equip", id:selected, slot:key}, "equipped"); }
                    else if (c) { catalog = false; selected = c.id; render(); }
                });
                slot.SetPanelEvent("oncontextmenu", function () { if (c) { catalog = false; selected = c.id; render(); } });
                slot.SetPanelEvent("onmouseover", function () { preview(key); });
                slot.SetPanelEvent("onmouseout", function () { $("#CfDropHint").text = local(catalog ? "catalog_readonly" : "drag_hint"); });
                dropTarget(slot, key);
            });
        });
    }
    function render() {
        if (drag) { return; }
        $("#CfCapacity").text = catalog ? "100" : M.inventory(state).length + " / 24";
        $("#CfCapacityHint").text = catalog ? fmt("catalog_count", {n:100}) : local("capacity_hint");
        $("#CfLibraryTitle").text = local(catalog ? "catalog" : "library");
        $("#CfLibraryTab").SetHasClass("CfActive", !catalog);
        $("#CfCatalogTab").SetHasClass("CfActive", catalog);
        $("#CfDropHint").text = local(catalog ? "catalog_readonly" : "drag_hint");
        $("#CfFieldCount").text = fmt("field_count", {n:Object.keys(state.slots).filter(function (key) { return M.get(state, state.slots[key]).type === "field"; }).length});
        $("#CfWallet").text = "◈ " + state.gold;
        $("#CfCost").text = "COST  " + M.used(state) + " / " + M.budget(state);
        $("#CfCost").SetHasClass("CfOver", M.used(state) > M.budget(state));
        $("#CfBudgetBar").max = M.budget(state); $("#CfBudgetBar").value = Math.min(M.used(state), M.budget(state));
        $("#CfBudgetBar").SetHasClass("CfOver", M.used(state) > M.budget(state));
        $("#CfConfirm").enabled = !catalog && state.phase === "prepare" && M.used(state) <= M.budget(state);
        $("#CfOffersTab").enabled = state.phase === "prepare";
        $("#CfForgeTab").enabled = state.phase === "prepare";
        $("#CfControlsHint").text = local(state.phase === "loading" ? "loading" : "controls");
        var ledger = $("#CfLedger"), tabs = $("#CfFactions"); ledger.RemoveAndDeleteChildren(); tabs.RemoveAndDeleteChildren();
        validFactions.forEach(function (f) { var row = panel("Panel", ledger, "", "CfLedgerRow"); label(row, "", M.factions[f].glyph + "  " + factionName(f)); label(row, "", String(state.points[f] || 0), "CfLedgerCount"); });
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
    }
    function showOffers() {
        if (state.phase !== "prepare") { return; }
        var parent = openModal(local("offers"), fmt("offer_hint", {n:3-state.purchases, gold:state.gold}), "offers");
        if (!state.factions.length) {
            label(parent, "", local("choose_factions_hint"), "CfHelpText");
            var choices = panel("Panel", parent, "", "CfOfferRow");
            validFactions.forEach(function (f) {
                var choose = button(choices, "CfPool_" + f, factionName(f), "CfMetal", function () {
                    chosenFactions[f] = !chosenFactions[f]; showOffers();
                }); choose.SetHasClass("CfActive", !!chosenFactions[f]);
            });
            var confirm = button(parent, "CfPoolConfirm", local("choose_factions"), "CfPrimary", function () {
                execute({type:"factions", factions:validFactions.filter(function (f) { return chosenFactions[f]; })});
            }); confirm.enabled = validFactions.some(function (f) { return chosenFactions[f]; });
            return;
        }
        label(parent, "", state.factions.map(factionName).join(" · "), "CfHint");
        var row = panel("Panel", parent, "", "CfOfferRow");
        state.offers.forEach(function (id, index) {
            var c = M.definitions.find(function (item) { return item.id === id; }), bought = state.bought.indexOf(index) >= 0;
            if (!c) { return; }
            var col = panel("Panel", row, "", "CfOffer");
            if (bought) { cardView(col, M.get(state, id) || c, true); }
            else { var back = panel("Panel", col, "", "CfCard"); background(back, c.faction); label(back, "", factionName(c.faction) + " · " + local("type_" + c.type), "CfBackType"); }
            var buy = button(col, "CfBuy" + index, local(bought ? "revealed" : M.get(state, id) && M.get(state, id).level >= 3 ? "card_maxed" : "buy"), "CfMetal", function () { execute({type:"buy", index:index}); });
            buy.enabled = M.supported(state, id) && !bought && state.purchases < 3 && state.gold >= 100 && state.phase === "prepare" && M.canAcquire(state, id);
        });
        label(parent, "", local("offer_note"), "CfHint");
        label(parent, "", local("progression_limit"), "CfHint");
    }
    function showForge() {
        if (state.phase !== "prepare") { return; }
        var parent = openModal(local("forge"), local("forge_hint"), "forge"), columns = panel("Panel", parent, "", "CfForgeRows");
        (state.cards.some(function (c) { return c.type === "hero"; }) ? [true, false] : [false]).forEach(function (smelting) {
            var column = panel("Panel", columns, "", "CfForgeColumn"); label(column, "", local(smelting ? "smelt" : "exchange"), "CfSectionTitle");
            var scroll = panel("Panel", column, "", "CfForgeScroll");
            var list = smelting ? M.inventory(state).filter(function (c) { return c.type === "hero"; }) : M.definitions.filter(function (c) { return c.type !== "hero" && M.supported(state, c.id); });
            list.forEach(function (c) {
                var row = panel("Panel", scroll, "", "CfForgeRow");
                label(row, "", cardName(c) + "\n" + factionName(c.faction) + "  " + (smelting ? c.copies + " " + local("copies") : state.points[c.faction] + " / 3"), "CfDetailText");
                var action = button(row, (smelting ? "CfSmelt_" : "CfExchange_") + c.id, local(smelting ? "smelt" : "exchange"), "CfMetal", function () {
                    if (smelting) { showSmelt(c.id); } else { execute({type:"exchange", id:c.id}); }
                }); action.enabled = state.phase === "prepare" && (smelting || (state.points[c.faction] >= 3 && M.canAcquire(state, c.id)));
            });
        });
    }
    function showSmelt(id) {
        var c = M.get(state, id); if (!c) { return; }
        var parent = openModal(local("smelt_confirm"), cardName(c), "smelt");
        label(parent, "", fmt("smelt_warning", {before:c.copies, after:c.copies-1, level:Math.min(3,c.copies-1), faction:factionName(c.faction)}), "CfHelpText");
        var actions = panel("Panel", parent, "", "CfModalActions");
        button(actions, "CfSmeltCancel", local("cancel"), "CfMetal", closeModal);
        button(actions, "CfSmeltConfirm", local("smelt_one"), "CfPrimary", function () { execute({type:"smelt", id:id}); });
    }
    function showHelp() {
        var parent = openModal(local("help_title"), local("shared"), "help");
        ["help_drag", "help_slots", "help_cost", "help_storage"].forEach(function (key) { label(parent, "", local(key), "CfHelpText"); });
        label(parent, "", local("live_help"), "CfHint");
    }
    function openGallery() { requestState(); if (combatActive || state.phase === "locked") { catalog = true; } open = true; show($("#CardForgeOverlay"), true); render(); $("#CfWindow").SetFocus(); }
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
    $("#CfLibraryTab").SetPanelEvent("onactivate", function () { if (drag) { return; } closeModal(); catalog = false; selected = null; render(); $("#CfSearch").SetFocus(); });
    $("#CfCatalogTab").SetPanelEvent("onactivate", function () { if (drag) { return; } closeModal(); catalog = true; selected = null; render(); });
    $("#CfOffersTab").SetPanelEvent("onactivate", showOffers);
    $("#CfForgeTab").SetPanelEvent("onactivate", showForge);
    $("#CfModalClose").SetPanelEvent("onactivate", closeModal);
    $("#CfConfirm").SetPanelEvent("onactivate", function () {
        if (!catalog && !drag) { execute({type:"confirm"}); }
    });
    dropTarget($("#CfInventory"), null);
    GameEvents.Subscribe("rpg_card_state", receiveState);
    GameEvents.Subscribe("rpg_card_error", function (event) {
        pending = true; closeModal();
        if (!open) { openGallery(); }
        notify(String(event.message || local("invalid")), true); requestState();
    });
    GameEvents.Subscribe("rpg_endless_state", function (event) {
        var wasCombatActive = combatActive;
        combatActive = ["fight", "locked", "result"].indexOf(event.phase) >= 0;
        if (combatActive && !wasCombatActive) { closeGallery(); }
    });
    show($("#CardForgeEntry"), true);
    render(); requestState();
})();
