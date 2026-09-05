-- items.lua
-- 经验卷轴物品行为：英雄携带并主动使用时，经验直接进入该英雄的个人成长
-- （服务端权威：GameRules.Dota2RpgDemo:GrantScrollXPByUnit 负责查找英雄数据并结算升级）

local SCROLL_XP = {
	item_rpg_scroll_low = 500,
	item_rpg_scroll_high = 2000,
}

local function grant_scroll_xp(item, default_xp)
	-- 优先取施法目标英雄（对友方英雄施放）；无目标则回退到携带者
	local target = item:GetCursorTarget()
	if target == nil or target:IsNull() or not target:IsRealHero() then
		target = item:GetCaster()
	end
	if target == nil or target:IsNull() or not target:IsRealHero() then
		return
	end
	local xp = SCROLL_XP[item:GetAbilityName()] or default_xp
	if GameRules.Dota2RpgDemo ~= nil then
		GameRules.Dota2RpgDemo:GrantScrollXPByUnit(target, xp)
	end
end

item_rpg_scroll_low = class({})
function item_rpg_scroll_low:OnSpellStart()
	grant_scroll_xp(self, 500)
end

item_rpg_scroll_high = class({})
function item_rpg_scroll_high:OnSpellStart()
	grant_scroll_xp(self, 2000)
end
