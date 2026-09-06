-- Shared unit validity helpers used by production gameplay modules.
-- The legacy battle/tactic_engine.lua remains an offline simulator dependency;
-- production code must not load its rule evaluator or its global TacticEngine.

local UnitHelpers = {}

function UnitHelpers.IsValidUnit(unit)
	return unit ~= nil and IsValidEntity(unit) and not unit:IsNull()
end

function UnitHelpers.HealthPercent(unit)
	if unit == nil or unit:IsNull() or unit:GetMaxHealth() <= 0 then
		return 1
	end
	return unit:GetHealth() / unit:GetMaxHealth()
end

function UnitHelpers.ManaPercent(unit)
	if unit == nil or unit:IsNull() or unit:GetMaxMana() <= 0 then
		return 1
	end
	return unit:GetMana() / unit:GetMaxMana()
end

return UnitHelpers
