"""Opening encounter data contracts; no Dota combat simulation is implied."""
import json
from pathlib import Path
import shlex
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
EXPECTED = [
    [('centaur_khan', 1), ('ogre_mauler', 2)],
    [('centaur_khan', 1), ('alpha_wolf', 1), ('ogre_mauler', 2)],
    [('centaur_khan', 1), ('satyr_hellcaller', 1), ('ogre_mauler', 2), ('gnoll_assassin', 1)],
    [('centaur_khan', 2), ('satyr_hellcaller', 1), ('ogre_mauler', 2), ('gnoll_assassin', 1)],
]


def read_kv(text):
    tokens = iter(shlex.split(text))

    def block():
        result = {}
        for key in tokens:
            if key == '}':
                return result
            value = next(tokens)
            result[key] = block() if value == '{' else value
        return result

    return block()


def render_kv(value, depth=0):
    lines = []
    for key, item in value.items():
        prefix = '\t' * depth + json.dumps(str(key), ensure_ascii=False)
        if isinstance(item, dict):
            lines.extend([prefix, '{', render_kv(item, depth + 1).rstrip('\n'), '\t' * depth + '}'])
        else:
            lines.append(prefix + ' ' + json.dumps(str(item), ensure_ascii=False))
    return '\n'.join(lines) + '\n'


class OpeningBalanceTests(unittest.TestCase):
    def test_runtime_compositions_and_source(self):
        runtime = read_kv((DATA / 'levels.kv').read_text(encoding='utf-8'))['levels']
        source = json.loads((DATA / 'levels_v07.json').read_text(encoding='utf-8'))
        for index, expected in enumerate(EXPECTED, 1):
            key = f'ch{index:02}'
            rows = list(runtime[key]['enemies'].values())
            self.assertEqual([(r['unit'], int(r['count'])) for r in rows],
                             [('npc_dota_neutral_' + name, count) for name, count in expected])
            self.assertEqual(len(rows), len(source[key]['enemies']))
            for row, original in zip(rows, source[key]['enemies']):
                for field, value in original.items():
                    self.assertEqual(str(row[field]), str(value), (key, field))
                self.assertIn(row['ai'], ('simple_nearest', 'focus_lowest_hp'))
                self.assertGreaterEqual(float(row['hp_multiplier']), 1)
            self.assertEqual(int(runtime[key]['reward']['gold']), 800 + index * 100)
            self.assertEqual(int(runtime[key]['reward']['xp_per_active_hero']), [120, 160, 200, 250][index - 1])
            self.assertEqual(runtime[key]['time_limit'], '120')

    def test_stage_multi_curve(self):
        runtime = read_kv((DATA / 'levels.kv').read_text(encoding='utf-8'))['levels']
        source = json.loads((DATA / 'levels_v07.json').read_text(encoding='utf-8'))
        for key, stage in runtime.items():
            expected = round(1 + .05 * (int(key[2:]) - 1), 2)
            self.assertAlmostEqual(float(stage['multi']), expected)
            self.assertAlmostEqual(source[key]['multi'], expected)

    def test_kv_roundtrip(self):
        parsed = read_kv((DATA / 'levels.kv').read_text(encoding='utf-8'))
        self.assertEqual(read_kv(render_kv(parsed)), parsed)


if __name__ == '__main__':
    unittest.main(verbosity=2)
