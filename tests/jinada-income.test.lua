local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
function class(t) return t end
local server=true
function IsServer() return server end
DOTA_TEAM_GOODGUYS=2; DOTA_UNIT_ORDER_CAST_TARGET=6; DOTA_UNIT_ORDER_ATTACK_TARGET=4
LUA_MODIFIER_MOTION_NONE=0
function LinkLuaModifier() end
local time=0
GameRules={GetGameTime=function() return time end}
local Income=require("issue_fixes/jinada_income")
local gold, writes=0,0
local game={phase="fight",playerId=0}
function game:AddGold(amount) gold=gold+amount; writes=writes+1 end
function game:GetGoldBalance() return gold end
local ability={level=4,ready=true,auto=true,cooldown=3,talent=0}
function ability:GetAbilityName() return "bounty_hunter_jinada" end
function ability:GetLevel() return self.level end
function ability:IsCooldownReady() return self.ready end
function ability:GetAutoCastState() return self.auto end
function ability:GetEffectiveCooldown() return self.cooldown end
function ability:GetIntrinsicModifierName() return "modifier_native_jinada" end
local hero={lineupHeroName="npc_dota_hero_bounty_hunter",team=2,owner=0,illusion=false,broken=false}
function hero:GetUnitName() return "npc_dota_hero_bounty_hunter" end
function hero:GetTeamNumber() return self.team end
function hero:GetPlayerOwnerID() return self.owner end
function hero:IsIllusion() return self.illusion end
function hero:PassivesDisabled() return self.broken end
function hero:FindAbilityByName() return ability end
function hero:HasModifier() return self.mod~=nil end
function hero:HasScepter() return self.scepter end
local refreshed=0
function hero:FindModifierByName() return {ForceRefresh=function()
    refreshed=refreshed+1
    assert(ability:GetSpecialValueFor("gold_steal")==0,"refresh sees zero native steal")
end} end
function hero:AddNewModifier(_,_,name)
    assert(name=="modifier_rpg_jinada_income")
    self.mod=setmetatable({GetParent=function() return self end},{__index=modifier_rpg_jinada_income})
    self.mod:OnCreated()
end
function ability:GetSpecialValueFor(key)
    local event={ability=self,ability_special_value=key}
    if hero.mod and hero.mod:GetModifierOverrideAbilitySpecial(event)==1 then
        return hero.mod:GetModifierOverrideAbilitySpecialValue(event)
    end
    if key=="gold_steal" then return ({15,22,29,36})[self.level]+self.talent end
    return 175
end
local function target(name,team)
    return {GetTeamNumber=function() return team or 3 end,GetUnitName=function() return name end}
end
-- Targets deliberately have no owner/gold APIs.
local creep=target("npc_dota_neutral_kobold")
local enemyHero=target("npc_dota_hero_axe")
Income.Attach(game,hero)
assert(hero.mod and refreshed==1,"owned hero gets one income modifier and native cache refresh")
Income.Attach(game,hero); assert(refreshed==1,"repeated preparation does not duplicate modifier")
local m=hero.mod
assert(ability:GetSpecialValueFor("gold_steal")==0,"server native payout is disabled")
assert(ability:GetSpecialValueFor("bonus_damage")==175,"native damage special is unchanged")
assert(m:Amount(ability)==36,"custom amount reads native value without recursive zero")
server=false; assert(ability:GetSpecialValueFor("gold_steal")==36,"client tooltip retains native gold amount"); server=true
local seq=0
local function attack(t,opts)
    opts=opts or {}; seq=seq+1
    local event={attacker=hero,target=t,record=seq,no_attack_cooldown=opts.extra or 0,process_procs=opts.procs}
    m:OnAttackStart(event)
    if opts.nativeConsumedEarly then ability.ready=false end
    m:OnAttackRecord(event)
    if opts.release~=false then
        m:OnAttack(event)
        -- Simulate the native ability consuming its cooldown after release.
        if m.records[seq] and ability.cooldown > 0 then ability.ready=false end
    end
    if opts.hit~=false then m:OnAttackLanded(event) end
    if opts.duplicate then m:OnAttackLanded(event) end
    m:OnAttackRecordDestroy(event)
    return event
end
attack(creep,{duplicate=true}); assert(gold==36 and writes==1,"ownerless creep pays once on actual landed attack")
attack(creep); assert(gold==36,"second attack in native interval cannot pay")
time=3; ability.ready=true; attack(enemyHero); assert(gold==72,"ownerless enemy hero pays the same amount")
time=6; ability.ready=true; attack(target("npc_dota_bounty_hunter_summon")); assert(gold==108,"summons qualify")
time=9; ability.ready=true; attack(target("npc_dota_badguys_tower")); assert(gold==144,"buildings qualify without IsHero restriction")
time=12; ability.ready=true; attack(target("ally",2)); assert(gold==144,"allies do not pay")
hero.broken=true; attack(creep); assert(gold==144,"break blocks gold"); hero.broken=false
hero.illusion=true; attack(creep); assert(gold==144,"illusion cannot produce gold"); hero.illusion=false
hero.owner=-1; attack(creep); assert(gold==144,"foreign or unbound caster cannot credit player"); hero.owner=0
ability.ready=false; attack(creep); assert(gold==144,"native cooldown blocks proc eligibility"); ability.ready=true
ability.auto=false; attack(creep); assert(gold==144,"disabled autocast does not steal on ordinary attack")
m:OnOrder({unit=hero,order_type=6,ability=ability,target=creep})
attack(creep,{nativeConsumedEarly=true}); assert(gold==180,"manual Jinada and native early cooldown retain captured windup")
ability.ready=true; ability.auto=true; time=15
attack(creep,{hit=false}); assert(gold==180,"misses cannot pay")
attack(creep); assert(gold==180,"missed release still consumes income interval")
time=18; ability.ready=true; attack(creep,{release=false}); assert(gold==180,"unreleased attack cannot pay")
attack(creep,{extra=1}); attack(creep,{procs=0}); assert(gold==180,"non-proccing extra attacks do not pay")
game.phase="setup"; attack(creep); assert(gold==180,"preparation cannot farm gold"); game.phase="fight"
ability.level=0; attack(creep); assert(gold==180,"untrained Jinada cannot steal"); ability.level=4
ability.talent=50; ability.cooldown=0; ability.ready=true
attack(creep); attack(creep); assert(gold==352,"native gold talent and no-cooldown talent apply per landed hit")
assert(next(m.records)==nil,"attack record cleanup is bounded")
ability.cooldown=3; ability.ready=true
attack(creep); assert(gold==438,"normal cooldown can be consumed again")
ability.ready=true -- Refresher: no elapsed time is required.
attack(creep); assert(gold==524,"native cooldown refresh immediately permits another income proc")
local shuriken={GetAbilityName=function() return "bounty_hunter_shuriken_toss" end}
local damage={attacker=hero,unit=creep,inflictor=shuriken,damage=100}
m:OnTakeDamage(damage); assert(gold==524,"ordinary Shuriken cannot pay")
hero.scepter=true; m:OnTakeDamage(damage); assert(gold==610,"Scepter Shuriken pays per target hit independent of attack cooldown")
damage.unit=enemyHero; m:OnTakeDamage(damage); assert(gold==696,"tracked bounce can pay another target")
damage.damage=0; m:OnTakeDamage(damage); assert(gold==696,"zero-damage notification cannot pay")
damage.damage=100; hero.broken=true; m:OnTakeDamage(damage); assert(gold==696,"break blocks Scepter income"); hero.broken=false
local nativeGetter=ability.GetSpecialValueFor
ability.GetSpecialValueFor=function() error("native getter unavailable") end
assert(m:Amount(ability)==0 and not m.readingNative,"failed native read cannot disable suppression")
ability.GetSpecialValueFor=nativeGetter
assert(m:RemoveOnDeath()==false,"same-handle reincarnation keeps income observer")
print("PASS RPG Jinada income: all enemy unit types, native-special suppression, talents, cooldown, landed records, misses, manual/autocast, break, Scepter and phase/owner guards; native APIs mocked")
