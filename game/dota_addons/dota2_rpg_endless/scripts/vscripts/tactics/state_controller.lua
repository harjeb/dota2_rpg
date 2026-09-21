-- Toggle and autocast are distinct native states. Never spend a spell to toggle
-- autocast; require native acknowledgement and apply a per-source dwell time.
local C=require("tactics/condition_context")
local S={}
local function clock(ctx) return C.Number(ctx and ctx.now) or C.Call(GameRules,"GetGameTime") or 0 end
function S.IsManaged(spec) return spec.cast_type=="toggle" or spec.cast_type=="autocast" end
function S.Current(spec)
    local method=spec.cast_type=="autocast" and "GetAutoCastState" or "GetToggleState"
    local value=C.Call(spec.source,method)
    if value==true or value==1 then return true end
    if value==false or value==0 then return false end
end
function S.Desired(caster,spec)
    local desired
    if spec.cast_type=="autocast" then desired=spec.desired_autocast_state else desired=spec.desired_toggle_state end
    if spec.state_policy~="mana_hysteresis" then return desired end
    local current=S.Current(spec)
    local mana,max=C.Number(C.Call(caster,"GetMana")),C.Number(C.Call(caster,"GetMaxMana"))
    if current==nil or not mana or not max or max<=0 then return nil end
    local pct=mana/max
    if current and pct<=spec.state_mana_off then return false end
    if not current and pct>=spec.state_mana_on then return true end
    return current
end
function S.CanChange(caster,spec,ctx)
    local current,desired=S.Current(spec),S.Desired(caster,spec)
    if current==nil or desired==nil then return false,"native_state_unavailable" end
    if spec.cast_type=="autocast" then spec.desired_autocast_state=desired else spec.desired_toggle_state=desired end
    local memories=caster.rpgStateControls or {}
    local last=memories[spec.source]
    local now=clock(ctx)
    if last and current==last.desired then last.confirmed=true end
    if current==desired then return false,spec.cast_type .. "_already_in_desired_state" end
    if last and now-last.time<(spec.state_hold_seconds or 0.75) then return false,"state_change_debounce" end
    if last and not last.confirmed and now-last.time<1.5 then return false,"state_change_awaiting_native_ack" end
    return true
end
function S.Issued(caster,spec,ctx)
    caster.rpgStateControls=caster.rpgStateControls or {}
    local desired=spec.desired_toggle_state
    if spec.cast_type=="autocast" then desired=spec.desired_autocast_state end
    caster.rpgStateControls[spec.source]={time=clock(ctx),desired=desired,confirmed=false}
end
function S.Reset(unit) if unit then unit.rpgStateControls=nil end end
return S
