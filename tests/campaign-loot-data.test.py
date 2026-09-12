"""Reproducibility and full native definition accounting (no internet)."""
import importlib.util
import json
from collections import Counter
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('loot_author', ROOT / 'scripts/author-campaign-loot.py')
author = importlib.util.module_from_spec(spec)
spec.loader.exec_module(author)

class CatalogTests(unittest.TestCase):
    def test_catalog(self):
        c = json.loads((author.DATA / 'campaign_loot_catalog.json').read_text(encoding='utf-8'))
        self.assertEqual(len(c['items']), 544)
        self.assertEqual(len({r['name'] for r in c['items']}), 544)
        pool = {r['name']: r for r in c['items'] if r['category']}
        self.assertEqual(len(pool), 266)
        self.assertNotIn('item_roshans_banner', pool)
        # 本模式不需要回城卷轴：既不进掉落池，也从原版商店下架。
        self.assertNotIn('item_tpscroll', pool)
        self.assertTrue(all(not name.startswith('item_recipe_') for name in pool))
        self.assertTrue(all(r['schema'].get('ItemRecipe') != '1' for r in pool.values()))
        for r in c['items']:
            self.assertEqual(bool(r['category']), not bool(r['excluded_reason']))
        self.assertIn('item_ward_observer', pool)
        self.assertIn('item_foragers_kit', pool)
        self.assertIn('item_enhancement_quickened', pool)
        self.assertNotIn('item_keen_optic', pool)  # neutral flag alone is not current rotation
        self.assertNotIn('item_recipe_phase_boots', pool)
        # 肉山版 A 杖（含 blessing 别名）对上阵英雄无效，两条来源一起排除。
        self.assertNotIn('item_ultimate_scepter_roshan', pool)
        self.assertNotIn('item_ultimate_scepter_2', pool)
        self.assertIn('item_ultimate_scepter', pool)
        # 掉落强度分级：每行都必须带 1..5 的档位，且标准装备按价格分档。
        for name, row in pool.items():
            self.assertIn(row['power'], (1, 2, 3, 4, 5), name)
        for name, row in pool.items():
            if row['category'] != 'standard':
                continue
            cost = int(row['schema'].get('ItemCost', '0') or 0)
            self.assertEqual(row['power'], author.power_from_cost(cost), name)
        limits = author.POWER_COST_THRESHOLDS
        cheap = [r for n, r in pool.items() if r['category'] == 'standard' and r['power'] == 1]
        self.assertTrue(all(int(r['schema'].get('ItemCost', '0')) <= limits[0] for r in cheap))
        top = [r for n, r in pool.items() if r['category'] == 'standard' and r['power'] == 5]
        self.assertTrue(all(int(r['schema'].get('ItemCost', '0')) > limits[-1] for r in top))
        # 掉落池里的魔晶只以无用的肉山消耗品形式存在：两条来源一起排除。
        self.assertNotIn('item_aghanims_shard', pool)
        self.assertNotIn('item_aghanims_shard_roshan', pool)
        self.assertEqual(author.ALIASES, {})
        self.assertEqual(len({r['delivery'] for r in pool.values()}), 266)
        kv = author.native.parse_kv((author.DATA / 'loot.kv').read_text(encoding='utf-8'))['loot']
        for name, expected in [('loot_basic', .85), ('loot_hero', .85), ('loot_boss', 1.35)]:
            self.assertEqual(kv[name]['pool'], 'all_items')
            self.assertEqual(len(kv[name]['items']), 3)
            self.assertAlmostEqual(sum(float(r['chance']) for r in kv[name]['items'].values()), expected)
        lua = author.LUA.read_text(encoding='utf-8')
        for name in pool:
            self.assertIn('name = "' + name + '"', lua)
        # Runtime progression must use native total prices, including zero-cost neutrals.
        self.assertEqual(lua, author.LF.join(author.HEADER + [author.row_line(r) for r in c['items'] if r['category']] + ['}']) + author.LF)
        for row in pool.values():
            self.assertIn('cost = ' + str(int(row['schema'].get('ItemCost', '0') or 0)) + ', category = "' + row['category'] + '"', author.row_line(row))
        self.assertNotIn('item_recipe_', lua)
        self.assertNotIn('item_roshans_banner', lua)
        # 中立装备只有带标记才能在交付/转交时走专属中立槽(16),而不是 0..14。
        neutral = {r['delivery'] for r in pool.values()
                   if r['category'] in ('neutral', 'neutral_enhancement')}
        self.assertEqual(len(neutral), 68)
        for name in neutral:
            self.assertIn('delivery = "' + name + '", neutral = true', lua)
        self.assertNotIn('delivery = "item_blink", neutral = true', lua)

    @unittest.skipUnless(author.native.DEFAULT_VPK.exists(), 'installed native VPK not present')
    def test_installed_native_reproduction(self):
        native = author.native
        result = author.build(native.read_entry(native.DEFAULT_VPK, 'scripts/npc/items.txt'),
                              native.read_entry(native.DEFAULT_VPK, 'scripts/npc/neutral_items.txt'))
        self.assertEqual(result, json.loads((author.DATA / 'campaign_loot_catalog.json').read_text(encoding='utf-8')))

if __name__ == '__main__':
    unittest.main()
