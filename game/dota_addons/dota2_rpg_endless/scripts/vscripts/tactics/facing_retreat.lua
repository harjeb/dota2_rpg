-- Own-facing displacement: enemy is an anchor, never the native cast target.
local C = require("tactics/condition_context")
local Movement = require("tactics/persistent_movement")
local Lifecycle = require("tactics/action_lifecycle")
local F = {}
local COS_TOLERANCE = math.cos(math.rad(10))
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k,v in pairs(t) do out[k] = copy(v) end; return out
end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function F.IsAction(action, nativeName)
    local name = nativeName or (action and (action.name or action.logical_id))
    return action ~= nil and action.destination == "away_from_target"
        and ((name == "mirana_leap" and action.kind == "ability")
            or (name == "item_force_staff" and action.kind == "item"))
end
function F.Supports(action,spec)
    local name = spec and (C.Call(spec.source,"GetAbilityName") or (spec.capability or {}).name or spec.logical_id)
    return F.IsAction(action,name) and spec ~= nil
        and ((name == "mirana_leap" and spec.cast_type == "none")
            or (name == "item_force_staff" and spec.cast_type == "unit"))
end
function F.Select(engine,rule,spec,ctx,locked)
    if not F.Supports(rule.action,spec) then return nil,nil,"invalid_facing_action" end
    if (rule.target or {}).team ~= "enemy" then return nil,nil,"retreat_requires_enemy_anchor" end
    if spec.cast_type == "unit" and not engine.actions:IsValidTarget(ctx.caster,spec,ctx.caster) then
        return nil,nil,"invalid_native_target"
    end
    local candidates = ctx.get_candidates and ctx.get_candidates(ctx.caster,spec,rule.target) or {}
    local pool = {}
    for _,u in ipairs(candidates) do
        if u ~= ctx.caster and (not locked or u == locked) and C.Call(u,"IsAlive") ~= false
            and C.Call(u,"IsNull") ~= true and C.Call(u,"IsOutOfGame") ~= true
            and C.Call(u,"GetTeamNumber") ~= C.Call(ctx.caster,"GetTeamNumber") then
            pool[#pool+1] = u
        end
    end
    -- Filter as an anchor, without Force Staff's native friendly unit filter.
    local anchorSpec = {}; for k,v in pairs(spec) do anchorSpec[k]=v end
    anchorSpec.target_mode="none"; anchorSpec.cast_type="none"
    local filtered = engine.selector:FilterCandidates(pool,rule.target_filters,ctx,anchorSpec,rule.target_filters_mode)
    engine.selector:SortCandidates(filtered,rule.target_priorities,ctx)
    if not filtered[1] then return nil,nil,"no_retreat_anchor" end
    return ctx.caster,filtered[1]
end
local function direction(unit,anchor)
    local p,q = C.Call(unit,"GetAbsOrigin"),C.Call(anchor,"GetAbsOrigin")
    local f = C.Call(unit,"GetForwardVector")
    if not p or not q or not f then return end
    local dx,dy=p.x-q.x,p.y-q.y
    local n,fn=math.sqrt(dx*dx+dy*dy),math.sqrt(f.x*f.x+f.y*f.y)
    if n < 1 or fn < 0.001 then return end
    local d=Vector(dx/n,dy/n,0)
    return d,(d.x*f.x+d.y*f.y)/fn >= COS_TOLERANCE
end
function F.Release(engine,unit,state,ctx,stop)
    local s=state.facing_retreat
    if not s then return end
    if stop then Movement.StopOrder(engine,unit,s,ctx or {}) end
    state.facing_retreat=nil
    if state.events then state.events.exclusive_movement=state.movement ~= nil and true or nil end
    local fighting=engine.get_phase() == "FIGHT"
    C.Call(unit,"SetIdleAcquire",fighting and s.idle or false)
    if not fighting then C.Call(unit,"SetAcquisitionRange",0)
    elseif s.range ~= nil then C.Call(unit,"SetAcquisitionRange",s.range) end
    state.last_order_signature=nil
end
function F.Start(engine,unit,state,ctx,rule,index,spec,anchor)
    if ctx.movement_cast_only or state.movement then return false,"retreat_movement_busy" end
    if ctx.now < (state.facing_retry_after or 0) then return false,"retreat_retry_delay" end
    local d,aligned = direction(unit,anchor)
    if not d then return false,"invalid_retreat_direction" end
    if not aligned and not engine.actions:CanExecute(unit,{kind="move"},ctx) then return false,"cannot_turn" end
    local idle=C.Call(unit,"GetIdleAcquire")
    if type(idle) ~= "boolean" then idle=C.Call(unit,"IsIdleAcquire") end
    if type(idle) ~= "boolean" then idle=true end
    state.facing_retreat={rule=copy(rule),rule_index=index,anchor=anchor,source=spec.source,
        deadline=ctx.now+1.5,idle=idle,range=C.Call(unit,"GetAcquisitionRange"),owns_order=false}
    state.chase=nil; state.posture_order=nil; state.last_order_signature=nil
    require("tactics/neutral_attack").Release(unit)
    C.Call(unit,"SetIdleAcquire",false); C.Call(unit,"SetAcquisitionRange",0)
    if state.events then state.events.exclusive_movement=true end
    return F.Continue(engine,unit,state,ctx,engine.get_rules(unit) or {})
end
function F.Continue(engine,unit,state,ctx,rules)
    local s=state.facing_retreat
    if not s then return false end
    local function cancel(reason)
        F.Release(engine,unit,state,ctx,true)
        state.facing_retry_after=ctx.now+1
        engine:Debug(unit,"retreat_cancelled",{rule_index=s.rule_index,reason=reason})
        return true
    end
    if s.submitted then
        if Lifecycle.Phase(unit,s.name,ctx.now) == "REQUESTED" then return true end
        F.Release(engine,unit,state,ctx,false)
        return true
    end
    local rule=rules[s.rule_index]
    if not rule or rule.enabled == false or not equal(rule,s.rule) then return cancel("rule_changed") end
    if ctx.now >= s.deadline then return cancel("turn_timeout") end
    if engine:IsBusy(unit) then return cancel("caster_busy") end
    local spec=engine.actions:Resolve(unit,rule.action,ctx)
    if not F.Supports(rule.action,spec) or spec.source ~= s.source then return cancel("action_changed") end
    ctx.current_action_id=spec.logical_id; ctx.current_action_spec=spec
    if not require("tactics/rule_compatibility").Validate(unit,rule,{runtime=true,capability=spec.capability})
        or not engine.actions:CanExecute(unit,spec,ctx)
        or not engine.conditions:EvaluateUseConditions(rule.use_conditions,ctx,rule.use_conditions_mode) then
        return cancel("conditions_changed")
    end
    local target,anchor=F.Select(engine,rule,spec,ctx,s.anchor)
    if not target then return cancel("anchor_invalid") end
    local d,aligned=direction(unit,anchor)
    if not d then return cancel("invalid_retreat_direction") end
    if aligned then
        if not engine.actions:IsInRange(unit,spec,target) then return cancel("out_of_range") end
        local issued,why=engine:IssueAction(unit,state,ctx,rule,s.rule_index,spec,target,anchor)
        if not issued then return cancel(why or "cast_rejected") end
        s.owns_order=false; s.submitted=true
        s.name=C.Call(spec.source,"GetAbilityName") or spec.logical_id
        return true
    end
    if not engine.actions:CanExecute(unit,{kind="move"},ctx) then return cancel("cannot_turn") end
    local p=unit:GetAbsOrigin(); local goal=Vector(p.x+d.x*64,p.y+d.y*64,p.z)
    if GridNav and ((GridNav.CanFindPath and not GridNav:CanFindPath(p,goal))
        or (GridNav.IsTraversable and not GridNav:IsTraversable(goal))
        or (GridNav.IsBlocked and GridNav:IsBlocked(goal))) then return cancel("turn_path_blocked") end
    if engine.order_gate:Execute({UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        Position=goal,Queue=false}) == false then return cancel("turn_order_rejected") end
    s.owns_order=true
    return true
end
return F
