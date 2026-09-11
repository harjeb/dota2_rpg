"""Author stronger enemy gear from reviewed, attributable player-build profiles.

The OpenDota snapshot provides hero purchase frequencies and observed match-end
inventories. Profiles choose compatible combat cores; the level curve deliberately
adds RPG difficulty. It is not a claim of population-average gold at each level.
Runtime levels.kv is authoritative; no network is used when generating equipment.
"""
import json
from pathlib import Path
import re
import runpy

ROOT = Path(__file__).resolve().parents[1]
PROFILE_DATA = json.loads((ROOT / 'data/enemy_equipment_profiles.json').read_text(encoding='utf-8'))
BUILDS = PROFILE_DATA['heroes']
ROLES = {hero: row['role'] for hero, row in BUILDS.items()}
RESEARCH = json.loads((ROOT / 'data' / PROFILE_DATA['research_snapshot']).read_text(encoding='utf-8'))
ITEM_COSTS = RESEARCH['item_costs']
BOOT_ITEMS = {'boots', 'phase_boots', 'power_treads', 'arcane_boots', 'guardian_greaves', 'boots_of_bearing'}
UPGRADES = {
    'basher': 'abyssal_blade', 'dragon_lance': 'hurricane_pike',
    'yasha': 'manta', 'maelstrom': 'mjollnir', 'diffusal_blade': 'disperser',
    'mekansm': 'guardian_greaves', 'invis_sword': 'silver_edge',
    'echo_sabre': 'harpoon', 'orchid': 'bloodthorn', 'cyclone': 'wind_waker',
    'rod_of_atos': 'gungir',
}


def loadout(hero, level, boss=False):
    """Earlier completed cores, six slots from level 22, luxury upgrades at 26."""
    numeric = float(level)
    if not numeric.is_integer() or not 1 <= numeric <= 30:
        raise ValueError(f'Enemy level must be an integer in 1..30: {level}')
    level = int(numeric)
    if boss and hero in PROFILE_DATA.get('boss_loadouts', {}):
        return ['item_' + item for item in PROFILE_DATA['boss_loadouts'][hero]]
    profile = BUILDS[hero]
    role = profile['role']
    stat = {'strength': 'bracer', 'agility': 'wraith_band',
            'caster': 'null_talisman', 'support': 'magic_wand'}[role]
    boots = profile['boots']
    if level <= 3:
        names = [stat]
    elif level <= 6:
        names = [boots, stat, 'wind_lace' if role == 'support' else 'magic_wand']
    elif level <= 9:
        names = [boots, profile['core'][0], 'magic_wand']
    elif level <= 13:
        names = [boots, *profile['core'][:2], 'magic_wand']
    elif level <= 17:
        names = [boots, *profile['core'][:3]]
    elif level <= 21:
        names = [boots, *profile['core'][:4]]
    elif level <= 25:
        names = [boots, *profile['mid']]
    else:
        names = list(profile['late'])
    if 'guardian_greaves' in names:
        names = [item for item in names if item not in BOOT_ITEMS or item == 'guardian_greaves']
    result = list(dict.fromkeys(names))
    if level >= 22:
        for item in profile['late']:
            if len(result) >= 6:
                break
            if item not in result and item not in BOOT_ITEMS:
                result.append(item)
    if len(result) > 6 or any(item not in ITEM_COSTS for item in result):
        raise ValueError(f'Invalid inventory: {hero} level {level}: {result}')
    return ['item_' + item for item in result]


def update_equipment(source_text, runtime_text):
    """Validate both files before touching disk; preserve all non-equipment KV."""
    read_kv = runpy.run_path(str(Path(__file__).with_name('export-level-configuration.py')))['read_kv']
    runtime = read_kv(runtime_text)['levels']
    source = json.loads(source_text)
    builds = []
    for stage_id, stage in source.items():
        actual = list(runtime[stage_id]['enemies'].values())
        if len(actual) != len(stage['enemies']):
            raise ValueError(f'Roster count mismatch in {stage_id}')
        for entry, live in zip(stage['enemies'], actual):
            if entry['unit'] != live['unit']:
                raise ValueError(f'Roster ordering mismatch in {stage_id}')
            if entry['unit'].startswith('npc_dota_hero_'):
                hero = entry['unit'].removeprefix('npc_dota_hero_')
                tags = live.get('tags', {})
                boss = 'boss' in (tags.values() if isinstance(tags, dict) else tags)
                builds.append((entry['unit'], int(live['level']), loadout(hero, live['level'], boss)))
    patterns = [
        r'("unit": "(npc_dota_hero_[^"]+)"[^{}]*?"items": \[)([^\]]*)(\])',
        r'("unit"\s+"(npc_dota_hero_[^"]+)"[^{}]*?"items"\s*\{)([^{}]*)(\})',
    ]
    outputs = []
    for text, pattern, is_json in zip((source_text, runtime_text), patterns, (True, False)):
        remaining = iter(builds)
        def replace(match):
            unit, level, items = next(remaining)
            if unit != match[2]:
                raise ValueError(f'Hero ordering mismatch: {unit}, {match[2]}')
            prefix = match[1]
            if is_json:
                prefix = re.sub(r'("level": )\d+', lambda m: m[1] + str(level), prefix)
                body = '\n' + ',\n'.join('          ' + json.dumps(item) for item in items) + '\n        '
            else:
                indent = re.search(r'\n([ \t]*)"1"', match[3]).group(1)
                closing_indent = match[3].rsplit('\n', 1)[-1]
                body = '\n' + '\n'.join(f'{indent}"{i}" "{item}"' for i, item in enumerate(items, 1)) + '\n' + closing_indent
            return prefix + body + match[4]
        updated, count = re.subn(pattern, replace, text, flags=re.S)
        if count != len(builds):
            raise ValueError(f'Expected {len(builds)} hero blocks, got {count}')
        outputs.append(updated)
    return outputs


def main():
    data = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
    paths = [data / 'levels_v07.json', data / 'levels.kv']
    outputs = update_equipment(*(path.read_text(encoding='utf-8') for path in paths))
    for path, text in zip(paths, outputs):
        path.write_text(text, encoding='utf-8', newline='\n')
    print('Authored player-data-informed enemy equipment; synchronized hero levels from runtime KV.')


if __name__ == '__main__':
    main()
