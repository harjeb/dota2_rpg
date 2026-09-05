-- Illustrative addon_game_mode.lua integration. Merge with the project's BattleManager.

LinkLuaModifier("modifier_rpg_bond_stats", "modifiers/modifier_rpg_bond_stats", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_opening_shield", "modifiers/modifier_rpg_opening_shield", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_hunt_mark", "modifiers/modifier_rpg_hunt_mark", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_affix_blood_frenzy", "modifiers/modifier_rpg_affix_blood_frenzy", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_affix_thick_hide", "modifiers/modifier_rpg_affix_thick_hide", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_affix_spell_shell", "modifiers/modifier_rpg_affix_spell_shell", LUA_MODIFIER_MOTION_NONE)

local RunState = require("battle/run_state")
local Progression = require("progression/progression")
local Filters = require("tactics/order_filter")
local ActionAdapter = require("tactics/action_adapter")
local TargetSelector = require("tactics/target_selector")
local TacticEngine = require("tactics/tactic_engine")
local RuleService = require("tactics/rule_service")
local ShopService = require("shop/shop_service")
local BondSystem = require("bonds/bond_system")
local AffixSystem = require("affixes/affix_system")
local BlinkAdapter = require("tactics/adapters/blink_adapter")
local HeroCompatibility = require("data/hero_compatibility")

RPGGameMode = class({})

function Activate()
    GameRules.RPGGameMode = RPGGameMode()
    GameRules.RPGGameMode:InitGameMode()
end

function RPGGameMode:InitGameMode()
    self.state = RunState.new()
    local game_mode_entity = GameRules:GetGameModeEntity()

    Progression.Validate()
    Progression.InstallCustomLevels(game_mode_entity)

    self.filters = Filters.OrderFilter.new({
        get_phase = function() return self.state.phase end,
        is_battle_unit = function(unit) return self:IsBattleUnit(unit) end,
        validate_prepare_order = function(filter_table) return self:ValidatePrepareOrder(filter_table) end,
    })
    self.filters:Install(game_mode_entity)

    self.action_adapter = ActionAdapter.new(self.filters.gate)
    self.action_adapter:Register("blink_to_target", BlinkAdapter.new())

    self.selector = TargetSelector.new()
    self.tactics = TacticEngine.new({
        order_gate = self.filters.gate,
        actions = self.action_adapter,
        selector = self.selector,
        get_phase = function() return self.state.phase end,
        get_battle_units = function() return self.state.battle_units end,
        get_rules = function(unit) return self.state.rules[unit:entindex()] or {} end,
        build_context = function(unit) return self:BuildTacticContext(unit) end,
        on_debug = function(unit, event, detail) self:OnTacticDebug(unit, event, detail) end,
    })
    self.tactics:Start(game_mode_entity)

    self.shop = ShopService.new({
        get_phase = function() return self.state.phase end,
        is_roster_hero = function(player_id, hero) return self:IsRosterHero(player_id, hero) end,
        state = self.state,
    })
    self.shop:InstallEventListeners()

    self.rules = RuleService.new({
        get_phase = function() return self.state.phase end,
        is_roster_hero = function(player_id, hero) return self:IsRosterHero(player_id, hero) end,
        is_action_allowed = function(player_id, hero, action) return self:IsActionAllowed(player_id, hero, action) end,
        state = self.state,
    })
    self.rules:InstallEventListener()

    self.bonds = BondSystem.new({
        get_tags = function(unit) return self:GetTags(unit) end,
        get_row_tag = function(unit) return self.state.row_tags[unit:entindex()] end,
    })

    self.affixes = AffixSystem.new({
        get_tags = function(unit) return self:GetTags(unit) end,
        state = self.state,
        affix_version = "v1",
    })

    -- Dota permits one damage filter. Chain every subsystem here.
    game_mode_entity:SetDamageFilter(Dynamic_Wrap(RPGGameMode, "DamageFilter"), self)
end

function RPGGameMode:IsBattleUnit(unit)
    for _, candidate in ipairs(self.state.battle_units) do
        if candidate == unit then return true end
    end
    return false
end

function RPGGameMode:IsRosterHero(player_id, hero)
    for _, candidate in ipairs(self.state.roster[player_id] or {}) do
        if candidate == hero then return true end
    end
    return false
end

function RPGGameMode:GetTags(unit)
    return self.state.unit_tags[unit:entindex()] or {}
end

function RPGGameMode:IsActionAllowed(_player_id, hero, action)
    if action.kind == "attack" or action.kind == "move" or action.kind == "wait" then
        return true
    end

    local compatibility = HeroCompatibility[hero:GetUnitName()]
    if compatibility == nil or compatibility.status == "blocked" then
        return false
    end

    local action_data = compatibility.actions[action.logical_id]
    if action_data == nil then
        return action.kind == "item" -- Item whitelist is checked separately by the shop/action catalog.
    end

    action.name = action_data.name
    action.cast_type = action_data.cast_type
    action.target_team = action_data.target_team
    action.aoe_radius = action_data.aoe_radius
    return true
end

function RPGGameMode:BuildTacticContext(caster)
    local allies = {}
    local enemies = {}
    for _, unit in ipairs(self.state.battle_units) do
        if unit ~= nil and not unit:IsNull() and unit:IsAlive() then
            if unit:GetTeamNumber() == caster:GetTeamNumber() then
                table.insert(allies, unit)
            else
                table.insert(enemies, unit)
            end
        end
    end

    local function units_around(origin_unit, radius, same_team)
        local count = 0
        for _, unit in ipairs(self.state.battle_units) do
            if unit:IsAlive() then
                local matches_team = same_team
                    and unit:GetTeamNumber() == origin_unit:GetTeamNumber()
                    or (not same_team and unit:GetTeamNumber() ~= origin_unit:GetTeamNumber())
                if matches_team and (unit:GetAbsOrigin() - origin_unit:GetAbsOrigin()):Length2D() <= radius then
                    count = count + 1
                end
            end
        end
        return count
    end

    return {
        elapsed = GameRules:GetGameTime() - (self.battle_start_time or GameRules:GetGameTime()),
        boss_phase = self.current_boss_phase or "phase_1",
        alive_ally_count = #allies,
        alive_enemy_count = #enemies,
        dead_ally_count = self.dead_ally_count or 0,
        get_tags = function(unit) return self:GetTags(unit) end,
        has_affix = function(unit, affix_id) return self.affixes:HasAffix(unit, affix_id) end,
        get_candidates = function(_source, action_spec, target_config)
            local team = target_config.team or action_spec.target_team or "enemy"
            if team == "self" then return { caster } end
            return team == "ally" and allies or enemies
        end,
        count_allies_around = function(unit, radius) return units_around(unit, radius, true) end,
        count_enemies_around = function(unit, radius) return units_around(unit, radius, false) end,
        resolve_action_name = function(unit, logical_id)
            local compatibility = HeroCompatibility[unit:GetUnitName()]
            local action = compatibility and compatibility.actions[logical_id]
            return action and action.name or logical_id
        end,
        record_action_order = function(unit, logical_id, target)
            self:OnActionOrderIssued(unit, logical_id, target)
        end,
    }
end

function RPGGameMode:ValidatePrepareOrder(_filter_table)
    -- Replace with checks that movement stays inside the player's placement grid.
    return true
end

function RPGGameMode:StartFight(player_id, player_units, enemy_units)
    self.state.battle_units = {}
    for _, unit in ipairs(player_units) do table.insert(self.state.battle_units, unit) end
    for _, unit in ipairs(enemy_units) do table.insert(self.state.battle_units, unit) end

    self.bonds:Apply(player_units)
    self.affixes:ApplyStage(self.state.stage, enemy_units)
    self.battle_start_time = GameRules:GetGameTime()
    self.state:SetPhase("FIGHT")
end

function RPGGameMode:DamageFilter(filter_table)
    if not self.affixes:FilterDamage(filter_table) then return false end
    if not self.bonds:FilterDamage(filter_table) then return false end
    return true
end

function RPGGameMode:OnTacticDebug(_unit, _event, _detail)
    -- Feed a ring buffer; do not broadcast every tick to Panorama in production.
end

function RPGGameMode:OnActionOrderIssued(_unit, _logical_id, _target)
    -- Count successful casts from an ability-executed hook, not merely from this order hook.
end
