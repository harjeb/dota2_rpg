--[[
	DataLoader
	加载 scripts/data 下的数据表（levels / enemy_ai / loot），策划改表不改码。

	说明：Dota 的 仅支持 KV 文本；JSON 源表已转换为 .kv。
]]

if DataLoader == nil then
	_G.DataLoader = class({})
end

function DataLoader:constructor()
	self.levels = {}
	self.enemyAI = {}
	self.loot = {}
end

function DataLoader:Init()
	self.levels = self:LoadTable("scripts/data/levels.kv", "levels")
	self.enemyAI = self:LoadTable("scripts/data/enemy_ai.kv", "enemy_ai")
	self.loot = self:LoadTable("scripts/data/loot.kv", "loot")
	print(string.format(
		"[Dota2Rpg] Data loaded: %d levels, %d ai presets, %d loot tables.",
		self:Count(self.levels), self:Count(self.enemyAI), self:Count(self.loot)
	))
end

function DataLoader:LoadTable(relativePath, label)
	local loaded = LoadKeyValues(relativePath)
	if loaded == nil or loaded == "" then
		print(string.format("[Dota2Rpg] WARNING: data table '%s' missing (%s).", label, relativePath))
		return {}
	end
	-- Workshop Tools 版本可能返回带文件根节点的表，也可能直接返回根节点内容。
	-- 两种形式都归一化，避免 levels/enemy_ai/loot 在不同工具版本下变成空表。
	if type(loaded) == "table" and type(loaded[label]) == "table" then
		return loaded[label]
	end
	return loaded
end

function DataLoader:Count(t)
	local count = 0
	for _ in pairs(t or {}) do
		count = count + 1
	end
	return count
end

function DataLoader:GetLevel(levelId)
	return self.levels[levelId]
end

function DataLoader:GetAllLevels()
	return self.levels
end

function DataLoader:GetEnemyAI(aiId)
	return self.enemyAI[aiId]
end

function DataLoader:GetLoot(lootId)
	return self.loot[lootId]
end
