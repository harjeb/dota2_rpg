local Context = require("tactics/condition_context")
local M = {}
-- Called only after the authored action's use/target conditions have passed.
-- Never infer attack release from an order, animation, damage, or windup.
function M.Try(engine,unit,state,ctx,rule,spec,target)
    local a=rule.action
    local mode=a.positioning_mode or "default"
    if mode == "default" or (spec.kind ~= "attack" and spec.kind ~= "ability") then return false end
    if not target or not target.GetAbsOrigin or target == unit then return false end
    if engine:IsBusy(unit) then return false end
    if spec.kind == "attack" then
        local release=state.events and state.events.attack
        local interval=tonumber(Context.Call(unit,"GetSecondsPerAttack",false))
        if not release or release.target ~= target or not interval or interval <= 0 then return false end
        -- End before the next native attack can begin. No attack-start heuristic.
        local elapsed=ctx.now-release.time
        if elapsed < 0 or elapsed >= math.max(0,interval-0.25) then return false end
        -- An intervening attack order invalidates this release window.
        if state.attack_order_time and state.attack_order_time > release.time then return false end
    end
    local wanted=tonumber(a.positioning_distance) or 250
    if mode == "attack_range" then wanted=tonumber(Context.Call(unit,"Script_GetAttackRange")) or 150
    elseif mode == "cast_range" then wanted=tonumber(engine.actions:GetRequiredRange(unit,spec,target)) or 0 end
    wanted=math.max(0,math.min(3000,wanted))
    local tolerance=math.max(0,tonumber(a.positioning_tolerance) or 40)
    local p=unit:GetAbsOrigin(); local center=target:GetAbsOrigin(); local delta=p-center
    local length=delta:Length2D()
    local lower=math.max(0,wanted-tolerance)
    local upper=wanted+tolerance
    if mode == "attack_range" then
        upper=wanted
        wanted=lower
        lower=math.max(0,wanted-tolerance)
    end
    if length >= lower and length <= upper then return false end
    local radial=length > 1 and Vector(delta.x/length,delta.y/length,0) or Vector(1,0,0)
    local goal=center+radial*wanted
    if GridNav and GridNav.CanFindPath and not GridNav:CanFindPath(p,goal) then return false end
    return engine.actions:Issue(unit,{kind="move",logical_id="action_positioning",target_mode="point"},goal,ctx)
end
return M
