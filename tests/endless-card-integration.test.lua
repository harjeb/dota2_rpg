package.path = 'game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;' .. package.path
local I = require('endless.card_integration')
local function unit(team, hero)
    return {IsNull=function() return false end,IsAlive=function(self) return not self.dead end,
        GetTeamNumber=function() return team end,IsRealHero=function() return hero end}
end
local source = unit(2,true)
local form, animal, dead = unit(2,true),unit(2,false),unit(2,true)
for _,u in ipairs({form,animal,dead}) do u.endlessRebirthForm=true end
form.endlessRebirthSource=source
animal.endlessRebirthSource=unit(2,false)
dead.endlessRebirthSource=source;dead.dead=true
local game={phase='fight',endlessCardCombat={forms={[form]={},[animal]={},[dead]={}}}}
assert(#I.Forms(game,2)==2)
assert(#I.Forms(game,3)==0)
assert(I.HeroFormCount(game,2)==1,'beast souls must not prevent hero wipe')
assert(I.IsForm(game,form) and not I.IsForm(game,dead))
local calls, installs=0,0
local entity={SetDamageFilter=function(_,callback,context) installs=installs+1;game.filter=function(e)return callback(context,e)end end}
GameRules={GetGameModeEntity=function()return entity end}
package.loaded['endless.card_effects']={DamageFilter=function(g,e)assert(g==game);calls=calls+1;e.damage=e.damage*2;return e.damage>0 end}
I.Install(game);I.Install(game)
assert(installs==1)
local e={damage=3};assert(game.filter(e) and e.damage==6 and calls==1)
assert(not game.filter({damage=0}))
game.phase='setup';e={damage=3};assert(game.filter(e) and e.damage==3 and calls==2)
game.endlessCardCombat=nil;assert(#I.Forms(game)==0 and not I.IsForm(game,form))
-- Exercise the real battle manager: the last hero's soul can finish the fight,
-- but ordinary beast souls cannot hold the battle open after it expires.
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3
function class() local c={};c.__index=c;return c end
package.loaded['battle.unit_helpers']={IsValidUnit=function(u)return u and not u:IsNull()end}
package.loaded['tactics/ability_behavior']={}
package.loaded['battle.respawn_policy']={IsReturning=function()return false end}
package.loaded['battle.buyback']={Process=function()end}
require('battle.battle_manager')
source.dead=true;form.dead=false
local enemy=unit(3,true)
game.endlessCardCombat={forms={[form]={},[animal]={}}};game.phase='fight'
function game:EndBattle(winner)self.winner=winner end
local manager=setmetatable({gameMode=game,phase='fight',teamHeroes={[2]={source},[3]={enemy}}},BattleManager)
function manager:GetTimeLeft()return 30 end
assert(manager:GetAliveCount(2,true)==1)
assert(not manager:CheckBattleEnd() and not game.winner)
form.dead=true
assert(manager:CheckBattleEnd() and game.winner=='dire')
print('endless-card-integration: damage boundary and last-hero soul survival PASS')
