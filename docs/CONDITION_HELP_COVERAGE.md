# Condition help coverage / 条件教程覆盖

沿用 [docs/UNIQUE_SKILL_MECHANISMS.md](UNIQUE_SKILL_MECHANISMS.md) 的 G00–G21 **22 类**；排除 G14 纯被动后 **21 类**主动设置主题。已有基础教程 **17/21 = 80.95%**，落在用户要求的约80–90%范围。共 26 个浏览章节，章节与机制类型并非一一对应。

类型教学覆盖的判定：该历史主题至少有一份当前可照填的基础设置或配置流程，列出实例与限制。分类原本就可重叠；一个技能可参考多页。它不表示实现该历史标签列出的所有高级诉求，也不是全技能ID覆盖率或实机通过率。G18、G19、G20、G21未计入：普通矢量首击说明也不等于G20专属双点几何。

## Historical type mapping / 历史类型映射

| 类型 | 主题 | 本次基础教学 | 对应章节 |
|---|---|---|---|
| G00 | 完整合法目标 | basic_tutorial | single_target |
| G01 | 目标低血、治疗/护盾/救援 | basic_tutorial | healing, protection |
| G02 | 范围人数与范围收益 | basic_tutorial | area |
| G03 | 控制、打断、驱散、免疫 | basic_tutorial | single_target, dispel |
| G04 | 斩杀与伤害收益 | basic_tutorial | finisher |
| G05 | 自动施法、开关、持续耗蓝 | basic_tutorial | toggle |
| G06 | 连招、先后顺序和共享状态 | basic_tutorial | combo |
| G07 | 位移方向、落点和运动预判 | basic_tutorial | movement, persistent_movement |
| G08 | 召唤物、分身、支配、多单位 | basic_tutorial | summon |
| G09 | 标记、层数、剩余持续时间 | basic_tutorial | buff_state |
| G10 | 持续施法、蓄力与中止 | basic_tutorial | channel |
| G11 | 全图、视野、传送和远距目标 | basic_tutorial | global |
| G12 | 充能及特殊资源 | basic_tutorial | charges |
| G13 | 树、建筑、尸体、装置等对象 | basic_tutorial | special_objects |
| G14 | 纯被动观察（可包含先天） | excluded_passive | — |
| G15 | 神杖/魔晶/命石/形态/额外技能 | basic_tutorial | upgrades |
| G16 | 友军误伤、交换、献血等风险 | basic_tutorial | risk |
| G17 | 敌友两用、自施放、替代施放 | basic_tutorial | dual_target |
| G18 | 再次释放、返回、终止、子技能 | deferred | — |
| G19 | 普攻附魔和攻击时机 | deferred | — |
| G20 | 矢量/双点/双目标 | deferred | — |
| G21 | 英雄特有机制 | deferred | — |

G09说明有无/层数/剩余时间及OR拆行；G11用存活敌人数代替附近门槛；G13只教已实现的小小抓取/落点并说明自动抓树；G15教升级后新增技能单独配置与重新检查范围；G16只教自损技能的自身血量下限；G17用迷雾缠绕分别配置敌友两条规则。这些基础流程不声称预测伤害、传送落点、对象全覆盖、自动形态规划或友军误伤收益。

## Per-ID audit / 逐技能审查口径

Source: `data/native_skill_conditions.json`. SHA-256: `ae5fbdf964b472ab1248d8159f380dfcc9e0179371161ad09ddf93bd7f4d683b`.

原始 1095 行；主动分母 **755**；排除被动 340。按 `active` 保留旧版、升级、隐藏与子技能，不以常用程度缩小分母。

逐ID已审查基础模式映射 **439/755 = 58.15%**；已有一键预设 **439/755 = 58.15%**。只按已审查family映射，不将新增专题的示例直接加入分子；特殊对象等未在快照中复核的ID也不因教程提到就自动改成已审查。

快照原生实机验证数：**0**。本任务没有运行Dota，不更改条件实现或现有预设。

## Evidence / 证据与限制

`condition_catalog.js` and `condition_registry.lua` expose health, counts, timing and modifier conditions. `tests/condition-v2.test.lua` covers modifier presence/stacks/duration; `target_selector.lua` applies legality and ordering. `docs/RUNTIME_FIXES_V19.md` and `tests/condition-specials.test.lua` describe and exercise Tiny grab/landing contracts. `tests/action-success-chain.test.lua` exercises Blink → Blade Mail → Call. `tests/marci-targets.test.lua` covers native-target mocks and teammate preferences. `docs/CONDITION_LIST_ZH.md` defines UI units and condition meanings. Mist Coil’s snapshot description and BOTH target team support the self-cost and dual-team examples. Upgrade teaching only explains separate rules for newly available abilities; it does not claim automatic upgrade detection or special form logic. Native execution is still distinct from these offline checks.

## Category counts / 类别统计

| ID | 中文用途 | Audited IDs | Existing presets | Role |
|---|---|---:|---:|---|
| single_target | 单体伤害与控制 | 114 | 114 | primary |
| point | 地点伤害与区域控制 | 37 | 37 | primary |
| area | 范围伤害与控制 | 85 | 85 | primary |
| no_target | 无目标战斗技能 | 48 | 48 | primary |
| healing | 治疗友方与自身 | 13 | 13 | primary |
| protection | 保护与护盾 | 39 | 39 | primary |
| ally_buff | 友方增益 | 8 | 8 | primary |
| self_buff | 自身增益与变身启动 | 50 | 50 | primary |
| movement | 位移接近敌人 | 12 | 12 | primary |
| summon | 召唤与部署 | 18 | 18 | primary |
| mana | 回蓝与消耗敌方魔法 | 3 | 3 | primary |
| finisher | 低血量收割 | 3 | 3 | primary |
| dispel | 解控与救援 | 2 | 2 | primary |
| toggle | 开关技能：分开开启和关闭 | 6 | 6 | primary |
| vector | 矢量基础施法 | 1 | 1 | primary |
| channel | 持续施法：启动与等待 | 0 | 0 | supplemental |
| charges | 充能：保留一层资源 | 0 | 0 | supplemental |
| persistent_movement | 持续移动：缩地与践踏 | 0 | 0 | supplemental |
| combo | 连招：跳刀 → 刃甲 → 吼 | 0 | 0 | supplemental |
| buff_state | 增益、层数与剩余时间 | 0 | 0 | supplemental |
| global | 全图与远距离技能 | 0 | 0 | supplemental |
| special_objects | 抓取对象与投掷落点 | 0 | 0 | supplemental |
| upgrades | 升级、形态与新增技能 | 0 | 0 | supplemental |
| risk | 消耗自身生命的技能 | 0 | 0 | supplemental |
| dual_target | 同一技能治疗友方、伤害敌方 | 0 | 0 | supplemental |
| special | 特殊技能与未覆盖范围 | 0 | 0 | supplemental |

Supplemental pages overlap primary abilities or explain limitations; do not sum example counts. Supplemental `has_preset=false` refers to the additional workflow, while `examples[].has_preset` refers to the example ability’s basic preset.

## Uncovered active IDs / 未覆盖主动ID

| Native ability | Exclusion in snapshot |
|---|---|
| `antimage_mana_overload` | `unique_mechanism` |
| `bane_nightmare` | `unique_mechanism` |
| `bane_nightmare_end` | `unique_mechanism` |
| `crystal_maiden_crystal_clone` | `unique_mechanism` |
| `crystal_maiden_freezing_field_stop` | `unique_mechanism` |
| `crystal_maiden_let_it_go` | `unique_mechanism` |
| `mirana_leap` | `unique_mechanism` |
| `morphling_morph_agi` | `unique_mechanism` |
| `morphling_morph_str` | `unique_mechanism` |
| `morphling_replicate` | `unique_mechanism` |
| `morphling_morph_replicate` | `unique_mechanism` |
| `morphling_hybrid` | `unique_mechanism` |
| `morphling_syntropy` | `unique_mechanism` |
| `nevermore_shadowraze1` | `unique_mechanism` |
| `nevermore_shadowraze2` | `unique_mechanism` |
| `nevermore_shadowraze3` | `unique_mechanism` |
| `phantom_lancer_doppelwalk` | `unique_mechanism` |
| `phantom_lancer_phantom_edge` | `unique_mechanism` |
| `puck_illusory_orb` | `unique_mechanism` |
| `puck_ethereal_jaunt` | `unique_mechanism` |
| `pudge_eject` | `unique_mechanism` |
| `storm_spirit_electric_rave` | `unique_mechanism` |
| `tiny_toss` | `unique_mechanism` |
| `tiny_tree_grab` | `unique_mechanism` |
| `tiny_tree_channel` | `unique_mechanism` |
| `tiny_toss_tree` | `unique_mechanism` |
| `vengefulspirit_nether_swap` | `unique_mechanism` |
| `windrunner_gale_force` | `unique_mechanism` |
| `windrunner_focusfire_cancel` | `unique_mechanism` |
| `zuus_cloud` | `unique_mechanism` |
| `kunkka_x_marks_the_spot` | `unique_mechanism` |
| `kunkka_tidal_wave` | `unique_mechanism` |
| `kunkka_return` | `unique_mechanism` |
| `kunkka_torrent_storm` | `unique_mechanism` |
| `shadow_shaman_serpentine` | `unique_mechanism` |
| `slardar_scepter` | `unique_mechanism` |
| `witch_doctor_voodoo_switcheroo` | `unique_mechanism` |
| `lich_ice_spire` | `unique_mechanism` |
| `lich_death_charge` | `unique_mechanism` |
| `riki_poison_dart` | `unique_mechanism` |
| `tinker_warp_grenade` | `unique_mechanism` |
| `tinker_keen_teleport` | `unique_mechanism` |
| `tinker_rearm` | `unique_mechanism` |
| `tinker_heat_seeking_missile` | `unique_mechanism` |
| `tinker_shrink_ray` | `unique_mechanism` |
| `sniper_take_aim_stop` | `unique_mechanism` |
| `necrolyte_death_seeker` | `unique_mechanism` |
| `necrolyte_sadist_stop` | `unique_mechanism` |
| `beastmaster_hawk_perch` | `unique_mechanism` |
| `beastmaster_mark_of_the_beast` | `unique_mechanism` |
| `venomancer_area_poison` | `unique_mechanism` |
| `faceless_void_time_walk_reverse` | `unique_mechanism` |
| `faceless_void_time_zone` | `unique_mechanism` |
| `skeleton_king_bone_guard` | `unique_mechanism` |
| `skeleton_king_reincarnation` | `unique_mechanism` |
| `phantom_assassin_fan_of_knives` | `unique_mechanism` |
| `pugna_decrepify` | `unique_mechanism` |
| `templar_assassin_trap` | `unique_mechanism` |
| `templar_assassin_trap_teleport` | `unique_mechanism` |
| `templar_assassin_psionic_trap` | `unique_mechanism` |
| `templar_assassin_hidden_gates` | `unique_mechanism` |
| `templar_assassin_meditation_end` | `unique_mechanism` |
| `templar_assassin_self_trap` | `unique_mechanism` |
| `dragon_knight_fireball` | `unique_mechanism` |
| `dazzle_nothl_projection` | `unique_mechanism` |
| `dazzle_nothl_projection_end` | `unique_mechanism` |
| `dazzle_bad_juju` | `unique_mechanism` |
| `dazzle_rain_of_vermin` | `unique_mechanism` |
| `rattletrap_overclocking` | `unique_mechanism` |
| `rattletrap_jetpack` | `unique_mechanism` |
| `rattletrap_jetpack_toggle` | `unique_mechanism` |
| `leshrac_greater_lightning_storm` | `unique_mechanism` |
| `furion_teleportation` | `unique_mechanism` |
| `furion_force_of_nature` | `unique_mechanism` |
| `furion_curse_of_the_forest` | `unique_mechanism` |
| `furion_arboreal_might` | `unique_mechanism` |
| `furion_greater_sprout` | `unique_mechanism` |
| `furion_summon_fey` | `unique_mechanism` |
| `life_stealer_infest` | `unique_mechanism` |
| `life_stealer_consume` | `unique_mechanism` |
| `life_stealer_assimilate` | `unique_mechanism` |
| `life_stealer_assimilate_eject` | `unique_mechanism` |
| `life_stealer_control` | `unique_mechanism` |
| `dark_seer_wall_of_replica` | `unique_mechanism` |
| `clinkz_death_pact` | `unique_mechanism` |
| `clinkz_burning_army` | `unique_mechanism` |
| `clinkz_scepter` | `unique_mechanism` |
| `omniknight_angelic_flight` | `unique_mechanism` |
| `enchantress_enchant` | `unique_mechanism` |
| `enchantress_bunny_hop` | `unique_mechanism` |
| `broodmother_spin_web` | `unique_mechanism` |
| `broodmother_sticky_snare` | `unique_mechanism` |
| `broodmother_spin_web_destroy` | `unique_mechanism` |
| `bounty_hunter_lookout` | `unique_mechanism` |
| `weaver_time_lapse` | `unique_mechanism` |
| `jakiro_liquid_fire` | `unique_mechanism` |
| `jakiro_liquid_ice` | `unique_mechanism` |
| `jakiro_ice_path_detonate` | `unique_mechanism` |
| `batrider_sticky_napalm_application_damage` | `unique_mechanism` |
| `chen_holy_persuasion` | `unique_mechanism` |
| `chen_zealot` | `unique_mechanism` |
| `chen_innate_check_for_team_change` | `unique_mechanism` |
| `chen_martyrdom` | `unique_mechanism` |
| `chen_test_of_faith_teleport` | `unique_mechanism` |
| `spectre_shadow_step` | `unique_mechanism` |
| `spectre_reality` | `unique_mechanism` |
| `spectre_haunt` | `unique_mechanism` |
| `ancient_apparition_ice_blast` | `unique_mechanism` |
| `ancient_apparition_ice_blast_release` | `unique_mechanism` |
| `doom_bringer_devour` | `unique_mechanism` |
| `ursa_earthshock` | `unique_mechanism` |
| `gyrocopter_lock_on` | `unique_mechanism` |
| `alchemist_unstable_concoction` | `unique_mechanism` |
| `alchemist_berserk_potion` | `unique_mechanism` |
| `alchemist_unstable_concoction_throw` | `unique_mechanism` |
| `invoker_quas` | `unique_mechanism` |
| `invoker_wex` | `unique_mechanism` |
| `invoker_exort` | `unique_mechanism` |
| `invoker_invoke` | `unique_mechanism` |
| `invoker_cold_snap` | `unique_mechanism` |
| `invoker_ghost_walk` | `unique_mechanism` |
| `invoker_tornado` | `unique_mechanism` |
| `invoker_emp` | `unique_mechanism` |
| `invoker_alacrity` | `unique_mechanism` |
| `invoker_chaos_meteor` | `unique_mechanism` |
| `invoker_sun_strike` | `unique_mechanism` |
| `invoker_forge_spirit` | `unique_mechanism` |
| `invoker_ice_wall` | `unique_mechanism` |
| `invoker_deafening_blast` | `unique_mechanism` |
| `invoker_alacrity_ad` | `unique_mechanism` |
| `invoker_chaos_meteor_ad` | `unique_mechanism` |
| `invoker_cold_snap_ad` | `unique_mechanism` |
| `invoker_deafening_blast_ad` | `unique_mechanism` |
| `invoker_emp_ad` | `unique_mechanism` |
| `invoker_forge_spirit_ad` | `unique_mechanism` |
| `invoker_ghost_walk_ad` | `unique_mechanism` |
| `invoker_ice_wall_ad` | `unique_mechanism` |
| `invoker_sun_strike_ad` | `unique_mechanism` |
| `invoker_tornado_ad` | `unique_mechanism` |
| `lycan_wolf_bite` | `unique_mechanism` |
| `brewmaster_drunken_brawler` | `unique_mechanism` |
| `brewmaster_fire_pull` | `unique_mechanism` |
| `brewmaster_primal_split_cancel` | `unique_mechanism` |
| `shadow_demon_shadow_poison` | `unique_mechanism` |
| `shadow_demon_shadow_poison_release` | `unique_mechanism` |
| `lone_druid_spirit_bear_return` | `unique_mechanism` |
| `lone_druid_true_form_battle_cry` | `unique_mechanism` |
| `lone_druid_true_form_druid` | `unique_mechanism` |
| `meepo_poof` | `unique_mechanism` |
| `meepo_petrify` | `unique_mechanism` |
| `meepo_megameepo` | `unique_mechanism` |
| `meepo_megameepo_fling` | `unique_mechanism` |
| `meepo_fling` | `unique_mechanism` |
| `meepo_fling_release` | `unique_mechanism` |
| `treant_eyes_in_the_forest` | `unique_mechanism` |
| `treant_super_bloom` | `unique_mechanism` |
| `ogre_magi_unrefined_fireblast` | `unique_mechanism` |
| `ogre_magi_smash` | `unique_mechanism` |
| `undying_soul_rip` | `unique_mechanism` |
| `undying_tombstone_grab` | `unique_mechanism` |
| `undying_tombstone_unit_grab` | `unique_mechanism` |
| `rubick_spell_steal` | `unique_mechanism` |
| `rubick_telekinesis_land` | `unique_mechanism` |
| `rubick_hidden1` | `unique_mechanism` |
| `rubick_hidden2` | `unique_mechanism` |
| `rubick_telekinesis_land_self` | `unique_mechanism` |
| `rubick_hidden3` | `unique_mechanism` |
| `rubick_hidden4` | `unique_mechanism` |
| `rubick_hidden5` | `unique_mechanism` |
| `disruptor_kinetic_fence` | `unique_mechanism` |
| `nyx_assassin_burrow` | `unique_mechanism` |
| `nyx_assassin_unburrow` | `unique_mechanism` |
| `naga_siren_reel_in` | `unique_mechanism` |
| `naga_siren_song_of_the_siren_cancel` | `unique_mechanism` |
| `naga_siren_reel_in_ad` | `unique_mechanism` |
| `keeper_of_the_light_radiant_bind` | `unique_mechanism` |
| `keeper_of_the_light_will_o_wisp` | `unique_mechanism` |
| `keeper_of_the_light_illuminate_end` | `unique_mechanism` |
| `keeper_of_the_light_mana_leak` | `unique_mechanism` |
| `keeper_of_the_light_recall` | `unique_mechanism` |
| `wisp_tether` | `unique_mechanism` |
| `wisp_spirits_in` | `unique_mechanism` |
| `wisp_spirits_out` | `unique_mechanism` |
| `wisp_relocate` | `unique_mechanism` |
| `wisp_tether_break` | `unique_mechanism` |
| `visage_soul_assumption` | `unique_mechanism` |
| `visage_stone_form_self_cast` | `unique_mechanism` |
| `visage_summon_familiars_stone_form` | `unique_mechanism` |
| `visage_summon_familiars_recall` | `unique_mechanism` |
| `slark_pounce` | `unique_mechanism` |
| `slark_depth_shroud` | `unique_mechanism` |
| `slark_fish_bait` | `unique_mechanism` |
| `troll_warlord_switch_stance` | `unique_mechanism` |
| `troll_warlord_whirling_axes_ranged` | `unique_mechanism` |
| `troll_warlord_whirling_axes_melee` | `unique_mechanism` |
| `troll_warlord_battle_trance` | `unique_mechanism` |
| `dark_troll_warlord_raise_dead` | `unique_mechanism` |
| `troll_warlord_rampage` | `unique_mechanism` |
| `troll_warlord_scepter` | `unique_mechanism` |
| `centaur_work_horse` | `unique_mechanism` |
| `centaur_mount` | `unique_mechanism` |
| `centaur_overrun` | `unique_mechanism` |
| `magnataur_horn_toss` | `unique_mechanism` |
| `magnataur_greater_shockwave` | `unique_mechanism` |
| `shredder_flamethrower` | `unique_mechanism` |
| `shredder_chakram` | `unique_mechanism` |
| `shredder_return_chakram` | `unique_mechanism` |
| `shredder_chakram_2` | `unique_mechanism` |
| `shredder_return_chakram_2` | `unique_mechanism` |
| `bristleback_hairball` | `unique_mechanism` |
| `tusk_snowball` | `unique_mechanism` |
| `tusk_drinking_buddies` | `unique_mechanism` |
| `tusk_walrus_kick` | `unique_mechanism` |
| `tusk_launch_snowball` | `unique_mechanism` |
| `tusk_frozen_sigil` | `unique_mechanism` |
| `tusk_ice_shards_stop` | `unique_mechanism` |
| `elder_titan_move_spirit` | `unique_mechanism` |
| `elder_titan_return_spirit` | `unique_mechanism` |
| `techies_reactive_tazer` | `unique_mechanism` |
| `techies_minefield_sign` | `unique_mechanism` |
| `techies_reactive_tazer_stop` | `unique_mechanism` |
| `techies_focused_detonate` | `unique_mechanism` |
| `techies_remote_mines` | `unique_mechanism` |
| `techies_remote_mines_self_detonate` | `unique_mechanism` |
| `techies_snare_trap` | `unique_mechanism` |
| `ember_spirit_activate_fire_remnant` | `unique_mechanism` |
| `earth_spirit_boulder_smash` | `unique_mechanism` |
| `earth_spirit_rolling_boulder` | `unique_mechanism` |
| `earth_spirit_geomagnetic_grip` | `unique_mechanism` |
| `earth_spirit_stone_caller` | `unique_mechanism` |
| `earth_spirit_petrify` | `unique_mechanism` |
| `abyssal_underlord_dark_portal` | `unique_mechanism` |
| `abyssal_underlord_cancel_dark_rift` | `unique_mechanism` |
| `abyssal_underlord_dark_rift` | `unique_mechanism` |
| `abyssal_underlord_portal_warp` | `unique_mechanism` |
| `terrorblade_demon_zeal` | `unique_mechanism` |
| `terrorblade_sunder` | `unique_mechanism` |
| `phoenix_sun_ray` | `unique_mechanism` |
| `phoenix_sun_ray_toggle_move` | `unique_mechanism` |
| `phoenix_launch_fire_spirit` | `unique_mechanism` |
| `phoenix_icarus_dive_stop` | `unique_mechanism` |
| `phoenix_sun_ray_stop` | `unique_mechanism` |
| `arc_warden_tempest_double` | `unique_mechanism` |
| `arc_warden_scepter` | `unique_mechanism` |
| `arc_warden_tempest_recall` | `unique_mechanism` |
| `monkey_king_tree_dance` | `unique_mechanism` |
| `monkey_king_mischief` | `unique_mechanism` |
| `monkey_king_primal_spring_early` | `unique_mechanism` |
| `monkey_king_untransform` | `unique_mechanism` |
| `monkey_king_transfiguration` | `unique_mechanism` |
| `dark_willow_bedlam` | `unique_mechanism` |
| `dark_willow_terrorize` | `unique_mechanism` |
| `pangolier_swashbuckle` | `unique_mechanism` |
| `pangolier_rollup` | `unique_mechanism` |
| `pangolier_gyroshell` | `unique_mechanism` |
| `pangolier_gyroshell_stop` | `unique_mechanism` |
| `pangolier_rollup_stop` | `unique_mechanism` |
| `grimstroke_dark_portrait` | `unique_mechanism` |
| `grimstroke_soul_chain` | `unique_mechanism` |
| `grimstroke_ink_over` | `unique_mechanism` |
| `grimstroke_return` | `unique_mechanism` |
| `hoodwink_decoy` | `unique_mechanism` |
| `hoodwink_hunters_boomerang` | `unique_mechanism` |
| `hoodwink_sharpshooter` | `unique_mechanism` |
| `hoodwink_sharpshooter_release` | `unique_mechanism` |
| `void_spirit_aether_remnant` | `unique_mechanism` |
| `void_spirit_dissimilate` | `unique_mechanism` |
| `snapfire_firesnap_cookie` | `unique_mechanism` |
| `snapfire_gobble_up` | `unique_mechanism` |
| `snapfire_spit_creep` | `unique_mechanism` |
| `mars_bulwark` | `unique_mechanism` |
| `ringmaster_tame_the_beasts_crack` | `unique_mechanism` |
| `ringmaster_funhouse_mirror` | `unique_mechanism` |
| `ringmaster_strongman_tonic` | `unique_mechanism` |
| `ringmaster_whoopee_cushion` | `unique_mechanism` |
| `ringmaster_summon_unicycle` | `unique_mechanism` |
| `ringmaster_crystal_ball` | `unique_mechanism` |
| `ringmaster_weighted_pie` | `unique_mechanism` |
| `dawnbreaker_converge` | `unique_mechanism` |
| `dawnbreaker_solar_guardian` | `unique_mechanism` |
| `dawnbreaker_land` | `unique_mechanism` |
| `marci_grapple` | `unique_mechanism` |
| `marci_companion_run` | `unique_mechanism` |
| `marci_special_delivery` | `unique_mechanism` |
| `marci_unleash` | `unique_mechanism` |
| `marci_guardian` | `unique_mechanism` |
| `primal_beast_onslaught` | `unique_mechanism` |
| `primal_beast_uproar` | `unique_mechanism` |
| `primal_beast_rock_throw` | `unique_mechanism` |
| `primal_beast_onslaught_release` | `unique_mechanism` |
| `muerta_gunslinger` | `unique_mechanism` |
| `muerta_grave_visitation` | `unique_mechanism` |
| `muerta_ofrenda` | `unique_mechanism` |
| `muerta_ofrenda_destroy` | `unique_mechanism` |
| `muerta_parting_shot` | `unique_mechanism` |
| `kez_echo_slash` | `unique_mechanism` |
| `kez_grappling_claw` | `unique_mechanism` |
| `kez_kazurai_katana` | `unique_mechanism` |
| `kez_switch_weapons` | `unique_mechanism` |
| `kez_raptor_dance` | `unique_mechanism` |
| `kez_falcon_rush` | `unique_mechanism` |
| `kez_talon_toss` | `unique_mechanism` |
| `kez_shodo_sai` | `unique_mechanism` |
| `kez_ravens_veil` | `unique_mechanism` |
| `kez_shodo_sai_parry_cancel` | `unique_mechanism` |
| `kez_falcon_rush_ad` | `unique_mechanism` |
| `kez_ravens_veil_ad` | `unique_mechanism` |
| `kez_shodo_sai_ad` | `unique_mechanism` |
| `kez_talon_toss_ad` | `unique_mechanism` |
| `largo_catchy_lick` | `unique_mechanism` |
| `largo_frogstomp` | `unique_mechanism` |
| `largo_croak_of_genius` | `unique_mechanism` |
| `largo_amphibian_rhapsody` | `unique_mechanism` |
| `largo_song_fight_song` | `unique_mechanism` |
| `largo_song_double_time` | `unique_mechanism` |
| `largo_song_good_vibrations` | `unique_mechanism` |

## Data contract and regeneration / 接口与生成

Global `var RpgConditionHelpData = {schema_version, summary, basics, categories, type_coverage, uncovered}`. All display strings use `{zh,en}`, including title, description, steps, settings label/value, notes, example label and preset status. IDs, source paths, enum-like audit fields and numbers are not display text. `examples[].hero` is the native hero ID for portrait/localization; `label` is the bilingual ability name. Basics also expose direct `zh/en` aliases for simple text renderers; `summary.note` combines the coverage notices. Each category repeats its preset status in notes for basic renderers. No new localization tokens are required.

`data/condition_help_topics.json` authors additional bilingual topics and maps the existing historical types to tutorial pages. `python scripts/build-condition-help.py` regenerates the JS and this report; `python scripts/build-condition-help.py --check` verifies byte-for-byte freshness. `python tests/condition-help.test.py` verifies integrity, denominator arithmetic, bilingual fields and the audited family-to-tutorial mapping.
