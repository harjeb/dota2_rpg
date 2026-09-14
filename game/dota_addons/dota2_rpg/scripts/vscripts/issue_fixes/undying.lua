-- Native Relentless Return (internal name: ceaseless_dirge) starts with a
-- 480-second cooldown. Preparation should begin ready, not wait eight minutes.
-- Do not change native KV, intrinsic modifiers, or the cooldown spent in combat.
local Undying = {}
local function call(entity, method, ...)
    if entity == nil then return nil end
    local ok, fn = pcall(function() return entity[method] end)
    if not ok or type(fn) ~= "function" then return nil end
    local success, value = pcall(fn, entity, ...)
    if success then return value end
end
-- Relentless Return uses its own native death buff, not IsReincarnating.
-- The intrinsic is always present (including on cooldown), so only the active
-- return buff can grant respawn permission or postpone a team wipe.
function Undying.IsReturning(hero)
    return call(hero, "IsNull") ~= true
        and call(hero, "GetUnitName") == "npc_dota_hero_undying"
        and call(hero, "HasModifier", "modifier_undying_ceaseless_dirge_buff") == true
end
-- Only a roster death classified by RespawnPolicy may enter this cleanup.
-- Native return already restored the entity; do not respawn it or end its buff.
-- The recorded stuck return retains fountain protection. Remove that known
-- spawn-only modifier, not arbitrary out-of-game states or AI legality checks.
-- Native causality/action recovery still requires user-run engine verification.
function Undying.FinishNativeReturn(game, hero, pending)
    if not pending or game.phase ~= "fight" or call(hero, "IsNull") == true
        or call(hero, "GetUnitName") ~= "npc_dota_hero_undying"
        or call(hero, "IsAlive") ~= true or Undying.IsReturning(hero)
        or call(hero, "HasModifier", "modifier_fountain_invulnerability") ~= true then return false end
    if type(hero.RemoveModifierByName) ~= "function" then return false end
    hero:RemoveModifierByName("modifier_fountain_invulnerability")
    return true
end
function Undying.ResetPreparation(game, hero)
    if game.phase ~= "setup" or call(hero, "IsNull") == true
        or call(hero, "GetUnitName") ~= "npc_dota_hero_undying" then return false end
    local ability = call(hero, "FindAbilityByName", "undying_ceaseless_dirge")
    if ability == nil or call(ability, "IsNull") == true then return false end
    call(ability, "EndCooldown")
    return true
end
function Undying.RefreshPreparation(game)
    if game.phase ~= "setup" then return end
    -- Repeat only while preparing: native spawn/ability initialization may finish
    -- after PrepareBattleHero. Includes bench and retained (not recreated) heroes.
    for _, team in pairs(game.battleManager and game.battleManager.teamHeroes or {}) do
        for _, hero in pairs(team) do Undying.ResetPreparation(game, hero) end
    end
    for _, hero in pairs(game.benchUnits or {}) do Undying.ResetPreparation(game, hero) end
end
return Undying
