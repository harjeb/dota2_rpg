local package_root = assert(arg[1], "package root required")
local vscripts = package_root .. "/overlay/game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = vscripts .. "/?.lua;" .. vscripts .. "/?/init.lua;" .. package.path

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local next_index = 100
local entities = {}
local function allocate(entity)
    entity.valid = true
    entity.index = next_index
    next_index = next_index + 1
    entities[entity.index] = entity
    return entity
end

function IsValidEntity(entity)
    return entity ~= nil and entity.valid ~= false
end

function EntIndexToHScript(index)
    return entities[tonumber(index)]
end

DOTA_UNIT_ORDER_MOVE_TO_POSITION = 1
DOTA_UNIT_ORDER_ATTACK_MOVE = 3
DOTA_UNIT_ORDER_ATTACK_TARGET = 4
DOTA_UNIT_ORDER_TRAIN_ABILITY = 11
DOTA_UNIT_ORDER_DROP_ITEM = 12
DOTA_UNIT_ORDER_GIVE_ITEM = 13
DOTA_UNIT_ORDER_PICKUP_ITEM = 14
DOTA_UNIT_ORDER_PURCHASE_ITEM = 16
DOTA_UNIT_ORDER_SELL_ITEM = 17
DOTA_UNIT_ORDER_DISASSEMBLE_ITEM = 18
DOTA_UNIT_ORDER_MOVE_ITEM = 19
DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH = 25
DOTA_UNIT_ORDER_MOVE_TO_DIRECTION = 28
DOTA_UNIT_ORDER_PATROL = 29
DOTA_UNIT_ORDER_SET_ITEM_COMBINE_LOCK = 32
DOTA_UNIT_ORDER_MOVE_RELATIVE = 39
DOTA_UNIT_ORDER_CONSUME_ITEM = 41
DOTA_UNIT_ORDER_SET_ITEM_MARK_FOR_SELL = 42
DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3

function Vector(x, y, z)
    return { x = x, y = y, z = z }
end

local Item = {}
Item.__index = Item
function Item.new(name)
    return allocate(setmetatable({ name = name, charges = 0, secondary = 0 }, Item))
end
function Item:IsNull() return not self.valid end
function Item:entindex() return self.index end
function Item:GetAbilityName() return self.name end
function Item:GetName() return self.name end
function Item:GetCurrentCharges() return self.charges end
function Item:GetSecondaryCharges() return self.secondary end
function Item:SetPurchaser(hero) self.purchaser = hero end
function Item:GetContainer() return nil end

local Unit = {}
Unit.__index = Unit
function Unit.new(team, position)
    return allocate(setmetatable({
        team = team or DOTA_TEAM_GOODGUYS,
        position = position or Vector(0, 0, 0),
        inventory = {},
        alive = true,
        modifiers = {},
    }, Unit))
end
function Unit:IsNull() return not self.valid end
function Unit:entindex() return self.index end
function Unit:GetItemInSlot(slot) return self.inventory[slot] end
function Unit:RemoveItem(item)
    for slot = 0, 15 do
        if self.inventory[slot] == item then
            self.inventory[slot] = nil
            return
        end
    end
end
function Unit:AddItem(item)
    for slot = 0, 15 do
        if self.inventory[slot] == nil then
            self.inventory[slot] = item
            return item
        end
    end
    return nil
end
function Unit:GetTeamNumber() return self.team end
function Unit:GetAbsOrigin() return self.position end
function Unit:IsAlive() return self.alive end
function Unit:IsCourier() return false end
function Unit:IsHero() return true end
function Unit:GetUnitName() return self.unit_name or "" end
function Unit:IsIdle() return true end
function Unit:IsChanneling() return false end
function Unit:IsStunned() return false end
function Unit:IsCommandRestricted() return false end
function Unit:GetCurrentActiveAbility() return nil end
function Unit:GetAttackTarget() return self.attack_target end
function Unit:SetIdleAcquire(value) self.idle_acquire = value end
function Unit:SetAcquisitionRange(value) self.acquisition_range = value end
function Unit:SetForceAttackTarget(value) self.force_target = value end
function Unit:RemoveModifierByName(name) self.modifiers[name] = nil end
function Unit:Stop() self.stopped = true end

-- Issue 1: move the exact item handle and preserve it on full-inventory failure.
do
    local InventoryTransfer = require("issue_fixes.inventory_transfer")
    local source = Unit.new()
    local target = Unit.new()
    local item = Item.new("item_blink")
    source.inventory[0] = item

    local service = InventoryTransfer.new({
        get_phase = function() return "PREPARE" end,
        is_roster_hero = function() return true end,
    })
    local ok = service:Transfer(0, source, item, target)
    assert_equal(ok, true, "inventory transfer success")
    assert_equal(source.inventory[0], nil, "source item removed")
    assert_equal(target.inventory[0], item, "same handle attached to target")

    local second = Item.new("item_force_staff")
    source.inventory[0] = second
    for slot = 0, 8 do target.inventory[slot] = Item.new("full_" .. slot) end
    local full_ok = service:Transfer(0, source, second, target)
    assert_equal(full_ok, false, "full inventory rejected")
    assert_equal(source.inventory[0], second, "rejected item remains in source")
end

-- Issue 3: exactly one default rule, no forced padding.
do
    local DefaultRules = require("issue_fixes.default_rules")
    local rules = DefaultRules.Normalize(nil)
    assert_equal(#rules, 1, "single default rule")
    assert_equal(rules[1].action.kind, "attack", "default action")

    local authored = {
        { action = { kind = "cast", name = "test" } },
        { action = { kind = "attack" } },
        { placeholder = true },
    }
    local normalized = DefaultRules.Normalize(authored)
    assert_equal(#normalized, 2, "preserve authored rules without padding")
end

-- Issue 5: stage 1 and 2 duplicate composition is repaired only in stage 2.
do
    local LevelUniqueness = require("issue_fixes.level_uniqueness")
    local levels = {
        [1] = { enemies = { { unit = "npc_dota_neutral_kobold", count = 3 } } },
        [2] = { enemies = { { unit = "npc_dota_neutral_kobold", count = 3 } }, gold = 123 },
    }
    local changed = LevelUniqueness.ApplyStageOneTwoFix(levels)
    assert_equal(changed, true, "duplicate stage fixed")
    assert(levels[2].gold == 123, "stage reward metadata preserved")
    assert(
        LevelUniqueness.CompositionSignature(levels[1])
            ~= LevelUniqueness.CompositionSignature(levels[2]),
        "stage signatures must differ"
    )
    local valid, errors = LevelUniqueness.ValidateAll(levels, 2)
    assert_equal(valid, true, table.concat(errors, "; "))
end

-- Issues 4/6: all actual current-stage units bind and receive initial orders.
do
    local EnemyRuntime = require("issue_fixes.enemy_runtime")
    local orders = {}
    local binds = {}
    local players = { Unit.new(DOTA_TEAM_GOODGUYS, Vector(-500, 0, 0)) }
    local enemies = {
        Unit.new(DOTA_TEAM_BADGUYS, Vector(500, 0, 0)),
        Unit.new(DOTA_TEAM_BADGUYS, Vector(600, 0, 0)),
        Unit.new(DOTA_TEAM_BADGUYS, Vector(700, 0, 0)),
        Unit.new(DOTA_TEAM_BADGUYS, Vector(800, 0, 0)),
    }
    for _, unit in ipairs(enemies) do unit.unit_name = "centaur" end
    local runtime = EnemyRuntime.new({
        get_phase = function() return "FIGHT" end,
        execute_order = function(order) orders[#orders + 1] = order; return true end,
        bind_tactic_profile = function(unit, profile)
            binds[#binds + 1] = { unit = unit, profile = profile }
        end,
    })
    runtime:RegisterStage({ { unit = "centaur", count = 4, ai_profile = "attack_nearest" } }, enemies)
    runtime:Start(players, Vector(0, 0, 0))
    assert_equal(#binds, 4, "bind every current stage enemy")
    assert_equal(#orders, 4, "order every current stage enemy")
    assert_equal(enemies[4].idle_acquire, true, "fourth enemy activated")
end

-- Issues 2/4/10: preparation UI orders pass; player battle orders block; AI passes.
do
    package.loaded["tactics.order_filter"] = nil
    local Filters = require("tactics.order_filter")
    local battle_unit = Unit.new()
    local phase = "PREPARE"
    local filter = Filters.OrderFilter.new({
        get_phase = function() return phase end,
        is_battle_unit = function(unit) return unit == battle_unit end,
        validate_prepare_order = function() return true end,
    })
    local base = { units = { ["0"] = battle_unit:entindex() }, issuer_player_id_const = 0 }

    base.order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY
    assert_equal(filter:Filter(base), true, "train ability allowed in prepare")
    base.order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM
    assert_equal(filter:Filter(base), true, "purchase allowed in prepare")
    base.order_type = DOTA_UNIT_ORDER_ATTACK_TARGET
    base.issuer_player_id_const = -1
    assert_equal(filter:Filter(base), false, "AI order blocked in prepare")

    phase = "FIGHT"
    base.order_type = DOTA_UNIT_ORDER_ATTACK_TARGET
    base.issuer_player_id_const = 0
    assert_equal(filter:Filter(base), false, "player order blocked in fight")
    base.issuer_player_id_const = -1
    assert_equal(filter:Filter(base), true, "AI order allowed in fight")

    local purchase_without_units = {
        units = {},
        issuer_player_id_const = 0,
        order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM,
    }
    assert_equal(
        filter:Filter(purchase_without_units),
        false,
        "purchase without unit list blocked in fight"
    )
end

-- Issue 9: fallback arena is compact 2400x900 and movement is clamped.
do
    local ArenaController = require("issue_fixes.arena_controller")
    local arena = ArenaController.new()
    arena:LoadBounds()
    assert_equal(arena.min.x, -1200, "compact arena min x")
    assert_equal(arena.max.x, 1200, "compact arena max x")
    assert_equal(arena.min.y, -450, "compact arena min y")
    assert_equal(arena.max.y, 450, "compact arena max y")

    local unit = Unit.new(DOTA_TEAM_GOODGUYS)
    local order = {
        order_type = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        units = { ["0"] = unit:entindex() },
        position_x = 9999,
        position_y = 9999,
        position_z = 0,
    }
    arena:ValidateOrder(order)
    assert(order.position_x <= -72, "prepare player stays in compact left zone")
    assert(order.position_y <= 402, "movement clamped inside compact y boundary")

    -- Existing external callers that explicitly asked for the former square
    -- layout retain its original dimensions.
    local legacy = ArenaController.new({ square_size = 1600 })
    legacy:LoadBounds()
    assert_equal(legacy.min.x, -1600, "legacy arena min x")
    assert_equal(legacy.max.x, 1600, "legacy arena max x")
    assert_equal(legacy.min.y, -800, "legacy arena min y")
    assert_equal(legacy.max.y, 800, "legacy arena max y")
end

-- Current-game bootstrap: use battleManager.teamHeroes instead of broad scans so
-- compact arena enforcement never pulls the player wisp or bench into combat.
do
    local Bootstrap = require("issue_fixes.bootstrap")
    local game_mode_entity = {
        SetContextThink = function(self, name, callback, delay)
            self.thinks = self.thinks or {}
            self.thinks[name] = { callback = callback, delay = delay }
        end,
    }
    GameRules = {
        GetGameModeEntity = function() return game_mode_entity end,
        SetUseUniversalShopMode = function() end,
    }

    local function battle_unit(team, x)
        return {
            valid = true,
            team = team,
            position = Vector(x, 0, 0),
            IsNull = function() return false end,
            IsAlive = function() return true end,
            GetTeamNumber = function(self) return self.team end,
            GetAbsOrigin = function(self) return self.position end,
            RemoveModifierByName = function() end,
            SetIdleAcquire = function() end,
            SetAcquisitionRange = function() end,
            SetForceAttackTarget = function() end,
            IsIdle = function() return true end,
        }
    end

    local fielded = battle_unit(DOTA_TEAM_GOODGUYS, -700)
    local enemy = battle_unit(DOTA_TEAM_BADGUYS, 700)
    local benched = battle_unit(DOTA_TEAM_GOODGUYS, -2300)
    local Game = {}
    function Game:InitGameMode()
        self.battleManager = {
            teamHeroes = {
                [DOTA_TEAM_GOODGUYS] = { fielded },
                [DOTA_TEAM_BADGUYS] = { enemy },
            },
        }
        self.phase = "setup"
    end
    function Game:RespawnPlayerRoster() self.respawned = true end
    function Game:SpawnLevelEnemies() self.spawned = true end
    function Game:OnStartBattle() self.phase = "fight" end
    function Game:EndBattle() self.phase = "settle" end

    Bootstrap.Install(Game)
    local game = setmetatable({ benchUnits = { benched } }, { __index = Game })
    game:InitGameMode()
    game:RespawnPlayerRoster()
    assert_equal(game.issueFixes.arena.phase, "PREPARE", "roster enters prepare")
    assert_equal(#game.issueFixes.arena.units, 1, "only fielded hero registered in prepare")
    assert_equal(game.issueFixes.arena.units[1], fielded, "fielded hero retained in prepare")

    game:OnStartBattle()
    assert_equal(game.issueFixes.arena.phase, "FIGHT", "battle enters fight")
    assert_equal(#game.issueFixes.arena.units, 2, "only real battle teams registered in fight")
    assert_equal(game.issueFixes.arena.units[1], fielded, "fielded hero retained in fight")
    assert_equal(game.issueFixes.arena.units[2], enemy, "enemy retained in fight")

    game:EndBattle()
    assert_equal(game.issueFixes.arena.phase, "PREPARE", "battle end restores prepare")
    assert_equal(#game.issueFixes.arena.units, 2, "battle end excludes bench and commander")
end

-- The compatibility bootstrap preserves the whole original item handle for an
-- unclaimed merged purchase. Older host code otherwise split its new charge
-- before the first recipient ever owned the stack.
do
    local Bootstrap = require("issue_fixes.bootstrap")
    local PurchaseGame = {}
    function PurchaseGame:InitGameMode() end
    function PurchaseGame:FindNewPurchasedItem()
        return { item_id = "unclaimed-stack", changed = true }
    end

    Bootstrap.Install(PurchaseGame)
    local purchase_game = setmetatable({ nativePurchaseClaimedIds = {} }, {
        __index = PurchaseGame,
    })
    assert_equal(
        purchase_game:FindNewPurchasedItem().changed,
        false,
        "unclaimed merged stack routes as an exact item"
    )
    purchase_game.nativePurchaseClaimedIds["unclaimed-stack"] = "npc_dota_hero_axe"
    assert_equal(
        purchase_game:FindNewPurchasedItem().changed,
        true,
        "already claimed stack retains split protection"
    )
end

print("runtime tests passed")
