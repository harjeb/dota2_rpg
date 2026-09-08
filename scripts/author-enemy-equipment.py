"""Explicit enemy hero builds, keyed by progression tier and inventory size.

Tiers: chapters 5-9, 10-14, 15-19, 20-24, 25-29, 30.
Each row is authored for its hero, never selected by enemy position. Item counts
stay unchanged. Early builds use boots/stats, then role cores, then protection
and luxury upgrades. Strength carries (Huskar/Sven) are not aura supports;
Sand King is a spell initiator, Lina a spell core, Dazzle a support.

Run from the repository root to update only hero item blocks in both data files.
"""
import json
from pathlib import Path
import re

# Six complete builds per hero; names below are native IDs without item_.
BUILDS = {
    'axe': [
        'boots bracer', 'phase_boots bracer magic_wand',
        'phase_boots blink vanguard', 'blink blade_mail black_king_bar',
        'blink crimson_guard heart phase_boots',
        'blink crimson_guard heart black_king_bar shivas_guard'],
    'dragon_knight': [
        'boots bracer', 'power_treads bracer magic_wand',
        'power_treads blink armlet', 'blink armlet black_king_bar',
        'blink assault black_king_bar power_treads',
        'blink assault black_king_bar satanic greater_crit'],
    'huskar': [
        'boots bracer', 'power_treads bracer magic_wand',
        'power_treads armlet halberd', 'armlet halberd black_king_bar',
        'armlet halberd black_king_bar satanic',
        'armlet halberd black_king_bar satanic assault'],
    'sand_king': [
        'boots bracer', 'arcane_boots bracer magic_wand',
        'arcane_boots blink veil_of_discord', 'blink shivas_guard black_king_bar',
        'blink shivas_guard black_king_bar ultimate_scepter',
        'blink shivas_guard black_king_bar ultimate_scepter octarine_core'],
    'drow_ranger': [
        'boots wraith_band', 'power_treads wraith_band magic_wand',
        'power_treads dragon_lance yasha', 'hurricane_pike yasha black_king_bar',
        'hurricane_pike manta butterfly black_king_bar',
        'hurricane_pike manta butterfly black_king_bar satanic'],
    'sniper': [
        'boots wraith_band', 'power_treads wraith_band magic_wand',
        'power_treads dragon_lance maelstrom', 'hurricane_pike maelstrom black_king_bar',
        'hurricane_pike mjollnir greater_crit black_king_bar',
        'hurricane_pike mjollnir greater_crit black_king_bar satanic'],
    'clinkz': [
        'boots wraith_band', 'power_treads wraith_band magic_wand',
        'power_treads dragon_lance phylactery', 'desolator dragon_lance black_king_bar',
        'desolator hurricane_pike greater_crit black_king_bar',
        'desolator hurricane_pike greater_crit black_king_bar bloodthorn'],
    'phantom_assassin': [
        'boots wraith_band', 'power_treads wraith_band magic_wand',
        'power_treads desolator orb_of_corrosion', 'desolator basher black_king_bar',
        'desolator abyssal_blade black_king_bar satanic',
        'desolator abyssal_blade black_king_bar satanic butterfly'],
    'riki': [
        'boots wraith_band', 'power_treads wraith_band magic_wand',
        'power_treads diffusal_blade orb_of_corrosion', 'diffusal_blade manta black_king_bar',
        'diffusal_blade manta abyssal_blade black_king_bar',
        'diffusal_blade manta abyssal_blade black_king_bar butterfly'],
    'juggernaut': [
        'boots wraith_band', 'phase_boots wraith_band magic_wand',
        'phase_boots maelstrom yasha', 'maelstrom manta basher',
        'mjollnir manta abyssal_blade butterfly',
        'mjollnir manta abyssal_blade butterfly satanic'],
    'sven': [
        'boots bracer', 'power_treads bracer magic_wand',
        'power_treads echo_sabre blink', 'echo_sabre blink black_king_bar',
        'blink greater_crit black_king_bar satanic',
        'blink greater_crit black_king_bar satanic assault'],
    'lina': [
        'boots null_talisman', 'arcane_boots null_talisman magic_wand',
        'arcane_boots force_staff kaya', 'kaya_and_sange blink black_king_bar',
        'kaya_and_sange ultimate_scepter black_king_bar sheepstick',
        'kaya_and_sange ultimate_scepter black_king_bar sheepstick octarine_core'],
    'crystal_maiden': [
        'boots magic_wand', 'boots force_staff magic_wand',
        'arcane_boots force_staff glimmer_cape', 'glimmer_cape force_staff black_king_bar',
        'glimmer_cape blink black_king_bar ultimate_scepter',
        'glimmer_cape blink black_king_bar ultimate_scepter sheepstick'],
    'witch_doctor': [
        'boots magic_wand', 'boots force_staff magic_wand',
        'arcane_boots force_staff glimmer_cape', 'glimmer_cape ultimate_scepter black_king_bar',
        'glimmer_cape ultimate_scepter black_king_bar octarine_core',
        'glimmer_cape ultimate_scepter black_king_bar octarine_core sheepstick'],
    'oracle': [
        'boots magic_wand', 'arcane_boots magic_wand wind_lace',
        'arcane_boots force_staff glimmer_cape', 'glimmer_cape force_staff lotus_orb',
        'glimmer_cape lotus_orb guardian_greaves aeon_disk',
        'glimmer_cape lotus_orb guardian_greaves aeon_disk sheepstick'],
    'dazzle': [
        'boots magic_wand', 'boots force_staff magic_wand',
        'arcane_boots force_staff glimmer_cape', 'guardian_greaves force_staff glimmer_cape',
        'guardian_greaves lotus_orb glimmer_cape sheepstick',
        'guardian_greaves lotus_orb glimmer_cape sheepstick octarine_core'],
}

# These stages intentionally give the third enemy only two slots. Authored
# alternatives retain a carry core instead of truncating a three-item build.
TWO_SLOT_BUILDS = {
    (2, 'sven'): 'power_treads echo_sabre',
    (2, 'phantom_assassin'): 'power_treads orb_of_corrosion',
    (2, 'riki'): 'power_treads orb_of_corrosion',
    (3, 'sven'): 'echo_sabre black_king_bar',
    (3, 'riki'): 'diffusal_blade black_king_bar',
    (3, 'juggernaut'): 'phase_boots manta',
}


def loadout(hero, chapter, count):
    tier = min(chapter // 5, 6)
    if not 1 <= tier <= 6:
        raise ValueError(f'No hero equipment tier for chapter {chapter}')
    names = (TWO_SLOT_BUILDS[(tier, hero)] if count == 2 and tier > 1
             else BUILDS[hero][tier - 1]).split()
    if len(names) != count:
        raise ValueError(f'Unauthored inventory: {hero}, tier {tier}, count {count}')
    return ['item_' + name for name in names]


def main():
    data = Path(__file__).resolve().parents[1] / 'game/dota_addons/dota2_rpg/scripts/data'
    source_path, runtime_path = data / 'levels_v07.json', data / 'levels.kv'
    source_text = source_path.read_text(encoding='utf-8')
    runtime_text = runtime_path.read_text(encoding='utf-8')
    source = json.loads(source_text)
    builds = []
    for stage_id, stage in source.items():
        for entry in stage['enemies']:
            if entry['unit'].startswith('npc_dota_hero_'):
                hero = entry['unit'].removeprefix('npc_dota_hero_')
                builds.append((entry['unit'], loadout(hero, int(stage_id[2:]), len(entry['items']))))
    # Only substitute item arrays/blocks; runtime rewards and other fields are
    # independently authored and must not be regenerated from this source.
    source_pattern = r'("unit": "(npc_dota_hero_[^"]+)"[^{}]*?"items": \[)([^\]]*)(\])'
    runtime_pattern = r'("unit"\s+"(npc_dota_hero_[^"]+)"[^{}]*?"items"\s*\{)([^{}]*)(\})'
    for path, text, pattern, is_json in [
        (source_path, source_text, source_pattern, True),
        (runtime_path, runtime_text, runtime_pattern, False),
    ]:
        remaining = iter(builds)
        def replace(match):
            unit, items = next(remaining)
            if unit != match[2]:
                raise ValueError(f'Hero ordering mismatch: {unit}, {match[2]}')
            old = match[3]
            old_items = re.findall(r'"item_[^"]+"', old)
            if len(old_items) != len(items):
                raise ValueError(f'Inventory count mismatch for {unit}')
            item_iter = iter(items)
            new = re.sub(r'"item_[^"]+"', lambda _: json.dumps(next(item_iter)), old)
            return match[1] + new + match[4]
        updated, count = re.subn(pattern, replace, text, flags=re.S)
        if count != len(builds):
            raise ValueError(f'{path}: expected {len(builds)} blocks, got {count}')
        path.write_text(updated, encoding='utf-8', newline='\n')
    print(f'Authored {len(builds)} hero entries across {len(BUILDS)} heroes; preserved item counts.')


if __name__ == '__main__':
    main()
