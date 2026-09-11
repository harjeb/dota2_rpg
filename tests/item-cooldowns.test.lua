local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Cooldowns = require("battle.item_cooldowns")
local items = {}
local function carrier()
    local slots = {}
    for slot=0,16 do
        local item={remaining=100,charges=2,secondary=4,custom={used=true},calls=0}
        function item:EndCooldown() self.remaining=0; self.calls=self.calls+1 end
        slots[slot]=item; items[#items+1]=item
    end
    return {IsAlive=function() return false end, GetItemInSlot=function(_,slot) return slots[slot] end}
end
local active,bench,stash=carrier(),carrier(),carrier()
local game={phase="fight",battleManager={teamHeroes={[2]={active},[3]={}}},benchUnits={bench,active},GetStashUnit=function() return stash end}
for _,phase in ipairs({"fight","countdown"}) do
    game.phase=phase; Cooldowns.Refresh(game)
    for _,item in ipairs(items) do assert(item.remaining==100 and item.calls==0) end
end
for _,phase in ipairs({"result","setup"}) do
    game.phase=phase
    for _,item in ipairs(items) do item.remaining=100; item.calls=0 end
    Cooldowns.Refresh(game)
    for _,item in ipairs(items) do
        assert(item.remaining==0 and item.calls==1,"refresh every native slot once including dead, bench and warehouse")
        assert(item.charges==2 and item.secondary==4 and item.custom.used,"preserve charges and custom state")
    end
end
local invalid={IsNull=function() return true end,GetItemInSlot=function() error("invalid carrier") end}
game.benchUnits={invalid,{}}
game.battleManager.teamHeroes={[2]={{GetItemInSlot=function() return {IsNull=function() return true end,EndCooldown=function() error("invalid item") end} end}}}
Cooldowns.Refresh(game)
print("PASS: item refresh covers all slots/carriers, preserves charges, skips invalid handles and live combat")
