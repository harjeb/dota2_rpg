"""Export the design table verbatim; no effect or COST inference."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = root / 'BASIC_CARDS_V1.md'
cards = []
for line in source.read_text(encoding='utf-8').splitlines():
    if not re.match(r'^\| [ECDAW]-[gcf]\d+ \|', line):
        continue
    cells = [part.strip() for part in line.strip().strip('|').split('|')]
    identity, name, axis = cells[:3]
    kind = identity[2]
    condition = cells[4] if kind == 'g' else cells[3] if kind == 'c' else '全战场 · 持续本场'
    cards.append(dict(id=identity, name=name, faction=identity[0], kind=kind,
                      axis=axis if axis not in ('', '—') else '',
                      condition=condition, effect=cells[-1].replace('**', '')))
assert len(cards) == 100 and len({c['id'] for c in cards}) == 100
for faction in 'ECDAW':
    for kind, count in [('g', 9), ('c', 7), ('f', 4)]:
        assert sum(c['faction'] == faction and c['kind'] == kind for c in cards) == count
output = '// Generated from BASIC_CARDS_V1.md by build-data.py; all tiers retained verbatim.\nwindow.CARD_DESIGN_DATA = ' + json.dumps(cards, ensure_ascii=False, indent=2) + ';\n'
Path(__file__).with_name('data.js').write_text(output, encoding='utf-8')
print('Exported 100 unique cards: 45 buffs, 35 consumables, 20 fields.')
