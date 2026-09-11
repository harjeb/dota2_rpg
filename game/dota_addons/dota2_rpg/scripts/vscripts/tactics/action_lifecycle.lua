-- Native observations and submitted orders have deliberately separate clocks.
local C = require("tactics/condition_context")
local L = {}
L.release_parents = {
    keeper_of_the_light_illuminate_end="keeper_of_the_light_illuminate",
    hoodwink_sharpshooter_release="hoodwink_sharpshooter",
    primal_beast_onslaught_release="primal_beast_onslaught",
    ringmaster_tame_the_beasts_crack="ringmaster_tame_the_beasts",
    monkey_king_primal_spring_early="monkey_king_primal_spring",
    phoenix_sun_ray_stop="phoenix_sun_ray",
}
local function state(unit)
    if not unit then return nil end
    unit.rpgActionLifecycle=unit.rpgActionLifecycle or {actions={}}
    return unit.rpgActionLifecycle
end
local function entry(unit,name)
    local s=state(unit)
    s.actions[name]=s.actions[name] or {phase="IDLE"}
    return s.actions[name],s
end
function L.Requested(unit,name,now)
    if not name or name=="" then return end
    local e=entry(unit,name)
    e.requested_at=now
    -- A native callback can run synchronously inside order submission.
    if not e.executed_at or e.executed_at<now then
        e.phase="REQUESTED"; e.executed_at=nil; e.channel_started_at=nil; e.cast_started_at=nil; e.ended_at=nil
    end
end
function L.Executed(unit,name,now)
    local e=entry(unit,name)
    e.executed_at=now
    if e.phase~="CHANNELING" then e.phase="EXECUTED" end
end
function L.ChannelEnded(unit,name,now,interrupted)
    local e=entry(unit,name)
    e.ended_at=now
    -- Unknown interruption status is not falsely reported as completion.
    e.phase=interrupted==true and "INTERRUPTED" or interrupted==false and "FINISHED" or "ENDED"
end
function L.Observe(unit,now)
    local s=state(unit)
    local active=C.Call(unit,"GetCurrentActiveAbility")
    local name=C.Call(active,"GetAbilityName")
    local channeling=C.Call(unit,"IsChanneling")==true
    if name and (channeling or C.Call(active,"IsInAbilityPhase")==true) then
        if s.current and s.current~=name then
            local previous=s.actions[s.current]
            if previous and (previous.phase=="CHANNELING" or previous.phase=="CASTING") then
                L.ChannelEnded(unit,s.current,now,nil)
            end
        end
        local e=entry(unit,name)
        if channeling then
            local started=C.Number(C.Call(active,"GetChannelStartTime"))
            if e.phase~="CHANNELING" then
                e.channel_started_at=started and started>=0 and started<=now and started or now
            end
            e.phase="CHANNELING"
        else
            e.phase="CASTING"; e.cast_started_at=e.cast_started_at or now
        end
        s.current=name
    elseif not channeling and s.current then
        local e=s.actions[s.current]
        if e and e.phase=="CHANNELING" then L.ChannelEnded(unit,s.current,now,nil)
        elseif e and e.phase=="CASTING" and not e.executed_at then e.phase="INTERRUPTED" end
        s.current=nil
    end
    for _,e in pairs(s.actions) do
        if e.phase=="REQUESTED" and now-(e.requested_at or now)>2 then e.phase="UNCONFIRMED" end
    end
    return s
end
function L.ChannelElapsed(unit,name,now)
    local s=L.Observe(unit,now)
    local active=C.Call(unit,"GetCurrentActiveAbility")
    local activeName=C.Call(active,"GetAbilityName")
    name=name or activeName
    if C.Call(unit,"IsChanneling")~=true or name~=activeName then return nil end
    local e=s.actions[name]
    return e and e.channel_started_at and math.max(0,now-e.channel_started_at) or nil
end
function L.Phase(unit,name,now)
    local s=L.Observe(unit,now)
    return s.actions[name] and s.actions[name].phase or "IDLE"
end
function L.CanRelease(unit,spec)
    if not spec or not spec.source then return false end
    local name=C.Call(spec.source,"GetAbilityName")
    local parent=L.release_parents[name]
    if not parent or C.Call(unit,"IsChanneling")~=true then return false end
    local active=C.Call(unit,"GetCurrentActiveAbility")
    if C.Call(active,"GetAbilityName")~=parent then return false end
    if C.Call(unit,"FindAbilityByName",name)~=spec.source then return false end
    return C.Call(spec.source,"IsHidden")==false and C.Call(spec.source,"IsActivated")~=false
        and (C.Number(C.Call(spec.source,"GetLevel")) or 0)>0
end
function L.Reset(unit) if unit then unit.rpgActionLifecycle=nil end end
return L
