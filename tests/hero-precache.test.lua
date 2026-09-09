local root=arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path=root.."/?.lua;"..package.path
local Recruitment=require("patches/recruitment_patch")
local Class={}
Recruitment.Install(Class)
local callbacks,count={},0
PrecacheUnitByNameAsync=function(name,ready) count=count+1; callbacks[name]=ready end
local function game()
    local g=setmetatable({phase="setup",ownedHeroes={},shopCosts={lineup_max=5},benchSlots=0,
        freeRecruitChoices=0,gold=500,offers={a={price=100,level=1},b={price=100,level=1}},data={},spawns=0},{__index=Class})
    function g:FindOffer(name) return self.offers[name] end
    function g:SpendGold(amount) if self.gold<amount then return false end; self.gold=self.gold-amount; return true end
    function g:GetHeroData(name) self.data[name]=self.data[name] or {}; return self.data[name] end
    function g:RespawnPlayerRoster() self.spawns=self.spawns+1 end
    function g:BroadcastShopState() end
    return g
end
local g=game()
g:OnShopBuy(nil,{hero="a"});g:OnShopBuy(nil,{hero="a"})
assert(count==1 and g.gold==500 and #g.ownedHeroes==0,"pending load is deduplicated and cannot charge early")
callbacks.a()
assert(g.gold==400 and #g.ownedHeroes==1 and g.spawns==1,"ready callback revalidates then purchases exactly once")
callbacks.a()
assert(g.gold==400 and g.spawns==1,"duplicate native callback cannot duplicate recruitment")
local stale=game()
stale:OnShopBuy(nil,{hero="b"});stale.offers.b={price=300,level=9};callbacks.b()
assert(stale.gold==500 and #stale.ownedHeroes==0,"new offer is never substituted for the clicked one")
local refreshed=game()
refreshed:OnShopBuy(nil,{hero="a"});local beforeCount=count
refreshed.offers.a={price=200,level=2};refreshed:OnShopBuy(nil,{hero="a"});callbacks.a()
assert(count==beforeCount and refreshed.gold==300 and #refreshed.ownedHeroes==1,
    "a second click on a refreshed offer replaces the stale pending intent without duplicating native loading")
local fighting=game()
fighting:OnShopBuy(nil,{hero="a"});fighting.phase="fight";callbacks.a()
assert(fighting.gold==500 and #fighting.ownedHeroes==0,"battle transition cancels pending purchase")
fighting.phase="setup";fighting:OnShopBuy(nil,{hero="a"})
assert(fighting.gold==400,"already-loaded hero can be explicitly purchased later")
local full=game();full.freeRecruitChoices=2
full:OnShopBuy(nil,{hero="a"});full.shopCosts.lineup_max=0;callbacks.a()
assert(full.freeRecruitChoices==2 and #full.ownedHeroes==0,"capacity revalidation preserves free choices")
print("hero-precache tests passed")
