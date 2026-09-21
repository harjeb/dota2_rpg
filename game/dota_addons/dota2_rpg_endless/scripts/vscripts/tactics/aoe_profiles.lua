-- Reviewed against data/native_skill_conditions.json AbilityValues and description_en.
-- Explicit spatial lifetimes only: stun/slow/burn debuff duration is NOT zone duration.
-- Numeric constants below come from native top-level AbilityDuration/AbilityCastRange.
local P = {}
local function add(name, radius, delay, duration, extra)
    local p = extra or {}; p.radius=radius; p.delay=delay or 0; p.duration=duration or 0
    p.shape=p.shape or 'circle'; p.origin=p.origin or 'cursor'; P[name]=p
end
local function sum(a,b) return {op='add',a,b} end
local function product(a,b) return {op='mul',a,b} end
local function difference(a,b) return {op='sub',a,b} end
add('lina_light_strike_array','light_strike_array_aoe','light_strike_array_delay_time')
add('leshrac_split_earth','radius','delay',0,{repeats=true})
add('kunkka_torrent','radius','delay')
add('invoker_sun_strike','area_of_effect','delay')
add('invoker_emp','area_of_effect','delay')
add('pugna_nether_blast','radius','delay')
add('bloodseeker_blood_bath','radius','delay')
add('warlock_rain_of_chaos','aoe','stun_delay')
add('alchemist_acid_spray','radius',0,'duration')
add('viper_nethertoxin','radius',0,'duration',{travel_speed='projectile_speed'})
add('dragon_knight_fireball','radius',0,'duration')
add('doom_bringer_scorched_earth','radius',0,'duration',{origin='caster',follow='caster'})
add('ember_spirit_flame_guard','radius',0,'duration',{origin='caster',follow='caster',envelope=true})
add('oracle_rain_of_destiny','radius',0,'duration')
add('largo_frogstomp','radius','delay',product('total_ticks','stomp_interval'),{envelope=true})
add('tiny_avalanche','radius',0,'total_duration',{travel_speed='projectile_speed'})
add('juggernaut_blade_fury','blade_fury_radius',0,'duration',{origin='caster',follow='caster'})
add('gyrocopter_rocket_barrage','radius',0,'barrage_duration',{origin='caster',follow='caster',envelope=true})
add('primal_beast_trample','effect_radius',0,'duration',{origin='caster',follow='caster',envelope=true})
add('primal_beast_pulverize','splash_radius',0,'channel_time',{origin='target',follow='target',channel=true})
add('keeper_of_the_light_will_o_wisp','radius','off_duration_initial',
    sum(product('on_count','on_duration'),product(difference('on_count',1),'off_duration')),{envelope=true})
add('wisp_spirits',sum('max_range','explode_radius'),0,'spirit_duration',{origin='caster',follow='caster',envelope=true})
add('winter_wyvern_winters_curse','radius',0,'max_duration',{origin='target',follow='target',envelope=true})
add('ancient_apparition_ice_vortex','radius',0,'vortex_duration')
add('enigma_midnight_pulse','radius',0,'duration')
add('enigma_black_hole','radius',0,'duration',{channel=true})
add('faceless_void_chronosphere','radius',0,'duration')
add('disruptor_static_storm','radius',0,'duration')
add('disruptor_kinetic_field',sum('radius',product('wall_thickness',0.5)),'formation_time','duration',
    {shape='ring',inner_radius=difference('radius',product('wall_thickness',0.5))})
add('mars_arena_of_blood',sum('radius','width'),'formation_time','duration',
    {shape='ring',inner_radius=difference('radius','spear_distance_from_wall')})
add('riki_smoke_screen','radius',0,'AbilityDuration')
add('sniper_shrapnel','radius','damage_delay','duration')
add('abyssal_underlord_pit_of_malice','radius',0,'pit_duration')
add('abyssal_underlord_firestorm','radius',0,'wave_duration')
add('windrunner_gale_force','radius',0,'duration')
add('zuus_cloud','cloud_radius',0,'cloud_duration',{envelope=true})
add('lich_ice_spire','aura_radius',0,'duration',{envelope=true})
add('sandking_sand_storm','sand_storm_radius',0,'AbilityDuration',{origin='caster',leash=true})
add('phoenix_supernova','aura_radius',0,6,{origin='caster',envelope=true})
add('monkey_king_wukongs_command','second_radius',0,'duration',{leash=true,envelope=true})
add('dark_willow_bramble_maze',sum('placement_range','latch_range'),'initial_creation_delay','placement_duration',{envelope=true})
add('muerta_the_calling',sum('dead_zone_distance','hit_radius'),0,'duration',{envelope=true})
add('warlock_upheaval','aoe',0,'@channel',{channel=true})
add('crystal_maiden_freezing_field',sum('explosion_max_dist','explosion_radius'),0,'AbilityChannelTime',
    {origin='caster',follow='caster',channel=true,envelope=true})
add('riki_tricks_of_the_trade','radius',0,'@channel',{channel=true})
add('razor_eye_of_the_storm','radius',0,'duration',{origin='caster',follow='caster',envelope=true})
add('leshrac_diabolic_edict','radius',0,'AbilityDuration',{origin='caster',follow='caster',envelope=true})
add('necrolyte_ghost_shroud','slow_aoe',0,'duration',{origin='caster',follow='caster'})
add('dark_seer_ion_shell','radius',0,'duration',{origin='target',follow='target'})
add('lich_frost_shield','radius',0,'duration',{origin='target',follow='target'})
add('dark_willow_cursed_crown','stun_radius','delay',0,{origin='target',follow='target'})
add('earth_spirit_petrify','aoe','duration',0,{origin='target',follow='target'})
add('slark_dark_pact','radius','delay','pulse_duration',{origin='caster',follow='caster'})
add('sandking_epicenter',sum('epicenter_radius_base',product(difference('epicenter_pulses',1),'epicenter_radius_increment')),0,6,
    {origin='caster',follow='caster',envelope=true})
add('death_prophet_exorcism','max_distance',0,40,{origin='caster',follow='caster',envelope=true})
add('dark_willow_bedlam',sum('attack_radius','roaming_radius'),0,'roaming_duration',{origin='caster',follow='caster',envelope=true})
add('pangolier_gyroshell','hit_radius',0,'duration',{origin='caster',follow='caster'})
add('techies_reactive_tazer','explosion_radius','duration',0,{origin='target',follow='target'})
add('techies_suicide','radius','duration',0,{envelope=true})
-- Paths: width special semantics are individually reviewed (Macropyre is full width).
add('jakiro_ice_path','path_radius','path_delay','path_duration',{shape='line',length=1100})
add('jakiro_macropyre',product('path_width',0.5),0,'duration',{shape='line',length='AbilityCastRange'})
add('treant_natures_grasp','latch_range','initial_latch_delay','vines_duration',{shape='line',length='@cursor',envelope=true})
add('elder_titan_earth_splitter',product('crack_width',0.5),'crack_time',0,{shape='line',length='crack_distance'})
-- Swept full-flight corridors are conservative envelopes, not live projectiles.
local function projectile(name,radius,length,speed,extra)
    extra=extra or {}; extra.shape=extra.end_radius and 'cone' or 'line'
    extra.length=length; extra.speed=speed; extra.envelope=true
    add(name,radius,0,0,extra)
end
projectile('lina_dragon_slave','dragon_slave_width_initial','dragon_slave_distance','dragon_slave_speed',{end_radius='dragon_slave_width_end'})
projectile('death_prophet_carrion_swarm','start_radius','range','speed',{end_radius='end_radius'})
projectile('invoker_deafening_blast','radius_start','travel_distance','travel_speed',{end_radius='radius_end'})
projectile('invoker_tornado','area_of_effect','travel_distance','travel_speed')
projectile('venomancer_venomous_gale','radius','AbilityCastRange','speed')
projectile('mars_spear','spear_width','spear_range','spear_speed')
projectile('snapfire_scatterblast','blast_width_initial','AbilityCastRange','blast_speed',{end_radius='blast_width_end'})
projectile('windrunner_powershot','arrow_width','arrow_range','arrow_speed',{channel_release=true})
projectile('keeper_of_the_light_illuminate','radius','range','speed',{channel_release=true})
projectile('drow_ranger_wave_of_silence','wave_width','wave_length','wave_speed')
projectile('magnataur_shockwave','shock_width','AbilityCastRange','shock_speed')
projectile('queenofpain_sonic_wave','starting_aoe','distance','speed',{end_radius='final_aoe'})
add('invoker_chaos_meteor','area_of_effect','land_time',0,
    {shape='line',length='travel_distance',speed='travel_speed',path_from_cursor=true,envelope=true})
-- Point projectiles: impact estimate uses released source->destination / native speed.
add('hoodwink_bushwhack','trap_radius',0,0,{travel_speed='projectile_speed',envelope=true})
add('dark_willow_terrorize','destination_radius',0,0,{travel_speed='destination_travel_speed',envelope=true})
add('batrider_flamebreak','explosion_radius',0,0,{travel_speed='speed',envelope=true})
-- Campaign neutral native snapshot: scripts/data/campaign-neutral-native.json.
add('black_dragon_fireball','radius',0,'duration')
projectile('satyr_hellcaller_shockwave','radius_start','distance','speed',{end_radius='radius_end'})
-- Item contracts: upstream d2vpkr scripts/npc/items.txt; bounded evidence in data/research/aoe_item_fields_20260915.json.
add('item_meteor_hammer','impact_radius','land_time',0,{channel_release=true,require_completion=true})
add('item_shivas_guard','blast_radius',0,{op='div','blast_radius','blast_speed'},{origin='caster',envelope=true})
add('item_blood_grenade','radius',0,0,{travel_speed='speed',envelope=true})
return P
