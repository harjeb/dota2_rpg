/* Standalone interaction model. No combat effects or server authority implied. */
(function (root) {
  "use strict";
  const factions = {
    element: { name: "元素", glyph: "✧", color: "#65c8ec", back: "b4abc352-adac-4c04-b317-a50fda9b5ef7.png" },
    civilization: { name: "文明", glyph: "♜", color: "#ec915c", back: "be9a6cb4-b644-4567-8cbc-dc19aac2eb63.png" },
    divine: { name: "神域", glyph: "☼", color: "#e9cb7d", back: "cbc16103-fc85-4701-881d-4925517c5031.png" },
    abyss: { name: "深渊", glyph: "◈", color: "#b998e8", back: "cc414802-49e5-4e01-a92f-5359e3ace084.png" },
    wild: { name: "荒野", glyph: "❧", color: "#a8c67a", back: "ea13d122-aee2-4716-856b-2ff57cbe5027.png" }
  };
  const heroes = [
    ["lina", "莉娜", "element"], ["crystal_maiden", "水晶室女", "element"],
    ["dragon_knight", "龙骑士", "civilization"], ["kunkka", "昆卡", "civilization"],
    ["omniknight", "全能骑士", "divine"], ["nevermore", "影魔", "abyss"],
    ["ursa", "熊战士", "wild"], ["windrunner", "风行者", "wild"]
  ].map(([id, name, faction]) => ({ id, name, faction, level: 8 }));
  const fixtures = [
    ["E-g1", "奥术共鸣", "element", "buff", "crystal_maiden", 3, "普通", "法术 · 共鸣"],
    ["E-g2", "法力涌动", "element", "buff", "storm_spirit", 2, "普通", "法力 · 循环"],
    ["E-c1", "爆裂符文", "element", "charge", "lina", 2, "普通", "符文 · 反击"],
    ["E-f1", "奥术回廊", "element", "field", "invoker", 3, "强力", "场地 · 法力"],
    ["C-g2", "铁壁", "civilization", "buff", "dragon_knight", 3, "普通", "护甲 · 防御"],
    ["C-g1", "阵列", "civilization", "buff", "legion_commander", 2, "普通", "阵列 · 进攻"],
    ["D-g1", "圣愈", "divine", "buff", "omniknight", 3, "普通", "治疗 · 守护"],
    ["D-g2", "开场祝福", "divine", "buff", "dawnbreaker", 2, "普通", "护盾 · 祝福"],
    ["A-g1", "汲取", "abyss", "buff", "nevermore", 2, "普通", "汲取 · 续航"],
    ["A-g2", "血契", "abyss", "buff", "queenofpain", 1, "普通", "生命 · 契约"],
    ["W-g1", "野性本能", "wild", "buff", "ursa", 2, "普通", "野性 · 进攻"],
    ["W-f1", "荆棘丛", "wild", "field", "treant", 2, "强力", "场地 · 反伤"],
    ["H-lina", "神灭斩·炽印", "element", "hero", "lina", 3, "强力", "莉娜 · 特殊专属", "lina"],
    ["H-cm", "冰晶之约", "element", "hero", "crystal_maiden", 2, "强力", "水晶室女 · 普通专属", "crystal_maiden"],
    ["H-dk", "古龙之血", "civilization", "hero", "dragon_knight", 2, "强力", "龙骑士 · 普通专属", "dragon_knight"],
    ["H-kunkka", "洪流·怒涛", "civilization", "hero", "kunkka", 1, "强力", "昆卡 · 普通专属", "kunkka"],
    ["H-omni", "守护天使", "divine", "hero", "omniknight", 2, "强力", "全能骑士 · 特殊专属", "omniknight"],
    ["H-sf", "魂之挽歌·狂澜", "abyss", "hero", "nevermore", 3, "强力", "影魔 · 特殊专属", "nevermore"],
    ["H-ursa", "怒意狂击·撕扯", "wild", "hero", "ursa", 2, "强力", "熊战士 · 普通专属", "ursa"],
    ["H-wr", "风之契约", "wild", "hero", "windrunner", 1, "强力", "风行者 · 普通专属", "windrunner"],
    ["E-g3", "咒能循环", "element", "buff", "invoker", 1, "普通", "冷却 · 循环"],
    ["D-g3", "光辉庇佑", "divine", "buff", "dawnbreaker", 1, "普通", "护盾 · 守护"]
  ].map(([id, name, faction, type, art, copies, tier, theme, hero]) => ({ id, name, faction, type, art, copies, tier, theme, hero, level: Math.min(3, copies), load: 1, plus: 0 }));
  const basicCards = typeof module !== "undefined" ? require("./card_forge_data.js") : GameUI.CustomUIConfig().CardForgeData;
  const definitions = basicCards.concat(fixtures.filter(c => c.type === "hero"));
  const curves = { "普通": [1, 5, 10], "强力": [1, 6, 15], "顶级": [1, 8, 20] };
  const clone = value => JSON.parse(JSON.stringify(value));
  function initial() {
    const owned = fixtures.map(fixture => Object.assign({}, clone(definitions.find(c => c.id === fixture.id)), { copies:fixture.copies, level:fixture.level, load:1 }));
    const state = { cards: owned, heroes: clone(heroes), slots: {}, points: {element: 2, civilization: 1, divine: 3, abyss: 1, wild: 2}, gold: 1200, purchases: 0, offers: ["E-g1", "H-dk", "D-g2", "H-sf", "W-f1"], bought: [], phase: "prepare" };
    [ ["crystal_maiden:hero", "H-cm", 2], ["dragon_knight:general", "C-g2", 2], ["omniknight:hero", "H-omni", 1], ["nevermore:general", "A-g1", 2], ["ursa:hero", "H-ursa", 1], ["windrunner:general", "W-g1", 1] ].forEach(([slot, id, level]) => { state.slots[slot] = id; state.cards.find(c => c.id === id).load = level; });
    return state;
  }
  const get = (s, id) => s.cards.find(c => c.id === id);
  const location = (s, id) => Object.keys(s.slots).find(key => s.slots[key] === id);
  const inventory = s => s.cards.filter(c => !location(s, c.id));
  const cost = c => curves[c.tier][c.load - 1];
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
  function apply(state, action) {
    const s = clone(state);
    if (s.phase !== "prepare" && action.type !== "return") return { error: "构筑已锁定，请先返回准备" };
    const card = get(s, action.id);
    const fail = error => ({ error });
    if (["equip", "unequip", "level", "smelt"].includes(action.type) && !card) return fail("卡牌不存在");
    switch (action.type) {
      case "equip": {
        const error = eligibility(s, action.id, action.slot);
        if (error) return fail(error);
        const source = location(s, action.id), displaced = s.slots[action.slot];
        if (source === action.slot) return fail("卡牌已经在该槽位");
        if (source && displaced && inventory(s).length >= 24) return fail("卡库已满，无法退回被替换卡；请先腾出位置");
        if (source) delete s.slots[source];
        s.slots[action.slot] = action.id;
        break;
      }
      case "unequip": {
        const source = location(s, action.id);
        if (!source) return fail("卡牌已在卡库");
        if (inventory(s).length >= 24) return fail("卡库已满，请先腾出位置");
        delete s.slots[source]; break;
      }
      case "level":
        if (!Number.isInteger(action.level) || action.level < 1 || action.level > card.level) return fail("该装载等级尚未解锁");
        card.load = action.level; break;
      case "smelt":
        if (card.type !== "hero") return fail("只有专属卡可以熔炼");
        if (location(s, card.id)) return fail("请先卸下这张专属卡");
        card.copies -= 1; s.points[card.faction] += 1;
        if (!card.copies) s.cards = s.cards.filter(c => c.id !== card.id);
        else { card.level = Math.min(3, card.copies); card.load = Math.min(card.load, card.level); }
        break;
      case "buy": {
        if (!Number.isInteger(action.index) || !s.offers[action.index]) return fail("报价不存在");
        if (s.bought.includes(action.index)) return fail("已购买该报价");
        if (s.purchases >= 3) return fail("本波购买次数已用完");
        if (s.gold < 100) return fail("金币不足");
        const error = acquire(s, s.offers[action.index]); if (error) return fail(error);
        s.gold -= 100; s.purchases++; s.bought.push(action.index); break;
      }
      case "exchange": {
        const def = definitions.find(c => c.id === action.id);
        if (!def || def.type === "hero") return fail("仅可兑换基础卡");
        if (s.points[def.faction] < 3) return fail("需要 3 点对应阵营印记");
        const error = acquire(s, def.id); if (error) return fail(error);
        s.points[def.faction] -= 3; break;
      }
      case "confirm":
        if (used(s) > budget(s)) return fail("COST 超出预算，请降低装载等级或卸卡");
        s.phase = "locked"; break;
      case "return": s.phase = "prepare"; break;
      default: return fail("未知操作");
    }
    return { state: s };
  }
  function acquire(s, id) {
    const existing = get(s, id);
    if (existing) {
      if (existing.type !== "hero" && existing.level === 3) existing.plus = Math.min(99, existing.plus + 1);
      existing.copies++; existing.level = Math.min(3, existing.copies);
    } else {
      if (inventory(s).length >= 24) return "卡库已满，无法获得新卡";
      const def = definitions.find(c => c.id === id);
      if (!def) return "卡牌未收录";
      s.cards.push({ ...clone(def), copies: 1, level: 1, load: 1, plus: 0 });
    }
    return null;
  }
  const api = { factions, heroes, definitions, curves, initial, get, location, inventory, cost, used, budget, eligibility, apply };
  if (typeof module !== "undefined") module.exports = api;
  else if (typeof GameUI !== "undefined") GameUI.CustomUIConfig().CardForgeModel = api;
  else root.CardForge = api;
})(typeof globalThis === "undefined" ? this : globalThis);
