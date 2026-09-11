/*
 * 当前 Run 规则同步器。
 *
 * 规则数据只发送到服务端内存中的 RuleService；不使用 LocalStorage，也不把整包
 * 旧版规则 payload 当成权威状态。每条规则均携带稳定的英雄实体 ID 和槽位号。
 */
var RpgRuleSync = (function () {
    "use strict";

    var requestSerial = 0;
    var pending = {}, latestByKey = {}, failures = {};
    function showFailures() {
        var notice = $("#RuleSyncNotice");
        if (!notice) { return; }
        var keys = Object.keys(failures);
        notice.visible = keys.length > 0;
        if (keys.length) {
            var failure = failures[keys[0]];
            var category = failure.reason === "wrong_phase" ? "rule_wrong_phase"
                : failure.reason === "invalid_hero" ? "rule_invalid_hero"
                : failure.reason === "action_not_allowed_for_hero" ? "rule_invalid_action" : "rule_invalid_conditions";
            notice.text = $.Localize("#dota2_rpg_v2_rule_failed") + " " + $.Localize("#"+failure.hero) + " / " + failure.slot + ": " + $.Localize("#dota2_rpg_v2_"+category) + " / " + (typeof RpgAbilityCapabilities!=="undefined" ? RpgAbilityCapabilities.message(failure.reason) : failure.reason);
        }
    }
    function onResult(result) {
        var entry = result && pending[result.request_id];
        if (!entry) { return; }
        delete pending[result.request_id];
        if (latestByKey[entry.key] !== result.request_id) { return; }
        if (Number(result.ok) === 1) { delete failures[entry.key]; }
        else {
            entry.reason = String(result.reason || "invalid_rule"); failures[entry.key] = entry;
            if ($.Msg) { $.Msg("[RPGRule] rejected "+entry.hero+" slot="+entry.slot+" reason="+entry.reason); }
        }
        showFailures();
    }

    function forgetHero(heroKey) {
        Object.keys(pending).forEach(function (id) {
            if (pending[id].heroKey === heroKey) { delete latestByKey[pending[id].key]; delete pending[id]; }
        });
        Object.keys(failures).forEach(function (key) {
            if (failures[key].heroKey === heroKey) { delete latestByKey[key]; delete failures[key]; }
        });
        showFailures();
    }

    function nextRequestId() {
        requestSerial += 1;
        return "rule_" + requestSerial + "_" + Math.floor(Date.now());
    }

    function numberValue(value, fallback) {
        var number = typeof value === "number" || typeof value === "string" && value.trim() !== "" ? Number(value) : NaN;
        return isFinite(number) ? number : fallback;
    }

    function bool(value, fallback) {
        if (value === true || value === 1 || value === "1" || value === "true") { return true; }
        if (value === false || value === 0 || value === "0" || value === "false") { return false; }
        return fallback;
    }
    function actionSettings(input, action) {
        input = input || {};
        var out = {};
        function choice(key, values, fallback) { out[key] = values.indexOf(input[key]) >= 0 ? input[key] : fallback; }
        function numeric(key, fallback) { out[key] = Math.max(0, numberValue(input[key], fallback)); }
        if (action === "sustained_move") {
            choice("movement_mode", ["follow", "pass", "orbit", "cycle"], "follow");
            choice("movement_direction", ["auto", "cw", "ccw"], "auto");
            out.movement_buff = String(input.movement_buff || "").trim().slice(0, 128);
            out.movement_trigger_ability = String(input.movement_trigger_ability || "").trim().slice(0, 128);
            numeric("movement_duration", 5); numeric("movement_distance", 150);
            ["movement_retarget", "movement_loop", "movement_interruptible"].forEach(function (key) { out[key] = bool(input[key], false); });
        } else if (action === "attack" || action === "basic_attack" || action && action.indexOf("item_") !== 0) {
            choice("positioning_mode", action === "attack" || action === "basic_attack" ? ["default", "fixed", "attack_range"] : ["default", "fixed", "attack_range", "cast_range"], "default");
            numeric("positioning_distance", 0); numeric("positioning_tolerance", 50);
        }
        return out;
    }
    function targetTeam(target) {
        if (target === "self") {
            return "self";
        }
        if (String(target).indexOf("ally_") === 0) {
            return "ally";
        }
        return "enemy";
    }

    function targetPriority(target) {
        target = String(target || "enemy_distance_nearest");
        if (target === "self") {
            return "nearest";
        }
        if (target.indexOf("distance_nearest") >= 0) {
            return "nearest";
        }
        if (target.indexOf("distance_farthest") >= 0) {
            return "farthest";
        }
        if (target.indexOf("hp_pct_lowest") >= 0) {
            return "lowest_hp_pct";
        }
        if (target.indexOf("hp_pct_highest") >= 0) {
            return "highest_hp_pct";
        }
        if (target.indexOf("hp_lowest") >= 0) {
            return "lowest_health";
        }
        if (target.indexOf("hp_highest") >= 0) {
            return "highest_health";
        }
        if (target.indexOf("armor_lowest") >= 0) {
            return "lowest_armor";
        }
        if (target.indexOf("armor_highest") >= 0) {
            return "highest_armor";
        }
        if (target.indexOf("attack_lowest") >= 0) { return "lowest_attack_damage"; }
        if (target.indexOf("mr_highest") >= 0) { return "highest_magic_resistance"; }
        if (target.indexOf("attack_highest") >= 0) {
            return "highest_attack_damage";
        }
        if (target.indexOf("mr_lowest") >= 0) {
            return "lowest_magic_resistance";
        }
        return "nearest";
    }

    function targetTypes(target) {
        return target === "self" ? "hero" : "hero,monster,summon";
    }

    function actionKind(action) {
        action = String(action || "attack");
        if (action === "sustained_move") { return "move"; }
        if (action === "attack" || action === "basic_attack") {
            return "attack";
        }
        if (action.indexOf("item_") === 0) {
            return "item";
        }
        return "ability";
    }

    function useCondition(rule) {
        var condition = String(rule.condition || "always");
        var value = numberValue(rule.value, 50);
        if (condition === "always") {
            return { type: "always" };
        }
        if (condition === "self_hp_pct_lte" || condition === "self_mana_pct_gte") {
            return { type: condition, value: value / 100 };
        }
        if (condition === "alive_enemy_count_gte") {
            return { type: condition, value: value };
        }
        if (condition === "elapsed_gte" || condition === "self_recently_damaged" || condition === "any_ally_recently_damaged") {
            return { type: condition, seconds: Math.max(1, value), value: Math.max(1, value) };
        }
        return { type: "always" };
    }

    function targetFilter(rule) {
        var target = String(rule.target || "");
        var attr = String(rule.target_attr || "");
        var value = numberValue(rule.value, 50);
        if (attr === "casting" || target === "enemy_casting") {
            return { type: "is_casting" };
        }
        if (attr === "controlled" || target.indexOf("_controlled") >= 0) {
            return { type: "is_controlled" };
        }
        return null;
    }

    function putCondition(payload, prefix, condition) {
        payload[prefix + "_type"] = condition.type;
        if (condition.modifier !== undefined) { payload[prefix + "_modifier"] = condition.modifier; }
        if (condition.value !== undefined) {
            payload[prefix + "_value"] = condition.value;
        }
        if (condition.seconds !== undefined) {
            payload[prefix + "_seconds"] = condition.seconds;
        }
        if (condition.radius !== undefined) {
            payload[prefix + "_radius"] = condition.radius;
        }
        if (condition.target_actor !== undefined) { payload[prefix + "_target_actor"] = condition.target_actor; }
        if (condition.action_actor !== undefined) { payload[prefix + "_action_actor"] = condition.action_actor; }
        if (condition.action_id !== undefined) {
            payload[prefix + "_action_id"] = condition.action_id;
        }
    }

    function serialize(args) {
        var rule = args.rule || {};
        var action = String(args.actionId || rule.action || "attack");
        var target = String(rule.target || "enemy_distance_nearest");
        var slot = Math.max(1, Math.min(32, Math.floor(numberValue(args.slot, 1))));
        var payload = {
            request_id: nextRequestId(),
            hero_index: Math.floor(numberValue(args.heroIndex, -1)),
            hero_name: String(args.heroName || ""),
            slot: slot,
            rule_id: String(args.heroName || "hero") + ":" + slot,
            enabled: rule.enabled === false ? 0 : 1,
            action_kind: actionKind(action),
            action_id: action === "attack" ? "basic_attack" : String(args.actionName || action),
            action_name: action === "attack" ? "" : String(args.actionName || ""),
            target_team: rule.target_team || targetTeam(target),
            target_types: Array.isArray(rule.target_types) ? rule.target_types.join(",") : rule.target_types || targetTypes(target),
            approach: rule.forced ? "allow_approach" : "range_only"
        };

        if (args.ruleCount !== undefined) {
            payload.rule_count = Math.max(1, Math.min(32, Math.floor(numberValue(args.ruleCount, 1))));
        }
        var condition = useCondition(rule);
        putCondition(payload, "use_condition_1", condition);

        var filter = targetFilter(rule);
        if (filter !== null) {
            putCondition(payload, "target_filter_1", filter);
        }
        payload.target_priority_1_type = targetPriority(target);
        // Explicit slots replace the legacy-derived slot only after the player authors them.
        var specs = [["use_conditions", "use_condition", "use", 4], ["target_filters", "target_filter", "target", 4], ["target_priorities", "target_priority", "priority", 2]];
        specs.forEach(function (spec) {
            if (!Array.isArray(rule[spec[0]])) { return; }
            for (var i = 0; i < spec[3]; i++) {
                var prefix = spec[1] + "_" + (i + 1);
                ["type", "value", "radius", "seconds", "action_id", "action_actor", "target_actor", "modifier"].forEach(function (field) { delete payload[prefix + "_" + field]; });
                var raw = rule[spec[0]][i] || { type: "" };
                var normalized = typeof RpgConditionCatalog !== "undefined" ? RpgConditionCatalog.wire(spec[2], raw) : raw;
                putCondition(payload, prefix, normalized);
            }
        });
        payload.condition = String(rule.condition || "always");
        payload.value = numberValue(rule.value, 50);
        payload.target = target;
        payload.target_attr = String(rule.target_attr || "");
        // A zero/absent hit count disables spatial AoE gating. Radius always
        // comes from the native spell; UI cannot enlarge its real effect.
        if (rule.destination && rule.destination !== "target") { payload.destination = rule.destination; }
        if (rule.cast_preference === "unit" || rule.cast_preference === "point") { payload.cast_preference = rule.cast_preference; }
        if (rule.desired_toggle_state === true || rule.desired_toggle_state === "1" || rule.desired_toggle_state === 1) { payload.desired_toggle_state = "1"; }
        if (rule.desired_toggle_state === false || rule.desired_toggle_state === "0" || rule.desired_toggle_state === 0) { payload.desired_toggle_state = "0"; }
        ["cast_variant","state_policy","state_mana_on","state_mana_off","state_hold_seconds"].forEach(function(key) {
            if (rule[key] !== undefined && rule[key] !== null && rule[key] !== "") { payload[key]=rule[key]; }
        });
        if (rule.desired_autocast_state !== undefined && rule.desired_autocast_state !== null && rule.desired_autocast_state !== "") {
            payload.desired_autocast_state=bool(rule.desired_autocast_state,false) ? "1" : "0";
        }
        payload.allow_unverified_modifiers=bool(rule.allow_unverified_modifiers,false) ? 1 : 0;
        var settings = actionSettings(rule, action);
        Object.keys(settings).forEach(function (key) { payload[key] = typeof settings[key] === "boolean" ? (settings[key] ? 1 : 0) : settings[key]; });
        if (action === "sustained_move") { payload.action_id = "sustained_move"; payload.action_name = ""; }
        return payload;
    }

    function sendRule(args) {
        if (!args || args.heroIndex === undefined || args.heroIndex === null
            || numberValue(args.heroIndex, -1) < 0) {
            return false;
        }
        var payload = serialize(args);
        var heroKey = String(args.heroKey || args.heroName+":"+args.heroIndex);
        var key = heroKey+":"+payload.slot;
        Object.keys(pending).forEach(function(id) { if (pending[id].key === key) { delete pending[id]; } });
        Object.keys(failures).forEach(function(id) { if (failures[id].heroKey === heroKey && failures[id].slot > payload.rule_count) { delete failures[id]; } });
        pending[payload.request_id] = {key:key,heroKey:heroKey,hero:String(args.heroName || ""),slot:payload.slot};
        latestByKey[key] = payload.request_id;
        GameEvents.SendCustomGameEventToServer("rpg_update_rule", payload);
        return true;
    }

    function list(input) {
        if (Array.isArray(input)) { return input; }
        return Object.keys(input || {}).filter(function(key) { return /^\d+$/.test(key); })
            .sort(function(a,b) { return Number(a)-Number(b); }).map(function(key) { return input[key]; });
    }
    function fromServer(source) {
        var team = source.target_team || "enemy";
        var priorities = list(source.target_priorities);
        var priority = priorities[0] && priorities[0].type || "nearest";
        var suffixes = ["distance_nearest","distance_farthest","hp_pct_lowest","hp_pct_highest","hp_lowest","hp_highest","armor_lowest","armor_highest","attack_lowest","attack_highest","mr_lowest","mr_highest"];
        var suffix = "distance_nearest";
        suffixes.forEach(function(value) { if (targetPriority("enemy_"+value) === priority) { suffix = value; } });
        var parts = suffix.split("_");
        var ordering = parts.pop();
        var attr = parts.join("_");
        var side = team === "self" ? "self" : attr === "distance" ? (team === "ally" ? "ally_" : "")+ordering : team+"_"+ordering;
        var rule = { action:source.action || (source.action_kind === "move" ? "sustained_move" : source.action_id === "basic_attack" ? "attack" : source.action_id) || "attack",enabled:Number(source.enabled)!==0,forced:Number(source.forced)===1,
            target:team === "self" ? "self" : team+"_"+suffix,target_attr:attr,target_side:side,
            destination:source.destination || "target",
            cast_preference:source.cast_preference || "auto",
            desired_toggle_state:source.desired_toggle_state === "0" ? false : source.desired_toggle_state === "1" ? true : null };
        ["use_conditions","target_filters","target_priorities"].forEach(function(key) {
            rule[key] = list(source[key]).map(function(item) {
                var copy = JSON.parse(JSON.stringify(item));
                if (String(copy.type).indexOf("_pct_") >= 0 && copy.value !== undefined) { copy.value = Number(copy.value)*100; }
                return copy;
            });
        });
        var first = rule.use_conditions[0] || {type:"always"};
        rule.condition = first.type; rule.value = first.seconds !== undefined ? first.seconds : first.value !== undefined ? first.value : 50;
        rule.target_team=team; rule.target_types=source.target_types || targetTypes(rule.target);
        ["cast_variant","state_policy","state_mana_on","state_mana_off","state_hold_seconds"].forEach(function(key) { if (source[key]!==undefined && source[key]!=="") { rule[key]=source[key]; } });
        rule.desired_autocast_state=bool(source.desired_autocast_state,null);
        rule.allow_unverified_modifiers=bool(source.allow_unverified_modifiers,false);
        var settings = actionSettings(source, rule.action);
        Object.keys(settings).forEach(function (key) { rule[key] = settings[key]; });
        return rule;
    }

    return {
        actionSettings: actionSettings,
        bool: bool,
        forgetHero: forgetHero,
        onResult: onResult,
        fromServer: fromServer,
        list: list,
        serialize: serialize,
        initialSettings: function (rule) {
            var use = useCondition(rule);
            if (use.type.indexOf("_pct_") >= 0) { use.value *= 100; }
            var settings = {
                target_team:rule.target_team || targetTeam(rule.target),
                target_types:rule.target_types || targetTypes(rule.target),
                target:rule.target,
                use_conditions: rule.use_conditions || [use],
                target_filters: rule.target_filters || [targetFilter(rule) || { type: "" }],
                target_priorities: rule.target_priorities || [{ type: targetPriority(rule.target) }],
                forced: bool(rule.forced, false),
                destination: rule.destination || "target",
                cast_preference: rule.cast_preference || "auto",
                desired_toggle_state: rule.desired_toggle_state === undefined ? null : rule.desired_toggle_state
            };
            ["desired_autocast_state","cast_variant","state_policy","state_mana_on","state_mana_off","state_hold_seconds","allow_unverified_modifiers"].forEach(function(key) { if (rule[key]!==undefined) { settings[key]=rule[key]; } });
            var extra = actionSettings(rule, rule.action);
            Object.keys(extra).forEach(function (key) { settings[key] = extra[key]; });
            return JSON.parse(JSON.stringify(settings));
        },
        sendRule: sendRule
    };
}());
