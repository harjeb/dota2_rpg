-- Owned native charge episodes only. An order is not confirmation of a charge.
local C = require("tactics/condition_context")
local Charge = {}
Charge.profiles = {
    windrunner_powershot = {channel=true, stop=true},
    oracle_fortunes_end = {channel=true, stop=true, maximum="channel_time"},
    keeper_of_the_light_illuminate = {channel=true, maximum="max_channel_time", release="keeper_of_the_light_illuminate_end"},
    monkey_king_primal_spring = {channel=true, release="monkey_king_primal_spring_early"},
    ringmaster_tame_the_beasts = {channel=true, release="ringmaster_tame_the_beasts_crack"},
    -- max_charge_time on Onslaught describes travel, not its preparation.
    primal_beast_onslaught = {modifier="modifier_primal_beast_onslaught_windup", maximum="chargeup_time", release="primal_beast_onslaught_release"},
    hoodwink_sharpshooter = {modifier="modifier_hoodwink_sharpshooter_windup", maximum="max_charge_time", release="hoodwink_sharpshooter_release"},
    alchemist_unstable_concoction = {modifier="modifier_alchemist_unstable_concoction", maximum="brew_time", release="alchemist_unstable_concoction_throw", targeted=true},
}
local function number(value)
    value=tonumber(value)
    if value and value==value and value>=0 and value<math.huge then return value end
end
function Charge.Profile(name) return Charge.profiles[name] end
function Charge.Supports(name) return Charge.Profile(name)~=nil end
function Charge.Maximum(ability, profile)
    profile=profile or Charge.Profile(C.Call(ability,"GetAbilityName"))
    if not profile then return nil end
    local value=profile.maximum and number(C.Call(ability,"GetSpecialValueFor",profile.maximum))
    if not value or value<=0 then value=number(C.Call(ability,"GetChannelTime")) end
    if value and value>0 then return value end
end
local function observation(unit, pending, now)
    local p=pending.profile
    if C.Call(unit,"FindAbilityByName",pending.name)~=pending.ability then return nil end
    if C.Call(unit,"IsChanneling")==true then
        if C.Call(unit,"GetCurrentActiveAbility")~=pending.ability then return nil end
        local start=number(C.Call(pending.ability,"GetChannelStartTime"))
        if start and start<=now then return pending.ability,start end
    end
    if p.modifier then
        local modifier=C.Call(unit,"FindModifierByName",p.modifier)
        if modifier and C.Call(modifier,"IsNull")~=true then
            -- Require native creation time: never use submission time as brew time.
            local start=number(C.Call(modifier,"GetCreationTime"))
            local owner=C.Call(modifier,"GetAbility")
            if owner and owner~=pending.ability then return nil end
            if start and start<=now then return modifier,start end
        end
    end
end
function Charge.Requested(unit, state, rule, spec, now)
    local action=rule and rule.action or {}
    if action.charge_mode~="time" and action.charge_mode~="max" then return end
    local name=C.Call(spec.source,"GetAbilityName")
    local profile=Charge.Profile(name)
    local seconds=number(action.charge_time)
    if not profile or (action.charge_mode=="time" and not seconds) then return end
    state.charge={name=name,ability=spec.source,profile=profile,mode=action.charge_mode,
        seconds=seconds,requested_at=now,rule=rule}
end
local function controlled(unit)
    return C.Call(unit,"IsAlive")~=false and C.Call(unit,"IsNull")~=true
        and C.Call(unit,"IsStunned")~=true and C.Call(unit,"IsHexed")~=true
        and C.Call(unit,"IsCommandRestricted")~=true and C.Call(unit,"IsOutOfGame")~=true
end
local function release(engine,unit,pending,ctx)
    local p=pending.profile
    if not controlled(unit) then return false end
    if p.stop then
        -- STOP releases these reviewed charge channels (Powershot / Fortune's End).
        if not DOTA_UNIT_ORDER_STOP then return false end
        return engine.order_gate:Execute({UnitIndex=unit:entindex(),OrderType=DOTA_UNIT_ORDER_STOP,Queue=false})~=false
    end
    local ability=C.Call(unit,"FindAbilityByName",p.release)
    if not ability or C.Call(ability,"IsHidden")~=false or C.Call(ability,"IsActivated")==false
        or (number(C.Call(ability,"GetLevel")) or 0)<=0
        or C.Call(ability,"IsFullyCastable")~=true then return false end
    if C.Call(unit,"IsSilenced")==true then return false end
    local order={UnitIndex=unit:entindex(),AbilityIndex=ability:entindex(),Queue=false,OrderType=DOTA_UNIT_ORDER_CAST_NO_TARGET}
    if p.targeted then
        local spec=engine.actions:Resolve(unit,{kind="ability",name=p.release,logical_id=p.release},ctx)
        if not spec then return false end
        local target=engine:ResolveRuleTarget(pending.rule,spec,ctx)
        if not target or not engine.actions:IsValidTarget(unit,spec,target)
            or not engine.actions:IsInRange(unit,spec,target) then return false end
        order.OrderType=DOTA_UNIT_ORDER_CAST_TARGET;order.TargetIndex=target:entindex()
    end
    return engine.order_gate:Execute(order)~=false
end
function Charge.Continue(engine,unit,state,ctx,rules)
    local pending=state.charge
    if not pending then return false end
    if rules then
        local matching
        for _,rule in ipairs(rules) do
            if rule==pending.rule or (rule.id and rule.id==pending.rule.id) then matching=rule;break end
        end
        local action=matching and matching.action or {}
        if not matching or matching.enabled==false or action.charge_mode~=pending.mode
            or (pending.mode=="time" and number(action.charge_time)~=pending.seconds)
            or (action.name or action.logical_id)~=pending.name then
            state.charge=nil;return false
        end
        pending.rule=matching
    end
    if C.Call(unit,"IsAlive")==false or C.Call(unit,"IsNull")==true then state.charge=nil;return false end
    local token,start=observation(unit,pending,ctx.now)
    if not token then
        if pending.token or ctx.now-pending.requested_at>2 then state.charge=nil;return false end
        -- A different native cast cannot be adopted as confirmation.
        local active=C.Call(unit,"GetCurrentActiveAbility")
        if active and active~=pending.ability then state.charge=nil;return false end
        return true
    end
    if start<pending.requested_at or (pending.token and (pending.token~=token or pending.start~=start)) then
        state.charge=nil;return false
    end
    pending.token=token;pending.start=start
    local maximum=Charge.Maximum(pending.ability,pending.profile)
    local deadline=maximum
    if pending.mode=="time" then deadline=pending.seconds end
    if maximum and deadline then deadline=math.min(maximum,deadline) end
    -- Submission is not confirmation. A throw can be interrupted without ending brew.
    local button=pending.profile.release and C.Call(unit,"FindAbilityByName",pending.profile.release)
    local events=unit.rpgTacticsEvents and unit.rpgTacticsEvents.successes or {}
    local success=events[pending.profile.release or ""]
    local submitted=pending.release_submission
    if submitted then
        local in_phase=C.Call(button,"IsInAbilityPhase")==true
        if success and success.sequence>submitted.sequence then pending.released=true
        elseif not in_phase and ((submitted.saw_phase and ctx.now>submitted.at+0.1) or ctx.now>=submitted.deadline) then
            pending.release_submission=nil
        end
        submitted.saw_phase=submitted.saw_phase or in_phase
    end
    -- Missing native maximum fails closed; native completion still clears the lock.
    if deadline and ctx.now-start>=deadline and not pending.released and not pending.release_submission
        and (pending.release_attempts or 0)<3 and C.Call(button,"IsInAbilityPhase")~=true then
        local sequence=success and success.sequence or 0
        if release(engine,unit,pending,ctx) then
            pending.release_attempts=(pending.release_attempts or 0)+1
            pending.release_submission={at=ctx.now,sequence=sequence,
                deadline=ctx.now+math.max(0.35,(number(C.Call(button,"GetCastPoint")) or 0)+0.15)}
        end
    end
    -- Keep protecting the matching episode while release awaits native completion.
    return true
end
return Charge
