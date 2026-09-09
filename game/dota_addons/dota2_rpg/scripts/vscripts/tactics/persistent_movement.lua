local Context = require("tactics/condition_context")
local M = {}
local function valid(unit)
    local ok, result = pcall(function() return unit ~= nil and (unit.IsNull == nil or not unit:IsNull()) end)
    return ok and result
end
-- Native acquisition must stay disabled even when a MOVE finishes or follow
-- holds its radius. No modifiers: preserve the native buff's combat semantics.
local function acquire(unit, previous)
    if previous then return previous end
    local idle = Context.Call(unit,"GetIdleAcquire")
    if type(idle) ~= "boolean" then idle = Context.Call(unit,"IsIdleAcquire") end
    if type(idle) ~= "boolean" then idle = true end -- battle enables native acquisition
    local saved = {idle=idle, range=Context.Call(unit,"GetAcquisitionRange")}
    Context.Call(unit,"SetIdleAcquire",false)
    Context.Call(unit,"SetAcquisitionRange",0)
    return saved
end
function M.Release(engine,unit,state,ctx,stop)
    local session = state.movement
    if not session then return end
    if stop and valid(unit) then M.StopOrder(engine,unit,session,ctx) end
    state.movement=nil
    if state.events then state.events.exclusive_movement=nil end
    local saved=session.acquisition
    if saved and valid(unit) then
        local fighting = not engine.get_phase or engine.get_phase() == "FIGHT"
        Context.Call(unit,"SetIdleAcquire",fighting and saved.idle or false)
        if not fighting then Context.Call(unit,"SetAcquisitionRange",0)
        elseif saved.range ~= nil then Context.Call(unit,"SetAcquisitionRange",saved.range) end
    end
end
local function alive(u)
    return u and Context.Call(u,"IsNull") ~= true and Context.Call(u,"IsAlive") ~= false
        and Context.Call(u,"IsOutOfGame") ~= true
end
local function distance(a,b) return (a-b):Length2D() end
local function direction(a,b)
    local d=b-a
    local n=d:Length2D()
    if n < 1 then return Vector(1,0,0) end
    return Vector(d.x/n,d.y/n,0)
end
local function buff(unit, action) return action.movement_buff and Context.Call(unit,"HasModifier",action.movement_buff) == true end
-- Keep the engine's conditions and authored selector intact; restrict only its
-- candidate source, either to the locked handle or to unvisited handles.
local function resolve(engine,s,ctx,accept)
    local filtered={}
    for k,v in pairs(ctx) do filtered[k]=v end
    filtered.get_candidates=function(...)
        local candidates={}
        for _,target in ipairs(ctx.get_candidates and ctx.get_candidates(...) or {}) do
            if alive(target) and target.GetAbsOrigin and accept(target) then candidates[#candidates+1]=target end
        end
        return candidates
    end
    local target,anchor=engine:ResolveRuleTarget(s.rule,s.spec,filtered)
    target=anchor or target
    if alive(target) and target.GetAbsOrigin and accept(target) then return target end
end
local function lock(s,target,p,now)
    s.target=target; s.axis=direction(p,target:GetAbsOrigin()); s.leg=1
    s.orbit_goal=nil; s.orbit_center=nil; s.arc=0
    s.last_position=p; s.progress_time=now
end
-- Observe every rule even when it cannot execute. Each rule consumes a buff
-- episode, or a newly observed native cast, once; timeout cannot re-arm it.
function M.Observe(unit,state,rules)
    state.movement_gates = state.movement_gates or {}
    for _,r in ipairs(rules) do
        local a=r.action or {}
        if a.logical_id == "sustained_move" then
            local key=r.id or r
            local g=state.movement_gates[key]
            local seq=(state.events.casts or {})[a.movement_trigger_ability] or 0
            if not g then g={seq=seq}; state.movement_gates[key]=g end
            if not buff(unit,a) then g.consumed=false; g.ready=false end
            if a.movement_trigger_ability then
                if seq > g.seq then g.ready=true; g.consumed=false end
                g.seq=seq
            else g.ready=buff(unit,a) and not g.consumed end
        end
    end
end
function M.Start(engine,unit,state,ctx,rule,index,spec,target)
    local a=rule.action
    local gate=state.movement_gates and state.movement_gates[rule.id or rule]
    if not gate or not gate.ready or gate.consumed or not buff(unit,a) then return false,"movement_not_armed" end
    if not alive(target) or not target.GetAbsOrigin then return false,"target_invalid" end
    gate.consumed=true; gate.ready=false
    local p=unit:GetAbsOrigin()
    state.chase=nil
    state.posture_order=nil
    state.last_order_signature=nil
    local acquisition=acquire(unit,state.movement and state.movement.acquisition)
    state.events.exclusive_movement=true
    -- Taking ownership also cancels a previous attack when follow starts
    -- already inside its radius (there may be no initial MOVE to replace it).
    state.movement={rule=rule, rule_index=index, spec=spec, target=target, acquisition=acquisition, owns_order=true,
        deadline=ctx.now+math.min(60,tonumber(a.movement_duration) or 8),
        last_position=p, progress_time=ctx.now, axis=direction(p,target:GetAbsOrigin()), leg=1, visited={}}
    M.Continue(engine,unit,state,ctx)
    return state.movement ~= nil, "movement_unreachable"
end
function M.StopOrder(engine,unit,session,ctx)
    if not session or not session.owns_order or not alive(unit) or engine:IsBusy(unit) then return end
    if not engine.actions:CanExecute(unit,{kind="move"},ctx or {}) then return end
    if DOTA_UNIT_ORDER_STOP then
        engine.order_gate:Execute({UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_STOP,Queue=false})
    end
    session.owns_order=false
end
function M.Continue(engine,unit,state,ctx)
    local s=state.movement
    if not s then return false end
    local a=s.rule.action
    local function finish()
        M.Release(engine,unit,state,ctx,true)
        return false
    end
    if not alive(unit) then return finish() end
    if ctx.now >= s.deadline or not buff(unit,a) then return finish() end
    ctx.current_action_id=s.spec.logical_id
    ctx.current_action_spec=s.spec
    if not engine.conditions:EvaluateUseConditions(s.rule.use_conditions,ctx) then return finish() end
    if not resolve(engine,s,ctx,function(target) return target == s.target end) then
        if not a.movement_retarget then return finish() end
        local target=resolve(engine,s,ctx,function(candidate)
            return candidate ~= s.target and not s.visited[candidate]
        end)
        if not target then return finish() end
        lock(s,target,unit:GetAbsOrigin(),ctx.now)
    end
    -- Own/native control pauses orders, never simulates locomotion.
    local move={kind="move",logical_id="sustained_move",target_mode="point"}
    if engine:IsBusy(unit) or not engine.actions:CanExecute(unit,move,ctx) then
        s.progress_time=ctx.now; s.last_position=unit:GetAbsOrigin(); return true
    end
    local p=unit:GetAbsOrigin(); local center=s.target:GetAbsOrigin()
    local radius=math.max(32,math.min(3000,tonumber(a.movement_distance) or 250))
    local mode=a.movement_mode or "follow"
    local goal,orbit_goal
    if mode == "follow" then
        if distance(p,center) <= radius then
            M.StopOrder(engine,unit,s,ctx)
            s.progress_time=ctx.now
            return true
        end
        goal=center-direction(p,center)*radius
    elseif mode == "orbit" then
        -- Keep the chord between orbit points outside both collision hulls.
        local hulls=math.max(0,tonumber(Context.Call(unit,"GetHullRadius")) or 0)
            +math.max(0,tonumber(Context.Call(s.target,"GetHullRadius")) or 0)
        radius=math.max(radius,(hulls+8)/math.cos(0.45/2))
        local radial=direction(center,p)
        s.orbit_sign=s.orbit_sign or (a.movement_direction == "cw" and -1 or 1)
        orbit_goal=function(sign)
            local angle=0.45*sign
            return center+Vector(radial.x*math.cos(angle)-radial.y*math.sin(angle),radial.x*math.sin(angle)+radial.y*math.cos(angle),0)*radius
        end
        goal=orbit_goal(s.orbit_sign)
        s.arc=(s.arc or 0)
        if s.orbit_goal and s.orbit_center then
            s.orbit_goal=s.orbit_goal+(center-s.orbit_center)
        end
        s.orbit_center=center
        local arrival=math.min(60,radius*0.15)
        if s.orbit_goal and distance(p,s.orbit_goal) < arrival then s.arc=s.arc+0.45 end
        if not a.movement_loop and s.arc >= math.pi*2 then return finish() end
        if s.orbit_goal and distance(p,s.orbit_goal) >= arrival then goal=s.orbit_goal end
        s.orbit_goal=goal
    else
        goal=center+s.axis*(radius*s.leg)
        if distance(p,goal) < 60 then
            if mode == "pass" and not a.movement_loop then return finish() end
            if mode == "cycle" then
                s.visited[s.target]=true
                local function unvisited(target) return not s.visited[target] end
                local target=resolve(engine,s,ctx,unvisited)
                if not target and a.movement_loop then
                    s.visited={}
                    target=resolve(engine,s,ctx,function(candidate) return candidate ~= s.target end)
                    -- A single eligible target can repeat only after the visit reset.
                    target=target or resolve(engine,s,ctx,unvisited)
                end
                if not target then return finish() end
                lock(s,target,p,ctx.now)
                center=target:GetAbsOrigin()
            else s.leg=-s.leg end
            goal=center+s.axis*(radius*s.leg)
        end
    end
    if distance(p,s.last_position) >= 16 then s.progress_time=ctx.now; s.last_position=p end
    local blocked=GridNav and GridNav.CanFindPath and not GridNav:CanFindPath(p,goal)
    local stalled=ctx.now-s.progress_time > 1.5
    if blocked or stalled then
        if mode ~= "orbit" or (a.movement_direction or "auto") ~= "auto" then return finish() end
        s.orbit_sign=-s.orbit_sign
        goal=orbit_goal(s.orbit_sign)
        if GridNav and GridNav.CanFindPath and not GridNav:CanFindPath(p,goal) then return finish() end
        s.orbit_goal=goal; s.progress_time=ctx.now; s.last_position=p
    end
    local issued=engine.actions:Issue(unit,move,goal,ctx)
    if not issued then return finish() end
    s.owns_order=true
    return true
end
return M
