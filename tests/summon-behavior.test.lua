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
    tacticBridge={orderGate={Execute=function(_,o) orders[#orders+1]=o end}}}
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
print("summon-behavior tests passed")
