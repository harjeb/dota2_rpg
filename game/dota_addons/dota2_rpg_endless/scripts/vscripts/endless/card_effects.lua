-- Supported, complete BASIC_CARDS_V1 effects only. This table is the equip allowlist.
local Effects = { definitions = {} }
local MODIFIER = "modifier_endless_card_stats"
if LinkLuaModifier then LinkLuaModifier(MODIFIER, "modifiers/" .. MODIFIER, LUA_MODIFIER_MOTION_NONE) end
local function define(id, kind, target, stats, trigger, duration)
    local effects = {}
    for stat, values in pairs(stats) do effects[#effects + 1] = {type = "stat", stat = stat, values = values} end
    Effects.definitions[id] = {type = kind, target = target, effects = effects, trigger = trigger, duration = duration}
end
define("E-g8", "buff", "friendly", {spell_amp = {4,7,10}})
define("C-g1", "buff", "friendly", {attack_speed = {20,35,55}})
define("C-g5", "buff", "friendly", {cooldown = {10,16,24}})
define("D-g1", "buff", "friendly", {move_speed = {8,13,20}, status_resistance = {10,16,24}})
define("D-g2", "buff", "friendly", {health_regen_pct = {0.4,0.7,1.1}})
define("A-g1", "buff", "friendly", {health_regen = {6,10,15}, missing_health_regen = {14,25,35}})
define("W-g1", "buff", "friendly", {attack_damage = {20,35,55}})
define("W-g5", "buff", "friendly", {base_damage_pct = {12,20,30}})
define("C-c1", "consumable", "friendly", {base_damage_pct = {40,60,80}}, {type="time", first=5, interval=12}, 8)
define("D-c1", "consumable", "friendly", {health_regen_pct = {2,3,4.5}}, {type="hero_health_below", threshold=0.7, cooldown=12}, 10)
define("W-c4", "consumable", "friendly", {base_damage_pct = {25,40,60}, move_speed = {15,25,35}}, {type="time", first=8, interval=14}, 10)
define("E-f1", "field", "friendly", {mana_regen = {8,16,29}})
define("E-f2", "field", "enemy", {move_speed = {-10,-18,-28}})
define("C-f1", "field", "friendly", {move_speed = {15,24,35}})
define("C-f2", "field", "enemy", {attack_speed = {-16,-32,-50}})
define("C-f3", "field", "friendly", {incoming_damage = {-4,-7,-12}})
define("A-f4", "field", "enemy", {armor = {-7,-13,-20}})

local function valid(unit) return unit ~= nil and (not unit.IsNull or not unit:IsNull()) end
local function alive(unit) return valid(unit) and (not unit.IsAlive or unit:IsAlive()) end
local function now(game)
    if GameRules and GameRules.GetGameTime then return GameRules:GetGameTime() end
    return tonumber(game.time) or 0
end
local function legal(game, unit)
    return valid(unit) and unit ~= game.placeholderHero and unit ~= game.commander
        and not (unit.HasModifier and (unit:HasModifier("modifier_rpg_prepare_bench") or unit:HasModifier("modifier_rpg_commander_disarmed")))
        and not (unit.IsOther and unit:IsOther()) and not (unit.IsBuilding and unit:IsBuilding())
end
local function units(game, state)
    local result, seen = {}, {}
    local function add(unit)
        if legal(game, unit) and not seen[unit] then seen[unit] = true; result[#result+1] = unit end
    end
    -- The radius is FIND_UNITS_EVERYWHERE, never a carrier's location/range.
    if FindUnitsInRadius then
        local flags = (DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 0) + (DOTA_UNIT_TARGET_FLAG_INVULNERABLE or 0) + (DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD or 0)
        for _, unit in pairs(FindUnitsInRadius(state.team, Vector(0,0,0), nil, FIND_UNITS_EVERYWHERE or -1,
            DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, flags, FIND_ANY_ORDER, false) or {}) do add(unit) end
    end
    for _, roster in pairs((game.battleManager or {}).teamHeroes or {}) do
        for _, unit in pairs(roster) do add(unit) end
    end
    for _, unit in pairs(game.spawnedSummons or {}) do add(unit) end
    return result
end
local function lowHero(game, state, threshold)
    -- Trigger only on deployed real heroes, never summons/illusions or the carrier alone.
    local roster = ((game.battleManager or {}).teamHeroes or {})[state.team] or {}
    for _, unit in pairs(roster) do
        if legal(game, unit) and alive(unit) and unit.IsRealHero and unit:IsRealHero()
            and not (unit.IsIllusion and unit:IsIllusion()) and not unit.endlessRebirthForm
            and unit:GetMaxHealth() > 0 and unit:GetHealth() / unit:GetMaxHealth() < threshold then return true end
    end
    return false
end
function Effects.Stop(game)
    local state = game.endlessCardCombat
    if not state then return end
    for unit in pairs(state.units) do
        if valid(unit) and unit.RemoveModifierByName then unit:RemoveModifierByName(MODIFIER) end
    end
    game.endlessCardCombat = nil
end
function Effects.Start(game, snapshot)
    Effects.Stop(game)
    local start = now(game)
    local state = {cards={}, units={}, started_at=start, team=game.endlessCardTeam or DOTA_TEAM_GOODGUYS or 2}
    local seen = {}
    for _, entry in ipairs(snapshot or {}) do
        local def, level = Effects.definitions[entry.id], tonumber(entry.load)
        if def and level and level >= 1 and level <= 3 and level == math.floor(level) and not seen[entry.id] then
            seen[entry.id] = true
            state.cards[#state.cards+1] = {id=entry.id, load=level,
                remaining=def.type == "consumable" and level or nil,
                next_trigger=def.trigger and (start + (def.trigger.first or 0)) or nil, active_until=nil}
        end
    end
    game.endlessCardCombat = state
    Effects.Tick(game)
    return state
end
function Effects.Tick(game)
    local state = game.endlessCardCombat
    if not state then return end
    local time = now(game)
    local totals = {friendly={}, enemy={}}
    for _, card in ipairs(state.cards) do
        local def = Effects.definitions[card.id]
        if card.remaining and card.remaining > 0 and time >= card.next_trigger then
            local trigger = def.trigger
            if trigger.type == "time" or lowHero(game, state, trigger.threshold) then
                card.remaining = card.remaining - 1
                card.active_until = time + def.duration
                -- No burst replay after a stalled think; keep the original timed cadence.
                if trigger.type == "time" then
                    card.next_trigger = card.next_trigger + (math.floor((time-card.next_trigger)/trigger.interval)+1)*trigger.interval
                else card.next_trigger = time + trigger.cooldown end
            end
        end
        if def.type ~= "consumable" or (card.active_until and time < card.active_until) then
            for _, effect in ipairs(def.effects) do
                local stats = totals[def.target]
                stats[effect.stat] = (stats[effect.stat] or 0) + effect.values[card.load]
            end
        end
    end
    local present = {}
    for _, unit in ipairs(units(game, state)) do
        present[unit] = true
        local stats = totals[unit:GetTeamNumber() == state.team and "friendly" or "enemy"]
        if next(stats) and unit.AddNewModifier then
            -- One non-duplicating modifier, including inherited illusion modifiers.
            local modifier = unit.FindModifierByName and unit:FindModifierByName(MODIFIER)
            if not modifier then modifier = unit:AddNewModifier(nil, nil, MODIFIER, {}) end
            if modifier and modifier.SetStats then modifier:SetStats(stats) end
            state.units[unit] = true
        elseif state.units[unit] and unit.RemoveModifierByName then
            unit:RemoveModifierByName(MODIFIER); state.units[unit] = nil
        end
    end
    for unit in pairs(state.units) do
        if not present[unit] then
            if valid(unit) and unit.RemoveModifierByName then unit:RemoveModifierByName(MODIFIER) end
            state.units[unit] = nil
        end
    end
end
return Effects
