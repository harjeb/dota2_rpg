# Released native AoE coverage

The detector has **84 explicit profiles: 79 hero abilities, 2 campaign-neutral abilities, and 3 items**. This is broad reviewed coverage, **not proof that all native AoEs are detected or that these profiles have been validated inside Dota**. Unsupported mechanisms and approximations are listed below. There is no generic `radius + duration` fallback: a slow, stun, burn, armor debuff, or buff lifetime does not by itself create a spatial danger zone.

## Evidence and verification

Hero field names and descriptions were reviewed in `data/native_skill_conditions.json`, using `rows[].native.definition.AbilityValues`, native top-level fields, and `description_en`. Campaign-neutral contracts come from `scripts/data/campaign-neutral-native.json`. The item evidence is `data/research/aoe_item_fields_20260915.json`, extracted from <https://raw.githubusercontent.com/dotabuff/d2vpkr/master/dota/scripts/npc/items.txt>. That upstream item version may differ from the installed game; runtime reads live specials and fails closed when required fields are absent or invalid. The installed VPK was unavailable in this workspace.

Validation commands:

```text
lua tests/aoe-threats.test.lua
lua tests/aoe-zones.test.lua
python tests/aoe-profile-coverage.test.py
```

The catalogue test checks every profile's required special names against the evidence, and constructs/expunges a released record using both the first and last native level values. Behavioral tests cover retained release visibility, hidden initial casts, independent team snapshots, hidden target position reads, duration versus debuff lifetime, paths, cone endpoints, rings, moving caster/target observations, death, channel start/stop/reappearance, charge interruption/completion, expiry, duplicates, resets, and Split Earth Shard repeats. These are mocked Lua tests; native event ordering, spatial offsets, upgrade behavior, and effects ending early still require engine validation.

## Runtime contract and privacy

`OnExecuted(unit, ability, now)` accepts only registered native releases. For charge profiles it remembers initial visibility without publishing a threat or reading the cursor. `OnChannelEnd(unit, ability, now, interrupted)` emits Powershot/Illuminate at release, including interrupted channels, but Meteor Hammer requires `interrupted == false`; a missing completion flag fails closed. Both initial execution and actual channel-end must be visible to the recipient team. No hidden initial cast is discovered later.

Records retain `position`, `radius`, `phase = released`, `released_at`, `impact_at`, and `expires_at`. `active_from == impact_at` and `active_until == expires_at`. Shapes are `circle`, `line`, `cone`, or `ring`; lines/cones have `endpoint`, cones have `end_radius`, and rings have `inner_radius`. Single delayed hits expire exactly at impact. Ground effects survive impact until their spatial lifetime ends. Each Split Earth Shard repeat has its own impact, radius, and expiry.

Moving caster and target effects have separate snapshots per viewer team. Only viewers in the latest roster can refresh a snapshot, and only while the anchor is visible to that team. Hidden anchors are neither position-sampled nor followed; their snapshots freeze until visibility returns or the known expiry is reached. Target-centered releases additionally require target visibility before any target-position read. The observation pass never polls a cursor or discovers a cast.

Released fixed ground areas survive caster hiding/death/detach. A visible moving anchor's death ends its effect for that observing team. Visible channel interruption/death ends a channel zone; hidden interruption is frozen. When the caster becomes visible again, known channel records reconcile against native channel state after a 0.1-second event-ordering grace. Sand Storm and Wukong's Command additionally end when a visible caster leaves their recorded region. Returned positions and endpoints are copied, including between teammates.

## Approximations within registered profiles

`envelope=true` denotes an explicitly conservative spatial or temporal bound, not an exact continuously occupied area. Broad envelopes can cause unnecessary avoidance. Other native offsets and event timing remain unproven even for profiles without this flag.

- Straight projectile profiles occupy their whole released corridor for `length / speed`; they do not track the moving front, collision, absorption, early termination, displacement, or return legs. Cones interpolate endpoint width. Point-projectile impact estimates use released source-to-point distance divided by speed; acceleration, lob height, and special offsets are not reconstructed.
- Chaos Meteor starts at the released destination and covers the forward rolling corridor after `land_time`, for `travel_distance / travel_speed`. The continuing burn on units is excluded. Extra meteors from talents are not emitted.
- Ice Path uses native base cast range 1100, `path_radius`, `path_delay`, and `path_duration`; later stun lifetime is excluded. Macropyre uses half `path_width` as radius and live `AbilityCastRange`/`duration`; Scepter ice-edge bands are not included. Nature's Grasp approximates segmented vine placement by one continuous line and does not model per-segment growth timing.
- Kinetic Field is a band around its radius, with half `wall_thickness` on each side. Arena uses outer `radius + width`, inner `radius - spear_distance_from_wall`, covering wall/inner spear reach. These are barrier danger bands, not a claim that the center deals continuous damage.
- Bramble Maze, The Calling, Wukong's Command, Freezing Field, Epicenter, Exorcism, Bedlam, Spirits, Rocket Barrage, Diabolic Edict, Eye of the Storm, Trample, Will-O-Wisp, and Frogstomp use broad envelopes rather than tracking individual brambles, revenants, soldiers, explosions, spirits, targets, or pulse gaps. Frogstomp uses `total_ticks * stomp_interval` after `delay`, including the final interval conservatively. Epicenter uses its maximum base pulse radius for its native six-second release.
- Will-O-Wisp, Nimbus, Ice Spire, Supernova, and other destroyable sources retain their known maximum duration; summon/egg destruction is not observed. Supernova includes the damaging aura for native six seconds; its final instantaneous stun is not extended into a ground zone.
- Flame Guard lasts at most its recorded duration; barrier break/dispel is not observed. Ion Shell, Frost Shield, Reactive Tazer, Crown and other target effects do not track dispels, purge-triggered behavior, or early recasts. Frost Shield kill extensions and Winter's Curse dynamic extension are not reconstructed; Curse uses `max_duration` as an upper envelope.
- Underlord Firestorm uses `wave_duration` for its stationary base zone. Shard unit-target following and changed wave count/interval are unsupported. Scorched Earth's permanent talent is unsupported beyond the base duration.
- Meteor Hammer is a delayed impact only: `burn_duration` is a debuff and is excluded. Shiva's Guard uses an expanding-blast circle envelope for `blast_radius / blast_speed`, anchored at release. Blood Grenade uses estimated projectile impact only, excluding its debuff duration.

## Techies native bomb sources (additional to the 84 profiles)

`tactics/techies_threats.lua` is integrated into observation, returned threats and reset. It discovers actual `npc_dota_techies_mines` and `npc_dota_thinker` entities every 200 ms, revisits known sources at the engine observation cadence, and reads positions/modifiers only after a viewer confirms entity visibility. A visible bomb may be learned even when its original planting was hidden; this exposes the visible object, not the hidden cast. Evidence and exact native names are retained in `data/research/techies_native_sources_20260915.json`.

- Proximity mines, legacy remote mines, stasis traps, snare traps, and M.A.D. death/planted barrels use the observed native object position and live ability radius. Creation time plus native arming delay is used when available. Observed stationary mines are remembered for at most three seconds without another visible update; visible destruction removes them immediately.
- Proximity mines add a conservative escape deadline from first observed activation plus native `proximity_threshold`, reserving 200 ms for discovery delay. This is **an estimate, not the private native proximity countdown**. Walking must clear this deadline; otherwise the next configured defensive-cast rule can be attempted. Another unit may already have triggered the mine, so this does not prove safety.
- Free Sticky Bombs are detected through actual `modifier_techies_sticky_bomb_throw`, `_chase`, and `_countdown` modifiers on discovered thinkers. The native strings verify these names; their live Lua parent/timer behavior still requires Dota testing. Throw/chase phases are short-lived moving envelopes, not an invented exact detonation time. Countdown uses the modifier's actual remaining time. Attached carriers additionally use the primary `_slow` modifier; the post-explosion `_slow_secondary` is excluded.
- Reactive Tazer's visible carrier modifier supplies the remaining timer and position. Its ordinary release profile follows the selected ally; an observed early-stop action consumes the scheduled profile. Blast Off uses a released cursor landing estimate with native `duration` (0.75 seconds in the snapshot); interrupted or altered jump trajectories are not reconstructed.
- A barrel with a valid native modifier remaining time uses that deadline. If no timer is exposed, it remains a visible hazard region; object type alone is not claimed to distinguish death from Shard placement.

Hidden positions never update, hidden expiry is bounded, and returned snapshots are isolated per team. Source absence is not proof of safety. Native mine trigger timers, unobservable thinkers, exact bomb collision/movement, and Minefield Sign's Scepter effect remain unverified or uncovered. Tests cover each mine kind, free and attached Sticky phases, visible motion, hidden motion, destruction, arming, stable IDs/deadlines, missing APIs/data, and reset.

## Material unsupported inventory

These are concrete known gaps, not an exhaustive theorem over every ability, facet, neutral, item, or future patch. An unsupported profile produces no record; absence of a record is not evidence that a location is safe.

| Native abilities / types | Missing mechanism or reason |
| --- | --- |
| `pudge_rot`, `leshrac_pulse_nova`, `bloodseeker_blood_mist`, `shredder_chakram`, `shredder_chakram_2` | Indefinite/toggle or mana-bound lifetime, explicit stop and modifier ownership needed. No invented fixed expiry. |
| `phoenix_sun_ray`, `phoenix_icarus_dive`, `batrider_firefly`, `dark_seer_surge`, `dawnbreaker_celestial_hammer` | Steering beams, curved motion, or accumulated moving trails need native segment history and stop/return handling. |
| `snapfire_mortimer_kisses`, `snapfire_spit_creep`, `tiny_tree_channel`, `drow_ranger_multishot` | Individual shots can target different points, or are launched in salvos with changing origin/direction; a channel cursor is not polled to invent release events. Lob timing is not speed alone. |
| `invoker_ice_wall`, `dark_seer_wall_of_replica`, `disruptor_kinetic_fence`, `void_spirit_aether_remnant`, `muerta_dead_shot` | Perpendicular/vector placement, remnant gaze, paired walls, or ricochet direction requires an explicit native vector/release contract. |
| `earthshaker_fissure`, `tusk_ice_shards`, `drow_ranger_glacier`, `furion_sprout` | Persistent obstacles have separate navigation geometry; their attack stun/debuff duration is not ongoing AoE damage. |
| `gyrocopter_call_down`, `medusa_gorgon_grasp` | Offset multi-strike/group placement and successive expanding group centers are not reconstructed. Medusa's `duration` describes affected units, not persistent ground. |
| `kunkka_ghostship`, `kunkka_torrent_storm` | Fleet/cannon/offset timing and randomized later Torrent centers require additional events. The directly cast Torrent remains supported. |
| `ancient_apparition_ice_blast`, `ancient_apparition_ice_blast_release` | Two-stage travelling tracer, selected release point, growing blast radius and actual projectile intercept. |
| `hoodwink_sharpshooter`, `hoodwink_sharpshooter_release`, `monkey_king_primal_spring`, `primal_beast_onslaught`, `tusk_snowball` | Bespoke charge/aim, subability release, relocation or launch semantics not established by the ordinary channel-end contract. No windup records. |
| `keeper_of_the_light_spirit_form_illuminate`, `oracle_fortunes_end` | Autonomous spirit release or target-projectile charge semantics need dedicated release/target history. Base Illuminate channel is supported. |
| `puck_illusory_orb`, `hoodwink_hunters_boomerang`, `shredder_twisted_chakram` | Curved/vector/return trajectories do not fit a straight released corridor. |
| `razor_plasma_field`, `venomancer_poison_nova`, `nevermore_requiem`, `tidehunter_ravage` | Expanding/returning rings or multiple rays with distance-dependent arrivals and upgrade returns. |
| `puck_dream_coil`, `earth_spirit_magnetize`, `venomancer_noxious_plague`, `lich_chain_frost`, `witch_doctor_paralyzing_cask`, `winter_wyvern_splinter_blast`, `warlock_fatal_bonds` | Victim membership, propagation, bounces, tethers and target-dependent later explosions cannot be inferred from one ground radius. |
| `templar_assassin_psionic_trap`, `storm_spirit_static_remnant`, `techies_minefield_sign` Scepter | Spawned source identity, trigger/destruction and special lifetimes. Techies mines/barrels themselves use the separate source observer described above; they are not ordinary executed profiles. |
| `viper_nose_dive`, `snapfire_firesnap_cookie`, `pangolier_shield_crash`, `void_spirit_dissimilate` | Target chase, jump/landing or portal-selection position cannot be determined safely from released cursor alone. |
| `crystal_maiden_crystal_clone`, `phoenix_fire_spirits`, `phoenix_launch_fire_spirit`, `weaver_the_swarm` | Destructible source or independent launched/binding units with separate lifetime and impact behavior. |
| `dawnbreaker_solar_guardian`, `witch_doctor_death_ward`, `bane_fiends_grip` upgrades | Landing relocation, ward target selection, or clone ownership needs additional native state. |
| `tinker_march_of_the_machines`, `tinker_deploy_turrets` | Many travelling machines or later spawned turrets and their attacks are not a single persistent circle. |
| `item_gungir`, `item_gleipnir` aliases, `item_eternal_shroud` and immediate AoE item activations | Root/debuff/reactive lifetimes do not establish post-release ground danger. Gungir evidence is reviewed but intentionally has no persistent profile. |
| `enraged_wildkin_tornado`, `enraged_wildkin_tornado_ability`, `mud_golem_hurl_boulder` / `mudgolem_hurl_boulder` | Not present in checked-in campaign-neutral contracts. Moving summoned tornado and targeted rock are not inferred from guessed keys. Campaign instant Stomp/Clap/Slam/Ogre Smash expire at release and are not delayed threats. |
| Passive auras/procs, automatic attacks, summoned unit attack zones, fountain attacks, custom scripted damage | No native ability-executed release contract; no speculative records. |

Upgrade gaps include Sun Strike Cataclysm; additional Meteor/Tornado effects; return Shockwave; Macropyre ice edges; Mars Spear Shard fire trail; Underlord Firestorm Shard tracking; Scepter portal pits; Epicenter Scepter explosions and passive Shard pulses; Wukong's outer talent ring and independent Scepter soldiers; Bedlam unit-target variant; Riki Tricks ally-riding/Scepter duration; Scorched Earth permanent talent; Viper Nethertoxin growing-radius talent; Supernova allied-egg upgrades; hidden or unobserved early Reactive Tazer detonation; and kill/refresh/extension mechanics. Live special-value scalar changes are picked up where the profile names the relevant key, but that does not implement new geometry or release events. **Split Earth Shard's `shard_max_count`, `shard_secondary_delay`, and `shard_radius_increase` are explicitly supported.**

## Exact profile inventory

The following table is generated from `tactics/aoe_profiles.lua`. `@channel` means native `GetChannelTime`; `@cursor` means released source-to-destination distance. A speed in the flight column makes a line/cone last `length / speed`; `point:` estimates an impact delay. All other delays/durations use the listed specials directly. Numbers are reviewed native top-level constants, not generic defaults. Expressions are evaluated from live specials; absent or invalid required fields fail closed.

| Native name | Shape / anchor | Radius / extra geometry | Delay | Active duration | Path length / flight |
| --- | --- | --- | --- | --- | --- |
| `abyssal_underlord_firestorm` | circle; cursor | `radius` | `0` | `wave_duration` | `-` |
| `abyssal_underlord_pit_of_malice` | circle; cursor | `radius` | `0` | `pit_duration` | `-` |
| `alchemist_acid_spray` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `ancient_apparition_ice_vortex` | circle; cursor | `radius` | `0` | `vortex_duration` | `-` |
| `batrider_flamebreak` | circle; cursor | `explosion_radius` | `0` | `0` | `point: speed` |
| `black_dragon_fireball` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `bloodseeker_blood_bath` | circle; cursor | `radius` | `delay` | `0` | `-` |
| `crystal_maiden_freezing_field` | circle; follow caster; channel | `(explosion_max_dist+explosion_radius)` | `0` | `AbilityChannelTime` | `-` |
| `dark_seer_ion_shell` | circle; follow target | `radius` | `0` | `duration` | `-` |
| `dark_willow_bedlam` | circle; follow caster | `(attack_radius+roaming_radius)` | `0` | `roaming_duration` | `-` |
| `dark_willow_bramble_maze` | circle; cursor | `(placement_range+latch_range)` | `initial_creation_delay` | `placement_duration` | `-` |
| `dark_willow_cursed_crown` | circle; follow target | `stun_radius` | `delay` | `0` | `-` |
| `dark_willow_terrorize` | circle; cursor | `destination_radius` | `0` | `0` | `point: destination_travel_speed` |
| `death_prophet_carrion_swarm` | cone; cursor | `start_radius; end=end_radius` | `0` | `0` | `range; speed=speed` |
| `death_prophet_exorcism` | circle; follow caster | `max_distance` | `0` | `40` | `-` |
| `disruptor_kinetic_field` | ring; cursor | `(radius+(wall_thickness*0.5)); inner=(radius-(wall_thickness*0.5))` | `formation_time` | `duration` | `-` |
| `disruptor_static_storm` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `doom_bringer_scorched_earth` | circle; follow caster | `radius` | `0` | `duration` | `-` |
| `dragon_knight_fireball` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `drow_ranger_wave_of_silence` | line; cursor | `wave_width` | `0` | `0` | `wave_length; speed=wave_speed` |
| `earth_spirit_petrify` | circle; follow target | `aoe` | `duration` | `0` | `-` |
| `elder_titan_earth_splitter` | line; cursor | `(crack_width*0.5)` | `crack_time` | `0` | `crack_distance` |
| `ember_spirit_flame_guard` | circle; follow caster | `radius` | `0` | `duration` | `-` |
| `enigma_black_hole` | circle; cursor; channel | `radius` | `0` | `duration` | `-` |
| `enigma_midnight_pulse` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `faceless_void_chronosphere` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `gyrocopter_rocket_barrage` | circle; follow caster | `radius` | `0` | `barrage_duration` | `-` |
| `hoodwink_bushwhack` | circle; cursor | `trap_radius` | `0` | `0` | `point: projectile_speed` |
| `invoker_chaos_meteor` | line; cursor | `area_of_effect` | `land_time` | `0` | `travel_distance; speed=travel_speed` |
| `invoker_deafening_blast` | cone; cursor | `radius_start; end=radius_end` | `0` | `0` | `travel_distance; speed=travel_speed` |
| `invoker_emp` | circle; cursor | `area_of_effect` | `delay` | `0` | `-` |
| `invoker_sun_strike` | circle; cursor | `area_of_effect` | `delay` | `0` | `-` |
| `invoker_tornado` | line; cursor | `area_of_effect` | `0` | `0` | `travel_distance; speed=travel_speed` |
| `item_blood_grenade` | circle; cursor | `radius` | `0` | `0` | `point: speed` |
| `item_meteor_hammer` | circle; cursor; channel-end | `impact_radius` | `land_time` | `0` | `-` |
| `item_shivas_guard` | circle; caster | `blast_radius` | `0` | `(blast_radius/blast_speed)` | `-` |
| `jakiro_ice_path` | line; cursor | `path_radius` | `path_delay` | `path_duration` | `1100` |
| `jakiro_macropyre` | line; cursor | `(path_width*0.5)` | `0` | `duration` | `AbilityCastRange` |
| `juggernaut_blade_fury` | circle; follow caster | `blade_fury_radius` | `0` | `duration` | `-` |
| `keeper_of_the_light_illuminate` | line; cursor; channel-end | `radius` | `0` | `0` | `range; speed=speed` |
| `keeper_of_the_light_will_o_wisp` | circle; cursor | `radius` | `off_duration_initial` | `((on_count*on_duration)+((on_count-1)*off_duration))` | `-` |
| `kunkka_torrent` | circle; cursor | `radius` | `delay` | `0` | `-` |
| `largo_frogstomp` | circle; cursor | `radius` | `delay` | `(total_ticks*stomp_interval)` | `-` |
| `leshrac_diabolic_edict` | circle; follow caster | `radius` | `0` | `AbilityDuration` | `-` |
| `leshrac_split_earth` | circle; cursor | `radius` | `delay` | `0` | `-` |
| `lich_frost_shield` | circle; follow target | `radius` | `0` | `duration` | `-` |
| `lich_ice_spire` | circle; cursor | `aura_radius` | `0` | `duration` | `-` |
| `lina_dragon_slave` | cone; cursor | `dragon_slave_width_initial; end=dragon_slave_width_end` | `0` | `0` | `dragon_slave_distance; speed=dragon_slave_speed` |
| `lina_light_strike_array` | circle; cursor | `light_strike_array_aoe` | `light_strike_array_delay_time` | `0` | `-` |
| `magnataur_shockwave` | line; cursor | `shock_width` | `0` | `0` | `AbilityCastRange; speed=shock_speed` |
| `mars_arena_of_blood` | ring; cursor | `(radius+width); inner=(radius-spear_distance_from_wall)` | `formation_time` | `duration` | `-` |
| `mars_spear` | line; cursor | `spear_width` | `0` | `0` | `spear_range; speed=spear_speed` |
| `monkey_king_wukongs_command` | circle; cursor | `second_radius` | `0` | `duration` | `-` |
| `muerta_the_calling` | circle; cursor | `(dead_zone_distance+hit_radius)` | `0` | `duration` | `-` |
| `necrolyte_ghost_shroud` | circle; follow caster | `slow_aoe` | `0` | `duration` | `-` |
| `oracle_rain_of_destiny` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `pangolier_gyroshell` | circle; follow caster | `hit_radius` | `0` | `duration` | `-` |
| `phoenix_supernova` | circle; caster | `aura_radius` | `0` | `6` | `-` |
| `primal_beast_pulverize` | circle; follow target; channel | `splash_radius` | `0` | `channel_time` | `-` |
| `primal_beast_trample` | circle; follow caster | `effect_radius` | `0` | `duration` | `-` |
| `pugna_nether_blast` | circle; cursor | `radius` | `delay` | `0` | `-` |
| `queenofpain_sonic_wave` | cone; cursor | `starting_aoe; end=final_aoe` | `0` | `0` | `distance; speed=speed` |
| `razor_eye_of_the_storm` | circle; follow caster | `radius` | `0` | `duration` | `-` |
| `riki_smoke_screen` | circle; cursor | `radius` | `0` | `AbilityDuration` | `-` |
| `riki_tricks_of_the_trade` | circle; cursor; channel | `radius` | `0` | `@channel` | `-` |
| `sandking_epicenter` | circle; follow caster | `(epicenter_radius_base+((epicenter_pulses-1)*epicenter_radius_increment))` | `0` | `6` | `-` |
| `sandking_sand_storm` | circle; caster | `sand_storm_radius` | `0` | `AbilityDuration` | `-` |
| `satyr_hellcaller_shockwave` | cone; cursor | `radius_start; end=radius_end` | `0` | `0` | `distance; speed=speed` |
| `slark_dark_pact` | circle; follow caster | `radius` | `delay` | `pulse_duration` | `-` |
| `snapfire_scatterblast` | cone; cursor | `blast_width_initial; end=blast_width_end` | `0` | `0` | `AbilityCastRange; speed=blast_speed` |
| `sniper_shrapnel` | circle; cursor | `radius` | `damage_delay` | `duration` | `-` |
| `techies_reactive_tazer` | circle; follow target | `explosion_radius` | `duration` | `0` | `-` |
| `techies_suicide` | circle; released landing estimate | `radius` | `duration` | `0` | envelope |
| `tiny_avalanche` | circle; cursor | `radius` | `0` | `total_duration` | `point: projectile_speed` |
| `treant_natures_grasp` | line; cursor | `latch_range` | `initial_latch_delay` | `vines_duration` | `@cursor` |
| `venomancer_venomous_gale` | line; cursor | `radius` | `0` | `0` | `AbilityCastRange; speed=speed` |
| `viper_nethertoxin` | circle; cursor | `radius` | `0` | `duration` | `point: projectile_speed` |
| `warlock_rain_of_chaos` | circle; cursor | `aoe` | `stun_delay` | `0` | `-` |
| `warlock_upheaval` | circle; cursor; channel | `aoe` | `0` | `@channel` | `-` |
| `windrunner_gale_force` | circle; cursor | `radius` | `0` | `duration` | `-` |
| `windrunner_powershot` | line; cursor; channel-end | `arrow_width` | `0` | `0` | `arrow_range; speed=arrow_speed` |
| `winter_wyvern_winters_curse` | circle; follow target | `radius` | `0` | `max_duration` | `-` |
| `wisp_spirits` | circle; follow caster | `(max_range+explode_radius)` | `0` | `spirit_duration` | `-` |
| `zuus_cloud` | circle; cursor | `cloud_radius` | `0` | `cloud_duration` | `-` |
