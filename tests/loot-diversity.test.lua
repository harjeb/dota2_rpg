local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
local Loot=require('battle.campaign_loot')
local D=require('battle.campaign_difficulty')
local Lives=require('battle.run_lives')
local byName={}; for _,row in ipairs(Loot.Catalog) do byName[row.name]=row end
-- Exhaust every possible final index, including an existing highest-price history.
-- Verify breadth on the Award output, after ALL budget transformations.
local config={pool='all_items',items={{chance=1}}}
local originalRoll=Loot.Roll
local oldPrint=print; print=function() end
for _,difficulty in ipairs({'easy','default','hard'}) do
 for stage=1,30 do
  for _,base in ipairs(Loot.PoolForStage(stage)) do
   if base.category=='standard' then
    local game={campaignDifficulty=difficulty}
    local budget=D.Scale(game,base.cost*2)
    local pool=Loot.EquipmentPool(budget,true)
    local affordable=0
    local families={}
    local assembled=require('data.assembled_loot_items')
    for _,row in ipairs(Loot.Catalog) do
     if row.category=='standard' and row.cost>0 and assembled[row.name] and row.cost<=budget then families[row.name:gsub('^item_dagon_%d+$','item_dagon')]=true end
    end
    for _ in pairs(families) do affordable=affordable+1 end
    assert(#pool>=math.min(16,affordable),'retain all candidates until at least16 families affordable')
    for _,row in ipairs(pool) do assert(row.cost<=budget and assembled[row.name]) end
   end
  end
 end
 local base=byName.item_dagon_5
 local pool=Loot.EquipmentPool(D.Scale({campaignDifficulty=difficulty},base.cost*2),true)
 assert(#pool>=16)
 local seen={}
 for pick=1,#pool do
  local game={campaignDifficulty=difficulty,currentLevelId='ch30',GetStashUnit=function() return nil end}
  Lives.Ensure(game).campaignLootProgress={highestEquipmentCost=7400}
  Loot.Roll=function() return {base} end
  local names=Loot.Award(game,config,function(a,b) assert(pick<=b);return pick end)
  assert(#names==1 and names[1]==pool[pick].delivery)
  seen[names[1]]=true
  Loot.Flush(game)
  assert(Lives.Ensure(game).pendingCampaignLoot[1].delivery==names[1],'delivery retains earned choice')
 end
 local count,dagons=0,0
 for name in pairs(seen) do count=count+1;if name:match('^item_dagon') then dagons=dagons+1 end end
 assert(count>=16 and dagons==1,'late Award has16+ equipment families, only one Dagon')
end
Loot.Roll=originalRoll
-- Real random pipeline, with category and gate rolls enabled.
local seed=918103
local function random(a,b)
 seed=(seed*16807)%2147483647
 local f=(seed-1)/2147483646
 return a and a+math.floor(f*(b-a+1)) or f
end
for _,difficulty in ipairs({'easy','default','hard'}) do
 local game={campaignDifficulty=difficulty,currentLevelId='ch30',GetStashUnit=function() return nil end}
 local seen,total,dagons,neutrals={},0,0,0
 for roll=1,3000 do
  game.runLives=nil
  for _,name in ipairs(Loot.Award(game,config,random)) do
   local row=byName[name]
   if row.category=='standard' then
    seen[name]=true;total=total+1
    if name=='item_dagon_5' then dagons=dagons+1 end
   elseif row.neutral then neutrals=neutrals+1 end
  end
 end
 local count=0;for _ in pairs(seen) do count=count+1 end
 assert(count>=16 and dagons/total<.12,'full pipeline cannot collapse into Dagon5')
 assert(neutrals>200,'neutral rewards survive final value selection')
 oldPrint(string.format('PASS %s late Award: %d equipment names; Dagon5 %.2f%%; neutrals %d',difficulty,count,dagons/total*100,neutrals))
end
print=oldPrint
