"""Value upgrades must use native recipe results, never raw stat components."""
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
data=json.loads((root/'game/dota_addons/dota2_rpg/scripts/data/campaign_loot_catalog.json').read_text(encoding='utf-8'))
expected={r['schema']['ItemResult'] for r in data['items'] if r.get('schema',{}).get('ItemResult','').startswith('item_')}
actual=set(re.findall(r'\["(item_[^"]+)"\] = true',(root/'game/dota_addons/dota2_rpg/scripts/vscripts/data/assembled_loot_items.lua').read_text(encoding='utf-8')))
assert actual==expected,(actual-expected,expected-actual)
assert 'item_dragon_lance' in actual and 'item_sange' in actual
assert 'item_ogre_axe' not in actual and 'item_hyperstone' not in actual
print('PASS native recipe-result allowlist for assembled loot upgrades')
