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
        self.assertEqual(len(pool), 351)
        for r in c['items']:
            self.assertEqual(bool(r['category']), not bool(r['excluded_reason']))
        self.assertIn('item_ward_observer', pool)
        self.assertIn('item_foragers_kit', pool)
        self.assertIn('item_enhancement_quickened', pool)
        self.assertNotIn('item_keen_optic', pool)  # neutral flag alone is not current rotation
        self.assertNotIn('item_recipe_phase_boots', pool)
        self.assertEqual(pool['item_aghanims_shard']['delivery'], 'item_aghanims_shard_roshan')
        self.assertEqual(len({r['delivery'] for r in pool.values()}), 349)
        kv = author.native.parse_kv((author.DATA / 'loot.kv').read_text(encoding='utf-8'))['loot']
        for name, expected in [('loot_basic', .85), ('loot_hero', .85), ('loot_boss', 1.35)]:
            self.assertEqual(kv[name]['pool'], 'all_items')
            self.assertEqual(len(kv[name]['items']), 3)
            self.assertAlmostEqual(sum(float(r['chance']) for r in kv[name]['items'].values()), expected)
        lua = author.LUA.read_text(encoding='utf-8')
        for name in pool:
            self.assertIn('name = "' + name + '"', lua)

    @unittest.skipUnless(author.native.DEFAULT_VPK.exists(), 'installed native VPK not present')
    def test_installed_native_reproduction(self):
        native = author.native
        result = author.build(native.read_entry(native.DEFAULT_VPK, 'scripts/npc/items.txt'),
                              native.read_entry(native.DEFAULT_VPK, 'scripts/npc/neutral_items.txt'))
        self.assertEqual(result, json.loads((author.DATA / 'campaign_loot_catalog.json').read_text(encoding='utf-8')))

if __name__ == '__main__':
    unittest.main()
