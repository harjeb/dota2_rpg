/* Portable UI snapshots only. Restores must still pass through RpgRuleSync. */
var RpgRuleLibrary = (function () {
    "use strict";
    var KEY = "dota2_rpg_rule_library_v1", FORMAT = "dota2_rpg_rule_library";
    var MAX_TEXT = 2 * 1024 * 1024, heroes = {}, drafts = {}, requests = {}, listeners = [], error = "", importRevision = 0, heroRevisions = {};
    var own = Object.prototype.hasOwnProperty;
    var booleanFields = /^(enabled|forced|allow_unverified_modifiers|movement_retarget|movement_loop|movement_interruptible|prediction_enabled|charge_enabled)$/;
    function fail(message) { throw new Error("Rule library: " + message); }
    function plain(value) { return value && Object.prototype.toString.call(value) === "[object Object]" && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null); }
    function heroName(name) { return typeof name === "string" && /^npc_dota_hero_[a-z0-9_]+$/.test(name) && name.length <= 128; }
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    function textSize(text) {
        var bytes = 0;
        for (var i = 0; i < text.length; i += 1) {
            var code = text.charCodeAt(i);
            if (code < 128) { bytes += 1; }
            else if (code < 2048) { bytes += 2; }
            else if (code >= 55296 && code <= 56319 && i + 1 < text.length && text.charCodeAt(i + 1) >= 56320 && text.charCodeAt(i + 1) <= 57343) { bytes += 4; i += 1; }
            else { bytes += 3; }
            if (bytes > MAX_TEXT) { return bytes; }
        }
        return bytes;
    }
    function tree(value, depth, budget, key) {
        budget.nodes += 1;
        if (depth > 16 || budget.nodes > 100000) { fail("tree exceeds depth or node limit"); }
        if (/^(?:__proto__|prototype|constructor)$/.test(key)) { fail("prohibited object key"); }
        if (/(?:^|_)(?:entindex|entity|entity_id|entity_index|entityindex|entityid|unit_index|unit_entindex)(?:$|_)/i.test(key)) { fail("engine entity IDs are not portable"); }
        if (/^(target_actor|action_actor)$/.test(key) && typeof value !== "string") { fail("actor references must be strings"); }
        if (booleanFields.test(key) && typeof value !== "boolean") { fail(key + " must be boolean"); }
        if (/^desired_(toggle|autocast)_state$/.test(key) && value !== null && typeof value !== "boolean") { fail(key + " must be boolean or null"); }
        if (value === null || typeof value === "boolean") { return; }
        if (typeof value === "string") { if (value.length > 8192) { fail("string exceeds limit"); } return; }
        if (typeof value === "number") { if (!isFinite(value)) { fail("non-finite number"); } return; }
        if (Array.isArray(value)) {
            if (value.length > 1024) { fail("array exceeds limit"); }
            for (var i = 0; i < value.length; i += 1) { tree(value[i], depth + 1, budget, ""); }
            return;
        }
        if (!plain(value)) { fail("only plain JSON objects are supported"); }
        Object.keys(value).forEach(function (field) {
            if (field.length > 128) { fail("object key exceeds limit"); }
            var descriptor = Object.getOwnPropertyDescriptor(value, field);
            if (!own.call(descriptor, "value")) { fail("accessor properties are not supported"); }
            tree(descriptor.value, depth + 1, budget, field);
        });
    }
    function validate(document) {
        tree(document, 0, {nodes:0}, "");
        if (!plain(document) || document.format !== FORMAT || document.version !== 1 || !plain(document.heroes)) { fail("unsupported format or version"); }
        if (Object.keys(document).some(function (key) { return ["format", "version", "heroes"].indexOf(key) < 0; })) { fail("unknown envelope field"); }
        var names = Object.keys(document.heroes);
        if (names.length > 200) { fail("too many heroes"); }
        names.forEach(function (name) {
            if (!heroName(name)) { fail("invalid hero name"); }
            var rules = document.heroes[name];
            if (!Array.isArray(rules) || rules.length < 1 || rules.length > 32) { fail("heroes require 1..32 rules"); }
            rules.forEach(function (rule) {
                if (!plain(rule) || typeof rule.action !== "string" || !/^[a-z][a-z0-9_]*$/.test(rule.action) || rule.action.length > 128 || /^(item_[0-9]+|ability_[0-9]+|ultimate)$/.test(rule.action)) { fail("action requires a stable string ID"); }
                ["use_conditions", "target_filters", "target_priorities"].forEach(function (field, index) {
                    if (!own.call(rule, field)) { return; }
                    var conditions = rule[field];
                    if (!Array.isArray(conditions) || conditions.length > (index === 2 ? 2 : 4)) { fail("invalid " + field + " array"); }
                    conditions.forEach(function (condition) {
                        if (!plain(condition) || typeof condition.type !== "string" || !/^[a-z0-9_]*$/.test(condition.type) || condition.type.length > 128) { fail("invalid condition object"); }
                    });
                });
            });
        });
        if (textSize(JSON.stringify(document, null, 2)) > MAX_TEXT) { fail("document exceeds 2MB text limit"); }
        return document;
    }
    function envelope(data) { return {format:FORMAT, version:1, heroes:data}; }
    function parse(text) {
        if (typeof text !== "string" || text.length > MAX_TEXT || textSize(text) > MAX_TEXT) { fail("document exceeds 2MB text limit or is not text"); }
        var document;
        try { document = JSON.parse(text); } catch (exception) { fail("invalid JSON"); }
        return validate(document);
    }
    function notify(type) { listeners.slice().forEach(function (callback) { try { callback(type); } catch (ignored) {} }); }
    function storage() {
        if (typeof $ === "undefined" || !$.LocalStorage || typeof $.LocalStorage.GetItem !== "function" || typeof $.LocalStorage.SetItem !== "function") { fail("local storage is unavailable"); }
        return $.LocalStorage;
    }
    function persist(data) {
        try {
            if (storage().SetItem(KEY, JSON.stringify(envelope(data), null, 2)) === false) { fail("local storage rejected the write"); }
            error = ""; return true;
        } catch (exception) { error = String(exception.message || exception); return false; }
    }
    function dirty(hero) {
        var draft = own.call(drafts, hero) ? drafts[hero] : null;
        return !!draft && Object.keys(draft.slots).some(function (slot) { return draft.slots[slot].state !== "ok"; });
    }
    try {
        var saved = storage().GetItem(KEY);
        if (saved !== undefined && saved !== null && saved !== "") { heroes = clone(parse(saved).heroes); }
    } catch (exception) { error = String(exception.message || exception); }
    return {
        exportText: function () { return JSON.stringify(envelope(heroes), null, 2); },
        importText: function (text) {
            var incoming = parse(text).heroes, merged = clone(heroes);
            if (Object.keys(requests).length) { fail("cannot import while edits await acknowledgement"); }
            Object.keys(incoming).forEach(function (hero) { merged[hero] = incoming[hero]; });
            validate(envelope(merged));
            if (!persist(merged)) { notify("error"); fail("import was not saved: " + error); }
            heroes = clone(merged); importRevision += 1;
            Object.keys(incoming).forEach(function (hero) { heroRevisions[hero] = (heroRevisions[hero] || 0) + 1; delete drafts[hero]; });
            notify("import"); return Object.keys(incoming).length;
        },
        get: function (hero) { return own.call(heroes, hero) ? clone(heroes[hero]) : null; },
        count: function () { return Object.keys(heroes).length; },
        status: function () { return error; },
        hasPending: function (hero) { return hero === undefined ? Object.keys(drafts).some(dirty) : dirty(hero); },
        revision: function (hero) { return hero === undefined ? importRevision : (own.call(heroRevisions, hero) ? heroRevisions[hero] : 0); },
        resetPending: function () { drafts = {}; requests = {}; notify("reset"); },
        resetImports: function () { heroRevisions = {}; importRevision = 0; },
        track: function (requestId, hero, rules, slot) {
            if (!heroName(hero)) { fail("invalid hero name"); }
            if ((typeof requestId !== "string" && typeof requestId !== "number") || !String(requestId) || !/^[0-9]+$/.test(String(slot)) || Number(slot) < 1 || Number(slot) > 32) { fail("invalid request ID or slot"); }
            var data = {}; data[hero] = rules;
            try { validate(envelope(data)); }
            catch (exception) { error = String(exception.message || exception); notify("error"); throw exception; }
            var requestKey = "$" + requestId, slotKey = "$" + slot;
            if (own.call(requests, requestKey)) { fail("duplicate request ID"); }
            var draft = drafts[hero] || {slots:{}};
            // Deleting rows also removes their pending/rejected acknowledgements.
            Object.keys(draft.slots).forEach(function (key) {
                if (Number(key.slice(1)) > rules.length) {
                    delete requests[draft.slots[key].request]; delete draft.slots[key];
                }
            });
            var previous = draft.slots[slotKey];
            if (previous) { delete requests[previous.request]; }
            draft.rules = clone(rules);
            draft.slots[slotKey] = {request:requestKey, state:"pending"};
            drafts[hero] = draft; requests[requestKey] = {hero:hero, slot:slotKey}; notify("track");
        },
        result: function (result) {
            var key = "$" + (result && result.request_id), request = requests[key];
            if (!request) { return; }
            delete requests[key];
            var draft = drafts[request.hero], entry = draft.slots[request.slot];
            if (entry.request !== key) { return; }
            entry.state = result.ok === 1 || result.ok === "1" ? "ok" : "failed";
            if (!dirty(request.hero)) {
                var merged = clone(heroes); merged[request.hero] = clone(draft.rules);
                try { validate(envelope(merged)); } catch (exception) { entry.state = "failed"; error = String(exception.message || exception); notify("error"); return; }
                persist(merged); heroes = merged; delete drafts[request.hero]; notify("save");
            }
            notify("result");
        },
        subscribe: function (callback) {
            if (typeof callback !== "function") { fail("subscriber must be a function"); }
            listeners.push(callback);
            return function () { var index = listeners.indexOf(callback); if (index >= 0) { listeners.splice(index, 1); } };
        }
    };
}());
