local package_root = assert(arg[1], "package root required")
local live_vscripts = package_root .. "/../game/dota_addons/dota2_rpg/scripts/vscripts"
local vscripts = arg[2] == "live" and live_vscripts
    or package_root .. "/overlay/game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = vscripts .. "/?.lua;" .. vscripts .. "/?/init.lua;"
    .. live_vscripts .. "/?.lua;" .. package.path

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
function Unit:TakeItem(item)
    for slot = 0, 15 do
        if self.inventory[slot] == item then
            self.inventory[slot] = nil
            return item
        end
    end
end
-- Match Dota: RemoveItem destroys; TakeItem only detaches the original entity.
function Unit:RemoveItem(item)
    self:TakeItem(item)
    item.valid = false
end
function Unit:AddItem(item)
    assert(IsValidEntity(item), "cannot attach a deleted native item")
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

-- Native TakeItem detaches; rejected attachments must preserve the original item,
-- including when the engine routes it to native stash slots or drops it instead.
do
    local Transfer = require("issue_fixes.inventory_transfer")
    local function fixture()
        local source, target = Unit.new(), Unit.new()
        local item = Item.new("item_wraith_band")
        item.charges, item.secondary, item.cooldown, item.purchaser = 3, 2, 7, source
        source.inventory[14] = item
        return Transfer.new(), source, target, item
    end
    local function retained(item, purchaser)
        assert(item.valid, "native item must remain alive")
        assert_equal(item.charges, 3, "charges preserved")
        assert_equal(item.secondary, 2, "secondary charges preserved")
        assert_equal(item.cooldown, 7, "cooldown preserved")
        assert_equal(item.purchaser, purchaser, "purchaser preserved")
    end
    local function dropped(item)
        local container = allocate({})
        function container:IsNull() return not self.valid end
        function container:GetContainedItem() return item end
        function container:RemoveSelf()
            self.valid, item.valid = false, false -- destructive populated container
            error("transfer must never remove a populated container")
        end
        item.GetContainer = function() return container end
        return container
    end

    local service, source, target, item = fixture()
    for slot = 0, 5 do target.inventory[slot] = Item.new("full_active_" .. slot) end
    assert_equal(service:Transfer(0, source, item, target), true, "native stash to backpack")
    assert_equal(target.inventory[6], item, "backpack holds exact source item")
    retained(item, source)
    assert_equal(service:Transfer(0, source, item, target), false, "stale repeated click rejected")
    assert_equal(target.inventory[6], item, "stale click does not detach recipient item")

    for _, mode in ipairs({ "missing", "no_op", "throw_before", "destroy" }) do
        service, source, target, item = fixture()
        source.TakeItem = mode == "missing" and false or function(self, value)
            if mode == "throw_before" then error("detach rejected") end
            if mode == "destroy" then Unit.TakeItem(self, value); value.valid = false end
        end
        local additions = 0
        target.AddItem = function() additions = additions + 1 end
        assert_equal(service:Transfer(0, source, item, target), false, mode .. " detach rejected")
        assert_equal(additions, 0, mode .. " cannot attach an unverified handle")
        if mode ~= "destroy" then
            assert_equal(source.inventory[14], item, mode .. " preserves source")
            retained(item, source)
        end
    end

    service, source, target, item = fixture()
    source.TakeItem = function(self, value) Unit.TakeItem(self, value); error("after detach") end
    assert_equal(service:Transfer(0, source, item, target), true, "post-detach exception accepted")
    retained(item, source)

    service, source, target, item = fixture()
    target.AddItem = function(self, value) self.inventory[14] = value end
    local ok, code = service:Transfer(0, source, item, target)
    assert_equal(ok, false, "target native stash attachment rolled back")
    assert_equal(code, "target_rejected", "rollback reported")
    assert_equal(target.inventory[14], nil, "target stash safely detached")
    assert_equal(source.inventory[0], item, "same item returned to warehouse")
    retained(item, source)

    service, source, target, item = fixture()
    target.AddItem = function(self, value) self.inventory[14] = value end
    target.TakeItem = function() error("rollback detach rejected") end
    ok, code = service:Transfer(0, source, item, target)
    assert_equal(code, "target_retained", "failed rollback leaves target ownership intact")
    assert_equal(target.inventory[14], item, "item retained in target stash")
    retained(item, source)

    service, source, target, item = fixture()
    local container
    target.AddItem = function(_, value) container = dropped(value) end
    ok, code = service:Transfer(0, source, item, target)
    assert_equal(code, "preserved_on_ground", "native ground fallback reported")
    assert(container.valid and container:GetContainedItem() == item, "populated drop retained")
    retained(item, source)

    service, source, target, item = fixture()
    target.AddItem = function() error("target rejected") end
    source.AddItem = function() error("rollback rejected") end
    local oldCreate = CreateItemOnPositionSync
    CreateItemOnPositionSync = function(position, value)
        assert_equal(position, source.position, "fallback at warehouse origin")
        assert_equal(value, item, "fallback uses exact original entity")
        return dropped(value)
    end
    ok, code = service:Transfer(0, source, item, target)
    CreateItemOnPositionSync = oldCreate
    assert_equal(code, "preserved_on_ground", "detached item safely dropped")
    retained(item, source)
end

-- Without a hero's learned abilities, defaults still contain one fallback attack.
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
    assert_equal(arena.min.y, -675, "expanded arena min y")
    assert_equal(arena.max.y, 675, "expanded arena max y")

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
    assert(order.position_y <= 627, "movement clamped inside expanded y boundary")

    -- Existing external callers that explicitly asked for the former square
    -- layout retain its original dimensions.
    local legacy = ArenaController.new({ square_size = 1600 })
    legacy:LoadBounds()
    assert_equal(legacy.min.x, -1600, "legacy arena min x")
    assert_equal(legacy.max.x, 1600, "legacy arena max x")
    assert_equal(legacy.min.y, -800, "legacy arena min y")
    assert_equal(legacy.max.y, 800, "legacy arena max y")

    -- Legacy compiled maps can still contain the obsolete middle brush.
    -- Preparation must not turn it back into a solid/ground-height obstruction.
    local fired = {}
    DoEntFire = function(target, input, value, delay, activator, caller)
        fired[#fired + 1] = {
            target = target,
            input = input,
            value = value,
            delay = delay,
            activator = activator,
            caller = caller,
        }
    end
    arena:OpenMiddleGate()
    arena:CloseMiddleGate()
    DoEntFire = nil
    local expectedGateInputs = {
        { "rpg_mid_gate_nav", "Disable", "" },
        { "rpg_mid_gate_nav", "SetNonsolid", "" },
        { "rpg_mid_gate_nav", "Disable", "" },
        { "rpg_mid_gate_nav", "SetNonsolid", "" },
    }
    assert_equal(#fired, #expectedGateInputs, "all gate inputs fired")
    for index, expected in ipairs(expectedGateInputs) do
        assert_equal(fired[index].target, expected[1], "gate target " .. index)
        assert_equal(fired[index].input, expected[2], "gate input " .. index)
        assert_equal(fired[index].value, expected[3], "gate value " .. index)
        assert_equal(fired[index].delay, 0, "gate delay " .. index)
        assert_equal(fired[index].activator, nil, "gate activator " .. index)
        assert_equal(fired[index].caller, nil, "gate caller " .. index)
    end
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

-- Transfers must authenticate both ends and inspect exact post-operation ownership.
do
    local Transfer = require("issue_fixes.inventory_transfer")
    local source, target = Unit.new(), Unit.new()
    local item = Item.new("item_blink")
    source.inventory[0] = item
    local service = Transfer.new({
        is_inventory_source = function(id, unit) return id == 0 and unit == source end,
        is_roster_hero = function(id, unit) return id == 0 and unit == target end,
    })
    assert_equal(service:Transfer(1, source, item, target), false, "foreign player rejected")
    assert_equal(service:Transfer(0, target, item, target), false, "foreign source rejected")
    target.AddItem = function(self)
        self.inventory[1] = Item.new("unrelated_change")
    end
    assert_equal(service:Transfer(0, source, item, target), false, "unrelated mutation is not transfer")
    assert_equal(source.inventory[0], item, "same handle rolled back")
    target.AddItem = function(self, value)
        self.inventory[0] = value
        error("engine throws after successful attach")
    end
    assert_equal(service:Transfer(0, source, item, target), true, "post-attach exception retains success")
    assert_equal(target.inventory[0], item, "successful handle retained")
    assert_equal(item.purchaser, nil, "transfer preserves original purchaser")
    target:TakeItem(item)
    source.inventory[0] = item
    target.AddItem = function(self, value)
        value.valid = false
        self.inventory[0] = Item.new("combined_item")
    end
    assert_equal(service:Transfer(0, source, item, target), true, "engine combination accepted")
end

-- The default rule is executable under the actual RuleService schema.
do
    local DefaultRules = require("issue_fixes.default_rules")
    local RuleService = require("tactics.rule_service")
    local service = RuleService.new({
        get_phase = function() return "PREPARE" end,
        is_roster_hero = function() return true end,
        is_action_allowed = function() return true end,
        state = { rules = {} },
    })
    local rule = DefaultRules.Normalize(false)[1]
    assert_equal(service:ValidateRule(0, Unit.new(), rule), true, "valid default schema")
    assert_equal(rule.target.team, "enemy", "default enemy team")
    assert_equal(rule.target_priorities[1].type, "nearest", "default nearest target")
    assert_equal(rule.approach, "range_only", "default current range only")
end

-- Actual ch01/ch02 keys, missing stages and already-distinct stages.
do
    local Levels = require("issue_fixes.level_uniqueness")
    local levels = {
        ch01 = { enemies = { { unit = "same", count = 2 } } },
        ch02 = { enemies = { { unit = "same" }, { unit = "same" } }, reward = { gold = 19 } },
    }
    local reward = levels.ch02.reward
    assert_equal(Levels.ApplyStageOneTwoFix(levels), true, "padded chapter repair")
    assert_equal(levels.ch02.reward, reward, "reward identity preserved")
    assert_equal(levels["2"], nil, "no phantom stage created")
    local enemies = levels.ch02.enemies
    assert_equal(Levels.ApplyStageOneTwoFix(levels), false, "distinct chapter untouched")
    assert_equal(levels.ch02.enemies, enemies, "distinct enemy identity retained")
    assert_equal(Levels.ApplyStageOneTwoFix({ ch01 = levels.ch01 }), false, "missing chapter not invented")
end

-- Live dataLoader/teamHeroes and native ai presets are authoritative.
do
    local Compat = require("issue_fixes.compat")
    local field, bench, enemy = Unit.new(), Unit.new(), Unit.new(DOTA_TEAM_BADGUYS)
    enemy.enemyRuleIndex = 1
    local levels = { ch02 = { enemies = { { unit = "centaur", ai = "bruiser" } } } }
    local game = {
        phase = "result", playerId = 0, currentLevelId = "ch02", benchUnits = { bench },
        dataLoader = { GetLevel = function(_, key) return levels[key] end, GetAllLevels = function() return levels end },
        battleManager = { teamHeroes = { [2] = { field }, [3] = { enemy } }, teamRules = { [3] = {} } },
        tacticBridge = { tacticEngine = { states = {} } },
        BuildEnemyRules = function(_, profile) return { profile } end,
        IsLineupUnit = function(_, unit) return unit == field end,
        IsBenchUnit = function(_, unit) return unit == bench end,
    }
    local compat = Compat.new(game)
    assert_equal(compat:GetPhase(), "SETTLE", "live result phase recognized")
    assert_equal(compat:GetPlayerUnits()[1], field, "bench excluded from AI targets")
    assert_equal(compat:GetEnemyUnits()[1], enemy, "actual enemies used")
    assert_equal(compat:GetLevels(), levels, "actual level registry used")
    assert_equal(compat:GetStageEntries(), levels.ch02.enemies, "current chapter entries used")
    assert_equal(compat:IsRosterHero(0, bench), true, "owned bench accepted")
    assert_equal(compat:IsRosterHero(1, bench), false, "other player rejected")
    compat:BindTacticProfile(enemy, "bruiser", {})
    assert_equal(game.battleManager.teamRules[3][1][1], "bruiser", "profile reaches live rules")
    game.tacticBridge.tacticEngine.states[enemy:entindex()] = { chase = {} }
    assert_equal(compat:HasTacticOrder(enemy), true, "live chase detected")
    game.battleManager.teamHeroes[3] = {}
    assert_equal(#compat:GetEnemyUnits(), 0, "empty team remains authoritative")
    game.battleManager = nil
    game.currentEnemyUnits = {}
    game.enemyUnits = { enemy }
    assert_equal(#compat:GetEnemyUnits(), 0, "empty current-stage list wins stale list")
    game.phase = nil
    game.battlePhase = "COUNTDOWN"
    assert_equal(compat:GetPhase(), "COUNTDOWN", "phase lookup survives nil fields")
end

-- Name matching never assigns another unit's profile to an unmatched name.
do
    local Runtime = require("issue_fixes.enemy_runtime")
    local a, b, extra = Unit.new(3), Unit.new(3), Unit.new(3)
    a.unit_name, b.unit_name, extra.unit_name = "a", "b", "summon"
    local orders = 0
    local busy = false
    local runtime = Runtime.new({
        execute_order = function() orders = orders + 1; return true end,
        has_tactic_order = function() return busy end,
    })
    runtime:RegisterStage({ { unit = "a", ai = "profile_a" }, { unit = "b", ai_profile = "profile_b" } }, { extra, b, a })
    assert_equal(extra.rpg_ai_profile, "attack_nearest", "unknown named unit keeps fallback")
    assert_equal(a.rpg_ai_profile, "profile_a", "legacy ai field bound by name")
    assert_equal(b.rpg_ai_profile, "profile_b", "explicit profile bound by name")
    for _, name in ipairs({ "modifier_rooted", "modifier_disarmed", "modifier_silence" }) do a.modifiers[name] = true end
    runtime:RegisterStage({ "a" }, { a })
    runtime:Start({ Unit.new(2, Vector(-200, 0, 0)) }, Vector(0, 0, 0))
    for _, name in ipairs({ "modifier_rooted", "modifier_disarmed", "modifier_silence" }) do
        assert_equal(a.modifiers[name], true, "combat modifier preserved: " .. name)
    end
    local before = orders
    busy = true
    runtime:Think()
    assert_equal(orders, before, "tactic chase not interrupted")
    busy = false
    a.IsInAbilityPhase = function() return true end
    runtime:Think()
    assert_equal(orders, before, "cast phase not interrupted")
    a.IsInAbilityPhase = nil
    a.attack_target = Unit.new(2)
    runtime:Think()
    assert_equal(orders, before, "live attack target not interrupted")
    a.attack_target = nil
    runtime:Think()
    assert_equal(orders, before + 1, "idle enemy receives fallback")
end

-- Native neutral fallback chases persist without overriding casts or tactic orders.
do
    local oldClock, clock = GameRules.GetGameTime, 0
    GameRules.GetGameTime = function() return clock end
    local neutral, hero, target = Unit.new(3), Unit.new(3), Unit.new(2, Vector(1000,0,0))
    neutral.unit_name = "npc_dota_neutral_centaur_khan"
    neutral.IsIdle = function() return false end
    hero.IsIdle = function() return false end
    local busy, orders = false, 0
    local runtime = require("issue_fixes.enemy_runtime").new({
        has_tactic_order = function() return busy end,
        execute_order = function() orders = orders + 1; return true end,
    })
    runtime:RegisterStage({}, { neutral, hero })
    runtime:Start({ target }, Vector(0, 0, 0))
    assert_equal(neutral.idle_acquire, false, "neutral native idle acquisition disabled")
    assert_equal(hero.idle_acquire, true, "hero acquisition unchanged")
    assert_equal(neutral.force_target, target, "neutral fallback owns target")
    local before = orders
    for _ = 1, 8 do
        clock=clock+.25
        neutral.position.x=neutral.position.x+25
        runtime:Think()
    end
    assert_equal(orders, before, "pending neutral chase is not restarted when attack target is nil")
    assert_equal(neutral.force_target, target, "pending chase keeps its forced target")
    neutral.IsIdle = function() return true end
    clock=clock+.5
    runtime:Think()
    assert_equal(orders, before + 1, "idle neutral recovers a lost attack order")
    neutral.IsIdle = function() return false end
    neutral.attack_target = target
    runtime:Think()
    assert_equal(orders, before + 1, "active attack is not restarted")
    neutral.attack_target = nil
    busy = true
    runtime:Think()
    assert_equal(orders, before + 1, "tactic order respected")
    assert_equal(neutral.force_target, nil, "force target released to tactic")
    busy = false
    neutral.IsChanneling = function() return true end
    runtime:Think()
    assert_equal(orders, before + 1, "channel not interrupted")
    neutral.IsChanneling = nil
    target.alive = false
    local replacement = Unit.new(2)
    runtime.player_units = { replacement }
    runtime:Think()
    assert_equal(neutral.force_target, replacement, "dead target replaced")
    assert_equal(orders, before + 2, "replacement target receives one attack order")
    runtime:Think()
    assert_equal(orders, before + 2, "replacement chase persists across ticks")
    runtime:Stop()
    assert_equal(neutral.force_target, nil, "force target cleared on stop")

    local accepted = false
    runtime.execute_order = function() orders = orders + 1; return accepted end
    runtime:RegisterStage({}, { neutral })
    runtime:Start({ replacement }, Vector(0, 0, 0))
    assert_equal(neutral.rpg_fallback_force_target, nil, "rejected attack does not own a pending chase")
    assert_equal(neutral.force_target, nil, "rejected attack releases forced target")
    local rejected_count = orders
    accepted = true
    runtime:Think()
    assert_equal(orders, rejected_count + 1, "rejected attack retries even on a non-idle neutral")
    assert_equal(neutral.force_target, replacement, "accepted retry owns replacement target")
    runtime:Think()
    assert_equal(orders, rejected_count + 1, "accepted retry is not repeated")
    runtime:Stop()
    GameRules.GetGameTime = oldClock
end

-- Authored actions take ownership before issuing orders, including direct attacks.
do
    local caster, target = Unit.new(3), Unit.new(2)
    local adapter = require("tactics/action_adapter").new({ Execute = function()
        assert_equal(caster.force_target, nil, "fallback released before tactical order")
    end })
    local function arm()
        caster.force_target = target
        caster.rpg_fallback_force_target = target
    end
    arm()
    adapter:Issue(caster, { kind = "attack", logical_id = "attack" }, target, {})
    assert_equal(caster.rpg_fallback_force_target, nil, "attack releases fallback ownership")
    arm()
    adapter:IssueApproach(caster, {}, target)
    assert_equal(caster.rpg_fallback_force_target, nil, "approach releases fallback ownership")
    arm()
    adapter:Issue(caster, { kind = "wait", logical_id = "wait" }, nil, {})
    assert_equal(caster.force_target, nil, "wait releases forced attack")
end

-- Native tactic attacks retain ownership across fallback ticks, but casts/waits release it.
do
    local caster, target = Unit.new(3), Unit.new(2)
    caster.unit_name = "npc_dota_neutral_centaur_khan"
    local orders = {}
    local adapter = require("tactics/action_adapter").new({ Execute = function(_, order)
        orders[#orders + 1] = order
    end })
    local runtime = require("issue_fixes.enemy_runtime").new({
        has_tactic_order = function() return true end,
        execute_order = function() error("fallback must not replace tactic target") end,
    })
    runtime.enemy_units, runtime.player_units, runtime.running = { caster }, { target }, true
    adapter:Issue(caster, { kind = "attack", logical_id = "attack" }, target, {})
    assert_equal(caster.rpg_tactic_force_target, target, "tactic attack owns neutral target")
    runtime:Think()
    assert_equal(caster.force_target, target, "fallback tick retains tactic ownership")
    adapter:IssueApproach(caster, { kind = "attack" }, target)
    assert_equal(orders[#orders].OrderType, DOTA_UNIT_ORDER_ATTACK_TARGET, "attack chase stays an attack order")
    adapter:IssueApproach(caster, { kind = "ability" }, target)
    assert_equal(caster.force_target, nil, "skill approach releases forced attack")
    adapter:Issue(caster, { kind = "attack", logical_id = "attack" }, target, {})
    adapter:Issue(caster, { kind = "wait", logical_id = "wait" }, nil, {})
    assert_equal(caster.force_target, nil, "explicit wait releases forced attack")
    adapter:Issue(caster, { kind = "attack", logical_id = "attack" }, target, {})
    target.alive = false
    runtime:Think()
    assert_equal(caster.force_target, nil, "dead tactic target is released")
    target.alive = true
    adapter:Issue(caster, { kind = "attack", logical_id = "attack" }, target, {})
    runtime:Stop()
    assert_equal(caster.force_target, nil, "battle stop releases tactic target")
end

-- Basic attack rows fill downtime instead of starving later skills or skill chases.
do
    local Engine = require("tactics/tactic_engine")
    local oldClock = GameRules.GetGameTime
    GameRules.GetGameTime = function() return 0 end
    local unit, target = Unit.new(2), Unit.new(3)
    setmetatable(unit.position, { __sub = function(a, b)
        return { Length2D = function() return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end }
    end })
    local attack = { kind = "attack", logical_id = "attack", target_mode = "unit" }
    local skill = { kind = "ability", logical_id = "skill", target_mode = "unit" }
    local wait = { kind = "wait", logical_id = "wait", wait_duration = 1 }
    local function rule(action) return { action = action, approach = "allow_approach" } end
    local rules, issued, moves = { rule(attack), rule(skill) }, {}, {}
    local engine = Engine.new({
        order_gate = {}, get_phase = function() return "FIGHT" end,
        get_battle_units = function() return { unit } end, get_rules = function() return rules end,
        build_context = function() return {} end, selector = {},
        conditions = { EvaluateUseConditions = function() return true end },
        actions = {
            Resolve = function(_, _, action) return action end,
            CanExecute = function(_, _, spec) return spec.ready ~= false, "cooldown" end,
            IsInRange = function(_, _, spec) return spec.in_range ~= false end,
            Issue = function(_, _, spec) issued[#issued + 1] = spec.logical_id; return true end,
            IssueApproach = function(_, _, spec) moves[#moves + 1] = spec.logical_id; return true end,
        },
    })
    engine.ResolveRuleTarget = function() return target, target end
    local state = engine:GetState(unit)
    engine:EvaluateUnit(unit, state, 1)
    assert_equal(issued[#issued], "skill", "skill after attack executes first")
    skill.ready = false
    engine:EvaluateUnit(unit, state, 2)
    assert_equal(issued[#issued], "attack", "cooldown falls back to authored attack")
    skill.ready, skill.in_range = true, false
    engine:EvaluateUnit(unit, state, 3)
    assert_equal(state.chase.rule_index, 2, "available skill starts chase after attack row")
    engine:EvaluateUnit(unit, state, 3.2)
    assert_equal(state.chase.rule_index, 2, "earlier attack cannot interrupt skill chase")
    skill.in_range = true
    engine:EvaluateUnit(unit, state, 3.4)
    assert_equal(issued[#issued], "skill", "skill casts after reaching range")
    skill.ready, attack.in_range = false, false
    engine:EvaluateUnit(unit, state, 4)
    assert_equal(state.chase.rule_index, 1, "attack chases during cooldown")
    skill.ready, skill.in_range = true, false
    engine:EvaluateUnit(unit, state, 4.2)
    assert_equal(state.chase.rule_index, 2, "later ready skill replaces attack chase without losing its new chase")
    state.chase = nil
    rules = { rule(wait), rule(attack), rule(skill) }
    engine:EvaluateUnit(unit, state, 5)
    assert_equal(issued[#issued], "wait", "explicit wait keeps authored non-attack priority")
    local count = #issued
    engine:EvaluateUnit(unit, state, 5.2)
    assert_equal(#issued, count, "explicit wait duration remains respected")
    unit.IsChanneling = function() return true end
    engine:EvaluateUnit(unit, state, 7)
    assert_equal(#issued, count, "channeling is not interrupted by priority scanning")
    GameRules.GetGameTime = oldClock
end

-- Rejected and repeated start events must not activate/reset enemy AI.
do
    local Bootstrap = require("issue_fixes.bootstrap")
    local Game = { InitGameMode = function() end }
    function Game:OnStartBattle(accept) if accept then self.phase = "fight" end end
    function Game:SpawnLevelEnemies(ready) return ready end
    Bootstrap.Install(Game)
    local started, registered = 0, 0
    local game = setmetatable({ phase = "setup" }, { __index = Game })
    game.rpgIssueFixCompat = require("issue_fixes.compat").new(game)
    game.issueFixes = {
        RegisterCurrentStage = function() registered = registered + 1 end,
        OnBattleStarted = function() started = started + 1 end,
    }
    local active, bench, portrait = Unit.new(2), Unit.new(2), Unit.new(2)
    for _, unit in ipairs({ active, bench, portrait }) do
        unit.modifiers.modifier_rpg_prepare_bench = true
        unit.modifiers.modifier_silence = true
    end
    game.battleManager = { teamHeroes = { [2] = { active }, [3] = {} } }
    game.selectedHero = portrait
    assert_equal(game:SpawnLevelEnemies(false), false, "pending spawn keeps return value")
    assert_equal(registered, 0, "pending/failed stage must not bind new entries to old enemies")
    assert_equal(game:SpawnLevelEnemies(true), true, "ready spawn keeps return value")
    assert_equal(registered, 1, "completed stage registers native units")
    game:OnStartBattle(false)
    assert_equal(active.modifiers.modifier_rpg_prepare_bench, true, "rejected start retains preparation")
    assert_equal(started, 0, "rejected start does not activate runtime")
    game:OnStartBattle(true)
    assert_equal(active.modifiers.modifier_rpg_prepare_bench, nil, "fielded hero released")
    assert_equal(active.modifiers.modifier_silence, true, "combat silence preserved")
    assert_equal(bench.modifiers.modifier_rpg_prepare_bench, true, "bench stays locked")
    assert_equal(portrait.modifiers.modifier_rpg_prepare_bench, true, "UI portrait does not choose release target")
    game:OnStartBattle(true)
    assert_equal(started, 1, "runtime starts only on phase transition")
end

-- Native order side effects run even without battle units, but never in combat.
do
    local Filters = require("tactics.order_filter")
    local phase, validated = "PREPARE", 0
    local unit = Unit.new()
    local filter = Filters.OrderFilter.new({
        get_phase = function() return phase end,
        is_battle_unit = function() return false end,
        is_inventory_unit = function(u) return u == unit end,
        validate_inventory_order = function() validated = validated + 1; return true end,
    })
    for _, order_type in ipairs({ DOTA_UNIT_ORDER_PURCHASE_ITEM, DOTA_UNIT_ORDER_TRAIN_ABILITY,
        DOTA_UNIT_ORDER_SELL_ITEM, DOTA_UNIT_ORDER_DISASSEMBLE_ITEM,
        DOTA_UNIT_ORDER_GIVE_ITEM, DOTA_UNIT_ORDER_MOVE_ITEM, DOTA_UNIT_ORDER_PICKUP_ITEM,
        DOTA_UNIT_ORDER_DROP_ITEM, DOTA_UNIT_ORDER_SET_ITEM_COMBINE_LOCK }) do
        local order = { order_type = order_type, issuer_player_id_const = 0, units = {} }
        phase = "PREPARE"
        assert_equal(filter:Filter(order), true, "prepare native order " .. order_type)
        for _, locked in ipairs({ "COUNTDOWN", "FIGHT", "SETTLE" }) do
            phase = locked
            assert_equal(filter:Filter(order), false, "locked native order " .. order_type)
        end
    end
    assert_equal(validated, 9, "native validator invoked once per preparation order")
end

-- Load the actual addon class: standalone compatibility mocks cannot prove wiring.
do
    function class()
        local result = {}
        result.__index = result
        return result
    end
    dofile(live_vscripts .. "/addon_game_mode.lua")
    local game = setmetatable({ playerId = 0, phase = "setup", heroData = {} }, CDota2RpgDemo)
    local hero = Unit.new()
    local ability = Item.new("test_spell")
    ability.level = 0
    function ability:GetLevel() return self.level end
    function ability:SetLevel(value) self.level = value end
    hero.level, hero.points = 1, 1
    function hero:GetLevel() return self.level end
    function hero:HeroLevelUp() self.level = self.level + 1; self.points = self.points + 1 end
    function hero:GetAbilityCount() return 1 end
    function hero:GetAbilityByIndex() return ability end
    function hero:GetAbilityPoints() return self.points end
    function hero:SetAbilityPoints(value) self.points = value end
    function hero:GetEntityIndex() return self:entindex() end
    function hero:SetRespawnsDisabled() end
    function hero:SetHealth() end
    function hero:SetMana() end
    function hero:GetMaxHealth() return 100 end
    function hero:GetMaxMana() return 100 end
    function hero:AddNewModifier(_, _, name) self.modifiers[name] = true end
    function hero:SetOwner(owner) self.owner = owner end
    function hero:SetPlayerID(id) self.player_id = id end
    function hero:SetControllableByPlayer(id) self.controlled = id end
    function hero:GetPlayerOwnerID() return self.player_id or -1 end
    hero.benchHeroName = "test_hero"
    game.heroData.test_hero = { level = 3, skill_points = 3 }
    game.autoAbilityHeroes = {}
    game:PrepareBattleHero(hero, 3)
    assert_equal(hero.points, 3, "bench retains manual skill points")
    assert_equal(ability.level, 0, "bench not auto-trained")
    assert_equal(hero.modifiers.modifier_rpg_prepare_bench, true, "bench uses non-stunning lock")
    ability.level, hero.points = 1, 2
    game:CaptureHeroAbilities(hero)
    assert_equal(game.heroData.test_hero.skill_points, 2, "native spent point recorded")
    game.heroData.test_hero.level = 4
    game:PrepareBattleHero(hero, 4)
    assert_equal(hero.points, 3, "only earned level point added")
    assert_equal(ability.level, 1, "trained ability retained through level-up")
    local stash = Unit.new()
    game.GetStashUnit = function() return stash end
    assert_equal(game:BindEquipmentCarrierToPlayer(hero), true, "live carrier binding works")
    assert_equal(hero.player_id, 0, "native PlayerID assigned")
    assert_equal(hero.owner, stash, "native owner assigned")
    game.IsLineupUnit = function() return false end
    game.IsBenchUnit = function(_, unit) return unit == hero end
    local order = { units = { hero:entindex() }, issuer_player_id_const = 0,
        order_type = DOTA_UNIT_ORDER_TRAIN_ABILITY, entindex_ability = ability:entindex() }
    assert_equal(game:ValidatePrepareOrder(order), true, "actual bench training validation")
    order.entindex_ability = Item.new("foreign_spell"):entindex()
    assert_equal(game:ValidatePrepareOrder(order), false, "foreign ability rejected")
    local item = Item.new("item_blink")
    hero.inventory[0] = item
    order.order_type, order.entindex_ability = DOTA_UNIT_ORDER_SET_ITEM_COMBINE_LOCK, item:entindex()
    assert_equal(game:ValidatePrepareOrder(order), true, "actual combine lock allowed")
    local transfer = require("issue_fixes.inventory_transfer").new({
        is_inventory_source = function(id, unit) return id == 0 and unit == stash end,
        is_roster_hero = function(id, unit) return id == 0 and unit == hero end,
    })
    game.issueFixes = { TransferWarehouseItem = function(_, ...) return transfer:Transfer(...) end }
    game.FindOwnedHeroUnit = function() return hero end
    game.SyncLiveEquipmentState = function(self) self.inventory_synced = true end
    for slot = 0, 5 do hero.inventory[slot] = Item.new("full_active_" .. slot) end
    local gift = Item.new("item_force_staff")
    stash.inventory[0] = gift
    game:OnItemEquip(nil, { hero = "test_hero", item = gift.name, item_index = gift:entindex() })
    assert_equal(hero.inventory[6], gift, "live HUD event transfers exact handle into backpack")
    assert_equal(stash.inventory[0], nil, "live HUD event removes source handle")
    assert_equal(game.inventory_synced, true, "live HUD event synchronizes state")
    local presets = { rules = {
        ["2"] = { action = { type = "attack" }, target = "enemy_distance_nearest" },
        ["1"] = { action = { type = "ability_1" }, target = "self" },
    } }
    game.dataLoader = { GetEnemyAI = function() return presets end }
    local enemy_rules = game:BuildEnemyRules("configured")
    assert_equal(#enemy_rules, 2, "string-keyed KV AI rules loaded")
    assert_equal(enemy_rules[1].action, "ability_1", "KV AI priority order retained")
end

-- The real bridge preserves authored rules across its battle ResetState call.
do
    local field = Unit.new()
    field.unit_name, field.lineupHeroName = "test_hero", "test_hero"
    local listeners, net_values = {}, {}
    CustomGameEventManager = {
        RegisterListener = function(_, name, callback) listeners[name] = callback end,
    }
    CustomNetTables = {
        SetTableValue = function(_, name, key, value) net_values[key] = value end,
    }
    Dynamic_Wrap = function(object, method) return object[method] end
    local mode = {
        SetExecuteOrderFilter = function(self, callback, context)
            self.filter, self.context = callback, context
        end,
    }
    GameRules = { GetGameModeEntity = function() return mode end, GetGameTime = function() return 0 end }
    local game = {
        phase = "setup", playerId = 0, heroData = { test_hero = {} }, heroRulesByName = {},
        battleManager = { teamHeroes = { [2] = { field }, [3] = {} }, teamRules = { [2] = {}, [3] = {} } },
        IsEquipmentCarrier = function(_, unit) return unit == field end,
        IsNativeItemShopOrder = function(_, order) return order.order_type == DOTA_UNIT_ORDER_PURCHASE_ITEM end,
        ValidatePrepareOrder = function(self) self.validated = (self.validated or 0) + 1; return true end,
    }
    local bridge = TacticBridge.new({ game_mode = game })
    bridge:Install()
    assert_equal(#bridge.getRules(field), 1, "unlearned hero has only attack default")
    local learned = 0
    local ability = {
        IsNull = function() return false end, GetAbilityName = function() return "test_nuke" end,
        GetLevel = function() return learned end, IsPassive = function() return false end,
        IsHidden = function() return false end, IsActivated = function() return true end,
    }
    field.GetAbilityCount = function() return 1 end
    field.GetAbilityByIndex = function() return ability end
    learned = 1
    assert_equal(#bridge.getRules(field), 2, "learning refreshes cached defaults without client")
    assert_equal(bridge.getRules(field)[1].action.logical_id, "test_nuke", "native spell identity before attack")
    assert_equal(bridge.getRules(field)[2].action.kind, "attack", "attack remains last")
    learned = 0
    assert_equal(#bridge.getRules(field), 1, "unavailable spells leave generated defaults")
    assert_equal(bridge.getRules(field)[1].approach, "range_only", "live bridge default is range-only")
    local authored = require("issue_fixes.default_rules").CreateAttackNearestRule()
    authored.enabled = false
    bridge.ruleService.state.rules.test_hero = { authored, authored, authored }
    bridge:ResetState()
    assert_equal(#bridge.getRules(field), 3, "battle reset preserves authored rows")
    local args = { action_kind = "attack", action_id = "basic_attack", target_team = "enemy",
        approach = "range_only", enabled = 0, rule_count = 1 }
    assert_equal(bridge.ruleService:UpdateRule(0, field:entindex(), 1, args), true, "authorized truncate accepted")
    assert_equal(#bridge.getRules(field), 1, "server stale rows truncated")
    assert_equal(bridge.getRules(field)[1].enabled, false, "authored disabled rule retained")
    assert_equal(next(net_values["test_hero:2"]), nil, "stale published rule cleared")
    args.rule_count = 0
    assert_equal(bridge.ruleService:UpdateRule(0, field:entindex(), 1, args), false, "zero rule count rejected")
    args.rule_count = 1.5
    assert_equal(bridge.ruleService:UpdateRule(0, field:entindex(), 1, args), false, "fractional count rejected")
    args.rule_count = 1
    assert_equal(bridge.ruleService:UpdateRule(1, field:entindex(), 1, args), false, "foreign truncation rejected")
    assert_equal(bridge.ruleService:UpdateRule(0, field:entindex(), "bad", args), false, "malformed slot rejected")
    assert_equal(bridge.ruleService:UpdateRule(0, field:entindex(), 2, args), false, "disabled row beyond count rejected")
    assert_equal(#bridge.getRules(field), 1, "invalid update never adds disabled padding")
    args.enabled = 1
    assert_equal(bridge.ruleService:UpdateRule(0, field:entindex(), 2, args), false, "active row beyond count rejected")
    local order = { order_type = DOTA_UNIT_ORDER_PURCHASE_ITEM, issuer_player_id_const = 0, units = {} }
    assert_equal(mode.filter(mode.context, order), true, "installed bridge filter allows native purchase")
    assert_equal(game.validated, 1, "installed bridge invokes native purchase context validator")
    game.phase = "fight"
    assert_equal(mode.filter(mode.context, order), false, "installed bridge blocks fight purchase")
end

-- Native shop API configuration and roster assignment failures are observable.
do
    local Roster = require("issue_fixes.roster_access")
    local easybuy, universal
    SendToServerConsole = function(command) easybuy = command end
    GameRules.SetUseUniversalShopMode = function(_, enabled) universal = enabled end
    Roster.EnableNativeShop({ enable_easy_buy = true })
    assert_equal(universal, true, "universal native shop enabled")
    assert_equal(easybuy, "dota_easybuy 1", "native easy-buy enabled")
    SendToServerConsole = nil
    local player = {}
    PlayerResource = { GetPlayer = function() return player end }
    local hero = Unit.new()
    function hero:SetOwner(value) self.owner = value end
    function hero:SetPlayerID(value) self.player_id = value end
    function hero:SetControllableByPlayer(value) self.controlled = value end
    assert_equal(Roster.AssignToPlayer(hero, 0), true, "all ownership APIs succeed")
    assert_equal(hero.owner, player, "roster owner assigned")
    assert_equal(hero.player_id, 0, "roster player id assigned")
    hero.SetPlayerID = function() error("assignment rejected") end
    assert_equal(Roster.AssignToPlayer(hero, 0), false, "assignment error not reported as success")
    MODIFIER_STATE_INVULNERABLE, MODIFIER_STATE_ROOTED = 1, 2
    MODIFIER_STATE_DISARMED, MODIFIER_STATE_SILENCED, MODIFIER_STATE_NO_UNIT_COLLISION = 3, 4, 5
    MODIFIER_STATE_STUNNED, MODIFIER_STATE_COMMAND_RESTRICTED = 6, 7
    require("modifiers.modifier_rpg_prepare_bench")
    local states = modifier_rpg_prepare_bench:CheckState()
    assert_equal(states[MODIFIER_STATE_STUNNED], nil, "bench is not stunned")
    assert_equal(states[MODIFIER_STATE_COMMAND_RESTRICTED], nil, "bench accepts native commands")
end

print("runtime tests passed (" .. (arg[2] or "overlay") .. ")")
