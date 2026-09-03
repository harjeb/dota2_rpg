--[[
	mock_env.lua
	离线模拟器宿主环境：提供 Dota VScript 全局的最小替代实现，
	使 battle/tactic_engine.lua 可以在纯 Lua 5.1 / LuaJIT 中运行。
]]

-- 纯 Lua 5.1 的 bit.band 最小实现（引擎只用它解析技能行为标志位）
if bit == nil then
	bit = {}
	local function tobits(n)
		local bits = {}
		local i = 0
		while n > 0 do
			bits[i] = n % 2
			n = math.floor(n / 2)
			i = i + 1
		end
		return bits
	end
	function bit.band(a, b)
		local ba, bb = tobits(a), tobits(b)
		local result = 0
		for i = 0, 30 do
			if (ba[i] or 0) == 1 and (bb[i] or 0) == 1 then
				result = result + 2 ^ i
			end
		end
		return result
	end
end

if IsValidEntity == nil then
	function IsValidEntity(entity)
		return entity ~= nil and type(entity) == "table"
	end
end

-- Valve class() 的最小兼容实现（构造函数 + 单层继承）
function class(baseClass, body)
	if body == nil then
		body = baseClass
		baseClass = nil
	end
	local result = {}

	if baseClass ~= nil then
		for key, value in pairs(baseClass) do
			result[key] = value
		end
		result.__baseClass = baseClass
	end

	result.__index = result

	setmetatable(result, {
		__call = function(cls, ...)
			local instance = setmetatable({}, cls)
			local ctor = cls.constructor -- 通过 __index 查找（方法在 class() 之后定义）
			if ctor ~= nil then
				ctor(instance, ...)
			end
			return instance
		end,
	})

	return result
end

-- 引擎内通过实体索引反查单位的钩子（模拟器维护一张索引表）
SimEntityLookup = {}

function EntIndexToHScript(index)
	return SimEntityLookup[index]
end

function DoUniqueString(prefix)
	return prefix .. "_" .. tostring(math.random(1000000))
end

-- 引擎不直接调用的 Dota 符号仅为兼容加载
function Dynamic_Wrap(_, name)
	return function(self, ...)
		return self[name](self, ...)
	end
end

-- 技能行为标志（与 Dota 常量一致的位值）
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 4
DOTA_ABILITY_BEHAVIOR_POINT = 16
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 32
DOTA_ABILITY_BEHAVIOR_TOGGLE = 8192
DOTA_UNIT_TARGET_TEAM_ENEMY = 4
DOTA_UNIT_TARGET_TEAM_FRIENDLY = 8
