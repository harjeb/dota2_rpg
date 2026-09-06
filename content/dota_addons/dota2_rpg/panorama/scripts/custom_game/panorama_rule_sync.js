/*
 * 当前 Run 规则同步器。
 *
 * 规则数据只发送到服务端内存中的 RuleService；不使用 LocalStorage，也不把整包
 * 旧版规则 payload 当成权威状态。每条规则均携带稳定的英雄实体 ID 和槽位号。
 */
var RpgRuleSync = (function () {
    "use strict";

    var requestSerial = 0;

    function nextRequestId() {
        requestSerial += 1;
        return "rule_" + requestSerial + "_" + Math.floor(Date.now());
    }

    function numberValue(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
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
        if (action === "attack") {
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
        if (condition === "alive_enemy_count_gte" || condition === "dead_ally_count_gte") {
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
            return { type: "is_channeling" };
        }
        if (attr === "boss" || target.indexOf("_boss") >= 0) {
            return { type: "has_tag", value: "boss" };
        }
        if (attr === "healer" || target.indexOf("_healer") >= 0) {
            return { type: "has_tag", value: "healer" };
        }
        if (attr === "controlled" || target.indexOf("_controlled") >= 0) {
            return { type: "is_stunned" };
        }
        return null;
    }

    function putCondition(payload, prefix, condition) {
        payload[prefix + "_type"] = condition.type;
        if (condition.value !== undefined) {
            payload[prefix + "_value"] = condition.value;
        }
        if (condition.seconds !== undefined) {
            payload[prefix + "_seconds"] = condition.seconds;
        }
        if (condition.radius !== undefined) {
            payload[prefix + "_radius"] = condition.radius;
        }
        if (condition.action_id !== undefined) {
            payload[prefix + "_action_id"] = condition.action_id;
        }
    }

    function serialize(args) {
        var rule = args.rule || {};
        var action = String(args.actionId || rule.action || "attack");
        var target = String(rule.target || "enemy_distance_nearest");
        var payload = {
            request_id: nextRequestId(),
            hero_index: args.heroIndex !== undefined && args.heroIndex !== null
                ? Number(args.heroIndex) : -1,
            hero_name: String(args.heroName || ""),
            slot: Number(args.slot || 1),
            rule_id: String(args.heroName || "hero") + ":" + Number(args.slot || 1),
            enabled: rule.enabled === false ? 0 : 1,
            action_kind: actionKind(action),
            action_id: action === "attack" ? "basic_attack" : String(args.actionName || action),
            action_name: action === "attack" ? "" : String(args.actionName || ""),
            target_team: targetTeam(target),
            target_types: targetTypes(target),
            approach: rule.forced ? "allow_approach" : "range_only"
        };

        var condition = useCondition(rule);
        putCondition(payload, "use_condition_1", condition);

        var filter = targetFilter(rule);
        if (filter !== null) {
            putCondition(payload, "target_filter_1", filter);
        }
        payload.target_priority_1_type = targetPriority(target);
        return payload;
    }

    function sendRule(args) {
        if (!args || args.heroIndex === undefined || args.heroIndex === null
            || Number(args.heroIndex) < 0) {
            return false;
        }
        var payload = serialize(args);
        GameEvents.SendCustomGameEventToServer("rpg_update_rule", payload);
        return true;
    }

    return {
        serialize: serialize,
        sendRule: sendRule
    };
}());
