-- Native API doubles for offline contracts, not a simulation of Dota spell logic.
local H={}
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET=8; DOTA_ABILITY_BEHAVIOR_POINT=16
DOTA_ABILITY_BEHAVIOR_NO_TARGET=4; DOTA_ABILITY_BEHAVIOR_TOGGLE=512
DOTA_ABILITY_BEHAVIOR_CHANNELLED=128; DOTA_ABILITY_BEHAVIOR_AUTOCAST=4096
DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING=1073741824; DOTA_ABILITY_BEHAVIOR_ALT_CASTABLE=2^36
DOTA_UNIT_TARGET_TEAM_FRIENDLY=1; DOTA_UNIT_TARGET_TEAM_ENEMY=2; DOTA_UNIT_TARGET_TEAM_BOTH=3; DOTA_UNIT_TARGET_TEAM_CUSTOM=4
DOTA_UNIT_TARGET_HERO=1; DOTA_UNIT_TARGET_CREEP=2; DOTA_UNIT_TARGET_BUILDING=4
DOTA_UNIT_TARGET_COURIER=16; DOTA_UNIT_TARGET_BASIC=18; DOTA_UNIT_TARGET_TREE=64; DOTA_UNIT_TARGET_CUSTOM=128
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=16; DOTA_UNIT_TARGET_FLAG_NOT_MAGIC_IMMUNE_ALLIES=32; DOTA_UNIT_TARGET_FLAG_NOT_SELF=4096
DOTA_UNIT_ORDER_CAST_TARGET=6; DOTA_UNIT_ORDER_CAST_POSITION=5; DOTA_UNIT_ORDER_CAST_NO_TARGET=8
DOTA_UNIT_ORDER_CAST_TOGGLE=9; DOTA_UNIT_ORDER_CAST_TOGGLE_AUTO=20
DOTA_UNIT_ORDER_ATTACK_TARGET=4; DOTA_UNIT_ORDER_MOVE_TO_POSITION=1; DOTA_UNIT_ORDER_MOVE_TO_TARGET=2
UF_SUCCESS=0
local vector={}
function Vector(x,y,z) return setmetatable({x=x,y=y or 0,z=z or 0},vector) end
vector.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vector.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vector.__div=function(a,b) return Vector(a.x/b,a.y/b,a.z/b) end
vector.__index={Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}
local nextid=100
function H.unit(team,x,y)
 nextid=nextid+1
 local u={id=nextid,team=team or 2,position=Vector(x or 0,y or 0,0),hp=100,mana=100,abilities={},channel=false,modifiers={}}
 function u:entindex() return self.id end
 function u:IsNull() return false end
 function u:IsAlive() return self.hp>0 end
 function u:GetAbsOrigin() return self.position end
 function u:GetHealth() return self.hp end
 function u:GetMaxHealth() return 100 end
 function u:GetMana() return self.mana end
 function u:GetMaxMana() return 100 end
 function u:GetTeamNumber() return self.team end
 function u:GetUnitName() return 'npc_dota_hero_test' end
 function u:IsHero() return true end
 function u:IsRealHero() return true end
 function u:IsChanneling() return self.channel end
 function u:GetCurrentActiveAbility() return self.active end
 function u:FindAbilityByName(name) return self.abilities[name] end
 function u:GetItemInSlot() return nil end
 function u:IsMagicImmune() return self.immune or false end
 function u:HasModifier(name) return self.modifiers[name]~=nil end
 function u:FindModifierByName(name) return self.modifiers[name] end
 function u:FindAllModifiers() local out={} for _,m in pairs(self.modifiers) do out[#out+1]=m end return out end
 function u:Script_GetAttackRange() return 150 end
 function u:GetAttackRange() return 150 end
 return u
end
function H.ability(hero,name,behavior,team,types,flags)
 nextid=nextid+1
 local a={id=nextid,name=name,behavior=behavior or 8,team=team or 2,types=types or 1,flags=flags or 0,
  radius=0,range=800,level=1,values={},auto=false,toggle=false,hidden=false,activated=true,castable=true,cooldown=true,maxcharges=0,charges=0,channelstart=0}
 function a:entindex() return self.id end
 function a:IsNull() return false end
 function a:GetAbilityName() return self.name end
 function a:GetBehavior() return self.behavior end
 function a:GetBehaviorInt() return self.behavior end
 function a:GetAbilityTargetTeam() return self.team end
 function a:GetAbilityTargetType() return self.types end
 function a:GetAbilityTargetFlags() return self.flags end
 function a:GetAOERadius() return self.radius end
 function a:GetCastRange() return self.range end
 function a:GetEffectiveCastRange() return self.range end
 function a:GetSpecialValueFor(key) return self.values[key] or 0 end
 function a:GetLevel() return self.level end
 function a:IsHidden() return self.hidden end
 function a:IsActivated() return self.activated end
 function a:IsPassive() return false end
 function a:IsFullyCastable() return self.castable end
 function a:IsCooldownReady() return self.cooldown end
 function a:GetMaxAbilityCharges() return self.maxcharges end
 function a:GetCurrentAbilityCharges() return self.charges end
 function a:GetAutoCastState() return self.auto end
 function a:GetToggleState() return self.toggle end
 function a:GetChannelStartTime() return self.channelstart end
 function a:IsInAbilityPhase() return self.winding or false end
 function a:CastFilterResultLocation() return 0 end
 function a:CastFilterResultTarget() return 0 end
 hero.abilities[name]=a
 return a
end
function H.rule(name,team)
 return {enabled=true,action={kind='ability',name=name,logical_id=name},target={team=team or 'enemy',types={'hero','monster','summon'}},
  use_conditions={},target_filters={},target_priorities={},approach='range_only'}
end
return H
