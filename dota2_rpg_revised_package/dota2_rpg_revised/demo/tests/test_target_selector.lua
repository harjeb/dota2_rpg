local root = arg[1] or "../game/scripts/vscripts"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Vec = {}
Vec.__index = Vec
function Vec.new(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, Vec) end
function Vec.__sub(a, b) return Vec.new(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vec.__add(a, b) return Vec.new(a.x + b.x, a.y + b.y, a.z + b.z) end
function Vec.__div(a, value) return Vec.new(a.x / value, a.y / value, a.z / value) end
function Vec:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
Vector = Vec.new

local Unit = {}
Unit.__index = Unit
function Unit.new(id, hp, max_hp, x, tags)
    return setmetatable({ id = id, hp = hp, max_hp = max_hp, pos = Vec.new(x, 0, 0), tags = tags or {} }, Unit)
end
function Unit:IsNull() return false end
function Unit:IsAlive() return self.hp > 0 end
function Unit:entindex() return self.id end
function Unit:GetHealth() return self.hp end
function Unit:GetMaxHealth() return self.max_hp end
function Unit:GetMana() return 100 end
function Unit:GetMaxMana() return 100 end
function Unit:GetAbsOrigin() return self.pos end
function Unit:GetPhysicalArmorValue() return 5 end
function Unit:GetAverageTrueAttackDamage() return 50 end
function Unit:GetMagicalArmorValue() return 0.25 end
function Unit:IsChanneling() return false end

local TargetSelector = require("tactics/target_selector")
local selector = TargetSelector.new()
local caster = Unit.new(1, 1000, 1000, 0, {})
local healer = Unit.new(2, 350, 1000, 300, { healer = true })
local tank = Unit.new(3, 200, 1000, 200, { frontline = true })
local full = Unit.new(4, 900, 1000, 100, {})
local candidates = { healer, tank, full }

local ctx = {
    caster = caster,
    get_tags = function(unit) return unit.tags end,
    get_candidates = function() return candidates end,
}

local rule = {
    target_filters = { { type = "hp_pct_lte", value = 0.5 } },
    target_priorities = {
        { type = "prefer_tag", value = "healer" },
        { type = "lowest_hp_pct" },
    },
    target = { team = "enemy" },
}
local spec = { target_mode = "unit", target_team = "enemy" }
local selected = selector:SelectUnit(rule, spec, ctx)
assert(selected == healer, "soft healer priority should win among legal targets")

rule.target_priorities = { { type = "prefer_tag", value = "nonexistent" }, { type = "lowest_hp_pct" } }
selected = selector:SelectUnit(rule, spec, ctx)
assert(selected == tank, "missing preferred tag must fall back to another legal target")

rule.target_filters = { { type = "hp_pct_lte", value = 0.1 } }
selected = selector:SelectUnit(rule, spec, ctx)
assert(selected == nil, "hard filter must reject every target")

print("target selector tests passed")
