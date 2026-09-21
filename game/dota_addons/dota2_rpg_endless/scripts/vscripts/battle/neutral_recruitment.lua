-- Preparation stores a choice. Battle creates a native neutral and asks the
-- original spell/item to recruit it. Never manufacture allied units or reset
-- mana/cooldowns; native conversion owns duration, stats and replacement caps.
local Recruit={Catalog=require("battle/neutral_recruitment_catalog")}
local sources={
    {name="enchantress_enchant",level="level_req",count="max_creeps"},
    {name="chen_holy_persuasion",level="level_req",count="max_units"},
    {name="item_helm_of_the_dominator",item=true,count="count_limit"},
    {name="item_helm_of_the_overlord",item=true,count="count_limit"},
}
local byName={}
for _,entry in ipairs(Recruit.Catalog) do byName[entry.unit_name]=entry end
local function call(object,method,...)
    if object==nil then return nil end
    local ok,fn=pcall(function() return object[method] end)
    if not ok or type(fn)~="function" then return nil end
    local success,result=pcall(fn,object,...)
    if success then return result end
end
local function valid(unit) return unit~=nil and call(unit,"IsNull")~=true end
local function alive(unit) return valid(unit) and call(unit,"IsAlive")==true end
local function now() return call(GameRules,"GetGameTime") or 0 end
local function heroKey(hero)
    return hero.ruleSnapshotKey or hero.lineupHeroName or hero.benchHeroName or call(hero,"GetUnitName")
end
local function special(ability,key) return tonumber(call(ability,"GetSpecialValueFor",key)) or 0 end
local function source(hero,definition)
    if not definition.item then return call(hero,"FindAbilityByName",definition.name) end
    for slot=0,5 do
        local item=call(hero,"GetItemInSlot",slot)
        if valid(item) and call(item,"GetAbilityName")==definition.name then return item,slot end
    end
end
local function limits(hero,definition,ability)
    local level=tonumber(call(ability,"GetLevel")) or 0
    local maxLevel=definition.level and special(ability,definition.level) or 0
    local ancient=false
    local maxAncients=0
    if definition.name=="item_helm_of_the_overlord" then ancient=special(ability,"is_overlord")>0
    elseif definition.name=="chen_holy_persuasion" then
        local ultimate=call(hero,"FindAbilityByName","chen_hand_of_god")
        maxAncients=valid(ultimate) and (tonumber(call(ultimate,"GetLevel")) or 0)>0
            and math.max(0,math.floor(special(ultimate,"ancient_creeps_scepter"))) or 0
        ancient=maxAncients>0
    end
    return level,maxLevel,ancient,math.max(0,math.floor(special(ability,definition.count))),maxAncients
end
local function eligible(hero,definition,ability,entry)
    if not valid(ability) or not entry then return false end
    local level,maxLevel,ancient,count=limits(hero,definition,ability)
    return level>0 and count>0 and (not definition.level or maxLevel>0)
        and (maxLevel==0 or entry.level<=maxLevel) and (not entry.ancient or ancient)
end
local function isChen(definition) return definition.name=="chen_holy_persuasion" end
-- Custom events may encode array keys as strings. Reject holes, aliases and metadata.
local function normalize(value)
    if type(value)=="string" then return value=="" and {} or {value} end
    if type(value)~="table" then return nil end
    local result,count={},0
    for key,name in pairs(value) do
        local index=tonumber(key)
        if (type(key)~="number" and type(key)~="string") or not index or index<1
            or index~=math.floor(index) or (type(key)=="string" and tostring(index)~=key)
            or type(name)~="string" or name=="" or result[index] then return nil end
        result[index]=name;count=count+1
    end
    for index=1,count do if not result[index] then return nil end end
    return result
end
local function sanitized(hero,definition,ability,saved)
    local result,ancients={},0
    local _,_,_,count,maxAncients=limits(hero,definition,ability)
    for _,name in ipairs(normalize(saved) or {}) do
        local entry=byName[name]
        if #result<count and eligible(hero,definition,ability,entry)
            and (not entry.ancient or ancients<maxAncients) then
            result[#result+1]=name
            if entry.ancient then ancients=ancients+1 end
        end
    end
    return result
end
local function controllable(hero,definition,ability)
    if not alive(hero) or not valid(ability) or call(ability,"IsFullyCastable")~=true
        or call(ability,"IsActivated")==false then return false end
    for _,method in ipairs({"IsStunned","IsHexed","IsCommandRestricted","IsOutOfGame","IsChanneling","IsUsingAbility"}) do
        if call(hero,method)==true then return false end
    end
    return call(hero,definition.item and "IsMuted" or "IsSilenced")~=true
end
local function member(game,hero)
    for _,candidate in ipairs(game.battleManager and game.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS or 2] or {}) do
        if candidate==hero then return true end
    end
    -- Preparation may select a purchased bench hero. The event handler must
    -- authenticate ownership; this module accepts only the game's own roster.
    for _,candidate in pairs(game.benchUnits or {}) do
        if candidate==hero then return true end
    end
    return false
end
function Recruit.GetOptions(game,hero)
    local options={}
    if not valid(hero) then return options end
    for _,definition in ipairs(sources) do
        local ability,slot=source(hero,definition)
        if valid(ability) then
            local level,maxLevel,ancient,count,maxAncients=limits(hero,definition,ability)
            local units={}
            for _,entry in ipairs(Recruit.Catalog) do
                if eligible(hero,definition,ability,entry) then
                    units[#units+1]={unit_name=entry.unit_name,level=entry.level,ancient=entry.ancient}
                end
            end
            local selected=(game.neutralRecruitChoices or {})[heroKey(hero)] or {}
            local states=(game.neutralRecruitStates or {})[hero] or {}
            options[#options+1]={source_name=definition.name,source_level=level,item_slot=slot,
                max_level=maxLevel,max_count=count,allow_ancient=ancient,units=units,
                selected_unit=not isChen(definition) and selected[definition.name] or "",
                selected_units=isChen(definition) and sanitized(hero,definition,ability,selected[definition.name]) or nil,
                max_ancients=isChen(definition) and maxAncients or nil,ready=controllable(hero,definition,ability),
                status=level==0 and "unlearned" or (states[definition.name] and states[definition.name].status or "selected")}
        end
    end
    return options
end
function Recruit.Select(game,hero,sourceName,unitName)
    if game.phase~="setup" or not valid(hero) or not member(game,hero) then return false,"invalid_phase_or_hero" end
    local definition
    for _,entry in ipairs(sources) do if entry.name==sourceName then definition=entry;break end end
    if not definition then return false,"invalid_source" end
    local ability=source(hero,definition)
    if isChen(definition) then
        unitName=normalize(unitName)
        if not unitName then return false,"invalid_unit_list" end
        if #sanitized(hero,definition,ability,unitName)~=#unitName then return false,"ineligible_unit" end
    else
        if type(unitName)=="table" then return false,"invalid_unit_list" end
        unitName=tostring(unitName or "")
        if unitName~="" and not eligible(hero,definition,ability,byName[unitName]) then return false,"ineligible_unit" end
    end
    game.neutralRecruitChoices=game.neutralRecruitChoices or {}
    local key=heroKey(hero)
    if key==nil then return false,"invalid_hero_identity" end
    game.neutralRecruitChoices[key]=game.neutralRecruitChoices[key] or {}
    game.neutralRecruitChoices[key][sourceName]=unitName~="" and unitName or nil
    return true
end
function Recruit.IsReserved(unit)
    return valid(unit) and unit.rpg_recruit_pending==true
        and call(unit,"GetTeamNumber")== (DOTA_TEAM_NEUTRALS or 4)
end
function Recruit.IsBusy(game,hero)
    local state=(game.neutralRecruitActive or {})[hero]
    return state~=nil and Recruit.IsReserved(state.unit) and now()<state.deadline
end
function Recruit.Candidates(game,hero,sourceName)
    local state=(game.neutralRecruitActive or {})[hero]
    if state and state.definition.name==sourceName and Recruit.IsReserved(state.unit) then return {state.unit} end
    return {}
end
local function restore(hero,state)
    if valid(hero) then
        call(hero,"SetIdleAcquire",state.idleAcquire)
        if state.acquisitionRange~=nil then call(hero,"SetAcquisitionRange",state.acquisitionRange) end
    end
end
local function finish(game,hero,state,status,remove)
    if remove and valid(state.unit) then call(state.unit,"RemoveSelf") end
    if valid(state.unit) then state.unit.rpg_recruit_pending=nil;call(state.unit,"RemoveModifierByName","modifier_rpg_neutral_recruit_pending") end
    state.status=status
    if state.choices then state.status="waiting";state.issued=nil end
    restore(hero,state)
    game.neutralRecruitActive[hero]=nil
end
function Recruit.Clear(game,resetChoices)
    for hero,state in pairs(game.neutralRecruitActive or {}) do restore(hero,state) end
    for unit in pairs(game.neutralRecruitUnits or {}) do if valid(unit) then call(unit,"RemoveSelf") end end
    game.neutralRecruitUnits={};game.neutralRecruitActive={};game.neutralRecruitStates={}
    game.neutralRecruitBattle=false
    if resetChoices then game.neutralRecruitChoices={} end
end
function Recruit.Precache(context)
    if type(PrecacheUnitByNameSync)=="function" then
        for _,entry in ipairs(Recruit.Catalog) do PrecacheUnitByNameSync(entry.spawn_name,context,-1) end
    end
end
local function filter(hero,ability,target)
    -- Native C++ abilities do not expose Lua CastFilterResultTarget. Use the
    -- engine UnitFilter plus audited live limits; the cast itself still runs
    -- the original ability's additional native conversion checks.
    if type(UnitFilter)~="function" then return false end
    local team=call(ability,"GetAbilityTargetTeam")
    local types=call(ability,"GetAbilityTargetType")
    local flags=call(ability,"GetAbilityTargetFlags")
    if team==nil or types==nil or flags==nil then return false end
    local ok,result=pcall(UnitFilter,target,team,types,flags,call(hero,"GetTeamNumber"))
    if not ok or result~=(UF_SUCCESS or 0) then return false end
    local custom=call(ability,"CastFilterResultTarget",target)
    return custom==nil or custom==(UF_SUCCESS or 0)
end
local function spawn(game,hero,definition,ability,entry,state)
    local origin=call(hero,"GetAbsOrigin")
    if origin==nil or type(CreateUnitByName)~="function" then state.status="spawn_failed";return end
    local point=type(Vector)=="function" and Vector(origin.x+96,origin.y,origin.z) or origin
    local ok,target=pcall(CreateUnitByName,entry.spawn_name,point,true,nil,nil,DOTA_TEAM_NEUTRALS or 4)
    if not ok or not valid(target) then state.status="spawn_failed";return end
    target.rpg_recruit_pending=true
    call(target,"SetIdleAcquire",false);call(target,"SetAcquisitionRange",0)
    call(target,"SetMinimumGoldBounty",0);call(target,"SetMaximumGoldBounty",0);call(target,"SetDeathXP",0)
    call(target,"AddNewModifier",hero,nil,"modifier_rpg_neutral_recruit_pending",{})
    -- Native CreateUnitByName does not consistently train neutral ability slots.
    for index=0,23 do
        local spell=call(target,"GetAbilityByIndex",index)
        if valid(spell) and (tonumber(call(spell,"GetLevel")) or 0)==0 then call(spell,"SetLevel",1) end
    end
    state.unit=target;state.definition=definition;state.ability=ability;state.deadline=now()+8
    state.idleAcquire=call(hero,"GetIdleAcquire")
    if state.idleAcquire==nil then state.idleAcquire=call(hero,"IsIdleAcquire") end
    if state.idleAcquire==nil then state.idleAcquire=not hero.rpg_debug_manual_cast or hero.rpg_debug_auto_acquire==true end
    state.acquisitionRange=call(hero,"GetAcquisitionRange")
    state.status="pending";state.nextOrder=0
    game.neutralRecruitUnits[target]={hero=hero,source=definition.name,ancient=entry.ancient}
    game.neutralRecruitActive[hero]=state
    -- This auxiliary cast can happen before the tactic engine's first unit
    -- evaluation. Install its native success observer now, so prerequisites
    -- see the actual spell execution even while normal orders are paused.
    require("tactics/native_events").Attach(hero)
    call(hero,"SetIdleAcquire",false);call(hero,"SetAcquisitionRange",0)
end
-- Include native controlled units as well as this battle's generated targets.
local function controlled(game,hero)
    local seen,count,ancients={},0,0
    local function add(unit,record)
        if seen[unit] or not alive(unit) then return end
        seen[unit]=true
        if call(unit,"GetTeamNumber")~=call(hero,"GetTeamNumber") then return end
        local owner=call(unit,"GetOwnerEntity") or call(unit,"GetOwner")
        local owned=owner==hero
        local persuaded=call(unit,"HasModifier","modifier_chen_holy_persuasion")
        local generated=record and record.hero==hero and record.source=="chen_holy_persuasion"
            and (owner==nil or owned) and persuaded~=false
        if generated or (owned and persuaded==true) then
            count=count+1
            if (record and record.ancient) or call(unit,"IsAncient")==true then ancients=ancients+1 end
        end
    end
    for unit,record in pairs(game.neutralRecruitUnits or {}) do add(unit,record) end
    for _,className in ipairs({"npc_dota_creature","npc_dota_creep_neutral"}) do
        for _,unit in ipairs(call(Entities,"FindAllByClassname",className) or {}) do add(unit) end
    end
    return count,ancients
end
local function withinCapacity(game,hero,state)
    if not state.choices then return true end
    local _,_,_,cap,ancientCap=limits(hero,state.definition,state.ability)
    local count,ancients=controlled(game,hero)
    local entry=byName[state.unitName]
    return state.attempts<=cap and count<cap and (not entry.ancient
        or (state.ancientAttempts<=ancientCap and ancients<ancientCap))
end
local function nextChoice(game,hero,definition,ability,state)
    local _,_,_,cap,ancientCap=limits(hero,definition,ability)
    if state.cursor>=#state.choices then state.status="complete";return nil end
    -- A live cap can fall and recover; preserve unconsumed choices without
    -- refilling any choice already attempted earlier in this battle.
    if state.attempts>=cap then return nil end
    local count,ancients=controlled(game,hero)
    if count>=cap then return nil end
    while state.cursor<#state.choices do
        local name=state.choices[state.cursor+1]
        local entry=byName[name]
        if eligible(hero,definition,ability,entry) then
            if entry.ancient and (state.ancientAttempts>=ancientCap or ancients>=ancientCap) then return nil end
            state.cursor=state.cursor+1
            return name
        end
        state.cursor=state.cursor+1
    end
    state.status="complete"
end
function Recruit.OnThink(game)
    if game.phase~="fight" then
        if game.neutralRecruitBattle then Recruit.Clear(game,false) end
        return
    end
    if not game.neutralRecruitBattle then
        game.neutralRecruitBattle=true;game.neutralRecruitStates={};game.neutralRecruitActive={};game.neutralRecruitUnits={}
        for _,hero in ipairs(game.battleManager and game.battleManager.teamHeroes[DOTA_TEAM_GOODGUYS or 2] or {}) do
            local states={}
            for name,unitName in pairs((game.neutralRecruitChoices or {})[heroKey(hero)] or {}) do
                states[name]={unitName=type(unitName)=="string" and unitName or nil,
                    choices=name=="chen_holy_persuasion" and (normalize(unitName) or {}) or nil,
                    cursor=0,attempts=0,ancientAttempts=0,status="waiting"}
            end
            game.neutralRecruitStates[hero]=states
        end
    end
    for unit,record in pairs(game.neutralRecruitUnits) do
        -- Converted companions follow native death/duration/ownership rules,
        -- including surviving their original recruiter and enemy theft. Only
        -- unconverted reserved targets depend on a living original recruiter.
        if not alive(unit) or (Recruit.IsReserved(unit) and not alive(record.hero)) then
            if valid(unit) then call(unit,"RemoveSelf") end
            game.neutralRecruitUnits[unit]=nil
        end
    end
    for hero,states in pairs(game.neutralRecruitStates) do
        local active=game.neutralRecruitActive[hero]
        if active then
            if not alive(active.unit) then finish(game,hero,active,"dead",true)
            elseif call(active.unit,"GetTeamNumber")~=(DOTA_TEAM_NEUTRALS or 4) then
                -- Observe native conversion before recruiter death/timeout: both
                -- can occur in one tick. Native theft also ends our reservation.
                local status=call(active.unit,"GetTeamNumber")==call(hero,"GetTeamNumber") and "recruited" or "stolen"
                finish(game,hero,active,status,false)
                require("battle/summon_behavior").OnSpawn(game,active.unit)
            elseif not alive(hero) then finish(game,hero,active,"dead",true)
            elseif now()>=active.deadline then finish(game,hero,active,"cast_failed",true)
            elseif source(hero,active.definition)~=active.ability
                or not eligible(hero,active.definition,active.ability,byName[active.unitName])
                or not withinCapacity(game,hero,active) then
                finish(game,hero,active,"source_changed",true)
            elseif active.issued then
                -- One submitted native cast. Do not cancel its cast point with
                -- repeated orders, and do not fabricate success after rejection.
            elseif controllable(hero,active.definition,active.ability) then
                if not filter(hero,active.ability,active.unit) then finish(game,hero,active,"native_filter_rejected",true)
                else
                    local gate=game.tacticBridge and game.tacticBridge.orderGate
                    if gate and gate:Execute({UnitIndex=call(hero,"entindex"),OrderType=DOTA_UNIT_ORDER_CAST_TARGET,
                        AbilityIndex=call(active.ability,"entindex"),TargetIndex=call(active.unit,"entindex"),Queue=false})==true then
                        active.issued=true
                    else finish(game,hero,active,"order_failed",true) end
                end
            end
        elseif alive(hero) then
            for _,definition in ipairs(sources) do
                local state=states[definition.name]
                if state and state.status=="waiting" then
                    local ability=source(hero,definition)
                    if state.choices then
                        -- Peek only when ready; waiting for native resources never consumes a choice.
                        if controllable(hero,definition,ability) then
                            state.unitName=nextChoice(game,hero,definition,ability,state)
                        else state.unitName=nil end
                    end
                    local entry=byName[state.unitName]
                    if state.choices and not entry then
                        -- Exhausted or waiting for native resources.
                    elseif not eligible(hero,definition,ability,entry) then state.status="ineligible"
                    elseif controllable(hero,definition,ability) then
                        if state.choices then
                            state.attempts=state.attempts+1
                            if entry.ancient then state.ancientAttempts=state.ancientAttempts+1 end
                        end
                        spawn(game,hero,definition,ability,entry,state)
                        if state.choices and state.status=="spawn_failed" then state.status="waiting" end
                        break
                    end
                end
            end
        end
    end
end
-- Pending creeps remain valid native spell targets. Damage/attacks cannot farm
-- them while waiting. States release immediately on native team conversion,
-- before the next think, so no protection leaks onto the recruited summon.
if type(LinkLuaModifier)=="function" then
    LinkLuaModifier("modifier_rpg_neutral_recruit_pending","battle/neutral_recruitment",LUA_MODIFIER_MOTION_NONE or 0)
end
if type(class)=="function" then
    modifier_rpg_neutral_recruit_pending=class({})
    local Modifier=modifier_rpg_neutral_recruit_pending
    function Modifier:IsHidden() return true end
    function Modifier:IsPurgable() return false end
    function Modifier:CheckState()
        if not Recruit.IsReserved(self:GetParent()) then return {} end
        return {[MODIFIER_STATE_ROOTED]=true,[MODIFIER_STATE_DISARMED]=true,
            [MODIFIER_STATE_ATTACK_IMMUNE]=true,[MODIFIER_STATE_SILENCED]=true,[MODIFIER_STATE_NO_UNIT_COLLISION]=true}
    end
    function Modifier:DeclareFunctions()
        return {MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_PHYSICAL,MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_MAGICAL,
            MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_PURE}
    end
    function Modifier:GetAbsoluteNoDamagePhysical() return Recruit.IsReserved(self:GetParent()) and 1 or 0 end
    Modifier.GetAbsoluteNoDamageMagical=Modifier.GetAbsoluteNoDamagePhysical
    Modifier.GetAbsoluteNoDamagePure=Modifier.GetAbsoluteNoDamagePhysical
end
return Recruit
