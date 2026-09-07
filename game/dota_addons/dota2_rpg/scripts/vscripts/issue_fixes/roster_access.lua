-- Preparation-stage ownership, skill-upgrade and native-shop access.
-- This module deliberately does not change gold, XP, hero prices or combat rules.

local RosterAccess = {}

local function is_valid(handle)
    if handle == nil then return false end
    if IsValidEntity ~= nil and not IsValidEntity(handle) then return false end
    if handle.IsNull ~= nil and handle:IsNull() then return false end
    return true
end

local function safe_method(handle, name, ...)
    if not is_valid(handle) or handle[name] == nil then return false end
    return pcall(handle[name], handle, ...)
end

function RosterAccess.EnableNativeShop(options)
    options = options or {}

    -- Official custom games expose this on GameRules, not GameModeEntity.
    if GameRules ~= nil and GameRules.SetUseUniversalShopMode ~= nil then
        GameRules:SetUseUniversalShopMode(true)
    end

    -- The official hero_demo uses dota_easybuy so the native shop works without
    -- standing in a shop trigger. Combat purchase is still blocked by OrderFilter.
    if options.enable_easy_buy ~= false and SendToServerConsole ~= nil then
        SendToServerConsole("dota_easybuy 1")
    end
end

function RosterAccess.AssignToPlayer(hero, player_id)
    if not is_valid(hero) then return false, "invalid_hero" end
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then return false, "invalid_player" end

    local player = nil
    if PlayerResource ~= nil then
        player = PlayerResource:GetPlayer(player_id)
    end

    if player == nil or not safe_method(hero, "SetOwner", player) then
        return false, "owner_assignment_failed"
    end
    if not safe_method(hero, "SetPlayerID", player_id) then
        return false, "player_assignment_failed"
    end
    if not safe_method(hero, "SetControllableByPlayer", player_id, true) then
        return false, "control_assignment_failed"
    end
    return true
end

function RosterAccess.SetBenchState(hero, player_id, is_bench)
    local ok, err = RosterAccess.AssignToPlayer(hero, player_id)
    if not ok then return false, err end

    -- Never use MODIFIER_STATE_COMMAND_RESTRICTED or MODIFIER_STATE_STUNNED in
    -- preparation. Those states block DOTA_UNIT_ORDER_TRAIN_ABILITY and native
    -- purchase orders as well as movement.
    if is_bench then
        if hero.HasModifier == nil
            or not hero:HasModifier("modifier_rpg_prepare_bench") then
            hero:AddNewModifier(
                hero,
                nil,
                "modifier_rpg_prepare_bench",
                {}
            )
        end
    elseif hero.RemoveModifierByName ~= nil then
        hero:RemoveModifierByName("modifier_rpg_prepare_bench")
    end

    return true
end

function RosterAccess.PrepareRoster(player_id, active_heroes, bench_heroes)
    for _, hero in ipairs(active_heroes or {}) do
        RosterAccess.SetBenchState(hero, player_id, false)
    end
    for _, hero in ipairs(bench_heroes or {}) do
        RosterAccess.SetBenchState(hero, player_id, true)
    end
end

function RosterAccess.EnsureAbilityPoints(hero, expected_unspent)
    if not is_valid(hero) then return false, "invalid_hero" end
    expected_unspent = math.max(0, math.floor(tonumber(expected_unspent) or 0))

    if hero.SetAbilityPoints == nil or hero.GetAbilityPoints == nil then
        return false, "ability_points_api_missing"
    end

    if hero:GetAbilityPoints() < expected_unspent then
        hero:SetAbilityPoints(expected_unspent)
    end
    return true
end

return RosterAccess
