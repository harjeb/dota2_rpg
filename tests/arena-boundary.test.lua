local root=TEST_REPO_ROOT or "."
package.path=root.."/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;"..package.path
function class(t) return t or {} end
function Vector(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_ORDER_PURCHASE_ITEM,DOTA_UNIT_ORDER_SELL_ITEM,DOTA_UNIT_ORDER_DISASSEMBLE_ITEM=16,17,18
DOTA_UNIT_ORDER_TRAIN_ABILITY,DOTA_UNIT_ORDER_CONSUME_ITEM,DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH=11,41,42
require("addon_game_mode")
local Integration=require("battle.arena_integration")
local Arena=require("battle.arena_mode")
local Compat=require("issue_fixes.compat")
local hits={}
local g=setmetatable({phase="setup",playerId=0,arena={mode="select",phase="preparing",generation=1,results={},serial=1},
 dataLoader={GetLevel=function(_,id) return {id=id} end},battleManager={teamHeroes={[2]={},[3]={}}}}, {__index=CDota2RpgDemo})
for _,name in ipairs({"OnShopBuy","OnShopRefresh","OnBenchBuy","OnLineupSet","PromoteBenchHero","OnSelectLevel","OnHeroLevels","OnReplayRun",
 "OnScrollBuy","OnScrollUse","OnShardBuy","OnItemSell","OnItemEquip","OnItemUnequip","OnStartBattle","SpawnLevelEnemies"}) do
 g[name]=function() hits[name]=(hits[name] or 0)+1;return true end
end
Integration.Install(g)
assert(not g:OnStartBattle() and not g:OnShopBuy() and not g:OnItemEquip())
assert(Compat.new(g):GetPhase()=="SETTLE")
g.arena.mode="campaign";assert(g:OnShopBuy() and g:OnStartBattle())
g.arena.mode="arena";g.arena.phase="preparing"
assert(not g:OnShopBuy() and not g:OnLineupSet() and not g:OnHeroLevels())
assert(g:OnShardBuy() and g:OnItemEquip() and not g:OnStartBattle())
assert(g.dataLoader:GetLevel("arena").reward.gold==0)
g.arena.locked=true;g.arena.phase="adjusting"
assert(not g:OnShardBuy() and not g:OnItemSell() and g:OnItemUnequip())
assert(Compat.new(g):GetPhase()=="PREPARE")
-- Exercise the actual addon order filter, including unitless purchase paths.
for _,order in ipairs({16,17,18,11,41,42}) do
 assert(not CDota2RpgDemo.ValidatePrepareOrder(g,{order_type=order,issuer_player_id_const=0,units={}}))
end
g.arena.phase="matching";assert(not g:OnItemEquip() and Compat.new(g):GetPhase()=="SETTLE")
g.arena.phase="fighting";g.arenaLaunching=true;assert(g:OnStartBattle());g.arenaLaunching=false
assert(not g:OnStartBattle())
assert(hits.OnShopBuy==1 and hits.OnStartBattle==2 and hits.OnShardBuy==1)
assert(not require("battle.skill_debug").Start(g,{}),"skill debug cannot replace an active ranked team")
print("PASS real addon arena entry, campaign/recruitment, native purchase/training, transfer phase and launch boundaries")
