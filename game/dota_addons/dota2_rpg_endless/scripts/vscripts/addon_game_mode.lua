-- Native UI gallery only. No campaign systems, combat, saves or external services.
function Precache(context)
end

function Activate()
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetPreGameTime(0)
    GameRules:SetCustomGameSetupAutoLaunchDelay(0)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 1)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
    GameRules:GetGameModeEntity():SetCustomGameForceHero("npc_dota_hero_wisp")
end
