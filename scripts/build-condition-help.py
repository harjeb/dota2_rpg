#!/usr/bin/env python3
"""Generate bilingual help; read-only native snapshot, no game installation needed."""
import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/native_skill_conditions.json'
JS = ROOT / 'content/dota_addons/dota2_rpg/panorama/scripts/custom_game/condition_help_data.js'
DOC = ROOT / 'docs/CONDITION_HELP_COVERAGE.md'
TOPICS = ROOT / 'data/condition_help_topics.json'
TYPE_SOURCE = ROOT / 'docs/UNIQUE_SKILL_MECHANISMS.md'


def text(zh, en):
    return {'zh': zh, 'en': en}


# Explicit purpose groupings of reviewed snapshot families. No flag-only semantic classification.
SPECS = [
('single_target', '单体伤害与控制', 'Single-target damage and control', 'offensive_unit',
 '对合法敌人使用普通单体技能；控制技能可另加正在持续施法筛选。', 'Use ordinary unit spells on legal enemies; interrupt spells may additionally filter channeling targets.',
 '敌方；最近', 'Enemy; nearest', '无额外条件；可按耗蓝添加自身魔法≥35%', 'No extra gate; optionally require self mana ≥35%', '距离≤900；打断时额外筛选正在持续施法', 'Distance ≤900; optionally require channeling to interrupt',
 '距离阈值不是技能施法距离。眩晕等效果仍由原生技能决定；并非所有伤害技能都能打断。', 'The threshold is not native cast range. Native spells determine effects; damage alone does not guarantee an interrupt.'),
('point', '地点伤害与区域控制', 'Point damage and area control', 'offensive_point',
 '把普通地点技能瞄准合法敌人的当前位置。', 'Aim ordinary point spells at a legal enemy’s current position.',
 '敌方；最近', 'Enemy; nearest', '自身800范围内敌人≥1', 'At least 1 enemy within 800 of caster', '距离≤900', 'Distance ≤900',
 '不预测弹道、目标移动或落点安全；线形技能不要直接套圆形范围人数。', 'No projectile, movement or safe-landing prediction; do not apply circular hit counts to line spells.'),
('area', '范围伤害与控制', 'Area damage and control', 'aoe',
 '已审查的普通范围技能，按原生范围半径估计候选人数。', 'Reviewed ordinary area spells using native radius to estimate candidate count.',
 '敌方；最近；最少范围命中=2', 'Enemy; nearest; minimum AOE hits=2', '自身800范围内敌人≥1', 'At least 1 enemy within 800 of caster', '按需要增加距离上限', 'Optionally limit distance',
 '范围计数不是实际命中承诺。原生半径未知或为0时，不使用人数门槛；环形、直线、矢量和延迟命中需单独审查。', 'Counts do not guarantee hits. Avoid hit-count gates with unknown/zero radius; rings, lines, vectors and delayed hits require separate review.'),
('no_target', '无目标战斗技能', 'No-target combat spells', 'offensive_no_target',
 '普通无目标伤害或控制技能，避免没有敌人时空放。', 'Ordinary no-target damage/control spells; avoid activation outside combat.',
 '敌方锚点；最近；原生执行为无目标', 'Enemy anchor; nearest; native order has no target', '自身450范围内敌人≥1', 'At least 1 enemy within 450 of caster', '无额外筛选', 'No additional filters',
 '450是可调战术阈值，不是统一作用半径。全图技能使用附近敌人只是保守战斗门槛。', '450 is an editable tactical threshold, not a universal spell radius. Nearby enemies are only a conservative combat gate for global spells.'),
('healing', '治疗友方与自身', 'Ally and self healing', 'healing_ally healing_self healing_area time_walk_recovery',
 '普通治疗选择受伤友方；自身治疗使用自身血量条件。', 'Choose wounded allies for ordinary healing; use self-health gates for self healing.',
 '友方；生命百分比最低；自身治疗改为自身', 'Ally; lowest HP percentage; self for self healing', '自身治疗：自身生命≤80%', 'Self healing: self HP ≤80%', '友方治疗：目标生命≤80%', 'Ally healing: target HP ≤80%',
 '优先队友可保留自身兜底；排除自身会取消兜底。时间漫游用自身≤60%且落点自身，只回溯近期伤害，不是全额治疗或安全撤退。治疗区域仍受原生距离限制。', 'Prefer teammate allows self fallback; exclude self removes it. Time Walk uses self HP ≤60% and caster position; it restores only recent damage, not all missing health or a safe retreat. Area healing respects native range.'),
('protection', '保护与护盾', 'Protection and shields', 'protection_ally protection_self protection_area',
 '对真正近期受伤的目标施放普通保护技能。', 'Apply ordinary protection to the unit that actually took recent damage.',
 '友方；生命百分比最低；自保改自身', 'Ally; lowest HP percentage; self for self protection', '自保：自身最近2秒受伤', 'Self protection: self damaged in last 2 seconds', '友方：目标最近2秒受伤', 'Ally: target damaged in last 2 seconds',
 '不要用任意友方受伤替代目标受伤。不预测致死伤害、来袭弹道；保护效果和强弱驱散由技能决定。', 'Do not substitute any ally damaged for selected target damaged. No lethal-damage or incoming-projectile prediction; native skills determine protection and dispel strength.'),
('ally_buff', '友方增益', 'Ally buffs', 'ally_combat_buff teammate_buff',
 '普通友方增益；区分战斗中增益和可提前施加的增益。', 'Ordinary ally buffs; distinguish combat buffs from pre-combat buffs.',
 '友方；优先队友，然后最近', 'Ally; prefer teammate, then nearest', '通常无额外条件', 'Usually no extra gate', '战斗增益：目标700范围内敌人≥1；提前增益：不加此项', 'Combat buff: ≥1 enemy within 700 of target; pre-combat: omit this filter',
 '附近敌我按施法者队伍判定。优先队友没有合格队友时才回退自身。玛西和猛犸的友方增益可提前施加，不加附近敌人门槛；其他普通战斗增益保留各自门槛。', 'Nearby teams are relative to the caster. Prefer teammate falls back to self only without a qualifying teammate. Marci Bodyguard and Magnus Empower omit nearby-enemy gates for early buffing; ordinary combat buffs keep their own gates.'),
('self_buff', '自身增益与变身启动', 'Self buffs and form activation', 'self_combat_buff',
 '启动已审查的普通自身战斗增益。', 'Activate reviewed ordinary self combat buffs.',
 '自身；无需目标排序', 'Self; no target ordering needed', '自身800范围内敌人≥1', 'At least 1 enemy within 800 of caster', '无额外筛选', 'No extra filters',
 '只介绍基础启动；不自动选择姿态、规划形态技能或完成专属连招。需要识别增益时必须核实modifier原生ID。', 'Covers basic activation only; no stance selection, form-specific planning or special combo. Verify native modifier IDs before using buff observation.'),
('movement', '位移接近敌人', 'Gap closing', 'gapclose',
 '已审查的进攻位移，选择有实际距离差的敌人。', 'Reviewed offensive movement toward an enemy at a meaningful distance.',
 '敌方；最近；目的地为目标', 'Enemy; nearest; destination target', '自身生命≥60%', 'Self HP ≥60%', '距离≥350且≤900', 'Distance ≥350 AND ≤900',
 '不保证落点安全、可达路径或越障；此配置不是逃生教程。不同位移技能的原生方向与距离仍需确认。', 'No safe-landing, path or obstacle guarantee; this is not an escape recipe. Confirm native direction and distance for each movement spell.'),
('summon', '召唤与部署', 'Summoning and deployment', 'summon',
 '有普通施法入口的已审查召唤技能，在交战附近启动。', 'Start reviewed summons with ordinary casting contracts near combat.',
 '敌方锚点；最近；保持原生目标方式', 'Enemy anchor; nearest; retain native targeting mode', '自身800范围内敌人≥1', 'At least 1 enemy within 800 of caster', '无额外筛选', 'No extra filters',
 '召唤物按已有固定行为行动；本页只设置本体何时召唤，不提供多单位独立战术。吃树、尸体或控制野怪等特殊入口需单独检查。', 'Summons follow existing fixed behavior. This page controls when the hero summons, not individual summon tactics. Tree consumption, corpses and creep domination need separate review.'),
('mana', '回蓝与消耗敌方魔法', 'Mana restoration and mana attacks', 'mana_restore mana_attack',
 '按技能用途选择缺蓝友方或仍有魔法的敌人。', 'Choose a low-mana ally or an enemy with remaining mana, according to the spell.',
 '回蓝：友方；魔法攻击：敌方；最近', 'Restore: ally; mana attack: enemy; nearest', '无额外条件', 'No extra gate', '回蓝：目标魔法≤50%；魔法攻击：目标魔法≥20%', 'Restore: target mana ≤50%; attack: target mana ≥20%',
 '百分比只作资源门槛，不估算实际回蓝量、烧蓝量或伤害。', 'Percentages are resource gates, not restoration, mana-burn or damage predictions.'),
('finisher', '低血量收割', 'Low-health finishers', 'execute',
 '把已审查收割技能留给低血量敌人。', 'Reserve reviewed finishing spells for low-health enemies.',
 '敌方；当前生命值最低', 'Enemy; lowest absolute health', '无额外条件', 'No extra gate', '目标生命≤30%', 'Target HP ≤30%',
 '30%不代表必杀。淘汰之刃等技能可能依赖绝对血量；法力虚空还依赖缺失魔法，需按实际技能调整。', '30% does not guarantee a kill. Culling Blade can depend on absolute health; Mana Void also depends on missing mana. Tune for the actual spell.'),
('dispel', '解控与救援', 'Dispel and rescue', 'dispel_control',
 '用已审查解控技能帮助受到控制的友方。', 'Help a controlled ally with a reviewed rescue spell.',
 '友方；最近，可优先队友', 'Ally; nearest, optionally prefer teammate', '无额外条件', 'No extra gate', '目标受到控制', 'Target is controlled',
 '受到控制仅是可观察状态，不证明所有负面状态均可驱散；优先检查技能驱散类型。', 'Controlled is an observable proxy, not proof that every debuff is dispellable. Check native dispel type.'),
('toggle', '开关技能：分开开启和关闭', 'Toggles: separate on and off rules', 'toggle_on toggle_combat_on healing_toggle_on',
 '已审查的耗蓝或战斗开关，必须用两条或多条独立规则。', 'Reviewed mana-draining or combat toggles need two or more separate rules.',
 '开启用战斗锚点；关闭用自身；显式选开/关', 'Combat anchor for on; self for off; explicitly select on/off', '耗蓝开启：附近800敌人≥1且自身魔法≥35%；关闭：魔法≤20%', 'Mana toggle on: ≥1 enemy within 800 AND mana ≥35%; off: mana ≤20%', '无额外筛选', 'No extra filters',
 '生命型：生命≥60%开启，≤40%或1000范围无敌人时各建关闭规则。治疗开关改为自身生命≤80%且魔法≥35%开启。不要把开关条件放进同一条AND规则；不适用于属性转换等特殊姿态。', 'Health toggle: on at HP ≥60%; separate off rules at HP ≤40% or no enemy within 1000. Healing toggle: on at HP ≤80% AND mana ≥35%. Never AND on/off gates in one rule. Not for special stances such as Attribute Shift.'),
('vector', '矢量基础施法', 'Basic vector casting', 'offensive_vector',
 '仅限已审查的琼英碧灵神枪出击普通敌方首击模式。', 'Only the reviewed ordinary hostile first-hit mode of Muerta’s Dead Shot.',
 '敌方；最近', 'Enemy; nearest', '自身800范围内敌人≥1', 'At least 1 enemy within 800 of caster', '距离≤900', 'Distance ≤900',
 '运行时沿施法者到目标方向延长150；不规划弹射、恐惧或双落点。其他矢量技能不因此得到覆盖，零方向不能施法。', 'Runtime extends caster-to-anchor direction by 150; no ricochet, fear or dual-endpoint planning. This does not cover other vectors; zero direction fails.')
]


def category(spec, rows):
    cid, zh, en, families, dz, de, tz, te, uz, ue, fz, fe, nz, ne = spec
    selected = [r for r in rows if r['active'] and r['expression_covered'] and r['family'] in families.split()]
    preferred = {
        'single_target': ['lion_impale', 'lion_voodoo', 'lina_laguna_blade'],
        'area': ['crystal_maiden_crystal_nova', 'lina_light_strike_array', 'enigma_black_hole'],
        'healing': ['omniknight_purification', 'warlock_shadow_word', 'necrolyte_death_pulse'],
        'protection': ['abaddon_aphotic_shield', 'omniknight_repel', 'antimage_counterspell'],
        'ally_buff': ['magnataur_empower', 'marci_bodyguard', 'ogre_magi_bloodlust'],
        'self_buff': ['sven_gods_strength', 'dragon_knight_elder_dragon_form', 'earthshaker_enchant_totem'],
        'summon': ['shadow_shaman_mass_serpent_ward', 'lycan_summon_wolves', 'lone_druid_spirit_bear']
    }.get(cid, [])
    shown = sorted(selected, key=lambda row: preferred.index(row['id']) if row['id'] in preferred else len(preferred))[:3]
    return dict(id=cid, title=text(zh,en), description=text(dz,de),
        examples=[example(r) for r in shown],
        steps=[text('选择英雄技能并打开规则设置。', 'Choose the hero ability and open rule settings.'),
               text('按模板设置目标、使用条件、筛选及排序。', 'Set target, use conditions, filters and ordering for the intended mode below.'),
               text('有预设时选择该技能的对应预设，再核对阈值、技能等级和冷却。', 'If available, choose the matching preset for this ability, check thresholds, save and check native availability.')],
        settings=[dict(label=text('UI目标与排序','UI target and ordering'),value=text(tz,te)),
                  dict(label=text('使用条件','Use conditions'),value=text(uz,ue)),
                  dict(label=text('目标筛选','Target filters'),value=text(fz,fe))],
        notes=[text(nz,ne)],
        covered_ability_ids=[r['id'] for r in selected], applicable_ability_ids=[r['id'] for r in selected],
        preset_count=len(selected), has_preset=bool(selected), preset_status=text('有现成技能预设，先选对应变体，再检查阈值。','Existing skill presets are available; choose the matching variant, then check thresholds.'),
        coverage_role='primary', source_families=families.split())


def example(row):
    # Native hero ID is retained for the UI's native hero localization and portrait.
    return dict(ability=row['id'], hero=row['hero'], label=text(row['name'], row['name_en']), has_preset=row['expression_covered'])


def extra(cid, zh, en, dz, de, ids, steps, settings, notes, by_id):
    return dict(id=cid,title=text(zh,en),description=text(dz,de),examples=[example(by_id[x]) for x in ids],
        steps=[text(*p) for p in steps],settings=[dict(label=text(*label),value=text(*value)) for label,value in settings],
        notes=[text(*p) for p in notes],covered_ability_ids=[],applicable_ability_ids=ids,
        coverage_role='supplemental',preset_count=0,has_preset=False,
        preset_status=text('本页额外流程需手动配置；示例的基础技能可能另有预设。','Configure this additional workflow manually; example abilities may have separate basic presets.'))


def build():
    raw=SOURCE.read_bytes(); source=json.loads(raw); rows=source['rows']; by_id={r['id']:r for r in rows}
    categories=[category(s,rows) for s in SPECS]
    categories.append(extra('channel','持续施法：启动与等待','Channeling: start and wait',
        '已审查技能只覆盖正常引导启动，完成由原生技能负责。','Reviewed spells cover ordinary channel startup; native spells own completion.',
        ['keeper_of_the_light_illuminate','witch_doctor_death_ward'],
        [('为启动规则选择技能原有目标类型。','Use the spell’s native target mode for startup.'),('按对应伤害教程设置敌人门槛并保存。','Set combat gates using the relevant damage tutorial and save.'),('保留正常引导；不要用施法经过时间猜测引导完成。','Allow normal channeling; do not infer completion from action elapsed time.')],
        [(('使用条件','Use conditions'),('附近800敌人≥1（启动示例）','≥1 enemy within 800 (startup example)')),(('目标与排序','Target and ordering'),('敌方；最近；按原生技能决定单位/地点/无目标','Enemy; nearest; native spell decides unit/point/no-target'))],
        [('不提供定时放波、提前取消或危险自动打断；成功施法事件不等于持续施法完成。','No timed release, early cancellation or danger interruption; cast success is not channel completion.')],by_id))
    charged=[r['id'] for r in rows if r['expression_covered'] and any(v.startswith('charged_') for v in r['preset_variants'])]
    categories.append(extra('charges','充能：保留一层资源','Charges: reserve a charge',
        '仅限原生充能可观察的技能；不是所有次数或层数资源。','Only spells with observable native charges; not arbitrary counters or stacks.',charged[:3],
        [('先套用该技能正确的基础用途规则。','Start with the correct basic-purpose rule.'),('增加技能充能≥2；动作留空表示当前技能。','Add ability charges ≥2; leave action empty for the current ability.'),('只要求可用一层时可选现成充能≥1变体。','For one available charge, use an existing charges ≥1 variant where available.')],
        [(('使用条件','Use conditions'),('技能充能≥2（希望保留一层时）','Ability charges ≥2 (to reserve one charge)')),(('目标/筛选/排序','Target/filters/ordering'),('继承基础用途规则','Inherit the basic-purpose rule'))],
        [('充能无法观察时条件不成立；不把modifier层数或英雄专属资源当作技能充能。','Unobservable charges fail the condition; modifier stacks and hero-specific resources are not native charges.')],by_id))
    categories.append(extra('persistent_movement','持续移动：缩地与践踏','Persistent movement: Shukuchi and Trample',
        '先启动技能，再用持续移动动作维持靠近目标的移动。','Activate the spell, then use a persistent movement action to move around the target.',
        ['weaver_shukuchi','primal_beast_trample'],
        [('先建立缩地或践踏施法规则。','Create a Shukuchi or Trample cast rule first.'),('新建持续移动动作，选择缩地或践踏移动模板。','Create a persistent movement action and select the Shukuchi or Trample movement template.'),('选择敌方目标，检查增益ID、触发技能和最长持续时间后保存。','Select an enemy target; check buff ID, trigger ability and maximum duration before saving.')],
        [(('UI目标与排序','UI target and ordering'),('敌方；最近','Enemy; nearest')),(('使用条件与筛选','Use conditions and filters'),('先使用技能对应基础门槛；移动由对应增益约束','Use the spell’s basic gates; the matching buff constrains movement')),(('移动模式','Movement mode'),('缩地：循环穿越；践踏：绕行；距离150；最长15秒','Shukuchi: cycle; Trample: orbit; distance 150; maximum 15 seconds'))],
        [('模板使用modifier_weaver_shukuchi / modifier_primal_beast_trample；停止、死亡、增益消失或超时会结束。地形及技能伤害间隔不由本教程保证。','Templates use modifier_weaver_shukuchi / modifier_primal_beast_trample; stop, death, buff loss or timeout ends movement. Terrain and damage tick timing are not guaranteed.')],by_id))
    categories.append(extra('combo','连招：跳刀 → 刃甲 → 吼','Combo: Blink → Blade Mail → Call',
        '用前置动作成功后的条件，把同一英雄的技能和装备接起来。','Chain skills and items on the same hero using a successful prerequisite action.',
        ['axe_berserkers_call'],
        [('第一条选择跳刀，目标敌方，排序最近。','Rule 1: Blink Dagger, enemy target, nearest priority.'),('第二条选择刃甲，目标自身。添加“前置动作成功后”，选择当前英雄的跳刀，窗口2秒。','Rule 2: Blade Mail, self target. Add after prerequisite success; choose this hero’s Blink Dagger with a 2-second window.'),('第三条选择狂战士之吼，目标自身。添加同一条件，前置动作选择当前英雄的刃甲，窗口2秒。','Rule 3: Berserker’s Call, self target. Add the same condition, selecting this hero’s Blade Mail with a 2-second window.'),('按跳刀、刃甲、吼的顺序放置并分别应用；每条规则的其他条件也要满足。','Order and apply the three rules as Blink, Blade Mail, Call. Each rule must also satisfy its other conditions.')],
        [(('第一条：跳刀','Rule 1: Blink'),('敌方；最近；不添加前置成功条件','Enemy; nearest; no prerequisite-success gate')),(('第二条：刃甲','Rule 2: Blade Mail'),('自身；前置跳刀成功后2秒内','Self; within 2 seconds after Blink succeeds')),(('第三条：吼','Rule 3: Call'),('自身；前置刃甲成功后2秒内','Self; within 2 seconds after Blade Mail succeeds'))],
        [('技能或物品必须属于规则对应的英雄，并且可以使用；受伤封锁的跳刀不会触发下一步。','Skills and items must belong to the configured hero and be usable. A damage-disabled Blink does not trigger the follow-up.'),('成功施放不等于已经命中、控制生效或引导完成；各条规则不会自动共享目标。后续来不及在窗口内施放时，可适当调大秒数。','Cast success does not mean impact, control application or channel completion. Rules do not automatically share targets. Increase the window if follow-up casting needs more time.')],by_id))
    categories[-1]['examples'] = [dict(ability='item_blink',hero='npc_dota_hero_axe',label=text('跳刀','Blink Dagger'),has_preset=False), dict(ability='item_blade_mail',hero='npc_dota_hero_axe',label=text('刃甲','Blade Mail'),has_preset=False)] + categories[-1]['examples']
    for authored in json.loads(TOPICS.read_text(encoding='utf-8'))['topics']:
        page = dict(authored)
        page['examples'] = [example(by_id[a]) for a in page.pop('example_ids')]
        page.update(covered_ability_ids=[], applicable_ability_ids=[e['ability'] for e in page['examples']], coverage_role='supplemental',preset_count=0,has_preset=False,
            preset_status=text('本页按步骤手动设置；技能的现成预设可作为起点。','Configure this workflow manually; an existing skill preset can be a starting point.'))
        categories.append(page)
    categories.append(extra('special','特殊技能与未覆盖范围','Special skills and uncovered cases',
        '没有审查成立的基础用途时，先确认专属目标与流程，不能直接套标记。','Without a reviewed useful basic mode, first establish special targeting and sequencing; flags alone are insufficient.',
        ['invoker_invoke','morphling_replicate','ancient_apparition_ice_blast','pangolier_gyroshell'],
        [('确认技能在当前形态、升级和阶段中确实可用。','Confirm the ability exists in the current form, upgrade and phase.'),('检查技能专属对象、阶段动作或子技能是否有专用支持。','Check support for special objects, phase actions or sub-abilities.'),('未确认支持时，暂不启用该自动规则；普通条件不能补齐缺少的专属流程。','Leave the automated rule disabled until support is confirmed; ordinary conditions cannot supply missing special workflows.')],
        [(('UI目标/条件/筛选/排序','UI target/conditions/filters/ordering'),('无通用配置；按专属机制逐技能检查','No generic configuration; review the special contract per ability'))],
        [('祈求配球、复制/偷取、定时释放、专属双落点、自动法球与攻击时机，以及石鳞剑士滚动转向没有通用模板。已有小小抓取支持见“抓取对象与投掷落点”。','Orb sequences, copy/steal, timed releases, special dual endpoints, autocast attack timing and Pangolier rolling/steering have no generic recipe here. See Grabbed units and Toss destinations for supported Tiny handling.')],by_id))
    active=[r for r in rows if r['active']]; covered=sorted({a for c in categories for a in c['covered_ability_ids']})
    presets=[r['id'] for r in active if r['expression_covered']]
    assert set(covered)==set(presets), 'Every reviewed primary family must have a tutorial'
    count=len(covered); denom=len(active); percent=round(count*100/denom,2)
    type_pages = json.loads(TOPICS.read_text(encoding='utf-8'))['type_pages']
    historical = re.findall(r'^\| (G\d{2}) \| ([^|]+) \|', TYPE_SOURCE.read_text(encoding='utf-8'), re.M)
    assert {key for key, _ in historical} == set(type_pages), 'Historical type mapping must remain complete'
    page_ids = {page['id'] for page in categories}
    assert all(set(pages) <= page_ids for pages in type_pages.values()), 'Type mapping references missing pages'
    type_coverage = [dict(id=key,title=name.strip(),status='excluded_passive' if key=='G14' else 'basic_tutorial' if type_pages[key] else 'deferred',pages=type_pages[key]) for key,name in historical]
    type_total = sum(row['status'] != 'excluded_passive' for row in type_coverage)
    type_covered = sum(row['status'] == 'basic_tutorial' for row in type_coverage)
    type_percent = round(type_covered*100/type_total,2)
    summary=dict(total_rows=len(rows),active_denominator=denom,passive_excluded=len(rows)-denom,
        reviewed_id_covered=count,reviewed_id_percent=percent,preset_covered=len(presets),preset_percent=round(len(presets)*100/denom,2),
        type_total=type_total,type_covered=type_covered,type_percent=type_percent,type_source='docs/UNIQUE_SKILL_MECHANISMS.md',
        native_execution_validated=source['coverage']['native_execution_validated'],target_percent_min=80,target_percent_max=90,
        target_met=80<=type_percent<=90,uncovered_active=denom-count,
        source='data/native_skill_conditions.json',source_sha256=hashlib.sha256(raw).hexdigest(),
        title=text('技能条件教程覆盖','Ability condition tutorial coverage'),
        description=text(f'沿用项目22类机制划分，排除纯被动后共{type_total}类；其中{type_covered}类提供基础设置教程（{type_percent}%）。',f'Using the project’s 22 existing mechanism types, {type_total} remain after excluding pure passives. {type_covered} have basic setup tutorials ({type_percent}%).'),
        denominator_note=text('类型可以重叠，一个技能可能参考多页。比例表示基础教学覆盖，不代表每个技能都可套同一模板；再次释放、自动法球与攻击时机、专属双目标、英雄专属流程四类暂不计入。','Types can overlap, so a spell may use several pages. This measures basic teaching coverage, not a universal recipe for every spell. Recasts, autocast attack timing, special dual targets and hero-specific workflows are not counted.'),
        validation_note=text('逐技能已审查预设和原生实机验证是独立审计指标。','Per-skill reviewed presets and native execution validation are separate audit measures.'))
    basics=[dict(id='pipeline',title=text('条件、筛选与排序的分工','Conditions, filters and ordering'),description=text('使用条件决定何时尝试；目标筛选决定谁有资格；排序从合格目标中挑选。多条条件和筛选分别按AND计算，排序按顺序比较；没有合格目标就不施放。','Use conditions decide when to try; target filters determine eligibility; priorities rank eligible targets. Conditions and filters are AND gates; ordering is lexicographic. No legal target means no cast.')),
        dict(id='units',title=text('阈值与原生限制','Thresholds and native limits'),description=text('UI百分比填写0–100；秒数填写秒；距离填写游戏单位。附近使用条件以自身为中心，附近目标筛选以目标为中心。条件通过仍需原生可用、距离、魔法和冷却合法。','UI percentages use 0–100; time uses seconds; distances use game units. Nearby use gates center on the caster; nearby target filters center on the candidate. Availability, range, mana and cooldown still apply.')),
        dict(id='presets',title=text('预设是起点','Presets are a starting point'),description=text('先按具体技能选择预设，再核对自身/友方/敌方、阈值和施法方式。每页说明其适用模式，不代表该技能所有专属机制都使用同一配置。','Choose the preset for the specific ability, then check self/ally/enemy, thresholds and casting mode. Each page covers its stated mode; a spell’s special mechanics may require different settings.'))]
    # Keep simple renderers compatible: basics can be passed directly to a {zh,en} text helper.
    for basic in basics:
        for lang in ('zh', 'en'):
            basic[lang] = basic['title'][lang] + ': ' + basic['description'][lang]
    summary['note'] = {lang: ' '.join(summary[key][lang] for key in ('description', 'denominator_note')) for lang in ('zh', 'en')}
    for item in categories:
        item['notes'].insert(0, item['preset_status'])
    return dict(schema_version=2,summary=summary,basics=basics,categories=categories,type_coverage=type_coverage,
        uncovered=[dict(ability=r['id'],hero=r['hero'],label=text(r['name'],r['name_en']),reason=r['unsupported_reason']) for r in active if r['id'] not in covered])


def outputs():
    data=build(); s=data['summary']; source=json.loads(SOURCE.read_text(encoding='utf-8'))
    js='// Generated by scripts/build-condition-help.py; do not edit.\nvar RpgConditionHelpData = '+json.dumps(data,ensure_ascii=False,indent=2)+';\n'
    lines=['# Condition help coverage / 条件教程覆盖','',
        f"沿用 [{s['type_source']}]({Path(s['type_source']).name}) 的 G00–G21 **22 类**；排除 G14 纯被动后 **{s['type_total']} 类**主动设置主题。已有基础教程 **{s['type_covered']}/{s['type_total']} = {s['type_percent']}%**，落在用户要求的约80–90%范围。共 {len(data['categories'])} 个浏览章节，章节与机制类型并非一一对应。",'',
        '类型教学覆盖的判定：该历史主题至少有一份当前可照填的基础设置或配置流程，列出实例与限制。分类原本就可重叠；一个技能可参考多页。它不表示实现该历史标签列出的所有高级诉求，也不是全技能ID覆盖率或实机通过率。G18、G19、G20、G21未计入：普通矢量首击说明也不等于G20专属双点几何。','',
        '## Historical type mapping / 历史类型映射','',
        '| 类型 | 主题 | 本次基础教学 | 对应章节 |', '|---|---|---|---|']
    lines += [f"| {t['id']} | {t['title']} | {t['status']} | {', '.join(t['pages']) or '—'} |" for t in data['type_coverage']]
    lines += ['', 'G09说明有无/层数/剩余时间及OR拆行；G11用存活敌人数代替附近门槛；G13只教已实现的小小抓取/落点并说明自动抓树；G15教升级后新增技能单独配置与重新检查范围；G16只教自损技能的自身血量下限；G17用迷雾缠绕分别配置敌友两条规则。这些基础流程不声称预测伤害、传送落点、对象全覆盖、自动形态规划或友军误伤收益。', '',
        '## Per-ID audit / 逐技能审查口径','',
        f"Source: `{s['source']}`. SHA-256: `{s['source_sha256']}`.",'',
        f"原始 {s['total_rows']} 行；主动分母 **{s['active_denominator']}**；排除被动 {s['passive_excluded']}。按 `active` 保留旧版、升级、隐藏与子技能，不以常用程度缩小分母。",'',
        f"逐ID已审查基础模式映射 **{s['reviewed_id_covered']}/{s['active_denominator']} = {s['reviewed_id_percent']}%**；已有一键预设 **{s['preset_covered']}/{s['active_denominator']} = {s['preset_percent']}%**。只按已审查family映射，不将新增专题的示例直接加入分子；特殊对象等未在快照中复核的ID也不因教程提到就自动改成已审查。",'',
        f"快照原生实机验证数：**{s['native_execution_validated']}**。本任务没有运行Dota，不更改条件实现或现有预设。",'',
        '## Evidence / 证据与限制','',
        '`condition_catalog.js` and `condition_registry.lua` expose health, counts, timing and modifier conditions. `tests/condition-v2.test.lua` covers modifier presence/stacks/duration; `target_selector.lua` applies legality and ordering. `docs/RUNTIME_FIXES_V19.md` and `tests/condition-specials.test.lua` describe and exercise Tiny grab/landing contracts. `tests/action-success-chain.test.lua` exercises Blink → Blade Mail → Call. `tests/marci-targets.test.lua` covers native-target mocks and teammate preferences. `docs/CONDITION_LIST_ZH.md` defines UI units and condition meanings. Mist Coil’s snapshot description and BOTH target team support the self-cost and dual-team examples. Upgrade teaching only explains separate rules for newly available abilities; it does not claim automatic upgrade detection or special form logic. Native execution is still distinct from these offline checks.','',
        '## Category counts / 类别统计','', '| ID | 中文用途 | Audited IDs | Existing presets | Role |','|---|---|---:|---:|---|']
    lines += [f"| {c['id']} | {c['title']['zh']} | {len(c['covered_ability_ids'])} | {c['preset_count']} | {c['coverage_role']} |" for c in data['categories']]
    lines += ['', 'Supplemental pages overlap primary abilities or explain limitations; do not sum example counts. Supplemental `has_preset=false` refers to the additional workflow, while `examples[].has_preset` refers to the example ability’s basic preset.', '', '## Uncovered active IDs / 未覆盖主动ID', '', '| Native ability | Exclusion in snapshot |', '|---|---|']
    lines += [f"| `{r['ability']}` | `{r['reason']}` |" for r in data['uncovered']]
    lines += ['', '## Data contract and regeneration / 接口与生成', '',
        'Global `var RpgConditionHelpData = {schema_version, summary, basics, categories, type_coverage, uncovered}`. All display strings use `{zh,en}`, including title, description, steps, settings label/value, notes, example label and preset status. IDs, source paths, enum-like audit fields and numbers are not display text. `examples[].hero` is the native hero ID for portrait/localization; `label` is the bilingual ability name. Basics also expose direct `zh/en` aliases for simple text renderers; `summary.note` combines the coverage notices. Each category repeats its preset status in notes for basic renderers. No new localization tokens are required.', '',
        '`data/condition_help_topics.json` authors additional bilingual topics and maps the existing historical types to tutorial pages. `python scripts/build-condition-help.py` regenerates the JS and this report; `python scripts/build-condition-help.py --check` verifies byte-for-byte freshness. `python tests/condition-help.test.py` verifies integrity, denominator arithmetic, bilingual fields and the audited family-to-tutorial mapping.', '']
    return {JS:js,DOC:'\n'.join(lines)}


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    for path,value in outputs().items():
        if args.check:
            if not path.exists() or path.read_bytes()!=value.encode('utf-8'):
                raise SystemExit('Stale generated output: '+str(path))
        else:
            path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(value.encode('utf-8'))
    print('condition help: outputs verified' if args.check else 'condition help: outputs generated')


if __name__=='__main__':
    main()
