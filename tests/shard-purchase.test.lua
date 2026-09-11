local root = TEST_REPO_ROOT or "."
local Shards = dofile(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/shard_purchase.lua")
DOTA_TEAM_GOODGUYS = 2
local price, now, writes = 1400, 0, 0
function GetItemCost(name) assert(name == "item_aghanims_shard"); return price end
local function unit(name, team, owner)
    local hero = {name=name, team=team or 2, owner=owner or 0}
    function hero:IsNull() return self.null end
    function hero:GetTeamNumber() return self.team end
    function hero:HasModifier(name) assert(name == "modifier_item_aghanims_shard"); return self.shard == true end
    function hero:HasShard() return self.fail ~= "flag" and (self.shard == true or self.nativeShard == true) end
    function hero:RemoveModifierByName(name) assert(name == "modifier_item_aghanims_shard"); self.shard = nil end
    function hero:AddNewModifier(caster, ability, name)
        assert(caster == self and ability == nil and name == "modifier_item_aghanims_shard")
        if self.callback then self.callback() end
        if self.fail == "throw" then error("engine failure") end
        if self.fail == "noop" then return end
        self.shard = true
        if self.fail == "after" then error("post-grant engine failure") end
    end
    return hero
end
local active, bench, enemy, wisp = unit("active"), unit("bench"), unit("enemy",3), unit("wisp")
local game = {phase="setup", playerId=0, gold=10000, heroData={active={},bench={},enemy={}}}
function game:GetStashUnit() return wisp end
function game:FindOwnedHeroUnit(name) return ({active=active,bench=bench,enemy=enemy})[name] end
function game:IsLineupUnit(hero) return hero==active end
function game:IsBenchUnit(hero) return hero==bench end
function game:GetCarrierPlayerOwnerId(hero) return hero.owner end
function game:GetNativePurchaseClock() return now end
function game:GetGoldBalance() return self.gold end
function game:SetGoldBalance(value) writes=writes+1; self.gold=value end
local function reject(issuer, key)
    local before, priorWrites = game.gold, writes
    local ok, reason = Shards.Purchase(game,issuer,key)
    assert(not ok and type(reason)=="string" and #reason>0)
    assert(game.gold==before and writes==priorWrites,"rejection must not charge")
end
reject(0,nil); reject(0,"__wisp"); reject(0,"unknown"); reject(0,"enemy"); reject(1,"active")
for _,phase in ipairs({"fight","countdown","settle"}) do game.phase=phase; reject(0,"active") end
game.phase="setup"
active.owner=1; reject(0,"active"); active.owner=0
active.team=3; reject(0,"active"); active.team=2
active.null=true; reject(0,"active"); active.null=nil
active.nativeShard=true; reject(0,"active"); active.nativeShard=nil
active.shard=true; reject(0,"active"); active.shard=nil
price=1; reject(0,"active"); price=1400
game.gold=1399; reject(0,"active"); game.gold=10000
for _,key in ipairs({"nativePurchaseOrderContexts","pendingNativePurchases"}) do
    game[key]={{gold_before=10000}}; reject(0,"active"); game[key]={}
end
for _,mode in ipairs({"throw","noop","flag"}) do active.fail=mode; reject(0,"active"); assert(not active.shard and not game.shardRestockAt) end
active.fail=nil
active.callback=function() reject(0,"bench") end
assert(Shards.Purchase(game,0,"active")); active.callback=nil
assert(game.gold==8600 and writes==1 and active.shard and not wisp.shard)
reject(0,"active"); reject(0,"bench") -- one native-equivalent stock, 1s restock
now=1
bench.fail="after" -- observed grant wins even if native call errors afterwards
assert(Shards.Purchase(game,0,"bench"))
assert(game.gold==7200 and writes==2 and bench.shard and game.heroData.bench.purchased_shard)
now=2; reject(0,"bench"); reject(0,"active")
local replacement=unit("active")
Shards.Restore(game,"active",replacement)
assert(replacement.shard and writes==2,"roster replacement retains paid upgrade without a second debit")
active=replacement; reject(0,"active")
assert(not wisp.shard and not enemy.shard)
-- Source contract: exception must run before ordinary debit contexts; never
-- accept native order (which would auto-consume on assigned Wisp).
local f=assert(io.open(root.."/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua","r"))
local source=f:read("*a"); f:close()
local branch=assert(source:match('if itemName == "item_aghanims_shard" then(.-)local affordable'))
assert(branch:find("ShardPurchase.Purchase",1,true) and branch:find("return false",1,true))
assert(not branch:find("table.insert",1,true))
-- Execute the actual addon order filter against a commander-origin order.
local filterSource=assert(source:match('(function CDota2RpgDemo:ValidatePrepareOrder%b().-)\nfunction CDota2RpgDemo:'))
local env=setmetatable({CDota2RpgDemo={},ShardPurchase=Shards},{__index=_G})
local chunk=assert(loadstring(filterSource)); setfenv(chunk,env); chunk()
DOTA_UNIT_ORDER_PURCHASE_ITEM=16
function EntIndexToHScript(id) return id==1 and wisp or nil end
function game:IsNativeItemShopOrder() return true end
function game:TraceNativeShopOrder() end
function game:IsEquipmentCarrier(hero) return hero==wisp or hero==active or hero==bench end
function game:BindEquipmentCarrierToPlayer() return true end
function game:GetNativePurchaseRecipientKey(hero) return hero==wisp and "__wisp" or hero.name end
function game:PruneNativePurchaseOrderContexts() end
function game:GetNativePurchaseItemName() return "item_aghanims_shard" end
function game:SyncLiveEquipmentState() self.synced=true end
Shards.Notify=function() end
active.shard=nil; game.heroData.active.purchased_shard=nil
now=3; game.nativePurchaseSelectionHero="active"
local before=game.gold
local accepted=env.CDota2RpgDemo.ValidatePrepareOrder(game,{issuer_player_id_const=0,order_type=16,units={["0"]=1}})
assert(accepted==false and active.shard and not wisp.shard and game.gold==before-1400 and game.synced)
assert(#game.nativePurchaseOrderContexts==0 and #game.pendingNativePurchases==0,"no later event may double debit")
assert(not env.CDota2RpgDemo.ValidatePrepareOrder(game,{issuer_player_id_const=0,order_type=16,units={}}))
assert(game.gold==before-1400,"unitless repeated order cannot charge again")
print("shard purchase tests passed: roster authorization, native grant, exact debit, failures, stock, duplicates, reentry, persistence and actual order-filter routing")
