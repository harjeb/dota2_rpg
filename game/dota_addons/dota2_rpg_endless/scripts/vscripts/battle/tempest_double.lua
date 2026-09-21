-- Tempest Double uses native attack acquisition, with no copied tactic rules.
local Double = {}
local function valid(unit)
    return unit ~= nil and (unit.IsNull == nil or not unit:IsNull())
end
function Double.OnSpawn(game, unit, acquisitionRange)
    if not valid(unit) or unit.IsTempestDouble == nil or not unit:IsTempestDouble() then return false end
    local fighting = game.phase == "fight"
    game.tempestDoubles = game.tempestDoubles or {}
    game.tempestDoubles[unit] = true
    unit:SetIdleAcquire(fighting)
    unit:SetAcquisitionRange(fighting and (acquisitionRange or 4000) or 0)
    return true
end
function Double.Clear(game)
    for unit in pairs(game.tempestDoubles or {}) do
        if valid(unit) then unit:RemoveSelf() end
    end
    game.tempestDoubles = {}
end
function Double.OnThink(game)
    -- Defer out-of-battle cleanup until native spawning has returned.
    if game.phase ~= "fight" then Double.Clear(game) end
end
return Double
