package.path='game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;'..package.path
DOTA_TEAM_GOODGUYS=2
Vector=function(x,y,z)return {x=x,y=y,z=z}end
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
assert(#Cards.Snapshot(g).cards==0 and #Cards.Snapshot(g).heroes==2,'no free cards')
assert(#g.endlessCards.offers==0,'choose the run pool before offers')
assert(action(g,{type='factions',factions={'civilization','element'}})==nil)
assert(action(g,{type='factions',factions={'wild'}}),'cannot reroll by changing faction')
for _,id in ipairs(g.endlessCards.offers) do assert(id:match('^[CE]%-')) end
-- Owned fixture cards isolate equipment/budget tests from random purchase outcomes.
local Catalog=require('endless.card_catalog')
for _,id in ipairs({'E-g8','C-g1'})do
 local card={};for k,v in pairs(Catalog[id])do card[k]=v end
 card.copies=1;card.level=1;card.load=1;g.endlessCards.cards[id]=card
end
assert(action(g,{type='equip',id='E-g8',slot='lina:general'})==nil)
assert(action(g,{type='equip',id='E-g8',slot='ursa:general'})==nil)
assert(g.endlessCards.slots['lina:general']==nil and Cards.Used(g)==1)
assert(action(g,{type='equip',id='C-g1',slot='ursa:general'})==nil)
assert(Cards.Used(g)==1)
assert(action(g,{type='equip',id='E-g8',slot='lina:hero'}))
assert(action(g,{type='equip',id='E-f3',slot='lina:general'}),'unowned card cannot equip')
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
assert(wire.run_id=='1' and wire.gold==g.gold and #wire.supported==100 and not next(wire.unsupported))
-- First-only elemental cards use an infinite internal deadline, never JSON infinity.
g.endlessCardCombat={cards={{id='E-c1',remaining=2,next_trigger=math.huge,active_until=10}}}
Cards.Publish(g);wire=Json.decode(events[#events].data.state_json)
assert(wire.combat.cards[1].next_trigger==nil and wire.combat.cards[1].remaining==2)
assert(wire.combat.cards[1].active_until==10)
g.endlessCardCombat=nil
-- New run removes old ownership, loadouts and charges.
g.endlessRunId=2;Cards.Ensure(g);assert(#Cards.Snapshot(g).cards==0 and not next(g.endlessCards.slots));assert(g.endlessPurchases==0)
-- Capacity transitions preserve all assets and never respawn on a rejected lineup.
local full=game();local fs=full.endlessCards
local names={'E-g8','C-g1'};for id in pairs(Catalog)do if id~='E-g8' and id~='C-g1' then names[#names+1]=id end end
for i=1,25 do local id=names[i];local c={};for k,v in pairs(Catalog[id])do c[k]=v end;c.copies=1;c.level=1;c.load=1;fs.cards[id]=c end
local equipped=names[1];fs.slots['lina:general']=equipped
local respawns=0;function full:RespawnPlayerRoster()respawns=respawns+1 end
full:OnLineupSet(10,{PlayerID=0,lineup={'npc_dota_hero_ursa'}})
assert(#full.lineup==2 and fs.slots['lina:general']==equipped and respawns==0,'overflow preflight prevents roster side effects')
assert(action(full,{type='unequip',id=equipped}),'cannot overflow on unequip')
local replacement=names[2]
assert(action(full,{type='equip',id=replacement,slot='lina:general'})==nil,'inventory replacement is net zero at capacity')
assert(fs.cards[equipped] and fs.slots['lina:general']==replacement)
fs.factions={abyss=true};fs.offers={replacement};fs.bought={}
assert(action(full,{type='buy',index=0})==nil,'duplicate acquisition needs no new capacity')
assert(fs.cards[replacement].level==2 and fs.cards[replacement].load==1,'duplicate preserves load level')
fs.cards[replacement].level=3;fs.cards[replacement].copies=3;fs.bought={}
local goldBefore=full.gold;local quotaBefore=full.endlessPurchases
assert(action(full,{type='buy',index=0}));assert(full.gold==goldBefore and full.endlessPurchases==quotaBefore,'saturated card never charges for unavailable bonus')
-- Preparation edits preserve intrinsic event semantics and server-owned cooldowns.
local triggers=game();local ts=triggers.endlessCards
for _,id in ipairs({'C-c1','C-c3','A-c1','E-c1'})do
 local c={};for k,v in pairs(Catalog[id])do c[k]=v end;c.copies=1;c.level=1;c.load=1;ts.cards[id]=c
end
assert(action(triggers,{type='trigger',id='C-c1',value=17})==nil)
assert(ts.cards['C-c1'].trigger.first==17 and ts.cards['C-c1'].trigger.interval==12)
assert(action(triggers,{type='trigger',id='C-c3',value=25})==nil)
assert(ts.cards['C-c3'].trigger.threshold==.25 and ts.cards['C-c3'].trigger.cooldown==12)
assert(action(triggers,{type='trigger',id='C-c3',value=9}))
assert(action(triggers,{type='trigger',id='C-c3',value=25.5}))
assert(action(triggers,{type='trigger',id='A-c1',value=20}),'intrinsic mark events cannot be rewritten')
assert(action(triggers,{type='trigger',id='E-c1',value=20}),'element repeat semantics remain fixed')
assert(action(triggers,{type='trigger',id='C-c3',value='default'})==nil and not ts.cards['C-c3'].trigger)
assert(action(triggers,{type='equip',id='C-c1',slot='lina:general'})==nil)
assert(action(triggers,{type='confirm'})==nil)
assert(triggers.endlessCardCombat.cards[1].next_trigger==17,'runtime honors configured first trigger')
assert(action(triggers,{type='trigger',id='C-c1',value=20}),'combat cannot change frozen conditions')
ts.cards['C-c1'].trigger.first=99
assert(triggers.endlessCardCombat.cards[1].trigger.first==17,'combat trigger is a frozen copy')
-- Frozen seeded pools are faction-scoped and remove saturated cards on the next wave.
local a=game();local b=game();a.endlessCards.seed=987654;b.endlessCards.seed=987654
assert(action(a,{type='factions',factions={'civilization'}})==nil)
assert(action(b,{type='factions',factions={'civilization'}})==nil)
assert(table.concat(a.endlessCards.offers,',')==table.concat(b.endlessCards.offers,','))
local oldOffers=table.concat(a.endlessCards.offers,',');Cards.Ensure(a);assert(oldOffers==table.concat(a.endlessCards.offers,','))
local maxed=a.endlessCards.offers[1];a.endlessCards.cards[maxed]={level=3,copies=3,load=1}
a.endlessWave=2;Cards.Ensure(a)
for _,id in ipairs(a.endlessCards.offers)do assert(id~=maxed and Catalog[id].faction=='civilization')end
-- Newly completed cards must be reachable through real quotes, purchases and equipment.
for _,id in ipairs({'E-g7','E-c2','E-c4','E-c7','D-f1','D-f3','W-f2','D-g3','D-g5','D-c2'}) do
 local fresh=game();local faction=Catalog[id].faction
 for other,card in pairs(Catalog) do
  if other~=id and card.faction==faction then
   local c={};for k,v in pairs(card)do c[k]=v end;c.level=3;c.copies=3;c.load=1
   fresh.endlessCards.cards[other]=c
  end
 end
 assert(action(fresh,{type='factions',factions={faction}})==nil)
 assert(#fresh.endlessCards.offers==5,'new card must remain available in its faction pool: '..id)
 for _,offer in ipairs(fresh.endlessCards.offers)do assert(offer==id,'only unsaturated card offered')end
 assert(action(fresh,{type='buy',index=0})==nil,'new card purchase: '..id)
 assert(fresh.gold==400 and fresh.endlessPurchases==1)
 assert(action(fresh,{type='equip',id=id,slot='lina:general'})==nil,'new card equip: '..id)
 assert(Cards.Validate(fresh)==nil)
end
print('endless-cards: all 100 supported, remaining 10 quote/buy/equip, authority, capacity, pools, shared purchases, budget and combat lifecycle passed')
