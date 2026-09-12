-- Reviewed native npc_abilities.txt contracts. CAN_SELF_CAST alone does not
-- imply centered damage: directional hero spells also carry that behavior.
local Context = require('tactics/condition_context')
local M = {}
local centered = {
    centaur_khan_war_stomp = true,
    ogre_bruiser_ogre_smash = true,
}
function M.IsSelfPoint(ability)
    return Context.Call(ability, 'GetAbilityName') == 'ogre_bruiser_ogre_smash'
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
