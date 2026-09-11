"""Surgically author UI38 late balance, preserving independent KV/JSON balances.

Native IDs verified in scripts/npc/npc_units.txt, SHA256
cbffa0e75f7802bae9d6dccff7d06821588f38e9a51ad53d6a643d75385bb4f4.
Run with --verify-native to recheck IsAncient against the installed native VPK.
"""
import argparse
from pathlib import Path
import re
import runpy

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
# HP/attack multiply the already chapter-scaled native stats; armor is additive,
# neutral MR sets native base MR. Counts, AI, status resistance and items persist.
NEUTRALS = {
    11: (['rock_golem', 'ice_shaman', 'granite_golem', 'black_drake'], 3, 2.5, 12, 45),
    16: (['frostbitten_golem', 'ice_shaman', 'granite_golem'], 4, 3.5, 18, 50),
    21: (['frostbitten_golem', 'ice_shaman', 'granite_golem', 'small_thunder_lizard'], 5.5, 4.5, 24, 55),
    26: (['big_thunder_lizard', 'ice_shaman', 'granite_golem', 'black_dragon', 'frostbitten_golem'], 7, 6, 30, 60),
}
BOSSES = {
    20: dict(boss_max_health=20000, boss_attack_damage_pct=75, boss_bonus_armor=15,
             boss_magic_resistance_bonus_pct=20),
    30: dict(boss_max_health=32000, boss_attack_damage_pct=100, boss_bonus_armor=25,
             boss_magic_resistance_bonus_pct=30),
}


def update_text(text, is_json):
    def update_stage(match):
        chapter, block = int(match.group(1)), match.group(0)
        if chapter not in NEUTRALS and chapter not in BOSSES:
            return block
        slot = 0
        def update_entry(entry):
            nonlocal slot
            body = entry.group(0)
            if chapter in NEUTRALS:
                names, hp, attack, armor, mr = NEUTRALS[chapter]
                assert 'npc_dota_neutral_' in body
                changes = dict(unit='npc_dota_neutral_' + names[slot], hp_multiplier=hp,
                               attack_multiplier=attack, bonus_armor=armor, magic_resistance=mr)
                slot += 1
            else:
                assert '"boss"' in body
                changes = BOSSES[chapter]
            for field, value in changes.items():
                scalar = re.compile(r'(?m)^(\s*"' + field + r'"\s*' + (r':\s*' if is_json else '') + r')("[^"\n]*"|[\d.]+)')
                encoded = ('"' + value + '"') if isinstance(value, str) else (str(value) if is_json else '"' + str(value) + '"')
                if scalar.search(body):
                    body = scalar.sub(lambda m: m.group(1) + encoded, body)
                else:
                    # Insert beside the existing boss HP scalar; no serialization
                    # of either entire file, and no copying KV balances to JSON.
                    anchor = re.search(r'(?m)^(\s*)"boss_max_health"[^\n]*\n', body)
                    assert anchor
                    line = anchor.group(1) + '"' + field + '"' + (': ' if is_json else ' ') + encoded + (',' if is_json else '') + '\n'
                    body = body[:anchor.end()] + line + body[anchor.end():]
            return body
        # Entries have nested items/tags but terminate at exactly three tabs.
        block = re.sub(r'(?ms)^\t{3}(?:\{|"\d+"\n\s*\{).*?^\t{3}\}', update_entry, block)
        if chapter in NEUTRALS:
            assert slot == len(NEUTRALS[chapter][0])
        return block
    # Bound stage matches by the next chapter header, preserving all separators.
    return re.sub(r'(?ms)^\t"ch(\d+)".*?(?=^\t"ch\d+"|\Z)', update_stage, text)


def verify_native():
    native = runpy.run_path(str(ROOT / 'scripts/author-playable-heroes.py'))
    raw = native['read_entry'](native['DEFAULT_VPK'], 'scripts/npc/npc_units.txt')
    units = native['parse_kv'](raw.decode('utf-8-sig'))['DOTAUnits']
    names = sorted({name for tier in NEUTRALS.values() for name in tier[0]})
    for name in names:
        assert units['npc_dota_neutral_' + name]['IsAncient'] == '1', name
    print('Verified native IsAncient=1:', ', '.join(names))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-native', action='store_true')
    args = parser.parse_args()
    if args.verify_native:
        verify_native()
    changes = []
    for name in ('levels.kv', 'levels_v07.json'):
        path = DATA / name
        original = path.read_text(encoding='utf-8')
        changes.append((path, original, update_text(original, name.endswith('.json'))))
    # Validate both transformations before updating either independent source.
    for path, original, updated in changes:
        if updated != original:
            path.write_text(updated, encoding='utf-8', newline='\n')
        print(path.name, 'updated' if updated != original else 'unchanged')


if __name__ == '__main__':
    main()
