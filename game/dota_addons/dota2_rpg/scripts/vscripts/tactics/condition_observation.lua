-- Bounded, scalar-only diagnostics. Missing observations stay "unknown".
local C=require("tactics/condition_context")
local L=require("tactics/action_lifecycle")
local O={}
local function scalar(v)
    if type(v)=="number" then
        if v~=v then return "unknown" end
        if v==math.huge then return "infinite" end
        if v==-math.huge then return "negative_infinite" end
        return v
    end
    if type(v)=="boolean" then return v and "true" or "false" end
    if type(v)=="string" then return v:sub(1,256) end
    return "unknown"
end
function O.Actual(ctx,c,unit)
    local id=(c.type or ""):gsub("^self_", "")
    local base=id:gsub("_gte$", ""):gsub("_lte$", ""):gsub("_lt$", "")
    if base=="hp_pct" or base=="mana_pct" then
        local hp=base=="hp_pct"
        local value=C.Number(C.Call(unit,hp and "GetHealth" or "GetMana"))
        local max=C.Number(C.Call(unit,hp and "GetMaxHealth" or "GetMaxMana"))
        if value and max and max>0 then return math.max(0,math.min(1,value/max)) end
    elseif base=="health" then return C.Call(unit,"GetHealth")
    elseif base=="missing_health" then
        local a,b=C.Number(C.Call(unit,"GetMaxHealth")),C.Number(C.Call(unit,"GetHealth"))
        if a and b then return math.max(0,a-b) end
    elseif base=="distance" then
        local a,b=C.Call(ctx.caster,"GetAbsOrigin"),C.Call(unit,"GetAbsOrigin")
        if a and b then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
    elseif base=="has_modifier" or base=="not_has_modifier" then
        return C.Call(unit,"HasModifier",c.modifier or c.value)
    elseif base=="modifier_stacks" or base=="modifier_remaining" then
        return C.ModifierValue(unit,c.modifier,base=="modifier_stacks" and "GetStackCount" or "GetRemainingTime")
    elseif base=="elapsed" then return ctx.elapsed
    elseif base=="alive_enemy_count" or base=="alive_ally_count" then return ctx[base]
    elseif base=="nearby_enemies" or base=="nearby_allies" then
        local fn=ctx[base=="nearby_enemies" and "count_enemies_around" or "count_allies_around"]
        if fn then return fn(ctx.caster,tonumber(c.radius or 600)) end
    elseif base=="is_spell_immune" or base=="not_spell_immune" then return C.Call(unit,"IsMagicImmune")
    elseif base=="channel_elapsed" or base=="action_phase_is" or base=="action_elapsed" or base=="action_use_count" or base=="ability_charges" then
        local actor=ctx.caster
        if c.action_actor and ctx.get_action_actor then actor=ctx.get_action_actor(c.action_actor) end
        if not actor then return nil end
        local name=c.action_id or ctx.current_action_id
        if ctx.resolve_action_name then name=ctx.resolve_action_name(actor,name) end
        if not c.action_id and (base=="channel_elapsed" or base=="action_phase_is") then name=L.release_parents[name] or name end
        if base=="channel_elapsed" then return L.ChannelElapsed(actor,name,ctx.now)
        elseif base=="action_phase_is" then return L.Phase(actor,name,ctx.now) end
        local fn=ctx[base=="action_elapsed" and "get_action_elapsed" or base=="action_use_count" and "get_action_use_count" or "get_ability_charges"]
        if fn then return fn(actor,name) end
    elseif base=="release_action_available" then return L.CanRelease(ctx.caster,ctx.current_action_spec)
    elseif base=="always" then return true end
end
function O.Record(ctx,group,index,c,unit,passed,err)
    if not ctx.condition_trace or #ctx.condition_trace>=24 then return end
    local ok,actual=pcall(O.Actual,ctx,c,unit)
    if not ok then actual=nil end
    ctx.condition_trace[#ctx.condition_trace+1]={group=group,index=index,type=c.type,
        expected=scalar(c.seconds or c.value or c.modifier or true),actual=scalar(actual),
        passed=passed and 1 or 0,error=err and tostring(err):sub(1,160) or "",
        target_index=C.Call(unit,"entindex") or -1}
end
return O
