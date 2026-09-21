/* Authoritative snapshots and read-only catalog helpers. */
(function (root) {
  "use strict";
  const factions = {
    element: { name: "元素", glyph: "✧", color: "#65c8ec", back: "b4abc352-adac-4c04-b317-a50fda9b5ef7.png" },
    civilization: { name: "文明", glyph: "♜", color: "#ec915c", back: "be9a6cb4-b644-4567-8cbc-dc19aac2eb63.png" },
    divine: { name: "神域", glyph: "☼", color: "#e9cb7d", back: "cbc16103-fc85-4701-881d-4925517c5031.png" },
    abyss: { name: "深渊", glyph: "◈", color: "#b998e8", back: "cc414802-49e5-4e01-a92f-5359e3ace084.png" },
    wild: { name: "荒野", glyph: "❧", color: "#a8c67a", back: "ea13d122-aee2-4716-856b-2ff57cbe5027.png" }
  };
  const definitions = typeof module !== "undefined" ? require("./card_forge_data.js") : GameUI.CustomUIConfig().CardForgeData;
  const curves = { "普通": [1, 5, 10], "强力": [1, 6, 15], "顶级": [1, 8, 20] };
  function initial() {
    return { cards: [], heroes: [], slots: {}, points: {}, gold: 0, purchases: 0, offers: [], bought: [], phase: "loading", run_id: "", revision: -1, wave: 0, supported: [], combat: { cards: [] } };
  }
  function snapshot(payload) {
    const s = JSON.parse(payload.state_json);
    if (!s || !Array.isArray(s.cards) || !Array.isArray(s.heroes) || !s.slots || !s.points ||
        !Array.isArray(s.offers) || !Array.isArray(s.bought) || !Array.isArray(s.supported) ||
        typeof s.run_id !== "string" || !Number.isInteger(s.revision) || !Number.isInteger(s.wave) ||
        ["prepare", "locked"].indexOf(s.phase) < 0) throw new Error("Invalid card snapshot");
    s.cards = s.cards.map(c => Object.assign({}, definitions.find(d => d.id === c.id) || {}, c));
    s.combat = s.combat || { cards: [] };
    return s;
  }
  const supported = (s, id) => s.supported.indexOf(id) >= 0;
  const get = (s, id) => s.cards.find(c => c.id === id);
  const location = (s, id) => Object.keys(s.slots).find(key => s.slots[key] === id);
  const inventory = s => s.cards.filter(c => !location(s, c.id));
  const cost = c => c ? (curves[c.tier] || curves["普通"])[(c.load || 1) - 1] : 0;
  const used = s => Object.values(s.slots).reduce((sum, id) => sum + cost(get(s, id)), 0);
  const budget = s => s.heroes.reduce((sum, h) => sum + h.level, 0);
  function eligibility(s, id, key) {
    const card = get(s, id);
    if (!card) return "卡牌不存在";
    const [hero, kind] = key.split(":");
    if (!s.heroes.some(h => h.id === hero) || !["hero", "general"].includes(kind)) return "槽位不存在";
    if (kind === "hero" && card.hero !== hero) return "专属槽只能装备该英雄的专属卡";
    if (kind === "general" && card.type === "hero") return "英雄专属卡需要对应英雄的专属槽";
    return null;
  }
  // Return intents only; never predict inventory or economy changes.
  function apply(s, action) {
    if (s.phase !== "prepare") return { error: "构筑已锁定，请先返回准备" };
    if (!["equip", "unequip", "level", "smelt", "buy", "exchange", "confirm"].includes(action.type)) return { error: "未知操作" };
    const card = get(s, action.id);
    if (["equip", "unequip", "level", "smelt"].includes(action.type) && !card) return { error: "卡牌不存在" };
    if (action.type === "equip") {
      const error = eligibility(s, action.id, action.slot);
      if (error) return { error };
    }
    if (action.type === "exchange" && !supported(s, action.id)) return { error: "卡牌尚未实现" };
    if (action.type === "buy" && (!Number.isInteger(action.index) || !supported(s, s.offers[action.index]) || s.bought.includes(action.index))) return { error: "报价不存在" };
    return { intent: Object.assign({}, action, { run_id: s.run_id, revision: s.revision, wave: s.wave }) };
  }
  const api = { factions, definitions, curves, initial, get, location, inventory, cost, used, budget, eligibility, apply, snapshot, supported };
  if (typeof module !== "undefined") module.exports = api;
  else if (typeof GameUI !== "undefined") GameUI.CustomUIConfig().CardForgeModel = api;
  else root.CardForge = api;
})(typeof globalThis === "undefined" ? this : globalThis);
