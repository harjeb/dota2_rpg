"""Selected carry survival equipment remains active, scoped and reproducible."""
import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
AUTHOR = runpy.run_path(str(ROOT / 'scripts/author-enemy-equipment.py'))
READ_KV = runpy.run_path(str(ROOT / 'scripts/export-level-configuration.py'))['read_kv']
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'


class EnemySurvivalTests(unittest.TestCase):
    def test_exact_encounters_and_active_slots(self):
        expected = {'ch14': ('luna', 'item_cheese'), 'ch17': ('ursa', 'item_aegis'),
                    'ch22': ('sniper', 'item_aegis'), 'ch24': ('lina', 'item_cheese'),
                    'ch25': ('gyrocopter', 'item_cheese'), 'ch27': ('ursa', 'item_aegis'),
                    'ch28': ('templar_assassin', 'item_aegis'), 'ch29': ('nevermore', 'item_cheese')}
        source = json.loads((DATA / 'levels_v07.json').read_text(encoding='utf-8'))
        runtime = READ_KV((DATA / 'levels.kv').read_text(encoding='utf-8'))['levels']
        found = {}
        for stage_id, stage in source.items():
            for entry, live in zip(stage['enemies'], runtime[stage_id]['enemies'].values()):
                items = entry.get('items', [])
                self.assertEqual(items, list(live.get('items', {}).values()))
                special = set(items) & {'item_aegis', 'item_cheese'}
                if special:
                    self.assertEqual(len(special), 1)
                    self.assertLessEqual(len(items), 6)
                    self.assertNotIn(stage_id, found)
                    found[stage_id] = (entry['unit'][14:], special.pop())
                    self.assertNotIn(found[stage_id][1], entry.get('backpack_items', []))
                    self.assertIn('item_black_king_bar', items, 'survival must retain combat immunity')
                if stage_id in ('ch24', 'ch25') and entry['unit'][14:] == expected[stage_id][0]:
                    self.assertGreaterEqual(int(live['level']), 25)
                    self.assertNotIn('quality_upgrades', live, 'default permanent Scepter replaces physical Scepter')
        self.assertEqual(found, expected)

    def test_generation_is_idempotent_and_only_selects_named_carries(self):
        texts = [(DATA / name).read_text(encoding='utf-8') for name in ('levels_v07.json', 'levels.kv')]
        self.assertEqual(AUTHOR['update_equipment'](*texts), texts)
        self.assertEqual(AUTHOR['encounter_loadout']('ch29', 'nevermore', 2),
                         AUTHOR['loadout']('nevermore', 2))
        source = json.loads(texts[0])
        for stage_id, stage in source.items():
            for entry in stage['enemies']:
                if not entry['unit'].startswith('npc_dota_hero_') or stage_id == 'ch30':
                    continue
                hero = entry['unit'][14:]
                boss = 'boss' in entry.get('tags', [])
                base = AUTHOR['loadout'](hero, entry['level'], boss)
                generated = AUTHOR['encounter_loadout'](stage_id, hero, entry['level'], boss)
                selected = AUTHOR['SURVIVAL_ITEMS'].get(stage_id)
                if not selected or hero != selected[0]:
                    self.assertEqual(generated, base)
                else:
                    self.assertEqual(len(set(generated) - set(base)), 1)
                    self.assertLessEqual(len(set(base) - set(generated)), 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
