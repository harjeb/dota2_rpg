-- Native proximity mines are stationary spell units, not attack summons.
-- Verified in shipped npc_units.txt: npc_dota_techies_land_mine uses
-- npc_dota_techies_mines, NO_ATTACK and zero acquisition. Never replace its
-- native arming/detonation modifier, issue attacks, or synthesize damage.
local Techies = {}
local function call(unit, method, ...)
    if unit == nil then return nil end
    local ok, fn = pcall(function() return unit[method] end)
    if not ok or type(fn) ~= "function" then return nil end
    local success, value = pcall(fn, unit, ...)
    if success then return value end
end
local function valid(unit) return unit ~= nil and call(unit, "IsNull") ~= true end
function Techies.IsMine(unit)
    return valid(unit) and call(unit, "GetUnitName") == "npc_dota_techies_land_mine"
        and call(unit, "IsRealHero") ~= true
end
local function owned(game, unit, resolveOwner)
    local owner = resolveOwner(game, unit)
    if owner and call(owner, "GetTeamNumber") == call(unit, "GetTeamNumber") then return true end
    -- Bench owners are not in the battle roster. Accept actual handles only,
    -- never a shared player ID/team/name (which could include unrelated mines).
    local bench = {}
    for _, hero in pairs(game.benchUnits or {}) do if valid(hero) then bench[hero] = true end end
    local seen, queue = {[unit] = true}, {unit}
    for _ = 1, 8 do
        local nextLevel = {}
        for _, current in ipairs(queue) do
            for _, method in ipairs({"GetOwnerEntity", "GetOwner"}) do
                local owner = call(current, method)
                if valid(owner) and not seen[owner] then
                    if bench[owner] and call(owner, "GetTeamNumber") == call(unit, "GetTeamNumber") then return true end
                    seen[owner] = true
                    nextLevel[#nextLevel + 1] = owner
                end
            end
        end
        queue = nextLevel
    end
    return false
end
function Techies.Track(game, unit, resolveOwner)
    if not Techies.IsMine(unit) then return false end
    game.techiesMines = game.techiesMines or {}
    if not game.techiesMines[unit] and owned(game, unit, resolveOwner) then
        game.techiesMines[unit] = true
    end
    -- Recognized even before native ownership is assigned: bypass generic AI.
    return true
end
function Techies.Scan(game, resolveOwner)
    -- Class lookup includes invisible/unselectable mines and mines beyond the
    -- combat radius. Revisit delayed ownership and missed npc_spawned events.
    for _, unit in ipairs(call(Entities, "FindAllByClassname", "npc_dota_techies_mines") or {}) do
        Techies.Track(game, unit, resolveOwner)
    end
    for unit in pairs(game.techiesMines or {}) do
        if not valid(unit) then game.techiesMines[unit] = nil end
    end
end
function Techies.Clear(game, resolveOwner)
    if game.phase == "fight" then return end
    Techies.Scan(game, resolveOwner)
    local removing = game.techiesMines or {}
    game.techiesMines = {}
    for unit in pairs(removing) do
        -- Removal is lifecycle-only, not ForceKill (which can detonate a mine).
        if Techies.IsMine(unit) then call(unit, "RemoveSelf") end
    end
end
return Techies
