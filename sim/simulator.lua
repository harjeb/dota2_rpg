--[[
	simulator.lua
	离线批量战斗模拟器（DESIGN.md §5.5）：
	- 复用 battle/tactic_engine.lua 的规则评估（同一套代码）；
	- SimAdapter 用 SimUnit 模型实现 adapter 接口并结算伤害；
	- run_battle(config) 返回 { winner, duration, survivors }。

	独立运行自检：lua simulator.lua  或通过 lupa 驱动调用 run_battle。
]]

-- 载入 mock 环境与引擎（路径相对本文件）
local thisDir = string.sub(debug.getinfo(1, "S").source, 2):match("^(.*)/") or "."
package.path = thisDir .. "/?.lua;" .. package.path

require("mock_env")
require("sim_units")

local engineSrc = dofile(thisDir .. "/../game/dota_addons/dota2_rpg/scripts/vscripts/battle/tactic_engine.lua")

DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3

local function vdist2(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function getDist(hero, unit)
	return vdist2(hero:GetAbsOrigin(), unit:GetAbsOrigin())
end

local function getUnitAttackRange(unit)
	local attackRange = unit:Script_GetAttackRange()
	return tonumber(attackRange) or 150
end

-- 把规则里的 action 名映射到模拟单位的技能实例
local function resolveActionAbility(unit, action)
	if action == "attack" then
		return nil
	end
	if action == "ultimate" then
		for _, ability in ipairs(unit.abilities) do
			if ability:GetAbilityType() == 1 then
				return ability
			end
		end
		return nil
	end
	local slot = tonumber(string.match(action, "ability_(%d)"))
	if slot == nil then
		return nil
	end
	for _, ability in ipairs(unit.abilities) do
		if ability:GetAbilityType() ~= 1 and ability.name == "ability_" .. slot then
			return ability
		end
	end
	return nil
end

local function getAbilityTargetSide(ability)
	if ability:IsPassive() then
		return "self"
	end
	if bit.band(ability:GetAbilityTargetTeam(), DOTA_UNIT_TARGET_TEAM_ENEMY) ~= 0 then
		return "enemy"
	end
	if bit.band(ability:GetAbilityTargetTeam(), DOTA_UNIT_TARGET_TEAM_FRIENDLY) ~= 0 then
		return "ally"
	end
	return "self"
end

SimAdapter = {}

function SimAdapter:GetActionAbility(unit, action)
	return resolveActionAbility(unit, action)
end

function SimAdapter:IsAbilityReady(unit, ability)
	if ability == nil then
		return false
	end
	if ability:GetLevel() <= 0 or ability:IsHidden() or ability:IsPassive() then
		return false
	end
	if ability:GetCooldownTimeRemaining() > 0.05 then
		return false
	end
	if ability:IsFullyCastable() and unit:GetMana() >= ability.manaCost then
		return true
	end
	return false
end

function SimAdapter:GetAbilityBehavior(ability) return ability:GetBehaviorInt() end

function SimAdapter:IsUnitTargetAbility(ability)
	return bit.band(ability:GetBehaviorInt(), DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) ~= 0
end

function SimAdapter:IsPointTargetAbility(ability)
	return bit.band(ability:GetBehaviorInt(), DOTA_ABILITY_BEHAVIOR_POINT) ~= 0
end

function SimAdapter:IsNoTargetAbility(ability)
	return bit.band(ability:GetBehaviorInt(), DOTA_ABILITY_BEHAVIOR_NO_TARGET) ~= 0
end

function SimAdapter:IsToggleAbility(ability)
	return bit.band(ability:GetBehaviorInt(), DOTA_ABILITY_BEHAVIOR_TOGGLE) ~= 0
end

function SimAdapter:GetToggleState(_) return false end
function SimAdapter:GetCastPoint(ability) return ability:GetCastPoint() end

function SimAdapter:IsAbilityNoTarget(ability)
	return self:IsNoTargetAbility(ability)
end
function SimAdapter:GetAbilityTargetSide(ability) return getAbilityTargetSide(ability) end
function SimAdapter:IsAbilitySelfCastableAt(_, _) return true end

function SimAdapter:IsUnitInAbilityRange(unit, ability, target)
	local distance = getDist(unit, target)
	local castRange = ability:GetCastRange(unit:GetAbsOrigin(), target)
	if castRange <= 0 then
		castRange = ability:GetAOERadius() > 0 and ability:GetAOERadius() or 600
	end
	return distance <= castRange + 75
end

function SimAdapter:IsUnitInAttackRange(unit, target)
	return getDist(unit, target) <= getUnitAttackRange(unit) + 75
end

function SimAdapter:FilterUnitsInActionRange(hero, action, units)
	local inRange = {}
	for _, unit in ipairs(units or {}) do
		if TacticEngine.IsValidUnit(unit) and unit:IsAlive() then
			local ok
			if action.kind == "attack" then
				ok = self:IsUnitInAttackRange(hero, unit)
			else
				ok = self:IsUnitInAbilityRange(hero, action.ability, unit)
			end
			if ok then
				table.insert(inRange, unit)
			end
		end
	end
	return inRange
end

function SimAdapter:OrderAttackMove(hero, target)
	hero.attackTarget = target
	hero.moveTarget = nil
end

function SimAdapter:OrderMove(hero, position)
	hero.moveTarget = position
	hero.attackTarget = nil
end

function SimAdapter:OrderCastTarget(hero, ability, target)
	ability.cooldownEnd = SimClock + ability.cooldown
	hero:ConsumeMana(ability.manaCost)
	hero:StartChannel(ability.castPoint)
	target:TakeDamage(ability.damage)
end

function SimAdapter:OrderCastPosition(hero, ability, position)
	ability.cooldownEnd = SimClock + ability.cooldown
	hero:ConsumeMana(ability.manaCost)
	hero:StartChannel(ability.castPoint)
	-- 模拟 AOE：伤害落点 250 半径内所有敌人
	for _, unit in ipairs(_G.SIM_ALL_UNITS or {}) do
		if unit:IsAlive() and unit.team ~= hero.team and vdist2(position, unit:GetAbsOrigin()) <= 250 then
			unit:TakeDamage(ability.damage)
		end
	end
end

function SimAdapter:OrderCastNoTarget(hero, ability)
	ability.cooldownEnd = SimClock + ability.cooldown
	hero:ConsumeMana(ability.manaCost)
	hero:StartChannel(ability.castPoint)
	local radius = math.max(250, ability:GetAOERadius())
	for _, unit in ipairs(_G.SIM_ALL_UNITS or {}) do
		if unit:IsAlive() and unit.team ~= hero.team and getDist(hero, unit) <= radius then
			unit:TakeDamage(ability.damage)
		end
	end
end

function SimAdapter:OrderCastToggle(hero, ability)
	ability.cooldownEnd = SimClock + 1
end

local function cloneRules(rules)
	local out = {}
	for _, rule in ipairs(rules or {}) do
		table.insert(out, {
			action = rule.action,
			condition = rule.condition,
			value = tonumber(rule.value) or 50,
			target = rule.target,
			forced = rule.forced == true,
		})
	end
	return out
end

-- config = { team_a = {units[], rules[]}, team_b = {...}, max_time }
-- units: {{name, position={x,y}, maxHealth, attackDamage, attackRange, abilities=[{...}], team}}
function run_battle(config)
	ResetSimClock()
	SimEntityLookup = {}
	_G.SIM_ALL_UNITS = {}

	local teams = { [DOTA_TEAM_GOODGUYS] = {}, [DOTA_TEAM_BADGUYS] = {} }
	local function buildTeam(defs, team)
		local units = {}
		for _, def in ipairs(defs or {}) do
			def.team = team
			local unit = SimUnit.new(def)
			table.insert(units, unit)
			table.insert(_G.SIM_ALL_UNITS, unit)
		end
		teams[team] = units
		return units
	end

	buildTeam(config.team_a and config.team_a.units or {}, DOTA_TEAM_GOODGUYS)
	buildTeam(config.team_b and config.team_b.units or {}, DOTA_TEAM_BADGUYS)

	local rulesByTeam = {
		[DOTA_TEAM_GOODGUYS] = {},
		[DOTA_TEAM_BADGUYS] = {},
	}
	for index, rules in ipairs(config.team_a and config.team_a.rules or {}) do
		rulesByTeam[DOTA_TEAM_GOODGUYS][index] = cloneRules(rules)
	end
	for index, rules in ipairs(config.team_b and config.team_b.rules or {}) do
		rulesByTeam[DOTA_TEAM_BADGUYS][index] = cloneRules(rules)
	end

	local tacticEngine = TacticEngine(SimAdapter)
	local states = {}
	local function buildStates(units, team)
		for index, unit in ipairs(units) do
			states[unit:GetEntityIndex()] = tacticEngine:CreateHeroState(index)
		end
	end
	buildStates(teams[DOTA_TEAM_GOODGUYS], DOTA_TEAM_GOODGUYS)
	buildStates(teams[DOTA_TEAM_BADGUYS], DOTA_TEAM_BADGUYS)

	local function aliveCount(team)
		local count = 0
		for _, unit in ipairs(teams[team]) do
			if unit:IsAlive() then
				count = count + 1
			end
		end
		return count
	end

	local maxTime = config.max_time or 120
	local dt = 0.2
	local elapsed = 0

	while elapsed < maxTime do
		StepWorld(dt)
		elapsed = SimClock

		if aliveCount(DOTA_TEAM_GOODGUYS) == 0 or aliveCount(DOTA_TEAM_BADGUYS) == 0 then
			break
		end

		for team = DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS do
			local enemies = teams[team == DOTA_TEAM_GOODGUYS and DOTA_TEAM_BADGUYS or DOTA_TEAM_GOODGUYS]
			for _, unit in ipairs(teams[team]) do
				if unit:IsAlive() then
					local state = states[unit:GetEntityIndex()]
					local env = {
						now = SimClock,
						battleTime = elapsed,
						enemies = enemies,
						allies = teams[team],
					}
					tacticEngine:Think(unit, state, rulesByTeam[team][state.teamIndex], env)
				end
			end
		end

		-- 表现层：各单位执行移动/攻击
		for _, unit in ipairs(_G.SIM_ALL_UNITS) do
			unit:Step(dt)
		end
	end

	local result = {
		winner = "timeout",
		duration = elapsed,
		survivors = {},
	}
	if aliveCount(DOTA_TEAM_BADGUYS) == 0 and aliveCount(DOTA_TEAM_GOODGUYS) == 0 then
		result.winner = "draw"
	elseif aliveCount(DOTA_TEAM_BADGUYS) == 0 then
		result.winner = "team_a"
	elseif aliveCount(DOTA_TEAM_GOODGUYS) == 0 then
		result.winner = "team_b"
	end
	for team, label in pairs({ [DOTA_TEAM_GOODGUYS] = "team_a", [DOTA_TEAM_BADGUYS] = "team_b" }) do
		for _, unit in ipairs(teams[team]) do
			if unit:IsAlive() then
				table.insert(result.survivors, { name = unit.name, hp = unit.health, team = label })
			end
		end
	end
	return result
end

-- 自检：最简单的互殴 + 一条集火规则
if SIM_SELFTEST ~= false then
	local melee = {
		name = "sim_melee",
		position = Vector(-300, 0),
		maxHealth = 1200,
		attackDamage = 90,
		attackRange = 150,
		abilities = {},
	}
	local caster = {
		name = "sim_caster",
		position = Vector(-500, 0),
		maxHealth = 900,
		attackDamage = 45,
		attackRange = 500,
		abilities = {
			{ name = "ability_1", castRange = 600, damage = 300, manaCost = 90, cooldown = 5, behavior = DOTA_ABILITY_BEHAVIOR_NO_TARGET },
			{ name = "ability_2", castRange = 600, damage = 220, manaCost = 120, cooldown = 8, behavior = DOTA_ABILITY_BEHAVIOR_NO_TARGET, isUltimate = true },
		},
	}

	local rulesA = {
		{ action = "ultimate", condition = "enemy_count_ge", value = 1, target = "enemy_hp_pct_lowest", forced = true },
		{ action = "ability_1", condition = "enemy_exists", target = "enemy_armor_lowest", forced = false },
		{ action = "attack", condition = "always", target = "enemy_distance_nearest", forced = true },
	}
	local rulesB = {
		{ action = "attack", condition = "always", target = "enemy_distance_nearest", forced = false },
	}

	local teamB = {
		{ name = "sim_brute", position = Vector(300, 0), maxHealth = 1500, attackDamage = 70, attackRange = 150, abilities = {} },
	}

	local result = run_battle({
		team_a = { units = { melee, caster }, rules = { rulesA, rulesA } },
		team_b = { units = teamB, rules = { rulesB } },
		max_time = 60,
	})

	print(string.format("[simulator] selftest winner=%s duration=%.1f survivors=%d",
		result.winner, result.duration, #result.survivors))
	for _, survivor in ipairs(result.survivors) do
		print(string.format("  %s (%s) hp=%d", survivor.name, survivor.team, survivor.hp))
	end

	-- 批量模式示例：同一配置重复 N 次统计胜率
	local runs, winsA = 20, 0
	for _ = 1, runs do
		local batchResult = run_battle({
			team_a = { units = { melee, caster }, rules = { rulesA, rulesA } },
			team_b = { units = teamB, rules = { rulesB } },
			max_time = 60,
		})
		if batchResult.winner == "team_a" then
			winsA = winsA + 1
		end
	end
	print(string.format("[simulator] batch: team_a winrate=%d%% (%d runs)", math.floor(winsA / runs * 100 + 0.5), runs))
end

return {
	run_battle = run_battle,
	SimAdapter = SimAdapter,
	SimUnit = SimUnit,
	SimAbility = SimAbility,
}
