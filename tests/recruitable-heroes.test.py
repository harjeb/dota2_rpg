import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
read_kv = runpy.run_path(str(ROOT / 'tests/opening-balance.test.py'))['read_kv']

class RecruitableHeroesTests(unittest.TestCase):
    def test_explicit_pool_and_native_identities(self):
        data = read_kv((DATA / 'heroes.kv').read_text(encoding='utf-8'))['heroes']
        pool = data['recruitable']
        self.assertEqual({k: len(v) for k, v in pool.items()},
                         dict(strength=9, agility=9, intelligence=8, universal=9))
        names = [name for group in pool.values() for name in group.values()]
        self.assertEqual(len(set(names)), 35)
        native = {r['hero'] for r in json.loads((ROOT / 'data/native_skill_conditions.json').read_text(encoding='utf-8'))['rows']}
        self.assertFalse(set(names) - native)
        additions = dict(strength='largo', agility='morphling', universal='arc_warden')
        legacy = json.loads((DATA / 'heroes.json').read_text(encoding='utf-8'))
        for category, hero in additions.items():
            name = 'npc_dota_hero_' + hero
            self.assertIn(name, pool[category].values())
            self.assertIn(name, [entry['name'] for entry in legacy[category]])
        # The complete reference catalog no longer overrides the playable subset.
        self.assertGreater(len(data['strength']), len(pool['strength']))
        self.assertNotIn('npc_dota_hero_invoker', names)

if __name__ == '__main__':
    unittest.main()
