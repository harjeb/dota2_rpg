local Stats = dofile('game/dota_addons/dota2_rpg/scripts/vscripts/battle/damage_stats.lua')
local function unit(id, team, hero)
    local u = { id = id, team = team, hero = hero, name = 'duplicate_name' }
    function u:IsNull() return self.removed or false end
    function u:entindex() return self.id end
    function u:GetUnitName() return self.name end
    function u:GetTeamNumber() return self.team end
    function u:IsRealHero() return self.hero or false end
    function u:GetOwnerEntity() return self.owner end
    return u
end
local function ability(name)
    return { IsNull = function() return false end, GetAbilityName = function() return name end }
end
local function source(row, name)
    for _, item in ipairs(row.sources) do if item.name == name then return item end end
    error('Missing source ' .. name)
end
local a, b, c, idle = unit(1, 2, true), unit(2, 3, true), unit(3, 3), unit(4, 2)
local stats = Stats.new()
assert(#stats:Snapshot(0) == 0)
assert(not stats:Record(a, b, nil, 10, 0))
stats:Start({c, a, idle, b, a}, 10)
assert(#stats:Snapshot(10) == 4)
assert(stats:Record(a, b, nil, 40, 11))
assert(stats:Record(a, b, ability('fire'), 30, 12))
assert(stats:Record(a, c, ability('fire'), 50, 13))
assert(stats:Record(b, a, nil, 20, 13))
local snapshot = stats:Snapshot(14)
assert(snapshot[1].id == 1 and snapshot[2].id == 2)
assert(snapshot[1].name == snapshot[2].name)
assert(snapshot[1].team == 2 and snapshot[2].team == 3)
assert(snapshot[1].total == 120 and snapshot[1].dps == 30)
assert(snapshot[2].total == 20 and snapshot[2].dps == 5)
assert(snapshot[4].total == 0 and snapshot[4].dps == 0 and #snapshot[4].sources == 0)
assert(source(snapshot[1], 'attack').total == 40)
local fire = source(snapshot[1], 'fire')
assert(fire.total == 80 and #fire.targets == 2)
assert(fire.targets[1].id == 2 and fire.targets[1].total == 30)
assert(fire.targets[2].id == 3 and fire.targets[2].total == 50)
assert(snapshot[1].targets[1].total == 70 and snapshot[1].targets[2].total == 50)
snapshot[1].sources[1].targets[1].total = -99
snapshot[1].targets[1].total = -99
assert(stats:Snapshot(14)[1].targets[1].total == 70)
assert(source(stats:Snapshot(14)[1], 'attack').targets[1].total == 40)

-- Ownership is guarded and only registered heroes receive unregistered summon credit.
local summon, intermediate = unit(10, 2), unit(11, 2)
summon.owner = intermediate
intermediate.owner = a
assert(stats:Record(summon, b, nil, 8, 14))
intermediate.owner = idle
assert(not stats:Record(summon, b, nil, 100, 14))
intermediate.owner = summon
assert(not stats:Record(summon, b, nil, 100, 14))
intermediate.GetOwnerEntity = function() error('stale handle') end
assert(not stats:Record(summon, b, nil, 100, 14))
local deep = unit(100, 2)
local tail = deep
for i = 101, 125 do tail.owner = unit(i, 2); tail = tail.owner end
tail.owner = a
assert(not stats:Record(deep, b, nil, 100, 14))

-- Reject invalid/environment/self/allied/unregistered events without changing totals.
for _, value in ipairs({0, -1, math.huge, -math.huge, 0/0, '10'}) do
    assert(not stats:Record(a, b, nil, value, 15))
end
assert(not stats:Record(a, b, nil, nil, 15))
assert(not stats:Record(nil, b, nil, 10, 15))
assert(not stats:Record(12, b, nil, 10, 15))
assert(not stats:Record(a, a, nil, 10, 15))
assert(not stats:Record(a, idle, nil, 10, 15))
assert(not stats:Record(unit(99, 2), b, nil, 10, 15))
assert(not stats:Record(a, unit(99, 3), nil, 10, 15))
assert(not stats:Record(unit(1, 2), b, nil, 10, 15)) -- Reused entindex.
assert(not stats:Record(a, b, {}, 10, 15))
assert(not stats:Record(a, b, ability(''), 10, 15))
b.removed = true
assert(not stats:Record(a, b, nil, 10, 15))
b.removed = false
b.team = 2
assert(not stats:Record(a, b, nil, 10, 15))
b.team = 3
assert(stats:Snapshot(14)[1].total == 128)
local stopped = stats:Stop(18)
assert(stopped[1].dps == 16)
assert(stats:Snapshot(1000)[1].dps == 16)
assert(stats:Stop(2000)[1].dps == 16)
assert(not stats:Record(a, b, nil, 100, 2000))
a.removed = true
assert(stats:Snapshot(3000)[1].total == 128)
a.removed = false

-- A fresh fight resets maps; zero/backward/invalid timestamps keep finite DPS.
stats:Start({a, b}, 100)
assert(stats:Snapshot(100)[1].total == 0)
assert(stats:Record(a, b, nil, 10, 100))
assert(stats:Snapshot(100)[1].dps == 0)
assert(stats:Snapshot(90)[1].dps == 0)
assert(stats:Snapshot(0/0)[1].dps == 0)
for i = 1, 200 do assert(stats:Record(a, b, ability('spell_' .. i), 1, 101)) end
local bounded = stats:Snapshot(102)[1]
assert(#bounded.sources == 64 and bounded.total == 210)
assert(#bounded.targets == 1 and source(bounded, 'other').total == 138)
local sum = 0
for _, item in ipairs(bounded.sources) do
    assert(#item.targets == 1)
    sum = sum + item.total
end
assert(sum == bounded.total)
stats:Start({}, 0)
assert(#stats:Snapshot(1) == 0)
local neutral = unit(8, 4)
stats:Start({ {unit=a, team=2}, {unit=neutral, team=3} }, 30)
assert(stats:Record(neutral, a, nil, 25, 31))
assert(stats:Snapshot(31)[2].team == 3, 'neutral wave uses logical enemy side')
assert(stats:Snapshot(31)[2].dps == 25)
stats:Start({ {unit=a, team=2}, {unit=neutral, team=2} }, 30)
assert(not stats:Record(neutral, a, nil, 25, 31), 'logical allies excluded')
print('PASS: damage totals, DPS, source/victim splits, identities, ownership, guards, bounds and lifecycle')
