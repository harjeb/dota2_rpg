local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
local E=require("issue_fixes.eldwurms_edda")
local Sales=require("issue_fixes.item_sales")
local Policy=require("issue_fixes.hero_ability_policy")
local items={}
local function book(id)
    local i={id=id,name=E.ITEM,dead=false}
    function i:IsNull() return self.dead end
    function i:GetAbilityName() return self.name end
    function i:entindex() return self.id end
    function i:RemoveSelf() self.dead=true end
    items[id]=i
    return i
end
local upgrades={current=4,maximum=4,scaling=1}
local hero={lineupHeroName=E.HERO,inventory={},alive=true,intellect=100,modifiers={}}
function hero:IsNull() return false end
function hero:GetUnitName() return E.HERO end
function hero:GetItemInSlot(slot) return self.inventory[slot] end
function hero:TakeItem(item) for slot,v in pairs(self.inventory) do if v==item then self.inventory[slot]=nil end end end
function hero:IsAlive() return self.alive end
function hero:RespawnHero() self.alive=true;self.respawns=(self.respawns or 0)+1 end
function hero:RemoveModifierByName(name) self.modifiers[name]=nil end
function hero:SetAbsOrigin(pos) self.position=pos end
function hero:FindAllModifiers() return self.effects or {} end
function hero:ConsumeItem(item)
    self.calls=(self.calls or 0)+1
    if self.reject then return end
    self:TakeItem(item);item:RemoveSelf()
    self.intellect=self.intellect*1.25
    upgrades.current=upgrades.current+1;upgrades.maximum=upgrades.maximum+1;upgrades.scaling=1.5
end
local game={playerId=0,phase="setup",heroData={[E.HERO]={}},arena={mode="campaign"}}
function game:IsLiveItem(i) return i and not i:IsNull() end
function game:FindOwnedHeroUnit(name) return name==E.HERO and hero or nil end
function game:IsEquipmentCarrier(u) return u==hero end
function game:IsItemHeldBy(u,i,a,b) for slot=a,b do if u.inventory[slot]==i then return true end end return false end
function game:BindEquipmentCarrierToPlayer(u) return u==hero end
function game:SyncHeroInventoryFromUnit(u) self.synced=u end
function game:CaptureHeroAbilities(u) self.captured=u end
EntIndexToHScript=function(id) return items[id] end
local original=book(10);hero.inventory[16]=original
E.BeforeRestore(game,hero)
assert(not original.dead,"the first native grant survives")
game.heroData[E.HERO].inventory_entities={original}
local duplicate=book(11);hero.inventory[0]=duplicate
E.BeforeRestore(game,hero)
assert(duplicate.dead and not original.dead,"rebuild removes the extra native grant, never the saved entity")
local payload={PlayerID=0,hero=E.HERO,item=E.ITEM,item_index=10}
local bad={PlayerID=1,hero=E.HERO,item=E.ITEM,item_index=10}
assert(not Sales.Sell(game,bad) and hero.calls==nil,"wrong owner cannot consume")
game.phase="fight";assert(not Sales.Sell(game,payload));game.phase="setup"
game.arena.mode="arena"
local ok,why=Sales.Sell(game,payload)
assert(not ok and why=="edda_arena_unavailable" and not original.dead,"unsupported arena export cannot lose consumed upgrades")
game.arena.mode="campaign";hero.reject=true
assert(not Sales.Sell(game,payload) and not game.heroData[E.HERO].edda_consumed,"native rejection is not success")
hero.reject=false
ok,why=Sales.Sell(game,payload)
assert(ok and why=="consumed" and original.dead and hero.intellect==125 and upgrades.current==5)
assert(game.synced==hero and game.captured==hero)
assert(not Sales.Sell(game,payload) and hero.calls==2,"duplicate network request never consumes twice")
local durable,temporary,badEffect={},{},{}
local function modifier(row,duration,debuff)
    function row:GetDuration() return duration end
    function row:IsDebuff() return debuff end
    function row:Destroy() self.destroyed=true end
    return row
end
hero.effects={modifier(durable,-1,false),modifier(temporary,6,false),modifier(badEffect,-1,true)}
hero.alive=false;hero.modifiers.modifier_rpg_prepare_bench=true
assert(E.KeepForRespawn(game,hero))
local reused=E.TakeRetained(game,E.HERO,{x=-800,y=200})
assert(reused==hero and hero.alive and hero.respawns==1)
assert(hero.intellect==125 and upgrades.maximum==5 and upgrades.scaling==1.5,"native upgrade state is retained, not reconstructed with guessed modifiers")
assert(not durable.destroyed and temporary.destroyed and badEffect.destroyed,"new battle drops temporary effects but retains permanent native upgrades")
assert(not hero.modifiers.modifier_rpg_prepare_bench and hero.benchHeroName==nil and hero.lineupHeroName==nil)
assert(E.TakeRetained(game,E.HERO,{})==nil,"retained hero is claimed only once per rebuild")
hero.benchHeroName=E.HERO
game.heroData[E.HERO].inventory_entities={}
hero.inventory[16]=book(12)
E.BeforeRestore(game,hero)
assert(items[12].dead,"consumption followed by respawn does not award a replacement book")
assert(E.KeepForRespawn(game,hero));game.heroData={}
assert(E.TakeRetained(game,E.HERO,{})==nil,"fresh run cannot reuse old native upgrades")
-- Reapplying unchanged skill levels can invoke native upgrade hooks again.
local calls=0
local a={GetAbilityName=function()return "winter_wyvern_splinter_blast"end,GetLevel=function()return 5 end,SetLevel=function()calls=calls+1 end}
Policy.RestoreManualAbilities({GetAbilityCount=function()return 1 end,GetAbilityByIndex=function()return a end,SetAbilityPoints=function()end},
    {ability_levels={winter_wyvern_splinter_blast=5},skill_points=0},0)
assert(calls==0,"reused native abilities do not retrigger unchanged levels")
print("PASS Edda native consume, exact ownership, native rejection, duplicate grant suppression, retained upgrades, battle reset and fresh run")
