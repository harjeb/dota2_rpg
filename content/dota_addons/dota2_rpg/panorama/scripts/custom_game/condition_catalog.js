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
    ["nearest", "farthest", "lowest_hp_pct", "highest_hp_pct", "lowest_health", "highest_health", "most_missing_health", "lowest_armor", "highest_armor", "lowest_attack_damage", "highest_attack_damage", "lowest_magic_resistance", "highest_magic_resistance"].forEach(function (id) { add("priority", id, "priority", ""); });

    function text(id) { return $.Localize("#dota2_rpg_v2_" + id); }
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
            if (field === "modifier" || field === "action_id" || field === "value_text") {
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
    function open(rule, initial, onApply, options) {
        options = options || {};
        var root = $("#RuleSettings");
        var body = $("#RuleSettingsBody");
        body.RemoveAndDeleteChildren();
        var draft = clone(initial), readers = [];
        $("#RuleSettingsError").text = "";
        var activeMenu = null;
        function choose(parent, id, options, selected, changed) {
            var trigger = button(parent, id, text(selected || "none"), function () {
                if (activeMenu) { var same = activeMenu === menu; activeMenu.SetHasClass("Hidden", true); activeMenu = null; if (same) { return; } }
                menu.SetHasClass("Hidden", false); activeMenu = menu;
            });
            var menu = $.CreatePanel("Panel", parent, id + "Menu"); menu.AddClass("V2Choices"); menu.AddClass("Hidden");
            var category = "";
            options.forEach(function (option) {
                if (option.category && category !== option.category) { category = option.category; label(menu, "", text("category_" + category)).AddClass("V2Category"); }
                button(menu, "", text(option.id || "none"), function () {
                    trigger.GetChild(0).text = text(option.id || "none"); menu.SetHasClass("Hidden", true); activeMenu = null; changed(option.id);
                });
            });
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
                        var fields = (definitions[group + ":" + current.type] || { fields: [] }).fields;
                        var entries = [];
                        fields.forEach(function (field) {
                            var keyName = field === "value_text" && def.fields.indexOf("value") < 0 ? "value" : field;
                            var wrap = $.CreatePanel("Panel", params, ""); wrap.AddClass("V2Field");
                            label(wrap, "", text(field === "value" && current.type.indexOf("_pct_") >= 0 ? "percent" : field));
                            var entry = $.CreatePanel("TextEntry", wrap, "V2_" + group + index + "_" + field);
                            entry.text = String(current[keyName] === undefined ? "" : current[keyName]); entry.maxchars = 128;
                            if (field === "modifier" || field === "action_id" || field === "value_text") { entry.AddClass("V2TextInput"); }
                            entries.push({ panel: entry, key: keyName });
                        });
                        readFields = function () { entries.forEach(function (entry) { current[entry.key] = entry.panel.text; }); current = normalize(group, current); draft[key][index] = current; };
                    }
                    choose(selector, "V2_" + group + index + "Select", [{ id: "" }].concat(groups[group]), current.type, function (type) {
                        readFields(); current.type = type; current = normalize(group, current); draft[key][index] = current; renderFields();
                    });
                    renderFields(); readers.push(function () { readFields(); });
                }(i));
            }
        }
        if (!options.readOnly && options.abilityName && typeof RpgSkillPresets !== "undefined") {
            var variants = RpgSkillPresets.variants(options.abilityName);
            if (variants.length) {
                label(body, "", text("preset_hint")).AddClass("V2Hint");
                variants.forEach(function(variant,index) {
                    var preset = RpgSkillPresets.get(options.abilityName,variant);
                    var gate = (preset.use_conditions || [])[0] || (preset.target_filters || [])[0];
                    var title = text(preset.desired_toggle_state === "0" ? "preset_off" : "preset") + " " + (index+1);
                    if (gate) { title += ": " + text(gate.type); }
                    button(body,"V2Preset"+index,title,function() {
                        preset = RpgSkillPresets.get(options.abilityName,variant);
                        preset.min_aoe_hits = preset.min_aoe_hits || 0;
                        if (preset.desired_toggle_state === undefined) { preset.desired_toggle_state = null; }
                        open(rule,preset,onApply,options);
                    });
                });
            } else {
                label(body,"",text("preset_unavailable")).AddClass("V2Hint");
            }
        }
        slots("use", "use_conditions", 4, "use_title");
        slots("target", "target_filters", 4, "target_title");
        slots("priority", "target_priorities", 2, "priority_title");
        label(body, "", text("action_title")).AddClass("V2SectionTitle");
        var casting = $.CreatePanel("Panel",body,""); casting.AddClass("V2Selector");
        label(casting,"",text("cast_preference"));
        var castPreference = draft.cast_preference || "auto";
        choose(casting,"V2CastSelect",[{id:"cast_auto"},{id:"cast_unit"},{id:"cast_point"}],"cast_"+castPreference,function(id) { castPreference=id.substring(5); });
        readers.push(function() { draft.cast_preference=castPreference; });
        var actionOptions = $.CreatePanel("Panel", body, ""); actionOptions.AddClass("V2Parameters");
        ["min_aoe_hits"].forEach(function (key) {
            var wrap = $.CreatePanel("Panel", actionOptions, ""); wrap.AddClass("V2Field"); label(wrap, "", text(key));
            var entry = $.CreatePanel("TextEntry", wrap, "V2_" + key); entry.text = String(draft[key] === undefined ? rule[key] || 0 : draft[key]);
            readers.push(function () { draft[key] = Math.floor(number(entry.text, rule[key] || 0, 0, 20)); });
        });
        var toggle = $.CreatePanel("Panel", body, ""); toggle.AddClass("V2Selector");
        label(toggle, "", text("toggle_title"));
        var desired = draft.desired_toggle_state !== undefined ? draft.desired_toggle_state : rule.desired_toggle_state;
        var toggleValue = desired === false || desired === "0" ? "toggle_off" : desired === true || desired === "1" ? "toggle_on" : "toggle_auto";
        choose(toggle, "V2ToggleSelect", [{ id: "toggle_auto" }, { id: "toggle_on" }, { id: "toggle_off" }], toggleValue, function (id) { toggleValue = id; });
        label(body, "", text("advanced_hint")).AddClass("V2Hint");
        body.enabled = !options.readOnly;
        $("#RuleSettingsApply").enabled = !options.readOnly;
        $("#RuleSettingsApply").SetPanelEvent("onactivate", function () {
            if (options.readOnly) { return; }
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
            draft.desired_toggle_state = toggleValue === "toggle_auto" ? null : toggleValue === "toggle_on";
            onApply(draft); root.SetHasClass("Hidden", true);
        });
        $("#RuleSettingsClose").SetPanelEvent("onactivate", function () { root.SetHasClass("Hidden", true); });
        root.SetHasClass("Hidden", false);
    }
    return { groups: groups, normalize: normalize, wire: wire, open: open, number: number };
}());
