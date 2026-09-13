-- Generated enemy-hero policy only; never a spell target or player rule override.
local Context = require("tactics/condition_context")
local Objectives = {}
-- Verified against installed Dota pak01 scripts/npc/npc_units.txt:
-- npc_dota_phoenix_sun uses models/heroes/phoenix/phoenix_egg.vmdl.
local names = {npc_dota_phoenix_sun=true}
for level=1,5 do names["npc_dota_unit_tombstone"..level]=true end
-- Match the tactic engine's normal maximum chase distance, not mapwide scans.
Objectives.radius = 1200

function Objectives.IsRule(rule)
    return rule ~= nil and rule.enemy_attack_objective == true
        and rule.action ~= nil and rule.action.kind == "attack"
end

function Objectives.Prepend(unit, rules)
    if Context.Call(unit,"IsRealHero") ~= true then return rules end
    table.insert(rules,1,{
        id="enemy_attack_objective", enemy_attack_objective=true, enabled=true,
        action={kind="attack",logical_id="basic_attack"},
        target={team="enemy",types={"summon"}}, target_filters={},
        target_priorities={{type="nearest"}}, use_conditions={{type="always"}},
        approach="allow_approach", max_chase_distance=Objectives.radius,
    })
    return rules
end

function Objectives.Candidates(caster)
    local team, origin = Context.Call(caster,"GetTeamNumber"), Context.Call(caster,"GetAbsOrigin")
    if team == nil or origin == nil or type(FindUnitsInRadius) ~= "function" then return {} end
    -- Native eggs/tombstones need not belong to the observed hero/summon roster.
    local flags = (DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 16)
        + (DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE or 128) + (DOTA_UNIT_TARGET_FLAG_NO_INVIS or 256)
    local ok, found = pcall(FindUnitsInRadius,team,origin,nil,Objectives.radius,
        DOTA_UNIT_TARGET_TEAM_ENEMY or 2,DOTA_UNIT_TARGET_ALL or 55,flags,FIND_CLOSEST or 1,false)
    if not ok then return {} end
    local result = {}
    for _, target in ipairs(found or {}) do
        if target ~= nil and Context.Call(target,"IsNull") ~= true and Context.Call(target,"IsAlive") == true
            and names[Context.Call(target,"GetUnitName")]
            and Context.Call(target,"GetTeamNumber") ~= nil and Context.Call(target,"GetTeamNumber") ~= team
            and Context.Call(target,"IsInvulnerable") ~= true and Context.Call(target,"IsAttackImmune") ~= true
            and Context.Call(target,"IsOutOfGame") ~= true
            and Context.Call(caster,"CanEntityBeSeenByMyTeam",target) ~= false
            and Context.Call(target,"IsInvisible") ~= true then
            local position = Context.Call(target,"GetAbsOrigin")
            if position and (position-origin):Length2D() <= Objectives.radius then result[#result+1]=target end
        end
    end
    return result
end
return Objectives
