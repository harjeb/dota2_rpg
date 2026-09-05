local Definitions = require("data/bond_definitions")

local BondSystem = {}
BondSystem.__index = BondSystem

local CAPS = {
    member_max_health_pct = 12,
    member_mana_regen_pct = 20,
    member_heal_amp_pct = 10,
    hunt_mark_damage_pct = 10,
    disabled_target_damage_pct = 10,
    summon_health_pct = 15,
    summon_duration_pct = 15,
}

local function valid_entity(entity)
    return entity ~= nil and (entity.IsNull == nil or not entity:IsNull())
end

local function has_tag(tags, wanted)
    if tags == nil then return false end
    if tags[wanted] == true then return true end
    for _, value in pairs(tags) do
        if value == wanted then return true end
    end
    return false
end

local function highest_threshold(definition, count)
    local best = nil
    for threshold, effects in pairs(definition.thresholds or {}) do
        local numeric = tonumber(threshold)
        if count >= numeric and (best == nil or numeric > best.threshold) then
            best = { threshold = numeric, effects = effects }
        end
    end
    return best
end

local function capped(effect_name, value)
    local cap = CAPS[effect_name]
    if cap == nil then return value end
    return math.min(value, cap)
end

function BondSystem.new(options)
    options = options or {}
    return setmetatable({
        definitions = options.definitions or Definitions,
        get_tags = assert(options.get_tags, "get_tags is required"),
        get_row_tag = assert(options.get_row_tag, "get_row_tag is required"),
        snapshot = nil,
        runtime = nil,
    }, BondSystem)
end

function BondSystem:BuildSnapshot(active_units)
    local counts = {}
    local units = {}
    local seen = {}

    for _, unit in ipairs(active_units or {}) do
        if valid_entity(unit) and unit:IsAlive() then
            local id = unit:entindex()
            if not seen[id] then
                seen[id] = true
                table.insert(units, unit)
                local tags = self.get_tags(unit) or {}
                for bond_id, _ in pairs(self.definitions) do
                    if has_tag(tags, bond_id) then
                        counts[bond_id] = (counts[bond_id] or 0) + 1
                    end
                end
            end
        end
    end

    local active = {}
    for bond_id, count in pairs(counts) do
        local definition = self.definitions[bond_id]
        local selected = highest_threshold(definition, count)
        if selected ~= nil then
            active[bond_id] = {
                id = bond_id,
                name = definition.name,
                count = count,
                threshold = selected.threshold,
                effects = selected.effects,
            }
        end
    end

    local snapshot = {
        units = units,
        active = active,
        unit_tags = {},
    }
    for _, unit in ipairs(units) do
        snapshot.unit_tags[unit:entindex()] = self.get_tags(unit) or {}
    end
    return snapshot
end

function BondSystem:UnitHasBond(unit, bond_id)
    if self.snapshot == nil or unit == nil then return false end
    local tags = self.snapshot.unit_tags[unit:entindex()]
    return self.snapshot.active[bond_id] ~= nil and has_tag(tags, bond_id)
end

function BondSystem:AggregateStatsForUnit(unit)
    local stats = {
        max_health_pct = 0,
        mana_regen_pct = 0,
        heal_amp_pct = 0,
    }
    if self.snapshot == nil then return stats end

    for bond_id, active in pairs(self.snapshot.active) do
        if self:UnitHasBond(unit, bond_id) then
            local effects = active.effects
            stats.max_health_pct = stats.max_health_pct + tonumber(effects.member_max_health_pct or 0)
            stats.mana_regen_pct = stats.mana_regen_pct + tonumber(effects.member_mana_regen_pct or 0)
            stats.heal_amp_pct = stats.heal_amp_pct + tonumber(effects.member_heal_amp_pct or 0)
        end
    end

    stats.max_health_pct = capped("member_max_health_pct", stats.max_health_pct)
    stats.mana_regen_pct = capped("member_mana_regen_pct", stats.mana_regen_pct)
    stats.heal_amp_pct = capped("member_heal_amp_pct", stats.heal_amp_pct)
    return stats
end

function BondSystem:Apply(active_units)
    self.snapshot = self:BuildSnapshot(active_units)
    self.runtime = {
        arcane_echo_remaining = {},
        hunter_next_mark_time = {},
        emergency_shield_used = false,
    }

    for _, unit in ipairs(self.snapshot.units) do
        unit:RemoveModifierByName("modifier_rpg_bond_stats")
        unit:RemoveModifierByName("modifier_rpg_opening_shield")

        local stats = self:AggregateStatsForUnit(unit)
        if stats.max_health_pct > 0 or stats.mana_regen_pct > 0 or stats.heal_amp_pct > 0 then
            unit:AddNewModifier(unit, nil, "modifier_rpg_bond_stats", {
                max_health_pct = stats.max_health_pct,
                mana_regen_pct = stats.mana_regen_pct,
                heal_amp_pct = stats.heal_amp_pct,
            })
        end

        local caster_bond = self.snapshot.active.caster
        if caster_bond ~= nil and self:UnitHasBond(unit, "caster") then
            self.runtime.arcane_echo_remaining[unit:entindex()] = tonumber(caster_bond.effects.arcane_echo_charges or 0)
        end
    end

    local frontline = self.snapshot.active.frontline
    if frontline ~= nil then
        local shield_pct = tonumber(frontline.effects.opening_backline_shield_pct or 0)
        if shield_pct > 0 then
            for _, unit in ipairs(self.snapshot.units) do
                if self.get_row_tag(unit) == "back_row" then
                    unit:AddNewModifier(unit, nil, "modifier_rpg_opening_shield", {
                        shield_amount = math.floor(unit:GetMaxHealth() * shield_pct / 100),
                        duration = 5,
                    })
                end
            end
        end
    end

    return self.snapshot
end

function BondSystem:GetLowestManaAlly(caster)
    if self.snapshot == nil then return nil end
    local best = nil
    local best_pct = math.huge
    for _, ally in ipairs(self.snapshot.units) do
        if ally:IsAlive() and ally:GetTeamNumber() == caster:GetTeamNumber() then
            local max_mana = math.max(1, ally:GetMaxMana())
            local pct = ally:GetMana() / max_mana
            if pct < best_pct then
                best_pct = pct
                best = ally
            end
        end
    end
    return best
end

-- Call from the project's central ability-executed hook after a cast succeeds.
function BondSystem:OnAbilityExecuted(caster)
    if self.snapshot == nil or not self:UnitHasBond(caster, "caster") then return end
    local remaining = self.runtime.arcane_echo_remaining[caster:entindex()] or 0
    if remaining <= 0 then return end

    local active = self.snapshot.active.caster
    local mana_pct = tonumber(active.effects.arcane_echo_mana_pct or 0)
    local target = self:GetLowestManaAlly(caster)
    if target ~= nil and mana_pct > 0 then
        target:GiveMana(target:GetMaxMana() * mana_pct / 100)
        self.runtime.arcane_echo_remaining[caster:entindex()] = remaining - 1
    end
end

-- Call from modifier event MODIFIER_EVENT_ON_ATTACK_LANDED or a central event proxy.
function BondSystem:OnAttackLanded(attacker, target, current_time)
    if self.snapshot == nil or not self:UnitHasBond(attacker, "hunter") then return end
    current_time = current_time or GameRules:GetGameTime()
    local next_time = self.runtime.hunter_next_mark_time[attacker:entindex()] or 0
    if current_time < next_time then return end

    local effects = self.snapshot.active.hunter.effects
    target:AddNewModifier(attacker, nil, "modifier_rpg_hunt_mark", {
        duration = tonumber(effects.hunt_mark_duration or 4),
        bonus_damage_pct = capped("hunt_mark_damage_pct", tonumber(effects.hunt_mark_damage_pct or 0)),
        mark_team = attacker:GetTeamNumber(),
    })
    self.runtime.hunter_next_mark_time[attacker:entindex()] = current_time + tonumber(effects.hunt_mark_cooldown or 10)
end

-- Call after damage is applied. This is a once-per-battle emergency shield.
function BondSystem:OnUnitDamaged(victim)
    if self.snapshot == nil or self.runtime.emergency_shield_used then return end
    local support = self.snapshot.active.support
    if support == nil then return end

    local shield_pct = tonumber(support.effects.emergency_shield_pct or 0)
    if shield_pct <= 0 or victim:GetHealth() / math.max(1, victim:GetMaxHealth()) > 0.25 then
        return
    end

    victim:AddNewModifier(victim, nil, "modifier_rpg_opening_shield", {
        shield_amount = math.floor(victim:GetMaxHealth() * shield_pct / 100),
        duration = 5,
    })
    self.runtime.emergency_shield_used = true
end

-- Merge this into the project's single damage filter.
function BondSystem:FilterDamage(filter_table)
    if self.snapshot == nil then return true end
    local attacker = EntIndexToHScript(filter_table.entindex_attacker_const or -1)
    local victim = EntIndexToHScript(filter_table.entindex_victim_const or -1)
    if not valid_entity(attacker) or not valid_entity(victim) then return true end

    local bonus_pct = 0
    local mark = victim:FindModifierByName("modifier_rpg_hunt_mark")
    if mark ~= nil and mark.GetMarkTeam ~= nil
        and mark:GetMarkTeam() == attacker:GetTeamNumber()
        and self:UnitHasBond(attacker, "hunter") then
        bonus_pct = bonus_pct + mark:GetBonusDamagePct()
    end

    local controller = self.snapshot.active.controller
    if controller ~= nil and self:UnitHasBond(attacker, "controller") then
        local disabled = (victim.IsStunned ~= nil and victim:IsStunned())
            or (victim.IsRooted ~= nil and victim:IsRooted())
        if disabled then
            bonus_pct = bonus_pct + capped(
                "disabled_target_damage_pct",
                tonumber(controller.effects.disabled_target_damage_pct or 0)
            )
        end
    end

    if bonus_pct > 0 then
        filter_table.damage = tonumber(filter_table.damage or 0) * (1 + bonus_pct / 100)
    end
    return true
end

function BondSystem:GetSnapshotForUI()
    local result = {}
    if self.snapshot == nil then return result end
    for bond_id, active in pairs(self.snapshot.active) do
        result[bond_id] = {
            name = active.name,
            count = active.count,
            threshold = active.threshold,
        }
    end
    return result
end

return BondSystem
