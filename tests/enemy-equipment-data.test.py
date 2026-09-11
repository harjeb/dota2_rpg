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
shivas_guard armlet assault satanic greater_crit heavens_halberd veil_of_discord
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
    def test_all_heroes_all_levels_native_slots_roles_and_determinism(self):
        self.assertEqual(set(AUTHOR['BUILDS']), EXPECTED_HEROES)
        for hero in EXPECTED_HEROES:
            for level in range(1, 31):
                with self.subTest(hero=hero, level=level):
                    items = AUTHOR['loadout'](hero, level)
                    short = {item.removeprefix('item_') for item in items}
                    self.assertEqual(items, AUTHOR['loadout'](hero, str(level)))
                    self.assertEqual(len(items), len(set(items)))
                    self.assertLessEqual(len(items), 5 if hero in SUPPORTS else 6)
                    self.assertEqual(len(short & AUTHOR['BOOT_ITEMS']), 0 if level <= 3 else 1)
                    self.assertTrue(set(items) <= NATIVE_ITEMS, set(items) - NATIVE_ITEMS)
                    for base, upgraded in AUTHOR['UPGRADES'].items():
                        self.assertFalse({base, upgraded} <= short, items)
                    if level >= 18:
                        self.assertTrue(short & CORE_ITEMS[hero], (hero, items))
                    if hero in AGILITY_CARRIES | PHYSICAL_STRENGTH:
                        self.assertFalse(short & {'arcane_boots', 'null_talisman', 'glimmer_cape',
                                                 'guardian_greaves', 'kaya', 'octarine_core'})
                    if hero in SUPPORTS:
                        self.assertFalse(short & {'assault', 'satanic', 'greater_crit', 'butterfly', 'heart'})
                    if level <= 6:
                        self.assertFalse(short & {'blink', 'black_king_bar', 'force_staff', 'ultimate_scepter'})
                    if level >= 26:
                        self.assertGreaterEqual(len(items), 5)

    def test_drow_low_mid_and_high_level_builds(self):
        expected = {
            1: 'wraith_band', 4: 'boots wraith_band',
            8: 'power_treads wraith_band magic_wand',
            12: 'power_treads dragon_lance magic_wand',
            16: 'power_treads dragon_lance yasha magic_wand',
            20: 'power_treads hurricane_pike yasha black_king_bar',
            24: 'power_treads hurricane_pike manta butterfly black_king_bar',
            30: 'power_treads hurricane_pike manta butterfly black_king_bar satanic',
        }
        for level, names in expected.items():
            self.assertEqual(AUTHOR['loadout']('drow_ranger', level),
                             ['item_' + name for name in names.split()])
        for hero, required in {
            'antimage': {'bfury', 'manta', 'abyssal_blade'},
            'phantom_lancer': {'disperser', 'manta', 'heart'},
            'centaur': {'blink', 'pipe', 'heart'},
            'leshrac': {'bloodstone', 'kaya_and_sange', 'shivas_guard'},
            'warlock': {'glimmer_cape', 'ultimate_scepter', 'refresher'},
        }.items():
            self.assertTrue({'item_' + item for item in required} <= set(AUTHOR['loadout'](hero, 30)))

    def test_representative_inventory_value_is_level_appropriate(self):
        # Approximate authored balance estimates, not live patch prices or
        # public-match observations. Broad ranges tolerate native price changes.
        costs = dict(zip('boots bracer wraith_band null_talisman magic_wand wind_lace phase_boots power_treads arcane_boots blink vanguard blade_mail black_king_bar crimson_guard heart shivas_guard assault dragon_lance yasha hurricane_pike manta butterfly satanic force_staff kaya kaya_and_sange ultimate_scepter sheepstick octarine_core glimmer_cape'.split(),
                         [500,505,505,505,450,250,1500,1400,1400,2250,1700,2100,4050,3725,5200,5175,5125,1900,2100,4450,4650,5450,5050,2200,2100,4100,4200,5200,4800,2150]))
        for hero in ('axe', 'drow_ranger', 'lina', 'crystal_maiden'):
            previous = 0
            for level in range(1, 31):
                value = sum(costs[item.removeprefix('item_')] for item in AUTHOR['loadout'](hero, level))
                self.assertGreaterEqual(value, previous, (hero, level, value, previous))
                previous = value
                if level <= 3: self.assertLessEqual(value, 600)
                elif level <= 6: self.assertLessEqual(value, 1100)
                elif level <= 9: self.assertLessEqual(value, 2600)
                elif level <= 13: self.assertLessEqual(value, 6500)
                elif level <= 17: self.assertLessEqual(value, 10500)
                elif level <= 21: self.assertLessEqual(value, 16000)
                elif level <= 25: self.assertLessEqual(value, 24000)
                else: self.assertTrue(11000 <= value <= 33000, (hero, value))
        self.assertLess(sum(costs[i[5:]] for i in AUTHOR['loadout']('crystal_maiden', 30)),
                        sum(costs[i[5:]] for i in AUTHOR['loadout']('drow_ranger', 30)))

    def test_runtime_levels_drive_both_files_and_rerun_is_idempotent(self):
        source_text = (DATA / 'levels_v07.json').read_text(encoding='utf-8')
        runtime_text = (DATA / 'levels.kv').read_text(encoding='utf-8')
        self.assertEqual(AUTHOR['update_equipment'](source_text, runtime_text), [source_text, runtime_text])
        source = json.loads(source_text)
        runtime = read_kv(runtime_text)['levels']
        count = 0
        for stage_id, stage in source.items():
            for entry, live in zip(stage['enemies'], runtime[stage_id]['enemies'].values()):
                if not entry['unit'].startswith('npc_dota_hero_'): continue
                count += 1
                self.assertEqual(str(entry['level']), live['level'])
                expected = AUTHOR['loadout'](entry['unit'][14:], live['level'])
                self.assertEqual(entry['items'], expected)
                self.assertEqual(list(live['items'].values()), expected)
        self.assertEqual(count, 93)
        # A late chapter with a deliberately low native level gets starter gear;
        # a stale maintenance level and prior inventory count cannot override it.
        source['ch30']['enemies'][0]['level'] = 30
        changed_runtime = runtime_text.replace('"level" "30"', '"level" "2"')
        updated_source, updated_runtime = AUTHOR['update_equipment'](json.dumps(source), changed_runtime)
        boss = json.loads(updated_source)['ch30']['enemies'][0]
        self.assertEqual(boss['level'], 2)
        self.assertEqual(boss['items'], ['item_bracer'])
        original = read_kv(changed_runtime)['levels']
        updated = read_kv(updated_runtime)['levels']
        for chapter, stage in original.items():
            for index, enemy in stage['enemies'].items():
                actual = updated[chapter]['enemies'][index]
                for field, value in enemy.items():
                    if field != 'items': self.assertEqual(actual[field], value)
            for field, value in stage.items():
                if field != 'enemies': self.assertEqual(updated[chapter][field], value)

    def test_invalid_level_and_roster_mismatch_fail_before_writes(self):
        for level in (0, 31, 8.5, 'nan', 'inf'):
            with self.assertRaises(ValueError): AUTHOR['loadout']('axe', level)
        source = (DATA / 'levels_v07.json').read_text(encoding='utf-8')
        runtime = (DATA / 'levels.kv').read_text(encoding='utf-8')
        with self.assertRaises(ValueError):
            AUTHOR['update_equipment'](source, runtime.replace('npc_dota_hero_axe', 'npc_dota_hero_sven', 1))


if __name__ == '__main__':
    unittest.main(verbosity=2)
