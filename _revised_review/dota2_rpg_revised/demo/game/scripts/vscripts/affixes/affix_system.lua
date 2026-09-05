local Definitions = require("data/affix_definitions")

local AffixSystem = {}
AffixSystem.__index = AffixSystem

local MODULUS = 2147483647
local MULTIPLIER = 48271

local THREAT_BANDS = {
    { from_stage = 1,  to_stage = 4,  budget = 0 },
    { from_stage = 5,  to_stage = 9,  budget = 1 },
    { from_stage = 10, to_stage = 14, budget = 2 },
    { from_stage = 15, to_stage = 19, budget = 3 },
    { from_stage = 20, to_stage = 24, budget = 4 },
    { from_stage = 25, to_stage = 29, budget = 5 },
    { from_stage = 30, to_stage = 30, budget = 6 },
}

local function valid_entity(entity)
    return entity ~= nil and (entity.IsNull == nil or not entity:IsNull())
end

local function copy_table(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function tag_set(raw_tags, unit)
    local result = {}
    for key, value in pairs(raw_tags or {}) do
        if type(key) == "string" and value == true then
            result[key] = true
        else
            result[value] = true
        end
    end
    if valid_entity(unit) then
        if unit.IsRealHero ~= nil and unit:IsRealHero() then result.hero = true end
        if unit.IsBoss ~= nil and unit:IsBoss() then result.boss = true end
    end
    return result
end

local function any_allowed(tags, allowed)
    if allowed == nil or #allowed == 0 then return true end
    for _, wanted in ipairs(allowed) do
        if tags[wanted] then return true end
    end
    return false
end

local function hash_string(value)
    local hash = 5381
    for index = 1, #value do
        hash = (hash * 33 + string.byte(value, index)) % MODULUS
    end
    return hash
end

local RNG = {}
RNG.__index = RNG

function RNG.new(seed)
    seed = math.floor(math.abs(tonumber(seed or 1))) % MODULUS
    if seed == 0 then seed = 1 end
    return setmetatable({ seed = seed }, RNG)
end

function RNG:Next()
    self.seed = (self.seed * MULTIPLIER) % MODULUS
    return self.seed
end

function RNG:Int(min_value, max_value)
    if max_value <= min_value then return min_value end
    return min_value + (self:Next() % (max_value - min_value + 1))
end

function RNG:Shuffle(values)
    for index = #values, 2, -1 do
        local other = self:Int(1, index)
        values[index], values[other] = values[other], values[index]
    end
end

function AffixSystem.new(options)
    options = options or {}
    return setmetatable({
        definitions = options.definitions or Definitions,
        get_tags = assert(options.get_tags, "get_tags is required"),
        state = assert(options.state, "current-run state is required"),
        affix_version = tostring(options.affix_version or "v1"),
    }, AffixSystem)
end

function AffixSystem:GetThreatBudget(stage)
    for _, band in ipairs(THREAT_BANDS) do
        if stage >= band.from_stage and stage <= band.to_stage then
            return band.budget
        end
    end
    return 0
end

function AffixSystem:GetMinimumCoverage(stage)
    if stage >= 25 then return 3 end
    if stage >= 20 then return 2 end
    if stage >= 10 then return 1 end
    return stage >= 5 and 1 or 0
end

function AffixSystem:GetStageSeed(stage)
    local run_seed = tonumber(self.state.run_seed or 1)
    local mixed = (run_seed + stage * 7919 + hash_string(self.affix_version)) % MODULUS
    if mixed == 0 then mixed = 1 end
    return mixed
end

function AffixSystem:BuildUnits(units)
    local result = {}
    for _, unit in ipairs(units or {}) do
        if valid_entity(unit) and unit:IsAlive() then
            local tags = tag_set(self.get_tags(unit), unit)
            table.insert(result, {
                entity = unit,
                entity_index = unit:entindex(),
                tags = tags,
                is_boss = tags.boss == true,
            })
        end
    end
    table.sort(result, function(a, b)
        return a.entity_index < b.entity_index
    end)
    return result
end

function AffixSystem:BuildOptions(units)
    local options = {}
    local affix_ids = {}
    for affix_id, definition in pairs(self.definitions) do
        if definition.enabled == true then
            table.insert(affix_ids, affix_id)
        end
    end
    table.sort(affix_ids)

    for _, affix_id in ipairs(affix_ids) do
        local definition = self.definitions[affix_id]
        for _, unit in ipairs(units) do
            if any_allowed(unit.tags, definition.allowed_tags) then
                table.insert(options, {
                    affix_id = affix_id,
                    definition = definition,
                    unit = unit,
                })
            end
        end
    end
    return options
end

local function category_slot(category)
    if category == "offense" then return "offense" end
    return "defense_support"
end

function AffixSystem:CanPlace(option, selected_by_unit, global_counts)
    local unit_id = option.unit.entity_index
    local placed = selected_by_unit[unit_id] or {}
    local limit = option.unit.is_boss and 3 or 2
    if #placed >= limit then return false end

    local definition = option.definition
    if (global_counts[option.affix_id] or 0) >= tonumber(definition.max_per_stage or 1) then
        return false
    end

    local wanted_slot = category_slot(definition.category)
    for _, existing in ipairs(placed) do
        if existing.affix_id == option.affix_id then return false end
        if existing.definition.stacking_group ~= nil
            and existing.definition.stacking_group == definition.stacking_group then
            return false
        end
        if category_slot(existing.definition.category) == wanted_slot then
            return false
        end
        for _, excluded in ipairs(definition.excluded_affixes or {}) do
            if excluded == existing.affix_id then return false end
        end
        for _, excluded in ipairs(existing.definition.excluded_affixes or {}) do
            if excluded == option.affix_id then return false end
        end
    end
    return true
end

function AffixSystem:Coverage(selected_by_unit)
    local count = 0
    for _, placed in pairs(selected_by_unit) do
        if #placed > 0 then count = count + 1 end
    end
    return count
end

function AffixSystem:SearchCombination(options, budget, min_coverage)
    local selected = {}
    local selected_by_unit = {}
    local global_counts = {}
    local nodes = 0
    local max_nodes = 50000

    local function place(option)
        local id = option.unit.entity_index
        selected_by_unit[id] = selected_by_unit[id] or {}
        table.insert(selected_by_unit[id], option)
        table.insert(selected, option)
        global_counts[option.affix_id] = (global_counts[option.affix_id] or 0) + 1
    end

    local function unplace(option)
        local id = option.unit.entity_index
        table.remove(selected_by_unit[id])
        table.remove(selected)
        global_counts[option.affix_id] = global_counts[option.affix_id] - 1
    end

    local function search(start_index, remaining)
        nodes = nodes + 1
        if nodes > max_nodes then return false end
        if remaining == 0 then
            return self:Coverage(selected_by_unit) >= min_coverage
        end

        for index = start_index, #options do
            local option = options[index]
            local cost = tonumber(option.definition.cost or 0)
            if cost > 0 and cost <= remaining
                and self:CanPlace(option, selected_by_unit, global_counts) then
                place(option)
                if search(index + 1, remaining - cost) then
                    return true
                end
                unplace(option)
            end
        end
        return false
    end

    if search(1, budget) then
        return selected
    end
    return nil
end

function AffixSystem:RollStage(stage, enemy_units)
    self.state.stage_affixes = self.state.stage_affixes or {}
    if self.state.stage_affixes[stage] ~= nil then
        return self.state.stage_affixes[stage]
    end

    local budget = self:GetThreatBudget(stage)
    if budget == 0 then
        self.state.stage_affixes[stage] = {}
        return self.state.stage_affixes[stage]
    end

    local units = self:BuildUnits(enemy_units)
    assert(#units > 0, "cannot roll affixes without enemy units")

    local rng = RNG.new(self:GetStageSeed(stage))
    local min_coverage = math.min(self:GetMinimumCoverage(stage), #units)
    local selected = nil

    for _attempt = 1, 20 do
        local options = self:BuildOptions(units)
        rng:Shuffle(options)
        selected = self:SearchCombination(options, budget, min_coverage)
        if selected ~= nil then break end
    end

    assert(selected ~= nil, "no legal affix combination for stage " .. tostring(stage))

    local rolled = {}
    for _, option in ipairs(selected) do
        table.insert(rolled, {
            affix_id = option.affix_id,
            unit_index = option.unit.entity_index,
            cost = option.definition.cost,
        })
    end
    self.state.stage_affixes[stage] = rolled
    self:SyncStage(stage, rolled)
    return rolled
end

function AffixSystem:ApplyStage(stage, enemy_units)
    local rolled = self:RollStage(stage, enemy_units)
    for _, record in ipairs(rolled) do
        local unit = EntIndexToHScript(record.unit_index)
        local definition = self.definitions[record.affix_id]
        if valid_entity(unit) and definition ~= nil then
            unit._rpg_affixes = unit._rpg_affixes or {}
            unit._rpg_affixes[record.affix_id] = true
            unit._rpg_affix_behaviors = unit._rpg_affix_behaviors or {}

            if definition.behavior ~= nil then
                unit._rpg_affix_behaviors[definition.behavior] = true
            end
            if definition.implemented == true and definition.modifier ~= nil then
                local kv = copy_table(definition.modifier_kv)
                unit:AddNewModifier(unit, nil, definition.modifier, kv)
            end
        end
    end
    return rolled
end

function AffixSystem:HasAffix(unit, affix_id)
    return valid_entity(unit)
        and unit._rpg_affixes ~= nil
        and unit._rpg_affixes[affix_id] == true
end

function AffixSystem:HasBehavior(unit, behavior_id)
    return valid_entity(unit)
        and unit._rpg_affix_behaviors ~= nil
        and unit._rpg_affix_behaviors[behavior_id] == true
end

-- Merge into the project's single damage filter. Run this before bond damage bonuses.
function AffixSystem:FilterDamage(filter_table)
    local victim = EntIndexToHScript(filter_table.entindex_victim_const or -1)
    if not valid_entity(victim) then return true end

    local damage = tonumber(filter_table.damage or 0)
    local inflictor_index = tonumber(filter_table.entindex_inflictor_const or -1)

    local shell = victim:FindModifierByName("modifier_rpg_affix_spell_shell")
    if shell ~= nil and inflictor_index > 0 then
        local reduction = shell.GetReductionPct ~= nil and shell:GetReductionPct() or 40
        filter_table.damage = damage * (1 - reduction / 100)
        shell:Destroy()
        return true
    end

    local hide = victim:FindModifierByName("modifier_rpg_affix_thick_hide")
    if hide ~= nil
        and tonumber(filter_table.damagetype_const) == DAMAGE_TYPE_PHYSICAL
        and inflictor_index <= 0 then
        local reduction = hide.GetAttackReductionPct ~= nil and hide:GetAttackReductionPct() or 5
        filter_table.damage = damage * (1 - reduction / 100)
    end
    return true
end

function AffixSystem:SyncStage(stage, rolled)
    local compact = {}
    for index, record in ipairs(rolled or {}) do
        compact[index] = table.concat({
            tostring(record.unit_index),
            record.affix_id,
            tostring(record.cost),
        }, "|")
    end
    CustomNetTables:SetTableValue("rpg_affixes", tostring(stage), {
        version = self.affix_version,
        seed = self:GetStageSeed(stage),
        rolled = table.concat(compact, ";"),
    })
end

return AffixSystem
