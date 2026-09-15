-- Emergency responses to observed released areas. No enemy rule/order introspection.
local Context = require('tactics/condition_context')
local Threats = require('tactics/aoe_threats')
local Geometry = require('tactics/aoe_geometry')
local R = {}
local function distance(a,b)
    local x,y=a.x-b.x,a.y-b.y
    return math.sqrt(x*x+y*y)
end
local function hull(unit) return tonumber(Context.Call(unit,'GetHullRadius')) or 24 end
local function inside(unit,point,threat,padding)
    return Geometry.Contains(threat,point,hull(unit)+(padding or 0))
end
local function starts(threat) return threat.active_from or threat.impact_at end
local function finishes(threat) return threat.active_until or threat.expires_at or starts(threat) end
local function persistent(threat) return finishes(threat)>starts(threat) end
local function relevant(threat,now)
    return threat.phase=='released' and finishes(threat)>now and starts(threat)-now<=3
end
function R.Condition(rule)
    for _,c in ipairs(rule.use_conditions or {}) do if c.type=='incoming_aoe' then return c end end
end
function R.HasRules(rules)
    for _,rule in ipairs(rules or {}) do if rule.enabled~=false and R.Condition(rule) then return true end end
    return false
end
local function update_submission(ctx,pending)
    local submitted=pending.submitted
    if not submitted then return end
    local success=ctx.caster.rpgTacticsEvents and ctx.caster.rpgTacticsEvents.successes[submitted.action]
    if success and success.sequence>submitted.sequence then
        pending.consumed=true;pending.submitted=nil;return
    end
    local phase=require('tactics/action_lifecycle').Phase(ctx.caster,submitted.action,ctx.now)
    if phase=='INTERRUPTED' or phase=='UNCONFIRMED'
        or (ctx.now>=submitted.deadline and phase~='CASTING' and phase~='CHANNELING') then
        pending.failed_rows=pending.failed_rows or {}
        pending.failed_rows[submitted.rule_index]=true
        pending.submitted=nil
    end
end
local function records(ctx)
    if ctx.aoe_threat_list==nil then ctx.aoe_threat_list=Threats.Threats(ctx.caster,ctx.now) end
    return ctx.aoe_threat_list
end
function R.Match(ctx,condition)
    local state=ctx.aoe_state
    if not state then return false end
    state.aoe_pending=state.aoe_pending or {}
    local current,seen={},{}
    for _,t in ipairs(records(ctx)) do
        seen[t.id]=true
        if relevant(t,ctx.now) and inside(ctx.caster,ctx.caster:GetAbsOrigin(),t) then
            current[#current+1]=t
        elseif state.aoe_pending[t.id] and state.aoe_pending[t.id].consumed then
            -- A fresh entry into a persistent area is a new exposure.
            state.aoe_pending[t.id]=nil
        end
    end
    for id in pairs(state.aoe_pending) do if not seen[id] then state.aoe_pending[id]=nil end end
    table.sort(current,function(a,b) return a.impact_at==b.impact_at and a.id<b.id or a.impact_at<b.impact_at end)
    for _,t in ipairs(current) do
        local pending=state.aoe_pending[t.id]
        if not pending then
            local random=ctx.aoe_random or RandomFloat or function(a,b) return a+math.random()*(b-a) end
            pending={started_at=ctx.now,fraction=random(0,1)}
            state.aoe_pending[t.id]=pending
        end
        -- Share one draw, but honor each response row's configured interval.
        local low=tonumber(condition.reaction_min_ms) or 80
        local high=tonumber(condition.reaction_max_ms) or 500
        local ready_at=pending.started_at+(low+(high-low)*pending.fraction)/1000
        update_submission(ctx,pending)
        if (not pending.consumed or (condition.response or 'walk')=='walk') and not pending.submitted and ctx.now>=ready_at then
            ctx.aoe_match={threat=t,condition=condition,pending=pending}
            return true
        end
    end
    return false
end
local function traversable(point)
    if not GridNav then return false end
    return Context.Call(GridNav,'IsTraversable',point)==true and Context.Call(GridNav,'IsBlocked',point)==false
end
local function walkable(from,to)
    if not traversable(to) or Context.Call(GridNav,'CanFindPath',from,to)~=true then return false end
    local count=math.ceil(distance(from,to)/64)
    if count>24 then return false end
    for i=1,count do
        local p=Vector(from.x+(to.x-from.x)*i/count,from.y+(to.y-from.y)*i/count,to.z)
        if not traversable(p) then return false end
    end
    return true
end
local function safe_walk(unit,ctx,goal,threats)
    local origin=unit:GetAbsOrigin()
    if not walkable(origin,goal) then return false end
    local d=distance(origin,goal)
    local speed=tonumber(Context.Call(unit,'GetIdealSpeed')) or 0
    if speed<=0 then return false end
    local travel=d/speed
    local function point_at(seconds)
        local fraction=d>0 and math.max(0,math.min(1,(seconds-0.1)*speed/d)) or 1
        return {x=origin.x+(goal.x-origin.x)*fraction,y=origin.y+(goal.y-origin.y)*fraction}
    end
    for _,other in ipairs(threats) do
        if finishes(other)>ctx.now then
            if inside(unit,goal,other,24) then return false end
            if type(other.escape_deadline)=='number' and inside(unit,point_at(other.escape_deadline-ctx.now),other,8) then
                return false
            end
            if not persistent(other) then
                if inside(unit,point_at(starts(other)-ctx.now),other,8) then return false end
            else
                local first=math.max(0,starts(other)-ctx.now)
                local last=math.min(0.1+travel,finishes(other)-ctx.now)
                if first<=last then
                    local escaping=starts(other)<=ctx.now and inside(unit,origin,other,8)
                    local previous=Geometry.SignedDistance(other,origin)
                    -- Sample active travel every <=16 units, including activation and arrival.
                    local count=math.max(1,math.ceil((last-first)*speed/16))
                    for i=0,count do
                        local p=point_at(first+(last-first)*i/count)
                        local within=inside(unit,p,other,8)
                        local clearance=Geometry.SignedDistance(other,p)
                        if within then
                            if not escaping or clearance<previous-0.01 then return false end
                        else
                            escaping=false
                        end
                        previous=clearance
                    end
                end
            end
        end
    end
    return true
end
function R.SafePoint(engine,unit,ctx,spec)
    local origin=unit:GetAbsOrigin()
    local threats=records(ctx)
    local best,bestDistance
    for _,threat in ipairs(threats) do
        for _,candidate in ipairs(Geometry.Candidates(threat,origin,hull(unit)+48)) do
            local p=Vector(candidate.x,candidate.y,candidate.z or origin.z)
            if type(GetGroundPosition)=='function' then p=GetGroundPosition(p,unit) end
            local d=distance(origin,p)
            local safe=traversable(p)
            for _,other in ipairs(threats) do
                if inside(unit,p,other,24) then safe=false;break end
            end
            if safe and spec then
                -- Ordinary cast-range checks include an approach tolerance;
                -- escape destinations must lie inside the actual native range.
                local range=engine.actions:GetRequiredRange(unit,spec,p)
                safe=type(range)=='number' and d<=range
                local source=spec.source or spec.ability
                if safe and source and source.CastFilterResultLocation then
                    local ok,result=pcall(source.CastFilterResultLocation,source,p)
                    safe=ok and result==(UF_SUCCESS or 0)
                end
            elseif safe then
                safe=safe_walk(unit,ctx,p,threats)
            end
            if safe and (not bestDistance or d<bestDistance) then best,bestDistance=p,d end
        end
    end
    return best
end
function R.Release(engine,unit,state,ctx,stop)
    local session=state.aoe_walk
    if session and session.owns_order and stop and not engine:IsBusy(unit) then
        engine.order_gate:Execute({UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_STOP,Queue=false})
    end
    state.aoe_walk=nil
    if session and session.acquisition then
        local fighting=engine.get_phase()== 'FIGHT'
        Context.Call(unit,'SetIdleAcquire',fighting and session.acquisition.idle or false)
        Context.Call(unit,'SetAcquisitionRange',fighting and session.acquisition.range or 0)
    end
    if state.events and not state.movement and not state.facing_retreat then state.events.exclusive_movement=nil end
end
local function acquire(unit,previous)
    if previous then return previous end
    local idle=Context.Call(unit,'GetIdleAcquire')
    if type(idle)~='boolean' then idle=Context.Call(unit,'IsIdleAcquire') end
    local saved={idle=idle~=false,range=Context.Call(unit,'GetAcquisitionRange') or 0}
    Context.Call(unit,'SetIdleAcquire',false)
    Context.Call(unit,'SetAcquisitionRange',0)
    return saved
end
local function stop_other_movement(engine,unit,state,ctx)
    require('tactics/facing_retreat').Release(engine,unit,state,ctx,false)
    require('tactics/persistent_movement').Release(engine,unit,state,ctx,false)
    require('tactics/neutral_attack').Release(unit)
    state.chase=nil;state.posture_order=nil;state.last_order_signature=nil
end
function R.Continue(engine,unit,state,ctx,rules)
    local session=state.aoe_walk
    if not session then return false end
    local rule=rules[session.rule_index]
    local c=rule and R.Condition(rule)
    if not rule or rule.enabled==false or not c or (c.response or 'walk')~='walk' then
        R.Release(engine,unit,state,ctx,true);return false
    end
    local exists=false
    for _,t in ipairs(records(ctx)) do if t.id==session.threat_id then exists=true;break end end
    if not exists then R.Release(engine,unit,state,ctx,true);return false end
    if engine:IsBusy(unit) then session.owns_order=false;return false end
    if session.owns_order and not safe_walk(unit,ctx,session.point,records(ctx)) then
        R.Release(engine,unit,state,ctx,true);return false
    end
    -- Hold the safe edge until impact/cancellation; do not attack-chase back into it.
    local safe=true
    for _,t in ipairs(records(ctx)) do if inside(unit,unit:GetAbsOrigin(),t,8) then safe=false;break end end
    if safe and session.owns_order then
        engine.order_gate:Execute({UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_STOP,Queue=false})
        session.owns_order=false
    end
    return true
end
function R.Try(engine,unit,state,ctx,rules)
    ctx.aoe_state=state
    for index,rule in ipairs(rules or {}) do
        local condition=rule.enabled~=false and R.Condition(rule)
        if condition then
            ctx.aoe_match=nil
            ctx.current_action_id=rule.action and rule.action.logical_id
            ctx.current_action_spec=engine.actions:Resolve(unit,rule.action,ctx)
            ctx.condition_trace={};ctx.native_target_trace={accepted=0,rejected=0}
            local danger=R.Match(ctx,condition)
            local passed=danger and engine.conditions:EvaluateUseConditions(rule.use_conditions,ctx,rule.use_conditions_mode)
            local match=ctx.aoe_match
            if passed and match and not (match.pending.failed_rows or {})[index] and not require('tactics/persistent_movement').CastPending(unit,state,ctx)
                and engine.conditions:EvaluateTargetFilters(rule.target_filters,ctx,unit,rule.target_filters_mode) then
                if (match.condition.response or 'walk')=='walk' then
                    local move={kind='move',logical_id='aoe_walk',cast_type='point',target_mode='point'}
                    if engine.actions:CanExecute(unit,move,ctx) then
                        local point=R.SafePoint(engine,unit,ctx)
                        if point then
                            local old=state.aoe_walk
                            if old and old.owns_order and old.threat_id==match.threat.id and distance(old.point,point)<32 then return true end
                            local accepted=engine.order_gate:Execute({UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_MOVE_TO_POSITION,Position=point,Queue=false})
                            if accepted~=false then
                                stop_other_movement(engine,unit,state,ctx)
                                local acquisition=acquire(unit,old and old.acquisition)
                                state.events=state.events or {}
                                state.events.exclusive_movement=true
                                state.aoe_walk={owns_order=true,point=point,threat_id=match.threat.id,rule_index=index,acquisition=acquisition}
                                engine:Debug(unit,'aoe_reaction',{rule_index=index,reason='walk',threat_id=match.threat.id})
                                return true
                            end
                        end
                    end
                else
                    local spec=engine.actions:Resolve(unit,rule.action,ctx)
                    local compatibility=require('tactics/rule_compatibility')
                    if spec and not compatibility.IncomingAoeCastReason(rule.action,spec.capability,(rule.target or {}).team)
                        and compatibility.Validate(unit,rule,{runtime=true,capability=spec.capability})
                        and engine.actions:CanExecute(unit,spec,ctx) then
                        ctx.current_action_spec=spec;ctx.current_action_id=spec.logical_id
                        local target
                        if spec.target_mode=='point' then target=R.SafePoint(engine,unit,ctx,spec)
                        elseif spec.target_mode=='none' or spec.target_mode=='self' or spec.target_mode=='unit' then target=unit end
                        if target and engine.actions:IsInRange(unit,spec,target) then
                            -- Submit through the normal adapter; unit/self legality and native control remain authoritative.
                            local before=unit.rpgTacticsEvents and unit.rpgTacticsEvents.successes[spec.logical_id]
                            local sequence=before and before.sequence or 0
                            state.last_order_signature=nil
                            local issued=engine:IssueAction(unit,state,ctx,rule,index,spec,target,unit)
                            if issued then
                                match.pending.submitted={action=spec.logical_id,sequence=sequence,rule_index=index,
                                    deadline=ctx.now+math.max(0.35,(tonumber(Context.Call(spec.source,'GetCastPoint')) or 0)+0.25)}
                                update_submission(ctx,match.pending)
                                R.Release(engine,unit,state,ctx,false)
                                stop_other_movement(engine,unit,state,ctx)
                                engine:Debug(unit,'aoe_reaction',{rule_index=index,reason='cast',threat_id=match.threat.id})
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    ctx.aoe_match=nil
    for _,pending in pairs(state.aoe_pending or {}) do
        update_submission(ctx,pending)
        if pending.submitted then return true end
    end
    return R.Continue(engine,unit,state,ctx,rules)
end
return R
