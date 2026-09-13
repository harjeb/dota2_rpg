local root=TEST_REPO_ROOT or '.'
local Transport=dofile(root..'/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/shop_transport.lua')
local time=0; Time=function() return time end
local player, other={},{}
PlayerResource={GetPlayer=function(_,id) return id==0 and player or other end}
local count=0
local game={playerId=0,SendStateTo=function() end}
function game:BroadcastShopState(target)
 assert(target==player,'recovery is targeted')
 count=count+1
 Transport.Send(self,target,{rule_generation=1,gold=99})
end
Transport.Send(game,nil,{rule_generation=1,gold=1})
Transport.Request(game,{PlayerID=1,rule_generation=-1,shop_revision=-1})
Transport.Request(game,{rule_generation=-1,shop_revision=-1})
assert(count==0,'missing or foreign engine identity cannot request recovery')
Transport.Request(game,{PlayerID=0,rule_generation=-1,shop_revision=-1})
assert(count==1,'lost initial publication recovered')
for i=1,100 do Transport.Request(game,{PlayerID=0,shop_revision=-1}) end
assert(count==1,'recovery requests rate limited')
time=5
Transport.Request(game,{PlayerID=0,rule_generation=1,shop_revision=2})
assert(count==1 and game.shopTransportAcknowledged==2,'matching receipt suppresses resend')
Transport.Send(game,nil,{rule_generation=1,gold=2})
time=10
Transport.Request(game,{PlayerID=0,rule_generation=1,shop_revision=2})
assert(count==2,'newer completely dropped broadcast overrides old targeted receipt')
time=15
Transport.Request(game,{PlayerID=0,rule_generation=0,shop_revision=4})
assert(count==3,'generation must match too')
print('PASS targeted shop receipt recovery, missing/foreign identity, rate limits and superseding broadcast')
