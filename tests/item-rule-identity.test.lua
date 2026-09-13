local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Snapshot = require("tactics/rule_snapshot")
local first, second = "item_black_king_bar", "item_blade_mail"
local function item(name)
    return {IsNull=function() return false end, GetAbilityName=function() return name end}
end
local inventory = {[0]=item(first)}
local hero = {GetUnitName=function() return "npc_dota_hero_axe" end,
    GetItemInSlot=function(_, slot) return inventory[slot] end}
local rules = {
    {action={kind="item",logical_id=first,name=first}, use_conditions={{type="self_hp_pct_gte",value=0.77}}},
    {action={kind="attack",logical_id="basic_attack"}},
}
local manager = {getRules=function() return rules end}
local function check()
    local snapshot = Snapshot.ForHero(manager,hero)
    assert(snapshot[1].action == first, "snapshot must preserve item identity instead of current inventory slot")
    assert(snapshot[1].use_conditions[1].value == 0.77)
    assert(snapshot[2].action == "attack", "inventory changes must preserve rule order")
end
check()
inventory = {[0]=item(second),[1]=item(first)}
check()
inventory = {[0]=item(second)}
check()
rules[1].action.logical_id = "item_1"
check() -- Legacy slot IDs with a saved native name must use the saved name.
assert(rules[1].action.logical_id == "item_1", "snapshot must not mutate stored rules")
print("PASS item rule snapshot identity and order through purchase, repacking, removal and legacy IDs")
