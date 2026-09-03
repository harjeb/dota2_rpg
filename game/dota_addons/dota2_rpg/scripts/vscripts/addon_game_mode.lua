if CDota2RpgDemo == nil then
	_G.CDota2RpgDemo = class({})
end

local PLAYER_PLACEHOLDER_HERO = "npc_dota_hero_wisp"
local HERO_LEVEL = 30
local THINK_INTERVAL = 0.1
local CAST_RANGE_BUFFER = 75
local ORDER_RETRY_INTERVAL = 0.25

local TEAM_ROSTERS = {
	[DOTA_TEAM_GOODGUYS] = {
		"npc_dota_hero_sven",
		"npc_dota_hero_lina",
		"npc_dota_hero_dazzle",
	},
	[DOTA_TEAM_BADGUYS] = {
		"npc_dota_hero_axe",
		"npc_dota_hero_lion",
		"npc_dota_hero_crystal_maiden",
	},
}

local TEAM_SPAWNS = {
	[DOTA_TEAM_GOODGUYS] = {
		Vector(-1100, -650, 128),
		Vector(-1350, 0, 128),
		Vector(-1100, 650, 128),
	},
	[DOTA_TEAM_BADGUYS] = {
		Vector(1100, 650, 128),
		Vector(1350, 0, 128),
		Vector(1100, -650, 128),
	},
}

local PRE_BATTLE_MODIFIERS = {
	"modifier_invulnerable",
	"modifier_rooted",
	"modifier_disarmed",
	"modifier_silence",
}

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
	enemy_below = true,
	self_below = true,
	ally_below = true,
	enemy_in_range = true,
	enemy_highest_hp = true,
	enemy_lowest_hp = true,
	enemy_nearest = true,
	enemy_farthest = true,
	enemy_has_effect = true,
	enemy_lacks_effect = true,
	enemy_channeling = true,
}

local VALID_EFFECTS = {
	magic_immune = true,
	stunned = true,
	silenced = true,
	rooted = true,
}

local DEFAULT_RULES = {
	{ action = "ultimate", condition = "always", threshold = 50, effect = "magic_immune", forced = true },
	{ action = "ability_1", condition = "enemy_below", threshold = 50, effect = "magic_immune", forced = true },
	{ action = "ability_2", condition = "always", threshold = 50, effect = "magic_immune", forced = true },
	{ action = "ability_3", condition = "self_below", threshold = 50, effect = "magic_immune", forced = true },
	{ action = "attack", condition = "always", threshold = 50, effect = "magic_immune", forced = true },
}

local function IsValidUnit(unit)
	return unit ~= nil and IsValidEntity(unit) and not unit:IsNull()
end

local function HasFlag(value, flag)
	return bit.band(value, flag) ~= 0
end

local function HealthPercent(unit)
	if not IsValidUnit(unit) or unit:GetMaxHealth() <= 0 then
		return 1
	end
	return unit:GetHealth() / unit:GetMaxHealth()
end

local function ClampThreshold(value)
	local threshold = math.floor((tonumber(value) or 50) + 0.5)
	return math.max(1, math.min(100, threshold))
end

local function ParseBoolean(value, defaultValue)
	if value == nil then
		return defaultValue
	end
	if type(value) == "boolean" then
		return value
	end

	local normalized = string.lower(tostring(value))
	if normalized == "1" or normalized == "true" or normalized == "yes" or normalized == "on" then
		return true
	end
	if normalized == "0" or normalized == "false" or normalized == "no" or normalized == "off" then
		return false
	end
	return defaultValue
end

local function CloneDefaultRules()
	local rules = {}
	for _, rule in ipairs(DEFAULT_RULES) do
		table.insert(rules, {
			action = rule.action,
			condition = rule.condition,
			threshold = rule.threshold,
			effect = rule.effect,
			forced = rule.forced,
		})
	end
	return rules
end

function Precache(context)
	PrecacheUnitByNameSync(PLAYER_PLACEHOLDER_HERO, context)
	for _, roster in pairs(TEAM_ROSTERS) do
		for _, heroName in ipairs(roster) do
			PrecacheUnitByNameSync(heroName, context)
		end
	end
end

function Activate()
	GameRules.Dota2RpgDemo = CDota2RpgDemo()
	GameRules.Dota2RpgDemo:InitGameMode()
end

function CDota2RpgDemo:InitGameMode()
	local gameMode = GameRules:GetGameModeEntity()

	self.playerId = -1
	self.placeholderHero = nil
	self.phase = "setup"
	self.winner = ""
	self.teamsSpawned = false
	self.teamHeroes = {
		[DOTA_TEAM_GOODGUYS] = {},
		[DOTA_TEAM_BADGUYS] = {},
	}
	self.heroStates = {}
	self.heroRules = {}
	for team, roster in pairs(TEAM_ROSTERS) do
		self.heroRules[team] = {}
		for heroIndex = 1, #roster do
			self.heroRules[team][heroIndex] = CloneDefaultRules()
		end
	end

	gameMode:SetCustomGameForceHero(PLAYER_PLACEHOLDER_HERO)
	gameMode:SetBuybackEnabled(false)
	gameMode:SetDaynightCycleDisabled(true)
	gameMode:SetFogOfWarDisabled(true)
	gameMode:SetUnseenFogOfWarEnabled(false)
	gameMode:SetCameraDistanceOverride(1500)
	gameMode:SetExecuteOrderFilter(Dynamic_Wrap(CDota2RpgDemo, "FilterExecuteOrder"), self)
	gameMode:SetContextThink("Dota2RpgDemoThink", function()
		return self:OnThink()
	end, THINK_INTERVAL)

	GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 1)
	GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
	GameRules:SetCustomGameSetupTimeout(0)
	GameRules:SetHeroSelectionTime(0)
	GameRules:SetStrategyTime(0)
	GameRules:SetShowcaseTime(0)
	GameRules:SetPreGameTime(0)
	GameRules:SetPostGameTime(8)
	GameRules:SetStartingGold(0)
	GameRules:SetUseUniversalShopMode(true)
	if GameRules.SetHeroRespawnEnabled ~= nil then
		GameRules:SetHeroRespawnEnabled(false)
	end

	ListenToGameEvent("player_connect_full", Dynamic_Wrap(CDota2RpgDemo, "OnPlayerConnectFull"), self)
	ListenToGameEvent("npc_spawned", Dynamic_Wrap(CDota2RpgDemo, "OnNpcSpawned"), self)
	ListenToGameEvent("game_rules_state_change", Dynamic_Wrap(CDota2RpgDemo, "OnGameRulesStateChange"), self)
	ListenToGameEvent("entity_killed", Dynamic_Wrap(CDota2RpgDemo, "OnEntityKilled"), self)

	CustomGameEventManager:RegisterListener("rpg_start_battle", function(eventSourceIndex, payload)
		return self:OnStartBattle(eventSourceIndex, payload)
	end)
	CustomGameEventManager:RegisterListener("rpg_request_battle_state", function(eventSourceIndex, payload)
		return self:OnRequestBattleState(eventSourceIndex, payload)
	end)

	PlayerResource:SetCustomTeamAssignment(0, DOTA_TEAM_GOODGUYS)
	print("[Dota2RpgDemo] 3v3 battle mode initialized.")
end

function CDota2RpgDemo:ResolvePlayerId(payload)
	if payload ~= nil then
		local playerId = tonumber(payload.PlayerID)
		if playerId ~= nil and playerId >= 0 then
			return playerId
		end

		local playerIndex = tonumber(payload.index)
		if playerIndex ~= nil then
			local player = EntIndexToHScript(playerIndex)
			if player ~= nil and player.GetPlayerID ~= nil then
				return player:GetPlayerID()
			end
		end
	end

	return self.playerId >= 0 and self.playerId or 0
end

function CDota2RpgDemo:OnPlayerConnectFull(event)
	local playerId = self:ResolvePlayerId(event)
	self.playerId = playerId
	PlayerResource:SetCustomTeamAssignment(playerId, DOTA_TEAM_GOODGUYS)
	self:ScheduleStateBroadcast(0.5)
end

function CDota2RpgDemo:OnNpcSpawned(event)
	local unit = EntIndexToHScript(event.entindex or -1)
	if not IsValidUnit(unit) or not unit:IsRealHero() then
		return
	end

	if unit:GetUnitName() ~= PLAYER_PLACEHOLDER_HERO or unit.rpgPlaceholderReady then
		return
	end

	unit.rpgPlaceholderReady = true
	self.placeholderHero = unit
	self.playerId = math.max(self.playerId, unit:GetPlayerOwnerID())
	unit:SetRespawnsDisabled(true)
	unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
	unit:AddNewModifier(unit, nil, "modifier_rooted", {})
	unit:AddNewModifier(unit, nil, "modifier_disarmed", {})
	unit:AddNewModifier(unit, nil, "modifier_silence", {})
	if unit.AddNoDraw ~= nil then
		unit:AddNoDraw()
	end
	FindClearSpaceForUnit(unit, Vector(-7600, -7600, 128), true)
	self:EnsureBattlefield()
	print(string.format("[Dota2RpgDemo] Hidden placeholder ready for player %d.", self.playerId))
end

function CDota2RpgDemo:OnGameRulesStateChange()
	local state = GameRules:State_Get()
	if state == DOTA_GAMERULES_STATE_PRE_GAME or state == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		self:EnsureBattlefield()
	end
end

function CDota2RpgDemo:EnsureBattlefield()
	if self.teamsSpawned then
		return
	end

	self.teamsSpawned = true
	for team, roster in pairs(TEAM_ROSTERS) do
		for index, heroName in ipairs(roster) do
			local spawnPosition = GetGroundPosition(TEAM_SPAWNS[team][index], nil)
			local hero = CreateUnitByName(heroName, spawnPosition, true, nil, nil, team)
			if IsValidUnit(hero) then
				FindClearSpaceForUnit(hero, spawnPosition, true)
				self:PrepareBattleHero(hero)
				table.insert(self.teamHeroes[team], hero)
				self.heroStates[hero:GetEntityIndex()] = {
					nextActionAt = 0,
					teamIndex = index,
					forcedRuleIndex = nil,
					forcedTargetIndex = nil,
				}
			else
				print(string.format("[Dota2RpgDemo] Failed to spawn %s.", heroName))
			end
		end
	end

	local cameraTarget = self.teamHeroes[DOTA_TEAM_GOODGUYS][2] or self.teamHeroes[DOTA_TEAM_GOODGUYS][1]
	if self.playerId >= 0 and IsValidUnit(cameraTarget) then
		PlayerResource:SetCameraTarget(self.playerId, cameraTarget)
		GameRules:GetGameModeEntity():SetContextThink("ReleaseRpgBattleCamera", function()
			PlayerResource:SetCameraTarget(self.playerId, nil)
			return nil
		end, 0.5)
	end

	self:BroadcastBattleState()
	print("[Dota2RpgDemo] Spawned three level-30 heroes for each team.")
end

function CDota2RpgDemo:PrepareBattleHero(hero)
	while hero:GetLevel() < HERO_LEVEL do
		hero:HeroLevelUp(false)
	end

	for slot = 0, hero:GetAbilityCount() - 1 do
		local ability = hero:GetAbilityByIndex(slot)
		if ability ~= nil and not ability:IsNull() then
			local abilityName = ability:GetAbilityName()
			local isTalent = string.find(abilityName, "special_bonus", 1, true) ~= nil
			if not isTalent and ability:GetMaxLevel() > 0 then
				ability:SetLevel(ability:GetMaxLevel())
			end
		end
	end

	hero:SetAbilityPoints(0)
	hero:SetRespawnsDisabled(true)
	hero:SetHealth(hero:GetMaxHealth())
	hero:SetMana(hero:GetMaxMana())
	hero:SetIdleAcquire(false)
	hero:SetAcquisitionRange(0)

	for _, modifierName in ipairs(PRE_BATTLE_MODIFIERS) do
		hero:AddNewModifier(hero, nil, modifierName, {})
	end
end

function CDota2RpgDemo:FilterExecuteOrder(filterTable)
	local issuerPlayerId = tonumber(filterTable.issuer_player_id_const) or -1
	if issuerPlayerId >= 0 then
		return false
	end
	return true
end

function CDota2RpgDemo:OnRequestBattleState(eventSourceIndex, payload)
	local playerId = self:ResolvePlayerId(payload)
	local player = PlayerResource:GetPlayer(playerId)
	if player ~= nil then
		CustomGameEventManager:Send_ServerToPlayer(player, "rpg_battle_state", self:BuildBattleState())
	end
end

function CDota2RpgDemo:OnStartBattle(eventSourceIndex, payload)
	if self.phase ~= "setup" or not self.teamsSpawned then
		return
	end

	local battlePayload = payload or {}
	for team, roster in pairs(TEAM_ROSTERS) do
		local teamPrefix = team == DOTA_TEAM_GOODGUYS and "radiant" or "dire"
		for heroIndex = 1, #roster do
			local heroPrefix = string.format("%s_hero_%d", teamPrefix, heroIndex)
			self.heroRules[team][heroIndex] = self:ParseRules(battlePayload, heroPrefix)
		end
	end
	self.phase = "battle"

	local now = GameRules:GetGameTime()
	for _, heroes in pairs(self.teamHeroes) do
		for index, hero in ipairs(heroes) do
			if IsValidUnit(hero) and hero:IsAlive() then
				for _, modifierName in ipairs(PRE_BATTLE_MODIFIERS) do
					hero:RemoveModifierByName(modifierName)
				end
				hero:SetHealth(hero:GetMaxHealth())
				hero:SetMana(hero:GetMaxMana())
				hero:SetIdleAcquire(true)
				hero:SetAcquisitionRange(2400)
				local heroState = self.heroStates[hero:GetEntityIndex()]
				heroState.nextActionAt = now + 0.15 + (index * 0.08)
				self:ClearForcedRule(heroState)
			end
		end
	end

	self:BroadcastBattleState()
	print("[Dota2RpgDemo] Battle started with player-configured rules.")
end

function CDota2RpgDemo:ParseRules(payload, prefix)
	local parsedRules = {}
	local usedActions = {}

	for index = 1, #ACTION_KEYS do
		local action = tostring(payload[prefix .. "_action_" .. index] or "")
		local condition = tostring(payload[prefix .. "_condition_" .. index] or "")
		local threshold = ClampThreshold(payload[prefix .. "_threshold_" .. index])
		local effect = tostring(payload[prefix .. "_effect_" .. index] or "")
		local forced = ParseBoolean(payload[prefix .. "_forced_" .. index], true)
		if not VALID_ACTIONS[action] or usedActions[action] then
			action = nil
			for _, fallbackAction in ipairs(ACTION_KEYS) do
				if not usedActions[fallbackAction] then
					action = fallbackAction
					break
				end
			end
		end
		if not VALID_CONDITIONS[condition] then
			condition = "always"
		end
		if not VALID_EFFECTS[effect] then
			effect = "magic_immune"
		end

		usedActions[action] = true
		table.insert(parsedRules, {
			action = action,
			condition = condition,
			threshold = threshold,
			effect = effect,
			forced = forced,
		})
	end

	return parsedRules
end

function CDota2RpgDemo:OnEntityKilled(event)
	if self.phase ~= "battle" then
		return
	end

	local killed = EntIndexToHScript(event.entindex_killed or -1)
	if not IsValidUnit(killed) then
		return
	end

	if self.heroStates[killed:GetEntityIndex()] ~= nil then
		self:ScheduleStateBroadcast(0.05)
	end
end

function CDota2RpgDemo:OnThink()
	if not self.teamsSpawned then
		local state = GameRules:State_Get()
		if state >= DOTA_GAMERULES_STATE_PRE_GAME then
			self:EnsureBattlefield()
		end
	end

	if self.phase ~= "battle" then
		return THINK_INTERVAL
	end

	if self:CheckVictory() then
		return THINK_INTERVAL
	end

	local now = GameRules:GetGameTime()
	for team, heroes in pairs(self.teamHeroes) do
		for _, hero in ipairs(heroes) do
			if IsValidUnit(hero) and hero:IsAlive() then
				self:ThinkHero(team, hero, now)
			end
		end
	end

	return THINK_INTERVAL
end

function CDota2RpgDemo:ClearForcedRule(state)
	if state == nil then
		return
	end
	state.forcedRuleIndex = nil
	state.forcedTargetIndex = nil
end

function CDota2RpgDemo:SetForcedRule(state, ruleIndex, target)
	if state == nil or not IsValidUnit(target) or not target:IsAlive() then
		return
	end
	state.forcedRuleIndex = ruleIndex
	state.forcedTargetIndex = target:GetEntityIndex()
end

function CDota2RpgDemo:GetForcedTarget(state)
	if state == nil or state.forcedTargetIndex == nil then
		return nil
	end
	local target = EntIndexToHScript(state.forcedTargetIndex)
	if not IsValidUnit(target) or not target:IsAlive() then
		return nil
	end
	return target
end

function CDota2RpgDemo:ApplyActionResult(state, ruleIndex, result, target, now, ability)
	if result == "moving" then
		self:SetForcedRule(state, ruleIndex, target)
		state.nextActionAt = now + ORDER_RETRY_INTERVAL
		return true
	end

	self:ClearForcedRule(state)
	if result == "cast" then
		state.nextActionAt = now + math.max(0.65, ability:GetCastPoint() + 0.35)
		return true
	end
	if result == "attack" then
		state.nextActionAt = now + 0.7
		return true
	end
	return false
end

function CDota2RpgDemo:ThinkHero(team, hero, now)
	local state = self.heroStates[hero:GetEntityIndex()]
	if state == nil or now < state.nextActionAt then
		return
	end

	if hero:IsChanneling() or hero:GetCurrentActiveAbility() ~= nil then
		state.nextActionAt = now + THINK_INTERVAL
		return
	end

	local rules = self.heroRules[team] and self.heroRules[team][state.teamIndex]
	rules = rules or DEFAULT_RULES

	if state.forcedRuleIndex ~= nil then
		local ruleIndex = state.forcedRuleIndex
		local rule = rules[ruleIndex]
		local target = self:GetForcedTarget(state)
		if rule == nil or not rule.forced or target == nil then
			self:ClearForcedRule(state)
		else
			local ability = rule.action == "attack" and nil or self:GetActionAbility(hero, rule.action)
			local result = "skip"
			local actionTarget = target
			if rule.action == "attack" then
				result, actionTarget = self:IssueAttackOrder(hero, target, true)
			else
				if not self:IsAbilityReady(hero, ability) then
					state.nextActionAt = now + ORDER_RETRY_INTERVAL
					return
				end
				result, actionTarget = self:IssueAbilityOrder(team, hero, ability, rule, target)
			end

			if self:ApplyActionResult(state, ruleIndex, result, actionTarget, now, ability) then
				return
			end
		end
	end

	for ruleIndex, rule in ipairs(rules) do
		local ability = rule.action == "attack" and nil or self:GetActionAbility(hero, rule.action)
		local actionReady = rule.action == "attack" or self:IsAbilityReady(hero, ability)
		if actionReady and self:EvaluateCondition(team, hero, rule, ability) then
			local result = "skip"
			local target = nil
			if rule.action == "attack" then
				target = self:SelectEnemyTarget(team, hero, rule, nil)
				result, target = self:IssueAttackOrder(hero, target, rule.forced)
			else
				result, target = self:IssueAbilityOrder(team, hero, ability, rule, nil)
			end

			if self:ApplyActionResult(state, ruleIndex, result, target, now, ability) then
				return
			end
		end
	end

	state.nextActionAt = now + ORDER_RETRY_INTERVAL
end

function CDota2RpgDemo:EvaluateCondition(team, hero, rule, ability)
	local condition = rule.condition
	local threshold = ClampThreshold(rule.threshold) / 100
	if condition == "always" then
		return true
	end
	if condition == "self_below" then
		return HealthPercent(hero) < threshold
	end
	if condition == "enemy_below" then
		return self:SelectEnemyTarget(team, hero, rule, ability) ~= nil
	end
	if condition == "ally_below" then
		return self:SelectFriendlyTarget(team, hero, rule, ability) ~= nil
	end
	return self:SelectEnemyTarget(team, hero, rule, ability) ~= nil
end

function CDota2RpgDemo:GetEnemyTeam(team)
	if team == DOTA_TEAM_GOODGUYS then
		return DOTA_TEAM_BADGUYS
	end
	return DOTA_TEAM_GOODGUYS
end

function CDota2RpgDemo:GetEnemyHeroes(team)
	return self.teamHeroes[self:GetEnemyTeam(team)]
end

function CDota2RpgDemo:GetLowestHealthUnit(units, threshold)
	local selected = nil
	local selectedPercent = 2
	for _, unit in ipairs(units or {}) do
		if IsValidUnit(unit) and unit:IsAlive() then
			local percent = HealthPercent(unit)
			if (threshold == nil or percent < threshold) and percent < selectedPercent then
				selected = unit
				selectedPercent = percent
			end
		end
	end
	return selected
end

function CDota2RpgDemo:GetHighestHealthUnit(units)
	local selected = nil
	local selectedPercent = -1
	for _, unit in ipairs(units or {}) do
		if IsValidUnit(unit) and unit:IsAlive() then
			local percent = HealthPercent(unit)
			if percent > selectedPercent then
				selected = unit
				selectedPercent = percent
			end
		end
	end
	return selected
end

function CDota2RpgDemo:GetNearestUnit(origin, units)
	local selected = nil
	local selectedDistance = nil
	for _, unit in ipairs(units or {}) do
		if IsValidUnit(unit) and unit:IsAlive() then
			local distance = (origin - unit:GetAbsOrigin()):Length2D()
			if selectedDistance == nil or distance < selectedDistance then
				selected = unit
				selectedDistance = distance
			end
		end
	end
	return selected
end

function CDota2RpgDemo:GetFarthestUnit(origin, units)
	local selected = nil
	local selectedDistance = -1
	for _, unit in ipairs(units or {}) do
		if IsValidUnit(unit) and unit:IsAlive() then
			local distance = (origin - unit:GetAbsOrigin()):Length2D()
			if distance > selectedDistance then
				selected = unit
				selectedDistance = distance
			end
		end
	end
	return selected
end

function CDota2RpgDemo:GetNearestMatchingUnit(origin, units, predicate)
	local matchingUnits = {}
	for _, unit in ipairs(units or {}) do
		if IsValidUnit(unit) and unit:IsAlive() and predicate(unit) then
			table.insert(matchingUnits, unit)
		end
	end
	return self:GetNearestUnit(origin, matchingUnits)
end

function CDota2RpgDemo:UnitHasEffect(unit, effect)
	if not IsValidUnit(unit) then
		return false
	end
	if effect == "magic_immune" then
		local debuffImmune = unit.IsDebuffImmune ~= nil and unit:IsDebuffImmune()
		return debuffImmune or unit:IsMagicImmune()
	end
	if effect == "stunned" then
		return unit.IsStunned ~= nil and unit:IsStunned()
	end
	if effect == "silenced" then
		return unit.IsSilenced ~= nil and unit:IsSilenced()
	end
	if effect == "rooted" then
		return unit.IsRooted ~= nil and unit:IsRooted()
	end
	return false
end

function CDota2RpgDemo:IsUnitWithinActionRange(hero, ability, action, unit)
	if not IsValidUnit(unit) then
		return false
	end

	local distance = (hero:GetAbsOrigin() - unit:GetAbsOrigin()):Length2D()
	if action == "attack" then
		local attackRange = 150
		if hero.Script_GetAttackRange ~= nil then
			attackRange = tonumber(hero:Script_GetAttackRange()) or attackRange
		elseif hero.GetAttackRange ~= nil then
			attackRange = tonumber(hero:GetAttackRange()) or attackRange
		end
		return distance <= attackRange + CAST_RANGE_BUFFER
	end

	if ability == nil or ability:IsNull() then
		return false
	end

	local behavior = ability:GetBehaviorInt()
	if HasFlag(behavior, DOTA_ABILITY_BEHAVIOR_NO_TARGET) then
		local radius = ability:GetAOERadius()
		if radius <= 0 then
			radius = 600
		end
		return distance <= radius + CAST_RANGE_BUFFER
	end

	local castRange = ability:GetCastRange(hero:GetAbsOrigin(), unit)
	if castRange <= 0 then
		local radius = ability:GetAOERadius()
		castRange = radius > 0 and radius or 600
	end
	return distance <= castRange + CAST_RANGE_BUFFER
end

function CDota2RpgDemo:GetUnitsInActionRange(hero, ability, action, units)
	local inRange = {}
	for _, unit in ipairs(units or {}) do
		if IsValidUnit(unit) and unit:IsAlive() and self:IsUnitWithinActionRange(hero, ability, action, unit) then
			table.insert(inRange, unit)
		end
	end
	return inRange
end

function CDota2RpgDemo:SelectEnemyTarget(team, hero, rule, ability)
	local enemies = self:GetEnemyHeroes(team)
	local condition = rule.condition
	if not rule.forced or condition == "enemy_in_range" then
		enemies = self:GetUnitsInActionRange(hero, ability, rule.action, enemies)
	end
	if condition == "enemy_below" then
		return self:GetLowestHealthUnit(enemies, ClampThreshold(rule.threshold) / 100)
	end
	if condition == "enemy_highest_hp" then
		return self:GetHighestHealthUnit(enemies)
	end
	if condition == "enemy_lowest_hp" then
		return self:GetLowestHealthUnit(enemies, nil)
	end
	if condition == "enemy_farthest" then
		return self:GetFarthestUnit(hero:GetAbsOrigin(), enemies)
	end
	if condition == "enemy_in_range" then
		return self:GetNearestUnit(hero:GetAbsOrigin(), enemies)
	end
	if condition == "enemy_has_effect" then
		return self:GetNearestMatchingUnit(hero:GetAbsOrigin(), enemies, function(enemy)
			return self:UnitHasEffect(enemy, rule.effect)
		end)
	end
	if condition == "enemy_lacks_effect" then
		return self:GetNearestMatchingUnit(hero:GetAbsOrigin(), enemies, function(enemy)
			return not self:UnitHasEffect(enemy, rule.effect)
		end)
	end
	if condition == "enemy_channeling" then
		return self:GetNearestMatchingUnit(hero:GetAbsOrigin(), enemies, function(enemy)
			return enemy:IsChanneling()
		end)
	end
	return self:GetNearestUnit(hero:GetAbsOrigin(), enemies)
end

function CDota2RpgDemo:SelectFriendlyTarget(team, hero, rule, ability)
	local condition = rule.condition
	if condition == "self_below" then
		return hero
	end

	local friendlies = self.teamHeroes[team]
	if not rule.forced then
		friendlies = self:GetUnitsInActionRange(hero, ability, rule.action, friendlies)
	end
	if condition == "ally_below" then
		return self:GetLowestHealthUnit(friendlies, ClampThreshold(rule.threshold) / 100)
	end
	return self:GetLowestHealthUnit(friendlies, nil) or hero
end

function CDota2RpgDemo:GetActionAbility(hero, action)
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

function CDota2RpgDemo:IsAbilityReady(hero, ability)
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

function CDota2RpgDemo:IssueAttackOrder(hero, target, forced)
	if not IsValidUnit(target) or not target:IsAlive() then
		return "skip", nil
	end

	if not self:IsUnitWithinActionRange(hero, nil, "attack", target) then
		if not forced then
			return "skip", target
		end
		hero:MoveToTargetToAttack(target)
		return "moving", target
	end

	hero:MoveToTargetToAttack(target)
	return "attack", target
end

function CDota2RpgDemo:IssueAbilityOrder(team, hero, ability, rule, lockedTarget)
	local behavior = ability:GetBehaviorInt()
	local targetTeam = ability:GetAbilityTargetTeam()
	local targetsEnemy = HasFlag(targetTeam, DOTA_UNIT_TARGET_TEAM_ENEMY)
	local targetsFriendly = HasFlag(targetTeam, DOTA_UNIT_TARGET_TEAM_FRIENDLY)
	local validLockedTarget = IsValidUnit(lockedTarget) and lockedTarget:IsAlive()
	local enemy = validLockedTarget and targetsEnemy and lockedTarget or self:SelectEnemyTarget(team, hero, rule, ability)
	local friendly = validLockedTarget and targetsFriendly and not targetsEnemy and lockedTarget or self:SelectFriendlyTarget(team, hero, rule, ability)

	if HasFlag(behavior, DOTA_ABILITY_BEHAVIOR_TOGGLE) then
		if ability.GetToggleState ~= nil and ability:GetToggleState() then
			return "skip", nil
		end
		ExecuteOrderFromTable({
			UnitIndex = hero:GetEntityIndex(),
			OrderType = DOTA_UNIT_ORDER_CAST_TOGGLE,
			AbilityIndex = ability:GetEntityIndex(),
			Queue = false,
			IssuerPlayerID = -1,
		})
		return "cast", nil
	end

	if HasFlag(behavior, DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) then
		local target = targetsEnemy and enemy or friendly
		if not IsValidUnit(target) or not target:IsAlive() then
			return "skip", nil
		end
		if not self:IsWithinCastRange(hero, ability, target:GetAbsOrigin(), target) then
			if not rule.forced then
				return "skip", target
			end
			hero:MoveToPosition(target:GetAbsOrigin())
			return "moving", target
		end
		ExecuteOrderFromTable({
			UnitIndex = hero:GetEntityIndex(),
			OrderType = DOTA_UNIT_ORDER_CAST_TARGET,
			TargetIndex = target:GetEntityIndex(),
			AbilityIndex = ability:GetEntityIndex(),
			Queue = false,
			IssuerPlayerID = -1,
		})
		return "cast", target
	end

	if HasFlag(behavior, DOTA_ABILITY_BEHAVIOR_POINT) then
		local target = targetsEnemy and enemy or friendly
		if not IsValidUnit(target) then
			return "skip", nil
		end
		local position = target:GetAbsOrigin()
		if not self:IsWithinCastRange(hero, ability, position, target) then
			if not rule.forced then
				return "skip", target
			end
			hero:MoveToPosition(position)
			return "moving", target
		end
		ExecuteOrderFromTable({
			UnitIndex = hero:GetEntityIndex(),
			OrderType = DOTA_UNIT_ORDER_CAST_POSITION,
			Position = position,
			AbilityIndex = ability:GetEntityIndex(),
			Queue = false,
			IssuerPlayerID = -1,
		})
		return "cast", target
	end

	if HasFlag(behavior, DOTA_ABILITY_BEHAVIOR_NO_TARGET) then
		if targetsEnemy and IsValidUnit(enemy) then
			local radius = ability:GetAOERadius()
			if radius <= 0 then
				radius = 600
			end
			local distance = (hero:GetAbsOrigin() - enemy:GetAbsOrigin()):Length2D()
			if distance > radius + CAST_RANGE_BUFFER then
				if not rule.forced then
					return "skip", enemy
				end
				hero:MoveToPosition(enemy:GetAbsOrigin())
				return "moving", enemy
			end
		elseif targetsEnemy then
			return "skip", nil
		end

		ExecuteOrderFromTable({
			UnitIndex = hero:GetEntityIndex(),
			OrderType = DOTA_UNIT_ORDER_CAST_NO_TARGET,
			AbilityIndex = ability:GetEntityIndex(),
			Queue = false,
			IssuerPlayerID = -1,
		})
		return "cast", enemy
	end

	if targetsFriendly and IsValidUnit(friendly) then
		return "skip", friendly
	end
	return "skip", nil
end

function CDota2RpgDemo:IsWithinCastRange(hero, ability, position, target)
	local castRange = ability:GetCastRange(hero:GetAbsOrigin(), target)
	if castRange <= 0 then
		return true
	end
	local distance = (hero:GetAbsOrigin() - position):Length2D()
	return distance <= castRange + CAST_RANGE_BUFFER
end

function CDota2RpgDemo:GetAliveCount(team)
	local count = 0
	for _, hero in ipairs(self.teamHeroes[team] or {}) do
		if IsValidUnit(hero) and hero:IsAlive() then
			count = count + 1
		end
	end
	return count
end

function CDota2RpgDemo:CheckVictory()
	local radiantAlive = self:GetAliveCount(DOTA_TEAM_GOODGUYS)
	local direAlive = self:GetAliveCount(DOTA_TEAM_BADGUYS)
	if radiantAlive > 0 and direAlive > 0 then
		return false
	end

	if radiantAlive == 0 and direAlive == 0 then
		self:EndBattle("draw", nil)
	elseif direAlive == 0 then
		self:EndBattle("radiant", DOTA_TEAM_GOODGUYS)
	else
		self:EndBattle("dire", DOTA_TEAM_BADGUYS)
	end
	return true
end

function CDota2RpgDemo:EndBattle(winner, winnerTeam)
	if self.phase ~= "battle" then
		return
	end

	self.phase = "result"
	self.winner = winner
	for _, heroes in pairs(self.teamHeroes) do
		for _, hero in ipairs(heroes) do
			if IsValidUnit(hero) and hero:IsAlive() then
				hero:Stop()
				hero:SetIdleAcquire(false)
			end
		end
	end
	self:BroadcastBattleState()

	if winnerTeam ~= nil then
		GameRules:GetGameModeEntity():SetContextThink("Dota2RpgDeclareWinner", function()
			GameRules:SetGameWinner(winnerTeam)
			return nil
		end, 1.0)
	end
	print(string.format("[Dota2RpgDemo] Battle finished. Result=%s", winner))
end

function CDota2RpgDemo:BuildBattleState()
	return {
		phase = self.phase,
		ready = self.teamsSpawned and 1 or 0,
		radiant_alive = self:GetAliveCount(DOTA_TEAM_GOODGUYS),
		dire_alive = self:GetAliveCount(DOTA_TEAM_BADGUYS),
		winner = self.winner,
	}
end

function CDota2RpgDemo:BroadcastBattleState()
	CustomGameEventManager:Send_ServerToAllClients("rpg_battle_state", self:BuildBattleState())
end

function CDota2RpgDemo:ScheduleStateBroadcast(delay)
	GameRules:GetGameModeEntity():SetContextThink(DoUniqueString("Dota2RpgState"), function()
		self:BroadcastBattleState()
		return nil
	end, delay or 0)
end
