-- Run from repo root: lua tests/endless-card-effects.test.lua
package.path = "game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;" .. package.path
function class(t) t.__index=t; return t end
function IsServer() return true end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS=2
DOTA_UNIT_TARGET_TEAM_BOTH=3
DOTA_UNIT_TARGET_HERO=1
DOTA_UNIT_TARGET_BASIC=2
FIND_ANY_ORDER=0
local clock, world = 0, {}
GameRules={GetGameTime=function() return clock end}
function FindUnitsInRadius(team, origin, cache, radius, side, types)
    assert(radius == -1 and side == 3 and types == 3, "whole battlefield query")
    return world
end
local Modifier=require("modifiers/modifier_endless_card_stats")
local Effects=require("endless/card_effects")
local NAME="modifier_endless_card_stats"
local function unit(team, hero)
    local u={team=team,hp=100,maxhp=100,alive=true,hero=hero,mods={},adds=0}
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return self.alive end
    function u:IsRealHero() return self.hero end
    function u:IsIllusion() return self.illusion or false end
    function u:GetTeamNumber() return self.team end
    function u:GetHealth() return self.hp end
    function u:GetMaxHealth() return self.maxhp end
    function u:HasModifier(name) return self.mods[name] ~= nil end
    function u:FindModifierByName(name) return self.mods[name] end
    function u:RemoveModifierByName(name) self.mods[name]=nil end
    function u:AddNewModifier(caster, ability, name)
        assert(caster==nil, "effects must not belong to carrier")
        self.adds=self.adds+1
        local m=setmetatable({parent=self},Modifier)
        function m:GetParent() return self.parent end
        m:OnCreated(); self.mods[name]=m; return m
    end
    return u
end
local a,b,e,commander=unit(2,true),unit(2,true),unit(3,true),unit(2,true)
local game={placeholderHero=commander,battleManager={teamHeroes={[2]={a,b},[3]={e}}}}
local function at(t) clock=t; Effects.Tick(game) end
local function stat(u,key) return u.mods[NAME] and (u.mods[NAME].stats[key] or 0) or 0 end
local function eq(actual,expected,message) assert(actual==expected,(message or "value")..": "..tostring(actual).." ~= "..tostring(expected)) end
world={a,b,e,commander,a}
local count=0
for _ in pairs(Effects.definitions) do count=count+1 end
eq(count,17)
local state=Effects.Start(game,{{id="C-g1",load=2,hero=a},{id="C-g1",load=3},{id="E-f2",load=3},{id="A-f4",load=2},{id="E-g4",load=3},{id="D-g1",load=4}})
eq(#state.cards,3,"unique and supported valid levels only")
eq(stat(a,"attack_speed"),35); eq(stat(b,"attack_speed"),35)
eq(stat(e,"move_speed"),-28); eq(stat(e,"armor"),-13)
eq(commander.mods[NAME],nil)
for i=1,10 do at(i/10) end
eq(a.adds,1,"ticks cannot stack modifiers")
a.alive=false
local summon=unit(2,false); world[#world+1]=summon
at(2); eq(stat(summon,"attack_speed"),35); eq(stat(e,"armor"),-13,"carrier death leaves field")
-- Adopt an already present inherited modifier instead of adding a second copy.
local illusion=unit(2,true); illusion.illusion=true
illusion:AddNewModifier(nil,nil,NAME):SetStats({attack_speed=35})
world[#world+1]=illusion
at(3); eq(illusion.adds,1); eq(stat(illusion,"attack_speed"),35)
Effects.Stop(game)
for _,u in ipairs(world) do eq(u.mods[NAME],nil,"cleanup all recipients") end
Effects.Stop(game); at(4)
clock=100; a.alive=true
state=Effects.Start(game,{{id="C-c1",load=2},{id="W-g5",load=1},{id="W-c4",load=1}})
eq(stat(a,"base_damage_pct"),12)
at(104.99); eq(state.cards[1].remaining,2)
at(105); eq(state.cards[1].remaining,1); eq(stat(a,"base_damage_pct"),72)
at(108); eq(state.cards[3].remaining,0); eq(stat(a,"base_damage_pct"),97)
at(113); eq(stat(a,"base_damage_pct"),37,"first buff expiry")
at(117); eq(state.cards[1].remaining,0); eq(stat(a,"base_damage_pct"),97,"last charge still active")
at(118); eq(stat(a,"base_damage_pct"),72)
at(125); eq(stat(a,"base_damage_pct"),12)
at(150); eq(state.cards[1].remaining,0)
-- Low-health triggers require living deployed hero bodies; team shares one charge.
clock=200; a.hp=70; b.hp=100; summon.hp=1; illusion.hp=1; commander.hp=1
state=Effects.Start(game,{{id="D-c1",load=3},{id="D-g2",load=1},{id="A-g1",load=3}})
eq(state.cards[1].remaining,3,"strict below threshold; summons excluded")
a.hp=69; b.hp=60; at(201)
eq(state.cards[1].remaining,2); eq(state.cards[1].next_trigger,213)
eq(stat(a,"health_regen_pct"),4.9); eq(stat(summon,"health_regen_pct"),4.9)
at(210.9); eq(state.cards[1].remaining,2)
at(211); eq(stat(a,"health_regen_pct"),0.4)
at(213); eq(state.cards[1].remaining,1)
a.hp=0; eq(a.mods[NAME]:GetModifierConstantHealthRegen(),50)
a.hp=100; eq(a.mods[NAME]:GetModifierConstantHealthRegen(),15)
at(225); eq(state.cards[1].remaining,0); eq(stat(b,"health_regen_pct"),4.9)
at(235); eq(stat(b,"health_regen_pct"),0.4)
-- Starting another battle removes all effects and resets relative timers.
clock=300; Effects.Start(game,{{id="W-c4",load=3}})
eq(stat(a,"health_regen_pct"),0); eq(stat(a,"base_damage_pct"),0)
at(308); eq(stat(a,"base_damage_pct"),60)
at(320); eq(stat(a,"base_damage_pct"),0)
at(322); eq(game.endlessCardCombat.cards[1].remaining,1)
at(336); eq(game.endlessCardCombat.cards[1].remaining,0)
at(346); eq(a.mods[NAME],nil)
-- Removing a unit from the legal battlefield also strips its old bonus.
Effects.Start(game,{{id="C-g1",load=1}})
b.mods.modifier_rpg_prepare_bench={}; at(347); eq(b.mods[NAME],nil)
Effects.Stop(game)
Effects.Start(game,{{id="C-g5",load=3}})
eq(a.mods[NAME]:GetModifierPercentageCooldown({ability={IsItem=function()return false end}}),24)
eq(a.mods[NAME]:GetModifierPercentageCooldown({ability={IsItem=function()return true end}}),0)
eq(a.mods[NAME]:GetModifierPercentageCooldown(nil),0)
Effects.Stop(game)
print("endless-card-effects: 17 definitions; lifecycle, timers, thresholds, fields, skill-only cooldown and no-stacking passed")
