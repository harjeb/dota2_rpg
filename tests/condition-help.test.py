#!/usr/bin/env python3
"""Audit help coverage, examples, translations and generated-file freshness."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('help_builder', ROOT / 'scripts/build-condition-help.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class HelpDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = builder.build()
        cls.source = json.loads(builder.SOURCE.read_text(encoding='utf-8'))
        cls.rows = {row['id']: row for row in cls.source['rows']}

    def localized(self, value):
        self.assertEqual(set(value), {'zh', 'en'})
        for lang in ('zh', 'en'):
            self.assertIsInstance(value[lang], str)
            self.assertTrue(value[lang].strip())

    def test_denominator_and_no_double_counting(self):
        s = self.data['summary']
        active = {r['id'] for r in self.rows.values() if r['active']}
        reviewed = {r['id'] for r in self.rows.values() if r['active'] and r['expression_covered']}
        ids = [a for c in self.data['categories'] for a in c['covered_ability_ids']]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), reviewed)
        self.assertEqual(s['active_denominator'], len(active))
        self.assertEqual(s['passive_excluded'], len(self.rows) - len(active))
        self.assertEqual(s['reviewed_id_covered'], len(ids))
        self.assertEqual(s['reviewed_id_percent'], round(len(ids)*100/len(active), 2))
        self.assertEqual(s['preset_covered'], len(reviewed))
        self.assertEqual(s['preset_percent'], round(len(reviewed)*100/len(active), 2))
        types = self.data['type_coverage']
        self.assertEqual({t['id'] for t in types}, {'G%02d' % i for i in range(22)})
        self.assertEqual([t['id'] for t in types if t['status']=='excluded_passive'], ['G14'])
        self.assertEqual(s['type_total'], 21)
        self.assertEqual(s['type_covered'], sum(t['status']=='basic_tutorial' for t in types))
        self.assertEqual(s['type_percent'], round(s['type_covered']*100/s['type_total'],2))
        self.assertEqual(s['target_met'], 80 <= s['type_percent'] <= 90)
        pages = {c['id'] for c in self.data['categories']}
        for topic in types:
            self.assertTrue(set(topic['pages']) <= pages)
            self.assertEqual(bool(topic['pages']), topic['status']=='basic_tutorial')
            self.assertNotIn('special', topic['pages'], 'limitations page cannot count as a working recipe')
        self.assertEqual({t['id'] for t in types if t['status']=='deferred'}, {'G18','G19','G20','G21'})
        self.assertEqual(s['native_execution_validated'], self.source['coverage']['native_execution_validated'])
        uncovered = {r['ability'] for r in self.data['uncovered']}
        self.assertEqual(uncovered, active-set(ids))
        self.assertEqual(s['source_sha256'], hashlib.sha256(builder.SOURCE.read_bytes()).hexdigest())

    def test_purposes_and_bilingual_contract(self):
        categories = self.data['categories']
        self.assertEqual(len({c['id'] for c in categories}), len(categories))
        self.assertTrue({'single_target','point','area','no_target','healing','protection','ally_buff',
                         'self_buff','movement','summon','channel','toggle','charges','persistent_movement',
                         'combo','special'}.issubset({c['id'] for c in categories}))
        for basic in self.data['basics']:
            self.localized(basic['title']); self.localized(basic['description'])
        for key in ('title','description','denominator_note','validation_note'):
            self.localized(self.data['summary'][key])
        for c in categories:
            for key in ('title','description','preset_status'):
                self.localized(c[key])
            self.assertTrue(c['steps']); self.assertTrue(c['settings']); self.assertTrue(c['notes'])
            for t in c['steps']+c['notes']:
                self.localized(t)
            for setting in c['settings']:
                self.localized(setting['label']); self.localized(setting['value'])
            for e in c['examples']:
                if e['ability'].startswith('item_'):
                    self.assertEqual(c['id'], 'combo')
                    self.assertIn(e['ability'], {'item_blink', 'item_blade_mail'})
                    self.assertEqual(e['hero'], 'npc_dota_hero_axe')
                    self.localized(e['label'])
                    continue
                row = self.rows[e['ability']]
                self.assertEqual(e['hero'], row['hero'])
                self.assertEqual(e['label'], {'zh':row['name'],'en':row['name_en']})
                self.assertEqual(e['has_preset'], row['expression_covered'])
                self.localized(e['label'])
            if c['coverage_role'] == 'primary':
                expected = {r['id'] for r in self.rows.values() if r['active'] and r['expression_covered'] and r['family'] in c['source_families']}
                self.assertEqual(set(c['covered_ability_ids']), expected)
                self.assertEqual(c['preset_count'], len(expected))
                self.assertEqual(c['has_preset'], bool(expected))
                self.assertTrue({e['ability'] for e in c['examples']} <= expected)
            else:
                self.assertEqual(c['covered_ability_ids'], [])
                self.assertFalse(c['has_preset'])
                self.assertEqual(c['preset_count'], 0)

    def test_generated_bytes_and_panorama_global(self):
        subprocess.run([sys.executable, str(ROOT/'scripts/build-condition-help.py'), '--check'], check=True)
        js = builder.JS.read_text(encoding='utf-8')
        payload = js.split('var RpgConditionHelpData = ', 1)[1].removesuffix(';\n')
        self.assertEqual(json.loads(payload), self.data)


if __name__ == '__main__':
    unittest.main()
