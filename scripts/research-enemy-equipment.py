"""Reproduce UI40's public OpenDota equipment sample; never needed at runtime.

fetch: cache 64 hero purchase-frequency responses and 20 recent pro matches,
at most 40 requests/minute. summarize: use cached data + installed native prices.
The snapshot contains no player names/account IDs. Raw responses stay in Temp.
"""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import runpy
import statistics
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path(tempfile.gettempdir()) / 'rpg_ui40_opendota'
SNAPSHOT = ROOT / 'data/research/enemy_equipment_opendota_20260911.json'
BASE = 'https://api.opendota.com/api/'


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def profiles():
    heroes = json.loads((ROOT / 'data/enemy_equipment_profiles.json').read_text(encoding='utf-8'))['heroes']
    return {'BUILDS': heroes, 'ROLES': {hero: row['role'] for hero, row in heroes.items()}}


def fetch():
    author = profiles()
    CACHE.mkdir(parents=True, exist_ok=True)
    metadata = {}
    manifest = CACHE / 'manifest.json'
    if manifest.exists(): metadata = json.loads(manifest.read_text(encoding='utf-8'))
    previous = 0

    def get(key, endpoint):
        nonlocal previous
        path = CACHE / (key + '.json')
        url = BASE + endpoint
        if not path.exists():
            time.sleep(max(0, 1.5 - (time.monotonic() - previous)))
            previous = time.monotonic()
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'dota2-rpg-equipment-research/1.0'}), timeout=18) as response:
                    data = response.read()
                json.loads(data)
                path.write_bytes(data)
            except Exception as error:
                metadata[key] = {'url': url, 'error': str(error)}
                save(manifest, metadata)
                print(key, str(error), flush=True)
                return None
        data = path.read_bytes()
        metadata[key] = {'url': url, 'retrieved_at_utc': datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat(), 'sha256': hashlib.sha256(data).hexdigest()}
        save(manifest, metadata)
        print(key, len(data), flush=True)
        return json.loads(data)

    heroes = get('heroes', 'heroes')
    get('items', 'constants/items')
    matches = get('pro_matches', 'proMatches')
    if heroes is None or matches is None:
        raise RuntimeError('Required OpenDota response unavailable; keep the prior snapshot.')
    ids = {h['name'].removeprefix('npc_dota_hero_'): h['id'] for h in heroes}
    for hero in sorted(author['BUILDS']):
        key = 'wk_popularity' if ids[hero] == 42 else f'popularity_{ids[hero]}'
        get(key, f'heroes/{ids[hero]}/itemPopularity')
    # Consecutive proMatches results include wins and losses. This is a small
    # tournament sample, not a population-weighted sample of all Dota players.
    for match in matches[:20]:
        get('match_' + str(match['match_id']), 'matches/' + str(match['match_id']))
    summarize()


def summarize():
    author = profiles()
    native_reader = runpy.run_path(str(ROOT / 'scripts/author-playable-heroes.py'))
    raw = native_reader['read_entry'](native_reader['DEFAULT_VPK'], 'scripts/npc/items.txt')
    native = native_reader['parse_kv'](raw.decode('utf-8-sig'))['DOTAAbilities']
    costs = {name.removeprefix('item_'): int(value['ItemCost']) for name, value in native.items() if isinstance(value, dict) and 'ItemCost' in value}
    load = lambda key: json.loads((CACHE / (key + '.json')).read_text(encoding='utf-8'))
    item_ids = {int(value['id']): name for name, value in load('items').items() if 'id' in value}
    heroes = {h['id']: h['name'].removeprefix('npc_dota_hero_') for h in load('heroes')}
    meta = load('manifest')
    observations, matches, unknown = [], [], set()
    for index in load('pro_matches')[:20]:
        path = CACHE / ('match_' + str(index['match_id']) + '.json')
        if not path.exists(): continue
        match = json.loads(path.read_text(encoding='utf-8'))
        # Turbo, bot/custom/ability draft and incomplete records are unsuitable
        # comparators for ordinary player equipment at a given hero level.
        accepted = match.get('game_mode') in (1, 2, 22) and match.get('duration', 0) >= 600 and len(match.get('players', [])) == 10
        matches.append({key: match.get(key, index.get(key)) for key in ('match_id', 'start_time', 'duration', 'game_mode', 'lobby_type', 'avg_rank_tier')})
        matches[-1]['included'] = accepted
        if not accepted: continue
        for player in match['players']:
            names = [item_ids.get(player.get(f'item_{slot}', 0), 'unknown') for slot in range(6) if player.get(f'item_{slot}', 0)]
            missing = [name for name in names if name not in costs]
            unknown.update(missing)
            hero = heroes.get(player.get('hero_id'))
            if not hero or missing or not 1 <= player.get('level', 0) <= 30: continue
            observations.append({'match_id': match['match_id'], 'hero': hero, 'role': author['ROLES'].get(hero, 'outside_roster'), 'level': player['level'], 'items': names, 'equipment_value': sum(costs[name] for name in names), 'net_worth': player.get('net_worth'), 'gold_per_min': player.get('gold_per_min')})

    def describe(rows):
        values = sorted(row['equipment_value'] for row in rows)
        return {'n': len(values), 'mean': round(statistics.mean(values)), 'median': round(statistics.median(values)), 'p75': round(statistics.quantiles(values, n=4, method='inclusive')[2]) if len(values) > 1 else values[0]} if values else {'n': 0}

    groups = {}
    for low, high in [(1, 6), (7, 9), (10, 13), (14, 17), (18, 21), (22, 25), (26, 30)]:
        rows = [row for row in observations if low <= row['level'] <= high]
        groups[f'{low}-{high}'] = {'all': describe(rows)}
        for role in ('strength', 'agility', 'caster', 'support'):
            groups[f'{low}-{high}'][role] = describe([row for row in rows if row['role'] == role])
    popularity = {}
    for hero_id, hero in heroes.items():
        if hero not in author['BUILDS']: continue
        key = 'wk_popularity' if hero_id == 42 else f'popularity_{hero_id}'
        if not (CACHE / (key + '.json')).exists(): continue
        phases = load(key)
        popularity[hero] = {'hero_id': hero_id, 'source': meta[key], 'phases': {phase: {item_ids.get(int(item_id), 'unknown_id_' + item_id): count for item_id, count in rows.items()} for phase, rows in phases.items()}, 'observed_inventory': describe([row for row in observations if row['hero'] == hero])}
    used_sources = {'heroes', 'items', 'pro_matches', *('match_' + str(m['match_id']) for m in matches)}
    used_sources.update('wk_popularity' if value['hero_id'] == 42 else 'popularity_' + str(value['hero_id']) for value in popularity.values())
    meta = {key: value for key, value in meta.items() if key in used_sources}
    snapshot = {'retrieved_at_utc': datetime.now(timezone.utc).isoformat(), 'method': 'First 20 entries from one OpenDota proMatches response; ordinary modes 1/2/22, duration >=600s, ten players. Value is sum of occupied item_0..5 at match end using installed native ItemCost; not net worth, purchase spend or a population average. Hero role is the authored RPG role, not inferred match lane.', 'limitations': ['Small, correlated, convenience sample; low-level matches and individual heroes may have few/no observations.', 'Excludes backpack, cash, consumed Shard/Blessing/Moon Shard and neutral slot. Unmapped/unpriced inventories excluded.', 'itemPopularity is purchase-event frequency by phase, not percentage of all hero matches or six-slot inventories; no invented denominator or purchase minutes.', 'The RPG strength uplift is authored separately from these measured observations.'], 'native_item_source': {'path': 'pak01_dir.vpk/scripts/npc/items.txt', 'sha256': hashlib.sha256(raw).hexdigest()}, 'sources': meta, 'matches': matches, 'observations': observations, 'level_groups': groups, 'popularity': popularity, 'unpriced_items': sorted(unknown), 'item_costs': costs}
    save(SNAPSHOT, snapshot)
    print(json.dumps({'snapshot': str(SNAPSHOT), 'heroes': len(popularity), 'included_matches': sum(m['included'] for m in matches), 'players': len(observations), 'level_groups': groups, 'unpriced_items': sorted(unknown)}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('fetch', 'summarize'))
    args = parser.parse_args()
    fetch() if args.mode == 'fetch' else summarize()
