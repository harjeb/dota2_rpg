--[[
	TacticEngine
	规则 = [优先级] IF <条件(value)> THEN <动作> → <目标选择器> [+ 执行模式]

	设计要点（DESIGN.md §2.2 / §5.2）：
	- 条件只做布尔判断，不包含目标选择语义；目标筛选由独立的目标选择器负责。
	- 执行模式：范围内(range_only) / 强制追击(forced)。强制追击仅在条件满足且动作
	  可执行时锁定；目标死亡、动作不可执行、超时或战斗结束即解除。
	- 与 Dota API 解耦：所有引擎/指令调用都经由 adapter 注入，便于离线模拟器复用。
]]

if TacticEngine == nil then
	_G.TacticEngine = class({})
end

local ORDER_RETRY_INTERVAL = 0.25
local CAST_RANGE_BUFFER = 75
local FORCED_CHASE_TIMEOUT = 8.0

local ACTION_KEYS = {
	"ultimate",
	"ability_1",
	"ability_2",
	"ability_3",
	"item_1",
	"item_2",
	"item_3",
	"item_4",
	"item_5",
	"item_6",
	"attack",
}

local VALID_ACTIONS = {
	ultimate = true,
	ability_1 = true,
	ability_2 = true,
	ability_3 = true,
	item_1 = true,
	item_2 = true,
	item_3 = true,
	item_4 = true,
	item_5 = true,
	item_6 = true,
	attack = true,
}

local VALID_CONDITIONS = {
	always = true,
	self_hp_below = true,
	self_mp_above = true,
	enemy_exists = true,
	ally_exists = true,
	enemy_count_ge = true,
	battle_time_ge = true,
	ally_under_attack = true,
	ally_hit_count_ge = true,   -- 连续事件计数：友军受击次数
	ally_death_ge = true,       -- 已阵亡友军数
	none = true,                -- 组合第二槽占位
}

-- 目标选择器组合式 ID：{enemy|ally}_{hp|hp_pct|armor|attack|mr}_{highest|lowest}
-- 特殊：self / enemy_casting / enemy_distance_nearest / enemy_distance_farthest
local TARGET_METRICS = {
	hp = true,
	hp_pct = true,
	armor = true,
	attack = true,
	mr = true,
	-- 标签/状态类目标（敌方限定，忽略 extremum，取最近匹配）
	boss = true,
	healer = true,
	controlled = true,
}

local function splitSelector(selectorId)
	-- Lua 模式不支持 | 交替，分两步解析阵营前缀
	local side = "enemy"
	local rest = string.match(selectorId, "^enemy_(.+)$")
	if rest == nil then
		side = "ally"
		rest = string.match(selectorId, "^ally_(.+)$")
	end
	if rest == nil then
		return nil
	end
	local attr, extremum = string.match(rest, "^(%a+)_(%a+)$")
	if attr == nil then
		return nil
	end
	return side, attr, extremum
end

function TacticEngine.IsValidTarget(selectorId)
	if selectorId == "self" or selectorId == "enemy_casting" then
		return true
	end
	local side, attr, extremum = splitSelector(selectorId)
	if side == nil then
		return false
	end
	if attr == "distance" then
		return extremum == "nearest" or extremum == "farthest"
	end
	return TARGET_METRICS[attr] == true and (extremum == "highest" or extremum == "lowest")
end

function TacticEngine.GetTargetSide(selectorId)
	if selectorId == "self" then
		return "self"
	end
	if string.match(selectorId, "^enemy_") ~= nil then
		return "enemy"
	end
	if string.match(selectorId, "^ally_") ~= nil then
		return "ally"
	end
	return "enemy"
end

local function metricValue(unit, metric)
	if metric == "hp" then
		return unit:GetHealth()
	end
	if metric == "hp_pct" then
		return TacticEngine.HealthPercent(unit)
	end
	if metric == "armor" then
		if unit.GetPhysicalArmorValue ~= nil then
			return unit:GetPhysicalArmorValue(false)
		end
		return unit.GetPhysicalArmorBaseValue ~= nil and unit:GetPhysicalArmorBaseValue() or 0
	end
	if metric == "attack" then
		return unit:GetAttackDamage()
	end
	if metric == "mr" then
		-- 魔抗百分比：数值越大越抗魔
		if unit.GetMagicalArmorValue ~= nil then
			return unit:GetMagicalArmorValue() * 100
		end
		return 25
	end
	return 0
end

local PERCENT_CONDITIONS = {
	self_hp_below = true,
	self_mp_above = true,
}

function TacticEngine:constructor(adapter)
	self.adapter = adapter
	self.conditions = {}
	self:RegisterConditions()
end

-- 条件求值统一入口：conditions[type](ctx, value)
function TacticEngine:RegisterConditions()
	self.conditions.always = function(ctx, value)
		return true
	end
	self.conditions.none = function(ctx, value)
		return true -- 组合条件第二槽未启用
	end
	self.conditions.self_hp_below = function(ctx, value)
		return TacticEngine.HealthPercent(ctx.hero) < value
	end
	self.conditions.self_mp_above = function(ctx, value)
		return TacticEngine.ManaPercent(ctx.hero) >= value
	end
	self.conditions.enemy_exists = function(ctx, value)
		return self:SelectTarget(ctx.hero, ctx.rule, ctx, "enemy") ~= nil
	end
	self.conditions.ally_exists = function(ctx, value)
		return self:SelectTarget(ctx.hero, ctx.rule, ctx, "ally") ~= nil
	end
	self.conditions.enemy_count_ge = function(ctx, value)
		return self:CountAlive(ctx.enemies) >= value
	end
	self.conditions.battle_time_ge = function(ctx, value)
		return (ctx.env.battleTime or 0) >= value
	end
	self.conditions.ally_under_attack = function(ctx, value)
		-- 任意友军最近 3 秒内受到伤害（宿主通过 entity_hurt 事件维护）
		local attacked = ctx.env.recentlyAttackedAllies
		return attacked ~= nil and #attacked > 0
	end
	self.conditions.ally_hit_count_ge = function(ctx, value)
		-- 连续事件计数：友军在受击窗口内被击中次数 ≥ N
		local hits = ctx.env.recentlyAllyHitCount or 0
		return hits >= value
	end
	self.conditions.ally_death_ge = function(ctx, value)
		local deaths = ctx.env.allyDeathCount or 0
		return deaths >= value
	end
end

-- 组合条件求值：rule.conditionList = { {type, value}, ... }，rule.logic = "all"|"any"
function TacticEngine:EvaluateConditionList(rule, ctx)
	local list = rule.conditionList
	if list == nil or #list == 0 then
		-- 兼容旧单条件
		local fn = self.conditions[rule.condition]
		if fn == nil then
			return false
		end
		return fn(ctx, ctx.value) == true
	end
	local function normalizedValue(cond)
		-- 百分比类条件入参为 1..100，统一换算到 0..1
		if PERCENT_CONDITIONS[cond.type] then
			return math.max(0.01, math.min(1, cond.value / 100))
		end
		return cond.value
	end
	if rule.logic == "any" then
		for _, cond in ipairs(list) do
			local fn = self.conditions[cond.type]
			if fn ~= nil and fn(ctx, normalizedValue(cond)) == true then
				return true
			end
		end
		return false
	end
	-- 默认 all（AND）
	for _, cond in ipairs(list) do
		local fn = self.conditions[cond.type]
		if fn == nil then
			return false
		end
		if fn(ctx, normalizedValue(cond)) ~= true then
			return false
		end
	end
	return true
end

-- 组合式目标选择：selectorId -> 单位
function TacticEngine:SelectSelectorTarget(hero, selectorId, units, env)
	if selectorId == "enemy_casting" then
		return self:NearestMatching(hero, units, function(unit)
			return unit:IsChanneling()
		end)
	end

	local side, attr, extremum = splitSelector(selectorId)
	if side == nil then
		return nil
	end

	if attr == "distance" then
		return self:ExtremeUnit(units, "distance", extremum == "nearest", hero)
	end

	-- 标签类目标：Boss/精英、治疗者、被控制的敌人（取最近匹配）
	if attr == "boss" or attr == "healer" or attr == "controlled" then
		local wantedTag = attr == "boss" and "boss" or (attr == "boss" and "elite" or nil)
		local function hasTag(unit)
			local tags = env ~= nil and env.enemyTags ~= nil and env.enemyTags[unit:GetEntityIndex()] or nil
			if tags == nil then
				return false
			end
			for _, tag in ipairs(tags) do
				if attr == "boss" and (tag == "boss" or tag == "elite") then
					return true
				end
				if attr == "healer" and (tag == "healer" or tag == "support") then
					return true
				end
			end
			return false
		end
		if attr == "controlled" then
			return self:NearestMatching(hero, units, function(unit)
				if unit.IsStunned ~= nil and unit:IsStunned() then
					return true
				end
				if unit.IsRooted ~= nil and unit:IsRooted() then
					return true
				end
				return false
			end)
		end
		return self:NearestMatching(hero, units, hasTag)
	end

	return self:ExtremeUnit(units, attr, extremum == "lowest")
end

function TacticEngine.HealthPercent(unit)
	if unit == nil or unit:IsNull() or unit:GetMaxHealth() <= 0 then
		return 1
	end
	return unit:GetHealth() / unit:GetMaxHealth()
end

function TacticEngine.ManaPercent(unit)
	if unit == nil or unit:IsNull() or unit:GetMaxMana() <= 0 then
		return 1
	end
	return unit:GetMana() / unit:GetMaxMana()
end

function TacticEngine:ExtremeUnit(units, metric, wantMinimum, origin)
	local selected = nil
	local bestValue = nil
	for _, unit in ipairs(units or {}) do
		if TacticEngine.IsValidUnit(unit) then
			local value
			if metric == "distance" then
				value = (origin:GetAbsOrigin() - unit:GetAbsOrigin()):Length2D()
			else
				value = metricValue(unit, metric)
			end

			if value ~= nil and (bestValue == nil or (wantMinimum and value < bestValue or not wantMinimum and value > bestValue)) then
				selected = unit
				bestValue = value
			end
		end
	end
	return selected
end

function TacticEngine:CountAlive(units)
	local count = 0
	for _, unit in ipairs(units or {}) do
		if TacticEngine.IsValidUnit(unit) and unit:IsAlive() then
			count = count + 1
		end
	end
	return count
end

function TacticEngine:NearestMatching(origin, units, predicate)
	local selected = nil
	local bestDistance = nil
	for _, unit in ipairs(units or {}) do
		if TacticEngine.IsValidUnit(unit) and predicate(unit) then
			local distance = (origin:GetAbsOrigin() - unit:GetAbsOrigin()):Length2D()
			if bestDistance == nil or distance < bestDistance then
				selected = unit
				bestDistance = distance
			end
		end
	end
	return selected
end

function TacticEngine.IsValidUnit(unit)
	return unit ~= nil and IsValidEntity(unit) and not unit:IsNull()
end

function TacticEngine:ParseRules(payload, prefix, ruleCount, fallbackRules)
	local parsedRules = {}
	local usedActions = {}

	for index = 1, ruleCount do
		local action = tostring(payload[prefix .. "_action_" .. index] or "")
		local condition = tostring(payload[prefix .. "_condition_" .. index] or "")
		local value = tonumber(payload[prefix .. "_value_" .. index]) or 50
		value = math.max(1, math.min(999, math.floor(value + 0.5)))
		local condition2 = tostring(payload[prefix .. "_condition2_" .. index] or "none")
		local value2 = tonumber(payload[prefix .. "_value2_" .. index]) or 50
		value2 = math.max(1, math.min(999, math.floor(value2 + 0.5)))
		local logic = tostring(payload[prefix .. "_logic_" .. index] or "all")
		local target = tostring(payload[prefix .. "_target_" .. index] or "")
		local forced = payload[prefix .. "_forced_" .. index]
		local enabled = payload[prefix .. "_enabled_" .. index]
		if enabled == nil then
			enabled = fallbackRules[index] ~= nil and fallbackRules[index].enabled ~= false or true
		else
			enabled = tonumber(enabled) ~= 0
		end

		if not TacticEngine.IsValidTarget(target) then
			target = fallbackRules[index] ~= nil and fallbackRules[index].target or "enemy_distance_nearest"
		end
		if not VALID_CONDITIONS[condition] then
			condition = fallbackRules[index] ~= nil and fallbackRules[index].condition or "always"
		end

		if not VALID_ACTIONS[action] or usedActions[action] then
			action = nil
			for _, fallbackAction in ipairs(ACTION_KEYS) do
				if not usedActions[fallbackAction] then
					action = fallbackAction
					break
				end
			end
		end
		if action == nil then
			action = "attack"
		end

		if not VALID_CONDITIONS[condition2] then
			condition2 = "none"
		end
		if logic ~= "any" then
			logic = "all"
		end

		-- 组合条件：第二条件为 none 时退化为单条件
		local conditionList = { { type = condition, value = value } }
		if condition2 ~= "none" then
			table.insert(conditionList, { type = condition2, value = value2 })
		end

		usedActions[action] = true
		table.insert(parsedRules, {
			action = action,
			condition = condition,
			conditionList = conditionList,
			logic = logic,
			value = value,
			target = target,
			forced = forced,
			enabled = enabled,
		})
	end

	return parsedRules
end

function TacticEngine:CreateHeroState(teamIndex)
	return {
		teamIndex = teamIndex,
		nextActionAt = 0,
		forcedRuleIndex = nil,
		forcedTargetIndex = nil,
		forcedStartedAt = nil,
	}
end

-- 每次规则评估的环境：单位列表由宿主(BattleManager)提供
function TacticEngine:Think(hero, state, rules, env)
	local now = env.now
	if now < state.nextActionAt then
		return
	end

	if hero:IsChanneling() or hero:GetCurrentActiveAbility() ~= nil then
		state.nextActionAt = now + 0.1
		return
	end

	if state.forcedRuleIndex ~= nil and self:ProcessForcedLock(hero, state, rules, env) then
		return
	end

	for ruleIndex, rule in ipairs(rules) do
		if rule.enabled == false then
			-- 规则被玩家停用（如关闭发球技能）时直接跳过
		else
		local action = self:ResolveAction(hero, rule)
		if action ~= nil then
			local ctx = self:BuildContext(hero, rule, action, env)
			if self:IsActionExecutable(hero, action, rule, ctx) and self:EvaluateConditionList(rule, ctx) then
				if self:ExecuteRule(hero, state, ruleIndex, rule, action, ctx) then
					return
				end
			end
		end
		end
	end

	state.nextActionAt = now + ORDER_RETRY_INTERVAL
end

function TacticEngine:BuildContext(hero, rule, action, env)
	local value = tonumber(rule.value) or 50
	local primaryType = rule.condition
	if rule.conditionList ~= nil and rule.conditionList[1] ~= nil then
		primaryType = rule.conditionList[1].type
	end
	if PERCENT_CONDITIONS[primaryType] then
		value = math.max(0.01, math.min(1, value / 100))
	end
	return {
		hero = hero,
		rule = rule,
		action = action,
		value = value,
		env = env,
		enemies = env.enemies,
		allies = env.allies,
	}
end

function TacticEngine:SelectTarget(hero, rule, ctx, side)
	local selectorId = rule.target
	if selectorId == "self" then
		return hero
	end

	local units
	if side == "enemy" then
		units = ctx.env.enemies
	else
		units = ctx.env.allies
	end
	if units == nil then
		return nil
	end

	-- 范围内模式：只在当前动作有效范围内筛选
	if not rule.forced then
		units = self.adapter:FilterUnitsInActionRange(hero, ctx.action, units)
	end

	return self:SelectSelectorTarget(hero, selectorId, units, ctx.env)
end

function TacticEngine:ResolveAction(hero, rule)
	if rule.action == "attack" then
		return { kind = "attack" }
	end

	local ability = self.adapter:GetActionAbility(hero, rule.action)
	if ability == nil then
		return nil
	end
	return { kind = "ability", ability = ability }
end

function TacticEngine:IsActionExecutable(hero, action, rule, ctx)
	if action.kind == "attack" then
		return true
	end
	return self.adapter:IsAbilityReady(hero, action.ability)
end

function TacticEngine:ExecuteRule(hero, state, ruleIndex, rule, action, ctx)
	local now = ctx.env.now
	if action.kind == "attack" then
		local target = self:SelectTarget(hero, rule, ctx, "enemy")
		if target == nil then
			return false
		end
		return self:PerformAttack(hero, state, ruleIndex, rule, target, ctx)
	end

	local ability = action.ability
	local side = self.adapter:GetAbilityTargetSide(ability)
	-- 目标选择器与技能阵营不匹配时规则不可执行（如对治疗技能选了敌方选择器）
	local selectorSide = TacticEngine.GetTargetSide(rule.target)
	if side == "enemy" and selectorSide ~= nil and selectorSide ~= "enemy" then
		return false
	end
	if side == "ally" and selectorSide == "enemy" then
		return false
	end

	local target
	if side == "self" then
		target = hero
	elseif side == "enemy" then
		target = self:SelectTarget(hero, rule, ctx, "enemy")
	else
		target = self:SelectTarget(hero, rule, ctx, "ally")
	end

	if side ~= "self" and target == nil then
		-- 无目标可选：若能力不需要目标（无目标/AOE），仍可直接施放
		if not self.adapter:IsAbilityNoTarget(ability) then
			return false
		end
		target = nil
	end

	if side == "self" and not self.adapter:IsAbilitySelfCastableAt(hero, ability, target) then
		return false
	end

	local result = self:PerformCast(hero, state, ruleIndex, rule, ability, target, ctx)
	return result
end

function TacticEngine:PerformAttack(hero, state, ruleIndex, rule, target, ctx)
	local now = ctx.env.now
	if not self.adapter:IsUnitInAttackRange(hero, target) then
		if not rule.forced then
			return false
		end
		self:LockForcedRule(hero, state, ruleIndex, target, now)
		self.adapter:OrderAttackMove(hero, target)
		state.nextActionAt = now + ORDER_RETRY_INTERVAL
		return true
	end

	self:ClearForcedLock(state)
	self.adapter:OrderAttackMove(hero, target)
	state.nextActionAt = now + 0.7
	return true
end

function TacticEngine:PerformCast(hero, state, ruleIndex, rule, ability, target, ctx)
	local now = ctx.env.now
	local behavior = self.adapter:GetAbilityBehavior(ability)

	if self.adapter:IsToggleAbility(ability) then
		if self.adapter:GetToggleState(ability) then
			return false
		end
		self:ClearForcedLock(state)
		self.adapter:OrderCastToggle(hero, ability)
		state.nextActionAt = now + math.max(0.65, self.adapter:GetCastPoint(ability) + 0.35)
		return true
	end

	if self.adapter:IsNoTargetAbility(ability) then
		-- 敌方无目标技能（如 AOE）：若强制追击则需要先接近
		if target ~= nil and target ~= hero then
			if not self.adapter:IsUnitInAbilityRange(hero, ability, target) then
				if not rule.forced then
					return false
				end
				self:LockForcedRule(hero, state, ruleIndex, target, now)
				self.adapter:OrderMove(hero, target:GetAbsOrigin())
				state.nextActionAt = now + ORDER_RETRY_INTERVAL
				return true
			end
		end
		self:ClearForcedLock(state)
		self.adapter:OrderCastNoTarget(hero, ability)
		state.nextActionAt = now + math.max(0.65, self.adapter:GetCastPoint(ability) + 0.35)
		return true
	end

	if not TacticEngine.IsValidUnit(target) then
		return false
	end

	if not self.adapter:IsUnitInAbilityRange(hero, ability, target) then
		if not rule.forced then
			return false
		end
		self:LockForcedRule(hero, state, ruleIndex, target, now)
		self.adapter:OrderMove(hero, target:GetAbsOrigin())
		state.nextActionAt = now + ORDER_RETRY_INTERVAL
		return true
	end

	self:ClearForcedLock(state)
	if self.adapter:IsPointTargetAbility(ability) then
		self.adapter:OrderCastPosition(hero, ability, target:GetAbsOrigin())
	else
		self.adapter:OrderCastTarget(hero, ability, target)
	end
	state.nextActionAt = now + math.max(0.65, self.adapter:GetCastPoint(ability) + 0.35)
	return true
end

-- 强制追击锁定：目标死亡/失效/超时时解除，否则继续追击直到动作成功释放
function TacticEngine:ProcessForcedLock(hero, state, rules, env)
	local ruleIndex = state.forcedRuleIndex
	local rule = rules[ruleIndex]
	local target = self:GetForcedTarget(state)

	if rule == nil or not rule.forced or rule.enabled == false or target == nil then
		self:ClearForcedLock(state)
		return false
	end

	if state.forcedStartedAt ~= nil and env.now - state.forcedStartedAt > FORCED_CHASE_TIMEOUT then
		self:ClearForcedLock(state)
		return false
	end

	local action = self:ResolveAction(hero, rule)
	if action == nil then
		self:ClearForcedLock(state)
		return false
	end

	if not self:IsActionExecutable(hero, action, rule, self:BuildContext(hero, rule, action, env)) then
		state.nextActionAt = env.now + ORDER_RETRY_INTERVAL
		return true
	end

	if self:ExecuteRule(hero, state, ruleIndex, rule, action, self:BuildContext(hero, rule, action, env)) then
		-- 若返回 true 但仍处于追击（moving），保持锁定；释放成功时 PerformCast/PerformAttack 已清除
		return true
	end

	self:ClearForcedLock(state)
	return false
end

function TacticEngine:LockForcedRule(hero, state, ruleIndex, target, now)
	if not TacticEngine.IsValidUnit(target) or not target:IsAlive() then
		return
	end
	state.forcedRuleIndex = ruleIndex
	state.forcedTargetIndex = target:GetEntityIndex()
	if state.forcedStartedAt == nil then
		state.forcedStartedAt = now
	end
end

function TacticEngine:ClearForcedLock(state)
	state.forcedRuleIndex = nil
	state.forcedTargetIndex = nil
	state.forcedStartedAt = nil
end

function TacticEngine:GetForcedTarget(state)
	if state.forcedTargetIndex == nil then
		return nil
	end
	local target = EntIndexToHScript(state.forcedTargetIndex)
	if not TacticEngine.IsValidUnit(target) or not target:IsAlive() then
		return nil
	end
	return target
end

function TacticEngine:GetValidConditions()
	return VALID_CONDITIONS
end

