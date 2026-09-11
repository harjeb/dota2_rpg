-- One authoritative runtime contract for the editor, save service and executor.
-- Capability is not availability: cooldown, silence, level, hidden phase and
-- temporary target immunity must never permanently rewrite a player's rule.
local C=require("tactics/condition_context")
local B=require("tactics/ability_behavior")
local Native=require("tactics/native_targeting")
local L=require("tactics/action_lifecycle")
local Profiles=require("tactics/ability_profiles")
local Modifiers=require("tactics/modifier_catalog")
local A={VERSION=1}
local function yes(v) return v and 1 or 0 end
local function flag(mask,name) return B.HasFlag(mask,_G[name]) end
function A.Source(hero,action)
    if not action then return nil end
    local name=action.name or action.logical_id
    if action.kind=="ability" then return C.Call(hero,"FindAbilityByName",name) end
    if action.kind=="item" then
        for slot=0,8 do
            local item=C.Call(hero,"GetItemInSlot",slot)
            if C.Call(item,"GetAbilityName")==name then return item end
        end
    end
end
local function triFlag(mask,name,invert)
    if mask==nil or type(_G[name])~="number" then return -1 end
    local value=flag(mask,name)
    if invert then value=not value end
    return yes(value)
end
function A.Describe(hero,source,action,options)
    action=action or {}; options=options or {}
    if not source or C.Call(source,"IsNull")==true then return nil end
    local name=C.Call(source,"GetAbilityName") or action.name or action.logical_id or ""
    if source.GetBehavior == nil and source.GetBehaviorInt == nil then return nil end
    local mask=B.Read(source)
    local unit=flag(mask,"DOTA_ABILITY_BEHAVIOR_UNIT_TARGET")
    local point=flag(mask,"DOTA_ABILITY_BEHAVIOR_POINT")
    local none=flag(mask,"DOTA_ABILITY_BEHAVIOR_NO_TARGET")
    local toggle=flag(mask,"DOTA_ABILITY_BEHAVIOR_TOGGLE")
    local autocast=flag(mask,"DOTA_ABILITY_BEHAVIOR_AUTOCAST")
    local vector=flag(mask,"DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING")
    local autoManaged=autocast and action.desired_autocast_state~=nil
    local mode=toggle and "toggle" or point and "point" or unit and "unit" or none and "none" or "unsupported"
    if action.cast_preference=="unit" and unit and not vector and not toggle then mode="unit" end
    if action.cast_preference=="point" and point and not vector and not toggle then mode="point" end
    if vector then mode="vector" end
    if autoManaged then mode="autocast" end
    local nativeTeam,nativeTypes=Native.ResolveMasks(source,C.Call(source,"GetAbilityTargetTeam"),C.Call(source,"GetAbilityTargetType"))
    local targetFlags=C.Number(C.Call(source,"GetAbilityTargetFlags"))
    local nativeUnit=mode=="unit" or (mode=="vector" and unit and not point)
    local modifiers,modifierDetails={},{}
    if not options.runtime then modifiers,modifierDetails=Modifiers.List(hero,source) end
    local cap={version=A.VERSION,name=name,mode=mode,
        role=nativeUnit and "native_unit" or (mode=="point" or mode=="vector") and "anchor" or "trigger",
        teams={self=1,ally=1,enemy=1},types={hero=1,monster=1,summon=1},
        cast={unit=yes(unit),point=yes(point),none=yes(none),toggle=yes(toggle),autocast=yes(autocast),vector=yes(vector)},
        cast_preferences={auto=1,unit=yes(unit and not vector and not toggle),point=yes(point and not vector and not toggle)},
        variants={default=1,alternate=0},alternate_native=yes(flag(mask,"DOTA_ABILITY_BEHAVIOR_ALT_CASTABLE")),
        alternate_reason="alternate_adapter_unavailable",
        channelled=yes(flag(mask,"DOTA_ABILITY_BEHAVIOR_CHANNELLED")),
        release_parent=L.release_parents[name] or "",
        magic_immune_enemy=-1,magic_immune_ally=-1,
        modifiers=modifiers,modifier_details=modifierDetails,modifiers_omitted=options.runtime and 1 or 0,support="generic_unreviewed",
        supported_expression=yes((Profiles[name] or {}).supported_expression),
        requires_runtime_validation=1}
    if nativeUnit then
        -- CUSTOM is not a generic bit mask. Reviewed translations live in
        -- native_targeting.lua; other custom semantics stay runtime-only.
        if nativeTeam and nativeTeam>0 and nativeTeam~=(DOTA_UNIT_TARGET_TEAM_CUSTOM or 4) then
            local friendly=flag(nativeTeam,"DOTA_UNIT_TARGET_TEAM_FRIENDLY")
            local enemy=flag(nativeTeam,"DOTA_UNIT_TARGET_TEAM_ENEMY")
            if type(DOTA_UNIT_TARGET_TEAM_FRIENDLY)=="number" and type(DOTA_UNIT_TARGET_TEAM_ENEMY)=="number" then
                cap.teams={self=yes(friendly),ally=yes(friendly),enemy=yes(enemy)}
            end
        end
        if Native.RejectsSelf(source,hero,hero) or flag(targetFlags,"DOTA_UNIT_TARGET_FLAG_NOT_SELF") then cap.teams.self=0 end
        if nativeTypes and nativeTypes>0 and nativeTypes~=(DOTA_UNIT_TARGET_CUSTOM or 128)
            and type(DOTA_UNIT_TARGET_HERO)=="number" and type(DOTA_UNIT_TARGET_BASIC)=="number" then
            local heroType=flag(nativeTypes,"DOTA_UNIT_TARGET_HERO")
            local basic=flag(nativeTypes,"DOTA_UNIT_TARGET_BASIC") or flag(nativeTypes,"DOTA_UNIT_TARGET_CREEP")
                or flag(nativeTypes,"DOTA_UNIT_TARGET_COURIER")
            cap.types={hero=yes(heroType),monster=yes(basic),summon=yes(heroType or basic)}
        end
        cap.magic_immune_enemy=triFlag(targetFlags,"DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES")
        cap.magic_immune_ally=triFlag(targetFlags,"DOTA_UNIT_TARGET_FLAG_NOT_MAGIC_IMMUNE_ALLIES",true)
    end
    local treeOnly=type(DOTA_UNIT_TARGET_TREE)=="number" and nativeTypes==DOTA_UNIT_TARGET_TREE and not point
    if treeOnly or mode=="unsupported" or (vector and not unit and not point) then
        cap.blocked_reason="special_adapter_required"
    end
    if cap.supported_expression==1 then cap.support="generic" end
    if cap.channelled==1 or autocast or toggle or vector or cap.alternate_native==1 or cap.release_parent~="" then
        cap.support="partial"
    end
    if cap.blocked_reason then cap.support="adapter_required" end
    if nativeUnit then
        cap.native_unit_contract={teams=cap.teams,types=cap.types,magic_immune_enemy=cap.magic_immune_enemy,magic_immune_ally=cap.magic_immune_ally}
    elseif unit and not action._native_contract then
        local nativeAction={kind=action.kind,name=name,logical_id=name,cast_preference="unit",_native_contract=true}
        local nativeCap=A.Describe(hero,source,nativeAction,options)
        if nativeCap and nativeCap.role=="native_unit" then
            cap.native_unit_contract={teams=nativeCap.teams,types=nativeCap.types,magic_immune_enemy=nativeCap.magic_immune_enemy,magic_immune_ally=nativeCap.magic_immune_ally}
        end
    end
    return cap
end
function A.ForAction(hero,action,options)
    options=options or {}
    local kind=action and action.kind
    if kind=="attack" or kind=="move" or kind=="wait" then
        local modifiers,modifierDetails={},{}
        if not options.runtime then modifiers,modifierDetails=Modifiers.List(hero,nil) end
        return {version=A.VERSION,name=action.logical_id or kind,mode=kind,role="trigger",support="builtin",
            teams={self=1,ally=1,enemy=1},types={hero=1,monster=1,summon=1},cast={},cast_preferences={auto=1},
            variants={default=1},
            modifiers=modifiers,modifier_details=modifierDetails,modifiers_omitted=options.runtime and 1 or 0,magic_immune_enemy=-1,magic_immune_ally=-1,release_parent=""}
    end
    return A.Describe(hero,A.Source(hero,action),action,options)
end
function A.ConditionReason(cap,group,condition,team)
    if not cap then return nil end
    local id=condition.type or ""
    if id:match("^tiny_grab_") and cap.name~="tiny_toss" then return "condition_requires_tiny_toss" end
    if id=="release_action_available" and cap.release_parent=="" then return "condition_requires_release_action" end
    local ownActor=not condition.action_actor or condition.action_actor=="" or condition.action_actor=="self"
    local needsChannel=id=="channel_elapsed_gte" or id=="channel_elapsed_lte"
        or (id=="action_phase_is" and condition.value=="CHANNELING")
    if needsChannel and ownActor then
        if cap.release_parent=="" then return "channel_requires_release_or_other_actor" end
        if condition.action_id and condition.action_id~=cap.release_parent then return "channel_reference_not_parent" end
    end
    if id=="action_phase_is" and condition.value=="CASTING" and ownActor then return "casting_phase_cannot_be_interrupted" end
    if group~="target" then return nil end
    if id=="exclude_self" and team=="self" then return "self_excluded" end
    if id=="specified_enemy" and team~="enemy" then return "invalid_specified_enemy_team" end
    if id=="is_spell_immune" then
        local allowed=team=="enemy" and cap.magic_immune_enemy or cap.magic_immune_ally
        if allowed==0 then return "condition_conflicts_with_native_targeting" end
    end
end
return A
