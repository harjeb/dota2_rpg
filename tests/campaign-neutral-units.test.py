"""Portable coverage and native-field regression checks for campaign creatures."""
import json
from pathlib import Path
import runpy
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = runpy.run_path(str(ROOT / 'scripts/build-campaign-neutral-units.py'))
SNAPSHOT = json.loads(TOOL['SNAPSHOT'].read_text(encoding='utf-8'))
UNITS = TOOL['parse_kv'](TOOL['OUTPUT'].read_text(encoding='utf-8'))['DOTAUnits']


class CampaignNeutralTests(unittest.TestCase):
    def test_every_campaign_and_summon_unit_has_creature_definition(self):
        names = set(TOOL['campaign_names']())
        self.assertEqual(len(names), 22)
        for summons in SNAPSHOT['summons'].values():
            names.update(summons)
        self.assertEqual(set(SNAPSHOT['units']), names)
        self.assertEqual(set(UNITS), names | {'npc_rpg_skill_test_target'})
        for name in names:
            self.assertEqual(UNITS[name]['BaseClass'], 'npc_dota_creature', name)

    def test_all_native_fields_preserved_except_camp_identity(self):
        for name, native in SNAPSHOT['units'].items():
            expected = dict(native)
            expected['BaseClass'] = 'npc_dota_creature'
            expected.pop('TeamName', None)
            expected.pop('IsNeutralUnitType', None)
            self.assertEqual(UNITS[name], expected, name)

    def test_ability_slots_passives_and_unresolved_contracts_are_explicit(self):
        abilities = SNAPSHOT['abilities']
        self.assertEqual(abilities['neutral_upgrade']['AbilityBehavior'], 'DOTA_ABILITY_BEHAVIOR_PASSIVE')
        self.assertEqual(SNAPSHOT['unresolved_abilities'], [])
        self.assertEqual(abilities['dark_troll_warlord_raise_dead']['AbilityBehavior'],
                         'DOTA_ABILITY_BEHAVIOR_NO_TARGET')
        self.assertEqual(abilities['dark_troll_warlord_raise_dead']['AbilityValues']['skeletons_created'], '3')
        for name, unit in SNAPSHOT['units'].items():
            for field, ability in unit.items():
                if field.startswith('Ability') and ability:
                    self.assertIn(ability, abilities, (name, ability))
                    if ability not in SNAPSHOT['unresolved_abilities']:
                        self.assertIn('AbilityBehavior', abilities[ability], ability)
        troll = UNITS['npc_dota_neutral_dark_troll_warlord']
        self.assertEqual(troll['Ability1'], '')
        self.assertEqual(troll['Ability2'], 'dark_troll_warlord_raise_dead')
        skeleton = UNITS['npc_dota_dark_troll_warlord_skeleton_warrior']
        self.assertEqual(skeleton['IsSummoned'], '1')
        self.assertEqual(skeleton['Ability1'], 'hill_troll_rally')

    def test_legacy_hellbear_alias_is_documented(self):
        self.assertEqual(SNAPSHOT['aliases'], {
            'npc_dota_neutral_hellbear_smasher': 'npc_dota_neutral_polar_furbolg_ursa_warrior'})
        self.assertEqual(UNITS['npc_dota_neutral_hellbear_smasher']['Ability1'],
                         'polar_furbolg_ursa_warrior_thunder_clap')

    def test_generator_is_current_and_portable(self):
        subprocess.run([sys.executable, str(ROOT / 'scripts/build-campaign-neutral-units.py'), '--check'],
                       cwd=ROOT, check=True)


if __name__ == '__main__':
    unittest.main()
