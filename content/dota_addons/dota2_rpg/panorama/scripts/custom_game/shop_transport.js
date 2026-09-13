// Single bounded, atomic snapshot assembler. No UI mutation before completion.
(function (root) {
    "use strict";
    function create(deliver, now, request) {
        now = now || function () { return Date.now() / 1000; };
        var generation = -1, revision = -1, committed = -1, pending = null;
        var MAX_CHUNKS = 512, MAX_CHARS = 256, TTL = 15;
        var lastProbe = -Infinity, committedGeneration = -1, committedRevision = -1;
        function integer(n) { return typeof n === "number" && isFinite(n) && Math.floor(n) === n && n >= 0; }
        function expire() {
            if (pending && now() - pending.started >= TTL) { pending = null; }
            if (request && now() - lastProbe >= 5) {
                lastProbe = now();
                request({rule_generation: committedGeneration, shop_revision: committedRevision});
            }
        }
        function commit(data) {
            deliver(data);
            committedGeneration = Number(data.rule_generation || 0);
            committedRevision = Number(data.shop_revision);
        }
        function order(data) {
            var g = Number(data.rule_generation || 0), r = Number(data.shop_revision);
            if (!integer(g) || !integer(r) || g < generation || (g === generation && r < revision)) { return false; }
            if (g > generation || r > revision) { generation = g; revision = r; pending = null; committed = -1; }
            return r !== committed;
        }
        function normal(data) {
            expire();
            // Compatibility for old servers, before any revisioned snapshot.
            if (data && data.shop_revision === undefined && revision < 0) { deliver(data); return; }
            if (!data || !order(data)) { return; }
            pending = null; committed = revision; commit(data);
        }
        function chunk(data) {
            expire();
            if (!data || Number(data.version) !== 1 || typeof data.data !== "string" || data.data.length > MAX_CHARS) { return; }
            var count = Number(data.count), index = Number(data.index);
            if (!integer(count) || count < 1 || count > MAX_CHUNKS || !integer(index) || index < 1 || index > count || !order(data)) { return; }
            if (!pending) { pending = { count: count, parts: [], received: 0, started: now() }; }
            if (pending.count !== count) { pending = null; return; }
            if (pending.parts[index - 1] !== undefined) {
                if (pending.parts[index - 1] !== data.data) { pending = null; }
                return;
            }
            pending.parts[index - 1] = data.data;
            pending.received++;
            if (pending.received !== count) { return; }
            var text = pending.parts.join(""); pending = null;
            var snapshot;
            try { snapshot = JSON.parse(text); } catch (e) { return; }
            if (!snapshot || Array.isArray(snapshot) || Number(snapshot.rule_generation || 0) !== generation || Number(snapshot.shop_revision) !== revision) { return; }
            committed = revision; commit(snapshot);
        }
        return { normal: normal, chunk: chunk, expire: expire };
    }
    if (typeof module !== "undefined" && module.exports) { module.exports = { create: create }; }
    else { root.RpgShopTransport = { create: create }; }
}(this));
