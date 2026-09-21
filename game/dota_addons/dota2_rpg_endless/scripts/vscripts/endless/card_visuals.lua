-- Cosmetic companions to card_world's scripted hazards. All live handles belong
-- to the combat state; the existing combat tick owns reversal and cleanup.
local M = {}
local WAVE = 'particles/units/heroes/hero_razor/razor_plasmafield.vpcf'
local WALL = 'particles/units/heroes/hero_dark_seer/dark_seer_wall_of_replica.vpcf'

function M.Precache(context)
    PrecacheResource('particle', WAVE, context)
    PrecacheResource('particle', WALL, context)
end

local function create(s, path, expires)
    local visual = {handle=ParticleManager:CreateParticle(path, PATTACH_WORLDORIGIN, nil), expires=expires}
    s.card_visuals = s.card_visuals or {}
    s.card_visuals[#s.card_visuals+1] = visual
    return visual
end

-- CP1=(speed, radius, direction), with direction +1 outward and -1 inward.
-- Verified against Elfansoer/dota-2-lua-abilities:
-- scripts/vscripts/lua_abilities/razor_plasma_field_lua/razor_plasma_field_lua.lua.
function M.SpawnWave(s, w)
    if not ParticleManager then return end
    local speed, range = w.speed or 1200, w.range or 2000
    local outward = range / speed
    local visual = create(s, WAVE, w.started + 2 * outward)
    visual.turns = w.started + outward
    visual.speed, visual.range = speed, range
    ParticleManager:SetParticleControl(visual.handle, 0, w.center)
    ParticleManager:SetParticleControl(visual.handle, 1, Vector(speed, range, 1))
    return visual.handle
end

-- CP0/CP1 are endpoints, verified against EarthSalamander42/dota_imba:
-- game/scripts/vscripts/components/abilities/heroes/hero_dark_seer.lua.
-- dx/dy are the unit direction ALONG the wall, matching the collision segment.
function M.SpawnWall(s, w)
    if not ParticleManager then return end
    local half = (w.length or 900) / 2
    local center = w.center
    local visual = create(s, WALL, w.expires)
    ParticleManager:SetParticleControl(visual.handle, 0,
        Vector(center.x + w.dx * half, center.y + w.dy * half, center.z))
    ParticleManager:SetParticleControl(visual.handle, 1,
        Vector(center.x - w.dx * half, center.y - w.dy * half, center.z))
    return visual.handle
end

local function destroy(visual)
    ParticleManager:DestroyParticle(visual.handle, true)
    ParticleManager:ReleaseParticleIndex(visual.handle)
end

function M.Tick(s, time)
    if not ParticleManager then return end
    local visuals = s.card_visuals
    if not visuals then return end
    for i = #visuals, 1, -1 do
        local visual = visuals[i]
        if time >= visual.expires then
            destroy(visual)
            table.remove(visuals, i)
        elseif visual.turns and time >= visual.turns then
            ParticleManager:SetParticleControl(visual.handle, 1, Vector(visual.speed, visual.range, -1))
            visual.turns = nil
        end
    end
    if #visuals == 0 then s.card_visuals = nil end
end

function M.Stop(s)
    if not ParticleManager then return end
    for _, visual in ipairs(s.card_visuals or {}) do destroy(visual) end
    s.card_visuals = nil
end

return M
