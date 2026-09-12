-- 回归：野怪必须被升级并把原生技能点到可用等级。
--
-- 背景：PrepareEnemyCreep 过去只关掉 idle-acquire 并把 acquisition range 设为 0，
-- 完全没碰等级。野怪的技能声明在单位 KV 的 Ability1/2 上，但技能停在 0 级时
-- 引擎会拒绝一切施法指令；战术 AI 照常下发（日志里只有 rule_executed、
-- 永远没有真正的 cast），玩家看到的现象就是"野怪全都没有技能"。
local repoRoot = TEST_REPO_ROOT or "."

function class()
	local result = {}
	result.__index = result
	return result
end

-- addon_game_mode.lua 顶部会读取一批原生常量。
DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_TEAM_NEUTRALS = 4
ABILITY_TYPE_BASIC = 0
ABILITY_TYPE_ULTIMATE = 1

local vectorMeta = {}
vectorMeta.__add = function(left, right)
	return setmetatable({ x = left.x + right.x, y = left.y + right.y, z = left.z + right.z }, vectorMeta)
end

function Vector(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, vectorMeta)
end

local xpAsserts = 0
local function assertEqual(actual, expected, message)
	xpAsserts = xpAsserts + 1
	if actual ~= expected then
		error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)), 2)
	end
end

-- 只需让 addon_game_mode.lua 能加载。这里把项目自己的模块真实加载进来
-- （与 precache-battlefield.test.lua 的做法一致），只把无关的调试安装器留空。
require = function(moduleName)
	if moduleName == "issue_fixes.bootstrap" or moduleName == "battle.skill_debug" then
		return { Install = function() end }
	end
	local rel = moduleName:gsub("%.", "/")
	local path = repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/" .. rel .. ".lua"
	local chunk, err = loadfile(path)
	if chunk == nil then
		error("failed to load module " .. tostring(moduleName) .. ": " .. tostring(err))
	end
	return chunk()
end

local addonPath = repoRoot .. "/game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua"
local loaded, loadError = pcall(dofile, addonPath)
assert(loaded, "failed to load addon_game_mode.lua: " .. tostring(loadError))

local CDota2RpgDemo = _G.CDota2RpgDemo
assert(CDota2RpgDemo ~= nil, "addon_game_mode.lua did not define the CDota2RpgDemo class")

-- 假的技能句柄：记录被点到的等级，模拟引擎 SetLevel 的行为。
local function newAbility(name, maxLevel, passive)
	local ability = {
		name = name,
		maxLevel = maxLevel,
		level = 0,
		passive = passive or false,
	}
	function ability:IsNull() return false end
	function ability:GetAbilityName() return self.name end
	function ability:GetMaxLevel() return self.maxLevel end
	function ability:GetLevel() return self.level end
	function ability:SetLevel(value) self.level = math.max(0, math.min(self.maxLevel, value)) end
	function ability:IsPassive() return self.passive end
	return ability
end

-- 假的野怪：初始 1 级，abilities 即单位 KV 里声明的技能组。
local function newCreep(name, nativeLevel, abilities)
	local unit = {
		name = name,
		nativeLevel = nativeLevel,
		level = nativeLevel,
		abilities = abilities or {},
		idleAcquire = true,
		acquisitionRange = 500,
	}
	function unit:IsNull() return false end
	function unit:GetUnitName() return self.name end
	function unit:IsRealHero() return false end
	function unit:IsAlive() return true end
	function unit:GetLevel() return self.level end
	function unit:SetLevel(value) self.level = value end
	function unit:SetIdleAcquire(value) self.idleAcquire = value end
	function unit:SetAcquisitionRange(value) self.acquisitionRange = value end
	function unit:GetAbilityCount() return #self.abilities end
	function unit:GetAbilityByIndex(index)
		return self.abilities[index + 1]
	end
	return unit
end

local game = setmetatable({}, CDota2RpgDemo)

-- 场景 1：centaur_khan 的等级/技能与 levels.kv 的 ch01 一致（level 1）。
local stomp = newAbility("centaur_khan_war_stomp", 1)
local khan = newCreep("npc_dota_neutral_centaur_khan", 5, { stomp })
-- 原生 KV 的 Level=5，但 levels.kv 指定该关用 1 级：升级按关卡配置，不能反而降级。
game:PrepareEnemyCreep(khan, 1)
assertEqual(khan.level, 5, "a configured level below the native level must not demote the creep")
assertEqual(stomp.level, 1, "the creep's native ability must be unlocked even at the native level")

-- 场景 2：levels.kv 要求更高等级时，野怪必须真的升上去。
local smash = newAbility("ogre_bruiser_ogre_smash", 1)
local upgrade = newAbility("neutral_upgrade", 1, true)
local ogre = newCreep("npc_dota_neutral_ogre_mauler", 2, { smash, upgrade })
ogre.level = 1 -- 模拟引擎可能以 1 级创建
game:PrepareEnemyCreep(ogre, 7)
assertEqual(ogre.level, 7, "PrepareEnemyCreep must level the creep up to the configured level")
assertEqual(smash.level, 1, "the creep's active ability must be maxed so the AI can actually cast it")
assertEqual(upgrade.level, 1, "passive creep abilities declared in the KV must also be maxed")
assertEqual(ogre.idleAcquire, false, "creeps must still not auto-acquire targets")
assertEqual(ogre.acquisitionRange, 0, "creeps must still keep acquisition range disabled")

-- 场景 3：缺失/非法 level 不能把野怪卡在 0 级或无限循环。
local noLevel = newCreep("npc_dota_neutral_ogre_mauler", 1, { newAbility("a", 1) })
game:PrepareEnemyCreep(noLevel, nil)
assertEqual(noLevel.level, 1, "a missing level must fall back to 1 instead of failing")
local bogus = newCreep("npc_dota_neutral_ogre_mauler", 1, { newAbility("a", 1) })
game:PrepareEnemyCreep(bogus, "not-a-number")
assertEqual(bogus.level, 1, "a non-numeric level must fall back to 1 instead of failing")
-- 已经是目标等级以上时不应有任何变化（防止把高等级野怪降级）。
local high = newCreep("npc_dota_neutral_centaur_khan", 9, { newAbility("b", 1) })
game:PrepareEnemyCreep(high, 2)
assertEqual(high.level, 9, "a creep already above the configured level must not be demoted")

-- 场景 4：天赋占位技能不该被点亮（它们不属于野怪技能组）。
local talent = newAbility("special_bonus_unique_centaur_2", 7)
local heroish = newCreep("npc_dota_hero_axe", 1, { talent })
game:PrepareEnemyCreep(heroish, 3)
assertEqual(talent.level, 0, "special_bonus talent placeholders must never be levelled on creeps")

-- Native Troll leaves Ability1 empty; scanning must continue through that hole.
local raiseDead = newAbility("dark_troll_warlord_raise_dead", 1)
local troll = newCreep("npc_dota_neutral_dark_troll_warlord", 6, {})
function troll:GetAbilityCount() return 3 end
function troll:GetAbilityByIndex(index) if index == 1 then return raiseDead end end
game:PrepareEnemyCreep(troll, 6)
assertEqual(raiseDead.level, 1, "the active spell after an empty native slot must be unlocked")

print(string.format("[enemy-creep-abilities] ok assertions=%d", xpAsserts))
