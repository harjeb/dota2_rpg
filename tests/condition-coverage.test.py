"""Audit baseline, reproducibility and the real preset -> JS wire -> Lua contract.
Run: python tests/condition-coverage.test.py
Node is required. Lua validation uses the optional lupa package (or is explicitly
reported skipped); it never loads Dota or starts/stops a game.
"""
import copy
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data/native_skill_conditions.json'
SPEC = importlib.util.spec_from_file_location('coverage_builder', ROOT / 'scripts/build-condition-coverage.py')
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)

NODE_CHECK = r'''
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const path = require('path');
const root = process.argv[1];
const base = path.join(root, 'content/dota_addons/dota2_rpg/panorama/scripts/custom_game');
const context = vm.createContext({ console });
['condition_catalog.js', 'panorama_rule_sync.js', 'skill_condition_presets.js'].forEach(file =>
    vm.runInContext(fs.readFileSync(path.join(base, file), 'utf8'), context, { filename: file }));
const data = JSON.parse(fs.readFileSync(path.join(root, 'data/native_skill_conditions.json'), 'utf8'));
const api = context.RpgSkillPresets;
const catalog = context.RpgConditionCatalog;
const sync = context.RpgRuleSync;
const payloads = [];
for (const row of data.rows) {
    if (!row.expression_covered) {
        assert.strictEqual(api.get(row.id), null, row.id);
        assert(api.unsupportedReason(row.id).includes('unsupported_ability'), row.id);
        continue;
    }
    assert.strictEqual(api.unsupportedReason(row.id), null, row.id);
    assert.deepStrictEqual(Array.from(api.variants(row.id)), row.preset_variants);
    assert.strictEqual(api.get(row.id, 'invalid_family'), null);
    for (const variant of api.variants(row.id)) {
        const preset = api.get(row.id, variant);
        assert.deepStrictEqual(JSON.parse(JSON.stringify(preset)), data.families[variant].rule, row.id);
        let nontrivial = preset.min_aoe_hits > 1;
        [['use_conditions', 'use', 4], ['target_filters', 'target', 4], ['target_priorities', 'priority', 2]].forEach(([key, group, max]) => {
            assert(Array.isArray(preset[key]));
            assert(preset[key].length <= max);
            for (const c of preset[key]) {
                const def = catalog.groups[group].find(d => d.id === c.type);
                assert(def, row.id + ':' + c.type + ' missing from actual UI');
                assert.notStrictEqual(c.type, 'always');
                if (group !== 'priority') nontrivial = true;
                const wire = catalog.wire(group, c);
                if (c.type.includes('_pct_')) {
                    assert(c.value >= 0 && c.value <= 100);
                    assert.strictEqual(wire.value, c.value / 100);
                }
                if (c.seconds !== undefined) assert.strictEqual(wire.value, c.seconds);
                if (c.radius !== undefined) assert.strictEqual(wire.radius, c.radius);
            }
        });
        assert(nontrivial, row.id + ' has only sorting/default behavior');
        const payload = sync.serialize({ rule: preset, actionId: row.id, actionName: row.id,
            heroIndex: 7, heroName: row.hero, slot: 32, ruleCount: 32 });
        assert.strictEqual(payload.target_team, preset.target_team, row.id + ' team changed in wire');
        assert.strictEqual(payload.rule_count, 32);
        assert.strictEqual(payload.action_id, row.id);
        if (preset.min_aoe_hits !== undefined) assert.strictEqual(payload.min_aoe_hits, preset.min_aoe_hits);
        if (preset.desired_toggle_state !== undefined) assert.strictEqual(payload.desired_toggle_state, preset.desired_toggle_state);
        for (const value of Object.values(payload)) assert(['string', 'number', 'boolean'].includes(typeof value));
        assert(!Object.keys(preset).some(key => /vector|channel|release|phase/.test(key)), row.id);
        assert(!Object.keys(payload).some(key => /vector|channel|release|phase/.test(key)), row.id);
        payloads.push({ id: row.id, variant, payload, rule: JSON.parse(JSON.stringify(preset)) });
        const original = JSON.stringify(api.get(row.id, variant));
        preset.target_team = 'corrupted';
        preset.use_conditions.push({ type: 'always' });
        if (preset.target_filters.length) preset.target_filters[0].value = -999;
        assert.strictEqual(JSON.stringify(api.get(row.id, variant)), original, 'clone isolation');
    }
}
for (const name of ['not_a_native_ability', '__proto__', 'constructor', 'toString', null, undefined]) {
    assert.strictEqual(api.get(name), null);
    assert(api.unsupportedReason(name).includes('unsupported_ability'));
}
// Actual UI units at representative semantic boundaries.
assert.strictEqual(api.get('omniknight_purification').target_filters[0].value, 80);
assert.strictEqual(api.get('antimage_blink').use_conditions[0].value, 60);
assert.strictEqual(api.get('antimage_blink').target_filters[0].value, 350);
assert.strictEqual(api.get('faceless_void_time_walk_reverse'), null);
const timeWalk = api.get('faceless_void_time_walk');
assert.strictEqual(timeWalk.target_team, 'self');
assert.strictEqual(timeWalk.target, 'self');
assert.strictEqual(timeWalk.use_conditions[0].type, 'self_hp_pct_lte');
assert.strictEqual(timeWalk.use_conditions[0].value, 60);
assert.strictEqual(timeWalk.target_filters.length, 0, 'recovery must work with enemies inside 350 units');
assert.strictEqual(api.get('faceless_void_time_walk', 'gapclose').target_filters[0].value, 350);
const recoveryWire = sync.serialize({ rule: timeWalk, actionId: 'faceless_void_time_walk',
    actionName: 'faceless_void_time_walk', heroIndex: 7, slot: 1, ruleCount: 1 });
assert.strictEqual(recoveryWire.target_team, 'self');
assert.strictEqual(recoveryWire.use_condition_1_value, 0.6);
assert.strictEqual(api.get('leshrac_pulse_nova').desired_toggle_state, '1');
assert.strictEqual(api.get('leshrac_pulse_nova', 'toggle_off').desired_toggle_state, '0');
process.stdout.write(JSON.stringify(payloads));
'''


class ConditionCoverage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(DATA.read_text(encoding='utf-8'))
        cls.rows = cls.data['rows']
        cls.by_id = {r['id']: r for r in cls.rows}

    def test_baseline_and_inventory(self):
        self.assertEqual(len(self.rows), 1095)
        self.assertEqual(len(self.by_id), 1095)
        self.assertEqual(len({r['hero'] for r in self.rows}), 127)
        self.assertEqual(sum(r['active'] for r in self.rows), 755)
        self.assertEqual(sum(not r['active'] for r in self.rows), 340)
        self.assertEqual(set(self.data['catalog_gap_definitions']), {f'G{i:02d}' for i in range(22)})
        unique_doc = BUILDER.UNIQUE_DOC.read_text(encoding='utf-8')
        for r in self.rows:
            self.assertEqual(r['native']['behavior_flags'], BUILDER.split_flags(r['native']['behavior_raw']))
            self.assertIn('definition', r['native'])
            self.assertIn('description_cn', r)
            self.assertIn('description_en', r)
            self.assertIn('gaps', r['catalog'])
            self.assertIn('## `' + r['id'] + '`', unique_doc)
            for mechanism in r['unique_mechanism']['mechanisms']:
                self.assertEqual(mechanism['status'], '未实现')
                self.assertTrue(mechanism['missing_capability'])
                self.assertTrue(mechanism['mechanism_cn'])
                self.assertTrue(mechanism['mechanism_en'])
        self.assertNotRegex(unique_doc, r'- \[ \]|- \[x\]')

    def test_generic_only_and_all_unique_excluded(self):
        allowed = {'nearby_enemies_gte', 'distance_lte', 'distance_gte',
            'hp_pct_lte', 'self_hp_pct_lte', 'self_hp_pct_gte', 'recently_damaged',
            'self_recently_damaged', 'mana_pct_lte', 'mana_pct_gte', 'is_controlled',
            'self_mana_pct_gte', 'self_mana_pct_lte', 'no_enemy_within', 'ability_charges_gte',
            'nearest', 'lowest_hp_pct', 'lowest_health'}
        for family in self.data['families'].values():
            rule = family['rule']
            self.assertFalse({'vector_origin', 'vector_direction', 'cast_preference'} & rule.keys())
            for key in ('use_conditions', 'target_filters', 'target_priorities'):
                for c in rule[key]:
                    self.assertIn(c['type'], allowed)
                    self.assertFalse({'modifier', 'action_id', 'value_text', 'unit_name'} & c.keys())
        js = BUILDER.JS.read_text(encoding='utf-8')
        self.assertNotIn('var unsupported =', js)
        self.assertNotIn('modifier_', js)
        self.assertNotIn('npc_dota_', js)
        removed = {'dead_ally_count_gte', 'self_strength_gte', 'self_agility_gte',
            'owned_summons_gte', 'owned_summons_lte', 'action_used_within',
            'action_not_used_within', 'not_illusion', 'is_creep', 'is_invulnerable',
            'not_invulnerable', 'has_tag', 'not_has_tag'}
        for kind in removed:
            self.assertNotIn('"' + kind + '"', js)
        for r in self.rows:
            excluded = r['unique_mechanism']['excluded_from_presets']
            if excluded:
                self.assertFalse(r['expression_covered'], r['id'])
                self.assertEqual(r['preset_variants'], [])
                self.assertNotIn('"' + r['id'] + '"', js)
            if 'DOTA_ABILITY_BEHAVIOR_HIDDEN' in r['native']['behavior_flags']:
                self.assertTrue(excluded, r['id'])
            if r['expression_covered']:
                self.assertTrue(r['active'])
                self.assertIsNone(r['unsupported_reason'])
                self.assertIn(r['family'], BUILDER.FAMILIES)
        for name in ('invoker_invoke', 'tinker_rearm', 'dazzle_bad_juju', 'primal_beast_uproar',
                     'tiny_tree_channel', 'kez_switch_weapons', 'meepo_megameepo',
                     'ancient_apparition_ice_blast_release', 'earth_spirit_stone_caller'):
            self.assertFalse(self.by_id[name]['expression_covered'], name)

    def test_basic_vector_and_channel_review(self):
        vector = self.by_id['muerta_dead_shot']
        self.assertEqual(vector['family'], 'offensive_vector')
        self.assertFalse(vector['unique_mechanism']['excluded_from_presets'])
        self.assertEqual(vector['unique_mechanism']['basic_native_mode'], 'vector')
        preset = self.data['families']['offensive_vector']['rule']
        self.assertEqual(set(preset), {'use_conditions', 'target_filters', 'target_priorities', 'target_team', 'target'})
        self.assertEqual(preset['target_priorities'], [{'type': 'nearest'}])
        self.assertEqual(preset['use_conditions'], [BUILDER.NEAR])
        self.assertEqual(preset['target_team'], 'enemy')
        for name in ('marci_companion_run', 'pangolier_swashbuckle', 'void_spirit_aether_remnant',
                     'brewmaster_fire_pull', 'shadow_shaman_serpentine', 'broodmother_sticky_snare',
                     'magnataur_greater_shockwave', 'naga_siren_reel_in', 'tiny_tree_channel'):
            self.assertFalse(self.by_id[name]['expression_covered'], name)
        for name in ('keeper_of_the_light_illuminate', 'bane_fiends_grip', 'elder_titan_echo_stomp'):
            row = self.by_id[name]
            self.assertTrue(row['expression_covered'], name)
            self.assertEqual(row['unique_mechanism']['basic_native_mode'], 'channel_startup')
            self.assertIn('busy', row['unique_mechanism']['basic_native_note'])
        # Reviewed names cannot override incompatible native flags or missing evidence.
        for change in ('friendly', 'missing_description', 'hidden'):
            row = copy.deepcopy(vector)
            if change == 'friendly':
                row['native']['target_team'] = 'DOTA_UNIT_TARGET_TEAM_FRIENDLY'
            elif change == 'missing_description':
                row['description_en'] = ''
            else:
                row['native']['behavior_flags'].append('DOTA_ABILITY_BEHAVIOR_HIDDEN')
            self.assertFalse(BUILDER.classify(row)['expression_covered'], change)

    def test_native_basic_contract_modules_exist(self):
        # These are implementation presence checks, not game execution validation.
        base = ROOT / 'game/dota_addons/dota2_rpg/scripts/vscripts/tactics'
        vector = (base / 'vector_target.lua').read_text(encoding='utf-8')
        adapter = (base / 'action_adapter.lua').read_text(encoding='utf-8')
        self.assertIn('function VectorTarget.Build(caster, primary)', vector)
        self.assertIn('function VectorTarget.NativeMode(source)', vector)
        self.assertIn('length <= 0', vector)
        self.assertIn('require("tactics/vector_target")', adapter)
        self.assertIn('DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION', adapter)
        self.assertIn('state("IsChanneling")', adapter)
        for text in (vector, adapter):
            self.assertNotIn('muerta_dead_shot', text)
            self.assertNotIn('marci_companion_run', text)

    def test_counts_and_reproducibility(self):
        count = sum(r['expression_covered'] for r in self.rows)
        self.assertEqual(count, self.data['coverage']['expression_covered'])
        self.assertEqual(round(count / 755 * 100, 2), self.data['coverage']['expression_percent'])
        self.assertEqual(self.data['coverage']['native_execution_validated'], 0)
        self.assertIn(f'{count}/755', BUILDER.DOC.read_text(encoding='utf-8'))
        outputs = BUILDER.artifacts(copy.deepcopy(self.rows), self.data['native_snapshot']['source_sha256'])
        for path, content in outputs.items():
            self.assertEqual(path.read_text(encoding='utf-8'), content, str(path))

    def test_localization_keys_are_case_insensitive(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            raw = {'heroes': {'hero': {'DOTAAbilities': {'sample': {'BaseClass': 'base_sample'}}}},
                   'loc': {'RESOURCE/LOCALIZATION/ABILITIES_ENGLISH.TXT': {
                       'dota_tooltip_ability_SAMPLE': 'Sample',
                       'DOTA_TOOLTIP_ABILITY_SAMPLE_DESCRIPTION': 'Correct description',
                       'Dota_Tooltip_Ability_Base_Sample_Description': 'Base evidence'},
                       'resource/localization/abilities_schinese.txt': {
                       'dota_tooltip_ability_sample_description': '中文描述'}}}
            (directory / 'rpg_hero_catalog_data.json').write_text(json.dumps(raw), encoding='utf-8')
            (directory / 'rpg_catalog_rows.json').write_text(json.dumps([{'id': 'sample', 'hero': 'hero', 'name': 'Sample'}]), encoding='utf-8')
            rows, hashes = BUILDER.import_rows(directory)
            self.assertEqual(rows[0]['description_en'], 'Correct description')
            self.assertEqual(rows[0]['description_cn'], '中文描述')
            self.assertEqual(rows[0]['base_description_en'], 'Base evidence')
            self.assertEqual(rows[0]['native']['definition'], {'BaseClass': 'base_sample'})
            self.assertEqual(len(hashes), 2)
        for name in ('muerta_dead_shot', 'broodmother_sticky_snare', 'muerta_gunslinger', 'chen_zealot', 'meepo_fling'):
            self.assertTrue(self.by_id[name]['description_en'], name)
        self.assertEqual(self.by_id['meepo_fling']['unsupported_reason'], 'unique_mechanism')

    def test_frontend_and_backend_serialization(self):
        result = subprocess.run(['node', '-e', NODE_CHECK, str(ROOT)], cwd=ROOT,
                                capture_output=True, text=True, encoding='utf-8', check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        records = json.loads(result.stdout)
        self.assertEqual(len(records), sum(len(r['preset_variants']) for r in self.rows))
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Frontend passed; Lua decode/validation requires optional lupa')
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().coverage_script_root = str(ROOT / 'game/dota_addons/dota2_rpg/scripts/vscripts').replace('\\', '/')
        lua.execute("package.path = coverage_script_root .. '/?.lua;' .. package.path")
        validate = lua.eval('''function(flat)
            local Service = require('tactics/rule_service')
            local service = Service.new({ get_phase = function() return 'PREPARE' end,
                is_roster_hero = function() return true end,
                is_action_allowed = function() return true end, state = {rules={}} })
            local decoded = service:DecodeFlat(flat)
            local ok, reason = service:ValidateRule(0, {}, decoded)
            return ok, reason, decoded
        end''')
        for record in records:
            ok, reason, decoded = validate(lua.table_from(record['payload']))
            self.assertTrue(ok, f"{record['id']}/{record['variant']}: {reason}")
            preset = record['rule']
            self.assertEqual(decoded['target']['team'], preset['target_team'])
            for key in ['use_conditions', 'target_filters', 'target_priorities']:
                self.assertEqual(len(decoded[key]), len(preset[key]), record['id'])
                for i, expected in enumerate(preset[key], 1):
                    actual = decoded[key][i]
                    self.assertEqual(actual['type'], expected['type'])
                    if '_pct_' in expected['type']:
                        self.assertAlmostEqual(actual['value'], expected['value'] / 100)
                    for field in ['radius', 'seconds', 'action_id']:
                        if field in expected:
                            self.assertEqual(actual[field], expected[field])
            if 'desired_toggle_state' in preset:
                self.assertEqual(decoded['action']['desired_toggle_state'], preset['desired_toggle_state'] == '1')


if __name__ == '__main__':
    unittest.main(verbosity=2)
