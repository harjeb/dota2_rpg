local Cache = {}
-- Delay purchase until this native hero is ready; the caller revalidates the
-- phase, exact offer, ownership, capacity and wallet when the callback arrives.
function Cache.Request(game, name, ready)
    game.recruitPrecache = game.recruitPrecache or {}
    local states = game.recruitPrecache
    if states[name] == "ready" or type(PrecacheUnitByNameAsync) ~= "function" then return true end
    if type(states[name]) == "table" then
        states[name].ready = ready -- Retain the latest validated purchase intent.
        return false
    end
    local pending = {ready=ready}
    states[name] = pending
    local ok = pcall(PrecacheUnitByNameAsync, name, function()
        if states[name] ~= pending then return end
        states[name] = "ready"
        pending.ready()
    end, tonumber(game.playerId) or 0)
    if not ok and states[name] == pending then states[name] = nil end
    return false
end
return Cache
