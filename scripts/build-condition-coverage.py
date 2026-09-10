#!/usr/bin/env python3
"""Rebuild the auditable native-condition snapshot, presets and compact report.
Default input is the checked-in snapshot. --source-dir imports the original two
UTF-8 extraction files; no Dota install, third-party Python modules or network.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data/native_skill_conditions.json'
JS = ROOT / 'content/dota_addons/dota2_rpg/panorama/scripts/custom_game/skill_condition_presets.js'
DOC = ROOT / 'docs/CONDITION_COVERAGE.md'
UNIQUE_DOC = ROOT / 'docs/UNIQUE_SKILL_MECHANISMS.md'

def condition(kind, **fields):
    return dict(type=kind, **fields)

def rule(team='enemy', use=None, filters=None, priority='nearest', **options):
    return dict(use_conditions=use or [], target_filters=filters or [],
                target_priorities=[condition(priority)], target_team=team,
                target='self' if team == 'self' else team + '_distance_nearest', **options)

NEAR = condition('nearby_enemies_gte', value=1, radius=800)
FAMILIES = {
    'offensive_vector': (rule(use=[NEAR], filters=[condition('distance_lte', value=900)]), 'Reviewed ordinary enemy vector mode: select the nearest legal in-range enemy. Native point start or primary unit uses that anchor; runtime continues caster-to-anchor direction by 150 units. Zero-length direction fails. No vector parameters, landing plan or ricochet-hit prediction.'),
    'offensive_unit': (rule(filters=[condition('distance_lte', value=900)]), 'Native hostile unit targeting: select a nearby opponent rather than spending the action without combat context. Native target flags and runtime legality determine invulnerability eligibility.'),
    'offensive_point': (rule(use=[NEAR], filters=[condition('distance_lte', value=900)]), 'Native point order with hostile team or damage metadata: require an enemy near the caster and anchor the point to a nearby opponent. No trajectory prediction is claimed.'),
    'offensive_no_target': (rule(use=[condition('nearby_enemies_gte', value=1, radius=450)]), 'Native no-target combat action with damage metadata or reviewed offensive purpose: only activate with an opponent nearby. The 450-unit tactical threshold is editable, not an asserted ability radius.'),
    'aoe': (rule(use=[NEAR], min_aoe_hits=2), 'Native AOE combat action: require at least two candidate enemies inside the runtime native GetAOERadius circle. Unknown/zero radius must not be treated as coverage of geometry or a successful cast.'),
    'healing_ally': (rule('ally', filters=[condition('hp_pct_lte', value=80)], priority='lowest_hp_pct'), 'Reviewed healing mode plus native friendly/both unit targeting: choose an ally at or below 80% HP to avoid full-health healing.'),
    'time_walk_recovery': (rule('self', use=[condition('self_hp_pct_lte', value=60)]), 'Time Walk recovery mode: at or below 60% self HP, cast at the caster position without an enemy-distance filter. Native Time Walk only restores damage within its backtrack window; this is not a guarantee of healing all missing HP or a safe retreat.'),
    'healing_self': (rule('self', use=[condition('self_hp_pct_lte', value=80)]), 'Reviewed self or caster-area healing: activate when the caster is at or below 80% HP. This does not optimize healing of the entire team.'),
    'healing_area': (rule('ally', filters=[condition('hp_pct_lte', value=80)], priority='lowest_hp_pct'), 'Reviewed team/point healing: choose a wounded allied anchor at or below 80% HP. Native area range still constrains execution.'),
    'protection_ally': (rule('ally', filters=[condition('recently_damaged', seconds=2)], priority='lowest_hp_pct'), 'Reviewed protection mode and native friendly/both target: protect the selected recently damaged ally, not an unrelated damaged ally.'),
    'protection_self': (rule('self', use=[condition('self_recently_damaged', seconds=2)]), 'Reviewed self-protection: activate after actual recent damage, without predicting incoming projectiles or lethal damage.'),
    'ally_combat_buff': (rule('ally', filters=[condition('nearby_enemies_gte', value=1, radius=700)]), 'Native friendly unit buff: select an ally with an enemy nearby. Proximity counts are relative to the caster team, not the target team.'),
    'teammate_buff': (rule('ally', filters=[condition('exclude_self')]), 'Native friendly buff: select the nearest legal teammate, excluding the caster. Native range and target validation remain authoritative; no enemy proximity gate prevents pre-combat buffing.'),
    'self_combat_buff': (rule('self', use=[NEAR]), 'Reviewed ordinary self combat buff: activate only when an enemy is within 800 units; no stance selection or form-specific follow-up actions.'),
    'gapclose': (rule(use=[condition('self_hp_pct_gte', value=60)], filters=[condition('distance_gte', value=350), condition('distance_lte', value=900)]), 'Reviewed offensive movement mode: close a meaningful gap (350–900 units) only with at least 60% self HP. This is not safe-landing/path/terrain prediction.'),
    'summon': (rule(use=[NEAR]), 'Reviewed summon/deploy action with ordinary native casting: summon when an enemy is nearby. Does not issue orders to spawned units or guarantee summon placement.'),
    'mana_restore': (rule('ally', filters=[condition('mana_pct_lte', value=50)], priority='nearest'), 'Reviewed native allied mana restoration: select an ally at or below 50% mana.'),
    'mana_attack': (rule(filters=[condition('mana_pct_gte', value=20)]), 'Reviewed enemy mana-drain/burn action: avoid an already empty mana pool (target mana at least 20%).'),
    'execute': (rule(filters=[condition('hp_pct_lte', value=30)], priority='lowest_health'), 'Reviewed finishing spell and native hostile target: reserve it for a low-health opponent. A percentage threshold is not lethal-damage prediction.'),
    'dispel_control': (rule('ally', filters=[condition('is_controlled')]), 'Reviewed strong-dispel/rescue mode: select a controlled ally. is_controlled is an observable status proxy, not proof that every debuff is dispellable.'),
    'toggle_on': (rule(use=[NEAR, condition('self_mana_pct_gte', value=35)], desired_toggle_state='1'), 'Reviewed mana-draining combat toggle: enable near an enemy with at least 35% mana. The separate off threshold is 20%, leaving a gap to avoid oscillation.'),
    'toggle_combat_on': (rule(use=[NEAR, condition('self_hp_pct_gte', value=60)], desired_toggle_state='1'), 'Reviewed combat toggle: enable near an enemy with at least 60% HP; separate off rules handle low HP or disengagement.'),
    'toggle_health_off': (rule('self', use=[condition('self_hp_pct_lte', value=40)], desired_toggle_state='0'), 'Health-draining combat toggle: turn off below 40% HP, with a 60% on threshold to avoid oscillation.'),
    'toggle_idle_off': (rule('self', use=[condition('no_enemy_within', radius=1000)], desired_toggle_state='0'), 'Disable this combat toggle after enemies leave the 1000-unit vicinity; on uses 800 units.'),
    'healing_toggle_on': (rule('self', use=[condition('self_hp_pct_lte', value=80), condition('self_mana_pct_gte', value=35)], desired_toggle_state='1'), 'Reviewed healing toggle: enable for a wounded caster at or below 80% HP with at least 35% mana; the separate off variant stops at 20% mana.'),
    'protection_area': (rule('ally', filters=[condition('recently_damaged', seconds=2)]), 'Reviewed point-area protection: anchor the field to a recently damaged ally; native point range still applies.'),
    'toggle_off': (rule('self', use=[condition('self_mana_pct_lte', value=20)], desired_toggle_state='0'), 'Mana-draining toggle: disable at or below 20% self mana. This is a separate rule and is not AND-ed with the on conditions.'),
}

# Optional charge-aware variants require explicit native charge metadata. The
# omitted action_id deliberately means the current rule's resolved native action.
for base_name, (base_rule, base_rationale) in list(FAMILIES.items()):
    if base_name.startswith('toggle_') or base_name.endswith('_off'):
        continue
    charged = json.loads(json.dumps(base_rule))
    if len(charged['use_conditions']) < 4:
        charged['use_conditions'].append(condition('ability_charges_gte', value=1))
        FAMILIES['charged_' + base_name] = (charged, base_rationale + ' Optional variant also requires at least one observed native charge.')

# Explicit per-ID semantic review. These lists are intentionally auditable, not
# translated-description keyword classifiers. Native order/team checks below
# prevent the chosen semantic mode from silently overriding incompatible flags.
REVIEW = {}
def assign(family, names):
    for name in names.split():
        if name in REVIEW:
            raise ValueError('duplicate review: ' + name)
        REVIEW[name] = family

assign('healing_ally', '''abaddon_death_coil omniknight_purification dazzle_shadow_wave warlock_shadow_word winter_wyvern_cold_embrace huskar_inner_vitality undying_soul_rip''')
assign('healing_self', '''enchantress_natures_attendants necrolyte_death_pulse meepo_petrify chen_hand_of_god''')
assign('healing_area', '''juggernaut_healing_ward oracle_rain_of_destiny''')
assign('protection_ally', '''abaddon_aphotic_shield antimage_counterspell_ally dazzle_shallow_grave oracle_false_promise tinker_defense_matrix lich_frost_shield lich_frost_armor treant_living_armor omniknight_repel ringmaster_the_box ringmaster_strongman_tonic ogre_magi_frost_armor''')
assign('protection_self', '''antimage_counterspell abaddon_borrowed_time puck_phase_shift templar_assassin_refraction templar_assassin_meld necrolyte_ghost_shroud nyx_assassin_spiked_carapace slark_shadow_dance slark_depth_shroud slark_dark_pact ursa_enrage life_stealer_rage life_stealer_unfettered tidehunter_kraken_shell windrunner_windrun phantom_assassin_blur dark_willow_shadow_realm ember_spirit_flame_guard pudge_flesh_heap spirit_breaker_bulldoze witch_doctor_voodoo_switcheroo pangolier_rollup omniknight_guardian_angel sven_warcry''')
assign('time_walk_recovery', 'faceless_void_time_walk')
assign('gapclose', '''antimage_blink queenofpain_blink phantom_assassin_phantom_strike riki_blink_strike chaos_knight_reality_rift huskar_life_break spirit_breaker_charge_of_darkness spirit_breaker_nether_strike storm_spirit_ball_lightning morphling_waveform sandking_burrowstrike void_spirit_astral_step''')
assign('summon', '''lycan_summon_wolves invoker_forge_spirit invoker_forge_spirit_ad beastmaster_summon_razorback beastmaster_summon_raptor beastmaster_call_of_the_wild enigma_demonic_conversion venomancer_plague_ward shadow_shaman_mass_serpent_ward shadow_shaman_urnaconda warlock_rain_of_chaos visage_summon_familiars lone_druid_spirit_bear terrorblade_conjure_image chaos_knight_phantasm naga_siren_mirror_image undying_tombstone pugna_nether_ward clinkz_burning_army tinker_deploy_turrets zuus_cloud brewmaster_primal_companion arc_warden_tempest_double tusk_frozen_sigil furion_summon_fey''')
assign('self_combat_buff', '''sven_gods_strength dragon_knight_elder_dragon_form lycan_shapeshift lycan_howl death_prophet_exorcism razor_eye_of_the_storm alchemist_chemical_rage earthshaker_enchant_totem ursa_overpower troll_warlord_battle_trance troll_warlord_rampage clinkz_strafe clinkz_wind_walk clinkz_scepter sniper_take_aim gyrocopter_flak_cannon broodmother_insatiable_hunger night_stalker_darkness night_stalker_crippling_fear bounty_hunter_wind_walk weaver_shukuchi invoker_ghost_walk invoker_ghost_walk_ad invoker_ice_wall invoker_ice_wall_ad brewmaster_primal_split lone_druid_true_form lone_druid_rabid lone_druid_true_form_battle_cry undying_flesh_golem terrorblade_metamorphosis terrorblade_demon_zeal muerta_pierce_the_veil marci_unleash winter_wyvern_arctic_burn snapfire_lil_shredder wisp_overcharge wisp_spirits medusa_stone_gaze slardar_sprint rattletrap_overclocking rattletrap_jetpack jakiro_ice_path_detonate mirana_invis mirana_solar_flare lina_flame_cloak nevermore_frenzy visage_silent_as_the_grave hoodwink_scurry phoenix_fire_spirits keeper_of_the_light_spirit_form kez_raptor_dance kez_falcon_rush kez_ravens_veil kez_falcon_rush_ad kez_ravens_veil_ad''')
assign('mana_restore', 'keeper_of_the_light_chakra_magic')
assign('mana_attack', 'lion_mana_drain nyx_assassin_mana_burn')
assign('execute', 'axe_culling_blade necrolyte_reapers_scythe antimage_mana_void')
assign('dispel_control', 'legion_commander_press_the_attack shadow_demon_demonic_cleanse')
assign('toggle_on', 'leshrac_pulse_nova')
assign('healing_toggle_on', 'witch_doctor_voodoo_restoration')
assign('protection_area', 'arc_warden_magnetic_field')
assign('protection_self', 'obsidian_destroyer_objurgation')
assign('toggle_combat_on', 'pudge_rot medusa_split_shot bloodseeker_blood_mist zuus_lightning_hands')
assign('protection_ally', 'spirit_breaker_planar_pocket')
assign('offensive_unit', 'mirana_celestial_quiver')
assign('ally_combat_buff', '''dark_seer_surge dark_seer_ion_shell bounty_hunter_wind_walk_ally chen_divine_favor alchemist_berserk_potion invoker_alacrity invoker_alacrity_ad lycan_wolf_bite ogre_magi_bloodlust grimstroke_spirit_walk largo_croak_of_genius''')
assign('teammate_buff', '''magnataur_empower marci_bodyguard''')
assign('protection_ally', '''omniknight_martyr ogre_magi_smash centaur_mount techies_reactive_tazer''')
assign('healing_ally', 'chen_test_of_faith')
assign('protection_self', '''nyx_assassin_burrow rubick_null_field naga_siren_song_of_the_siren phoenix_supernova ringmaster_funhouse_mirror hoodwink_decoy''')
assign('self_combat_buff', '''bloodseeker_bloodrage drow_ranger_glacier storm_spirit_electric_rave lich_dark_sorcery luna_lunar_orbit luna_lunar_grace spirit_breaker_empowering_haste lycan_summon_wolves_hightail brewmaster_storm_wind_walk treant_super_bloom nyx_assassin_vendetta tusk_tag_team elder_titan_fundamental_fury elder_titan_fundamental_fury_spirit''')
assign('offensive_point', '''drow_ranger_wave_of_silence drow_ranger_silence riki_smoke_screen faceless_void_chronosphere death_prophet_silence dazzle_weave meepo_earthbind disruptor_kinetic_field techies_stasis_trap terrorblade_reflection invoker_chaos_meteor_ad invoker_deafening_blast_ad invoker_emp_ad invoker_sun_strike_ad invoker_tornado_ad''')
assign('offensive_unit', '''bane_nightmare doom_bringer_doom pugna_life_drain shadow_demon_disseminate winter_wyvern_splinter_blast oracle_fortunes_end invoker_cold_snap_ad kez_talon_toss_ad''')
assign('offensive_no_target', '''razor_plasma_field sandking_sand_storm sandking_epicenter storm_spirit_static_remnant venomancer_poison_nova leshrac_greater_lightning_storm brewmaster_void_astral_pulse lone_druid_savage_roar lone_druid_savage_roar_bear dark_willow_bedlam kez_echo_slash juggernaut_trinity juggernaut_vaulted_strike''')
assign('summon', 'lich_ice_spire')
assign('offensive_no_target', '''axe_berserkers_call earthshaker_echo_slam slardar_slithereen_crush tidehunter_ravage tidehunter_anchor_smash centaur_hoof_stomp magnataur_reverse_polarity nevermore_requiem nevermore_shadowraze1 nevermore_shadowraze2 nevermore_shadowraze3 mirana_starfall queenofpain_scream_of_pain juggernaut_blade_fury rattletrap_battery_assault rattletrap_power_cogs gyrocopter_rocket_barrage bristleback_quill_spray shredder_whirling_death elder_titan_echo_stomp elder_titan_echo_stomp_spirit ember_spirit_searing_chains phantom_assassin_fan_of_knives luna_eclipse silencer_global_silence zuus_thundergods_wrath spectre_haunt brewmaster_thunder_clap primal_beast_trample''')

assign('offensive_unit', 'lone_druid_spirit_bear_fetch')
assign('offensive_point', 'treant_natures_grasp keeper_of_the_light_illuminate')
assign('offensive_vector', 'muerta_dead_shot')

# These are semantic reviews of basic native startup, not special conditions.
# Other vectors need a separate review: damage metadata alone cannot establish
# that placing the start on an enemy and continuing away is a useful cast.
BASIC_NATIVE_REVIEW = {
    'muerta_dead_shot': 'Ordinary hostile unit first hit damages/slows the nearest legal enemy; the fixed continuation does not promise ricochet damage or fear.',
    'keeper_of_the_light_illuminate': 'Ordinary point channel startup sends a damaging wave toward the nearest legal enemy; native channel completion owns release, with no timer or premature cancellation.',
}


def split_flags(value):
    return [x.strip() for x in str(value or '').split('|') if x.strip()]

def import_rows(directory):
    raw_path = directory / 'rpg_hero_catalog_data.json'
    rows_path = directory / 'rpg_catalog_rows.json'
    raw = json.loads(raw_path.read_text(encoding='utf-8'))
    old = json.loads(rows_path.read_text(encoding='utf-8'))
    localization = {path.lower(): {key.lower(): value for key, value in tokens.items()}
                    for path, tokens in raw['loc'].items()}
    english = localization['resource/localization/abilities_english.txt']
    chinese = localization['resource/localization/abilities_schinese.txt']
    result = []
    for source in old:
        name, hero = source['id'], source['hero']
        kv = raw['heroes'][hero]['DOTAAbilities'][name]
        result.append(dict(id=name, hero=hero, name=source['name'], name_en=english.get(('DOTA_Tooltip_ability_' + name).lower(), name),
            description_en=english.get(('DOTA_Tooltip_ability_' + name + '_Description').lower(), ''),
            description_cn=chinese.get(('DOTA_Tooltip_ability_' + name + '_Description').lower(), ''),
            base_description_en=english.get(('DOTA_Tooltip_ability_' + kv.get('BaseClass', name) + '_Description').lower(), ''),
            native=dict(definition=kv, source_path='scripts/npc/heroes/' + hero + '.txt', behavior_raw=kv.get('AbilityBehavior', ''),
                behavior_flags=split_flags(kv.get('AbilityBehavior')), target_team=kv.get('AbilityUnitTargetTeam', ''),
                target_types=split_flags(kv.get('AbilityUnitTargetType')), target_flags=split_flags(kv.get('AbilityUnitTargetFlags')),
                damage_type=kv.get('AbilityUnitDamageType', ''), value_keys=sorted(kv.get('AbilityValues', {})),
                cast_range=kv.get('AbilityCastRange', ''), channel_time=kv.get('AbilityChannelTime', ''),
                charges=kv.get('AbilityCharges', ''), ability_type=kv.get('AbilityType', ''))))
    return result, {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (raw_path, rows_path)}



REASONS = {
    'passive': 'Native PASSIVE; retained outside the active denominator.',
    'unique_mechanism': '未实现：专属机制仅记录，不提供专属预设或程序。',
    'semantic_review_needed': 'No reviewed useful generic trigger established.',
    'incompatible_review': 'Generic semantic review conflicts with native flags.',
}


def classify(row):
    n, name = row['native'], row['id']
    flags = {x.removeprefix('DOTA_ABILITY_BEHAVIOR_') for x in n['behavior_flags']}
    team, targets = n['target_team'], n['target_types']
    inventory = row['unique_mechanism']
    vector = 'VECTOR_TARGETING' in flags
    ordinary_unit = 'UNIT_TARGET' in flags and any(t.endswith(('_HERO', '_BASIC', '_CREEP', '_ALL')) for t in targets)
    basic_review = name in BASIC_NATIVE_REVIEW and bool(row.get('description_en')) and (
        (vector and REVIEW.get(name) == 'offensive_vector' and 'ENEMY' in team and ordinary_unit) or
        (not vector and 'CHANNELLED' in flags and 'POINT' in flags and REVIEW.get(name) == 'offensive_point'))
    if name in BASIC_NATIVE_REVIEW:
        inventory['excluded_from_presets'] = not basic_review
    special_native = ((vector and not basic_review) or 'HIDDEN' in flags or
        (any('TREE' in t for t in targets) and 'POINT' not in flags and
         not any(t.endswith(('_HERO', '_BASIC', '_CREEP', '_ALL')) for t in targets)) or
        (bool(targets) and all('RUNE' in t for t in targets)) or
        not flags.intersection({'UNIT_TARGET', 'POINT', 'NO_TARGET', 'TOGGLE', 'PASSIVE'}))
    child = (name.endswith(('_stop', '_cancel', '_release', '_destroy', '_end', '_crack', '_early', '_return'))
             or '_cancel_' in name) and name != 'oracle_fortunes_end'
    if special_native or child:
        inventory['excluded_from_presets'] = True
        if not inventory['mechanisms']:
            inventory.update(status='未实现', categories=['native_special_contract'], mechanisms=[dict(
                category='native_special_contract', status='未实现',
                mechanism_cn=row.get('description_cn') or '特殊原生动作或子技能',
                mechanism_en=row.get('description_en') or 'Special native action or child ability.',
                missing_capability='专用目标、动作入口或阶段状态契约。')])
    family, reason, evidence = None, None, []
    if 'PASSIVE' in flags:
        reason = 'passive'
    elif inventory['excluded_from_presets']:
        reason = 'unique_mechanism'
    elif name in REVIEW:
        family = REVIEW[name]
        evidence = ['Explicit ordinary semantic review; generic conditions only.']
        if basic_review:
            evidence.append(BASIC_NATIVE_REVIEW[name])
        if family in {'healing_ally', 'protection_ally', 'mana_restore', 'dispel_control'} and (
                'UNIT_TARGET' not in flags or not any(t in team for t in ('FRIENDLY', 'BOTH'))):
            family, reason = None, 'incompatible_review'
    elif 'UNIT_TARGET' in flags and 'ENEMY' in team and any(t.endswith(('_HERO', '_BASIC', '_CREEP', '_ALL')) for t in targets):
        family, evidence = 'offensive_unit', ['Native hostile ordinary unit target.']
    elif 'POINT' in flags and ('ENEMY' in team or n['damage_type'] not in ('', 'DAMAGE_TYPE_NONE')):
        family, evidence = 'offensive_point', ['Native point order and hostile team or damage metadata.']
    elif 'NO_TARGET' in flags and 'TOGGLE' not in flags and n['damage_type'] not in ('', 'DAMAGE_TYPE_NONE') and any(
            k in n['value_keys'] for k in ('damage', 'damage_per_second', 'base_damage', 'impact_damage', 'stomp_damage', 'damage_per_tick')):
        family, evidence = 'offensive_no_target', ['Native no-target damage keys.']
    else:
        reason = 'semantic_review_needed'
    if family in {'offensive_point', 'offensive_unit', 'offensive_no_target'} and 'AOE' in flags and 'DIRECTIONAL' not in flags:
        family = 'aoe'
        evidence.append('Native AOE radius required; circular approximation only.')
    variants = [family] if family else []
    if name == 'faceless_void_time_walk' and family == 'time_walk_recovery':
        variants.append('gapclose')
    if family in {'toggle_on', 'healing_toggle_on'}:
        variants.append('toggle_off')
    if family == 'toggle_combat_on':
        variants.extend(['toggle_health_off', 'toggle_idle_off'])
    if family and (n['charges'] or 'AbilityCharges' in n['value_keys']) and 'charged_' + family in FAMILIES:
        variants.append('charged_' + family)
    inventory['basic_native_mode'] = ('vector' if vector else 'channel_startup') if family and (vector or 'CHANNELLED' in flags) else None
    inventory['basic_native_note'] = (
        'native vector基础已实现：最近合法敌方锚点，沿施法者到锚点方向延长150；专属几何/弹射/落点程序未实现。'
        if family and vector else
        '普通引导启动已实现：通用条件及原生合法性检查，启动后busy阻止新指令；定时释放/提前取消/专属调度未实现。'
        if family and 'CHANNELLED' in flags else None)
    row.update(active='PASSIVE' not in flags, expression_covered=bool(family), family=family,
        preset_variants=variants, unsupported_reason=reason, evidence=evidence,
        rationale=FAMILIES[family][1] if family else REASONS[reason],
        review_note='Ordinary generic partial mode only.' if name in REVIEW and family else None,
        reviewed_family=family, implementation_gaps=[],
        execution_caveats=['Generic expression coverage only; native execution validated: 0.',
            'Native availability, legality, range, mana and cooldown still apply.',
            'All recorded unique mechanisms are 未实现; generic conditions do not implement their state or scheduling.',
            'Thresholds do not predict trajectories, lethal damage, safe landing or channel completion.'])
    return row


def escape(value):
    return str(value or '').strip().replace('|', '&#124;').replace(chr(13), '').replace(chr(10), '<br>')


def artifacts(rows, hashes):
    retained = json.loads(DATA.read_text(encoding='utf-8'))
    inventory = {r['id']: r for r in retained['rows']}
    for row in rows:
        saved = inventory.get(row['id'])
        if saved is None:
            raise ValueError('Missing per-ID mechanism inventory: ' + row['id'])
        for key in ('catalog', 'unique_mechanism'):
            if key not in row:
                row[key] = json.loads(json.dumps(saved[key]))
    for row in rows:
        for mechanism in row['unique_mechanism']['mechanisms']:
            if mechanism['category'] == 'G20':
                mechanism['missing_capability'] = 'native vector基础已实现；专属起点/终点/朝向选择、双目标几何、落点及后续程序未实现，固定最近锚点方向不等于这些设计能力。'
            elif mechanism['category'] == 'G10':
                mechanism['missing_capability'] = '普通引导原生启动及busy保护已实现；专属释放时机、最小引导、危险打断、目标离开时中止和阶段调度未实现。'
    rows = [classify(r) for r in rows]
    assert len(rows) == len({r['id'] for r in rows}) == 1095
    assert len({r['hero'] for r in rows}) == 127
    active = sum(r['active'] for r in rows)
    covered = sum(r['expression_covered'] for r in rows)
    assert active == 755 and len(rows) - active == 340
    retained['catalog_gap_definitions']['G20']['missing_capability'] = 'native vector基础已实现；专属起点/终点/朝向、双目标几何及落点程序未实现。'
    retained['catalog_gap_definitions']['G10']['missing_capability'] = '普通引导启动和busy保护已实现；定时释放、提前取消、危险打断和专属阶段程序未实现。'
    snapshot = dict(schema_version=2, native_snapshot=dict(client_version=6924, revision=10969619,
        heroes=127, baseline=1095, passive=340, active=755, source_sha256=hashes),
        coverage=dict(expression_covered=covered, active_denominator=755,
            expression_percent=round(covered / 755 * 100, 2), native_execution_validated=0,
            unique_excluded_active=sum(r['active'] and r['unique_mechanism']['excluded_from_presets'] for r in rows),
            definition='Reviewed generic partial triggers only; unique mechanisms deferred; no percentage target.'),
        catalog_gap_definitions=retained['catalog_gap_definitions'],
        pending_identity_evidence=retained['pending_identity_evidence'],
        families={k: dict(rule=v[0], rationale=v[1]) for k, v in FAMILIES.items()}, rows=rows)
    mapping = {r['id']: r['preset_variants'] for r in rows if r['expression_covered']}
    return render(snapshot, mapping)


PRESET_JS = """/* Generated generic data only. UI percentages: 0..100; toggle variants are separate rules.
 * No deferred rules, internal symbol allowlists, or orders. */
var RpgSkillPresets = (function () {
    "use strict";
    var families = %s;
    var mapping = %s;
    function has(object, key) { return typeof key === "string" && Object.prototype.hasOwnProperty.call(object, key); }
    function variants(name) { return has(mapping, name) ? mapping[name].slice() : []; }
    function get(name, variant) {
        if (!has(mapping, name)) { return null; }
        var selected = variant || mapping[name][0];
        return mapping[name].indexOf(selected) >= 0 ? JSON.parse(JSON.stringify(families[selected])) : null;
    }
    function unsupportedReason(name) {
        return has(mapping, name) ? null : "unsupported_ability: no generic preset; consult coverage inventory";
    }
    return {get: get, variants: variants, unsupportedReason: unsupportedReason};
}());
"""


def render(snapshot, mapping):
    rows = snapshot['rows']
    covered = snapshot['coverage']['expression_covered']
    presets = PRESET_JS % tuple(json.dumps(x, ensure_ascii=True, sort_keys=True, separators=(',', ':'))
        for x in ({k: v[0] for k, v in FAMILIES.items()}, mapping))
    lines = ['# 通用技能条件覆盖', '', '<!-- Generated by scripts/build-condition-coverage.py -->', '',
        f'**{covered}/755（{covered / 755 * 100:.2f}%）主动定义有通用局部条件预设。** 不设覆盖率目标，不以专属机制草稿增加分子。', '',
        '保留全部 **1,095** 个定义、**127** 位英雄、完整原生KV及中英文描述；**340** 个 PASSIVE 定义保留但不计入 **755** 主动分母。隐藏和旧版定义仍在分母中。原生执行实测 **0** 项；没有进行游戏内验证。', '',
        '仅实现通用伤害、治疗、保护、增益、基础接近/生命阈值、开关和邻近条件。充能变体观察当前技能，不引用另一个技能ID。普通语义逐ID复核只选择这些通用模板族。通用层数/剩余时间及普通归属条件可由玩家配置，但这里不内置技能专属配方。死亡队友数、自身力量/敏捷、召唤物数量、动作时间历史及目标幻象排除/小兵/无敌/标签条件不提供配置；无敌目标是否合法由原生目标标记与运行时检查决定。', '',
        '所有专属机制均在 [UNIQUE_SKILL_MECHANISMS.md](UNIQUE_SKILL_MECHANISMS.md) 和 JSON `unique_mechanism` 逐ID标为 **未实现**。普通技能可有一个通用模式，同时仍有未实现的专属扩展；`excluded_from_presets=true` 的专用动作完全不进入JS映射。G00–G21原始标签是设计库存，不是功能验收。', '',
        '阶段、释放、返回、目的地、法球组合、姿态切换、树木、专属矢量几何/朝向、专名单位资源及技能专属modifier/动作引用不提供可执行预设。原先SPECIAL缺口及后续AUDIT意见只作为历史复核证据保存在待实现记录，不代表当前已支持。', '',
        '**native vector基础已实现**：普通最近合法敌方锚点，点矢量起点取锚点位置，单位矢量主目标取该单位；终点沿施法者到锚点方向延长150，零长度失败。运行时按原生范围/过滤器检查并发送两条原生命令；预设不含矢量参数。仅逐ID确认描述适合此模式的定义计入覆盖，复杂落点、观察方向、布线和原型继续延期。', '',
        '**普通CHANNELLED启动已实现**：单位、点或无目标技能使用通用条件与原生启动检查；引导期间busy阻止新指令。原生技能负责持续和结束，无释放计时器或提前取消预设；特殊资源/阶段依赖仍延期。上述为代码契约，游戏内实测仍为0。', '',
        '`RpgSkillPresets.get(id[, variant])` 返回独立草稿；不支持时返回 `null`，`variants` 返回空数组。`unsupportedReason` 只返回通用提示；详细排除原因仅在文档/JSON。JS仅包含通用模板族与支持映射，不包含待实现规则。', '',
        'UI百分比0—100经实际JS wire转换一次为Lua的0—1；时间为秒、距离为世界单位。开关开启/关闭分别配置规则。圆形AOE使用原生半径，未知半径不能宣称命中。条件表达不保证施法成功、击杀、位移安全或引导完成。UI实现说明由独立主文档负责。', '',
        '复现：`python scripts/build-condition-coverage.py --check`；验证：`python tests/condition-coverage.test.py`。默认只读取入库快照；`--source-dir`以大小写不敏感的路径/token读取原始两份提取JSON，保留所有原生定义并合并入库机制库存。', '',
        '## 通用默认模板统计', '', '| 模板族 | 主动定义数 |', '|---|---:|']
    for family, count in sorted(Counter(r['family'] for r in rows if r['family']).items()):
        lines.append(f'| {family} | {count} |')
    lines += ['', '## 未覆盖主动定义', '', '| ID | 原因 |', '|---|---|']
    for r in rows:
        if r['active'] and not r['expression_covered']:
            lines.append(f"| `{r['id']}` | {r['unsupported_reason']}: {escape(r['rationale'])} |")
    unique = ['# 原生技能专属机制历史设计库存', '',
        '<!-- Generated by scripts/build-condition-coverage.py -->', '',
        '全部1,095个原生定义的历史设计库存，保留G00–G21原始标签、原生标记、中英文机制描述及当时的缺口。条目内的“未实现”是原始库存状态，不能用来统计当前游戏缺失功能或缺少条件的英雄数。最新取舍与实现见 [v19 简化特殊机制与英雄池](RUNTIME_FIXES_V19.md)：固定装置及吞噬/劝化使用普通条件；抓树自动处理；投掷新增抓取条件；残焰/游魂支持目的地；召唤物采用固定行为。土猫、卡尔、拉比克、凯暂不进入游戏池。普通通用模式不表示全部原生专属机制已重现；无描述条目保留缺失，不猜造语义。', '',
        'native vector基础已实现：最近合法锚点及固定延长150的原生双命令；普通CHANNELLED启动与busy保护已实现。它们不实现G20专属几何/双目标选择，也不实现G10定时释放/提前取消。逐ID基础模式另列，原始缺口标签保留作设计库存，不能理解为基础原生命令也全部缺失。游戏内执行实测0。', '',
        '## 原始缺口标签', '', '| 标签 | 机制 | 待具备能力（设计范围） |', '|---|---|---|']
    for tag, definition in snapshot['catalog_gap_definitions'].items():
        unique.append(f"| {tag} | {escape(definition['name_cn'])} | {escape(definition['missing_capability'])} |")
    for r in rows:
        u, n = r['unique_mechanism'], r['native']
        missing = '；'.join(escape(m['missing_capability']) for m in u['mechanisms']) or '没有额外专属状态机复核结论；原始标签对应的设计能力未逐项实现或验收。'
        unique += ['', f"## `{r['id']}` — {r['name']} / {r['name_en']}", '',
            '**专属机制状态：未实现。** ' + ('专用动作排除全部预设。' if u['excluded_from_presets'] else '仅可采用独立通用模式（如有）；不含专属调度。'), '',
            '原始标签：' + ', '.join(r['catalog']['gaps']) + '；机制标签：' + escape(r['catalog']['tags']), '',
            'Native flags: `' + n['behavior_raw'] + '`; team: `' + n['target_team'] + '`; types: `' + ' | '.join(n['target_types']) + '`; target flags: `' + ' | '.join(n['target_flags']) + '`.', '',
            '中文机制：' + escape(r.get('description_cn') or r['catalog']['summary'] or '当前ID中文描述缺失。'), '',
            'English mechanism: ' + escape(r.get('description_en') or r.get('base_description_en') or 'No English description in this snapshot.'), '',
            '缺失能力：' + missing]
        if u.get('basic_native_note'):
            unique += ['', '基础通用模式：' + escape(u['basic_native_note'])]
        if u.get('previous_review_note'):
            unique += ['', '历史复核（当前未实现）：' + escape(u['previous_review_note'])]
    return {DATA: json.dumps(snapshot, ensure_ascii=False, indent=2, sort_keys=True) + '\n', JS: presets,
            DOC: '\n'.join(lines) + '\n', UNIQUE_DOC: '\n'.join(unique) + '\n'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.source_dir:
        rows, hashes = import_rows(args.source_dir)
    else:
        data = json.loads(DATA.read_text(encoding='utf-8'))
        rows, hashes = data['rows'], data['native_snapshot']['source_sha256']
    outputs = artifacts(rows, hashes)
    for path, content in outputs.items():
        if args.check:
            if not path.exists() or path.read_text(encoding='utf-8') != content:
                raise SystemExit('Out of date: ' + str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding='utf-8', newline='\n')
    print(json.loads(outputs[DATA])['coverage'])


if __name__ == '__main__':
    main()
