"""Patch selected files in an unsigned, self-contained Workshop VPK v2.

Writes a separate archive; never changes Steam metadata, uploads or runs Dota.
The output uses standard MD5 chunk records and preserves every unselected payload.
"""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import struct
import zlib

MAGIC = 0x55AA1234
EMBEDDED = 0x7FFF
EMPTY_SIGNATURE = struct.pack('<5I', MAGIC, 1, 0, 0, 0)


def read_archive(path):
    data = Path(path).read_bytes()
    magic, version, tree_size, payload_size, chunks_size, hashes_size, signature_size = struct.unpack_from('<7I', data)
    if magic != MAGIC or version != 2:
        raise ValueError('Expected a VPK v2 archive')
    if 28 + tree_size + payload_size + chunks_size + hashes_size + signature_size != len(data):
        raise ValueError('Archive section lengths do not match its size')
    signature = data[-signature_size:] if signature_size else b''
    if signature not in (b'', EMPTY_SIGNATURE):
        raise ValueError('Refusing to rewrite an archive with a nonempty signature')
    start = 28 + tree_size
    pos = 28

    def string():
        nonlocal pos
        end = data.index(b'\0', pos, start)
        value = data[pos:end].decode('utf-8')
        pos = end + 1
        return value

    entries = {}
    while True:
        extension = string()
        if not extension:
            break
        while True:
            folder = string()
            if not folder:
                break
            while True:
                name = string()
                if not name:
                    break
                crc, preload_size, archive, offset, size, terminator = struct.unpack_from('<IHHIIH', data, pos)
                pos += 18
                if terminator != 0xFFFF or archive != EMBEDDED:
                    raise ValueError('Only self-contained VPK entries are supported')
                if pos + preload_size > start or offset + size > payload_size:
                    raise ValueError('Entry extends outside its archive section')
                payload = data[pos:pos + preload_size] + data[start + offset:start + offset + size]
                pos += preload_size
                relative = ('' if folder == ' ' else folder + '/') + name + ('' if extension == ' ' else '.' + extension)
                if relative in entries or zlib.crc32(payload) != crc:
                    raise ValueError('Duplicate path or CRC mismatch: ' + relative)
                entries[relative] = payload
    if pos != start:
        raise ValueError('Unexpected trailing tree bytes')
    return entries, signature


def write_archive(path, entries, signature):
    groups = {}
    for relative, data in sorted(entries.items()):
        p = PurePosixPath(relative)
        if p.is_absolute() or '..' in p.parts or '\x00' in relative:
            raise ValueError('Invalid archive path: ' + relative)
        extension = p.suffix[1:] or ' '
        name = p.stem if p.suffix else p.name
        folder = str(p.parent) if str(p.parent) != '.' else ' '
        groups.setdefault(extension, {}).setdefault(folder, []).append((name, data))
    tree, payload = bytearray(), bytearray()

    def string(value):
        tree.extend(value.encode('utf-8') + b'\0')

    for extension, folders in sorted(groups.items()):
        string(extension)
        for folder, files in sorted(folders.items()):
            string(folder)
            for name, data in files:
                string(name)
                tree.extend(struct.pack('<IHHIIH', zlib.crc32(data), 0, EMBEDDED, len(payload), len(data), 0xFFFF))
                payload.extend(data)
            string('')
        string('')
    string('')
    chunks = bytearray()
    chunk_size = 1024 * 1024
    for offset in range(0, len(payload), chunk_size):
        chunk = payload[offset:offset + chunk_size]
        chunks.extend(struct.pack('<III16s', EMBEDDED, offset, len(chunk), hashlib.md5(chunk).digest()))
    header = struct.pack('<7I', MAGIC, 2, len(tree), len(payload), len(chunks), 48, len(signature))
    data = header + tree + payload + chunks + hashlib.md5(tree).digest() + hashlib.md5(chunks).digest()
    data += hashlib.md5(data).digest() + signature
    Path(path).write_bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--addon-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--file', action='append', required=True, dest='files')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; use a fresh staging path')
    entries, signature = read_archive(args.base)
    original = dict(entries)
    for name in args.files:
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or name not in entries:
            parser.error('Replacement must name an existing relative archive entry: ' + name)
        entries[name] = (args.addon_source / relative).read_bytes()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_archive(args.output, entries, signature)
    verified, _ = read_archive(args.output)
    if verified != entries:
        raise RuntimeError('Output payload verification failed')
    changed = sorted(name for name in entries if entries[name] != original[name])
    print('Verified {} entries; {} changed: {}'.format(len(entries), len(changed), ', '.join(changed)))
    print('SHA256 ' + hashlib.sha256(args.output.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
