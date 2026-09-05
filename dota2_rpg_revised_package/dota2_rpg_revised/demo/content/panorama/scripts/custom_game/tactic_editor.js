(function () {
    "use strict";

    const MAX_RULES = 10;
    let requestCounter = 1;
    const pending = {};

    function nextRequestId() {
        return String(requestCounter++);
    }

    function emptyCondition() {
        return { type: "", value: "", radius: "", seconds: "", actionId: "" };
    }

    function emptyPriority() {
        return { type: "", value: "" };
    }

    function createDefaultRule(slot) {
        return {
            slot: slot,
            enabled: true,
            actionKind: slot === MAX_RULES ? "attack" : "ability",
            actionId: slot === MAX_RULES ? "basic_attack" : "",
            actionName: "",
            castType: "",
            targetMode: "unit",
            targetTeam: "enemy",
            targetTypes: ["hero", "monster", "summon"],
            targetFilters: [emptyCondition(), emptyCondition()],
            targetPriorities: [emptyPriority(), emptyPriority()],
            useConditions: [emptyCondition(), emptyCondition()],
            approach: "range_only",
            chaseTimeout: "",
            maxChaseDistance: "",
            minAoeHits: "",
            aoeRadius: "",
            aoePreferTag: ""
        };
    }

    function encodeCondition(payload, prefix, condition) {
        payload[prefix + "_type"] = condition && condition.type || "";
        payload[prefix + "_value"] = condition && condition.value !== undefined ? String(condition.value) : "";
        payload[prefix + "_radius"] = condition && condition.radius !== undefined ? String(condition.radius) : "";
        payload[prefix + "_seconds"] = condition && condition.seconds !== undefined ? String(condition.seconds) : "";
        payload[prefix + "_action_id"] = condition && condition.actionId || "";
    }

    function encodePriority(payload, prefix, priority) {
        payload[prefix + "_type"] = priority && priority.type || "";
        payload[prefix + "_value"] = priority && priority.value !== undefined ? String(priority.value) : "";
    }

    function normalizePercentCondition(condition) {
        if (!condition || !condition.type || condition.value === "") {
            return condition;
        }
        if (condition.type.indexOf("_pct_") !== -1) {
            const uiValue = Number(condition.value);
            return Object.assign({}, condition, { value: Math.max(0, Math.min(100, uiValue)) / 100 });
        }
        return condition;
    }

    function buildPayload(heroIndex, rule) {
        const payload = {
            request_id: nextRequestId(),
            hero_index: String(heroIndex),
            slot: String(rule.slot),
            rule_id: "hero_" + heroIndex + "_rule_" + rule.slot,
            enabled: rule.enabled ? "1" : "0",
            action_kind: rule.actionKind,
            action_id: rule.actionId,
            action_name: rule.actionName || "",
            cast_type: rule.castType || "",
            target_mode: rule.targetMode || "",
            target_team: rule.targetTeam,
            target_types: (rule.targetTypes || []).join(","),
            desired_toggle_state: rule.desiredToggleState === true ? "1" : (rule.desiredToggleState === false ? "0" : ""),
            approach: rule.approach,
            chase_timeout: rule.chaseTimeout || "",
            max_chase_distance: rule.maxChaseDistance || "",
            min_aoe_hits: rule.minAoeHits || "",
            aoe_radius: rule.aoeRadius || "",
            aoe_prefer_tag: rule.aoePreferTag || ""
        };

        encodeCondition(payload, "target_filter_1", normalizePercentCondition(rule.targetFilters[0]));
        encodeCondition(payload, "target_filter_2", normalizePercentCondition(rule.targetFilters[1]));
        encodePriority(payload, "target_priority_1", rule.targetPriorities[0]);
        encodePriority(payload, "target_priority_2", rule.targetPriorities[1]);
        encodeCondition(payload, "use_condition_1", normalizePercentCondition(rule.useConditions[0]));
        encodeCondition(payload, "use_condition_2", normalizePercentCondition(rule.useConditions[1]));
        return payload;
    }

    function validateLocally(rule) {
        if (!rule.actionKind || !rule.actionId) {
            return "请选择动作";
        }
        if (["self", "ally", "enemy"].indexOf(rule.targetTeam) === -1) {
            return "目标阵营无效";
        }
        if (["range_only", "allow_approach"].indexOf(rule.approach) === -1) {
            return "接近策略无效";
        }
        return "";
    }

    function submitRule(heroIndex, rule, onResult) {
        const localError = validateLocally(rule);
        if (localError) {
            onResult(false, localError);
            return;
        }

        const payload = buildPayload(heroIndex, rule);
        pending[payload.request_id] = onResult;
        GameEvents.SendCustomGameEventToServer("rpg_update_rule", payload);
    }

    function onRuleResult(args) {
        const callback = pending[String(args.request_id)];
        if (!callback) {
            return;
        }
        delete pending[String(args.request_id)];
        callback(Number(args.ok) === 1, args.reason || "");
    }

    function describeRule(rule) {
        const hard = rule.targetFilters.filter(c => c.type).map(c => c.type + " " + c.value).join(" 且 ");
        const prefer = rule.targetPriorities.filter(p => p.type).map(p => p.type + (p.value ? ":" + p.value : "")).join("，其次 ");
        const when = rule.useConditions.filter(c => c.type).map(c => c.type + " " + c.value).join(" 且 ");
        return [
            rule.actionId + " → " + rule.targetTeam,
            hard ? "仅限：" + hard : "",
            prefer ? "优先：" + prefer : "",
            when ? "当：" + when : "",
            rule.approach === "allow_approach" ? "允许接近" : "仅限当前范围"
        ].filter(Boolean).join("；");
    }

    GameEvents.Subscribe("rpg_rule_update_result", onRuleResult);

    // Expose a small controller to XML panels or the existing editor code.
    $.GetContextPanel().RPGTacticEditor = {
        MAX_RULES: MAX_RULES,
        createDefaultRule: createDefaultRule,
        submitRule: submitRule,
        describeRule: describeRule
    };
})();
