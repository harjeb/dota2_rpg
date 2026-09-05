local root = arg[1] or "../game/scripts/vscripts"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

CustomNetTables = { SetTableValue = function() end }

local Unit = {}
Unit.__index = Unit
function Unit.new(id, tags)
    return setmetatable({ id = id, tags = tags }, Unit)
end
function Unit:IsNull() return false end
function Unit:IsAlive() return true end
function Unit:entindex() return self.id end
function Unit:IsRealHero() return self.tags.hero == true end
function Unit:IsBoss() return self.tags.boss == true end

local entity_map = {}
function EntIndexToHScript(id) return entity_map[id] end

local AffixSystem = require("affixes/affix_system")
local units = {
    Unit.new(101, { hero = true, boss = true, elite = true, frontline = true }),
    Unit.new(102, { hero = true, frontline = true }),
    Unit.new(103, { hero = true, diver = true, assassin = true }),
    Unit.new(104, { hero = true, support = true }),
    Unit.new(105, { hero = true }),
    Unit.new(106, { hero = true }),
    Unit.new(107, { monster = true }),
}
for _, unit in ipairs(units) do entity_map[unit.id] = unit end

local function roll(seed)
    local state = { run_seed = seed, stage_affixes = {} }
    local system = AffixSystem.new({
        state = state,
        get_tags = function(unit) return unit.tags end,
        affix_version = "test_v1",
    })
    local result = system:RollStage(30, units)
    local cost = 0
    local covered = {}
    for _, record in ipairs(result) do
        cost = cost + record.cost
        covered[record.unit_index] = true
    end
    assert(cost == 6)
    local coverage = 0
    for _ in pairs(covered) do coverage = coverage + 1 end
    assert(coverage >= 3)
    return result
end

local a = roll(123456)
local b = roll(123456)
assert(#a == #b)
for index = 1, #a do
    assert(a[index].affix_id == b[index].affix_id)
    assert(a[index].unit_index == b[index].unit_index)
end
print("affix generation tests passed")
