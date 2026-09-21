-- BASIC_CARDS_V1 is authoritative. A definition is a promise of executable behavior.
local D = {}
local function add(id, kind, target, stats, trigger, duration)
    local effects = {}
    for stat, values in pairs(stats or {}) do effects[#effects+1]={type='stat',stat=stat,values=values} end
    D[id]={type=kind,target=target or 'friendly',effects=effects,trigger=trigger,duration=duration}
end
local function buff(id, stats) add(id,'buff','friendly',stats) end
local function field(id,target,stats) add(id,'field',target,stats) end
local function time(first,interval) return {type='time',first=first,interval=interval or 12} end
local function event(name) return {type=name,cooldown=12} end
local function low(n) return {type='hero_health_below',threshold=n,cooldown=12} end
local function consume(id,stats,trigger,duration,target) add(id,'consumable',target or 'friendly',stats,trigger,duration or 0) end
buff('E-g1',{}); buff('E-g2',{}); buff('E-g3',{health={200,300,500}})
buff('E-g4',{}); buff('E-g5',{}); buff('E-g6',{missing_health_amp={12,20,35}})
buff('E-g8',{spell_amp={4,7,10}}); buff('E-g9',{})
buff('C-g1',{attack_speed={20,35,55}}); buff('C-g2',{attack_block={15,25,40}})
buff('C-g3',{}); buff('C-g4',{}); buff('C-g5',{cooldown={10,16,24}})
buff('C-g6',{incoming_damage={-5,-8,-12}}); buff('C-g7',{spell_amp={12,20,30},mana_cost={20,20,20}})
buff('C-g8',{armor={4,7,11}}); buff('C-g9',{})
buff('D-g1',{move_speed={8,13,20},status_resistance={10,16,24}})
buff('D-g2',{health_regen_pct={0.4,0.7,1.1}}); buff('D-g3',{}); buff('D-g4',{})
buff('D-g5',{shield_amp={15,25,40}}); buff('D-g6',{heal_amp={15,25,40}})
buff('D-g7',{magic_resistance={10,18,28}}); buff('D-g8',{mana={150,250,400},mana_regen={3,5,8}})
buff('D-g9',{physical_reduction={8,13,20}})
buff('A-g1',{health_regen={6,10,15},missing_health_regen={14,25,35}})
buff('A-g2',{}); buff('A-g3',{}); buff('A-g4',{spell_lifesteal={8,14,22}})
buff('A-g5',{}); buff('A-g6',{health_pct={-10,-10,-10},outgoing_damage={10,17,25}})
buff('A-g7',{mana_pct={-15,-15,-15},attack_damage={25,45,70}})
buff('A-g8',{evasion={10,17,25}}); buff('A-g9',{attack_lifesteal={10,18,28}})
buff('W-g1',{attack_damage={20,35,55}}); buff('W-g2',{}); buff('W-g3',{}); buff('W-g4',{})
buff('W-g5',{base_damage_pct={12,20,30}}); buff('W-g6',{attack_speed={18,30,45},move_speed={5,8,12}})
buff('W-g7',{crit_chance={15,20,25},crit_multiplier={160,180,200}})
buff('W-g8',{health={250,450,700}}); buff('W-g9',{health_pct={8,14,22}})
consume('E-c1',{spell_amp={20,30,45}},time(5),10)
consume('E-c3',{},time(0),5,'enemy')
consume('E-c5',{}, {type='team_mana_below',threshold=.3,cooldown=12})
consume('E-c6',{},time(12))
consume('C-c1',{base_damage_pct={40,60,80}},time(5),8)
consume('C-c2',{attack_speed={50,80,120},move_speed={12,20,30}},time(5),8)
consume('C-c3',{armor={10,16,24},incoming_damage={-12,-20,-30}},low(.4),8)
consume('C-c4',{},time(6),2)
consume('C-c5',{},event('attacked'),8)
consume('C-c6',{health_regen_pct={1,1.5,2}},low(.5),6)
consume('C-c7',{attack_speed={30,50,80}},event('friendly_death'),8)
consume('D-c1',{health_regen_pct={2,3,4.5}},low(.7),10)
consume('D-c2',{heal_amp={30,50,75},shield_amp={30,50,75}},low(.7),10)
consume('D-c3',{},low(.5),10); consume('D-c4',{},low(.3),4)
consume('D-c5',{status_resistance={25,40,60}},event('controlled'),6)
consume('D-c6',{},time(10)); consume('D-c7',{},event('friendly_death'),10)
consume('A-c1',{},event('killed_ally')); consume('A-c2',{outgoing_damage={15,25,40}},event('mark_death'),8)
consume('A-c3',{},low(.5)); consume('A-c4',{attack_lifesteal={30,50,75},spell_lifesteal={10,18,28}},time(5,14),10)
consume('A-c5',{base_damage_pct={20,35,50}},event('friendly_death'),8)
consume('A-c6',{mana_cost={-15,-25,-40}},{type='hero_mana_below',threshold=.3,cooldown=12},8)
consume('A-c7',{heal_amp={-40,-60,-80}},time(5),8,'enemy')
consume('W-c1',{},event('cast'),8)
consume('W-c2',{attack_speed={80,120,180},attack_lifesteal={15,25,40}},low(.45),8)
consume('W-c3',{},time(5,20),15)
consume('W-c4',{base_damage_pct={25,40,60},move_speed={15,25,35}},time(8,14),10)
consume('W-c5',{},time(5),8); consume('W-c6',{},time(5),10)
consume('W-c7',{evasion={20,35,50}},low(.5),8)
field('E-f1','friendly',{mana_regen={8,16,29}}); field('E-f2','enemy',{move_speed={-10,-18,-28}})
field('E-f3','friendly',{}); field('E-f4','enemy',{})
field('C-f1','friendly',{move_speed={15,24,35}}); field('C-f2','enemy',{attack_speed={-16,-32,-50}})
field('C-f3','friendly',{incoming_damage={-4,-7,-12}})
field('C-f4','friendly',{health_regen={50,80,130},field_heal_amp={0,0,15}})
field('D-f2','friendly',{health_regen_pct={1,1.6,2.4}}); field('D-f4','enemy',{})
field('A-f1','enemy',{heal_amp={-30,-45,-60}}); field('A-f2','enemy',{}); field('A-f3','enemy',{})
field('A-f4','enemy',{armor={-7,-13,-20}})
field('W-f1','enemy',{miss={20,35,50}}); field('W-f3','enemy',{}); field('W-f4','enemy',{})
-- Elemental original designs promise a first activation, not an invented repeat interval.
for _,id in ipairs({'E-c1','E-c3','E-c5','E-c6'}) do D[id].trigger.once=true end
-- Native shields and casting strong illusions require engine integration not provided
-- by recipient card stats. Keep these out of the executable/equip allowlist.
D['D-g5']=nil;D['D-c2']=nil;D['D-g3']=nil
return D
