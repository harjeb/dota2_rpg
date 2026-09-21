package.path='game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;'..package.path
DOTA_TEAM_GOODGUYS=2
local Cards=require('endless.cards')
local events,listeners={},{}
PlayerResource={GetPlayer=function(_,id)return {id=id} end}
CustomGameEventManager={RegisterListener=function(_,name,fn)listeners[name]=fn end,Send_ServerToPlayer=function(_,p,name,data)events[#events+1]={name=name,data=data}end}
GameRules={GetGameTime=function()return 0 end}
EntIndexToHScript=function(source)return {GetPlayerID=function()return source==10 and 0 or 1 end}end
local function game()
 local g={endlessRunId=1,endlessWave=1,playerId=0,phase='setup',lineup={'npc_dota_hero_lina','npc_dota_hero_ursa'},ownedHeroes={'npc_dota_hero_lina','npc_dota_hero_ursa'},heroData={npc_dota_hero_lina={level=1},npc_dota_hero_ursa={level=1}},gold=500,battleManager={teamHeroes={[2]={}}}}
 function g:GetGoldBalance()return self.gold end
 function g:SpendGold(n)if self.gold<n then return false end;self.gold=self.gold-n;return true end
 function g:BroadcastShopState()end
 function g:OnStartBattle(source,payload)assert(source==10,'forward original source to guarded mode');assert(payload.PlayerID==0);self.phase='fight' end
 function g:EndBattle()self.phase='result' end
 function g:OnThink()return 0.1 end
 function g:OnShopBuy(_,p)for _,name in ipairs(self.ownedHeroes)do if name==p.hero then return end end;self.ownedHeroes[#self.ownedHeroes+1]=p.hero end
 function g:OnLineupSet(_,p)self.lineup=p.lineup end
 function g:RespawnPlayerRoster()end
 Cards.Install(g);return g
end
local function action(g,t)
 local s=Cards.Ensure(g);t.run_id=s.run_id;t.wave=s.wave;t.revision=s.revision
 return Cards.Apply(g,t,10)
end
local g=game()
assert(#Cards.Snapshot(g).cards==5 and #Cards.Snapshot(g).heroes==2)
assert(action(g,{type='equip',id='E-g8',slot='lina:general'})==nil)
assert(action(g,{type='equip',id='E-g8',slot='ursa:general'})==nil)
assert(g.endlessCards.slots['lina:general']==nil and Cards.Used(g)==1)
assert(action(g,{type='equip',id='C-g1',slot='ursa:general'})==nil)
assert(Cards.Used(g)==1)
assert(action(g,{type='equip',id='E-g8',slot='lina:hero'}))
assert(action(g,{type='equip',id='E-f3',slot='lina:general'}),'unimplemented cannot equip')
assert(action(g,{type='level',id='C-g1',level=2}),'cannot forge owned level')
assert(action(g,{type='level',id='C-g1',level=1.5}))
local s=g.endlessCards
local stale={type='buy',index=0,run_id=s.run_id,wave=s.wave,revision=s.revision}
assert(Cards.Apply(g,stale)==nil);local gold=g.gold
assert(Cards.Apply(g,stale));assert(g.gold==gold,'duplicate/stale action cannot charge twice')
g:OnShopBuy(10,{PlayerID=0,hero='npc_dota_hero_axe'})
assert(g.endlessPurchases==2)
assert(action(g,{type='buy',index=1})==nil)
assert(action(g,{type='buy',index=2}));g:OnShopBuy(10,{PlayerID=0,hero='npc_dota_hero_tiny'})
assert(#g.ownedHeroes==3 and g.endlessPurchases==3,'hero recruitment and cards share count')
-- Retry preserves quotes/count; advance regenerates once.
local offers=table.concat(s.offers,',');Cards.Ensure(g);assert(table.concat(s.offers,',')==offers)
g.endlessWave=2;Cards.Ensure(g);assert(g.endlessPurchases==0 and not next(s.bought))
-- An over-budget server loadout blocks normal HUD start too.
s.cards['C-g1'].copies=3;s.cards['C-g1'].level=3
assert(action(g,{type='level',id='C-g1',level=3})==nil)
assert(Cards.Validate(g));g:OnStartBattle(10,{PlayerID=0});assert(g.phase=='setup')
assert(action(g,{type='level',id='C-g1',level=1})==nil)
assert(action(g,{type='confirm'})==nil and g.phase=='fight')
assert(g.endlessCardCombat and #g.endlessCardCombat.cards==1)
assert(action(g,{type='unequip',id='C-g1'}),'battle locks editing')
g:EndBattle();assert(g.endlessCardCombat==nil)
-- Foreign client is rejected before evaluating any action.
g.phase='setup';local before=s.revision
Cards.Request(g,11,{PlayerID=1,type='buy',index=2});assert(s.revision==before)
Cards.Request(g,11,{PlayerID=0,type='buy',index=2});assert(s.revision==before)
Cards.Request(g,nil,{PlayerID=0,type='buy',index=2});assert(s.revision==before)
local resolve=EntIndexToHScript;EntIndexToHScript=function()return nil end
Cards.Request(g,10,{PlayerID=0,type='buy',index=2});assert(s.revision==before)
EntIndexToHScript=resolve
-- Recovery state is serializable and contains no engine handles.
Cards.Publish(g);local Json=require('lib.json');local wire=Json.decode(events[#events].data.state_json)
assert(wire.run_id=='1' and wire.gold==g.gold and #wire.supported==17)
-- New run removes old ownership, loadouts and charges.
g.endlessRunId=2;Cards.Ensure(g);assert(#Cards.Snapshot(g).cards==5 and not next(g.endlessCards.slots));assert(g.endlessPurchases==0)
print('endless-cards: authority, revisions, unique slots, shared purchases, budget, combat lifecycle and recovery passed')
