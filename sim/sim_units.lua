--[[
	sim_units.lua
	模拟单位：英雄/野怪的最小战斗模型（位置、HP/MP、普攻、冷却技能）。
	SimAbility / SimUnit 提供引擎 adapter 所需的全部接口。
]]

local nextEntityIndex = 1

local function makeEntityIndex()
	local index = nextEntityIndex
	nextEntityIndex = nextEntityIndex + 1
	return index
end

SimAbility = {}
SimAbility.__index = SimAbility

function SimAbility.new(def)
	local self = setmetatable({}, SimAbility)
	self.name = def.name or "sim_ability"
	self.level = def.level or 1
	self.maxLevel = def.maxLevel or 4
	self.castRange = def.castRange or 500
	self.aoeRadius = def.aoeRadius or 0
	self.castPoint = def.castPoint or 0.3
	self.cooldown = def.cooldown or 6
	self.manaCost = def.manaCost or 60
	self.damage = def.damage or 200
	self.isUltimate = def.isUltimate or false
	self.isPassive = def.isPassive or false
	self.behavior = def.behavior or DOTA_ABILITY_BEHAVIOR_NO_TARGET
	self.targetTeam = def.targetTeam or DOTA_UNIT_TARGET_TEAM_ENEMY
	self.cooldownEnd = 0
	return self
end

function SimAbility:GetAbilityName() return self.name end
function SimAbility:IsNull() return false end
function SimAbility:GetLevel() return self.level end
function SimAbility:GetMaxLevel() return self.maxLevel end
function SimAbility:IsHidden() return false end
function SimAbility:IsPassive() return self.isPassive end
function SimAbility:GetAbilityType() return self.isUltimate and 1 or 0 end
function SimAbility:GetBehaviorInt() return self.behavior end
function SimAbility:GetAbilityTargetTeam() return self.targetTeam end
function SimAbility:GetCastPoint() return self.castPoint end
function SimAbility:GetAOERadius() return self.aoeRadius end
function SimAbility:GetCastRange(_, _) return self.castRange end
function SimAbility:GetCooldownTimeRemaining() return math.max(0, self.cooldownEnd - SimClock) end
function SimAbility:IsOwnersManaEnough() return true end
function SimAbility:IsFullyCastable() return self.cooldownEnd <= SimClock end

SimUnit = {}
SimUnit.__index = SimUnit

function SimUnit.new(def)
	local self = setmetatable({}, SimUnit)
	self.entityIndex = makeEntityIndex()
	SimEntityLookup[self.entityIndex] = self
	self.name = def.name or "sim_unit"
	self.team = def.team
	self.isHero = def.isHero ~= false
	self.level = def.level or 1
	self.maxHealth = def.maxHealth or 600
	self.health = self.maxHealth
	self.maxMana = def.maxMana or 300
	self.mana = self.maxMana
	self.attackDamage = def.attackDamage or 50
	self.attackRange = def.attackRange or 150
	self.attackPeriod = def.attackPeriod or 1.2
	self.moveSpeed = def.moveSpeed or 300
	self.castRangeBonus = def.castRangeBonus or 100
	self.position = def.position or Vector(0, 0)
	self.abilities = {}
	for _, abilityDef in ipairs(def.abilities or {}) do
		table.insert(self.abilities, SimAbility.new(abilityDef))
	end
	self.nextAttackAt = 0
	self.channelUntil = 0
	self.alive = true
	return self
end

function SimUnit:IsNull() return false end
function SimUnit:GetEntityIndex() return self.entityIndex end
function SimUnit:IsAlive() return self.alive end
function SimUnit:IsRealHero() return self.isHero end
function SimUnit:GetTeamNumber() return self.team end
function SimUnit:GetUnitName() return self.name end
function SimUnit:GetLevel() return self.level end
function SimUnit:GetMaxHealth() return self.maxHealth end
function SimUnit:GetHealth() return self.health end
function SimUnit:SetHealth(v) self.health = math.min(self.maxHealth, v) end
function SimUnit:GetMaxMana() return self.maxMana end
function SimUnit:GetMana() return self.mana end
function SimUnit:SetMana(v) self.mana = math.max(0, math.min(self.maxMana, v)) end
function SimUnit:GetAttackDamage() return self.attackDamage end
function SimUnit:GetAbsOrigin() return self.position end
function SimUnit:IsChanneling() return SimClock < self.channelUntil end
function SimUnit:GetCurrentActiveAbility() return nil end

function SimUnit:GetAbilityCount() return #self.abilities end
function SimUnit:GetAbilityByIndex(slot) return self.abilities[slot + 1] end

function SimUnit:Script_GetAttackRange() return self.attackRange end
function SimUnit:GetAttackRange() return self.attackRange end

-- 指令：模拟器直接改状态，供回合推进结算
function SimUnit:MoveToTargetToAttack(target)
	self.attackTarget = target
end

function SimUnit:MoveToPosition(position)
	self.moveTarget = position
end

function SimUnit:Stop()
	self.attackTarget = nil
	self.moveTarget = nil
end

function SimUnit:TakeDamage(amount)
	if not self.alive then
		return
	end
	self.health = self.health - amount
	if self.health <= 0 then
		self.health = 0
		self.alive = false
		self.attackTarget = nil
		self.moveTarget = nil
	end
end

-- 单位一步推进：移动、普攻、技能冷却、回魔
function SimUnit:Step(dt)
	if not self.alive then
		return
	end

	self.mana = math.min(self.maxMana, self.mana + 5 * dt)

	if self.moveTarget ~= nil then
		local delta = self.moveTarget - self.position
		local dist = delta:Length2D()
		if dist <= self.moveSpeed * dt then
			self.position = self.moveTarget
			self.moveTarget = nil
		else
			self.position = self.position + delta:Normalized() * (self.moveSpeed * dt)
		end
		return
	end

	local target = self.attackTarget
	if target == nil or not target:IsAlive() then
		return
	end

	local distance = (target:GetAbsOrigin() - self.position):Length2D()
	if distance > self.attackRange + 75 then
		-- 追击目标
		local delta = target:GetAbsOrigin() - self.position
		self.position = self.position + delta:Normalized() * (self.moveSpeed * dt)
		return
	end

	if SimClock >= self.nextAttackAt then
		target:TakeDamage(self.attackDamage)
		self.nextAttackAt = SimClock + self.attackPeriod
	end
end

function SimUnit:ConsumeMana(cost)
	self.mana = math.max(0, self.mana - cost)
end

function SimUnit:StartChannel(duration)
	self.channelUntil = SimClock + duration
end

-- Vector 最小实现（2D 平面即可满足模拟器需求）
-- Vector 本体是带 __call 的表：Vector(x, y) 构造实例；实例元表为 VectorMT
local VectorMT = { __index = {} }
local vectorMethods = VectorMT.__index

function vectorMethods.Length2D(v)
	return math.sqrt(v.x * v.x + v.y * v.y)
end

function vectorMethods.Normalized(v)
	local len = v:Length2D()
	if len <= 0 then
		return Vector(0, 0)
	end
	return Vector(v.x / len, v.y / len)
end

VectorMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y) end
VectorMT.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y) end
VectorMT.__mul = function(a, scalar)
	if type(a) == "number" then
		a, scalar = scalar, a
	end
	return Vector(a.x * scalar, a.y * scalar)
end
VectorMT.__eq = function(a, b) return a.x == b.x and a.y == b.y end

Vector = setmetatable({}, {
	__call = function(_, x, y, z)
		return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VectorMT)
	end,
})

-- 模拟时钟（StepWorld 推进）
SimClock = 0

function StepWorld(dt)
	SimClock = SimClock + dt
end

function ResetSimClock()
	SimClock = 0
end
