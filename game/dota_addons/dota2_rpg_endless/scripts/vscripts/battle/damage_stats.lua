-- Standalone collector. The caller owns event hooks and supplies post-mitigation damage.
local DamageStats = {}
DamageStats.__index = DamageStats
local MAX_SOURCES = 64 -- Includes the reserved attack and overflow buckets.
local MAX_OWNER_DEPTH = 16

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end

local function call(entity, method)
    if entity == nil then return nil end
    local ok, result = pcall(function()
        local fn = entity[method]
        if type(fn) == 'function' then return fn(entity) end
    end)
    if ok then return result end
end

local function valid(entity)
    return (type(entity) == 'table' or type(entity) == 'userdata')
        and call(entity, 'IsNull') == false
end

local function identity(entity)
    if not valid(entity) then return nil end
    local id = call(entity, 'entindex') or call(entity, 'GetEntityIndex')
    if finite(id) and id > 0 and id == math.floor(id) then return id end
end

local function targetsSnapshot(targets, units)
    local result = {}
    for id, total in pairs(targets) do
        result[#result + 1] = { id = id, name = units[id].name, total = total }
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function DamageStats.new()
    return setmetatable({ units = {}, active = false, startedAt = 0, lastAt = 0 }, DamageStats)
end

-- Accept raw entities or {unit=entity, team=logicalSide}; neutral waves belong to Dire.
function DamageStats:Start(units, now)
    self.units = {}
    self.startedAt = finite(now) and now or 0
    self.lastAt = self.startedAt
    self.stoppedAt = nil
    self.active = true
    for _, entry in ipairs(units or {}) do
        local entity = type(entry) == 'table' and entry.unit or entry
        local id = identity(entity)
        local name = call(entity, 'GetUnitName')
        local team = (type(entry) == 'table' and entry.unit and entry.team) or call(entity, 'GetTeamNumber')
        if id and type(name) == 'string' and finite(team) and not self.units[id] then
            self.units[id] = { id = id, entity = entity, name = name, team = team,
                total = 0, sources = {}, sourceCount = 0, targets = {} }
        end
    end
end

function DamageStats:_Registered(entity)
    local row = self.units[identity(entity)]
    if row and row.entity == entity then return row end
end

function DamageStats:_Attacker(entity)
    local direct = self:_Registered(entity)
    if direct then return direct end
    local seen = {}
    for _ = 1, MAX_OWNER_DEPTH do
        if not valid(entity) or seen[entity] then return nil end
        seen[entity] = true
        entity = call(entity, 'GetOwnerEntity')
        local owner = self:_Registered(entity)
        if owner and call(entity, 'IsRealHero') == true then return owner end
    end
end

function DamageStats:Record(attacker, victim, inflictor, damage, now)
    if not self.active or not finite(damage) or damage <= 0 then return false end
    if not valid(attacker) or not valid(victim) or attacker == victim then return false end
    local source = self:_Attacker(attacker)
    local target = self:_Registered(victim)
    if not source or not target or source.id == target.id then return false end
    if source.team == target.team then return false end
    local attackerTeam = call(attacker, 'GetTeamNumber')
    local victimTeam = call(victim, 'GetTeamNumber')
    local ownerTeam = call(source.entity, 'GetTeamNumber')
    if not finite(attackerTeam) or not finite(victimTeam) or not finite(ownerTeam)
        or attackerTeam == victimTeam or ownerTeam == victimTeam then return false end
    local name = 'attack'
    if inflictor ~= nil then
        if not valid(inflictor) then return false end
        name = call(inflictor, 'GetAbilityName')
        if type(name) ~= 'string' or name == '' then return false end
    end
    if not finite(source.total + damage) then return false end
    if not source.sources[name] and name ~= 'attack' and name ~= 'other'
        and source.sourceCount >= MAX_SOURCES - 2 then name = 'other' end
    local bucket = source.sources[name]
    if not bucket then
        bucket = { total = 0, targets = {} }
        source.sources[name] = bucket
        if name ~= 'attack' and name ~= 'other' then
            source.sourceCount = source.sourceCount + 1
        end
    end
    source.total = source.total + damage
    source.targets[target.id] = (source.targets[target.id] or 0) + damage
    bucket.total = bucket.total + damage
    bucket.targets[target.id] = (bucket.targets[target.id] or 0) + damage
    if finite(now) then self.lastAt = math.max(self.lastAt, now) end
    return true
end

function DamageStats:Snapshot(now)
    local at = self.stoppedAt or (finite(now) and math.max(self.lastAt, now) or self.lastAt)
    local elapsed = math.max(0, at - self.startedAt)
    local result = {}
    for _, unit in pairs(self.units) do
        local sources = {}
        for name, bucket in pairs(unit.sources) do
            sources[#sources + 1] = { name = name, total = bucket.total,
                targets = targetsSnapshot(bucket.targets, self.units) }
        end
        table.sort(sources, function(a, b) return a.name < b.name end)
        result[#result + 1] = { id = unit.id, name = unit.name, team = unit.team,
            total = unit.total, dps = elapsed > 0 and unit.total / elapsed or 0,
            sources = sources, targets = targetsSnapshot(unit.targets, self.units) }
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function DamageStats:Stop(now)
    if self.active then
        self.stoppedAt = finite(now) and math.max(self.lastAt, now) or self.lastAt
        self.active = false
    end
    return self:Snapshot(now)
end

return DamageStats
