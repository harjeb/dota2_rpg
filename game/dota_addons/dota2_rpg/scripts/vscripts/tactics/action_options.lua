-- Authoring fields preserved identically by legacy conversion, snapshots and saves.
local O={fields={"desired_autocast_state","cast_variant","state_policy","state_mana_on","state_mana_off","state_hold_seconds"}}
function O.Copy(source,target)
    for _,field in ipairs(O.fields) do if source[field]~=nil and source[field]~="" then target[field]=source[field] end end
    local value=target.desired_autocast_state
    if value=="1" or value==1 then target.desired_autocast_state=true end
    if value=="0" or value==0 then target.desired_autocast_state=false end
    return target
end
function O.Validate(action)
    local C=require("tactics/condition_context")
    if action.desired_autocast_state~=nil and type(action.desired_autocast_state)~="boolean" then return false,"invalid_autocast_state" end
    if action.cast_variant~=nil and action.cast_variant~="default" and action.cast_variant~="alternate" then return false,"invalid_cast_variant" end
    if action.state_policy~=nil and action.state_policy~="fixed" and action.state_policy~="mana_hysteresis" then return false,"invalid_state_policy" end
    for _,field in ipairs({"state_mana_on","state_mana_off","state_hold_seconds"}) do
        if action[field]~=nil then
            local n=C.Number(action[field]); local lo,hi=0,1
            if field=="state_hold_seconds" then lo,hi=0.1,10 end
            if not n or n<lo or n>hi then return false,"invalid_"..field end
            action[field]=n
        end
    end
    return true
end
return O
