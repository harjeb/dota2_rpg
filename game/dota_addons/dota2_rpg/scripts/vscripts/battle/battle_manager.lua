--[[
	BattleManager
	状态机：PREPARE(setup) → FIGHT(battle) → SETTLE(result)

	职责：
	- 生成/清点双方单位，驱动 TacticEngine 每 tick 评估规则；
	- 实现 TacticEngine 所需的 Dota adapter（指令/射程/行为封装）；
	- 胜负判定（全灭或超时判负）与结算广播。
]]

if BattleManager == nil then
	_G.BattleManager = class({})
end

local BATTLE_TIME_LIMIT = 120.0

function BattleManager:constructor(gameMode)
	self.gameMode = gameMode
	self.phase = "prepare"
	self.battleStartedAt = nil
	self.heroStates = {}
	self.teamHeroes = {
		[DOTA_TEAM_GOODGUYS] = {},
		[DOTA_TEAM_BADGUYS] = {},
	}
	self.teamRules = {
		[DOTA_TEAM_GOODGUYS] = {},
		[DOTA_TEAM_BADGUYS] = {},
	}
	self.tacticEngine = TacticEngine(self)
end

function BattleManager:SetPhase(phase)
	self.phase = phase
end

function BattleManager:RegisterHero(team, teamIndex, hero)
	table.insert(self.teamHeroes[team], hero)
	self.heroStates[hero:GetEntityIndex()] = self.tacticEngine:CreateHeroState(teamIndex)
end

function BattleManager:StartBattle(rulesByTeam)
	self.teamRules = rulesByTeam
	self.battleStartedAt = GameRules:GetGameTime()

	local now = GameRules:GetGameTime()
	for team, heroes in pairs(self.teamHeroes) do
		for index, hero in ipairs(heroes) do
			if TacticEngine.IsValidUnit(hero) and hero:IsAlive() then
				local state = self.heroStates[hero:GetEntityIndex()]
				state.nextActionAt = now + 0.15 + (index * 0.08)
				self.tacticEngine:ClearForcedLock(state)
			end
		end
	end
	self.phase = "fight"
end

function BattleManager:StopBattle()
	self.phase = "settle"
	for _, heroes in pairs(self.teamHeroes) do
		for _, hero in ipairs(heroes) do
			if TacticEngine.IsValidUnit(hero) and hero:IsAlive() then
				hero:Stop()
				hero:SetIdleAcquire(false)
			end
		end
	end
end

function BattleManager:GetBattleTime()
	if self.battleStartedAt == nil or self.phase ~= "fight" then
		return 0
	end
	return GameRules:GetGameTime() - self.battleStartedAt
end

function BattleManager:GetTimeRemaining()
	return math.max(0, BATTLE_TIME_LIMIT - self:GetBattleTime())
end

function BattleManager:GetAliveCount(team)
	local count = 0
	for _, hero in ipairs(self.teamHeroes[team] or {}) do
		if TacticEngine.IsValidUnit(hero) and hero:IsAlive() then
			count = count + 1
		end
	end
	return count
end

function BattleManager:OnThink()
	if self.phase ~= "fight" then
		return
	end

	if self:CheckBattleEnd() then
		return
	end

	local now = GameRules:GetGameTime()
	for team, heroes in pairs(self.teamHeroes) do
		local enemies = self.teamHeroes[self:GetEnemyTeam(team)]
		local allies = heroes
		for _, hero in ipairs(heroes) do
			if TacticEngine.IsValidUnit(hero) and hero:IsAlive() then
				local state = self.heroStates[hero:GetEntityIndex()]
				local rules = self.teamRules[team][state.teamIndex]
				local env = {
					now = now,
					battleTime = self:GetBattleTime(),
					enemies = enemies,
					allies = allies,
				}
				self.tacticEngine:Think(hero, state, rules, env)
			end
		end
	end
end

function BattleManager:GetEnemyTeam(team)
	if team == DOTA_TEAM_GOODGUYS then
		return DOTA_TEAM_BADGUYS
	end
	return DOTA_TEAM_GOODGUYS
end

function BattleManager:CheckBattleEnd()
	local radiantAlive = self:GetAliveCount(DOTA_TEAM_GOODGUYS)
	local direAlive = self:GetAliveCount(DOTA_TEAM_BADGUYS)
	if radiantAlive > 0 and direAlive > 0 then
		if self:GetTimeLeft() <= 0 then
			-- 超时判负（DESIGN.md §2.3：防拖时间 loop 局）
			self.gameMode:EndBattle("timeout", DOTA_TEAM_BADGUYS)
			return true
		end
		return false
	end

	if radiantAlive == 0 and direAlive == 0 then
		self.gameMode:EndBattle("draw", nil)
	elseif direAlive == 0 then
		self.gameMode:EndBattle("radiant", DOTA_TEAM_GOODGUYS)
	else
		self.gameMode:EndBattle("dire", DOTA_TEAM_BADGUYS)
	end
	return true
end

function BattleManager:GetTimeLeft()
	if self.battleStartedAt == nil or self.phase ~= "fight" then
		return BATTLE_TIME_LIMIT
	end
	return math.max(0, BATTLE_TIME_LIMIT - (GameRules:GetGameTime() - self.battleStartedAt))
end

------------------------------------------------------------------
-- TacticEngine adapter（Dota API 封装，离线模拟器可替换本层）
------------------------------------------------------------------

local CAST_RANGE_BUFFER = 75

function BattleManager:GetActionAbility(hero, action)
	if action == "attack" then
		return nil
	end

	if action == "ultimate" then
		for slot = 0, hero:GetAbilityCount() - 1 do
			local ability = hero:GetAbilityByIndex(slot)
			if ability ~= nil and not ability:IsNull() and ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
				return ability
			end
		end
		return nil
	end

	local abilitySlot = tonumber(string.match(action, "ability_(%d)"))
	if abilitySlot == nil then
		return nil
	end
	return hero:GetAbilityByIndex(abilitySlot - 1)
end

function BattleManager:IsAbilityReady(hero, ability)
	if ability == nil or ability:IsNull() then
		return false
	end
	if ability:GetLevel() <= 0 or ability:IsHidden() or ability:IsPassive() then
		return false
	end
	if ability:GetCooldownTimeRemaining() > 0.05 then
		return false
	end
	if ability.IsOwnersManaEnough ~= nil and not ability:IsOwnersManaEnough() then
		return false
	end
	if ability.IsFullyCastable ~= nil and not ability:IsFullyCastable() then
		return false
	end
	return hero:IsAlive()
end

function BattleManager:GetAbilityBehavior(ability)
	return ability:GetBehaviorInt()
end

function BattleManager:IsUnitTargetAbility(ability)
	return bit.band(self:GetAbilityBehavior(ability), DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) ~= 0
end

function BattleManager:IsPointTargetAbility(ability)
	return bit.band(self:GetAbilityBehavior(ability), DOTA_ABILITY_BEHAVIOR_POINT) ~= 0
end

function BattleManager:IsNoTargetAbility(ability)
	return bit.band(self:GetAbilityBehavior(ability), DOTA_ABILITY_BEHAVIOR_NO_TARGET) ~= 0
end

function BattleManager:IsToggleAbility(ability)
	return bit.band(self:GetAbilityBehavior(ability), DOTA_ABILITY_BEHAVIOR_TOGGLE) ~= 0
end

function BattleManager:GetToggleState(ability)
	return ability.GetToggleState ~= nil and ability:GetToggleState() or false
end

function BattleManager:GetCastPoint(ability)
	return ability:GetCastPoint() or 0
end

function BattleManager:GetAbilityTargetSide(ability)
	local targetTeam = ability:GetAbilityTargetTeam()
	if ability:IsPassive() then
		return "self"
	end
	if bit.band(targetTeam, DOTA_UNIT_TARGET_TEAM_ENEMY) ~= 0 then
		return "enemy"
	end
	if bit.band(targetTeam, DOTA_UNIT_TARGET_TEAM_FRIENDLY) ~= 0 then
		return "ally"
	end
	if bit.band(self:GetAbilityBehavior(ability), DOTA_ABILITY_BEHAVIOR_NO_TARGET) ~= 0
		or bit.band(self:GetAbilityBehavior(ability), DOTA_ABILITY_BEHAVIOR_TOGGLE) ~= 0 then
		return "self"
	end
	return "enemy"
end

-- "self" 目标选择器只要求英雄存活即可施放（无目标/自身技能）
function BattleManager:IsAbilitySelfCastableAt(hero, ability, target)
	return hero:IsAlive()
end

function BattleManager:IsUnitInAbilityRange(hero, ability, target)
	local distance = (hero:GetAbsOrigin() - target:GetAbsOrigin()):Length2D()
	local castRange = ability:GetCastRange(hero:GetAbsOrigin(), target)
	if castRange <= 0 then
		local radius = ability:GetAOERadius()
		castRange = radius > 0 and radius or 600
	end
	return distance <= castRange + CAST_RANGE_BUFFER
end

function BattleManager:IsUnitInAttackRange(hero, target)
	local attackRange = 150
	if hero.Script_GetAttackRange ~= nil then
		attackRange = tonumber(hero:Script_GetAttackRange()) or attackRange
	elseif hero.GetAttackRange ~= nil then
		attackRange = tonumber(hero:GetAttackRange()) or attackRange
	end
	local distance = (hero:GetAbsOrigin() - target:GetAbsOrigin()):Length2D()
	return distance <= attackRange + CAST_RANGE_BUFFER
end

function BattleManager:FilterUnitsInActionRange(hero, action, units)
	local inRange = {}
	for _, unit in ipairs(units or {}) do
		if TacticEngine.IsValidUnit(unit) and unit:IsAlive() then
			if action.kind == "attack" then
				if self:IsUnitInAttackRange(hero, unit) then
					table.insert(inRange, unit)
				end
			elseif self:IsUnitInAbilityRange(hero, action.ability, unit) then
				table.insert(inRange, unit)
			end
		end
	end
	return inRange
end

function BattleManager:OrderAttackMove(hero, target)
	hero:MoveToTargetToAttack(target)
end

function BattleManager:OrderMove(hero, position)
	hero:MoveToPosition(position)
end

function BattleManager:OrderCastTarget(hero, ability, target)
	ExecuteOrderFromTable({
		UnitIndex = hero:GetEntityIndex(),
		OrderType = DOTA_UNIT_ORDER_CAST_TARGET,
		TargetIndex = target:GetEntityIndex(),
		AbilityIndex = ability:GetEntityIndex(),
		Queue = false,
		IssuerPlayerID = -1,
	})
end

function BattleManager:OrderCastPosition(hero, ability, position)
	ExecuteOrderFromTable({
		UnitIndex = hero:GetEntityIndex(),
		OrderType = DOTA_UNIT_ORDER_CAST_POSITION,
		Position = position,
		AbilityIndex = ability:GetEntityIndex(),
		Queue = false,
		IssuerPlayerID = -1,
	})
end

function BattleManager:OrderCastNoTarget(hero, ability)
	ExecuteOrderFromTable({
		UnitIndex = hero:GetEntityIndex(),
		OrderType = DOTA_UNIT_ORDER_CAST_NO_TARGET,
		AbilityIndex = ability:GetEntityIndex(),
		Queue = false,
		IssuerPlayerID = -1,
	})
end

function BattleManager:OrderCastToggle(hero, ability)
	ExecuteOrderFromTable({
		UnitIndex = hero:GetEntityIndex(),
		OrderType = DOTA_UNIT_ORDER_CAST_TOGGLE,
		AbilityIndex = ability:GetEntityIndex(),
		Queue = false,
		IssuerPlayerID = -1,
	})
end