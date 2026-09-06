local InventoryTransfer = require("issue_fixes.inventory_transfer")
local RosterAccess = require("issue_fixes.roster_access")
local DefaultRules = require("issue_fixes.default_rules")
local EnemyRuntime = require("issue_fixes.enemy_runtime")
local LevelUniqueness = require("issue_fixes.level_uniqueness")
local ArenaController = require("issue_fixes.arena_controller")

local IssueFixes = {}
IssueFixes.__index = IssueFixes

local function append_all(destination, source)
    for _, value in ipairs(source or {}) do
        destination[#destination + 1] = value
    end
end

function IssueFixes.new(options)
    options = options or {}
    local game_mode_entity = options.game_mode_entity
        or (GameRules and GameRules:GetGameModeEntity())

    local execute_order = options.execute_order
    if execute_order == nil and options.order_gate ~= nil then
        execute_order = function(order)
            return options.order_gate:Execute(order)
        end
    end

    local instance = setmetatable({
        get_phase = options.get_phase or function() return "PREPARE" end,
        get_player_units = options.get_player_units,
        is_roster_hero = options.is_roster_hero,
        game_mode_entity = game_mode_entity,
        installed = false,
    }, IssueFixes)

    instance.inventory = InventoryTransfer.new({
        get_phase = instance.get_phase,
        is_roster_hero = options.is_roster_hero,
        event_name = options.transfer_event_name,
        on_error = options.on_transfer_error,
    })

    instance.arena = ArenaController.new({
        game_mode_entity = game_mode_entity,
        -- New compact layout uses two 1200×900 preparation zones by default.
        -- Keep the legacy square-size option for callers that need it.
        half_width = options.arena_half_width,
        half_height = options.arena_half_height,
        square_size = options.arena_square_size,
        min_marker = options.arena_min_marker,
        max_marker = options.arena_max_marker,
        center_marker = options.arena_center_marker,
        gate_visual_name = options.gate_visual_name,
        gate_nav_name = options.gate_nav_name,
    })

    instance.enemies = EnemyRuntime.new({
        game_mode_entity = game_mode_entity,
        get_phase = instance.get_phase,
        get_player_units = options.get_player_units,
        bind_tactic_profile = options.bind_tactic_profile,
        has_tactic_order = options.has_tactic_order,
        execute_order = execute_order,
        remove_prepare_modifiers = options.remove_enemy_prepare_modifiers,
    })

    return instance
end

function IssueFixes:Install()
    if self.installed then return end
    self.installed = true

    if LinkLuaModifier ~= nil then
        LinkLuaModifier(
            "modifier_rpg_prepare_bench",
            "modifiers/modifier_rpg_prepare_bench",
            LUA_MODIFIER_MOTION_NONE
        )
    end

    RosterAccess.EnableNativeShop({ enable_easy_buy = true })
    self.inventory:InstallEventListener()
    self.arena:LoadBounds()
    self.arena:InstallThink()
end

function IssueFixes:PrepareRoster(player_id, active_heroes, bench_heroes)
    RosterAccess.PrepareRoster(player_id, active_heroes, bench_heroes)

    local all_units = {}
    append_all(all_units, active_heroes)
    append_all(all_units, bench_heroes)
    self.arena:StartPrepare(all_units)
end

function IssueFixes:RegisterCurrentStage(stage_entries, spawned_enemy_units)
    self.enemies:RegisterStage(stage_entries, spawned_enemy_units)
end

function IssueFixes:OnBattleStarted(player_units, enemy_units)
    local all_units = {}
    append_all(all_units, player_units)
    append_all(all_units, enemy_units)

    self.arena:StartFight(all_units)
    self.enemies.enemy_units = enemy_units or self.enemies.enemy_units
    self.enemies:Start(player_units, self.arena:GetCenter())
end

function IssueFixes:OnBattleEnded(all_units)
    self.enemies:Stop()
    self.arena:StartPrepare(all_units or {})
end

function IssueFixes:ValidatePrepareOrder(filter_table)
    return self.arena:ValidateOrder(filter_table)
end

function IssueFixes:DefaultRules(saved_rules)
    return DefaultRules.Normalize(saved_rules)
end

function IssueFixes:ApplyStageOneTwoFix(levels)
    return LevelUniqueness.ApplyStageOneTwoFix(levels)
end

function IssueFixes:ValidateLevelUniqueness(levels, max_stage)
    return LevelUniqueness.ValidateAll(levels, max_stage)
end

function IssueFixes:TransferWarehouseItem(
    player_id,
    source_unit,
    source_item,
    target_hero
)
    return self.inventory:Transfer(
        player_id,
        source_unit,
        source_item,
        target_hero
    )
end

return IssueFixes
