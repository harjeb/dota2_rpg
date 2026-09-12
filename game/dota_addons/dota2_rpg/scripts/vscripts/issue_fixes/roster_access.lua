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

function RosterAccess.EnableNativeShop()
    -- Universal Shop opens every shop's catalog, but still needs a physical
    -- shop in range. dota_easybuy also makes purchases free and is unsuitable
    -- as the ordinary-client access mechanism.
    if GameRules ~= nil and GameRules.SetUseUniversalShopMode ~= nil then
        GameRules:SetUseUniversalShopMode(true)
    end
end

function RosterAccess.EnsureNativeShopRange(state)
    if is_valid(state.nativeShopTrigger) then return true end
    local function failed(reason)
        if state.nativeShopRangeError ~= reason then
            print("[Dota2Rpg] NativeShopRange unavailable: " .. reason)
            state.nativeShopRangeError = reason
        end
        return false
    end
    if type(SpawnDOTAShopTriggerRadiusApproximate) ~= "function" then
        return failed("shop trigger API missing")
    end
    -- Covers the arena, bench (-2300, 0) and hidden commander (-1950, -700).
    -- This engine entity supplies replicated shop proximity to the native HUD;
    -- OrderFilter still rejects all purchases outside preparation.
    local ok, trigger = pcall(SpawnDOTAShopTriggerRadiusApproximate,
        Vector(-768, 0, 128), 4096)
    if not ok or not is_valid(trigger) then return failed("shop trigger creation failed") end
    if not safe_method(trigger, "SetShopType", DOTA_SHOP_HOME or 0) then
        if UTIL_Remove ~= nil then pcall(UTIL_Remove, trigger) end
        return failed("shop type assignment failed")
    end
    state.nativeShopTrigger = trigger
    state.nativeShopRangeError = nil
    print("[Dota2Rpg] NativeShopRange ready native-shop-range-v1 center=-768,0,128 radius=4096")
    return true
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

function RosterAccess.ReleaseFieldedRoster(heroes)
    for _, hero in ipairs(heroes or {}) do
        safe_method(hero, "RemoveModifierByName", "modifier_rpg_prepare_bench")
    end
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
