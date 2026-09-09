-- tactic_bridge.lua
-- 桥接层：把现有 BattleManager/规则负载接入修订版战术模块
-- （rule_service / condition_registry / target_selector / tactic_engine / order_filter / combat_memory）

local Context = require("tactics/condition_context")
local Snapshot = require("tactics/rule_snapshot")
local Conditions = require("tactics/condition_registry")
local TargetSelector = require("tactics/target_selector")
local ActionAdapter = require("tactics/action_adapter")
local OrderFilterModule = require("tactics/order_filter")
local OrderGateModule = OrderFilterModule.OrderGate
local CombatMemory = require("tactics/combat_memory")
local TacticEngine = require("tactics/tactic_engine")
local RuleService = require("tactics/rule_service")
local DefaultRules = require("issue_fixes.default_rules")

local function is_valid_entity(entity)
	return entity ~= nil and (entity.IsNull == nil or not entity:IsNull())
end

local function is_alive(entity)
	return is_valid_entity(entity) and (entity.IsAlive == nil or entity:IsAlive())
end

local function entity_index(entity)
	return is_valid_entity(entity) and entity:entindex() or -1
end

TacticBridge = {}
TacticBridge.__index = TacticBridge

-- 旧目标组合 ID -> 修订版 target 结构
local function decomposeLegacyTarget(target)
	local t = {
		team = "enemy",
		types = { "hero", "monster", "summon" },
	}
	local id = tostring(target or "")
	if id == "self" then
		t.team = "self"
		t.types = { "hero" }
		return t, {}, { { type = "nearest" } }
	end
	if string.match(id, "^ally_") ~= nil then
		t.team = "ally"
		t.types = { "hero" }
	end

	local filters = {}
	local priorities = {}

	if string.match(id, "_hp_lowest$") ~= nil then
		table.insert(priorities, { type = "lowest_health" })
	elseif string.match(id, "_hp_pct_lowest$") ~= nil then
		table.insert(priorities, { type = "lowest_hp_pct" })
	elseif string.match(id, "_hp_highest$") ~= nil then
		table.insert(priorities, { type = "highest_health" })
	elseif string.match(id, "_hp_pct_highest$") ~= nil then
		table.insert(priorities, { type = "highest_hp_pct" })
	elseif string.match(id, "_armor_lowest$") ~= nil then
		table.insert(priorities, { type = "lowest_armor" })
	elseif string.match(id, "_attack_highest$") ~= nil then
		table.insert(priorities, { type = "highest_attack_damage" })
	elseif string.match(id, "_attack_lowest$") ~= nil then
		table.insert(priorities, { type = "lowest_attack_damage" })
	elseif string.match(id, "_mr_highest$") ~= nil then
		table.insert(priorities, { type = "highest_magic_resistance" })
	elseif string.match(id, "_mr_lowest$") ~= nil then
		table.insert(priorities, { type = "lowest_magic_resistance" })
	end

	if string.match(id, "_distance_nearest$") ~= nil then
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_distance_farthest$") ~= nil then
		table.insert(priorities, { type = "farthest" })
	end

	if string.match(id, "_casting$") ~= nil then
		table.insert(filters, { type = "is_casting" })
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_boss$") ~= nil then
		table.insert(priorities, { type = "prefer_tag", value = "boss" })
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_healer$") ~= nil then
		table.insert(priorities, { type = "prefer_tag", value = "healer" })
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_controlled$") ~= nil then
		table.insert(filters, { type = "is_controlled" })
		table.insert(priorities, { type = "nearest" })
	end

	if #priorities == 0 then
		table.insert(priorities, { type = "nearest" })
	end
	return t, filters, priorities
end

-- 当前规则 ID -> RuleService use_condition。
local function mapRuleCondition(conditionType, value)
	local v = tonumber(value) or 50
	if conditionType == nil or conditionType == "always" then
		return { type = "always" }
	end
	if conditionType == "self_hp_pct_lte" then
		return { type = "self_hp_pct_lte", value = v / 100 }
	end
	if conditionType == "self_mana_pct_gte" then
		return { type = "self_mana_pct_gte", value = v / 100 }
	end
	if conditionType == "alive_enemy_count_gte" then
		return { type = "alive_enemy_count_gte", value = v }
	end
	if conditionType == "elapsed_gte" then
		return { type = "elapsed_gte", value = v }
	end
	if conditionType == "self_recently_damaged" then
		return { type = "self_recently_damaged", seconds = math.max(1, v) }
	end
	if conditionType == "any_ally_recently_damaged" then
		return { type = "any_ally_recently_damaged", seconds = math.max(1, v) }
	end
	return { type = tostring(conditionType), value = value }
end

-- 把旧负载规则（action/condition(组合)/value/target/forced）转换为修订版规则结构
function TacticBridge.ConvertLegacyRule(slot, legacy)
	local actionKind = "attack"
	local logicalId = "basic_attack"
	if legacy.action ~= nil and legacy.action ~= "attack" then
		actionKind = string.match(legacy.action, "^item_") ~= nil and "item" or "ability"
		logicalId = legacy.action
	end

	local target, filters, priorities = decomposeLegacyTarget(legacy.target)

	local useConditions = { mapRuleCondition(legacy.condition, legacy.value) }
    -- Existing gameplay payloads may retain action/target while carrying v2
    -- numbered clauses. Only the original eight-condition path uses percent units.
    local decoded = RuleService.DecodeFlat(nil, legacy)
    if #decoded.use_conditions > 0 then useConditions = decoded.use_conditions end
    if #decoded.target_filters > 0 then filters = decoded.target_filters end
    if #decoded.target_priorities > 0 then priorities = decoded.target_priorities end
    -- Snapshots carry structured clauses rather than numbered flat fields.
    if type(legacy.use_conditions) == "table" then useConditions = legacy.use_conditions end
    if type(legacy.target_filters) == "table" then filters = legacy.target_filters end
    if type(legacy.target_priorities) == "table" then priorities = legacy.target_priorities end

	return RuleService.StripRemovedConditions({
		id = tostring(legacy.id or ("legacy_rule_" .. slot)),
        is_default = legacy.is_default == true,
		enabled = legacy.enabled ~= false,
		action = {
			kind = actionKind,
			logical_id = logicalId,
            destination = decoded.action.destination,
            cast_preference = decoded.action.cast_preference,
            desired_toggle_state = decoded.action.desired_toggle_state,
			target_team = "enemy",
		},
		target = target,
		target_filters = filters,
		target_priorities = priorities,
		use_conditions = useConditions,
        min_aoe_hits = decoded.min_aoe_hits,
		approach = legacy.forced and "allow_approach" or "range_only",
	})
end

function TacticBridge.new(options)
	return setmetatable({
		gameMode = assert(options.game_mode, "game_mode is required"),
	}, TacticBridge)
end

function TacticBridge:Install()
	print("[TacticDebug] bridge install: OFM=" .. type(OrderFilterModule) ..
		" OFM.new=" .. type(OrderFilterModule ~= nil and OrderFilterModule.new or nil) ..
		" TE=" .. type(TacticEngine) .. " RS=" .. type(RuleService) ..
		" Sel=" .. type(TargetSelector) .. " Act=" .. type(ActionAdapter) ..
		" Cond=" .. type(Conditions))
	local gameMode = self.gameMode
	local manager = self
	local orderGate = OrderGateModule.new()

	self.combatMemory = CombatMemory.new()
	self.orderGate = orderGate

	local function getPhase()
		if gameMode.phase == "setup" then
			return "PREPARE"
		elseif gameMode.phase == "fight" then
			return "FIGHT"
		end
		return "SETTLE"
	end

	local function isBattleUnit(unit)
		if not is_valid_entity(unit) then
			return false
		end
		if (gameMode.managedSummons or {})[unit] or (gameMode.tempestDoubles or {})[unit]
            or (gameMode.specialObjects or {})[unit] then return true end
		if unit.benchHeroName ~= nil then
			return false
		end
		for _, hero in ipairs(gameMode.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
			if hero == unit then
				return true
			end
		end
		for _, unit2 in ipairs(gameMode.battleManager.teamHeroes[DOTA_TEAM_BADGUYS] or {}) do
			if unit2 == unit then
				return true
			end
		end
		return false
	end

	local function getBattleUnits()
		local units = {}
		for _, hero in ipairs(gameMode.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
			table.insert(units, hero)
		end
		for _, unit in ipairs(gameMode.battleManager.teamHeroes[DOTA_TEAM_BADGUYS] or {}) do
			table.insert(units, unit)
		end
		return units
	end

	-- 稳定逻辑 ID -> 真实技能/物品名
	local function resolveActionName(unit, logicalId)
		if logicalId == "ultimate" then
			for slot = 0, unit:GetAbilityCount() - 1 do
				local ability = unit:GetAbilityByIndex(slot)
				if ability ~= nil and not ability:IsNull() and ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE
                    and Context.Call(ability, "IsHidden") ~= true and Context.Call(ability, "IsPassive") ~= true
                    and Context.Call(ability, "IsActivated") ~= false then
					return ability:GetAbilityName()
				end
			end
			return ""
		end
		local abilitySlot = tonumber(string.match(logicalId, "^ability_(%d+)$"))
		if abilitySlot ~= nil then
			local ability = unit:GetAbilityByIndex(abilitySlot - 1)
			return ability ~= nil and not ability:IsNull() and ability:GetAbilityName() or ""
		end
		local itemSlot = tonumber(string.match(logicalId, "^item_(%d+)$"))
		if itemSlot ~= nil and unit.GetItemInSlot ~= nil then
			local item = unit:GetItemInSlot(itemSlot - 1)
			return item ~= nil and not item:IsNull() and item:GetAbilityName() or ""
		end
		return logicalId
	end

	local state = { rules = {} }
	local legacyCache = {}
    self.lastActionOrders = {}

	-- 旧负载规则（heroRulesByName）-> 修订版结构，缓存于桥接层
	function manager.getRules(unit)
        local configured = manager.ruleService ~= nil and manager.ruleService:GetHeroRules(unit) or {}
        if #configured > 0 and (not Snapshot.IsEnemy(gameMode.battleManager, unit) or Snapshot.IsDeveloperMode()) then
            return configured
        end
		-- 敌方单位：按关卡实例规则（teamRules 中以 enemyRuleIndex 定位）。
		if unit.enemyRuleIndex ~= nil then
			local enemyRules = gameMode.battleManager.teamRules[DOTA_TEAM_BADGUYS][unit.enemyRuleIndex] or {}
			local converted = {}
			for slot, legacy in ipairs(enemyRules) do
				if legacy.enabled ~= false then
					table.insert(converted, TacticBridge.ConvertLegacyRule(slot, legacy))
				end
			end
			return require("issue_fixes.enemy_rules").CreateForUnit(unit, converted)
		end

		-- 仅为旧版本当前 Run 内存数据提供迁移回退，不再在开战时覆盖新版规则。
		local heroName = unit.lineupHeroName or unit:GetUnitName()
		local cache = legacyCache[heroName]
		if cache ~= nil then
            cache = DefaultRules.Normalize(cache, unit)
            legacyCache[heroName] = cache
			return cache
		end
		local legacyRules = gameMode.heroRulesByName[heroName] or {}
		local converted = {}
		for slot, legacy in ipairs(legacyRules) do
            table.insert(converted, TacticBridge.ConvertLegacyRule(slot, legacy))
		end
		converted = DefaultRules.Normalize(converted, unit)
		legacyCache[heroName] = converted
		return converted
	end

	function manager.invalidateRules()
		-- 只清理旧规则迁移缓存；RuleService 的当前 Run 配置不能在开战时清空。
		legacyCache = {}
	end

	local function buildContext(unit)
        local roster, sides = getBattleUnits(), {}
        for _, side in ipairs({DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS}) do
            for _, member in ipairs(gameMode.battleManager.teamHeroes[side] or {}) do sides[member] = side end
        end
        local observedAt = GameRules:GetGameTime()
        if self.unitObservation == nil or self.unitObservation.time ~= observedAt then
            local observed, ownerRoots, available = Context.ExpandBattleUnits(roster)
            self.unitObservation = {time=observedAt,units=observed,roots=ownerRoots,available=available}
        end
        local units, roots, ownershipAvailable = self.unitObservation.units,self.unitObservation.roots,self.unitObservation.available
        for _, member in ipairs(roster) do
            if Context.Call(member,"IsRealHero") ~= true then
                local owner = Context.Call(member,"GetOwnerEntity") or Context.Call(member,"GetOwner")
                local root = owner and Context.OwnerRoot(owner,roster)
                if root and root ~= member then roots[member] = root end
            end
        end
        for object in pairs(gameMode.specialObjects or {}) do
            local owner = Context.OwnerRoot(object, roster)
            if owner ~= nil and owner ~= object then roots[object] = owner end
        end
        local team = sides[roots[unit] or unit] or unit:GetTeamNumber()
        local nativeCasterTeam = unit:GetTeamNumber()
        if nativeCasterTeam == DOTA_TEAM_GOODGUYS or nativeCasterTeam == DOTA_TEAM_BADGUYS then team = nativeCasterTeam end
        local enemies, allies = {}, {}
        for _, member in ipairs(units) do
            local side = sides[roots[member] or member]
            local nativeTeam = Context.Call(member,"GetTeamNumber")
            -- Converted stage creeps change allegiance, while neutral stage
            -- units keep their registered battle side until converted.
            if nativeTeam == DOTA_TEAM_GOODGUYS or nativeTeam == DOTA_TEAM_BADGUYS then side = nativeTeam end
            sides[member] = side
            if side == team then allies[#allies+1] = member else enemies[#enemies+1] = member end
        end
		local aliveAllies = 0
        local deadAllies = 0
		local aliveEnemies = 0
		for _, ally in ipairs(allies) do
			if is_alive(ally) then aliveAllies = aliveAllies + 1
            elseif is_valid_entity(ally) then deadAllies = deadAllies + 1 end
		end
		for _, enemy in ipairs(enemies) do
			if is_alive(enemy) then aliveEnemies = aliveEnemies + 1 end
		end
		return {
			caster = unit,
            special_objects = gameMode.specialObjects or {},
			allies = allies,
			enemies = enemies,
			alive_ally_count = aliveAllies,
			alive_enemy_count = aliveEnemies,
			elapsed = gameMode.battleManager:GetBattleTime(),
			dead_ally_count = deadAllies,
            count_allies_around = function(center, radius) return Context.CountAround(units, center, radius, true, sides, roots) end,
            count_enemies_around = function(center, radius) return Context.CountAround(units, center, radius, false, sides, roots) end,
            is_summon = function(target) return Context.IsSummon(target, roots) end,
            is_owned_by = function(target, owner) return target ~= owner and roots[target] == owner end,
            count_owned_summons = function(owner)
                if not ownershipAvailable then return nil end
                local count = 0
                for _, candidate in ipairs(units) do
                    if candidate ~= owner and roots[candidate] == owner and is_alive(candidate) then count = count+1 end
                end
                return count
            end,
            get_target_actor = function(key)
                return Snapshot.ResolveTargetActor(gameMode.battleManager, gameMode.currentLevelId, unit, key)
            end,
            get_action_actor = function(key)
                -- Resolve stable roster identities each tick; never trust an old entity index.
                for _, team in ipairs({ DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }) do
                    for _, actor in ipairs(gameMode.battleManager.teamHeroes[team] or {}) do
                        if is_valid_entity(actor) and Snapshot.HeroKey(gameMode.battleManager, actor) == key then
                            return actor
                        end
                    end
                end
                return nil
            end,
            get_action_elapsed = function(caster, id)
                local name = resolveActionName(caster, tostring(id or ""))
                local last = (self.lastActionOrders[caster] or {})[name]
                return last ~= nil and GameRules:GetGameTime() - last or nil
            end,
            has_dispellable_buff = function(target) return Context.HasDispellable(target, false) end,
            has_dispellable_debuff = function(target) return Context.HasDispellable(target, true) end,
            has_shield = Context.HasShield,
            get_ability_charges = function(caster, id)
                local ability = Context.Call(caster, "FindAbilityByName", resolveActionName(caster, tostring(id or "")))
                return Context.Number(Context.Call(ability, "GetCurrentAbilityCharges"))
            end,
            action_used_within = function(caster, id, seconds)
                local name = resolveActionName(caster, tostring(id or ""))
                local last = (self.lastActionOrders[caster] or {})[name]
                return last ~= nil and GameRules:GetGameTime() - last <= seconds
            end,
			get_candidates = function(caster, action_spec, ruleTarget)
				local wantedTeam = tostring(ruleTarget and ruleTarget.team or "enemy")
				local types = {}
				if ruleTarget ~= nil and ruleTarget.types ~= nil then
					for _, t in pairs(ruleTarget.types) do
						types[tostring(t)] = true
					end
				end
				if wantedTeam == "self" then
					return { caster }
				end
				local pool
				if wantedTeam == "enemy" then
					pool = enemies
				else
					pool = allies
				end
				local candidates = {}
				for _, unit2 in ipairs(pool) do
					if is_alive(unit2) then
						local isHero = unit2.IsRealHero ~= nil and unit2:IsRealHero()
                        local isSummon = Context.IsSummon(unit2, roots)
						if types["hero"] and isHero
                            or types["monster"] and not isHero and not isSummon
                            or types["summon"] and isSummon
							or next(types) == nil then
							table.insert(candidates, unit2)
						end
					end
				end
				return candidates
			end,
			get_tags = function(target)
				local tags = gameMode.battleManager.enemyTags or {}
				return tags[target:entindex()] or {}
			end,
			was_recently_damaged = function(target, seconds)
				return self.combatMemory:WasDamagedWithin(target, seconds or 3)
			end,
			any_ally_recently_damaged = function(caster2, seconds)
				return self.combatMemory:AnyAllyDamagedWithin(caster2, allies, seconds or 3)
			end,
			get_action_use_count = function(target, logicalId)
				return self.combatMemory:GetActionUseCount(target, resolveActionName(target, logicalId))
			end,
			record_action_order = function(target, logicalId, _)
				local name = resolveActionName(target, logicalId)
                self.combatMemory:RecordActionUse(target, name)
                -- Fresh spawns must not inherit history from recycled entity indices.
                self.lastActionOrders[target] = self.lastActionOrders[target] or {}
                self.lastActionOrders[target][name] = GameRules:GetGameTime()
			end,
			resolve_action_name = resolveActionName,
		}
	end

    self.RecordAuxiliaryAction = function(_, unit, name)
        buildContext(unit).record_action_order(unit, name)
    end

	local conditionsRegistry = Conditions
	local function is_current_lineup_hero(hero, player_id)
		if not is_valid_entity(hero) or hero.benchHeroName ~= nil then
			return false
		end
		if player_id ~= nil and tonumber(player_id) ~= tonumber(gameMode.playerId) then
			return false
		end
		if Snapshot.IsEnemy(gameMode.battleManager, hero) then return Snapshot.IsDeveloperMode() end
        if hero.GetTeamNumber == nil or hero:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then
			return false
		end
		local key = hero.lineupHeroName or (hero.GetUnitName ~= nil and hero:GetUnitName() or nil)
		if key == nil or gameMode.heroData == nil or gameMode.heroData[key] == nil then
			return false
		end
		for _, candidate in ipairs(gameMode.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
			if candidate == hero then
				return true
			end
		end
		return false
	end

	local function resolve_action_name_for_validation(hero, action)
		if action == nil then
			return nil
		end
		if action.kind == "attack" or action.kind == "move" or action.kind == "wait" then
			return action.logical_id
		end
		local logical = tostring(action.logical_id or "")
		return resolveActionName(hero, logical)
	end

	local function is_action_allowed_for_hero(player_id, hero, action)
		if not is_current_lineup_hero(hero, player_id) then
			return false
		end
		if action.kind == "attack" or action.kind == "move" or action.kind == "wait" then
			return true
		end
		local realName = resolve_action_name_for_validation(hero, action)
		if realName == nil or realName == "" then
			return false
		end
        if action.name ~= nil and action.name ~= realName then return false end
        local function canonicalize()
            action.logical_id, action.name = realName, realName
            action.cast_type, action.target_mode, action.aoe_radius = nil, nil, nil
            return true
        end
        if action.kind == "ability" then
            local ability = Context.Call(hero, "FindAbilityByName", realName)
            -- Hidden phase skills and unlearned skills may be configured in
            -- PREPARE. Their availability is checked again at execution time.
            if ability == nil or Context.Call(ability, "IsNull") == true
                or Context.Call(ability, "IsPassive") == true
                or realName:match("^special_bonus") or realName == "generic_hidden" then return false end
            return canonicalize()
        end
		if action.kind == "item" then
			for slot = 0, 8 do
				local item = hero:GetItemInSlot(slot)
				if item ~= nil and not item:IsNull() and item:GetAbilityName() == realName then
                    return canonicalize()
				end
			end
		end
		return false
	end


	self.ruleService = RuleService.new({
		get_phase = getPhase,
		get_hero_key = function(hero)
            return hero ~= nil and Snapshot.HeroKey(gameMode.battleManager, hero) or nil
		end,
		is_roster_hero = function(player_id, hero)
			return is_current_lineup_hero(hero, player_id)
		end,
		find_roster_hero = function(player_id, heroName)
			if heroName == nil then return nil end
			for _, hero in ipairs(gameMode.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS] or {}) do
				if is_current_lineup_hero(hero, player_id) and hero:GetUnitName() == tostring(heroName) then
					return hero
				end
			end
			return nil
		end,
        is_target_actor_allowed = function(_player_id, hero, key)
            return Snapshot.ResolveTargetActor(gameMode.battleManager, gameMode.currentLevelId, hero, key) ~= nil
        end,
		is_action_allowed = is_action_allowed_for_hero,
		state = state,
		conditions = conditionsRegistry,
	})
	self.ruleService:InstallEventListener()

	self.tacticEngine = TacticEngine.new({
		order_gate = orderGate,
		get_phase = getPhase,
		get_battle_units = function()
            local available = {}
            for _, unit in ipairs(getBattleUnits()) do
                if not (gameMode.treeGrabBusy or {})[unit] then available[#available+1] = unit end
            end
            return available
        end,
		get_rules = manager.getRules,
		build_context = buildContext,
		conditions = conditionsRegistry,
		selector = TargetSelector.new(conditionsRegistry),
		actions = ActionAdapter.new(orderGate),
		on_debug = function(unit, event, detail)
			print(string.format("[TacticDebug] %s %s %s", unit:GetUnitName(), event, detail.reason or detail.target_index or ""))
		end,
	})

	-- 订单过滤：内部订单放行；战斗中拒绝玩家订单；准备阶段走排位/换人校验
	self.orderFilter = OrderFilterModule.OrderFilter.new({
		gate = orderGate,
		get_phase = getPhase,
		is_battle_unit = isBattleUnit,
		-- 玩家小精灵与待命英雄不在 battleManager 的战斗名单中，
		-- 仍须受准备阶段的物品转移锁约束。
		is_inventory_unit = function(unit)
			return gameMode:IsEquipmentCarrier(unit)
		end,
		is_managed_order = function(filterTable)
			return gameMode:IsNativeItemShopOrder(filterTable)
		end,
		validate_prepare_order = function(filterTable)
			return gameMode:ValidatePrepareOrder(filterTable)
		end,
		validate_inventory_order = function(filterTable)
			return gameMode:ValidatePrepareOrder(filterTable)
		end,
	})
	self.orderFilter:Install(GameRules:GetGameModeEntity())
end

function TacticBridge:OnThink()
	self.tacticEngine:Think()
end

function TacticBridge:ResetState()
    self.unitObservation = nil
	self.tacticEngine:Reset()
	self.combatMemory:Reset()
    self.lastActionOrders = {}
	self:invalidateRules()
end
