local root=arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path=root.."/?.lua;"..package.path
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3;DOTA_TEAM_NEUTRALS=4
DOTA_UNIT_ORDER_CAST_TARGET=6;UF_SUCCESS=0
local time=0
GameRules={GetGameTime=function() return time end}
local Recruit=require("battle/neutral_recruitment")
local Summons=require("battle/summon_behavior")
local nextId=100
local entities={}
local function unit(name,team)
    nextId=nextId+1
    local u={name=name,team=team,id=nextId,alive=true,abilities={},items={},range=700,acquire=true}
    entities[u.id]=u
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return {x=0,y=0,z=0} end
    function u:FindAbilityByName(name) return self.abilities[name] end
    function u:GetAbilityByIndex(index) return self.abilities[index] end
    function u:GetItemInSlot(slot) return self.items[slot] end
    function u:RemoveSelf() self.removed=true end
    function u:SetIdleAcquire(value) self.acquire=value end
    function u:IsIdleAcquire() return self.acquire end
    function u:GetAcquisitionRange() return self.range end
    function u:SetAcquisitionRange(value) self.range=value end
    function u:AddNewModifier(_,_,name) self.modifier=name end
    function u:RemoveModifierByName(name) if self.modifier==name then self.modifier=nil end end
    function u:GetOwnerEntity() return self.owner end
    function u:IsControllableByAnyPlayer() return self.owner~=nil end
    function u:GetAttackCapability() return 1 end
    function u:SetMinimumGoldBounty(v) self.minGold=v end
    function u:SetMaximumGoldBounty(v) self.maxGold=v end
    function u:SetDeathXP(v) self.xp=v end
    function u:IsStunned() return self.stunned end
    function u:IsSilenced() return self.silenced end
    function u:IsMuted() return self.muted end
    function u:IsChanneling() return self.channeling end
    function u:IsUsingAbility() return self.using end
    -- Any attempt to fabricate native recruitment fails the suite immediately.
    function u:SetTeam() error("must use native conversion") end
    function u:SetOwner() error("must use native conversion") end
    function u:SetControllableByPlayer() error("must use native conversion") end
    return u
end
local function ability(name,level,values)
    local a=unit(name,2);a.level=level;a.values=values or {};a.ready=true
    function a:GetAbilityName() return self.name end
    function a:GetLevel() return self.level end
    function a:GetSpecialValueFor(name) return self.values[name] or 0 end
    function a:IsFullyCastable() return self.ready end
    function a:GetAbilityTargetTeam() return 2 end
    function a:GetAbilityTargetType() return 2 end
    function a:GetAbilityTargetFlags() return 0 end
    function a:EndCooldown() error("no free cooldown") end
    function a:SetLevel(value) self.level=value end
    return a
end
local creates,orders,filters=0,{},0
local nativeAccept=true
CreateUnitByName=function(name,point,clear,owner,unitOwner,team)
    assert(owner==nil and unitOwner==nil and team==4,"spawn must be unowned neutral")
    creates=creates+1
    local u=unit(name,team)
    u.abilities[0]=ability("neutral_spell",0)
    return u
end
UnitFilter=function(target,team,types,flags,casterTeam)
    filters=filters+1
    assert(Recruit.IsReserved(target) and casterTeam==2 and team==2 and types==2 and flags==0)
    return nativeAccept and 0 or 1
end
local function gameWith(hero)
    return {phase="setup",battleManager={teamHeroes={[2]={hero},[3]={}}},
        tacticBridge={orderGate={Execute=function(_,order) orders[#orders+1]=order;return true end}}}
end
local enchant=unit("npc_dota_hero_enchantress",2)
local spell=ability("enchantress_enchant",1,{level_req=4,max_creeps=1})
enchant.abilities.enchantress_enchant=spell
local game=gameWith(enchant)
local small="npc_dota_neutral_kobold"
local big="npc_dota_neutral_satyr_hellcaller"
local ancient="npc_dota_neutral_black_dragon"
local function choose(source,name) return Recruit.Select(game,enchant,source,name) end
assert(#Recruit.Catalog==46)
assert(not choose("enchantress_enchant",big),"rank 1 cannot select level 6")
assert(not choose("enchantress_enchant",ancient),"Enchant never selects ancients")
assert(not choose("enchantress_enchant","npc_dota_hero_axe"),"client cannot spawn arbitrary units")
assert(not choose("made_up_source",small))
local stranger=unit("npc_dota_hero_enchantress",2);stranger.abilities=enchant.abilities
assert(not Recruit.Select(game,stranger,"enchantress_enchant",small),"unregistered entity rejected")
assert(choose("enchantress_enchant",small))
Recruit.OnThink(game);assert(creates==0,"preparation never spawns a neutral")
assert(Recruit.GetOptions(game,enchant)[1].selected_unit==small)
spell.level=0
local option=Recruit.GetOptions(game,enchant)[1]
assert(option.source_level==0 and #option.units==0 and option.status=="unlearned")
spell.level=4;spell.values.level_req=6
assert(choose("enchantress_enchant",big),"options use current live ability level/values")
spell.values.level_req=4;spell.level=1
assert(choose("enchantress_enchant",small))
-- Saved choice survives entity replacement between bench and lineup.
local replacement=unit(enchant.name,2);replacement.abilities=enchant.abilities
game.benchUnits={replacement};game.battleManager.teamHeroes[2]={}
assert(Recruit.GetOptions(game,replacement)[1].selected_unit==small)
assert(Recruit.Select(game,replacement,"enchantress_enchant",small))
game.battleManager.teamHeroes[2]={replacement};game.benchUnits={};enchant=replacement
spell.ready=false;game.phase="fight"
assert(not choose("enchantress_enchant",small),"battle selection changes are rejected")
Recruit.OnThink(game);assert(creates==0,"cooldown/mana readiness never bypassed")
spell.ready=true;enchant.silenced=true
Recruit.OnThink(game);assert(creates==0,"silence blocks ability source")
enchant.silenced=false;enchant.channeling=true
Recruit.OnThink(game);assert(creates==0,"existing channels are not interrupted")
enchant.channeling=false
Recruit.OnThink(game)
assert(creates==1 and Recruit.IsBusy(game,enchant) and enchant.acquire==false)
assert(enchant.rpgTacticsEvents and next(enchant.rpgTacticsEvents.casts)==nil,
    "native observer attaches before auxiliary cast; submitting an order does not invent execution")
local active=game.neutralRecruitActive[enchant];local target=active.unit
assert(target.team==4 and target.owner==nil and target.modifier and target.abilities[0].level==1)
assert(target.minGold==0 and target.maxGold==0 and target.xp==0,"spawn cannot grant conversion farm")
assert(not Summons.OnSpawn(game,target),"reserved target is not an owned combat summon")
assert(#Recruit.Candidates(game,enchant,"enchantress_enchant")==1)
assert(#Recruit.Candidates(game,enchant,"attack")==0 and #Recruit.Candidates(game,stranger,"enchantress_enchant")==0)
Recruit.OnThink(game)
assert(#orders==1 and filters==1 and orders[1].AbilityIndex==spell.id and orders[1].TargetIndex==target.id)
Recruit.OnThink(game);assert(#orders==1,"pending cast point is not cancelled by repeated orders")
assert(not game.managedSummons,"no allied manufacture on successful order submission")
-- Only the native cast (simulated here) changes owner/team and spends resources.
target.team=2;target.owner=enchant;spell.ready=false
assert(not Recruit.IsReserved(target),"protection ends immediately upon native conversion")
Recruit.OnThink(game)
assert(active.status=="recruited" and not target.modifier and enchant.acquire and enchant.range==700)
assert(game.managedSummons[target] and not Recruit.IsBusy(game,enchant))
spell.ready=true;Recruit.OnThink(game);assert(creates==1,"one selected recruit per source per battle, no refill manufacture")
enchant.alive=false;Recruit.OnThink(game);assert(not target.removed,"converted companion survives original recruiter death")
local thief=unit("npc_dota_hero_chen",3)
target.team=3;target.owner=thief
Recruit.OnThink(game);assert(not target.removed,"native theft survives original recruiter death")
game.phase="setup";Recruit.OnThink(game)
assert(target.removed,"battle boundary clears generated companion even after native theft")
assert(Recruit.GetOptions(game,enchant)[1].selected_unit==small,"stage cleanup preserves choice")
assert(next(game.neutralRecruitUnits)==nil)

-- Native conversion wins a same-tick recruiter death race, including a
-- different team's native theft before our pending observer has run.
enchant.alive=true;game.phase="fight"
Recruit.OnThink(game);target=game.neutralRecruitActive[enchant].unit
Recruit.OnThink(game)
target.team=2;target.owner=enchant;enchant.alive=false
Recruit.OnThink(game)
assert(not target.removed and game.neutralRecruitStates[enchant].enchantress_enchant.status=="recruited",
    "successful conversion and recruiter death in same tick preserve native companion")
Recruit.Clear(game,false);enchant.alive=true
Recruit.OnThink(game);target=game.neutralRecruitActive[enchant].unit
target.team=3;target.owner=thief;enchant.alive=false
Recruit.OnThink(game)
assert(not target.removed and not target.modifier
    and game.neutralRecruitStates[enchant].enchantress_enchant.status=="stolen",
    "enemy native conversion ends reservation even when original recruiter dies that tick")
Recruit.Clear(game,false)

-- Native rejection and cast failure cannot leak protected neutral units.
enchant.alive=true;game.phase="fight";nativeAccept=false
Recruit.OnThink(game);target=game.neutralRecruitActive[enchant].unit
Recruit.OnThink(game);assert(target.removed and game.neutralRecruitStates[enchant].enchantress_enchant.status=="native_filter_rejected")
assert(enchant.acquire and enchant.range==700)
Recruit.Clear(game,false);nativeAccept=true
Recruit.OnThink(game);target=game.neutralRecruitActive[enchant].unit
enchant.alive=false;Recruit.OnThink(game)
assert(target.removed and not Recruit.IsBusy(game,enchant),"owner death removes only pending unconverted target")
enchant.alive=true
Recruit.Clear(game,false)
Recruit.OnThink(game);target=game.neutralRecruitActive[enchant].unit
Recruit.OnThink(game);time=time+9;Recruit.OnThink(game)
assert(target.removed and game.neutralRecruitStates[enchant].enchantress_enchant.status=="cast_failed")
Recruit.Clear(game,false)
Recruit.OnThink(game);target=game.neutralRecruitActive[enchant].unit
enchant.abilities.enchantress_enchant=nil;Recruit.OnThink(game)
assert(target.removed and not Recruit.IsBusy(game,enchant),"lost/stolen source removes pending target")
enchant.abilities.enchantress_enchant=spell
Recruit.Clear(game,true)
assert(Recruit.GetOptions(game,enchant)[1].selected_unit=="","run reset clears saved choices")

-- Items are restricted to active slots; live item ability values distinguish
-- Dominator/Overlord. Muting and silencing have their native distinct meanings.
local dom=ability("item_helm_of_the_dominator",1,{count_limit=1})
local over=ability("item_helm_of_the_overlord",1,{count_limit=1,is_overlord=1})
enchant.items[6]=over;game.phase="setup"
assert(#Recruit.GetOptions(game,enchant)==1,"backpack items are unavailable")
enchant.items[0]=dom;enchant.items[1]=over
assert(not choose(dom.name,ancient) and choose(dom.name,big))
assert(choose(over.name,ancient))
local opts=Recruit.GetOptions(game,enchant)
assert(opts[2].max_level==0 and opts[2].max_count==1 and not opts[2].allow_ancient)
assert(opts[3].allow_ancient and opts[3].item_slot==1)
assert(choose("enchantress_enchant",""))
enchant.silenced=true;enchant.muted=true;game.phase="fight"
local before=creates;Recruit.OnThink(game);assert(creates==before)
enchant.muted=false;Recruit.OnThink(game);assert(creates==before+1,"silence does not prevent item use")
target=game.neutralRecruitActive[enchant].unit
enchant.items[0]=nil;Recruit.OnThink(game);assert(target.removed,"moving item out of active inventory cancels pending recruitment")
Recruit.Clear(game,true)

-- Chen's ancient allowance comes from the live Hand of God shard special,
-- not a guessed Scepter flag. Count/level options track the native values.
local chen=unit("npc_dota_hero_chen",2)
chen.abilities.chen_holy_persuasion=ability("chen_holy_persuasion",1,{level_req=3,max_units=1})
chen.abilities.chen_hand_of_god=ability("chen_hand_of_god",0,{ancient_creeps_scepter=0})
local cg=gameWith(chen)
assert(not Recruit.Select(cg,chen,"chen_holy_persuasion",ancient))
chen.abilities.chen_holy_persuasion.level=4
chen.abilities.chen_holy_persuasion.values={level_req=6,max_units=4}
assert(Recruit.GetOptions(cg,chen)[1].max_count==4)
assert(not Recruit.Select(cg,chen,"chen_holy_persuasion",ancient))
chen.abilities.chen_hand_of_god.level=3
chen.abilities.chen_hand_of_god.values.ancient_creeps_scepter=3
assert(Recruit.Select(cg,chen,"chen_holy_persuasion",ancient))
chen.abilities.chen_holy_persuasion.values.max_units=0
assert(#Recruit.GetOptions(cg,chen)[1].units==0,"zero live control cap cannot recruit")
-- Native acquire getter variants must preserve an initially disabled value.
local quiet=unit("npc_dota_hero_enchantress",2)
quiet.acquire=false;quiet.IsIdleAcquire=nil
function quiet:GetIdleAcquire() return self.acquire end
quiet.abilities.enchantress_enchant=ability("enchantress_enchant",4,{level_req=6,max_creeps=1})
local qg=gameWith(quiet)
assert(Recruit.Select(qg,quiet,"enchantress_enchant",big))
qg.phase="fight";Recruit.OnThink(qg);assert(Recruit.IsBusy(qg,quiet))
Recruit.Clear(qg,true);assert(quiet.acquire==false,"restore actual GetIdleAcquire=false")

-- External orders pause action evaluation without losing native observation.
local Engine=require("tactics/tactic_engine")
local observed,paused,contexts=0,true,0
local threats=require("tactics/aoe_threats")
local previousObserve=threats.Observe
threats.Observe=function(units) assert(units[1]==quiet);observed=observed+1 end
local engine=Engine.new({order_gate=qg.tacticBridge.orderGate,get_phase=function() return "FIGHT" end,get_battle_units=function() return {quiet} end,
    should_pause_unit=function(u) assert(u==quiet);return paused end,get_rules=function() return {} end,
    build_context=function() contexts=contexts+1;return {} end})
engine:Start({SetContextThink=function() end})
engine:GetState(quiet).next_eval=0
engine:Think()
assert(observed==1 and contexts==0 and engine:HasActiveOrder(quiet),"paused hero remains observed but receives no ordinary order")
paused=false
assert(not engine:HasActiveOrder(quiet),"external order ownership ends immediately")
threats.Observe=previousObserve
engine:Reset()

-- Execute the actual protection modifier with engine constants. It must not
-- use invulnerability/out-of-game (which would block native conversion), and
-- its protections end synchronously when the native spell changes team.
class=function(base) return base end
MODIFIER_STATE_ROOTED=1;MODIFIER_STATE_DISARMED=2;MODIFIER_STATE_ATTACK_IMMUNE=3
MODIFIER_STATE_SILENCED=4;MODIFIER_STATE_NO_UNIT_COLLISION=5
MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_PHYSICAL=11;MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_MAGICAL=12
MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_PURE=13
assert(loadfile(root.."/battle/neutral_recruitment.lua"))()
local protected=unit("npc_rpg_recruit_kobold",4);protected.rpg_recruit_pending=true
local mod=setmetatable({GetParent=function() return protected end},{__index=modifier_rpg_neutral_recruit_pending})
assert(mod:CheckState()[MODIFIER_STATE_ATTACK_IMMUNE] and mod:GetAbsoluteNoDamagePhysical()==1
    and mod:GetAbsoluteNoDamageMagical()==1 and mod:GetAbsoluteNoDamagePure()==1)
protected.team=2
assert(next(mod:CheckState())==nil and mod:GetAbsoluteNoDamagePhysical()==0
    and mod:GetAbsoluteNoDamageMagical()==0 and mod:GetAbsoluteNoDamagePure()==0)
print("neutral recruitment: native level/ancient limits, stage/bench persistence, cast resources/control, isolation and cleanup passed")
