"""Offline campaign loot catalog. Native items + CURRENT neutral rotation, not shop-only.
All recipe scrolls and Roshan's Banner are excluded by campaign policy.
Self-consuming Shard/Blessing use transferable Roshan consumables instead of
AddItemByName on the commander. Blessing recipe excluded: auto-combination on
commander can consume Scepter without upgrading a roster hero.
"""
import argparse
import hashlib
import importlib.util
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native_author', ROOT / 'scripts/author-playable-heroes.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
DATA = ROOT / 'game/dota_addons/dota2_rpg/scripts/data'
LUA = ROOT / 'game/dota_addons/dota2_rpg/scripts/vscripts/data/campaign_loot_catalog.lua'
SPECIAL = set(('ward_observer cheese famango great_famango greater_famango royale_with_cheese ward_dispenser tango_single ultimate_scepter_roshan aghanims_shard_roshan aegis refresher_shard roshans_banner miniboss_minion_summoner foragers_health foragers_stats foragers_mana').split())
# 交付别名（普通魔晶/福佑 -> 肉山可转交版本）的两条来源现已被政策排除，
# 因此当前为空；保留映射结构，将来若要恢复只需改这里。
ALIASES = {}

# 掉落强度分级：1=最弱、5=最强。关卡按章节推进只抽该关区间内的档位，
# 避免第一章就掉 6000+ 的成品。数值来自本机物品价格分布（p20/p40/p60/p80）。
POWER_COST_THRESHOLDS = (1500, 3000, 4500, 6000)


def power_from_cost(cost):
    for index, limit in enumerate(POWER_COST_THRESHOLDS):
        if cost <= limit:
            return index + 1
    return len(POWER_COST_THRESHOLDS) + 1


def build(items_bytes, neutral_bytes):
    items = native.parse_kv(items_bytes.decode('utf-8-sig'))['DOTAAbilities']
    rotation = native.parse_kv(neutral_bytes.decode('utf-8-sig'))['neutral_items']['neutral_tiers']
    active = set()
    enhancements = set()
    # 中立装备本身自带 1..5 等级，直接作为掉落强度使用。
    neutral_power = {}
    for tier_key, tier in rotation.items():
        number = int(str(tier_key))
        for neutral_name in tier['items']:
            active.add(neutral_name)
            neutral_power[neutral_name] = number
        for group in tier['enhancements'].values():
            for neutral_name in group:
                enhancements.add(neutral_name)
                neutral_power[neutral_name] = number
    rows = []
    for name, schema in sorted(items.items()):
        if not isinstance(schema, dict):
            continue
        reason, category = None, None
        if name.startswith('item_recipe_') or schema.get('ItemRecipe') == '1':
            reason = 'Campaign policy: no recipe scroll drops'
        elif name == 'item_roshans_banner':
            reason = 'Campaign policy: no Roshan Banner drops'
        elif name == 'item_tpscroll':
            reason = 'Campaign policy: the mode has no Town Portal Scroll'
        elif name in ('item_ultimate_scepter_roshan', 'item_ultimate_scepter_2'):
            reason = "Campaign policy: Roshan's Aghanim's Scepter does nothing on roster heroes"
        elif name in ('item_aghanims_shard_roshan', 'item_aghanims_shard'):
            reason = "Campaign policy: dropped shards only exist as the inert Roshan consumable"
        elif schema.get('IsObsolete') == '1':
            reason = 'Native IsObsolete=1'
        elif name in active:
            category = 'neutral'
        elif name in enhancements:
            category = 'neutral_enhancement'
        elif schema.get('ItemIsNeutralActiveDrop') == '1' or schema.get('ItemIsNeutralPassiveDrop') == '1':
            reason = 'Not in installed neutral_items.txt current rotation (retired/test/token definition)'
        elif name.removeprefix('item_') in SPECIAL:
            category = 'special'
        elif schema.get('ItemPurchasable', '1') != '0' and int(schema.get('ItemCost', '0')) > 0:
            category = 'standard'
        else:
            short = name.removeprefix('item_')
            if short in ('black_grimoire', 'eldwurms_edda', 'furion_gold_bag', 'grisgris', 'tidehunter_fish'):
                reason = 'Hero-created/bound mechanic; arbitrary commander grant lacks originating hero state'
            elif short in ('courier', 'flying_courier'):
                reason = 'Legacy courier purchase consumable; current standard couriers are automatic'
            elif short == 'madstone_bundle':
                reason = 'Cast-on-pickup neutral crafting currency; campaign awards actual neutral equipment instead'
            else:
                reason = 'Event or test-only definition (Muerta event, mutation, pocket entity or super blink); not standard obtainable equipment'
        power = None
        if category in ('neutral', 'neutral_enhancement'):
            power = neutral_power.get(name, 5)
        elif category is not None:
            cost = int(schema.get('ItemCost', '0') or 0)
            # 零价的原生"高级消耗品"（不朽之守护、奶酪、肉山奖励）只应出现在后期关卡。
            power = power_from_cost(cost) if cost > 0 else 5
        rows.append(dict(name=name, category=category, excluded_reason=reason,
                         delivery=ALIASES.get(name, name) if category else None,
                         power=power, schema=schema))
    return dict(source_sha256=hashlib.sha256(items_bytes).hexdigest(),
                neutral_sha256=hashlib.sha256(neutral_bytes).hexdigest(),
                policy=__doc__, counts=dict(Counter(r['category'] or 'excluded' for r in rows)), items=rows)


LF = chr(10)  # Real newline; keeps the generated table free of escape noise.

HEADER = [
    '-- Generated by scripts/author-campaign-loot.py; no native creation/precache at startup.',
    '-- neutral = true marks native current-rotation neutral items: the engine keeps them in the',
    '-- dedicated neutral slot (16), outside the 0..14 inventory/backpack/native-stash range.',
    'return {',
]


def row_line(row):
    fields = [', neutral = true'] if row['category'] in ('neutral', 'neutral_enhancement') else []
    fields.append(', power = ' + str(row.get('power') or 1))
    fields.append(', cost = ' + str(int(row['schema'].get('ItemCost', '0') or 0)))
    fields.append(', category = "' + row['category'] + '"')
    return '    { name = "' + row['name'] + '", delivery = "' + row['delivery'] + '"' + ''.join(fields) + ' },'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--vpk', type=Path, default=native.DEFAULT_VPK)
    args = parser.parse_args()
    catalog = build(native.read_entry(args.vpk, 'scripts/npc/items.txt'), native.read_entry(args.vpk, 'scripts/npc/neutral_items.txt'))
    (DATA / 'campaign_loot_catalog.json').write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    pool = [r for r in catalog['items'] if r['category']]
    LUA.write_text(LF.join(HEADER + [row_line(r) for r in pool] + ['}']) + LF, encoding='utf-8')
    print(json.dumps(catalog['counts'], sort_keys=True), 'pool=', len(pool))

if __name__ == '__main__':
    main()
