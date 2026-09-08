"""Enemy loadouts must survive source-to-KV generation with native item IDs."""
from collections import Counter
import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
read_kv = runpy.run_path(str(ROOT / 'tests/opening-balance.test.py'))['read_kv']


AUTHOR = runpy.run_path(str(ROOT / 'scripts/author-enemy-equipment.py'))
EXPECTED_HEROES = set('''
axe dragon_knight huskar sand_king drow_ranger sniper clinkz phantom_assassin
riki juggernaut sven lina crystal_maiden witch_doctor oracle dazzle centaur
tidehunter bristleback slardar skeleton_king life_stealer chaos_knight
night_stalker spirit_breaker abaddon omniknight undying razor viper luna
gyrocopter bloodseeker slark troll_warlord ursa antimage phantom_lancer
templar_assassin nevermore lich lion shadow_shaman warlock jakiro disruptor
death_prophet necrolyte queenofpain leshrac zuus pugna vengefulspirit venomancer
skywrath_mage ancient_apparition grimstroke shadow_demon bane silencer treant
enchantress ogre_magi dark_willow
'''.split())

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
pipe bloodstone eternal_shroud sange_and_yasha skadi mask_of_madness bfury
invis_sword silver_edge harpoon disperser mekansm aether_lens refresher cyclone wind_waker
orchid spirit_vessel rod_of_atos meteor_hammer hand_of_midas
'''.split()}
AGILITY_CARRIES = {
    'drow_ranger', 'sniper', 'clinkz', 'phantom_assassin', 'riki', 'juggernaut',
    'razor', 'viper', 'luna', 'gyrocopter', 'bloodseeker', 'slark',
    'troll_warlord', 'ursa', 'antimage', 'phantom_lancer', 'templar_assassin',
    'nevermore',
}
PHYSICAL_STRENGTH = {
    'sven', 'huskar', 'slardar', 'skeleton_king', 'life_stealer',
    'chaos_knight', 'night_stalker', 'abaddon',
}
SUPPORTS = {
    'crystal_maiden', 'witch_doctor', 'oracle', 'dazzle', 'omniknight', 'undying',
    'lich', 'lion', 'shadow_shaman', 'warlock', 'jakiro', 'disruptor',
    'vengefulspirit', 'venomancer', 'ancient_apparition', 'grimstroke',
    'shadow_demon', 'bane', 'silencer', 'treant', 'enchantress', 'ogre_magi',
    'dark_willow',
}
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
    'centaur': {'blink'}, 'tidehunter': {'blink'},
    'bristleback': {'bloodstone'}, 'slardar': {'blink'},
    'skeleton_king': {'armlet'}, 'life_stealer': {'armlet'},
    'chaos_knight': {'armlet'}, 'night_stalker': {'echo_sabre', 'harpoon'},
    'spirit_breaker': {'invis_sword', 'silver_edge'},
    'abaddon': {'echo_sabre', 'harpoon'},
    'omniknight': {'mekansm', 'guardian_greaves'},
    'undying': {'mekansm', 'guardian_greaves'},
    'razor': {'yasha', 'sange_and_yasha'},
    'viper': {'dragon_lance', 'hurricane_pike'},
    'luna': {'yasha', 'manta'}, 'gyrocopter': {'maelstrom', 'mjollnir'},
    'bloodseeker': {'maelstrom', 'mjollnir'},
    'slark': {'diffusal_blade', 'disperser'}, 'troll_warlord': {'bfury'},
    'ursa': {'bfury'}, 'antimage': {'bfury'},
    'phantom_lancer': {'diffusal_blade', 'disperser'},
    'templar_assassin': {'desolator'}, 'nevermore': {'dragon_lance', 'hurricane_pike'},
    'lich': {'glimmer_cape'}, 'lion': {'blink'}, 'shadow_shaman': {'blink'},
    'warlock': {'glimmer_cape'}, 'jakiro': {'force_staff'},
    'disruptor': {'glimmer_cape'}, 'death_prophet': {'cyclone', 'wind_waker'},
    'necrolyte': {'kaya_and_sange'}, 'queenofpain': {'orchid', 'bloodthorn'},
    'leshrac': {'bloodstone'}, 'zuus': {'phylactery'}, 'pugna': {'aether_lens'},
    'vengefulspirit': {'force_staff'}, 'venomancer': {'spirit_vessel'},
    'skywrath_mage': {'rod_of_atos'}, 'ancient_apparition': {'glimmer_cape'},
    'grimstroke': {'aether_lens'}, 'shadow_demon': {'aether_lens'},
    'bane': {'aether_lens'}, 'silencer': {'force_staff'}, 'treant': {'blink'},
    'enchantress': {'dragon_lance', 'hurricane_pike'},
    'ogre_magi': {'force_staff'}, 'dark_willow': {'cyclone', 'wind_waker'},
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
                          for _, _, e in self.heroes}, EXPECTED_HEROES)
        self.assertEqual(len(EXPECTED_HEROES), 64)
        appearances = Counter(e['unit'] for _, _, e in self.heroes)
        self.assertLessEqual(max(appearances.values()), 2)
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
                if hero in AGILITY_CARRIES | PHYSICAL_STRENGTH:
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

    def test_drow_physical_build_at_each_tier(self):
        # Independent of roster appearances, preserve the original carry build.
        expected = [
            'boots wraith_band',
            'power_treads wraith_band magic_wand',
            'power_treads dragon_lance yasha',
            'hurricane_pike yasha black_king_bar',
            'hurricane_pike manta butterfly black_king_bar',
            'hurricane_pike manta butterfly black_king_bar satanic',
        ]
        for chapter, names in zip((5, 10, 15, 20, 25, 30), expected):
            self.assertEqual(AUTHOR['loadout']('drow_ranger', chapter, len(names.split())),
                             ['item_' + name for name in names.split()])

    def test_generator_covers_every_hero_chapter_and_inventory_size(self):
        self.assertEqual(set(AUTHOR['BUILDS']), EXPECTED_HEROES)
        self.assertEqual(set(CORE_ITEMS), EXPECTED_HEROES)
        for hero in EXPECTED_HEROES:
            self.assertEqual(len(AUTHOR['BUILDS'][hero]), 6)
            for chapter in range(5, 31):
                for count in (2, 3, 4, 5):
                    with self.subTest(hero=hero, chapter=chapter, count=count):
                        items = AUTHOR['loadout'](hero, chapter, count)
                        self.assertEqual(len(items), count)
                        self.assertEqual(len(set(items)), count)
                        self.assertLessEqual(len(set(items) & {
                            'item_boots', 'item_phase_boots', 'item_power_treads',
                            'item_arcane_boots', 'item_guardian_greaves',
                        }), 1, items)
                        self.assertEqual(items, AUTHOR['loadout'](
                            hero, (chapter // 5) * 5, count))
                        self.assertTrue(set(items) <= NATIVE_ITEMS, set(items) - NATIVE_ITEMS)
                        if chapter >= 15:
                            self.assertTrue({i.removeprefix('item_') for i in items}
                                            & CORE_ITEMS[hero], items)
                        if hero in AGILITY_CARRIES | PHYSICAL_STRENGTH:
                            self.assertFalse(set(items) & {
                                'item_null_talisman', 'item_arcane_boots',
                                'item_kaya', 'item_kaya_and_sange',
                                'item_octarine_core', 'item_sheepstick',
                                'item_guardian_greaves', 'item_glimmer_cape',
                            }, items)

    def test_representative_new_hero_late_roles(self):
        expected = {
            'antimage': {'bfury', 'manta', 'abyssal_blade'},
            'phantom_lancer': {'disperser', 'manta', 'heart'},
            'chaos_knight': {'armlet', 'manta', 'heart'},
            'luna': {'manta', 'butterfly', 'satanic'},
            'centaur': {'blink', 'pipe', 'heart'},
            'tidehunter': {'blink', 'guardian_greaves', 'refresher'},
            'leshrac': {'bloodstone', 'kaya_and_sange', 'shivas_guard'},
            'queenofpain': {'bloodthorn', 'kaya_and_sange'},
            'warlock': {'ultimate_scepter', 'refresher', 'glimmer_cape'},
            'bane': {'aether_lens', 'black_king_bar', 'ultimate_scepter'},
            'omniknight': {'guardian_greaves', 'pipe', 'lotus_orb'},
        }
        for hero, required in expected.items():
            with self.subTest(hero=hero):
                items = {i.removeprefix('item_') for i in AUTHOR['loadout'](hero, 30, 5)}
                self.assertTrue(required <= items, (required, items))

    def test_same_hero_tier_and_count_never_depend_on_enemy_slot(self):
        seen = {}
        for chapter, _, entry in self.heroes:
            key = (entry['unit'], min(chapter // 5, 6), len(entry['items']))
            if key in seen:
                self.assertEqual(entry['items'], seen[key], key)
            self.assertEqual(entry['items'], AUTHOR['loadout'](
                entry['unit'].removeprefix('npc_dota_hero_'), chapter, len(entry['items'])))
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
