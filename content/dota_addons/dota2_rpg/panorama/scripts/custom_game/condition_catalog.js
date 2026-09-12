/* Shared condition definitions and the per-rule settings editor. UI percentages are 0..100. */
var RpgConditionCatalog = (function () {
    "use strict";
    var groups = { use: [], target: [], priority: [] };
    var definitions = {};
    function add(group, id, category, fields) {
        var entry = { id: id, category: category, fields: fields ? fields.split(",") : [] };
        groups[group].push(entry); definitions[group + ":" + id] = entry;
    }
    add("use", "always", "general", "");
    ["self_hp_pct_lte", "self_hp_pct_gte", "self_mana_pct_lte", "self_mana_pct_gte"].forEach(function (id) { add("use", id, "resources", "value"); });
    ["alive_ally_count_gte", "alive_enemy_count_gte", "alive_enemy_count_lte", ].forEach(function (id) { add("use", id, "battle", "value"); });
    ["nearby_allies_gte", "nearby_enemies_gte"].forEach(function (id) { add("use", id, "proximity", "value,radius"); });
    add("use", "no_enemy_within", "proximity", "radius");
    ["elapsed_gte", "elapsed_lte", "self_recently_damaged", "any_ally_recently_damaged"].forEach(function (id) { add("use", id, "time", "seconds"); });
    ["action_elapsed_gte", "action_elapsed_lte"].forEach(function(id) { add("use",id,"action","seconds,action_id"); });
    add("use", "action_use_count_lt", "action", "value,action_id");
    add("use", "ability_charges_gte", "action", "value,action_id");
    ["self_has_modifier", "self_not_has_modifier"].forEach(function (id) { add("use", id, "advanced", "modifier"); });
    ["stacks", "remaining"].forEach(function (property) {
        ["gte", "lte"].forEach(function (direction) {
            add("use", "self_modifier_" + property + "_" + direction, "advanced", "modifier," + (property === "remaining" ? "seconds" : "value"));
        });
    });
    ["hp_pct_lte", "hp_pct_gte", "mana_pct_lte", "mana_pct_gte", "health_lte", "health_gte", "missing_health_gte", "missing_health_lte"].forEach(function (id) { add("target", id, "resources", "value"); });
    ["distance_lte", "distance_gte"].forEach(function (id) { add("target", id, "proximity", "value"); });
    ["nearby_allies_gte", "nearby_enemies_gte"].forEach(function (id) { add("target", id, "proximity", "value,radius"); });
    ["exclude_self", "is_hero", "is_summon", "is_illusion", "owned_by_self"].forEach(function (id) { add("target", id, "identity", ""); });
    ["is_casting", "is_channeling", "is_controlled", "is_stunned", "is_silenced", "is_rooted", "is_spell_immune", "not_spell_immune", "has_dispellable_buff", "has_dispellable_debuff"].forEach(function (id) { add("target", id, "status", ""); });
    add("target", "recently_damaged", "time", "seconds");
    ["has_modifier", "not_has_modifier"].forEach(function (id) { add("target", id, "advanced", "modifier"); });
    ["stacks", "remaining"].forEach(function (property) {
        ["gte", "lte"].forEach(function (direction) {
            add("target", "modifier_" + property + "_" + direction, "advanced", "modifier," + (property === "remaining" ? "seconds" : "value"));
        });
    });
    ["nearest", "farthest", "lowest_hp_pct", "highest_hp_pct", "lowest_health", "highest_health", "most_missing_health", "lowest_armor", "highest_armor", "lowest_attack_damage", "highest_attack_damage", "lowest_magic_resistance", "highest_magic_resistance", "prefer_teammate"].forEach(function (id) { add("priority", id, "priority", ""); });

    ["tiny_grab_is_enemy", "tiny_grab_is_ally", "tiny_grab_is_hero", "tiny_grab_is_creep"].forEach(function(id) { add("use", id, "tiny_grab", ""); });
    ["tiny_grab_hp_pct_lte", "tiny_grab_hp_pct_gte"].forEach(function(id) { add("use", id, "tiny_grab", "value"); });
    add("use", "action_succeeded_after", "action", "seconds,action_id");
    add("target", "specified_enemy", "identity", "target_actor");
    ["channel_elapsed_gte", "channel_elapsed_lte"].forEach(function(id) { add("use",id,"action","seconds,action_id"); });
    add("use","action_phase_is","action","value_text,action_id");
    add("use","release_action_available","action","");
    // Stable documentation IDs retain the gaps left by retired conditions.
    var codes = {
        use: [1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,21,22,23,24,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43],
        target: [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,17,19,20,21,22,23,24,25,26,27,30,31,32,33,34,35,36,37,38,39],
        priority: [1,2,3,4,5,6,7,8,9,10,11,12,13,14]
    };
    Object.keys(groups).forEach(function (group) {
        groups[group].forEach(function (entry, index) {
            entry.code = {use: "U", target: "F", priority: "P"}[group] + ("0" + codes[group][index]).slice(-2);
        });
    });
    function text(id) { return $.Localize("#dota2_rpg_v2_" + id); }
    function entryLabel(entry) { if (entry.label) { return entry.label; } return (entry.code ? entry.code + " " : "") + text(entry.id || "none"); }
    // Takes editor settings (percentages 0..100), never mutates or truncates them.
    function summary(initialSettingsObject) {
        var settings = initialSettingsObject || {}, parts = [];
        [["use", "use_conditions", "use_title"], ["target", "target_filters", "target_title"], ["priority", "target_priorities", "priority_title"]].forEach(function (spec) {
            var items = (settings[spec[1]] || []).filter(function (condition) { return condition && condition.type; }).map(function (condition) {
                var def = definitions[spec[0] + ":" + condition.type];
                var values = Object.keys(condition).filter(function (key) { return key !== "type" && condition[key] !== undefined && condition[key] !== ""; }).map(function (key) {
                    var value = condition[key];
                    if (key === "modifier" || key === "value" && condition.type.indexOf("has_modifier") >= 0) { value = modifierOption(String(value)).label + " [" + value + "]"; }
                    if (key === "value" && condition.type === "action_phase_is") { value = phaseLabel(value); }
                    return text(key === "value" && condition.type.indexOf("_pct_") >= 0 ? "percent" : key) + "=" + String(value);
                });
                return (def ? entryLabel(def) : condition.type) + (values.length ? " (" + values.join(", ") + ")" : "");
            });
            parts.push(text(spec[2]) + ": " + (items.join("; ") || text("none")));
        });
        if (settings.target_team || settings.target) { parts.push(text("target_team") + ": " + text("team_" + (settings.target_team || String(settings.target).split("_")[0]))); }
        var desired = settings.desired_toggle_state;
        if (desired === undefined || desired === null || desired === "") { desired = settings.desired_autocast_state; }
        if (desired !== undefined && desired !== null && desired !== "") {
            parts.push(text("toggle_title") + ": " + text(desired === true || desired === 1 || desired === "1" || desired === "true" ? "toggle_on" : "toggle_off"));
        }
        parts.push(text("destination") + ": " + text("destination_" + (settings.destination || "target")));
        parts.push(text("cast_preference") + ": " + text("cast_" + (settings.cast_preference || "auto")));
        ["movement_mode", "movement_buff", "movement_trigger_ability", "movement_duration", "movement_distance", "movement_retarget", "movement_loop", "movement_interruptible", "movement_direction", "positioning_mode", "positioning_distance", "positioning_tolerance"].forEach(function (key) {
            if (settings[key] !== undefined) {
                var value = settings[key];
                if (key === "movement_mode" || key === "movement_direction" || key === "positioning_mode" || typeof value === "boolean") { value = text(key + "_" + value); }
                parts.push(text(key) + ": " + value);
            }
        });
        return parts.join("\n");
    }
    function number(value, fallback, min, max) {
        var n = typeof value === "number" || typeof value === "string" && value.trim() !== "" ? Number(value) : NaN;
        return isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback;
    }
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    var valueLimits = { alive_enemy_count_gte: 1000, alive_ally_count_gte: 20, alive_enemy_count_lte: 20,
        nearby_allies_gte: 20, nearby_enemies_gte: 20, elapsed_gte: 120,
        elapsed_lte: 120, action_use_count_lt: 100, ability_charges_gte: 1000 };
    var retired = {"dead_ally_count_gte": true, "self_strength_gte": true, "self_agility_gte": true, "owned_summons_gte": true, "owned_summons_lte": true, "action_used_within": true, "action_not_used_within": true, "not_illusion": true, "is_creep": true, "is_invulnerable": true, "not_invulnerable": true, "has_tag": true, "not_has_tag": true};
    function normalize(group, input) {
        input = input && typeof input === "object" ? input : {};
        var type = String(input.type || "");
        if (!type || retired[type]) { return { type: "" }; }
        var def = definitions[group + ":" + type];
        // Preserve unknown authored conditions so future server additions are not silently erased.
        if (!def) { return clone(input); }
        var out = { type: type };
        def.fields.forEach(function (field) {
            if (field === "modifier" || field === "action_id" || field === "target_actor" || field === "value_text") {
                var key = field === "value_text" && def.fields.indexOf("value") < 0 ? "value" : field;
                out[key] = String(input[key] || (field === "modifier" ? input.value || "" : "")).slice(0, 128);
            } else {
                var pct = type.indexOf("_pct_") >= 0;
                var fallback = field === "radius" ? 600 : field === "seconds" ? 2 : pct ? 50 : 1;
                var max = pct ? 100 : field === "radius" ? 3000 : type.indexOf("distance_") === 0 ? 5000
                    : valueLimits[type] || (field === "seconds" || type.indexOf("modifier_remaining_") >= 0 ? 86400 : 1000000);
                out[field] = number(input[field], fallback, 0, max);
            }
        });
        if (def.fields.indexOf("action_id") >= 0 && input.action_actor) { out.action_actor = String(input.action_actor).slice(0, 128); }
        return out;
    }
    function wire(group, input) {
        var out = normalize(group, input);
        if (out.type.indexOf("_pct_") >= 0 && out.value !== undefined) { out.value /= 100; }
        if (out.seconds !== undefined) { out.value = out.seconds; }
        if (out.modifier && (out.type === "has_modifier" || out.type === "not_has_modifier" || out.type === "self_has_modifier" || out.type === "self_not_has_modifier")) { out.value = out.modifier; }
        if (out.type === "no_enemy_within") { out.value = out.radius; }
        if (out.action_id === "") { delete out.action_id; }
        return out;
    }
    function label(parent, id, value) {
        var panel = $.CreatePanel("Label", parent, id || ""); panel.text = value; return panel;
    }
    function button(parent, id, value, click) {
        var panel = $.CreatePanel("Button", parent, id || ""); panel.AddClass("V2Button");
        label(panel, "", value).hittest = false; panel.SetPanelEvent("onactivate", click); return panel;
    }
    var phases = ["IDLE", "REQUESTED", "CASTING", "EXECUTED", "CHANNELING", "FINISHED", "INTERRUPTED", "ENDED", "UNCONFIRMED"];
    function localizedToken(token) {
        var value = $.Localize(token);
        return value && value.charAt(0) !== "#" && value.toLowerCase() !== token.slice(1).toLowerCase() ? value : "";
    }
    function abilityLabel(name) {
        return localizedToken("#DOTA_Tooltip_Ability_" + name) || String(name || "").replace(/_/g, " ");
    }
    function phaseLabel(value) { return phases.indexOf(value) >= 0 ? text("phase_" + value) : value; }
    function modifierOption(name, metadata) {
        if (!name) { return {id:"", label:text("observed_modifiers")}; }
        metadata = metadata || {};
        var source = /^[A-Za-z0-9_]+$/.test(metadata.ability || "") ? metadata.ability : "";
        var caption = localizedToken("#DOTA_Tooltip_" + name);
        if (!caption && source) {
            var sourceName = localizedToken("#DOTA_Tooltip_Ability_" + source);
            if (sourceName) { caption = sourceName + " · " + text(metadata.debuff === 1 ? "status_debuff" : "status_effect"); }
        }
        return {id:name, label:caption || text("status_unnamed"), icon:source, hint:name};
    }
    var movementPresets = {
        shukuchi:{ability:"weaver_shukuchi", buff:"modifier_weaver_shukuchi", mode:"cycle"},
        trample:{ability:"primal_beast_trample", buff:"modifier_primal_beast_trample", mode:"orbit"},
        gyroshell:{ability:"pangolier_gyroshell", buff:"modifier_pangolier_gyroshell", mode:"orbit"}
    };
    function movementPreset(name) {
        var preset = movementPresets[name] || movementPresets.trample;
        return {movement_mode:preset.mode,
            movement_buff:preset.buff, movement_trigger_ability:preset.ability,
            movement_duration:name === "gyroshell" ? 20 : 15, movement_distance:150, movement_retarget:true,
            movement_loop:true, movement_interruptible:false, movement_direction:"auto"};
    }
    var editorGeneration=0;
    function open(rule, initial, onApply, options) {
        var generation=++editorGeneration;
        options = options || {};
        var root = $("#RuleSettings");
        var body = $("#RuleSettingsBody");
        body.RemoveAndDeleteChildren();
        var draft = clone(initial || {}), readers = [];
        delete draft.min_aoe_hits;
        ["use_conditions", "target_filters", "target_priorities"].forEach(function (key) { draft[key] = draft[key] || []; });
        $("#RuleSettingsError").text = "";
        var activeMenu = null;
        var capAPI=typeof RpgAbilityCapabilities!=="undefined" ? RpgAbilityCapabilities : null;
        var baseCap=options.getCapability ? options.getCapability() : options.capability;
        // Normalize removed controls before deriving capability or validating the draft.
        draft.cast_preference="auto";
        draft.cast_variant="default";
        draft.state_policy="fixed";
        draft.state_mana_on=0.4; draft.state_mana_off=0.2; draft.state_hold_seconds=0.75;
        draft.allow_unverified_modifiers=false;
        function normalizeNativeSettings(capability, previousKey) {
            var casts=capability && capability.cast || {};
            var key=casts.toggle===1 ? "desired_toggle_state" : casts.autocast===1 ? "desired_autocast_state" : "";
            var desired=key ? draft[previousKey || key] : null;
            if (key && desired===undefined) { desired=rule[previousKey || key]; }
            draft.desired_toggle_state=null; draft.desired_autocast_state=null;
            if (key) { draft[key]=RpgRuleSync.bool(desired,true); }
            var derived=capAPI ? capAPI.derive(capability,draft) : null;
            var types=capability && capability.native_unit_contract && capability.native_unit_contract.types || derived && derived.types;
            draft.target_types=["hero","monster","summon"].filter(function(type) { return !types || types[type]!==0; }).join(",");
            return key;
        }
        var stateKey=normalizeNativeSettings(baseCap);
        var cap=capAPI ? capAPI.derive(baseCap,draft) : null;
        var strict=!!options.getCapability;
        function explain(reason) { return capAPI ? capAPI.message(reason) : reason; }
        function reopen(changes) {
            readers.forEach(function(read) { read(); });
            Object.keys(changes || {}).forEach(function(key) { draft[key]=changes[key]; });
            open(rule,draft,onApply,options);
        }
        function restrict(entries, reasonFn) {
            return entries.map(function(entry) {
                var copy=clone(entry); copy.reason=reasonFn(entry) || ""; copy.disabled=!!copy.reason; return copy;
            });
        }
        function tooltip(panel,message) {
            panel.SetPanelEvent("onmouseover",function() { $.DispatchEvent("DOTAShowTextTooltip",panel,message); });
            panel.SetPanelEvent("onmouseout",function() { $.DispatchEvent("DOTAHideTextTooltip",panel); });
        }
        if (cap) {

            var initialCheck=capAPI.validate(draft,baseCap,{requireCapability:strict});
            if (!initialCheck.ok) { $("#RuleSettingsError").text=capAPI.describe(initialCheck); }
        } else if (strict) { $("#RuleSettingsError").text=explain("capability_unavailable"); }

        function choose(parent, id, options, selected, changed) {
            var selectedEntry = options.filter(function (option) { return option.id === selected; })[0] || {id: selected};
            var trigger = button(parent, id, entryLabel(selectedEntry), function () {
                if (activeMenu) { var same = activeMenu === menu; activeMenu.SetHasClass("Hidden", true); activeMenu = null; if (same) { return; } }
                menu.SetHasClass("Hidden", false); activeMenu = menu;
            });
            function draw(panel, option) {
                panel.RemoveAndDeleteChildren();
                panel.SetHasClass("V2StatusChoice", !!option.icon);
                if (option.icon) {
                    var item = option.icon.indexOf("item_") === 0;
                    var icon = $.CreatePanel(item ? "DOTAItemImage" : "DOTAAbilityImage", panel, "");
                    icon.AddClass("V2AbilityIcon"); icon.hittest = false;
                    if (item) { icon.itemname = option.icon; } else { icon.abilityname = option.icon; }
                }
                label(panel, "", entryLabel(option)).hittest = false;
                tooltip(panel, option.reason ? explain(option.reason) : option.hint || entryLabel(option));
            }
            var menu = $.CreatePanel("Panel", parent, id + "Menu"); menu.AddClass("V2Choices"); menu.AddClass("Hidden");
            var category = "";
            options.forEach(function (option) {
                if (option.category && category !== option.category) { category = option.category; label(menu, "", text("category_" + category)).AddClass("V2Category"); }
                var item=button(menu, id + "Option_" + (option.id || "none"), "", function () {
                    if (option.disabled) { return; }
                    draw(trigger, option); menu.SetHasClass("Hidden", true); activeMenu = null; changed(option.id);
                });
                item.enabled=!option.disabled; draw(item, option);
            });
            draw(trigger, selectedEntry);
            return function (option) { draw(trigger, option); };
        }
        function modifierChoices(saved) {
            var known=cap && cap.modifiers || {}, details=cap && cap.modifier_details || {};
            var names=Object.keys(known).sort();
            if (saved && names.indexOf(saved)<0) { names.push(saved); }
            var counts={}, seen={};
            var choices=names.map(function(name) {
                var option=modifierOption(name,details[name]);
                if (!Object.prototype.hasOwnProperty.call(known,name)) {
                    option.disabled=true; option.reason="modifier_not_observed";
                    option.label+=" · "+explain("modifier_not_observed");
                }
                counts[option.label]=(counts[option.label] || 0)+1;
                return option;
            });
            choices.forEach(function(option) {
                var caption=option.label;
                if (counts[caption]>1) { seen[caption]=(seen[caption] || 0)+1; option.label+=" · "+seen[caption]; }
            });
            return [modifierOption("")].concat(choices);
        }
        function actionPicker(parent, id, current, selfOnly) {
            parent.AddClass("V2ActionField");
            var trigger = button(parent, id, "", function () {
                if (activeMenu) { var same = activeMenu === menu; activeMenu.SetHasClass("Hidden", true); activeMenu = null; if (same) { return; } }
                menu.SetHasClass("Hidden", false); activeMenu = menu;
            });
            trigger.AddClass("V2ActionChoice");
            var menu = $.CreatePanel("Panel", parent, id + "Menu");
            menu.AddClass("V2AbilityChoices"); menu.AddClass("Hidden");
            function draw(parentPanel, name, caption) {
                parentPanel.RemoveAndDeleteChildren();
                if (name && name !== "attack" && name !== "basic_attack") {
                    var icon = $.CreatePanel(name.indexOf("item_") === 0 ? "DOTAItemImage" : "DOTAAbilityImage", parentPanel, "");
                    icon.AddClass("V2AbilityIcon"); icon.hittest = false;
                    if (name.indexOf("item_") === 0) { icon.itemname = name; } else { icon.abilityname = name; }
                }
                label(parentPanel, "", caption).hittest = false;
            }
            function refresh() {
                var name = current.action_id, actorName = "";
                (options.actionHeroes || []).forEach(function (hero) {
                    if (hero.actor === (current.action_actor || "")) { actorName = hero.label + " / "; }
                });
                draw(trigger, name || (selfOnly ? "" : options.abilityName), name ? actorName + abilityLabel(name) : text(selfOnly ? "none" : "current_action"));
            }
            button(menu, id + "Current", text(selfOnly ? "none" : "current_action"), function () {
                delete current.action_id; delete current.action_actor; refresh(); menu.SetHasClass("Hidden", true); activeMenu = null;
            });
            (options.actionHeroes || []).forEach(function (hero, heroIndex) {
                if (selfOnly && hero.actor !== "") { return; }
                label(menu, "", hero.label).AddClass("V2Category");
                hero.abilities.forEach(function (name, abilityIndex) {
                    if (selfOnly && (!name || name === "attack" || name === "basic_attack" || name === "sustained_move" || name.indexOf("item_") === 0)) { return; }
                    var option = button(menu, id + "Option_" + heroIndex + "_" + abilityIndex, "", function () {
                        current.action_id = name;
                        if (hero.actor) { current.action_actor = hero.actor; } else { delete current.action_actor; }
                        refresh(); menu.SetHasClass("Hidden", true); activeMenu = null;
                    });
                    option.AddClass("V2ActionChoice"); draw(option, name, abilityLabel(name));
                });
            });
            refresh();
        }
        // Actor keys are opaque, level-scoped snapshot identities, never entity IDs or names.
        function targetPicker(parent, id, current, clear) {
            parent.AddClass("V2ActionField");
            function actors() { return options.readOnly ? [] : (options.getTargetActors ? options.getTargetActors() : options.targetActors || []); }
            var trigger = button(parent, id, "", function () {
                if (options.readOnly) { return; }
                if (activeMenu) { var same = activeMenu === menu; activeMenu.SetHasClass("Hidden", true); activeMenu = null; if (same) { return; } }
                populate(); refresh(); menu.SetHasClass("Hidden", false); activeMenu = menu;
            });
            trigger.AddClass("V2TargetChoice");
            var menu = $.CreatePanel("Panel", parent, id + "Menu");
            menu.AddClass("V2AbilityChoices"); menu.AddClass("Hidden");
            function draw(panel, actor, caption) {
                panel.RemoveAndDeleteChildren();
                if (actor) {
                    var hero = actor.name.indexOf("npc_dota_hero_") === 0;
                    var icon = $.CreatePanel(hero ? "DOTAHeroImage" : "Image", panel, "");
                    icon.AddClass("V2TargetPortrait"); icon.hittest = false;
                    if (hero) { icon.heroname = actor.name; icon.heroimagestyle = "portrait"; }
                    else { icon.SetImage("file://{images}/units/" + actor.name + ".png"); }
                }
                label(panel, "", caption).hittest = false;
            }
            function refresh() {
                var selected = actors().filter(function (actor) { return actor.actor === current.target_actor; })[0];
                trigger.SetHasClass("V2UnavailableTarget", !!current.target_actor && !selected);
                draw(trigger, selected, selected ? selected.label : text(current.target_actor ? "unavailable_target" : "choose_target"));
                trigger.SetPanelEvent("onmouseover", function () { $.DispatchEvent("DOTAShowTextTooltip", trigger, text("specified_enemy_hint")); });
                trigger.SetPanelEvent("onmouseout", function () { $.DispatchEvent("DOTAHideTextTooltip", trigger); });
            }
            function populate() {
                menu.RemoveAndDeleteChildren();
                button(menu, id + "Clear", text("clear_target"), function () {
                    if (options.readOnly) { return; }
                    menu.SetHasClass("Hidden", true); activeMenu = null; clear();
                });
                actors().forEach(function (actor, index) {
                    var option = button(menu, id + "Option_" + index, "", function () {
                        // Roster may have changed while this menu was open. Never substitute another unit.
                        if (!actors().some(function (live) { return live.actor === actor.actor; })) { populate(); refresh(); return; }
                        current.target_actor = actor.actor; refresh(); menu.SetHasClass("Hidden", true); activeMenu = null;
                    });
                    option.AddClass("V2TargetChoice"); draw(option, actor, actor.label);
                });
            }
            populate(); refresh();
        }
        function slots(group, key, count, title) {
            label(body, "", text(title)).AddClass("V2SectionTitle");
            for (var i = 0; i < count; i++) {
                (function (index) {
                    var current = normalize(group, draft[key][index]);
                    draft[key][index] = current;
                    var row = $.CreatePanel("Panel", body, "V2_" + group + index); row.AddClass("V2Condition");
                    label(row, "", String(index + 1)).AddClass("V2SlotNumber");
                    var selector = $.CreatePanel("Panel", row, ""); selector.AddClass("V2Selector");
                    var params = $.CreatePanel("Panel", row, ""); params.AddClass("V2Parameters");
                    var readFields = function () {};
                    function renderFields() {
                        params.RemoveAndDeleteChildren();
                        var def = definitions[group + ":" + current.type] || { fields: [] };
                        var fields = def.fields;
                        var entries = [];
                        fields.forEach(function (field) {
                            var keyName = field === "value_text" && def.fields.indexOf("value") < 0 ? "value" : field;
                            var wrap = $.CreatePanel("Panel", params, ""); wrap.AddClass("V2Field");
                            label(wrap, "", text(field === "value" && current.type.indexOf("_pct_") >= 0 ? "percent" : field === "value_text" && current.type === "action_phase_is" ? "phase_selection" : field));
                            if (field === "target_actor") {
                                targetPicker(wrap, "V2_" + group + index + "_" + field, current, function () {
                                    current = {type: ""}; draft[key][index] = current;
                                    selector.GetChild(0).GetChild(0).text = text("none"); renderFields();
                                });
                                return;
                            }
                            if (field === "action_id") {
                                actionPicker(wrap, "V2_" + group + index + "_" + field, current);
                                return;
                            }
                            if (field === "value_text" && current.type === "action_phase_is") {
                                current.value=current.value || "CHANNELING";
                                wrap.AddClass("V2PhaseField");
                                choose(wrap,"V2_"+group+index+"Phase",phases.map(function(value) { return {id:value,label:phaseLabel(value),hint:text("phase_"+value+"_hint")}; }),current.value,function(value) { current.value=value; });
                                return;
                            }
                            if (field === "modifier") {
                                wrap.AddClass("V2WideField");
                                choose(wrap,"V2_"+group+index+"Modifier",modifierChoices(current.modifier),current.modifier || "",function(name) { current.modifier=name; });
                                return;
                            }
                            if (field === "value_text") { wrap.AddClass("V2WideField"); }
                            var entry = $.CreatePanel("TextEntry", wrap, "V2_" + group + index + "_" + field);
                            entry.AddClass("V2Input");
                            entry.text = String(current[keyName] === undefined ? "" : current[keyName]); entry.maxchars = 128;
                            if (field === "value_text") { entry.AddClass("V2TextInput"); }
                            entries.push({ panel: entry, key: keyName });
                        });
                        readFields = function () { entries.forEach(function (entry) { current[entry.key] = entry.panel.text; }); current = normalize(group, current); draft[key][index] = current; };
                    }
                    choose(selector, "V2_" + group + index + "Select", restrict([{ id: "" }].concat(groups[group]),function(entry) {
                        // Reference-dependent predicates need an actor picker first;
                        // validate their final reference on Apply, not the empty menu entry.
                        if (entry.id==="channel_elapsed_gte" || entry.id==="channel_elapsed_lte" || entry.id==="action_phase_is") { return ""; }
                        return entry.id && cap ? capAPI.conditionReason(cap,group,{type:entry.id},draft.target_team || targetTeam) : "";
                    }), current.type, function (type) {
                        readFields(); current.type = type; current = normalize(group, current); draft[key][index] = current; renderFields();
                    });
                    renderFields(); readers.push(function () { readFields(); });
                }(i));
            }
        }
        // Choose the team before reading detailed filters or movement options.
        label(body, "V2TargetTeamTitle", text("target_team")).AddClass("V2SectionTitle");
        label(body, "V2TargetTeamHint", text("target_team_hint")).AddClass("V2Hint");
        var team = $.CreatePanel("Panel", body, "V2TargetTeamRow"); team.AddClass("V2Selector");
        var targetTeam = draft.target_team || String(draft.target || rule.target || "enemy").split("_")[0];
        choose(team, "V2TeamSelect", restrict([{id:"team_self"}, {id:"team_ally"}, {id:"team_enemy"}],function(entry) {
            return cap && cap.teams[entry.id.substring(5)]===0 ? "target_team_incompatible" : "";
        }), "team_" + targetTeam, function (id) {
            var selected=id.substring(5);
            reopen({target_team:selected,target:selected === "self" ? "self" : selected + "_distance_nearest"});
        });
        readers.push(function () { draft.target_team = targetTeam; });
        var resetButton=$("#V2ClearConditions");
        resetButton.enabled=!options.readOnly;
        resetButton.SetPanelEvent("onactivate",function() {
            if (options.readOnly || generation!==editorGeneration) { return; }
            readers.forEach(function(read) { read(); });
            draft.use_conditions=[]; draft.target_filters=[]; draft.target_priorities=[];
            draft.desired_toggle_state=null; draft.desired_autocast_state=null; draft.destination="target";
            Object.keys(draft).forEach(function(key) {
                if (key.indexOf("movement_")===0 || key.indexOf("positioning_")===0) { delete draft[key]; }
            });
            open(rule,draft,onApply,options);
        });
        slots("use", "use_conditions", 4, "use_title");
        slots("target", "target_filters", 4, "target_title");
        slots("priority", "target_priorities", 2, "priority_title");
        label(body, "", text("action_title")).AddClass("V2SectionTitle");
        var action = rule.action || "attack";
        var extra = RpgRuleSync.actionSettings(draft, action);
        Object.keys(extra).forEach(function (key) { draft[key] = extra[key]; });
        function settingChoice(key, values) {
            var row = $.CreatePanel("Panel", body, "V2_" + key + "Row"); row.AddClass("V2Selector");
            label(row, "", text(key));
            choose(row, "V2_" + key, values.map(function (value) { return {id:key + "_" + value}; }), key + "_" + draft[key], function (id) { draft[key] = id.substring(key.length + 1); });
        }
        function settingInput(key) {
            var row = $.CreatePanel("Panel", body, ""); row.AddClass("V2Field"); row.AddClass("V2MotionField");
            label(row, "", text(key));
            var entry = $.CreatePanel("TextEntry", row, "V2_" + key); entry.AddClass("V2Input");
            entry.maxchars = 128; entry.text = String(draft[key]);
            readers.push(function () { draft[key] = entry.text; });
        }
        if (action === "sustained_move") {
            label(body, "", text("movement_hint")).AddClass("V2Hint");
            Object.keys(movementPresets).forEach(function (name) {
                button(body, "V2MovementPreset_" + name, text("movement_preset_" + name), function () {
                    readers.forEach(function (read) { read(); });
                    var preset = movementPreset(name);
                    Object.keys(preset).forEach(function (key) { draft[key] = preset[key]; });
                    open(rule, draft, onApply, options);
                });
            });
            settingChoice("movement_mode", ["follow", "pass", "orbit", "cycle"]);
            settingChoice("movement_direction", ["auto", "cw", "ccw"]);
            var buffRow = $.CreatePanel("Panel", body, ""); buffRow.AddClass("V2Selector");
            label(buffRow, "", text("movement_buff_selector"));
            choose(buffRow, "V2MovementBuffSelect", [{id:"movement_buff_custom"}], "movement_buff_custom", function () {});
            var statusRow=$.CreatePanel("Panel",body,"V2MovementStatusRow"); statusRow.AddClass("V2Selector");
            choose(statusRow,"V2MovementStatusSelect",modifierChoices(draft.movement_buff),draft.movement_buff || "",function(name) { draft.movement_buff=name; });
            label(body, "", text("movement_trigger_ability"));
            var triggerRow = $.CreatePanel("Panel", body, ""); triggerRow.AddClass("V2Selector");
            var trigger = {action_id:draft.movement_trigger_ability};
            actionPicker(triggerRow, "V2MovementTrigger", trigger, true);
            readers.push(function () { draft.movement_trigger_ability = trigger.action_id || ""; });
            settingInput("movement_duration"); settingInput("movement_distance");
            ["movement_retarget", "movement_loop", "movement_interruptible"].forEach(function (key) { settingChoice(key, [false, true]); });
        } else if (extra.positioning_mode !== undefined) {
            label(body, "", text("positioning_hint")).AddClass("V2Hint");
            settingChoice("positioning_mode", action === "attack" || action === "basic_attack" ? ["default", "fixed", "attack_range"] : ["default", "fixed", "attack_range", "cast_range"]);
            settingInput("positioning_distance"); settingInput("positioning_tolerance");
        }
        readers.push(function () {
            var normalized = RpgRuleSync.actionSettings(draft, action);
            Object.keys(draft).forEach(function (key) { if (key.indexOf("movement_") === 0 || key.indexOf("positioning_") === 0) { delete draft[key]; } });
            Object.keys(normalized).forEach(function (key) { draft[key] = normalized[key]; });
        });
        var approachRow = $.CreatePanel("Panel", body, "V2ApproachRow"); approachRow.AddClass("V2Selector");
        label(approachRow,"",text("approach_title"));
        var approach = draft.forced ? "approach_chase" : "approach_wait";
        choose(approachRow,"V2ApproachSelect",[{id:"approach_wait"},{id:"approach_chase"}],approach,function(value) { approach=value; });
        readers.push(function() { draft.forced=approach === "approach_chase"; });
        if (["ember_spirit_fire_remnant", "ember_spirit_activate_fire_remnant", "elder_titan_ancestral_spirit", "elder_titan_move_spirit"].indexOf(options.abilityName) >= 0) {
            var destinationRow = $.CreatePanel("Panel", body, "V2DestinationRow"); destinationRow.AddClass("V2Selector");
            label(destinationRow,"",text("destination"));
            var destination = draft.destination || "target", modes = ["target", "self"];
            if (options.abilityName === "ember_spirit_activate_fire_remnant") {
                modes = modes.concat(["remnant_nearest", "remnant_farthest", "remnant_near_enemy", "remnant_safe"]);
            }
            choose(destinationRow,"V2DestinationSelect",modes.map(function(mode) { return {id:"destination_"+mode}; }),
                "destination_"+destination,function(value) { destination=value.replace("destination_",""); });
            readers.push(function() { draft.destination=destination; });
        }
        if (stateKey) {
            var toggle = $.CreatePanel("Panel", body, "V2ToggleRow"); toggle.AddClass("V2Selector");
            label(toggle, "", text("toggle_title"));
            choose(toggle,"V2ToggleSelect",[{id:"toggle_on"},{id:"toggle_off"}],draft[stateKey] ? "toggle_on" : "toggle_off",function(id) {
                draft[stateKey]=id==="toggle_on";
            });
        }
        body.enabled = !options.readOnly;
        $("#RuleSettingsApply").enabled = !options.readOnly && (!strict || !!cap);
        $("#RuleSettingsApply").SetPanelEvent("onactivate", function () {
            if (options.readOnly || generation !== editorGeneration) { return; }
            readers.forEach(function (read) { read(); });
            var missing = false;
            [["use", "use_conditions"], ["target", "target_filters"]].forEach(function (spec) {
                draft[spec[1]].forEach(function (condition) {
                    var def = definitions[spec[0] + ":" + condition.type];
                    if (!def) { return; }
                    if (def.fields.indexOf("modifier") >= 0 && !String(condition.modifier || "").trim()) { missing = true; }
                    if (def.fields.indexOf("value_text") >= 0 && !String(def.fields.indexOf("value") >= 0 ? condition.value_text || "" : condition.value || "").trim()) { missing = true; }
                });
            });
            if (missing) { $("#RuleSettingsError").text = text("required_name"); return; }
            if (capAPI) {
                var latestCapability=options.getCapability ? options.getCapability() : baseCap;
                var latestStateKey=normalizeNativeSettings(latestCapability,stateKey);
                var checked=capAPI.validate(draft,latestCapability,{requireCapability:strict});
                if (!checked.ok) {
                    if (latestStateKey!==stateKey) { open(rule,draft,onApply,options); }
                    $("#RuleSettingsError").text=capAPI.describe(checked); return;
                }
            }
            if (onApply(draft) === false) { $("#RuleSettingsError").text = text("edit_conflict"); return; }
            root.SetHasClass("Hidden", true);
        });
        $("#RuleSettingsClose").SetPanelEvent("onactivate", function () { root.SetHasClass("Hidden", true); });
        root.SetHasClass("Hidden", false);
    }
    function reset() {
        editorGeneration++;
        $("#RuleSettings").SetHasClass("Hidden", true);
        $("#RuleSettingsBody").RemoveAndDeleteChildren();
        $("#RuleSettingsError").text = "";
        $("#RuleSettingsApply").enabled = false;
        $("#RuleSettingsApply").SetPanelEvent("onactivate", function () {});
    }
    return { movementPreset: movementPreset, groups: groups, abilityLabel: abilityLabel, summary: summary, normalize: normalize, wire: wire, open: open, reset: reset, number: number };
}());
