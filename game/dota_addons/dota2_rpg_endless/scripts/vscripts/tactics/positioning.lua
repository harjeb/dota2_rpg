local Context = require("tactics/condition_context")
local M = {}
local function distance(a,b) return (a-b):Length2D() end
local function copy(p) return Vector(p.x,p.y,p.z) end
local function open(point)
    if not GridNav then return true end
    if GridNav.IsTraversable and Context.Call(GridNav,"IsTraversable",point) ~= true then return false end
    if GridNav.IsBlocked and Context.Call(GridNav,"IsBlocked",point) ~= false then return false end
    return true
end
local function reachable(p,goal)
    if not open(goal) then return false end
    -- CanFindPath may allow a long detour. Sample the short movement segment
    -- as well so retreat does not aim through a nearby wall or tree.
    local steps=math.max(1,math.min(24,math.ceil(distance(p,goal)/48)))
    for i=1,steps do if not open(p+(goal-p)*(i/steps)) then return false end end
    return not GridNav or not GridNav.CanFindPath or Context.Call(GridNav,"CanFindPath",p,goal) == true
end
local function attackGoal(state,ctx,target,p,center,radial,wanted,upper,length)
    local nav=state.positioning_nav
    if not nav or nav.target ~= target or nav.range ~= upper then
        nav={target=target,range=upper,origin=copy(p),progress_time=ctx.now,prefer=1}
        state.positioning_nav=nav
    end
    if not nav.goal or distance(p,nav.goal)<=24 then
        nav.goal=nil; nav.origin=copy(p); nav.progress_time=ctx.now
    end
    if distance(p,nav.origin)>=16 then nav.origin=copy(p); nav.progress_time=ctx.now end
    if nav.blocked_origin and (distance(p,nav.blocked_origin)>=64
        or distance(center,nav.blocked_center)>=64 or ctx.now>=nav.blocked_until) then nav.blocked_origin=nil end
    if nav.goal and ctx.now-nav.progress_time>=.45 and distance(p,nav.goal)>24 then
        -- Native bodies can block movement even when static navigation says
        -- yes. Keep the opposite side until progress, rather than oscillating.
        if nav.last_side and nav.last_side~=0 then nav.prefer=-nav.last_side end
        nav.blocked_origin=copy(p); nav.blocked_center=copy(center); nav.blocked_until=ctx.now+2; nav.goal=nil
        nav.origin=copy(p); nav.progress_time=ctx.now
    end
    local function acceptable(goal)
        local radius=distance(goal,center)
        if radius>upper+.1 or distance(goal,p)<16 then return false end
        if length<wanted and radius<=length+1 then return false end
        -- A chord to a side point must not cut closer to the target. This also
        -- keeps an approach from cutting through the desired attack radius.
        local step=goal-p; local square=step.x*step.x+step.y*step.y
        local rel=p-center
        local t=math.max(0,math.min(1,-(rel.x*step.x+rel.y*step.y)/square))
        if distance(p+step*t,center)<math.min(length,wanted)-4 then return false end
        return reachable(p,goal)
    end
    if nav.goal and distance(center,nav.center)<=24 and acceptable(nav.goal) then
        return nav.goal,nav,nav.last_side
    end
    local goal=center+radial*wanted
    if not nav.blocked_origin and acceptable(goal) then return goal,nav,0 end
    local tangent=Vector(-radial.y,radial.x,0)
    -- Tangential steps open space beside a rear wall while staying in range.
    local room=math.sqrt(math.max(0,wanted*wanted-length*length))
    for _,step in ipairs({math.min(192,room),math.min(80,room)}) do
        for _,side in ipairs({nav.prefer,-nav.prefer}) do
            goal=p+tangent*(step*side)
            if acceptable(goal) then return goal,nav,side end
        end
    end
    for _,angle in ipairs({math.pi/6,math.pi/3}) do
        for _,side in ipairs({nav.prefer,-nav.prefer}) do
            goal=center+(radial*math.cos(angle)+tangent*(math.sin(angle)*side))*wanted
            if acceptable(goal) then return goal,nav,side end
        end
    end
    nav.goal=nil
    return nil
end
-- Called only after the authored action's use/target conditions have passed.
-- Never infer attack release from an order, animation, damage, or windup.
function M.Try(engine,unit,state,ctx,rule,spec,target)
    local a=rule.action
    local mode=a.positioning_mode or "default"
    if mode == "default" or (spec.kind ~= "attack" and spec.kind ~= "ability") then return false end
    if not target or not target.GetAbsOrigin or target == unit then return false end
    if engine:IsBusy(unit) then return false end
    if spec.kind == "attack" or spec.is_attack_ability then
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
    if length >= lower and length <= upper then
        if state.positioning_nav then state.positioning_nav.goal=nil end
        return false
    end
    local radial=length > 1 and Vector(delta.x/length,delta.y/length,0) or Vector(1,0,0)
    local goal=center+radial*wanted
    local nav,side
    if mode == "attack_range" then
        goal,nav,side=attackGoal(state,ctx,target,p,center,radial,wanted,upper,length)
        if not goal then return false end
    elseif GridNav and GridNav.CanFindPath and not GridNav:CanFindPath(p,goal) then return false end
    local issued=engine.actions:Issue(unit,{kind="move",logical_id="action_positioning",target_mode="point"},goal,ctx)
    if issued and nav then
        nav.goal=copy(goal); nav.center=copy(center); nav.last_side=side
        if side~=0 then nav.prefer=side end
    end
    return issued
end
return M
