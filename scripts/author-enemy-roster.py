"""Author 64 enemy heroes into the existing 30-stage campaign.

Each role cycles through its whole pool before repeating. With the current
107 hero slots this gives every hero 1-2 appearances, no duplicates within a
stage, and no overlap between consecutive hero stages (including across creep
stages). The roster is deterministic, so reloading a stage keeps its opponents.

Only hero unit IDs, attack profiles and equipment change in levels_v07.json and
levels.kv. Both files have independently authored balance/reward fields. Never
regenerate the runtime KV from the historical JSON wholesale.
"""
from collections import Counter
import json
from pathlib import Path
import re
import runpy

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
POOLS = {
    'front': '''axe dragon_knight huskar sand_king centaur tidehunter
        bristleback slardar skeleton_king life_stealer chaos_knight night_stalker
        spirit_breaker abaddon omniknight undying'''.split(),
    'damage': '''drow_ranger sniper clinkz phantom_assassin riki juggernaut sven
        lina razor viper luna gyrocopter bloodseeker slark troll_warlord ursa
        antimage phantom_lancer templar_assassin nevermore death_prophet
        necrolyte queenofpain leshrac zuus pugna'''.split(),
    'support': '''crystal_maiden witch_doctor oracle dazzle lich lion
        shadow_shaman warlock jakiro disruptor vengefulspirit venomancer
        skywrath_mage ancient_apparition grimstroke shadow_demon bane silencer
        treant enchantress ogre_magi dark_willow'''.split(),
}
PROFILES = {'front': 'aggro_front', 'damage': 'focus_lowest_hp',
            'support': 'ai_healer_protect'}
FORMATIONS = {
    3: ['front', 'damage', 'support'],
    4: ['front', 'damage', 'damage', 'support'],
    5: ['front', 'damage', 'damage', 'damage', 'support'],
    6: ['front', 'damage', 'damage', 'damage', 'support', 'support'],
    7: ['front', 'damage', 'damage', 'damage', 'support', 'front', 'support'],
}


def roster(source):
    cursors = Counter()
    result = {}
    for stage_id in sorted(source):
        entries = source[stage_id]['enemies']
        heroes = [entry for entry in entries if entry['unit'].startswith('npc_dota_hero_')]
        if not heroes:
            continue
        if len(heroes) != len(entries):
            raise ValueError(f'Unauthored mixed stage: {stage_id}')
        team = []
        # Keep the original role cursors so removing Boss escorts does not
        # reshuffle ordinary chapters when this maintenance tool is rerun.
        boss_stage = any('boss' in entry.get('tags', []) for entry in heroes)
        slots = {10: 4, 20: 6, 30: 7}.get(int(stage_id[2:]), len(heroes)) if boss_stage else len(heroes)
        for role in FORMATIONS[slots]:
            pool = POOLS[role]
            hero = pool[cursors[role] % len(pool)]
            cursors[role] += 1
            team.append((hero, PROFILES[role]))
        result[stage_id] = team[:1] if boss_stage else team
    return result


def update_text(text, changes, is_json):
    separator = r'\s*:\s*' if is_json else r'\s+'
    pattern = (r'("unit"' + separator + r'")(npc_dota_hero_[^"]+)'
               r'(".*?"ai"' + separator + r'")([^"]+)(")')
    remaining = iter(changes)

    def replace(match):
        old_unit, new_unit, profile, items = next(remaining)
        if match[2] != old_unit:
            raise ValueError(f'Hero ordering mismatch: {match[2]}, expected {old_unit}')
        middle = match[3]
        if len(re.findall(r'"item_[^"]+"', middle)) != len(items):
            raise ValueError(f'Inventory count mismatch for {old_unit}')
        item_iter = iter(items)
        middle = re.sub(r'"item_[^"]+"', lambda _: json.dumps(next(item_iter)), middle)
        return match[1] + new_unit + middle + profile + match[5]

    updated, count = re.subn(pattern, replace, text, flags=re.S)
    if count != len(changes):
        raise ValueError(f'Expected {len(changes)} hero blocks, got {count}')
    return updated


def main():
    source_path, runtime_path = DATA / 'levels_v07.json', DATA / 'levels.kv'
    source_text = source_path.read_text(encoding='utf-8')
    source = json.loads(source_text)
    loadout = runpy.run_path(str(ROOT / 'scripts/author-enemy-equipment.py'))['loadout']
    changes = []
    teams = roster(source)
    for stage_id, team in teams.items():
        for original, (hero, profile) in zip(source[stage_id]['enemies'], team):
            items = loadout(hero, int(stage_id[2:]), len(original['items']))
            changes.append((original['unit'], 'npc_dota_hero_' + hero, profile, items))
    # Validate both complete transformations before writing either file.
    updated_source = update_text(source_text, changes, True)
    updated_runtime = update_text(runtime_path.read_text(encoding='utf-8'), changes, False)
    source_path.write_text(updated_source, encoding='utf-8', newline='\n')
    runtime_path.write_text(updated_runtime, encoding='utf-8', newline='\n')
    counts = Counter(change[1] for change in changes)
    print(f'Authored {len(counts)} heroes in {len(teams)} stages / {len(changes)} slots; '
          f'max appearances {max(counts.values())}.')


if __name__ == '__main__':
    main()
