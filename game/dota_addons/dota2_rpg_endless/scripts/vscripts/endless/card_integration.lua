-- Native engine boundary for card damage and temporary rebirth actors.
local Integration = {}
local function alive(unit)
    return unit and (not unit.IsNull or not unit:IsNull()) and unit.IsAlive and unit:IsAlive()
end
function Integration.Forms(game, team)
    local out = {}
    for unit in pairs((game.endlessCardCombat or {}).forms or {}) do
        if alive(unit) and unit.endlessRebirthForm and (not team or unit:GetTeamNumber() == team) then
            out[#out + 1] = unit
        end
    end
    return out
end
function Integration.IsForm(game, unit)
    return alive(unit) and unit.endlessRebirthForm
        and ((game.endlessCardCombat or {}).forms or {})[unit] ~= nil
end
function Integration.HeroFormCount(game, team)
    local n = 0
    for _, unit in ipairs(Integration.Forms(game, team)) do
        local source = unit.endlessRebirthSource
        if source and source.IsRealHero and source:IsRealHero() then n = n + 1 end
    end
    return n
end
function Integration.Install(game)
    if game.endlessCardIntegrationInstalled then return end
    game.endlessCardIntegrationInstalled = true
    local entity = GameRules:GetGameModeEntity()
    -- This isolated addon has no earlier damage filter. Keep all card arithmetic
    -- at the engine's damage boundary instead of replaying a second attack.
    entity:SetDamageFilter(function(_, event)
        local effects = require('endless.card_effects')
        if game.phase == 'fight' and effects.DamageFilter then
            return effects.DamageFilter(game, event) ~= false
        end
        return true
    end, game)
end
return Integration
