local root=arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path=root.."/?.lua;"..package.path
local Summons=require("battle/summon_behavior")
DOTA_UNIT_ORDER_MOVE_TO_TARGET=1;DOTA_UNIT_ORDER_ATTACK_TARGET=4;DOTA_UNIT_ORDER_STOP=21
local time=0
GameRules={GetGameTime=function() return time end}
local function unit(id,name,team,x,owner,attack,real)
    local u={id=id,name=name,team=team,x=x,owner=owner,attack=attack,real=real,alive=true}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:IsRealHero() return self.real==true end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:GetOwnerEntity() return self.owner end
    function u:GetAttackCapability() return self.attack end
    function u:GetAbsOrigin() return {x=self.x,y=0,z=0} end
    function u:entindex() return self.id end
    function u:RemoveSelf() self.removed=true end
    function u:SetIdleAcquire(value) self.acquire=value end
    return u
end
local hero=unit(1,"hero",2,500,nil,1,true)
local other=unit(2,"hero",3,900,nil,1,true)
local nearer=unit(3,"hero",3,200,nil,1,true)
local ward=unit(4,"npc_dota_juggernaut_healing_ward",2,0,hero,0)
local wolf=unit(5,"wolf",2,0,hero,1)
local trap=unit(6,"trap",2,0,hero,0)
local spirit=unit(7,"npc_dota_elder_titan_ancestral_spirit",2,0,hero,1)
local bench=unit(8,"hero",2,0,nil,1,true)
local benchPet=unit(9,"wolf",2,0,bench,1)
local orders={}
local game={phase="fight",battleManager={teamHeroes={[2]={hero},[3]={other,nearer}}},
    tacticBridge={orderGate={Execute=function(_,o) orders[#orders+1]=o;return true end}}}
assert(Summons.OnSpawn(game,ward) and Summons.OnSpawn(game,wolf))
assert(not Summons.OnSpawn(game,hero) and not Summons.OnSpawn(game,other))
assert(not Summons.OnSpawn(game,trap) and not Summons.OnSpawn(game,spirit) and not Summons.OnSpawn(game,benchPet))
local soldier=unit(12,"native_soldier",2,0,hero,1)
soldier.IsControllableByAnyPlayer=function() return false end
assert(not Summons.OnSpawn(game,soldier) and soldier.acquire==nil,"uncontrollable native soldiers retain their original behavior")
FindUnitsInRadius=function() return {other,nearer,hero} end
Summons.OnThink(game)
local seen={};for _,o in ipairs(orders) do seen[o.UnitIndex]=o end
assert(seen[4].OrderType==1 and seen[4].TargetIndex==1,"healing summon follows living allied hero")
assert(seen[5].OrderType==4 and seen[5].TargetIndex==3,"attack summon chooses nearest enemy rather than discovery order")
local count=#orders;time=.1;Summons.OnThink(game);assert(#orders==count,"orders are throttled")
local late=unit(10,"wolf",2,0,nil,1)
assert(not Summons.OnSpawn(game,late))
late.owner=hero;time=.6;FindUnitsInRadius=function() return {late,other} end;Summons.OnThink(game)
assert(game.managedSummons[late],"ownership assigned after spawn is discovered")
local clone=unit(11,"hero_clone",2,0,hero,1,true)
clone.IsClone=function() return true end
assert(Summons.OnSpawn(game,clone))
Summons.Clear(game)
assert(ward.removed and wolf.removed and late.removed and not hero.removed and not other.removed)
assert(not clone.removed and clone.acquire==false,"real hero clones are stopped; native owner lifecycle removes them")
assert(next(game.managedSummons)==nil)
-- Native Conjure Image observed in the shared-commander game: Wisp owner,
-- player ID -1, controllable, no clone source and no direct roster ownership.
local player=unit(100,"player",2,0,nil,0)
local commander=unit(101,"npc_dota_hero_wisp",2,0,player,2,true)
local tb=unit(102,"npc_dota_hero_terrorblade",2,300,commander,2,true)
local image=unit(103,"npc_dota_hero_terrorblade",2,0,commander,2)
image.IsIllusion=function() return true end
image.IsControllableByAnyPlayer=function() return true end
image.GetPlayerOwnerID=function() return -1 end
image.GetAttackTarget=function(self) return self.target end
image.IsIdle=function(self) return self.idle end
local imageOrders={}
local accept=true
local battle={phase="fight",battleManager={teamHeroes={[2]={tb},[3]={other,nearer}}},
    tacticBridge={orderGate={Execute=function(_,o)
        imageOrders[#imageOrders+1]=o
        if accept then image.idle=false end
        return accept
    end}}}
assert(Summons.ResolveOwner(battle,image)==tb,"shared commander resolves a unique fielded illusion source even with player ID -1")
assert(Summons.OnSpawn(battle,image) and battle.managedSummons[image].owner==tb)
local shadow=unit(104,"npc_dota_hero_terrorblade",2,0,commander,2)
shadow.IsIllusion=function() return true end
shadow.IsControllableByAnyPlayer=function() return false end
assert(not Summons.OnSpawn(battle,shadow),"uncontrollable native images retain their own behavior")
local stranger=unit(105,"npc_dota_hero_terrorblade",2,0,unit(106,"other_player",2,0,nil,0),2)
stranger.IsIllusion=image.IsIllusion
assert(Summons.ResolveOwner(battle,stranger)==nil,"matching name/team alone cannot claim another player's illusion")
local benchImage=unit(107,"npc_dota_hero_phantom_assassin",2,0,commander,2)
benchImage.IsIllusion=image.IsIllusion
assert(Summons.ResolveOwner(battle,benchImage)==nil,"a bench-only hero name is not a fielded source")
local duplicate=unit(108,tb.name,2,0,commander,2,true)
battle.battleManager.teamHeroes[2]={tb,duplicate}
assert(Summons.ResolveOwner(battle,image)==nil,"ambiguous same-name sources are not guessed")
battle.battleManager.teamHeroes[2]={tb}
image.team=3;assert(Summons.ResolveOwner(battle,image)==nil,"shared owner cannot bind across teams");image.team=2
local alias=unit(109,"wolf",2,0,commander,1)
alias.GetOwner=function() return tb end
assert(Summons.ResolveOwner(battle,alias)==tb,"all native owner accessors are checked")
commander.owner=commander
assert(Summons.ResolveOwner(battle,image)==tb,"owner cycles are bounded without losing a shared commander")
commander.owner=player

FindUnitsInRadius=function() return {other,nearer,image} end
time=2;Summons.OnThink(battle)
assert(#imageOrders==1 and imageOrders[1].TargetIndex==nearer.id,"registered illusion attacks the nearest enemy")
for i=1,6 do time=2+i*.5;Summons.OnThink(battle) end
assert(#imageOrders==1,"nil GetAttackTarget during non-idle approach does not restart the attack every half second")
image.idle=true;time=5.5;Summons.OnThink(battle)
assert(#imageOrders==2,"an interrupted idle illusion recovers its attack")
nearer.alive=false;time=6;Summons.OnThink(battle)
assert(#imageOrders==3 and imageOrders[3].TargetIndex==other.id,"a dead target is replaced")
image.stunned=true;image.IsStunned=function(self) return self.stunned end
image.idle=true;time=6.5;Summons.OnThink(battle);assert(#imageOrders==3,"stun is respected")
image.stunned=false;accept=false;time=7;Summons.OnThink(battle)
accept=true;time=7.5;Summons.OnThink(battle)
assert(#imageOrders==5,"a rejected attack order can retry")
Summons.Clear(battle)
assert(image.removed and not tb.removed and not commander.removed,"stage cleanup removes managed illusions and retains real heroes")
print("summon-behavior tests passed: native shared-commander illusion ownership, nearest attacks and uninterrupted pursuit")
