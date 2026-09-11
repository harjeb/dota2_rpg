"""Campaign diversity and native hero coverage, against both shipped data files."""
from collections import Counter, defaultdict
import json
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
read_kv = runpy.run_path(str(ROOT / 'tests/opening-balance.test.py'))['read_kv']
author = runpy.run_path(str(ROOT / 'scripts/author-enemy-roster.py'))
HERO_COUNTS = dict(zip(
    [5, 7, 8, 9, 10, 12, 13, 14, 15, 17, 18, 19, 20, 22, 23, 24, 25, 27, 28, 29, 30],
    [3] * 4 + [4] * 4 + [5] * 4 + [6] * 4 + [7] * 5))
HERO_COUNTS.update({10: 1, 20: 1, 30: 1})


class EnemyRosterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = json.loads((DATA / 'levels_v07.json').read_text(encoding='utf-8'))
        cls.runtime = read_kv((DATA / 'levels.kv').read_text(encoding='utf-8'))['levels']
        cls.teams = {}
        for label, stages in [('source', cls.source), ('runtime', cls.runtime)]:
            cls.teams[label] = {}
            for stage_id, stage in sorted(stages.items()):
                entries = stage['enemies']
                if isinstance(entries, dict):
                    entries = list(entries.values())
                heroes = [e for e in entries if e['unit'].startswith('npc_dota_hero_')]
                if heroes:
                    cls.teams[label][int(stage_id[2:])] = heroes

    def test_native_hero_coverage_after_removing_boss_escorts(self):
        native = json.loads((ROOT / 'data/native_skill_conditions.json').read_text(encoding='utf-8'))
        known = {row['hero'] for row in native['rows']}
        for label, teams in self.teams.items():
            with self.subTest(data=label):
                counts = Counter(e['unit'] for team in teams.values() for e in team)
                self.assertEqual(len(counts), 60)
                self.assertTrue(set(counts) <= known, set(counts) - known)
                self.assertEqual(Counter(counts.values()), {1: 27, 2: 33})
                self.assertEqual(sum(counts.values()), 93)
                introduced = {e['unit'] for chapter, team in teams.items()
                              if chapter <= 25 for e in team}
                self.assertEqual(len(introduced), 59)
                self.assertTrue(all(int(e.get('count', 1)) == 1
                                    for team in teams.values() for e in team))

    def test_no_local_duplicates_and_reappearances_at_least_10_chapters_apart(self):
        for label, teams in self.teams.items():
            previous = set()
            chapters = defaultdict(list)
            for chapter, team in teams.items():
                with self.subTest(data=label, chapter=chapter):
                    names = [e['unit'] for e in team]
                    self.assertEqual(len(names), len(set(names)))
                    self.assertFalse(previous.intersection(names))
                    previous = set(names)
                    for name in names:
                        chapters[name].append(chapter)
            for name, appearances in chapters.items():
                for earlier, later in zip(appearances, appearances[1:]):
                    self.assertGreaterEqual(later - earlier, 10, (label, name, appearances))

    def test_original_stage_sizes_and_distinct_bosses(self):
        for label, teams in self.teams.items():
            self.assertEqual({ch: len(team) for ch, team in teams.items()}, HERO_COUNTS, label)
            bosses = [teams[ch][0]['unit'] for ch in (10, 20, 30)]
            self.assertEqual(len(set(bosses)), 3)
            for ch in (10, 20, 30):
                tags = teams[ch][0]['tags']
                if isinstance(tags, dict):
                    tags = list(tags.values())
                self.assertIn('boss', tags)
        for ch in set(range(1, 31)) - set(HERO_COUNTS):
            stage = self.runtime[f'ch{ch:02d}']
            self.assertTrue(all(e['unit'].startswith('npc_dota_neutral_')
                                for e in stage['enemies'].values()))

    def test_every_team_has_front_damage_and_support(self):
        roles = {hero: role for role, pool in author['POOLS'].items() for hero in pool}
        self.assertEqual(len(roles), sum(len(pool) for pool in author['POOLS'].values()))
        for label, teams in self.teams.items():
            for chapter, team in teams.items():
                found = []
                for entry in team:
                    role = roles[entry['unit'].removeprefix('npc_dota_hero_')]
                    self.assertEqual(entry['ai'], author['PROFILES'][role], (label, chapter))
                    found.append(role)
                if chapter not in (10, 20, 30):
                    self.assertTrue({'front', 'damage', 'support'} <= set(found), (label, chapter))

    def test_boss_strength_only_on_the_three_chapter_bosses(self):
        fields = ['boss_max_health', 'boss_attack_damage_pct',
                  'boss_spell_amp_pct', 'boss_cooldown_reduction_pct']
        expected = {10: (6000, 16.666667, 16.666667, 4.166667),
                    20: (20000, 75, 25, 6.666667),
                    30: (32000, 100, 33.333333, 8.333333)}
        for label, teams in self.teams.items():
            for chapter, team in teams.items():
                for slot, entry in enumerate(team):
                    with self.subTest(data=label, chapter=chapter, slot=slot):
                        if chapter in expected and slot == 0:
                            self.assertEqual(tuple(float(entry[field]) for field in fields), expected[chapter])
                            defenses = (float(entry.get('boss_bonus_armor', 0)),
                                        float(entry.get('boss_magic_resistance_bonus_pct', 0)),
                                        float(entry.get('boss_magic_resistance_pct', 0)))
                            self.assertEqual(defenses, {10: (0, 0, 0), 20: (15, 0, 80), 30: (25, 30, 0)}[chapter])
                            tags = entry['tags']
                            if isinstance(tags, dict):
                                tags = list(tags.values())
                            self.assertIn('boss', tags)
                        else:
                            self.assertFalse(set(fields + ['boss_bonus_armor', 'boss_magic_resistance_bonus_pct', 'boss_magic_resistance_pct']).intersection(entry), entry['unit'])

    def test_authored_roster_matches_both_files_and_reauthoring_is_stable(self):
        intended = author['roster'](self.source)
        changes = []
        for stage_id, expected in intended.items():
            chapter = int(stage_id[2:])
            for label, teams in self.teams.items():
                actual = [(e['unit'].removeprefix('npc_dota_hero_'), e['ai']) for e in teams[chapter]]
                self.assertEqual(actual, expected, (label, chapter))
            for entry in self.source[stage_id]['enemies']:
                changes.append((entry['unit'], entry['unit'], entry['ai'], entry['items']))
        for filename, is_json in [('levels_v07.json', True), ('levels.kv', False)]:
            text = (DATA / filename).read_text(encoding='utf-8')
            self.assertEqual(author['update_text'](text, changes, is_json), text, filename)


if __name__ == '__main__':
    unittest.main(verbosity=2)
