import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
AUTHOR = runpy.run_path(str(ROOT / 'scripts/author-playable-heroes.py'))
read_kv = AUTHOR['parse_kv']

class RecruitableHeroesTests(unittest.TestCase):
    def test_native_complete_pool_and_exclusions(self):
        native = json.loads((ROOT / 'data/native_hero_pool.json').read_text(encoding='utf-8'))
        self.assertEqual(len(native['rows']), 127)
        pool = read_kv((DATA / 'heroes.kv').read_text(encoding='utf-8'))['heroes']['recruitable']
        self.assertEqual({k: len(v) for k, v in pool.items()},
                         dict(strength=35, agility=34, intelligence=32, universal=22))
        names = [name for group in pool.values() for name in group.values()]
        self.assertEqual(len(names), 123)
        self.assertEqual(len(set(names)), 123)
        self.assertEqual(set(names), {row['name'] for row in native['rows']} - AUTHOR['EXCLUDED'])
        skills = {r['hero'] for r in json.loads((ROOT / 'data/native_skill_conditions.json').read_text(encoding='utf-8'))['rows']}
        self.assertFalse(set(names) - skills)
        for row in native['rows']:
            if row['name'] not in AUTHOR['EXCLUDED']:
                self.assertIn(row['name'],pool[row['attribute']].values())
        for name in ('morphling', 'arc_warden', 'largo'):
            self.assertIn('npc_dota_hero_' + name,names)
        level_text=(DATA / 'levels.kv').read_text(encoding='utf-8')
        for excluded in AUTHOR['EXCLUDED']:
            self.assertNotIn(excluded,level_text)
        self.assertNotIn('npc_dota_hero_lifestealer',names)
        self.assertIn('npc_dota_hero_life_stealer',names)

    def test_reproducible_authoring_and_json_parity(self):
        rows=json.loads((ROOT / 'data/native_hero_pool.json').read_text(encoding='utf-8'))['rows']
        kv,js=AUTHOR['author'](rows)
        self.assertEqual(kv,(DATA / 'heroes.kv').read_text(encoding='utf-8'))
        self.assertEqual(js,(DATA / 'heroes.json').read_text(encoding='utf-8'))
        source=json.loads(js)
        for category,names in AUTHOR['pools'](rows).items():
            self.assertEqual(names,[entry['name'] for entry in source[category]])

    def test_native_flags_control_availability(self):
        fixture=b'''"DOTAHeroes" { "npc_dota_hero_base" { "Enabled" "0" }
          "npc_dota_hero_axe" { "Enabled" "1" "AttributePrimary" "DOTA_ATTRIBUTE_STRENGTH" "HeroID" "2" }
          "npc_dota_hero_disabled" { "Enabled" "0" "AttributePrimary" "DOTA_ATTRIBUTE_ALL" "HeroID" "999" } }'''
        self.assertEqual(AUTHOR['enabled_rows'](fixture),[dict(name='npc_dota_hero_axe',attribute='strength',hero_id=2)])

if __name__ == '__main__':
    unittest.main()
