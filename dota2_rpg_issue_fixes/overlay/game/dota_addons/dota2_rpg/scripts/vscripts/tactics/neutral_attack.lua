-- One persistent attack intent for native neutral templates and the skill-test
-- creep. Both tactic and fallback attacks use this path, including approach
-- orders. A submitted order
-- is not native acknowledgement: stalled/lost intent gets bounded recovery.
local C = require("tactics/condition_context")
local M = {}
local function call(u,k,...) return C.Call(u,k,...) end
local function now() return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0 end
function M.IsNeutral(unit)
    local name = tostring(call(unit,"GetUnitName") or "")
    return name:match("^npc_dota_neutral_")~=nil or name=="npc_rpg_skill_test_target"
end
function M.ValidTarget(unit,target)
    return target~=nil and call(target,"IsNull")~=true and call(target,"IsAlive")~=false
        and call(target,"GetTeamNumber")~=call(unit,"GetTeamNumber")
        and call(target,"IsInvulnerable")~=true and call(target,"IsAttackImmune")~=true
        and call(target,"IsOutOfGame")~=true
end
function M.Release(unit)
    if not unit then return end
    if unit.rpg_neutral_attack_intent or unit.rpg_tactic_force_target or unit.rpg_fallback_force_target then
        call(unit,"SetForceAttackTarget",nil)
    end
    unit.rpg_neutral_attack_intent=nil
    unit.rpg_tactic_force_target=nil
    unit.rpg_fallback_force_target=nil
end
local function claim(unit,state,owner)
    state.owner=owner
    unit.rpg_tactic_force_target=owner=="tactic" and state.target or nil
    unit.rpg_fallback_force_target=owner=="fallback" and state.target or nil
end
function M.HasTactic(unit)
    local s=unit and unit.rpg_neutral_attack_intent
    return s~=nil and s.owner=="tactic" and M.ValidTarget(unit,s.target)
        and now()-(s.requested or 0)<=1 and now()>=(s.blocked_until or 0)
end
local function position(unit)
    local p=call(unit,"GetAbsOrigin")
    if p then return {x=p.x,y=p.y} end
end
local function paused(unit)
    for _,k in ipairs({"IsStunned","IsRooted","IsDisarmed","IsCommandRestricted","IsOutOfGame","IsChanneling","IsUsingAbility","IsInAbilityPhase"}) do
        if call(unit,k)==true then return true end
    end
    return false
end
local function progressing(unit,target,state)
    local p,q=position(unit),position(target)
    local old=state.position
    state.position=p
    if call(unit,"GetAttackTarget")==target then return true end
    local attack=unit.rpgTacticsEvents and unit.rpgTacticsEvents.attack
    if attack and attack.target==target and attack.time>(state.release_time or -math.huge) then
        state.release_time=attack.time
        return true
    end
    if p and q and old then
        local dx,dy=p.x-old.x,p.y-old.y
        local tx,ty=q.x-old.x,q.y-old.y
        -- Own movement toward (or sideways around) the target counts even if a
        -- faster target is increasing the gap. Retreat/no movement does not.
        if dx*dx+dy*dy>=1 and dx*tx+dy*ty>=0 then return true end
    end
    return false
end
function M.Submit(unit,target,owner,execute)
    if not M.ValidTarget(unit,target) then M.Release(unit);return false,"invalid_attack_target" end
    local t=now()
    local s=unit.rpg_neutral_attack_intent
    if s and s.target==target then
        s.requested=t
        if t<(s.blocked_until or 0) then return false,"attack_recovery_wait" end
        if s.blocked_until then
            M.Release(unit);s=nil
        else
            claim(unit,s,owner)
            local progress=progressing(unit,target,s)
            local waiting=paused(unit)
            if progress or waiting then s.progress=t;s.retries=0 end
            local recovery=math.max(1.5,(tonumber(call(unit,"GetSecondsPerAttack",false)) or 0)+.25)
            local idle=call(unit,"IsIdle")==true
            local lost=not progress and type(unit.GetForceAttackTarget)=="function" and call(unit,"GetForceAttackTarget")~=target
            if waiting or (not idle and not lost and t-math.max(s.progress,s.submitted)<recovery) then return true,"attack_persisted" end
            -- Do not retry multiple times per engine/fallback tick, including
            -- native rejection that leaves the unit idle with a cached target.
            if t-s.submitted<.5 then return true,"attack_persisted" end
            if t-s.progress>=recovery then
                s.retries=s.retries+1
                if s.retries>3 then
                    call(unit,"SetForceAttackTarget",nil)
                    unit.rpg_tactic_force_target=nil;unit.rpg_fallback_force_target=nil
                    s.blocked_until=t+recovery
                    return false,"attack_stalled"
                end
            end
        end
    else
        M.Release(unit)
        s=nil
    end
    if not s then
        s={target=target,progress=t,position=position(unit),retries=0}
        unit.rpg_neutral_attack_intent=s
    end
    claim(unit,s,owner)
    s.requested=t;s.submitted=t
    -- submitted provides recovery grace; progress changes only on observation.
    call(unit,"SetForceAttackTarget",target)
    if execute()==false then M.Release(unit);return false,"order_rejected" end
    return true
end
return M
