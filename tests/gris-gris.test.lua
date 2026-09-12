local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Gris = require("issue_fixes/gris_gris")
local Sales = require("issue_fixes/item_sales")
local time, lost, nextId, entities = 0, 0, 100, {}
GameRules = {GetGameTime=function() return time end}
PlayerResource = {GetGoldLostToDeath=function() return lost end}
function EntIndexToHScript(id) return entities[id] end
local function item(name)
    nextId = nextId + 1
    local value = {name=name or Gris.ITEM, id=nextId}
    function value:GetAbilityName() return self.name end
    function value:GetSpecialValueFor() return 3 end
    function value:IsSellable() return false end
    entities[value.id] = value
    return value
end
local function hero()
    local value = {slots={}, modifier={stacks=0}}
    function value:GetUnitName() return Gris.HERO end
    function value:GetItemInSlot(slot) return self.slots[slot] end
    function value:FindModifierByName() return self.modifier end
    function value.modifier:GetStackCount() return self.stacks end
    function value.modifier:SetStackCount(n) self.stacks=n end
    function value:RemoveItem(i)
        if self.onRemove then self.onRemove(i) end
        if self.fail == "error" then error("engine removal error") end
        if self.fail == "noop" then return end
        for slot, held in pairs(self.slots) do if held == i then self.slots[slot]=nil end end
        i.null=true
    end
    function value:ConsumeItem() error("never combine native and scripted bank payouts") end
    return value
end
function UTIL_Remove(i) i.null=true end
local function setup()
    time, lost = 0, 0
    local h = hero()
    local g = {playerId=0, phase="setup", balance=100, heroData={[Gris.HERO]={inventory={}}}, hero=h}
    function g:IsLiveItem(i) return i ~= nil and not i.null end
    function g:IsItemHeldBy(holder, i, first, last)
        for slot=first,last do if holder.slots[slot] == i then return true end end
        return false
    end
    function g:FindOwnedHeroUnit(name) return name == Gris.HERO and self.hero or nil end
    function g:GetStashUnit() return nil end
    function g:IsEquipmentCarrier(hh) return hh == self.hero end
    function g:BindEquipmentCarrierToPlayer() return true end
    function g:GetGoldBalance() return self.balance end
    function g:AddGold(n) self.balance=self.balance+n end
    h.slots[0]=item()
    Gris.Reconcile(g,h)
    return g,h,g.heroData[Gris.HERO].grisGris
end
local function payout(g,h,s)
    return {PlayerID=0,hero=Gris.HERO,item=Gris.ITEM,item_index=s.item.id}
end
local g,h,s=setup()
-- Fallback accrues in preparation/fight/result and game-time pause accrues zero.
for _,case in ipairs({{2.99,0,"setup"},{3,1,"setup"},{30.5,10,"fight"},{30.5,10,"result"}}) do
    time,g.phase=case[1],case[3]; Gris.OnThink(g)
    assert(s.gold==case[2] and g.balance==100,"savings accrue before redemption, without wallet income")
end
-- Native ticks are another view of the same bank, including a phase offset.
g,h,s=setup()
for _,case in ipairs({{2.9,1,1},{3.1,1,1},{5.9,2,2},{6.1,2,2},{30,10,10}}) do
    time,h.modifier.stacks=case[1],case[2]; Gris.OnThink(g)
    assert(s.gold==case[3],"native and fallback must not double count")
end
-- Actual native death losses are separate principal, even if native ticking
-- was stalled and the native counter remains below the fallback bank.
g,h,s=setup(); time=30; Gris.OnThink(g)
lost=5; h.modifier.stacks=5; Gris.OnKilled(g,h)
assert(s.gold==15,"death deposit cannot disappear behind fallback clock")
time=60; Gris.OnThink(g); assert(s.gold==25,"death deposit remains principal")
lost=9; Gris.OnKilled(g,hero()); time=63; Gris.OnThink(g)
assert(s.gold==26,"other roster hero death is not a Gris-Gris deposit")
-- Preserve canonical handle, native counter, and fractional tick through
-- repeated lineup/bench recreations; silently delete existing/late grants.
g,h,s=setup(); time=10; Gris.OnThink(g)
for round=1,5 do
    Gris.Capture(g,h)
    local canonical=s.item
    local duplicate=item()
    local data=g.heroData[Gris.HERO]
    data.inventory={Gris.ITEM,Gris.ITEM,"item_blink"}
    data.inventory_states={{name=Gris.ITEM},{name=Gris.ITEM},{name="item_blink"}}
    data.inventory_entities={canonical,duplicate,item("item_blink")}
    h.slots={}
    local new=hero(); new.slots[0]=item(); local grant=new.slots[0]
    g.hero=new; Gris.BeforeRestore(g,new)
    assert(grant.null and duplicate.null,"new and historic duplicate grants removed without redeem")
    assert(#data.inventory==2 and data.inventory_entities[1]==canonical)
    new.slots[0]=canonical
    Gris.Reconcile(g,new)
    assert(s.item==canonical and s.gold==3 and new.modifier.stacks==3)
    new.slots[1]=item(); local late=new.slots[1]
    Gris.OnThink(g); assert(late.null and s.item==canonical)
    h=new
end
time=12; Gris.OnThink(g); assert(s.gold==4,"rebuild must preserve incomplete 3-second interval")
-- Counter may appear after inventory restore.
Gris.Capture(g,h); local canonical=s.item; h.slots={}
local new=hero(); local modifier=new.modifier; new.modifier=nil; g.hero=new
Gris.BeforeRestore(g,new); new.slots[0]=canonical; Gris.Reconcile(g,new)
assert(s.pendingCounterGold==4)
new.modifier=modifier; Gris.OnThink(g); assert(modifier.stacks==4 and not s.pendingCounterGold)
h=new
-- Panel redemption honors real entity/ownership, permits native neutral slot,
-- blocks purchase interleaving, and credits a bank exactly once.
local payload=payout(g,h,s)
g.phase="fight"; assert(select(2,Sales.Sell(g,payload))=="wrong_phase"); g.phase="setup"
g.pendingNativePurchases={{}}; assert(select(2,Sales.Sell(g,payload))=="purchase_pending"); g.pendingNativePurchases={}
payload.PlayerID=1; assert(select(2,Sales.Sell(g,payload))=="not_owned"); payload.PlayerID=0
for _,failure in ipairs({"error","noop"}) do
    h.fail=failure
    assert(select(2,Sales.Sell(g,payload))=="sale_failed")
    assert(g.balance==100 and not s.consumed and not g.itemSaleInProgress)
end
h.fail=nil; h.slots[16],h.slots[0]=h.slots[0],nil
h.onRemove=function() assert(select(2,Sales.Sell(g,payload))=="purchase_pending") end
local ok,reason,refund=Sales.Sell(g,payload)
assert(ok and reason=="sold" and refund==4 and g.balance==104 and s.consumed)
h.onRemove=nil
assert(not Sales.Sell(g,payload) and g.balance==104,"stale click cannot redeem twice")
for round=1,5 do
    local rebuilt=hero(); rebuilt.slots[0]=item(); local grant=rebuilt.slots[0]
    g.hero=rebuilt; Gris.BeforeRestore(g,rebuilt); Gris.Reconcile(g,rebuilt)
    assert(grant.null and #g.heroData[Gris.HERO].inventory==1,"consumed innate is never restored")
    rebuilt.slots[0]=item(); local late=rebuilt.slots[0]; Gris.OnThink(g)
    assert(late.null and g.balance==104)
end
-- A new run's new heroData receives a fresh one-time innate.
g,h,s=setup(); assert(s.issued and not s.consumed and s.gold==0)
-- Execute the actual native order filter: both unitless native Consume and
-- native Sell must use the same bank and suppress subsequent engine execution.
local file=assert(io.open(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua","r"))
local source=file:read("*a"); file:close()
local start=assert(source:find("function CDota2RpgDemo:ValidatePrepareOrder",1,true))
local finish=assert(source:find("function CDota2RpgDemo:PromoteBenchHero",start,true))
CDota2RpgDemo={}
assert(loadstring('local CARRIER_LAST_SLOT=16; local ItemSales=require("issue_fixes/item_sales"); '
    .. 'local GrisGris=require("issue_fixes/gris_gris"); ' .. source:sub(start,finish-1)))()
DOTA_UNIT_ORDER_CONSUME_ITEM,DOTA_UNIT_ORDER_SELL_ITEM=30,31
for _,orderType in ipairs({30,31}) do
    g,h,s=setup(); time=30; Gris.OnThink(g)
    function g:IsNativeItemShopOrder() return false end
    function g:FindEquipmentItemHolder(i) return self:IsItemHeldBy(h,i,0,16) and h or nil end
    local order={issuer_player_id_const=0,order_type=orderType,entindex_ability=s.item.id,units={}}
    assert(CDota2RpgDemo.ValidatePrepareOrder(g,order)==false)
    assert(s.consumed and g.balance==110,"native context redemption shares the exact payout path")
    assert(CDota2RpgDemo.ValidatePrepareOrder(g,order)==false and g.balance==110)
end
print("gris-gris tests passed (native entity/counter mocks; no live gameplay claim)")
