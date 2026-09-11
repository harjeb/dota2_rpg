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
print("enemy-items.test.lua: passed")
