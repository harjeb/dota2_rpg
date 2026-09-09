"""Author the complete enabled native hero pool, minus explicitly excluded heroes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
EXCLUDED = {'npc_dota_hero_' + name for name in ('earth_spirit', 'invoker', 'rubick', 'kez')}
ATTRIBUTES = dict(DOTA_ATTRIBUTE_STRENGTH='strength', DOTA_ATTRIBUTE_AGILITY='agility',
                  DOTA_ATTRIBUTE_INTELLECT='intelligence', DOTA_ATTRIBUTE_ALL='universal')
DEFAULT_VPK = Path('C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota/pak01_dir.vpk')


def parse_kv(text):
    tokens = iter(t for t in re.findall(r'"(?:\\.|[^"\\])*"|[{}]|//[^\n]*', text) if not t.startswith('//'))
    def block():
        out = {}
        for key in tokens:
            if key == '}': return out
            value = next(tokens)
            out[key[1:-1]] = block() if value == '{' else value[1:-1]
        return out
    return block()


def read_entry(vpk, wanted):
    raw = vpk.read_bytes()
    signature, version, tree_size = struct.unpack_from('<III', raw)
    assert signature == 0x55AA1234 and version in (1, 2)
    header = 28 if version == 2 else 12
    cursor = header
    def string():
        nonlocal cursor
        end = raw.index(b'\0', cursor)
        result = raw[cursor:end].decode('utf-8')
        cursor = end + 1
        return result
    while True:
        extension = string()
        if not extension: break
        while True:
            folder = string()
            if not folder: break
            while True:
                name = string()
                if not name: break
                crc, preload, archive, offset, length, terminator = struct.unpack_from('<IHHIIH', raw, cursor)
                cursor += 18
                assert terminator == 0xffff
                prefix = raw[cursor:cursor+preload]
                cursor += preload
                path = ('' if folder == ' ' else folder + '/') + name + ('' if extension == ' ' else '.' + extension)
                if path == wanted:
                    if archive == 0x7fff:
                        content = raw[header+tree_size+offset:header+tree_size+offset+length]
                    else:
                        archive_path = vpk.with_name(vpk.name.replace('_dir.vpk', f'_{archive:03d}.vpk'))
                        with archive_path.open('rb') as stream:
                            stream.seek(offset)
                            content = stream.read(length)
                    result = prefix + content
                    import zlib
                    assert len(content) == length and zlib.crc32(result) == crc
                    return result
    raise KeyError(wanted)


def enabled_rows(native):
    heroes = parse_kv(native.decode('utf-8-sig'))['DOTAHeroes']
    return [dict(name=name, attribute=ATTRIBUTES[entry['AttributePrimary']], hero_id=int(entry['HeroID']))
            for name, entry in sorted(heroes.items()) if isinstance(entry, dict)
            and name.startswith('npc_dota_hero_') and entry.get('Enabled') == '1']


def pools(rows):
    return {category: [row['name'] for row in rows if row['attribute'] == category and row['name'] not in EXCLUDED]
            for category in ATTRIBUTES.values()}


def author(rows):
    pool = pools(rows)
    old = json.loads((DATA / 'heroes.json').read_text(encoding='utf-8'))
    for category, names in pool.items():
        old[category] = [dict(name=name, label=name.removeprefix('npc_dota_hero_')) for name in names]
    lines = ['"heroes"', '{', '\t"recruitable"', '\t{']
    for category, names in pool.items():
        lines += [f'\t\t"{category}"', '\t\t{']
        lines += [f'\t\t\t"{index}" "{name}"' for index, name in enumerate(names, 1)]
        lines += ['\t\t}']
    lines += ['\t}', '}']
    return '\n'.join(lines) + '\n', json.dumps(old, ensure_ascii=False, indent=2) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--vpk', type=Path, default=DEFAULT_VPK)
    parser.add_argument('--snapshot', action='store_true', help='Regenerate from the checked-in native metadata snapshot')
    args = parser.parse_args()
    snapshot_path = ROOT / 'data/native_hero_pool.json'
    if args.snapshot:
        snapshot = json.loads(snapshot_path.read_text(encoding='utf-8'))
    else:
        native = read_entry(args.vpk, 'scripts/npc/npc_heroes.txt')
        snapshot = dict(source='scripts/npc/npc_heroes.txt', source_vpk=str(args.vpk),
                        source_sha256=hashlib.sha256(native).hexdigest(), rows=enabled_rows(native))
    kv, js = author(snapshot['rows'])
    snapshot_path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (DATA / 'heroes.kv').write_text(kv, encoding='utf-8')
    (DATA / 'heroes.json').write_text(js, encoding='utf-8')
    print('Enabled native:',len(snapshot['rows']), 'Playable:',sum(map(len,pools(snapshot['rows']).values())),
          {k:len(v) for k,v in pools(snapshot['rows']).items()}, 'SHA256:',snapshot['source_sha256'])

if __name__ == '__main__':
    main()
