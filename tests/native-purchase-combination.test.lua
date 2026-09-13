-- Reuse the existing Dota/module loader; its fixtures stay local to that suite.
dofile((TEST_REPO_ROOT or ".") .. "/tests/shop-state.test.lua")
local nextId = 90000
local function item(name)
 nextId = nextId + 1
 return { name=name, id=nextId, IsNull=function() return false end,
  GetAbilityName=function(self) return self.name end, GetEntityIndex=function(self) return self.id end }
end
local function unit(name)
 local u = { slots={}, name=name, moves=0 }
 function u:GetItemInSlot(slot) return self.slots[slot] end
 function u:GetUnitName() return self.name end
 function u:IsNull() return false end
 function u:TakeItem(it)
  self.moves=self.moves+1
  for slot, value in pairs(self.slots) do if value==it then self.slots[slot]=nil end end
 end
 return u
end
local loads = {}
function LoadKeyValues(path)
 loads[path]=(loads[path] or 0)+1
 if path=="scripts/npc/items.txt" then
  return { DOTAAbilities={
   item_recipe_black_king_bar={ ItemRecipe="1", ItemCost="1450", ItemResult="item_black_king_bar",
    ItemRequirements={ ["01"]="item_ogre_axe;item_mithril_hammer" } },
  } }
 end
 if path=="scripts/npc/npc_items_custom.txt" then return { DOTAAbilities={} } end
 error("unexpected KV " .. path)
end
local prices={ item_mithril_hammer=1600, item_ogre_axe=1000, item_recipe_black_king_bar=1450 }
local function game()
 local wisp, axe, sven=unit("wisp"),unit("axe"),unit("sven")
 local g=setmetatable({ gold=10000, playerId=0, nativePurchaseTick=1,
  battleManager={teamHeroes={[DOTA_TEAM_GOODGUYS]={axe,sven}}}, benchUnits={},
  nativePurchaseOrderContexts={}, pendingNativePurchases={}, nativePurchaseClaimedIds={},
  GetStashUnit=function() return wisp end,
  GetNativePurchaseClock=function() return 1 end,
  GetGoldBalance=function(self) return self.gold end,
  SetGoldBalance=function(self,value) self.gold=value return value end,
  ResolveNativePurchaseRecipient=function(_,key) return key=="axe" and axe or key=="sven" and sven or wisp end,
  IsEquipmentCarrier=function() return true end,
  TryAttachItem=function(_,target,it) target.slots[0]=it return true end,
  GetEquipmentHeroName=function() return nil end,
  LogNativePurchase=function() end,
 },CDota2RpgDemo)
 return g,wisp,axe,sven
end
local function order(g,name,recipient)
 return { item_name=name,item_cost=prices[name],recipient_key=recipient or "axe",issuer=0,
  before_ids=g:CollectManagedItemIds(),gold_before=g.gold,created_at=1,created_tick=1 }
end
local function fullBatch(events,nativeDebit)
 local g,wisp,axe=game()
 local orders={order(g,"item_mithril_hammer"),order(g,"item_ogre_axe"),order(g,"item_recipe_black_king_bar")}
 if events then g.pendingNativePurchases=orders else g.nativePurchaseOrderContexts=orders end
 local bkb=item("item_black_king_bar"); wisp.slots[0]=bkb
 if nativeDebit then g.gold=g.gold-4050 end
 g:ReconcileNativePurchaseOrders()
 assert(axe.slots[0]==bkb,"complete BKB batch routes result")
 assert(wisp.moves==1,"BKB transfers exactly once")
 assert(g.gold==5950,"all three component prices settle once")
 for _,purchase in ipairs(orders) do assert(purchase.gold_checked,"every component is settled") end
 g:ReconcileNativePurchaseOrders()
 assert(g.gold==5950 and wisp.moves==1,"repeat reconciliation cannot charge or move again")
 -- A delayed matching event consumes a reconciled context without a new debit.
 if not events then
  g.phase="setup"
  for _,purchase in ipairs(orders) do g:OnNativeItemPurchased({PlayerID=0,itemname=purchase.item_name}) end
  g:ReconcileNativePurchaseOrders()
  assert(g.gold==5950 and wisp.moves==1,"late native events never debit combination twice")
 end
end
for _,events in ipairs({true,false}) do for _,nativeDebit in ipairs({true,false}) do fullBatch(events,nativeDebit) end end

-- Event callbacks may remove only part of a batch from the order queue.
do
 local g,wisp,axe=game()
 local a,b,c=order(g,"item_mithril_hammer"),order(g,"item_ogre_axe"),order(g,"item_recipe_black_king_bar")
 g.pendingNativePurchases={a}; g.nativePurchaseOrderContexts={b,c}
 local bkb=item("item_black_king_bar"); wisp.slots[0]=bkb
 g:ReconcileNativePurchaseOrders()
 assert(axe.slots[0]==bkb and g.gold==5950 and wisp.moves==1,"pending and silent orders share complete proof")
end
-- Actual observed pattern: Wisp components precede an Axe-targeted recipe.
do
 local g,wisp,axe=game()
 local hammer=order(g,"item_mithril_hammer","__wisp")
 wisp.slots[0]=item("item_mithril_hammer")
 local ogre=order(g,"item_ogre_axe","__wisp")
 wisp.slots[1]=item("item_ogre_axe")
 local purchase=order(g,"item_recipe_black_king_bar")
 local bkb=item("item_black_king_bar"); wisp.slots={[0]=bkb}
 g.pendingNativePurchases={hammer,ogre,purchase}
 g:ReconcileNativePurchaseOrders()
 assert(g.gold==5950,"mixed-target observed purchase settles all component prices")
 assert(axe.slots[0]==bkb and wisp.moves==1,"consumed same-holder baseline proves recipe result")
end
for _,scenario in ipairs({"missing","different-holder","moved","existing-result","mixed-recipients","unrelated","ambiguous","live-components"}) do
 local g,wisp,axe,sven=game()
 if scenario=="different-holder" then sven.slots[0]=item("item_mithril_hammer")
 else wisp.slots[0]=item("item_mithril_hammer") end
 if scenario~="missing" then wisp.slots[1]=item("item_ogre_axe") end
 local bkb=item("item_black_king_bar")
 if scenario=="existing-result" then wisp.slots[2]=bkb end
 local purchase=order(g,"item_recipe_black_king_bar")
 if scenario=="mixed-recipients" then
  wisp.slots={}; purchase=order(g,"item_recipe_black_king_bar")
  g.nativePurchaseOrderContexts={order(g,"item_mithril_hammer","sven"),order(g,"item_ogre_axe")}
 end
 if scenario=="live-components" then
  wisp.slots={}; purchase=order(g,"item_recipe_black_king_bar")
  g.nativePurchaseOrderContexts={order(g,"item_mithril_hammer"),order(g,"item_ogre_axe")}
 end
 if scenario=="moved" then sven.slots[0]=wisp.slots[0] end
 wisp.slots={[0]=scenario=="unrelated" and item("item_blink") or bkb}
 if scenario=="different-holder" then sven.slots={} end
 if scenario=="ambiguous" then wisp.slots[1]=item("item_black_king_bar") end
 if scenario=="live-components" then wisp.slots[1]=item("item_mithril_hammer"); wisp.slots[2]=item("item_ogre_axe") end
 assert(g:FindNewPurchasedItem(purchase)==nil,"reject insufficient proof: "..scenario)
end
assert(loads["scripts/npc/items.txt"] and loads["scripts/npc/npc_items_custom.txt"],"load qualified native and custom recipe data")
print("native-purchase-combination tests passed")
