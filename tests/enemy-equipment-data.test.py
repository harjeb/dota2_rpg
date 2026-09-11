"""Equipment research, stronger native inventories and safe source generation."""
import json
from pathlib import Path
import runpy
import statistics
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
AUTHOR = runpy.run_path(str(ROOT / 'scripts/author-enemy-equipment.py'))
read_kv = runpy.run_path(str(ROOT / 'scripts/export-level-configuration.py'))['read_kv']
EXPECTED_HEROES = set('''axe dragon_knight huskar sand_king drow_ranger sniper clinkz phantom_assassin
riki juggernaut sven lina crystal_maiden witch_doctor oracle dazzle centaur tidehunter bristleback
slardar skeleton_king life_stealer chaos_knight night_stalker spirit_breaker abaddon omniknight
undying razor viper luna gyrocopter bloodseeker slark troll_warlord ursa antimage phantom_lancer
templar_assassin nevermore lich lion shadow_shaman warlock jakiro disruptor death_prophet necrolyte
queenofpain leshrac zuus pugna vengefulspirit venomancer skywrath_mage ancient_apparition grimstroke
shadow_demon bane silencer treant enchantress ogre_magi dark_willow'''.split())


def value(items):
    return sum(AUTHOR['ITEM_COSTS'][item.removeprefix('item_')] for item in items)


class EnemyEquipmentDataTests(unittest.TestCase):
    def test_all_heroes_levels_native_slots_and_strength_progression(self):
        self.assertEqual(set(AUTHOR['BUILDS']), EXPECTED_HEROES)
        for hero, profile in AUTHOR['BUILDS'].items():
            previous = 0
            for level in range(1, 31):
                with self.subTest(hero=hero, level=level):
                    items = AUTHOR['loadout'](hero, level)
                    short = {item[5:] for item in items}
                    self.assertEqual(items, AUTHOR['loadout'](hero, str(level)))
                    self.assertEqual(len(items), len(short))
                    self.assertLessEqual(len(items), 6)
                    self.assertLessEqual(len(short & AUTHOR['BOOT_ITEMS']), 1)
                    for base, upgraded in AUTHOR['UPGRADES'].items():
                        self.assertFalse({base, upgraded} <= short, items)
                    if level >= 22: self.assertEqual(len(items), 6)
                    if level >= 14: self.assertFalse(short & {'magic_wand', 'bracer', 'wraith_band', 'null_talisman'})
                    self.assertGreaterEqual(value(items), previous)
                    previous = value(items)
                    if str(level) in profile['previous_value_at_level']:
                        old = profile['previous_value_at_level'][str(level)]
                        self.assertGreaterEqual(value(items), old)
                        if level >= 6: self.assertGreater(value(items), old)
            self.assertGreater(value(AUTHOR['loadout'](hero, 30)), 24000)
        for hero, required in {
            'skeleton_king': {'radiance', 'overwhelming_blink', 'assault', 'black_king_bar'},
            'warlock': {'ultimate_scepter', 'refresher', 'black_king_bar'},
            'antimage': {'manta', 'abyssal_blade', 'skadi'},
            'leshrac': {'bloodstone', 'kaya_and_sange', 'shivas_guard'},
        }.items():
            self.assertTrue({'item_' + item for item in required} <= set(AUTHOR['loadout'](hero, 30)))
        boss = AUTHOR['loadout']('spirit_breaker', 24, boss=True)
        self.assertEqual(len(boss), 6)
        self.assertEqual(boss.count('item_moon_shard'), 2)
        self.assertNotIn('item_moon_shard', AUTHOR['loadout']('spirit_breaker', 24))

    def test_research_is_attributable_and_does_not_invent_averages(self):
        sample = AUTHOR['RESEARCH']
        self.assertEqual(set(sample['popularity']), EXPECTED_HEROES)
        self.assertEqual(len(sample['observations']), 200)
        self.assertEqual(sum(match['included'] for match in sample['matches']), 20)
        self.assertFalse(sample['unpriced_items'])
        self.assertIn('not net worth', sample['method'])
        for source in sample['sources'].values():
            self.assertTrue(source['url'].startswith('https://api.opendota.com/api/'))
            self.assertEqual(len(source['sha256']), 64)
        for row in sample['observations']:
            self.assertNotIn('account_id', row)
            self.assertNotIn('personaname', row)
            self.assertEqual(row['equipment_value'], value(row['items']))
        for bracket, group in sample['level_groups'].items():
            low, high = map(int, bracket.split('-'))
            values = [r['equipment_value'] for r in sample['observations'] if low <= r['level'] <= high]
            self.assertEqual(group['all']['n'], len(values))
            if values:
                self.assertEqual(group['all']['mean'], round(statistics.mean(values)))
                self.assertEqual(group['all']['median'], round(statistics.median(values)))
            for stats in group.values():
                if stats['n']: self.assertGreaterEqual(stats['p75'], stats['median'])
        for hero, profile in AUTHOR['BUILDS'].items():
            observation = sample['popularity'][hero]
            self.assertEqual(profile['source_url'], observation['source']['url'])
            for item, count in profile['observed_purchases'].items():
                self.assertEqual(count, sum(observation['phases'][phase].get(item, 0)
                    for phase in ('mid_game_items', 'late_game_items')))

    def test_installed_native_items_and_moon_shards(self):
        reader = runpy.run_path(str(ROOT / 'scripts/author-playable-heroes.py'))
        if not reader['DEFAULT_VPK'].exists(): self.skipTest('Native Dota installation unavailable')
        raw = reader['read_entry'](reader['DEFAULT_VPK'], 'scripts/npc/items.txt')
        native = reader['parse_kv'](raw.decode('utf-8-sig'))['DOTAAbilities']
        names = {item for hero in EXPECTED_HEROES for level in range(1, 31) for item in AUTHOR['loadout'](hero, level)}
        names.update(AUTHOR['loadout']('spirit_breaker', 24, True))
        for name in names:
            self.assertIn(name, native)
            self.assertEqual(int(native[name]['ItemCost']), AUTHOR['ITEM_COSTS'][name[5:]])
        self.assertIn('item_gungir', names)
        self.assertNotIn('item_gleipnir', names)

    def test_runtime_authority_surgical_generation_and_idempotence(self):
        source_text = (DATA / 'levels_v07.json').read_text(encoding='utf-8')
        runtime_text = (DATA / 'levels.kv').read_text(encoding='utf-8')
        self.assertEqual(AUTHOR['update_equipment'](source_text, runtime_text), [source_text, runtime_text])
        source, runtime = json.loads(source_text), read_kv(runtime_text)['levels']
        count = 0
        for stage_id, stage in source.items():
            for entry, live in zip(stage['enemies'], runtime[stage_id]['enemies'].values()):
                if not entry['unit'].startswith('npc_dota_hero_'): continue
                count += 1
                self.assertEqual(str(entry['level']), live['level'])
                boss = 'boss' in live.get('tags', {}).values()
                expected = AUTHOR['loadout'](entry['unit'][14:], live['level'], boss)
                self.assertEqual(entry['items'], expected)
                self.assertEqual(list(live['items'].values()), expected)
        self.assertEqual(count, 93)
        source['ch30']['enemies'][0]['level'] = 30
        changed = runtime_text.replace('"level" "30"', '"level" "2"')
        updated_source, updated_runtime = AUTHOR['update_equipment'](json.dumps(source), changed)
        boss = json.loads(updated_source)['ch30']['enemies'][0]
        self.assertEqual(boss['level'], 2)
        self.assertEqual(boss['items'], ['item_bracer'])
        original, updated = read_kv(changed)['levels'], read_kv(updated_runtime)['levels']
        for chapter, stage in original.items():
            for index, enemy in stage['enemies'].items():
                for field, val in enemy.items():
                    if field != 'items': self.assertEqual(updated[chapter]['enemies'][index][field], val)
            for field, val in stage.items():
                if field != 'enemies': self.assertEqual(updated[chapter][field], val)

    def test_invalid_level_and_roster_mismatch_fail_before_writes(self):
        for level in (0, 31, 8.5, 'nan', 'inf'):
            with self.assertRaises(ValueError): AUTHOR['loadout']('axe', level)
        source = (DATA / 'levels_v07.json').read_text(encoding='utf-8')
        runtime = (DATA / 'levels.kv').read_text(encoding='utf-8')
        with self.assertRaises(ValueError):
            AUTHOR['update_equipment'](source, runtime.replace('npc_dota_hero_axe', 'npc_dota_hero_sven', 1))


if __name__ == '__main__':
    unittest.main(verbosity=2)
