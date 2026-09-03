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
	"attack",
}

local VALID_ACTIONS = {
	ultimate = true,
	ability_1 = true,
	ability_2 = true,
	ability_3 = true,
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
}

local VALID_TARGETS = {
	enemy_hp_lowest = true,
	enemy_hp_pct_lowest = true,
	enemy_hp_highest = true,
	enemy_hp_pct_highest = true,
	enemy_nearest = true,
	enemy_farthest = true,
	enemy_attack_highest = true,
	enemy_casting = true,
	ally_hp_lowest = true,
	ally_hp_pct_lowest = true,
	self = true,
}

local TARGET_SIDE = {
	enemy_hp_lowest = "enemy",
	enemy_hp_pct_lowest = "enemy",
	enemy_hp_highest = "enemy",
	enemy_hp_pct_highest = "enemy",
	enemy_nearest = "enemy",
	enemy_farthest = "enemy",
	enemy_attack_highest = "enemy",
	enemy_casting = "enemy",
	ally_hp_lowest = "ally",
	ally_hp_pct_lowest = "ally",
	self = "self",
}

local PERCENT_CONDITIONS = {
	self_hp_below = true,
	self_mp_above = true,
}

function TacticEngine:constructor(adapter)
	self.adapter = adapter
	self.conditions = {}
	self.targets = {}
	self:RegisterConditions()
	self:RegisterTargets()
end

function TacticEngine:RegisterConditions()
	self.conditions.always = function(ctx)
		return true
	end
	self.conditions.self_hp_below = function(ctx)
		return TacticEngine.HealthPercent(ctx.hero) < ctx.value
	end
	self.conditions.self_mp_above = function(ctx)
		return TacticEngine.ManaPercent(ctx.hero) >= ctx.value
	end
	self.conditions.enemy_exists = function(ctx)
		return self:SelectTarget(ctx.hero, ctx.rule, ctx, "enemy") ~= nil
	end
	self.conditions.ally_exists = function(ctx)
		return self:SelectTarget(ctx.hero, ctx.rule, ctx, "ally") ~= nil
	end
	self.conditions.enemy_count_ge = function(ctx)
		return self:CountAlive(ctx.enemies) >= ctx.value
	end
	self.conditions.battle_time_ge = function(ctx)
		return (ctx.env.battleTime or 0) >= ctx.value
	end
end

function TacticEngine:RegisterTargets()
	self.targets.enemy_hp_lowest = function(ctx)
		return self:ExtremeUnit(ctx.units, "hp", true)
	end
	self.targets.enemy_hp_pct_lowest = function(ctx)
		return self:ExtremeUnit(ctx.units, "hp_pct", true)
	end
	self.targets.enemy_hp_highest = function(ctx)
		return self:ExtremeUnit(ctx.units, "hp", false)
	end
	self.targets.enemy_hp_pct_highest = function(ctx)
		return self:ExtremeUnit(ctx.units, "hp_pct", false)
	end
	self.targets.enemy_nearest = function(ctx)
		return self:ExtremeUnit(ctx.units, "distance", true, ctx.hero)
	end
	self.targets.enemy_farthest = function(ctx)
		return self:ExtremeUnit(ctx.units, "distance", false, ctx.hero)
	end
	self.targets.enemy_attack_highest = function(ctx)
		return self:ExtremeUnit(ctx.units, "attack", false)
	end
	self.targets.enemy_casting = function(ctx)
		return self:NearestMatching(ctx.hero, ctx.units, function(unit)
			return unit:IsChanneling()
		end)
	end
	self.targets.ally_hp_lowest = function(ctx)
		return self:ExtremeUnit(ctx.units, "hp", true)
	end
	self.targets.ally_hp_pct_lowest = function(ctx)
		return self:ExtremeUnit(ctx.units, "hp_pct", true)
	end
	self.targets.self = function(ctx)
		return ctx.hero
	end
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
			if metric == "hp" then
				value = unit:GetHealth()
			elseif metric == "hp_pct" then
				value = TacticEngine.HealthPercent(unit)
			elseif metric == "attack" then
				value = unit:GetAttackDamage()
			elseif metric == "distance" then
				value = (origin:GetAbsOrigin() - unit:GetAbsOrigin()):Length2D()
			end

			if value ~= nil and (bestValue == nil or (wantMinimum and value < bestValue or not wantMinimum and value > bestValue)) then
				selected = unit
				bestValue = value
			end
		end
	end
	return selected
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
		local target = tostring(payload[prefix .. "_target_" .. index] or "")
		local forced = payload[prefix .. "_forced_" .. index]

		if not VALID_TARGETS[target] then
			target = fallbackRules[index] ~= nil and fallbackRules[index].target or "enemy_nearest"
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

		usedActions[action] = true
		table.insert(parsedRules, {
			action = action,
			condition = condition,
			value = value,
			target = target,
			forced = forced,
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
		local action = self:ResolveAction(hero, rule)
		if action ~= nil then
			local ctx = self:BuildContext(hero, rule, action, env)
			if self:IsActionExecutable(hero, action, rule, ctx) and self.conditions[rule.condition](ctx) then
				if self:ExecuteRule(hero, state, ruleIndex, rule, action, ctx) then
					return
				end
			end
		end
	end

	state.nextActionAt = now + ORDER_RETRY_INTERVAL
end

function TacticEngine:BuildContext(hero, rule, action, env)
	local value = tonumber(rule.value) or 50
	if PERCENT_CONDITIONS[rule.condition] then
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
		units = self.adapter.FilterUnitsInActionRange(hero, ctx.action, units)
	end

	local selector = self.targets[selectorId]
	if selector == nil then
		return nil
	end
	return selector({ hero = hero, units = units, rule = rule, env = ctx.env })
end

function TacticEngine:ResolveAction(hero, rule)
	if rule.action == "attack" then
		return { kind = "attack" }
	end

	local ability = self.adapter.GetActionAbility(hero, rule.action)
	if ability == nil then
		return nil
	end
	return { kind = "ability", ability = ability }
end

function TacticEngine:IsActionExecutable(hero, action, rule, ctx)
	if action.kind == "attack" then
		return true
	end
	return self.adapter.IsAbilityReady(hero, action.ability)
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
	local side = self.adapter.GetAbilityTargetSide(ability)
	-- 目标选择器与技能阵营不匹配时规则不可执行（如对治疗技能选了敌方选择器）
	local selectorSide = TARGET_SIDE[rule.target]
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
		if not self.adapter.IsAbilityNoTarget(ability) then
			return false
		end
		target = nil
	end

	if side == "self" and not self.adapter.IsAbilitySelfCastableAt(hero, ability, target) then
		return false
	end

	local result = self:PerformCast(hero, state, ruleIndex, rule, ability, target, ctx)
	return result
end

function TacticEngine:PerformAttack(hero, state, ruleIndex, rule, target, ctx)
	local now = ctx.env.now
	if not self.adapter.IsUnitInAttackRange(hero, target) then
		if not rule.forced then
			return false
		end
		self:LockForcedRule(hero, state, ruleIndex, target, now)
		self.adapter.OrderAttackMove(hero, target)
		state.nextActionAt = now + ORDER_RETRY_INTERVAL
		return true
	end

	self:ClearForcedLock(state)
	self.adapter.OrderAttackMove(hero, target)
	state.nextActionAt = now + 0.7
	return true
end

function TacticEngine:PerformCast(hero, state, ruleIndex, rule, ability, target, ctx)
	local now = ctx.env.now
	local behavior = self.adapter.GetAbilityBehavior(ability)

	if self.adapter.IsToggleAbility(ability) then
		if self.adapter.GetToggleState(ability) then
			return false
		end
		self:ClearForcedLock(state)
		self.adapter.OrderCastToggle(hero, ability)
		state.nextActionAt = now + math.max(0.65, self.adapter.GetCastPoint(ability) + 0.35)
		return true
	end

	if self.adapter.IsNoTargetAbility(ability) then
		-- 敌方无目标技能（如 AOE）：若强制追击则需要先接近
		if target ~= nil and target ~= hero then
			if not self.adapter.IsUnitInAbilityRange(hero, ability, target) then
				if not rule.forced then
					return false
				end
				self:LockForcedRule(hero, state, ruleIndex, target, now)
				self.adapter.OrderMove(hero, target:GetAbsOrigin())
				state.nextActionAt = now + ORDER_RETRY_INTERVAL
				return true
			end
		end
		self:ClearForcedLock(state)
		self.adapter.OrderCastNoTarget(hero, ability)
		state.nextActionAt = now + math.max(0.65, self.adapter.GetCastPoint(ability) + 0.35)
		return true
	end

	if not TacticEngine.IsValidUnit(target) then
		return false
	end

	if not self.adapter.IsUnitInAbilityRange(hero, ability, target) then
		if not rule.forced then
			return false
		end
		self:LockForcedRule(hero, state, ruleIndex, target, now)
		self.adapter.OrderMove(hero, target:GetAbsOrigin())
		state.nextActionAt = now + ORDER_RETRY_INTERVAL
		return true
	end

	self:ClearForcedLock(state)
	if self.adapter.IsPointTargetAbility(ability) then
		self.adapter.OrderCastPosition(hero, ability, target:GetAbsOrigin())
	else
		self.adapter.OrderCastTarget(hero, ability, target)
	end
	state.nextActionAt = now + math.max(0.65, self.adapter.GetCastPoint(ability) + 0.35)
	return true
end

-- 强制追击锁定：目标死亡/失效/超时时解除，否则继续追击直到动作成功释放
function TacticEngine:ProcessForcedLock(hero, state, rules, env)
	local ruleIndex = state.forcedRuleIndex
	local rule = rules[ruleIndex]
	local target = self:GetForcedTarget(state)

	if rule == nil or not rule.forced or target == nil then
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

function TacticEngine:GetValidTargets()
	return VALID_TARGETS
end

function TacticEngine:GetTargetSide(selectorId)
	return TARGET_SIDE[selectorId] or "enemy"
end
