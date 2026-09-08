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

# Shared openings reduce repetition; midgame cores and late upgrades are
# chosen for each hero. Tuple: role, boots, core, utility, protection, luxury.
ROLE_OPENINGS = {
    'strength': ('boots bracer', 'power_treads bracer magic_wand'),
    'agility': ('boots wraith_band', 'power_treads wraith_band magic_wand'),
    'caster': ('boots null_talisman', 'arcane_boots null_talisman magic_wand'),
    'support': ('boots magic_wand', 'arcane_boots magic_wand wind_lace'),
}
HERO_PROFILES = {
    'centaur': 'strength phase_boots blink blade_mail pipe heart',
    'tidehunter': 'strength arcane_boots blink pipe guardian_greaves refresher',
    'bristleback': 'strength phase_boots bloodstone eternal_shroud shivas_guard ultimate_scepter',
    'slardar': 'strength power_treads blink echo_sabre black_king_bar assault',
    'skeleton_king': 'strength phase_boots armlet desolator black_king_bar assault',
    'life_stealer': 'strength phase_boots armlet basher sange_and_yasha assault',
    'chaos_knight': 'strength power_treads armlet manta black_king_bar heart',
    'night_stalker': 'strength phase_boots echo_sabre blink black_king_bar assault',
    'spirit_breaker': 'strength phase_boots invis_sword ultimate_scepter black_king_bar octarine_core',
    'abaddon': 'strength phase_boots echo_sabre manta basher assault',
    'omniknight': 'support arcane_boots mekansm lotus_orb pipe ultimate_scepter',
    'undying': 'support arcane_boots mekansm glimmer_cape pipe lotus_orb',
    'razor': 'agility power_treads yasha maelstrom black_king_bar satanic',
    'viper': 'agility power_treads dragon_lance yasha black_king_bar skadi',
    'luna': 'agility power_treads yasha mask_of_madness black_king_bar satanic',
    'gyrocopter': 'agility power_treads maelstrom ultimate_scepter black_king_bar satanic',
    'bloodseeker': 'agility power_treads maelstrom basher black_king_bar butterfly',
    'slark': 'agility power_treads diffusal_blade ultimate_scepter black_king_bar skadi',
    'troll_warlord': 'agility power_treads bfury yasha black_king_bar satanic',
    'ursa': 'agility phase_boots bfury blink black_king_bar basher',
    'antimage': 'agility power_treads bfury yasha basher skadi',
    'phantom_lancer': 'agility power_treads diffusal_blade yasha heart butterfly',
    'templar_assassin': 'agility power_treads desolator blink black_king_bar greater_crit',
    'nevermore': 'agility power_treads dragon_lance greater_crit black_king_bar satanic',
    'lich': 'support arcane_boots glimmer_cape force_staff aeon_disk ultimate_scepter',
    'lion': 'support arcane_boots blink force_staff aeon_disk ultimate_scepter',
    'shadow_shaman': 'support arcane_boots blink aether_lens black_king_bar ultimate_scepter',
    'warlock': 'support arcane_boots glimmer_cape ultimate_scepter aeon_disk refresher',
    'jakiro': 'support arcane_boots force_staff glimmer_cape cyclone ultimate_scepter',
    'disruptor': 'support arcane_boots glimmer_cape force_staff aeon_disk ultimate_scepter',
    'death_prophet': 'caster arcane_boots cyclone kaya_and_sange black_king_bar shivas_guard',
    'necrolyte': 'caster arcane_boots kaya_and_sange eternal_shroud shivas_guard heart',
    'queenofpain': 'caster power_treads orchid kaya_and_sange black_king_bar shivas_guard',
    'leshrac': 'caster arcane_boots bloodstone kaya_and_sange black_king_bar shivas_guard',
    'zuus': 'caster arcane_boots phylactery ultimate_scepter kaya_and_sange refresher',
    'pugna': 'caster arcane_boots aether_lens glimmer_cape ultimate_scepter octarine_core',
    'vengefulspirit': 'support arcane_boots force_staff glimmer_cape lotus_orb ultimate_scepter',
    'venomancer': 'support arcane_boots spirit_vessel glimmer_cape force_staff shivas_guard',
    'skywrath_mage': 'caster arcane_boots rod_of_atos aether_lens black_king_bar ultimate_scepter',
    'ancient_apparition': 'support arcane_boots glimmer_cape force_staff aether_lens ultimate_scepter',
    'grimstroke': 'support arcane_boots aether_lens glimmer_cape ultimate_scepter sheepstick',
    'shadow_demon': 'support arcane_boots aether_lens glimmer_cape aeon_disk ultimate_scepter',
    'bane': 'support arcane_boots aether_lens glimmer_cape black_king_bar ultimate_scepter',
    'silencer': 'support arcane_boots force_staff glimmer_cape aeon_disk refresher',
    'treant': 'support arcane_boots blink meteor_hammer lotus_orb ultimate_scepter',
    'enchantress': 'support power_treads dragon_lance glimmer_cape lotus_orb ultimate_scepter',
    'ogre_magi': 'support arcane_boots force_staff aether_lens glimmer_cape sheepstick',
    'dark_willow': 'support arcane_boots cyclone glimmer_cape blink ultimate_scepter',
}
UPGRADES = {
    'basher': 'abyssal_blade', 'dragon_lance': 'hurricane_pike',
    'yasha': 'manta', 'maelstrom': 'mjollnir', 'diffusal_blade': 'disperser',
    'mekansm': 'guardian_greaves', 'invis_sword': 'silver_edge',
    'echo_sabre': 'harpoon', 'orchid': 'bloodthorn', 'cyclone': 'wind_waker',
}
for hero, profile in HERO_PROFILES.items():
    role, boots, core, utility, protection, luxury = profile.split()
    late = [UPGRADES.get(item, item) for item in (core, utility, protection, luxury)]
    final_slot = ('shivas_guard' if hero == 'tidehunter' else 'aeon_disk') \
        if 'guardian_greaves' in late else boots
    BUILDS[hero] = [
        *ROLE_OPENINGS[role],
        f'{boots} {core} {utility}',
        f'{core} {utility} {protection}',
        ' '.join(late),
        ' '.join([*late, final_slot] if 'guardian_greaves' in late else [boots, *late]),
    ]
# Razor wants status resistance; Luna upgrades her early lifesteal into damage.
BUILDS['razor'][4:] = [
    'sange_and_yasha mjollnir black_king_bar satanic',
    'power_treads sange_and_yasha mjollnir black_king_bar satanic',
]
BUILDS['luna'][4:] = [
    'manta butterfly black_king_bar satanic',
    'power_treads manta butterfly black_king_bar satanic',
]

# Every hero has an intentional boots/core pair for the two-slot stages.
# Support pairs retain their defining utility; selection never uses roster slot.
TWO_SLOT_BUILDS = {
    (tier, hero): ' '.join(rows[tier - 1].split()[:2])
    for hero, rows in BUILDS.items()
    for tier in range(2, 7)
}
TWO_SLOT_BUILDS.update({
    (3, hero): 'force_staff glimmer_cape'
    for hero in ('crystal_maiden', 'witch_doctor', 'oracle', 'dazzle')
})
TWO_SLOT_BUILDS.update({
    (3, 'sniper'): 'power_treads maelstrom',
    (3, 'clinkz'): 'power_treads phylactery',
    (3, 'lina'): 'arcane_boots kaya',
    (4, 'dazzle'): 'guardian_greaves glimmer_cape',
    (5, 'dazzle'): 'guardian_greaves glimmer_cape',
    (6, 'dazzle'): 'guardian_greaves glimmer_cape',
})
# Preserve the original authored two-slot alternatives.
TWO_SLOT_BUILDS.update({
    (2, 'sven'): 'power_treads echo_sabre',
    (2, 'phantom_assassin'): 'power_treads orb_of_corrosion',
    (2, 'riki'): 'power_treads orb_of_corrosion',
    (3, 'sven'): 'echo_sabre black_king_bar',
    (3, 'riki'): 'diffusal_blade black_king_bar',
    (3, 'juggernaut'): 'phase_boots manta',
})


BOOT_ITEMS = {'boots', 'phase_boots', 'power_treads', 'arcane_boots', 'guardian_greaves'}


def loadout(hero, chapter, count):
    if not 5 <= chapter <= 30:
        raise ValueError(f'No hero equipment tier for chapter {chapter}')
    if count not in (2, 3, 4, 5):
        raise ValueError(f'Unsupported inventory size: {count}')
    tier = min(chapter // 5, 6)
    names = (TWO_SLOT_BUILDS[(tier, hero)] if count == 2 and tier > 1
             else BUILDS[hero][tier - 1]).split()
    # Unusual inventory sizes draw additional items from the same hero's
    # progression. The standard 2/3/3/3/4/5 schedule preserves authored rows.
    for row in BUILDS[hero][tier:] + list(reversed(BUILDS[hero][:tier - 1])):
        if len(names) >= count:
            break
        for name in row.split():
            if name in BOOT_ITEMS and set(names) & BOOT_ITEMS:
                continue
            if name not in names:
                names.append(name)
    return ['item_' + name for name in names[:count]]


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
