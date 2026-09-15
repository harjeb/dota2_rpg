"""Verify recruit aliases preserve audited native creep identity and contracts."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('recruit_generator', ROOT / 'scripts/build-neutral-recruitment.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
snapshot = json.loads(generator.SNAPSHOT.read_text(encoding='utf-8'))
generated = generator.kv.parse_kv(generator.NPC.read_text(encoding='utf-8'))['DOTAUnits']
assert len(snapshot['units']) == len(generated) == 46
assert not (set(snapshot['units']) & generator.EXCLUDED)
for name, native in snapshot['units'].items():
    alias = 'npc_rpg_recruit_' + name.removeprefix('npc_dota_neutral_')
    fields = generated[alias]
    assert fields['BaseClass'] == 'npc_dota_creep_neutral'
    assert fields['IsNeutralUnitType'] == '1'
    assert fields['TeamName'] == native['TeamName']
    for key, value in native.items():
        if key not in ('BountyGoldMin', 'BountyGoldMax', 'BountyXP'):
            assert fields[key] == value, (name, key)
    assert all(fields[k] == '0' for k in ('BountyGoldMin', 'BountyGoldMax', 'BountyXP'))
items = snapshot['items']
assert 'NOT_ANCIENTS' in items['item_helm_of_the_dominator']['AbilityUnitTargetFlags']
assert 'NOT_ANCIENTS' not in items['item_helm_of_the_overlord']['AbilityUnitTargetFlags']
assert items['item_helm_of_the_overlord']['AbilityValues']['is_overlord'] == '1'
assert all(v['AbilityValues']['count_limit'] == '1' for v in items.values())
for script in ('build-neutral-recruitment.py', 'build-campaign-neutral-units.py'):
    subprocess.run([sys.executable, str(ROOT / 'scripts' / script), '--check'], cwd=ROOT, check=True)
custom = (ROOT / 'game/dota_addons/dota2_rpg/scripts/npc/npc_units_custom.txt').read_text(encoding='utf-8')
assert '#base "npc_units_neutral_recruitment.txt"' in custom
print('Native recruitment data: 46 aliases preserve creep levels, ancients, spells, models and native item evidence.')
