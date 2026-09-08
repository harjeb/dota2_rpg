"""Enemy loadouts must survive source-to-KV generation with native item IDs."""
import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
read_kv = runpy.run_path(str(ROOT / 'tests/opening-balance.test.py'))['read_kv']


# Reviewed native Dota item identifiers used by these authored builds. Keep this
# independent of the authoring script so a typo there cannot approve itself.
NATIVE_ITEMS = {'item_' + name for name in '''
boots bracer null_talisman magic_wand wraith_band phase_boots power_treads
arcane_boots blink vanguard blade_mail black_king_bar crimson_guard heart
shivas_guard armlet assault satanic greater_crit halberd veil_of_discord
ultimate_scepter octarine_core dragon_lance yasha hurricane_pike manta butterfly
maelstrom mjollnir phylactery desolator bloodthorn orb_of_corrosion basher
abyssal_blade diffusal_blade echo_sabre force_staff kaya kaya_and_sange sheepstick
glimmer_cape wind_lace lotus_orb guardian_greaves aeon_disk
'''.split()}
AGILITY_CARRIES = {
    'drow_ranger', 'sniper', 'clinkz', 'phantom_assassin', 'riki', 'juggernaut',
}
SUPPORTS = {'crystal_maiden', 'witch_doctor', 'oracle', 'dazzle'}
# Hero-specific cores from chapter 15 onward. This checks identity/role while
# allowing subsequent authoring changes to other slots.
CORE_ITEMS = {
    'axe': {'blink'},
    'dragon_knight': {'blink'},
    'huskar': {'armlet'},
    'sand_king': {'blink'},
    'drow_ranger': {'dragon_lance', 'hurricane_pike'},
    'sniper': {'maelstrom', 'mjollnir'},
    'clinkz': {'phylactery', 'desolator'},
    'phantom_assassin': {'desolator'},
    'riki': {'diffusal_blade'},
    'juggernaut': {'manta', 'maelstrom', 'mjollnir'},
    'sven': {'echo_sabre', 'greater_crit'},
    'lina': {'kaya', 'kaya_and_sange'},
    'crystal_maiden': {'glimmer_cape'},
    'witch_doctor': {'glimmer_cape'},
    'oracle': {'glimmer_cape'},
    'dazzle': {'glimmer_cape'},
}


class EnemyEquipmentDataTests(unittest.TestCase):
    def setUp(self):
        self.source = json.loads((DATA / 'levels_v07.json').read_text(encoding='utf-8'))
        self.heroes = [
            (int(stage_id[2:]), index, entry)
            for stage_id, stage in self.source.items()
            for index, entry in enumerate(stage['enemies'])
            if entry['unit'].startswith('npc_dota_hero_')
        ]

    def test_inventory_counts_and_native_ids(self):
        self.assertEqual(len(self.heroes), 107)
        self.assertEqual({e['unit'].removeprefix('npc_dota_hero_')
                          for _, _, e in self.heroes}, set(CORE_ITEMS))
        for chapter, slot, entry in self.heroes:
            with self.subTest(chapter=chapter, hero=entry['unit']):
                expected_count = (2 if chapter < 10 else
                                  2 if chapter < 20 and slot == 2 else
                                  3 if chapter < 25 else
                                  4 if chapter < 30 else 5)
                self.assertEqual(len(entry['items']), expected_count)
                self.assertEqual(len(set(entry['items'])), expected_count)
                self.assertTrue(set(entry['items']) <= NATIVE_ITEMS,
                                set(entry['items']) - NATIVE_ITEMS)

    def test_every_hero_has_role_appropriate_progression(self):
        for chapter, _, entry in self.heroes:
            hero = entry['unit'].removeprefix('npc_dota_hero_')
            items = {item.removeprefix('item_') for item in entry['items']}
            with self.subTest(chapter=chapter, hero=hero):
                if hero in AGILITY_CARRIES | {'sven', 'huskar'}:
                    self.assertFalse(items & {
                        'null_talisman', 'arcane_boots', 'kaya', 'octarine_core',
                        'refresher', 'mekansm', 'guardian_greaves', 'pipe',
                        'glimmer_cape', 'lotus_orb', 'crimson_guard',
                    }, (hero, items))
                if hero in AGILITY_CARRIES and chapter < 15:
                    self.assertTrue(items & {'wraith_band', 'orb_of_corrosion'})
                if hero in SUPPORTS:
                    self.assertFalse(items & {
                        'assault', 'crimson_guard', 'satanic', 'greater_crit',
                        'desolator', 'butterfly', 'heart',
                    }, (hero, items))
                if chapter >= 15:
                    self.assertTrue(items & CORE_ITEMS[hero], (hero, items))
                if hero == 'huskar':
                    self.assertNotIn('blink', items)
                if hero == 'sand_king' and chapter >= 20:
                    self.assertIn('shivas_guard', items)
                if hero == 'witch_doctor' and chapter >= 20:
                    self.assertIn('ultimate_scepter', items)

    def test_drow_physical_build_at_each_appearance(self):
        expected = {
            8: 'boots wraith_band',
            12: 'power_treads wraith_band magic_wand',
            18: 'power_treads dragon_lance yasha',
            20: 'hurricane_pike yasha black_king_bar',
            22: 'hurricane_pike yasha black_king_bar',
            24: 'hurricane_pike yasha black_king_bar',
            28: 'hurricane_pike manta butterfly black_king_bar',
            30: 'hurricane_pike manta butterfly black_king_bar satanic',
        }
        actual = {chapter: entry['items'] for chapter, _, entry in self.heroes
                  if entry['unit'] == 'npc_dota_hero_drow_ranger'}
        self.assertEqual(actual, {chapter: ['item_' + name for name in names.split()]
                                  for chapter, names in expected.items()})

    def test_same_hero_tier_and_count_never_depend_on_enemy_slot(self):
        seen = {}
        for chapter, _, entry in self.heroes:
            key = (entry['unit'], min(chapter // 5, 6), len(entry['items']))
            if key in seen:
                self.assertEqual(entry['items'], seen[key], key)
            seen[key] = entry['items']

    def test_source_and_runtime_hero_loadouts_match(self):
        runtime = read_kv((DATA / 'levels.kv').read_text(encoding='utf-8'))['levels']
        source = json.loads((DATA / 'levels_v07.json').read_text(encoding='utf-8'))
        for stage_id, stage in runtime.items():
            actual = list(stage['enemies'].values())
            expected = source[stage_id]['enemies']
            self.assertEqual(len(actual), len(expected), stage_id)
            for entry, original in zip(actual, expected):
                self.assertEqual(entry['unit'], original['unit'], stage_id)
                if not entry['unit'].startswith('npc_dota_hero_'):
                    continue
                items = list(entry.get('items', {}).values())
                self.assertTrue(items, (stage_id, entry['unit']))
                self.assertLessEqual(len(items), 6, (stage_id, entry['unit']))
                self.assertEqual(items, original['items'], (stage_id, entry['unit']))
                self.assertNotIn('item_assault_cuirass', items,
                                 'Dota native Assault Cuirass ID is item_assault')


if __name__ == '__main__':
    unittest.main(verbosity=2)
