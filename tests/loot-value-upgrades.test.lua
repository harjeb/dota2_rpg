local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
local Loot=require('battle.campaign_loot')
local Lives=require('battle.run_lives')
local assembled=require('data.assembled_loot_items')
local byName={}; for _,r in ipairs(Loot.Catalog) do byName[r.name]=r end
local axe=assert(byName.item_ogre_axe)
local choices={}
Loot.UpgradeEquipment(axe,function(a,b)
 for i=a,b do choices[Loot.UpgradeEquipment(axe,function() return i end).name]=true end
 return a
end)
assert(choices.item_dragon_lance and choices.item_lesser_crit,'1000-gold axe draws affordable assembled equipment')
assert(not choices.item_hyperstone and not choices.item_demon_edge,'no replacement with raw stat pieces')
for name in pairs(choices) do assert(byName[name].cost<=2000 and assembled[name]) end
for _,row in ipairs(Loot.Catalog) do
 local result=Loot.UpgradeEquipment(row,function(a) return a end)
 if row.category=='standard' and result~=row then assert(result.cost<=row.cost*2 and assembled[result.name])
 else assert(result==row,'neutral/special rewards unchanged') end
end
assert(#Loot.EquipmentPool(14800,true)>=16,'native price ceiling retains a broad top band')
local game={currentLevelId='ch04',GetStashUnit=function() return nil end}
local config={pool='all_items',items={{chance=1},{chance=1},{chance=1}}}
local original=Loot.Roll
Loot.Roll=function() return {axe,axe,axe} end
local earned=Loot.Award(game,config,function(a) return a end)
assert(#earned==3 and #Lives.Ensure(game).pendingCampaignLoot==3,'one improved reward per original gate, no doubled copies')
for _,name in ipairs(earned) do assert(choices[name],'Award actually enqueues upgraded equipment') end
for _,difficulty in ipairs({'easy','hard'}) do
 local g={campaignDifficulty=difficulty,currentLevelId='ch04',GetStashUnit=function() return nil end}
 local names=Loot.Award(g,config,function(a) return a end)
 local expected=Loot.FinalEquipment(g,axe,function(a) return a end)
 assert(#names==3 and #Lives.Ensure(g).pendingCampaignLoot==3)
 for _,name in ipairs(names) do assert(name==expected.delivery,'apply difficulty to the x2 budget once before the final draw') end
 Loot.Flush(g);Loot.Flush(g)
 assert(#Lives.Ensure(g).pendingCampaignLoot==3,'delivery retries neither reroll nor multiply')
 for _,pending in ipairs(Lives.Ensure(g).pendingCampaignLoot) do assert(pending.delivery==expected.delivery) end
end
Loot.Roll=original
local fresh={currentLevelId='ch04',GetStashUnit=function() return nil end}
local function first(a) return a or 0 end
local base=Loot.Roll(config,first,4,{})
local actual=Loot.Award(fresh,config,first)
assert(#actual==#base and #actual==3,'real roll-to-award pipeline retains gate count')
for i,name in ipairs(actual) do assert(byName[name].cost>base[i].cost,'real rewards increase in per-item value') end
print('PASS broad assembled value bands, native cap diversity, neutral exclusions and actual Award quantity')
