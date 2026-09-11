local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_ABILITY_BEHAVIOR_POINT=16
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4; DOTA_ABILITY_BEHAVIOR_TOGGLE=512; DOTA_ABILITY_BEHAVIOR_PASSIVE=2
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1; DOTA_UNIT_TARGET_TEAM_ENEMY=2
DOTA_UNIT_ORDER_CAST_TARGET=6; DOTA_UNIT_ORDER_CAST_POSITION=5
DOTA_UNIT_ORDER_CAST_NO_TARGET=8; DOTA_UNIT_ORDER_CAST_TOGGLE=9; DOTA_UNIT_ORDER_ATTACK_TARGET=4
local vm={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vm) end
vm.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__div=function(a,b) return Vector(a.x/b,a.y/b,a.z/b) end
vm.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
vm.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end}
local clock=10
GameRules={GetGameTime=function() return clock end}
local Engine=require("tactics/tactic_engine")
local Context=require("tactics/condition_context")
local EnemyRules=require("issue_fixes.enemy_rules")
local function unit(id,x,team)
 local u={id=id,x=x,team=team,hp=100,mana=100,items={},spells={}}
 function u:entindex() return self.id end
 function u:GetAbsOrigin() return Vector(self.x,0,0) end
 function u:GetForwardVector() return Vector(self.facing or 1,0,0) end
 function u:GetHealth() return self.hp end
 function u:GetMaxHealth() return 100 end
 function u:GetMana() return self.mana end
 function u:GetMaxMana() return 100 end
 function u:IsAlive() return self.hp>0 end
 function u:IsNull() return false end
 function u:GetTeamNumber() return self.team end
 function u:IsMuted() return self.muted==true end
 function u:IsChanneling() return self.channeling==true end
 function u:IsStunned() return self.stunned==true end
 function u:HasModifier(name) return (self.modifiers or {})[name]==true end
 function u:GetItemInSlot(slot) return self.items[slot] end
 function u:GetAbilityCount() return #self.spells end
 function u:GetAbilityByIndex(slot) return self.spells[slot+1] end
 function u:FindAbilityByName(name) for _,a in ipairs(self.spells) do if a.name==name then return a end end end
 function u:Script_GetAttackRange() return 150 end
 return u
end
local nextID=100
local function item(name,behavior,range,team)
 nextID=nextID+1
 local a={id=nextID,name=name,behavior=behavior or 4,range=range or 600,team=team or 2,charges=5,level=1}
 function a:GetAbilityName() return self.name end
 function a:entindex() return self.id end
 function a:GetBehaviorInt() return self.behavior end
 function a:GetLevel() return self.level end
 function a:GetAbilityTargetTeam() return self.team end
 function a:GetCastRange() return self.range end
 function a:GetAOERadius() return self.radius or 0 end
 function a:GetSpecialValueFor(key) return (self.specials or {})[key] or 0 end
 function a:IsFullyCastable() return self.castable~=false end
 function a:IsCooldownReady() return not self.cooldown end
 function a:GetCooldownTimeRemaining() return self.remaining or (self.cooldown and 30 or 0) end
 function a:GetManaCost() return 0 end
 function a:GetCurrentCharges() return self.charges end
 function a:IsPassive() return self.passive==true end
 function a:IsHidden() return self.hidden==true end
 function a:IsActivated() return self.activated~=false end
 function a:GetToggleState() return self.on==true end
 function a:CastFilterResultTarget(target) return ((self.team==1 and target.team==2) or (self.team==2 and target.team==3)) and 0 or 1 end
 return a
end
local caster=unit(1,0,2); local enemy=unit(2,400,3)
local opponents={enemy}
local orders={}
local engine=Engine.new({order_gate={Execute=function(_,o) orders[#orders+1]=o end},
 get_phase=function() return "FIGHT" end,get_battle_units=function() return {caster,enemy} end,
 get_rules=function() return EnemyRules.CreateForUnit(caster,{},opponents) end,
 build_context=function() return {resolve_action_name=function(_,name) return name end,
  get_candidates=function(_,_,target) return target.team=="enemy" and {enemy} or {caster} end,
  count_enemies_around=function(center,radius) return Context.CountAround({caster,enemy},center,radius,false) end} end})
local function attempt()
 engine:Reset();orders={}
 local rules=EnemyRules.CreateForUnit(caster,{},opponents)
 for i,r in ipairs(rules) do
  if engine:TryRule(caster,engine:GetState(caster),engine:BuildContext(caster,10),r,i) then return orders[1],rules end
 end
 return nil,rules
end
local function equip(a) caster.items={[0]=a};caster.spells={};caster.hp=100;caster.mana=100;enemy.x=400;return a end
local wand=equip(item("item_magic_wand"));caster.hp=50
assert(attempt() and orders[1].AbilityIndex==wand.id,"equipped charged wand must actually issue native item order at half HP")
caster.hp=51;assert(not attempt(),"wand above both thresholds must not cast")
caster.mana=25;assert(attempt() and orders[1].AbilityIndex==wand.id,"wand mana threshold is OR, not AND")
wand.charges=0;assert(not attempt(),"empty wand cannot cast")
wand.charges=5;caster.mana=100;caster.hp=50
for _,state in ipairs({"muted","channeling","stunned"}) do caster[state]=true;assert(not attempt(),state.." blocks item order");caster[state]=false end
wand.cooldown=true;assert(not attempt(),"native item cooldown blocks order");wand.cooldown=false
wand.castable=false;assert(not attempt(),"native mana/castability blocks order");wand.castable=true
for slot=6,16 do caster.items={[slot]=wand};assert(not attempt(),"unequipped slot "..slot.." cannot generate item order") end
for _,field in ipairs({"passive","hidden"}) do equip(wand);caster.hp=40;wand[field]=true;assert(not attempt(),field.." item omitted");wand[field]=false end
wand.activated=false;assert(not attempt());wand.activated=true
wand.level=0;assert(not attempt());wand.level=1
local bkb=equip(item("item_black_king_bar"));enemy.x=1500
assert(not attempt(),"BKB cannot open far away");enemy.x=400
assert(attempt() and orders[1].AbilityIndex==bkb.id,"BKB casts in combat")
local sheep=equip(item("item_sheepstick",8,800));enemy.x=850
assert(not attempt(),"enemy control respects native range");enemy.x=700
assert(attempt() and orders[1].TargetIndex==enemy.id,"offensive control targets opponent")
sheep.CastFilterResultTarget=function() return 1 end;assert(not attempt(),"native target filter respected")
local satanic=equip(item("item_satanic"));caster.hp=41;assert(not attempt())
caster.hp=40;assert(attempt() and orders[1].AbilityIndex==satanic.id)
enemy.x=1500;assert(not attempt(),"satanic needs enemy and low HP")
local blink=equip(item("item_blink",16,1200));enemy.x=300;assert(not attempt(),"no pointless short blink")
enemy.x=900;assert(attempt() and orders[1].Position.x==900,"blink uses native point order toward enemy")
enemy.x=1250;assert(not attempt(),"no overshoot blink")
for _,name in ipairs({"item_overwhelming_blink","item_swift_blink","item_arcane_blink"}) do
 local distance=name=="item_arcane_blink" and 1400 or 1200
 local upgraded=equip(item(name,16,distance));upgraded.specials={blink_range=distance}
 enemy.x=distance-1
 assert(attempt() and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_POSITION and orders[1].Position.x==enemy.x,name.." uses its native blink range")
 enemy.x=distance+1;assert(not attempt(),name.." cannot overshoot")
 enemy.x=900;upgraded.cooldown=true;assert(not attempt(),name.." preserves native damage cooldown")
end
local nullifier=equip(item("item_nullifier",8,900))
assert(attempt() and orders[1].TargetIndex==enemy.id,"Nullifier targets a legal enemy")
nullifier.CastFilterResultTarget=function() return 1 end;assert(not attempt(),"Nullifier respects native target rejection")
local gleipnir=equip(item("item_gungir",16,1100));enemy.x=1000
assert(attempt() and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_POSITION,"Gleipnir uses a native point order")
enemy.x=1200;assert(not attempt(),"Gleipnir respects cast range")
local radiance=equip(item("item_radiance",516));caster.hp=10
assert(attempt() and orders[1].OrderType==DOTA_UNIT_ORDER_CAST_TOGGLE,"Radiance burn can be enabled at low HP")
radiance.on=true;assert(not attempt(),"Radiance is never toggled off")
caster.spells={item("radiance_followup",8,600)}
assert(attempt() and orders[1].AbilityIndex==caster.spells[1].id,"already active Radiance yields to spells")
local shiva=equip(item("item_shivas_guard"));shiva.specials={blast_radius=825};enemy.x=826;assert(not attempt())
enemy.x=825;assert(attempt() and orders[1].AbilityIndex==shiva.id,"Shiva uses blast radius")
local greaves=equip(item("item_guardian_greaves"));caster.hp=60
assert(attempt() and orders[1].AbilityIndex==greaves.id);caster.hp=100;assert(not attempt(),"no full HP greaves")
local armlet=equip(item("item_armlet",516));local spell=item("test_spell",8,600);caster.spells={spell}
assert(attempt() and orders[1].AbilityIndex==armlet.id,"combat toggle-on first")
armlet.on=true;assert(attempt() and orders[1].AbilityIndex==spell.id,"already-on toggle cannot starve spells")
spell.cooldown=true;enemy.x=100;assert(attempt() and orders[1].OrderType==DOTA_UNIT_ORDER_ATTACK_TARGET,"unavailable items/spells fall through to attack")
local replacement=item("item_blade_mail");caster.items[0]=replacement;enemy.x=400
assert(attempt() and orders[1].AbilityIndex==replacement.id,"current inventory replacement is reflected immediately")
-- Native Warlock order: Chaotic Offering precedes a ready channelled Upheaval.
local upheaval=equip(item("warlock_upheaval",16,900));caster.items={}
local offering=item("warlock_rain_of_chaos",16,1200)
offering.GetAbilityType=function() return 1 end
caster.spells={upheaval,offering}
assert(attempt() and orders[1].AbilityIndex==offering.id,"enemy ultimate precedes lower native slot/channel")
offering.cooldown=true
assert(attempt() and orders[1].AbilityIndex==upheaval.id,"unavailable ultimate yields to basic spell")
offering.cooldown=false;offering.range=100
assert(attempt() and orders[1].AbilityIndex==upheaval.id,"ultimate without legal target cannot starve basics")
local reincarnation=equip(item("skeleton_king_reincarnation",8,600,1));caster.items={};caster.spells={reincarnation}
assert(not attempt() and #orders==0,"full HP WK emits no active Reincarnation order")
-- Model only the native lethal callback; this demonstrates no policy mutation,
-- not an in-Dota proof of rebirth animation, mana spending or lethal behavior.
local nativeRebirths=0
function caster:NativeLethalDamage() self.hp=0;if self.spells[1]==reincarnation and not reincarnation.cooldown then nativeRebirths=nativeRebirths+1;self.hp=100 end end
caster:NativeLethalDamage();assert(nativeRebirths==1 and reincarnation.level==1 and not reincarnation.cooldown,"native lethal callback remains available")
-- Exercise each additional reviewed active policy through native order selection.
for _,name in ipairs({"item_pipe","item_crimson_guard","item_blade_mail","item_manta","item_phase_boots","item_silver_edge","item_mjollnir","item_boots_of_bearing"}) do
 local a=equip(item(name,name=="item_mjollnir" and 8 or 4,800,1))
 assert(attempt() and orders[1].AbilityIndex==a.id,name.." casts near enemy")
 enemy.x=1500;assert(not attempt(),name.." rejects distant enemy")
end
for _,name in ipairs({"item_bloodthorn","item_diffusal_blade","item_disperser","item_heavens_halberd","item_abyssal_blade","item_harpoon","item_meteor_hammer"}) do
 local nativeRanges={item_bloodthorn=900,item_diffusal_blade=600,item_disperser=600,item_heavens_halberd=750,item_abyssal_blade=150,item_harpoon=700,item_meteor_hammer=600}
 local a=equip(item(name,name=="item_meteor_hammer" and 16 or 8,nativeRanges[name]))
 enemy.x=math.min(400,nativeRanges[name]-25)
 assert(attempt() and orders[1].AbilityIndex==a.id,name.." uses native offensive action")
 enemy.x=1500;assert(not attempt(),name.." cannot cast outside native range")
end
for _,name in ipairs({"item_glimmer_cape","item_lotus_orb","item_bloodstone","item_hurricane_pike"}) do
 local a=equip(item(name,name=="item_bloodstone" and 4 or 8,900,name=="item_hurricane_pike" and 2 or 1))
 assert(not attempt(),name.." saves its active at full HP")
 caster.hp=60;assert(attempt() and orders[1].AbilityIndex==a.id,name.." acts at low HP")
 enemy.x=1500;assert(not attempt(),name.." requires combat proximity")
end
for _,name in ipairs({"item_cyclone","item_wind_waker"}) do
 local a=equip(item(name,8,550,4))
 a.CastFilterResultTarget=function() return 0 end
 assert(attempt() and orders[1].TargetIndex==enemy.id,name.." controls legal enemy")
 caster.hp=25;assert(attempt() and orders[1].TargetIndex==caster.id,name.." saves self at critical HP")
end
local vessel=equip(item("item_spirit_vessel",8,750,3))
vessel.CastFilterResultTarget=function() return 0 end
assert(attempt() and orders[1].TargetIndex==enemy.id,"charged vessel attacks when nobody needs healing")
caster.hp=50;assert(attempt() and orders[1].TargetIndex==caster.id,"charged vessel heals low HP ally first")
vessel.charges=0;assert(not attempt(),"uncharged vessel omitted")
local arcane=equip(item("item_arcane_boots"));assert(not attempt());caster.mana=50
assert(attempt() and orders[1].AbilityIndex==arcane.id,"arcane boots recover missing mana")
local mask=equip(item("item_mask_of_madness"));local readySpell=item("native_spell",8,600);caster.spells={readySpell}
assert(attempt() and orders[1].AbilityIndex==readySpell.id,"Mask cannot silence ready opening spell")
readySpell.cooldown=true;assert(attempt() and orders[1].AbilityIndex==mask.id,"Mask buffs attacks after spells unavailable")
readySpell.remaining=5.9;assert(not attempt(),"Mask cannot silence a spell recovering within native six-second Berserk")
readySpell.remaining=6;assert(attempt() and orders[1].AbilityIndex==mask.id,"Mask accepts cooldown lasting through Berserk")
readySpell.GetCurrentAbilityCharges=function() return 1 end
assert(not attempt(),"an available native ability charge prevents Mask even during its cooldown")
readySpell.GetCurrentAbilityCharges=nil;readySpell.remaining=nil
local refresher=equip(item("item_refresher"));assert(not attempt(),"Refresher never opens with no cooldowns")
local spent1=item("spent_spell_one",8,600);local spent2=item("spent_spell_two",8,600)
spent1.cooldown=true;spent2.cooldown=true;caster.spells={spent1,spent2}
assert(attempt() and orders[1].AbilityIndex==refresher.id,"Refresher waits for two spent spells")
caster.mana=59;assert(not attempt(),"Refresher reserves mana for follow-up spells")
local force=equip(item("item_force_staff",8,600,1));force.specials={push_length=600}
caster.hp=35;caster.facing=1
assert(not attempt(),"Force Staff cannot push a low-HP caster toward enemies")
caster.facing=-1
assert(attempt() and orders[1].AbilityIndex==force.id and orders[1].TargetIndex==caster.id,"Force Staff self-save when native facing moves away from threats")
caster.hp=36;assert(not attempt(),"Force Staff saves its active above the HP threshold")
caster.hp=35;opponents={enemy,unit(3,-500,3)}
assert(not attempt(),"Force Staff rejects escape toward another observed enemy behind caster")
opponents={enemy};caster.facing=0
assert(not attempt(),"missing usable facing cannot invent a displacement")
caster.facing=nil
for _,name in ipairs({"item_power_treads","item_bfury","item_tpscroll","item_moon_shard","item_unreviewed"}) do
 equip(item(name));local _,rules=attempt();assert(#rules==1,name.." intentionally has no speculative action")
end
for _,name in ipairs({"item_aeon_disk","item_aether_lens","item_assault","item_basher","item_bracer","item_butterfly","item_desolator","item_dragon_lance","item_echo_sabre","item_eternal_shroud","item_greater_crit","item_heart","item_kaya","item_kaya_and_sange","item_maelstrom","item_octarine_core","item_sange_and_yasha","item_skadi","item_ultimate_scepter","item_wind_lace","item_wraith_band","item_yasha"}) do
 equip(item(name,2));local _,rules=attempt();assert(#rules==1,name.." native passive generates no action")
end
-- Priority is independent of inventory slot ordering.
equip(item("item_sheepstick",8,800));local rescue=item("item_magic_wand");caster.items[5]=rescue;caster.hp=40
assert(attempt() and orders[1].AbilityIndex==rescue.id,"defensive item in slot five beats control in slot zero")
-- Sequential actual evaluation retains lifecycle and engine state between item,
-- fade, opening attack, and the next spell. A reset-per-attempt test misses this.
local edge=equip(item("item_silver_edge"));edge.specials={windwalk_fade_time=0.3}
local waitingSpell=item("opening_spell",8,600);caster.spells={waitingSpell};enemy.x=100
engine:Reset();orders={};clock=20
local state=engine:GetState(caster)
engine:EvaluateUnit(caster,state,clock)
assert(#orders==1 and orders[1].AbilityIndex==edge.id,"Silver Edge begins the opener")
edge.cooldown=true;caster.modifiers={modifier_item_silver_edge_windwalk=true}
clock=20.1;engine:EvaluateUnit(caster,state,clock)
assert(#orders==1 and state.wait_until>=20.29,"native fade period cannot be interrupted by spell or early attack")
clock=20.31;engine:EvaluateUnit(caster,state,clock)
assert(#orders==2 and orders[2].OrderType==DOTA_UNIT_ORDER_ATTACK_TARGET,"observed windwalk prioritizes first attack over a ready spell")
clock=20.4;engine:EvaluateUnit(caster,state,clock)
assert(#orders==2,"retained engine state continues the same attack without substituting a spell")
caster.rpgTacticsEvents.attack={time=20.6,target=enemy};caster.modifiers={}
clock=20.7;engine:EvaluateUnit(caster,state,clock)
assert(#orders==3 and orders[3].AbilityIndex==waitingSpell.id,"native windwalk end resumes normal spells")
-- A submitted item order is not proof of native invisibility: only the bounded
-- fade grace applies when the native modifier never appears.
engine:Reset();orders={};clock=30;edge.cooldown=false
state=engine:GetState(caster);engine:EvaluateUnit(caster,state,clock);edge.cooldown=true
clock=30.31;engine:EvaluateUnit(caster,state,clock)
assert(#orders==2 and orders[2].AbilityIndex==waitingSpell.id,"unconfirmed windwalk cannot lock the hero for its full duration")
print("enemy-item-rules.test.lua: passed native Engine/adapter item conditions, orders, exclusions, dynamic inventory, WK omission, Silver Edge opener and Mask silence window")
