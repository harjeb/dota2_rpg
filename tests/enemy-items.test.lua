local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Items = require("patches.enemy_items_patch")
local calls = {}
local unit = { AddItemByName = function(_, name)
    calls[#calls + 1] = name
    if name == "item_invalid" then error("unknown native item") end
    if name == "item_null" then return { IsNull = function() return true end } end
    return { IsNull = function() return false end }
end }
local count = Items.EquipConfiguredItems(unit, { unit = "npc_dota_hero_crystal_maiden", items = {
    ["3"] = "item_glimmer_cape", ["1"] = "item_invalid", ["2"] = "item_null", ["4"] = "item_assault",
} })
assert(count == 2, "only live native items count as equipped")
assert(table.concat(calls, ",") == "item_invalid,item_null,item_glimmer_cape,item_assault",
    "KV slots must stay ordered and one failure must not prevent remaining equipment")
assert(Items.EquipConfiguredItems(nil, { items = {} }) == 0)
assert(Items.EquipConfiguredItems({ IsNull = function() return true end }, { items = { "item_boots" } }) == 0)
local created, added = nil, nil
CreateItem = function(name, owner, purchaser)
    assert(owner == purchaser)
    created = { name = name }
    return created
end
assert(Items.EquipConfiguredItems({ AddItem = function(_, item) added = item; return item end },
    { items = { "item_boots" } }) == 1)
assert(added == created, "fallback adds the original native item entity")
-- High-level cores now use all six active slots. Native item identity and
-- ordering must survive the larger KV inventory without touching economy APIs.
calls = {}
local lateCarry = {
    ["6"] = "item_satanic", ["2"] = "item_hurricane_pike", ["4"] = "item_butterfly",
    ["1"] = "item_power_treads", ["5"] = "item_black_king_bar", ["3"] = "item_manta",
}
assert(Items.EquipConfiguredItems(unit, {unit = "npc_dota_hero_drow_ranger", level = "30", items = lateCarry}) == 6)
assert(table.concat(calls, ",") == "item_power_treads,item_hurricane_pike,item_manta,item_butterfly,item_black_king_bar,item_satanic")
assert(lateCarry["6"] == "item_satanic", "equipping does not rewrite the configured build")
calls = {}
local spiritBoss = {"item_silver_edge", "item_ultimate_scepter", "item_black_king_bar", "item_octarine_core", "item_moon_shard", "item_moon_shard"}
assert(Items.EquipConfiguredItems(unit, {unit="npc_dota_hero_spirit_breaker", items=spiritBoss}) == 6)
assert(calls[5] == "item_moon_shard" and calls[6] == "item_moon_shard",
    "two configured Moon Shards must create two native items, not deduplicate or consume one")
local function inventoryUnit(rejectSwap)
    local inventory = {}
    local result = { inventory = inventory }
    function result:AddItemByName(name)
        local slot = 0
        while inventory[slot] do slot = slot + 1 end
        local item = { name = name, slot = slot }
        function item:GetItemSlot() return self.slot end
        inventory[slot] = item
        return item
    end
    function result:SwapItems(a, b)
        if rejectSwap then return end
        inventory[a], inventory[b] = inventory[b], inventory[a]
        if inventory[a] then inventory[a].slot = a end
        if inventory[b] then inventory[b].slot = b end
    end
    function result:RemoveItem(item) inventory[item.slot] = nil end
    return result
end
for _, backpack in ipairs({{ [2] = "item_bottle", [3] = "item_dust" },
                           { ["1"] = "", ["2"] = "item_bottle", ["3"] = "item_dust" }}) do
    local hero = inventoryUnit()
    assert(Items.EquipConfiguredItems(hero, {items=spiritBoss, backpack_items=backpack,
        neutral_item="item_desolator_2"}) == 9)
    for index, name in ipairs(spiritBoss) do assert(hero.inventory[index - 1].name == name) end
    assert(hero.inventory[6] == nil, "empty backpack slots must not collapse")
    assert(hero.inventory[7].name == "item_bottle" and hero.inventory[8].name == "item_dust")
    assert(hero.inventory[16].name == "item_desolator_2", "neutral must not occupy a main/backpack slot")
end
local rejected = inventoryUnit(true)
assert(Items.EquipConfiguredItems(rejected, {items={"item_boots"},
    backpack_items={[3]="item_bottle"}, neutral_item="item_demonicon"}) == 1)
assert(rejected.inventory[0].name == "item_boots" and rejected.inventory[1] == nil,
    "rejected optional placement must not grant active inventory stats")
local plan = require("battle.stage_precache").Plan({enemies={{unit="npc_dota_hero_mirana",
    items={"item_boots"}, backpack_items={["1"]="", ["2"]="item_dust"}, neutral_item="item_conjurers_catalyst"}}})
assert(table.concat(plan.items, ",") == "item_boots,item_conjurers_catalyst,item_dust",
    "stage precache must include backpack and neutral equipment and skip empty slots")
print("enemy-items.test.lua: passed")
