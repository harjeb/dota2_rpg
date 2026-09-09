local root=arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path=root.."/?.lua;"..package.path
local Tiny=require("issue_fixes/tiny_tree")
local time=0
GameRules={GetGameTime=function() return time end}
Vector=function(x,y,z) return {x=x,y=y,z=z} end
DOTA_UNIT_ORDER_CAST_TARGET_TREE=7
GetTreeIdForEntityIndex=function(index) assert(index==90); return 901 end
local orders,created={},0
local spell={IsNull=function() return false end,GetLevel=function() return 1 end,
    IsCooldownReady=function() return true end,IsFullyCastable=function() return true end,
    entindex=function() return 2 end}
local hero={held=false,stunned=false,GetUnitName=function() return "npc_dota_hero_tiny" end,
    IsNull=function() return false end,IsAlive=function() return true end,entindex=function() return 1 end,
    FindAbilityByName=function() return spell end,GetAbsOrigin=function() return Vector(0,0,0) end,
    HasModifier=function(self) return self.held end,IsStunned=function(self) return self.stunned end}
CreateTempTree=function(position,duration)
    created=created+1;assert(position.x==48 and duration==2)
    local tree={dead=false,entindex=function() return 90 end,IsNull=function(self) return self.dead end}
    function tree:CutDown() self.dead=true end
    return tree
end
local game={phase="setup",battleManager={teamHeroes={[2]={hero}}},tacticBridge={orderGate={Execute=function(_,order) orders[#orders+1]=order; return true end}}}
Tiny.OnThink(game);assert(created==0)
game.phase="fight";hero.stunned=true;Tiny.OnThink(game);assert(created==0)
hero.stunned=false;hero.rpgTacticsEvents={exclusive_movement=true};Tiny.OnThink(game)
assert(created==0 and #orders==0,"exclusive movement prevents automatic native tree cast and tree creation")
hero.rpgTacticsEvents.exclusive_movement=nil;Tiny.OnThink(game)
assert(created==1 and #orders==1 and orders[1].OrderType==7 and orders[1].TargetIndex==901 and orders[1].AbilityIndex==2)
assert(game.treeGrabBusy[hero],"native cast gets priority over the ordinary tactic tick")
time=.1;Tiny.OnThink(game);assert(created==1 and #orders==1,"pending tree cast is not duplicated")
hero.held=true;time=.5;Tiny.OnThink(game)
assert(not game.treeGrabBusy[hero] and #orders==1,"held native tree stops automatic attempts")
hero.held=false;time=2;spell.IsCooldownReady=function() return false end;Tiny.OnThink(game)
assert(created==1,"native cooldown is respected")
spell.IsCooldownReady=function() return true end;Tiny.OnThink(game)
assert(created==2 and #orders==2,"next ready cycle supplies another native tree")
local previous=game.tacticBridge.orderGate.Execute
hero.held=true;time=3;Tiny.OnThink(game);hero.held=false;time=4
local recorded=0
game.tacticBridge.RecordAuxiliaryAction=function() recorded=recorded+1 end
game.tacticBridge.orderGate.Execute=function() return false end
Tiny.OnThink(game)
assert(not game.treeGrabBusy[hero] and recorded==0,"gate failure cannot block tactics or record a successful order")
game.tacticBridge.orderGate.Execute=previous
hero.rpgTacticsEvents.exclusive_movement=true;time=6;Tiny.OnThink(game)
assert(#orders==2 and not game.treeGrabBusy[hero],"exclusive movement also guards an existing temporary tree")
hero.rpgTacticsEvents.exclusive_movement=nil;Tiny.OnThink(game)
assert(#orders==3 and recorded==1,"automatic cast resumes after session release")
local tree=game.tinyTrees[hero].tree
Tiny.Clear(game);assert(tree.dead and next(game.tinyTrees)==nil and next(game.treeGrabBusy)==nil)
print("tiny-tree tests passed")
