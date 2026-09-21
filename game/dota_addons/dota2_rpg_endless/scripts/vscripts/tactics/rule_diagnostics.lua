-- Bounded per-row diagnostic events; no unit handles or unbounded log flooding.
local C=require("tactics/condition_context")
local D={cache={},revision=0}
function D.Publish(unit,heroKey,event,detail,now)
    local slot=tonumber(detail.rule_index or detail.rule_id)
    if not slot or slot<1 or slot>32 then return end
    local id=C.Call(unit,"entindex"); if not id then return end
    local key=tostring(id)..":"..tostring(slot)
    local previous=D.cache[key]
    -- Throttle even changing failures: a permanently failing rule ticks at 5 Hz.
    if previous and previous.unit==unit and now-previous.time<1 then return end
    D.cache[key]={unit=unit,time=now}
    if not CustomGameEventManager or not CustomGameEventManager.Send_ServerToAllClients then return end
    CustomGameEventManager:Send_ServerToAllClients("rpg_rule_diagnostic", {
        hero_index=id,rule_key=heroKey or "",slot=slot,event=event,
        action_id=detail.action_id or "",reason=tostring(detail.reason or ""),
        conditions=detail.conditions or {},native_targets=detail.native_targets or {},time=now,
        revision=D.revision})
end
function D.Reset()
    D.cache={}; D.revision=D.revision+1
    if CustomGameEventManager and CustomGameEventManager.Send_ServerToAllClients then
        CustomGameEventManager:Send_ServerToAllClients("rpg_rule_diagnostics_reset",{revision=D.revision})
    end
end
return D
