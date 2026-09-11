"""Late ancient balance contract and surgical maintenance safety."""
import copy
import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
AUTHOR = runpy.run_path(str(ROOT / 'scripts/author-late-campaign-balance.py'))
EXPORT = runpy.run_path(str(ROOT / 'scripts/export-level-configuration.py'))


class LateCampaignBalanceTests(unittest.TestCase):
    def test_both_files_and_authoring_preserve_independent_fields(self):
        for filename in ('levels.kv', 'levels_v07.json'):
            text = (AUTHOR['DATA'] / filename).read_text(encoding='utf-8')
            is_json = filename.endswith('json')
            parse = json.loads if is_json else lambda value: EXPORT['normalize'](EXPORT['read_kv'](value)['levels'])
            stages = parse(text)
            self.assertEqual(AUTHOR['update_text'](text, is_json), text)
            # Deliberately vary unrelated source values to catch accidental
            # serialization from the other file or overwriting early chapters.
            varied = text.replace('"multi": 1.5', '"multi": 1.53') if is_json else text.replace('"multi" "1.5"', '"multi" "1.53"')
            self.assertEqual(AUTHOR['update_text'](varied, is_json), varied)
            late = []
            for stage_id, stage in stages.items():
                chapter = int(stage_id[2:])
                for entry in stage['enemies']:
                    if chapter > 10 and entry['unit'].startswith('npc_dota_neutral_'):
                        late.append(chapter)
                        names, *stats = AUTHOR['NEUTRALS'][chapter]
                        self.assertIn(entry['unit'], ['npc_dota_neutral_' + name for name in names])
                        self.assertEqual([float(entry[k]) for k in ('hp_multiplier', 'attack_multiplier', 'bonus_armor', 'magic_resistance')], stats)
                        self.assertFalse(any(key.startswith('boss_') for key in entry))
            self.assertEqual(sorted(set(late)), [11, 16, 21, 26])
            self.assertEqual(len(late), 16)
            # Reconstruct a pre-change balance, then prove only permitted
            # scalars are touched, with all early chapters exactly preserved.
            previous = copy.deepcopy(stages)
            for chapter, tier in AUTHOR['NEUTRALS'].items():
                for entry in previous[f'ch{chapter}']['enemies']:
                    entry.update(unit='npc_dota_neutral_kobold', hp_multiplier=1,
                                 attack_multiplier=1, bonus_armor=0, magic_resistance=0)
            for chapter in AUTHOR['BOSSES']:
                entry = previous[f'ch{chapter}']['enemies'][0]
                entry.update(boss_max_health=10000, boss_attack_damage_pct=1)
                entry.pop('boss_bonus_armor')
                entry.pop('boss_magic_resistance_bonus_pct')
            # JSON fixture exercises both insertion and existing replacements.
            fixture = json.dumps(previous, ensure_ascii=False, indent='\t') + '\n'
            actual = json.loads(AUTHOR['update_text'](fixture, True))
            expected = copy.deepcopy(previous)
            for chapter, (names, hp, attack, armor, mr) in AUTHOR['NEUTRALS'].items():
                for entry, name in zip(expected[f'ch{chapter}']['enemies'], names):
                    entry.update(unit='npc_dota_neutral_' + name, hp_multiplier=hp,
                                 attack_multiplier=attack, bonus_armor=armor, magic_resistance=mr)
            for chapter, changes in AUTHOR['BOSSES'].items():
                expected[f'ch{chapter}']['enemies'][0].update(changes)
            self.assertEqual(actual, expected)
            for chapter in range(1, 11):
                self.assertEqual(actual[f'ch{chapter:02}'], previous[f'ch{chapter:02}'])

    def test_native_ancient_proof_and_strength_progression(self):
        native = runpy.run_path(str(ROOT / 'scripts/author-playable-heroes.py'))
        if not native['DEFAULT_VPK'].exists():
            self.skipTest('Native Dota VPK is unavailable; run --verify-native on a Dota installation')
        AUTHOR['verify_native']()
        raw = native['read_entry'](native['DEFAULT_VPK'], 'scripts/npc/npc_units.txt')
        units = native['parse_kv'](raw.decode('utf-8-sig'))['DOTAUnits']
        old_names = ['gnoll_assassin', 'dark_troll_warlord', 'polar_furbolg_champion', 'kobold']
        old_stats = {11: (2.2, 1.65, 8, 34), 16: (2.9, 2, 12, 38),
                     21: (3.7, 2.4, 16, 42), 26: (4.6, 2.9, 20, 45)}
        previous_minimum = [0, 0, 0, 0]
        for chapter, (names, hp, attack, armor, mr) in AUTHOR['NEUTRALS'].items():
            multi = {11: 1.5, 16: 1.75, 21: 2, 26: 2.25}[chapter]
            values = []
            originals = old_names if chapter != 26 else old_names[:3] + ['black_dragon', 'kobold']
            for name, old in zip(names, originals):
                new, old_unit = units['npc_dota_neutral_' + name], units['npc_dota_neutral_' + old]
                def stats(unit, growth):
                    h, a, ar, resistance = growth
                    return [float(unit['StatusHealth']) * multi * h,
                            (float(unit['AttackDamageMin']) + float(unit['AttackDamageMax'])) / 2 * multi * a,
                            float(unit['ArmorPhysical']) * multi + ar, resistance]
                current = stats(new, (hp, attack, armor, mr))
                before = stats(old_unit, old_stats[chapter])
                self.assertTrue(all(a > b for a, b in zip(current, before)), (chapter, name, current, before))
                values.append(current)
            minimum = [min(row[i] for row in values) for i in range(4)]
            self.assertTrue(all(a > b for a, b in zip(minimum, previous_minimum)), (chapter, minimum))
            previous_minimum = minimum


if __name__ == '__main__':
    unittest.main(verbosity=2)
