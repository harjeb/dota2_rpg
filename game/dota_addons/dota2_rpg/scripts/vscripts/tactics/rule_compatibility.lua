-- Prove contradictions only. Unknown native state is not evidence of impossibility.
local C=require("tactics/condition_context")
local A=require("tactics/ability_capability")
local R={}
local function bool(value) return value==true or value==1 or value=="1" end
local function issue(code,group,index,extra)
    return {code=code,group=group or "action",index=index or 0,detail=extra or ""}
end
function R.Contradictions(rule)
    local ranges,positive,negative,phases={}, {}, {}, {}
    local function add(list,group)
        for index,c in ipairs(list or {}) do
            local id=c.type or ""
            local context=group=="target" and (rule.target or {}).team=="self" and "self" or group
            local metric=id
            if group=="use" and id:match("^self_") then context="self";metric=id:sub(6) end
            local stem,op=metric:match("^(.-)_([gl]te)$")
            if not stem then stem,op=metric:match("^(.-)_(lt)$") end
            local value=C.Number(c.seconds or c.value)
            local key=context..":"..tostring(stem or metric)..":"..tostring(c.modifier or "")..":"
                ..tostring(c.action_id or "<current>")..":"..tostring(c.action_actor or "self")..":"..tostring(c.radius or "")
            if stem and value then
                local range=ranges[key] or {min=0,max=math.huge,strict=false}
                if op=="gte" then range.min=math.max(range.min,value)
                elseif value<range.max then range.max=value;range.strict=op=="lt"
                elseif value==range.max and op=="lt" then range.strict=true end
                ranges[key]=range
                if range.min>range.max or (range.min==range.max and range.strict) then
                    return issue("contradictory_conditions",group,index,stem)
                end
            end
            if id=="action_phase_is" then
                if phases[key] and phases[key]~=c.value then return issue("contradictory_conditions",group,index,"action_phase_is") end
                phases[key]=c.value
            end
            local modifier=c.modifier or c.value
            if metric=="has_modifier" or metric=="not_has_modifier" then
                local tag=context..":modifier:"..tostring(modifier)
                local dst=metric=="has_modifier" and positive or negative
                dst[tag]=true
                if positive[tag] and negative[tag] then return issue("contradictory_conditions",group,index,tostring(modifier)) end
            end
            if metric=="is_spell_immune" or metric=="not_spell_immune" then
                local tag=context..":spell_immune"
                if metric=="is_spell_immune" then positive[tag]=true else negative[tag]=true end
                if positive[tag] and negative[tag] then return issue("contradictory_conditions",group,index,tag) end
            end
            if group=="target" and (rule.target or {}).team=="self" then
                if id=="exclude_self" then return issue("self_excluded",group,index) end
                if id=="distance_gte" and value and value>0 then return issue("self_distance_must_be_zero",group,index) end
            end
        end
    end
    local failed=add(rule.use_conditions,"use") or add(rule.target_filters,"target")
    if failed then return failed end
    local noEnemy,nearby={},{}
    for index,c in ipairs(rule.use_conditions or {}) do
        if c.type=="no_enemy_within" then noEnemy[#noEnemy+1]=tonumber(c.radius or c.value)
        elseif c.type=="nearby_enemies_gte" and tonumber(c.value or 0)>0 then nearby[#nearby+1]={radius=tonumber(c.radius or 600),index=index} end
    end
    for _,r in ipairs(noEnemy) do for _,n in ipairs(nearby) do
        if n.radius<=r then return issue("contradictory_conditions","use",n.index,"nearby_enemies") end
    end end
    local tiny={}
    for _,c in ipairs(rule.use_conditions or {}) do tiny[c.type]=true end
    if tiny.tiny_grab_is_enemy and tiny.tiny_grab_is_ally then return issue("contradictory_conditions","use",0,"tiny_grab_team") end
end
function R.Validate(hero,rule,options)
    options=options or {}
    local errors,warnings={},{}
    local contradiction=R.Contradictions(rule)
    if contradiction then errors[#errors+1]=contradiction end
    local cap=options.capability or A.ForAction(hero,rule.action,{runtime=options.runtime})
    local action=rule.action
    if action.cast_variant and action.cast_variant~="default" then
        errors[#errors+1]=issue("alternate_adapter_unavailable")
    end
    if cap then
        if cap.blocked_reason then errors[#errors+1]=issue(cap.blocked_reason) end
        -- Explicit autocast management uses trigger targets, not native cast targets.
        if cap.teams[(rule.target or {}).team]==0 then errors[#errors+1]=issue("target_team_incompatible") end
        local intersection=false
        for _,t in ipairs((rule.target or {}).types or {}) do if cap.types[t]~=0 then intersection=true end end
        if #((rule.target or {}).types or {})>0 and not intersection then errors[#errors+1]=issue("target_types_incompatible") end
        if action.cast_preference and cap.cast_preferences[action.cast_preference]~=1 then errors[#errors+1]=issue("unsupported_cast_preference") end
        if action.desired_toggle_state~=nil and cap.cast.toggle~=1 then errors[#errors+1]=issue("toggle_not_supported") end
        if action.desired_autocast_state~=nil and cap.cast.autocast~=1 then errors[#errors+1]=issue("autocast_not_supported") end
    end
    if action.state_policy=="mana_hysteresis" then
        local off,on=C.Number(action.state_mana_off),C.Number(action.state_mana_on)
        if not off or not on or off<0 or on>1 or off>=on then errors[#errors+1]=issue("invalid_hysteresis_thresholds") end
        if cap and cap.cast.toggle~=1 and not (cap.cast.autocast==1 and action.desired_autocast_state~=nil) then
            errors[#errors+1]=issue("state_policy_requires_toggle_or_autocast")
        end
    end
    for _,group in ipairs({{"use",rule.use_conditions},{"target",rule.target_filters}}) do
        for index,c in ipairs(group[2] or {}) do
            local reason=A.ConditionReason(cap,group[1],c,(rule.target or {}).team)
            if reason then errors[#errors+1]=issue(reason,group[1],index) end
            local modifier=c.modifier or ((c.type or ""):find("has_modifier",1,true) and c.value or nil)
            if modifier then
                if type(modifier)~="string" or not modifier:match("^[%a_][%w_]*$") then
                    errors[#errors+1]=issue("invalid_modifier_name",group[1],index)
                elseif cap and cap.modifiers_omitted~=1 and not cap.modifiers[modifier] then
                    warnings[#warnings+1]=issue("modifier_not_observed",group[1],index,modifier)
                    if not options.runtime and not bool(rule.allow_unverified_modifiers) then
                        errors[#errors+1]=issue("unverified_modifier_requires_ack",group[1],index,modifier)
                    end
                end
            end
            if c.action_id and options.validate_reference then
                local ok,refReason=options.validate_reference(hero,c.action_actor,c.action_id)
                if not ok then errors[#errors+1]=issue(refReason or "condition_action_not_owned",group[1],index,c.action_id) end
            end
        end
    end
    return #errors==0, errors[1] and errors[1].code or nil, {errors=errors,warnings=warnings,capability=cap}
end
return R
