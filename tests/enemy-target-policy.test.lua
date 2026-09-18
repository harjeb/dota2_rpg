local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local Policy=require("issue_fixes.enemy_target_policy")
local Selector=require("tactics/target_selector").new()
local vector={}
vector.__index=vector
function vector.__sub(a,b) return setmetatable({x=a.x-b.x,y=0},vector) end
function vector:Length2D() return math.abs(self.x) end
local function unit(id,x,hp,maxhp,armor,mr)
    local u={id=id,x=x,hp=hp,maxhp=maxhp,armor=armor,mr=mr,real=true}
    function u:IsNull() return false end
    function u:IsAlive() return self.hp>0 end
    function u:IsRealHero() return self.real end
    function u:IsIllusion() return self.illusion==true end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return self.maxhp end
    function u:GetPhysicalArmorValue() return self.armor end
    function u:GetMagicalArmorValue() return self.mr end
    function u:GetAbsOrigin() return setmetatable({x=self.x,y=0},vector) end
    function u:entindex() return self.id end
    function u:IsInvulnerable() return self.invulnerable==true end
    function u:IsAttackImmune() return self.attackImmune==true end
    function u:IsOutOfGame() return false end
    function u:IsMagicImmune() return false end
    function u:IsChanneling() return self.channeling==true end
    function u:Script_GetAttackRange() return self.range or 600 end
    return u
end
local caster=unit(1,0,1000,1000,0,0)
local tank=unit(2,150,2500,10000,30,0.6)
local carry=unit(3,500,1400,1400,5,0.25)
local candidates={tank,carry}
local ctx={caster=caster,get_candidates=function() return candidates end,
    is_in_range=function(_,target) return target.x<=caster:Script_GetAttackRange() end}
local rule={action={kind="attack"},target={team="enemy"},target_priorities={{type="lowest_hp_pct"}},
    target_filters={},approach="range_only"}
local spec={kind="attack",target_mode="unit"}
assert(Selector:SelectUnit(rule,spec,ctx)==tank,"old percentage priority fixates wounded tank")
Policy.Apply(caster,rule)
assert(Selector:SelectUnit(rule,spec,ctx)==carry,"attack selects reachable lower effective-health core")
assert(rule.approach=="range_only","ranking never grants permission to chase")
tank.hp=100
assert(Selector:SelectUnit(rule,spec,ctx)==tank,"finish a killable tank instead of rigidly ignoring frontline")
tank.hp=2500;carry.x=900
assert(Selector:SelectUnit(rule,spec,ctx)==tank,"unreachable backline cannot stall an in-range attack")
rule.approach="allow_approach";caster.range=150;carry.x=1200
Policy.Apply(caster,rule)
assert(Selector:SelectUnit(rule,spec,ctx)==tank,"melee will not run past frontline for a distant full-health target")
carry.x=300
assert(Selector:SelectUnit(rule,spec,ctx)==carry,"short step toward exposed core is worthwhile")
caster.range=600;carry.x=500;rule.approach="range_only"
Policy.Apply(caster,rule)
carry.invulnerable=true
assert(Selector:SelectUnit(rule,spec,ctx)==tank,"native invulnerability wins over score")
carry.invulnerable=false;carry.attackImmune=true
assert(Selector:SelectUnit(rule,spec,ctx)==tank,"native attack immunity wins over score")
carry.attackImmune=false
-- Damage-type defenses matter: a low armor/high magic resistance target is an
-- attack opportunity but a poor magic-burst target.
tank.hp=1000;tank.armor=0;tank.mr=0.8;carry.hp=1000;carry.armor=20;carry.mr=0.1
assert(Selector:SelectUnit(rule,spec,ctx)==tank)
local ability={GetAbilityDamageType=function() return 2 end,GetCastRange=function() return 600 end,
    CastFilterResultTarget=function(_,target) return target.reject and 1 or 0 end}
local spell={action={kind="ability",logical_id="lina_laguna_blade"},target={team="enemy"},
    target_filters={},approach="range_only"}
Policy.Apply(caster,spell,ability)
local spellSpec={kind="ability",target_mode="unit",ability=ability}
assert(Selector:SelectUnit(spell,spellSpec,ctx)==carry,"magic burst accounts for magic resistance")
carry.reject=true
assert(Selector:SelectUnit(spell,spellSpec,ctx)==tank,"native cast filter remains authoritative")
carry.reject=false
ability.GetAbilityDamageType=function() return 4 end
Policy.Apply(caster,spell,ability)
assert(Selector:SelectUnit(spell,spellSpec,ctx)==tank,"pure damage ignores both defenses")
spell.action.logical_id="lion_voodoo";tank.channeling=true
Policy.Apply(caster,spell,ability)
assert(Selector:SelectUnit(spell,spellSpec,ctx)==tank,"control interrupts channeling before normal damage ranking")
local pike={action={kind="item",logical_id="item_hurricane_pike"},target={team="enemy"},
    target_priorities={{type="nearest"}}}
Policy.Apply(caster,pike,ability)
assert(pike.target_priorities[1].type=="nearest","defensive Pike keeps nearest-threat targeting")
local ally={action={kind="ability"},target={team="ally"},target_priorities={{type="lowest_hp_pct"}}}
Policy.Apply(caster,ally,ability)
assert(ally.target_priorities[1].type=="lowest_hp_pct","healing target priorities survive")
local objective={action={kind="attack"},target={team="enemy"},enemy_attack_objective=true,
    target_priorities={{type="nearest"}}}
Policy.Apply(caster,objective)
assert(objective.target_priorities[1].type=="nearest","eggs/tombstones remain dedicated objectives")
caster.real=false
local creep={action={kind="attack"},target={team="enemy"},target_priorities={{type="nearest"}}}
Policy.Apply(caster,creep)
assert(creep.target_priorities[1].type=="nearest","neutral combat behavior remains separate")
print("enemy-target-policy.test.lua: passed")
