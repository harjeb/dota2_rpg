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
-- Den actors retain their card lifecycle; they are never recruited or heroes.
function Integration.IsDenCompanion(game, unit)
    local state = game.endlessCardCombat or {}
    local entry = (state.spawned or {})[unit]
    local neutral = entry and (entry.kind == 'den' or entry.kind == 'descendant' and entry.native_ai)
    if game.phase ~= 'fight' or not neutral or not alive(unit)
        or (unit.IsRealHero and unit:IsRealHero()) then return false end
    if entry.expires and state.time and entry.expires <= state.time then return false end
    local name = unit.GetUnitName and unit:GetUnitName() or ''
    local team = unit.GetTeamNumber and unit:GetTeamNumber()
    return name:match('^npc_dota_neutral_') ~= nil
        and (team == (DOTA_TEAM_GOODGUYS or 2) or team == (DOTA_TEAM_BADGUYS or 3))
end
function Integration.DenCompanions(game)
    local out = {}
    for unit in pairs((game.endlessCardCombat or {}).spawned or {}) do
        if Integration.IsDenCompanion(game, unit) then out[#out + 1] = unit end
    end
    return out
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
