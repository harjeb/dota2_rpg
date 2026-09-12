-- Reviewed native npc_abilities.txt contracts. CAN_SELF_CAST alone does not
-- imply centered damage: directional hero spells also carry that behavior.
local Context = require('tactics/condition_context')
local M = {}
local centered = {
    centaur_khan_war_stomp = true,
    ogre_bruiser_ogre_smash = true,
    big_thunder_lizard_slam = true,
    polar_furbolg_ursa_warrior_thunder_clap = true,
}
function M.IsSelfPoint(ability)
    return Context.Call(ability, 'GetAbilityName') == 'ogre_bruiser_ogre_smash'
end
-- Ogre's native point order still turns toward its cursor. An exact self point
-- has no direction and can end up behind a moving caster before processing.
-- Use a short forward cursor, refreshed at submission and checked by the native
-- location filter. Native range acceptance/turning still requires live checking.
-- This policy is specific to Ogre; ranged/directional spells keep their
-- selected enemy destination and native location filter.
function M.SelfPoint(caster)
    local origin = Context.Call(caster, 'GetAbsOrigin')
    local forward = Context.Call(caster, 'GetForwardVector')
    if origin == nil or forward == nil then return nil end
    local x, y = Context.Number(forward.x), Context.Number(forward.y)
    if x == nil or y == nil then return nil end
    local length = math.sqrt(x*x + y*y)
    if length < 0.001 then return nil end
    return Vector(origin.x + x/length*16, origin.y + y/length*16, origin.z)
end
function M.Radius(ability)
    if not centered[Context.Call(ability, 'GetAbilityName')] then return nil end
    local radius = Context.Number(Context.Call(ability, 'GetAOERadius'))
    if radius and radius > 0 then return radius end
    radius = Context.Number(Context.Call(ability, 'GetSpecialValueFor', 'radius'))
    -- Missing observations must not enable an arena-wide opening cast.
    return radius and math.max(0, radius) or 0
end
return M
