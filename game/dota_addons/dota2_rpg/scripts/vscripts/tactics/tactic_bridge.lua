-- tactic_bridge.lua
-- 桥接层：把现有 BattleManager/规则负载接入修订版战术模块
-- （rule_service / condition_registry / target_selector / tactic_engine / order_filter / combat_memory）

local Conditions = require("tactics/condition_registry")
local TargetSelector = require("tactics/target_selector")
local ActionAdapter = require("tactics/action_adapter")
local OrderFilterModule = require("tactics/order_filter")
local CombatMemory = require("tactics/combat_memory")
local TacticEngine = require("tactics/tactic_engine")
local RuleService = require("tactics/rule_service")

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
	elseif string.match(id, "_mr_lowest$") ~= nil then
		table.insert(priorities, { type = "lowest_magic_resistance" })
	end

	if string.match(id, "_distance_nearest$") ~= nil then
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_distance_farthest$") ~= nil then
		table.insert(priorities, { type = "farthest" })
	end

	if string.match(id, "_casting$") ~= nil then
		table.insert(filters, { type = "is_channeling" })
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_boss$") ~= nil then
		table.insert(filters, { type = "has_tag", value = "boss" })
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_healer$") ~= nil then
		table.insert(filters, { type = "has_tag", value = "healer" })
		table.insert(priorities, { type = "nearest" })
	elseif string.match(id, "_controlled$") ~= nil then
		table.insert(filters, { type = "is_stunned" })
		table.insert(priorities, { type = "nearest" })
	end

	if #priorities == 0 then
		table.insert(priorities, { type = "nearest" })
	end
	return t, filters, priorities
end

-- 旧条件 ID -> 修订版 use_condition（无法映射的返回 nil = 无条件）
local function mapLegacyCondition(conditionType, value)
	local v = tonumber(value) or 50
	if conditionType == "always" or conditionType == "none" then
		return nil
	end
	if conditionType == "self_hp_below" then
		return { type = "self_hp_pct_lte", value = v / 100 }
	end
	if conditionType == "self_mp_above" then
		return { type = "self_mana_pct_gte", value = v / 100 }
	end
	if conditionType == "enemy_count_ge" then
		return { type = "alive_enemy_count_gte", value = v }
	end
	if conditionType == "battle_time_ge" then
		return { type = "elapsed_gte", value = v }
	end
	if conditionType == "ally_under_attack" then
		return { type = "any_ally_recently_damaged", seconds = 3 }
	end
	if conditionType == "ally_hit_count_ge" then
		return { type = "any_ally_recently_damaged", seconds = 5 }
	end
	if conditionType == "ally_death_ge" then
		return { type = "dead_ally_count_gte", value = v }
	end
	-- enemy_exists / ally_exists：由目标选择失败自然表达，不需要使用条件
	return nil
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

	local useConditions = {}
	local primary = mapLegacyCondition(legacy.condition, legacy.value)
	if primary ~= nil then
		table.insert(useConditions, primary)
	end
	if legacy.condition2 ~= nil and legacy.condition2 ~= "none" then
		local secondary = mapLegacyCondition(legacy.condition2, legacy.value2)
		if secondary ~= nil then
			table.insert(useConditions, secondary)
		end
	end

	return {
		id = tostring(legacy.id or ("legacy_rule_" .. slot)),
		enabled = legacy.enabled ~= false,
		action = {
			kind = actionKind,
			logical_id = logicalId,
			target_team = "enemy",
		},
		target = target,
		target_filters = filters,
		target_priorities = priorities,
		use_conditions = useConditions,
		approach = legacy.forced and "allow_approach" or "range_only",
	}
end

function TacticBridge.new(options)
	return setmetatable({
		gameMode = assert(options.game_mode, "game_mode is required"),
	}, TacticBridge)
end

function TacticBridge:Install()
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
		if not TacticEngine.IsValidUnit(unit) then
			return false
		end
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
				if ability ~= nil and not ability:IsNull() and ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
					return ability:GetAbilityName()
				end
			end
			return ""
		end
		local abilitySlot = tonumber(string.match(logicalId, "ability_(%d)"))
		if abilitySlot ~= nil then
			local ability = unit:GetAbilityByIndex(abilitySlot - 1)
			return ability ~= nil and not ability:IsNull() and ability:GetAbilityName() or ""
		end
		local itemSlot = tonumber(string.match(logicalId, "item_(%d)"))
		if itemSlot ~= nil and unit.GetItemInSlot ~= nil then
			local item = unit:GetItemInSlot(itemSlot - 1)
			return item ~= nil and not item:IsNull() and item:GetAbilityName() or ""
		end
		return logicalId
	end

	local state = { rules = {} }

	-- 旧负载规则（heroRulesByName）-> 修订版结构，缓存于桥接层
	function manager.getRules(unit)
		local cache = state.rules[unit:entindex()]
		if cache ~= nil then
			return cache
		end
		local heroName = unit:GetUnitName()
		local legacyRules = gameMode.heroRulesByName[heroName] or {}
		local converted = {}
		for slot, legacy in ipairs(legacyRules) do
			if legacy.enabled ~= false then
				table.insert(converted, TacticBridge.ConvertLegacyRule(slot, legacy))
			end
		end
		state.rules[unit:entindex()] = converted
		return converted
	end

	function manager.invalidateRules()
		state.rules = {}
	end

	local function buildContext(unit)
		local team = unit:GetTeamNumber()
		local enemies = gameMode.battleManager.teamHeroes[gameMode.battleManager:GetEnemyTeam(team)] or {}
		local allies = gameMode.battleManager.teamHeroes[team] or {}
		return {
			caster = unit,
			allies = allies,
			enemies = enemies,
			elapsed = gameMode.battleManager:GetBattleTime(),
			enemy_tags = gameMode.battleManager.enemyTags,
			combat_memory = self.combatMemory,
			resolve_action_name = resolveActionName,
			record_action_order = function(_, logicalId, _)
				self.combatMemory:RecordActionUse(unit, logicalId)
			end,
		}
	end

	local conditionsRegistry = Conditions
	-- 扩展：敌人数 ≥ N（注册表原本只有 lte）
	conditionsRegistry:RegisterUseCondition("alive_enemy_count_gte", function(ctx, condition)
		local value = tonumber(condition.value) or 0
		local enemies = ctx.enemies or {}
		local alive = 0
		for _, unit in ipairs(enemies) do
			if unit ~= nil and unit.IsAlive ~= nil and unit:IsAlive() then
				alive = alive + 1
			end
		end
		return alive >= value
	end)

	self.ruleService = RuleService.new({
		get_phase = getPhase,
		is_roster_hero = function(_, hero)
			return TacticEngine.IsValidUnit(hero)
		end,
		is_action_allowed = function(_, _, _)
			return true -- 动作合法性由槽位生成时保证
		end,
		state = state,
		conditions = conditionsRegistry,
	})

	self.tacticEngine = TacticEngine.new({
		order_gate = orderGate,
		get_phase = getPhase,
		get_battle_units = getBattleUnits,
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
	self.orderFilter = OrderFilterModule.new({
		gate = orderGate,
		get_phase = getPhase,
		is_battle_unit = isBattleUnit,
		validate_prepare_order = function(filterTable)
			return gameMode:ValidatePrepareOrder(filterTable)
		end,
	})
	self.orderFilter:Install(GameRules:GetGameModeEntity())
end

function TacticBridge:OnThink()
	self.tacticEngine:Think()
end

function TacticBridge:ResetState()
	self.tacticEngine:Reset()
	self.combatMemory:Reset()
	self:invalidateRules()
end
