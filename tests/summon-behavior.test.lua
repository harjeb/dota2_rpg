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

-- 敌方召唤物（蛇棒、地狱火等）不进指令托管，但必须被清掉：它们曾经活到下一关，
-- 还在准备阶段把指挥官小精灵打死。
local enemyWard=unit(20,"npc_dota_shadow_shaman_ward",3,0,other,1)
local enemyInfernal=unit(21,"npc_dota_warlock_golem",3,0,other,1)
local registeredEnemy=unit(22,"npc_dota_neutral_centaur_khan",3,0,nil,1)
table.insert(game.battleManager.teamHeroes[3],registeredEnemy) -- 本关登记过的敌人
assert(Summons.TrackEnemySummon(game,enemyWard) and Summons.TrackEnemySummon(game,enemyInfernal),
    "enemy summons enter the cleanup list")
assert(not Summons.TrackEnemySummon(game,registeredEnemy),"a registered stage enemy is never tracked")
-- 生成顺序回归：npc_spawned 在 CreateUnitByName 期间同步触发，早于 RegisterHero。
-- 项目自己的敌方标记是"这不是召唤物"的持久依据，登记与否都要挡住；
-- 而生成瞬间标记尚未写入的那一窗，由 OnNpcSpawned 的 stageLoading 闸门负责（见 addon_game_mode）。
local stageEnemy=unit(23,"npc_dota_neutral_ogre_mauler",3,0,nil,1)
stageEnemy.enemyRuleIndex=1
assert(not Summons.TrackEnemySummon(game,stageEnemy),
    "the project enemy marker keeps a stage enemy out of the cleanup list")
assert(not Summons.TrackEnemySummon(game,wolf),"player summons keep the order-driven path instead")
assert(not Summons.TrackEnemySummon(game,other),"enemy heroes are never tracked")
Summons.Clear(game)
assert(enemyWard.removed and enemyInfernal.removed,"enemy summons are removed at battle end")
assert(not registeredEnemy.removed,"the registered enemy survives cleanup")
assert(not stageEnemy.removed,"a marked stage enemy survives cleanup")
assert(next(game.enemySummons)==nil,"the enemy cleanup list is drained")
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
-- Enemy Raise Dead uses a registered neutral owner, not player controllability.
local troll=unit(200,"npc_dota_neutral_dark_troll_warlord",3,700,nil,1)
local skeleton=unit(201,"npc_dota_dark_troll_warlord_skeleton_warrior",3,650,nil,1)
skeleton.IsControllableByAnyPlayer=function() return false end
local summonOrders,prepared={},0
local trollBattle={phase="fight",battleManager={teamHeroes={[2]={hero},[3]={troll}}},
    PrepareEnemyCreep=function(_,u,level)
        assert(u==skeleton and level==1); prepared=prepared+1
    end,
    tacticBridge={orderGate={Execute=function(_,o) summonOrders[#summonOrders+1]=o;return true end}}}
assert(not Summons.OnSpawn(trollBattle,skeleton),"a skeleton name alone cannot fabricate its owner")
assert(Summons.TrackEnemySummon(trollBattle,skeleton),"unowned skeleton is still covered by cleanup")
skeleton.owner=troll
FindUnitsInRadius=function() return {skeleton,hero,troll} end
Summons.OnThink(trollBattle)
assert(trollBattle.managedSummons[skeleton] and prepared==1,"late native ownership admits and initializes the campaign skeleton")
assert(#summonOrders==1 and summonOrders[1].TargetIndex==hero.id,"enemy skeleton receives an attack against the opposing team")
Summons.OnSpawn(trollBattle,skeleton)
assert(prepared==1,"repeat spawn registration does not reinitialize native skills")
local impostor=unit(202,skeleton.name,3,650,other,1)
impostor.IsControllableByAnyPlayer=skeleton.IsControllableByAnyPlayer
assert(not Summons.OnSpawn(trollBattle,impostor),"other uncontrollable summons keep native behavior")
Summons.Clear(trollBattle)
assert(skeleton.removed and not troll.removed and not hero.removed,"battle end removes the skeleton and preserves the roster")
print("summon-behavior tests passed: illusion ownership, campaign Troll skeletons, nearest attacks and cleanup")
