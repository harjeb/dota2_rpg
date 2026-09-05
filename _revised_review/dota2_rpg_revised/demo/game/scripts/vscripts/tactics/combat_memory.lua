local CombatMemory = {}
CombatMemory.__index = CombatMemory

function CombatMemory.new(now_fn)
    return setmetatable({
        now_fn = now_fn or function() return GameRules:GetGameTime() end,
        last_damage_time = {},
        action_use_count = {},
    }, CombatMemory)
end

local function entity_index(entity)
    if entity == nil or entity.entindex == nil then
        return -1
    end
    return entity:entindex()
end

function CombatMemory:Reset()
    self.last_damage_time = {}
    self.action_use_count = {}
end

function CombatMemory:RecordDamage(victim)
    local id = entity_index(victim)
    if id >= 0 then
        self.last_damage_time[id] = self.now_fn()
    end
end

function CombatMemory:WasDamagedWithin(unit, seconds)
    local id = entity_index(unit)
    local last_time = self.last_damage_time[id]
    if last_time == nil then
        return false
    end
    return self.now_fn() - last_time <= seconds
end

function CombatMemory:AnyAllyDamagedWithin(caster, allies, seconds)
    for _, ally in ipairs(allies or {}) do
        if ally ~= caster and self:WasDamagedWithin(ally, seconds) then
            return true
        end
    end
    return false
end

function CombatMemory:RecordActionUse(unit, logical_action_id)
    local id = entity_index(unit)
    if id < 0 then
        return
    end
    self.action_use_count[id] = self.action_use_count[id] or {}
    local per_unit = self.action_use_count[id]
    per_unit[logical_action_id] = (per_unit[logical_action_id] or 0) + 1
end

function CombatMemory:GetActionUseCount(unit, logical_action_id)
    local id = entity_index(unit)
    local per_unit = self.action_use_count[id] or {}
    return per_unit[logical_action_id] or 0
end

return CombatMemory
