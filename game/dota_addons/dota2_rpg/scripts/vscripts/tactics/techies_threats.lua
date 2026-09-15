-- Native object observations, never planting orders or guessed cursor mines.
-- Evidence: dotabuff/d2vpkr dota/scripts/npc/npc_units.txt (mine names/baseclass),
-- dota/resource/localization/abilities_english.txt (primary Sticky slow, Tazer),
-- and data/native_skill_conditions.json (ability specials).
-- Sticky phase names additionally verified in SteamTracking/GameTracking-Dota2
-- game/dota/bin/win64/server_strings.txt. Native private proximity timers are
-- not exposed: the visible-entry deadline below is a conservative estimate.
local M = {}
local objects, roster, sequence, nextScan = {}, {}, 1000000000, -math.huge
local signs = {}
local SIGN = 'npc_dota_techies_minefield_sign'
local SIGN_ABILITY = 'techies_minefield_sign'
local SIGN_THINKER = 'modifier_techies_minefield_sign_thinker'
local SIGN_ACTIVE = 'modifier_techies_minefield_sign_scepter'
local signTrigger = {radius='trigger_radius',envelope=true,state='trigger'}
local signActive = {radius='aura_radius',envelope=true,state='active'}
local SCAN_INTERVAL, MEMORY = .2, 3
local mines = {
    npc_dota_techies_land_mine = {ability='techies_land_mines', radius='radius', arm='activation_delay',trigger='proximity_threshold'},
    npc_dota_techies_remote_mine = {ability='techies_remote_mines', radius='radius', arm='activation_time'},
    npc_dota_techies_stasis_trap = {ability='techies_stasis_trap', radius='stun_radius', arm='activation_time'},
    npc_dota_techies_snare_trap = {ability='techies_snare_trap', radius='effect_radius', arm='activation_time'},
    npc_dota_techies_innate_mine = {ability='techies_mutually_assured_destruction', radius='radius'},
}
local effects = {
    {name='modifier_techies_sticky_bomb_slow', ability='techies_sticky_bomb', radius='explosion_radius'},
    {name='modifier_techies_reactive_tazer', ability='techies_reactive_tazer', radius='explosion_radius'},
    {name='modifier_techies_sticky_bomb_countdown', ability='techies_sticky_bomb', radius='explosion_radius'},
    {name='modifier_techies_sticky_bomb_chase', ability='techies_sticky_bomb', radius='explosion_radius',envelope=true},
    {name='modifier_techies_sticky_bomb_throw', ability='techies_sticky_bomb', radius='explosion_radius',envelope=true},
}
local function call(o, method, ...)
    if not o then return end
    local ok, fn = pcall(function() return o[method] end)
    if not ok or type(fn)~='function' then return end
    local success, result = pcall(fn,o,...)
    if success then return result end
end
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge end
local function point(p)
    local ok,x,y,z=pcall(function() return p.x,p.y,p.z end)
    if ok and finite(x) and finite(y) and finite(z) then return {x=x,y=y,z=z} end
end
local function visible(team,o)
    for v in pairs(roster) do
        if call(v,'GetTeamNumber')==team and call(v,'IsNull')~=true and call(v,'IsAlive')~=false
            and call(v,'CanEntityBeSeenByMyTeam',o)==true then return true end
    end
    return false
end
local function ability(o,p)
    -- Modifier ownership is more reliable than a living/visible original planter.
    for _,m in ipairs(call(o,'FindAllModifiers') or {}) do
        local a=call(m,'GetAbility')
        if call(a,'GetAbilityName')==p.ability then return a,m end
    end
    local a=call(o,'FindAbilityByName',p.ability)
    if a then return a end
    for _,method in ipairs({'GetOwnerEntity','GetOwner'}) do
        a=call(call(o,method),'FindAbilityByName',p.ability)
        if a then return a end
    end
end
local function prune(now)
    for o,teams in pairs(signs) do
        for team,s in pairs(teams) do
            if now>=s.lastSeen+MEMORY then teams[team]=nil end
        end
        if not next(teams) then signs[o]=nil end
    end
    for o,entries in pairs(objects) do
        for key,r in pairs(entries) do
            for team,s in pairs(r.snapshots) do
                if now>=s.expires_at then r.snapshots[team]=nil end
            end
            if not next(r.snapshots) then entries[key]=nil end
        end
        if not next(entries) then objects[o]=nil end
    end
end
local function record(o,key,team,p,a,now,impact,expiry)
    local pos=point(call(o,'GetAbsOrigin'))
    local radius=call(a,'GetSpecialValueFor',p.radius)
    if not pos or not finite(radius) or radius<=0 or not finite(impact) or not finite(expiry) or expiry<=now then return end
    local entries=objects[o] or {}; objects[o]=entries
    local r=entries[key]
    if not r then sequence=sequence+1; r={id=sequence,snapshots={},firstSeen={},activation={}}; entries[key]=r end
    r.firstSeen[team]=r.firstSeen[team] or now
    r.activation[team]=r.activation[team] or impact
    local escape
    if p.trigger then
        local threshold=call(a,'GetSpecialValueFor',p.trigger)
        if finite(threshold) and threshold>0 then
            escape=r.activation[team]+math.max(0,threshold-SCAN_INTERVAL)
        else escape=now end
    end
    r.snapshots[team]={id=r.id,caster=o,ability=a,position=pos,radius=radius,shape='circle',
        phase='released',released_at=r.firstSeen[team],impact_at=impact,
        expires_at=expiry,active_from=impact,active_until=expiry,
        escape_deadline=escape,envelope=p.envelope or nil,
        minefield_state=p.state,movement_triggered=p.state=='active' or nil}
end
local function clearTeam(o,team,key)
    for k,r in pairs(objects[o] or {}) do
        if not key or k==key then r.snapshots[team]=nil end
    end
end
-- Native strings establish the modifier names; upstream schema distinguishes the
-- source's Scepter duration from the victim aura's movement accumulator. Do not
-- read the thinker's private m_bTriggered or invent activation from nearby heroes.
local function observeSign(o,team,now)
    clearTeam(o,team,'sign')
    local name=call(o,'GetUnitName')
    if name~=SIGN and name~='npc_dota_thinker' then return end
    local active=call(o,'FindModifierByName',SIGN_ACTIVE)
    local thinker=call(o,'FindModifierByName',SIGN_THINKER)
    if not active and not thinker and not signs[o] then return end
    local entries=signs[o] or {}; signs[o]=entries
    local s=entries[team]
    if not s or (s.thinker~=thinker and (not active or s.active~=active)) then
        s={}; entries[team]=s
    end
    s.thinker=thinker
    s.lastSeen=now
    if active then
        local a=call(active,'GetAbility')
        local caster=call(active,'GetCaster')
        local enemy=call(caster,'GetTeamNumber')
        local remaining=call(active,'GetRemainingTime')
        local duration=call(a,'GetSpecialValueFor','minefield_duration')
        if call(a,'GetAbilityName')~=SIGN_ABILITY or not finite(enemy) or enemy==team
            or not finite(remaining) or remaining<=0 or not finite(duration) or duration<=0 then return end
        -- A new modifier is a new activation. Repeated observations cannot restart
        -- the full duration, even if a native timer is stale or unexpectedly long.
        if s.active~=active then s.active=active; s.deadline=now+math.min(remaining,duration) end
        s.deadline=math.min(s.deadline,now+remaining)
        s.triggered=true
        record(o,'sign',team,signActive,a,now,now,math.min(s.deadline,now+MEMORY))
    elseif thinker and name==SIGN and not s.triggered then
        local a=call(thinker,'GetAbility')
        local caster=call(thinker,'GetCaster')
        local enemy=call(caster,'GetTeamNumber')
        -- Ordinary/cosmetic signs are not hazards. The generic thinker is not
        -- upgrade evidence, and a hidden owner's inventory must never be polled.
        if call(a,'GetAbilityName')==SIGN_ABILITY and finite(enemy) and enemy~=team
            and visible(team,caster) and call(caster,'HasScepter')==true then
            local remaining=call(thinker,'GetRemainingTime')
            if finite(remaining) and remaining>0 then
                record(o,'sign',team,signTrigger,a,now,now,now+math.min(MEMORY,remaining))
            end
        end
    end
end
function M.Observe(units,now)
    if not finite(now) then return end
    roster={}
    local candidates,teams={},{}
    for _,u in ipairs(units or {}) do
        roster[u]=true; candidates[u]=true
        local t=call(u,'GetTeamNumber'); if finite(t) then teams[t]=true end
    end
    -- Revisit known objects every observation, but discover mine entities only 5 Hz.
    for o in pairs(objects) do candidates[o]=true end
    for o in pairs(signs) do candidates[o]=true end
    if now>=nextScan then
        nextScan=now+SCAN_INTERVAL
        for _,class in ipairs({'npc_dota_techies_mines','npc_dota_thinker',SIGN}) do
            for _,o in ipairs(call(Entities,'FindAllByClassname',class) or {}) do candidates[o]=true end
        end
    end
    for o in pairs(candidates) do
        for team in pairs(teams) do
            -- Position, modifiers, life state and owner specials are read only after
            -- actual object visibility. Hidden destruction only ages out old knowledge.
            if visible(team,o) then
                if call(o,'IsNull')==true or call(o,'IsAlive')==false then
                    clearTeam(o,team)
                    if signs[o] then signs[o][team]=nil end
                else
                    observeSign(o,team,now)
                    local sourceTeam=call(o,'GetTeamNumber')
                    local p=mines[call(o,'GetUnitName')]
                    if p then
                        clearTeam(o,team,'mine')
                        if finite(sourceTeam) and sourceTeam~=team then
                            local a,modifier=ability(o,p)
                            local arm=p.arm and call(a,'GetSpecialValueFor',p.arm) or 0
                            local born=call(o,'GetCreationTime')
                            -- An unknown arming time is conservatively a present hazard;
                            -- it never becomes an invented detonation deadline.
                            local active=now
                            if finite(arm) and arm>=0 and arm<=10 and finite(born) and born<=now then active=math.max(now,born+arm) end
                            local remaining=call(modifier,'GetRemainingTime')
                            if p.ability=='techies_mutually_assured_destruction' and finite(remaining) and remaining>0 and remaining<=30 then
                                record(o,'mine',team,p,a,now,now+remaining,now+remaining)
                            else
                                record(o,'mine',team,p,a,now,active,math.max(now+MEMORY,active+MEMORY))
                            end
                        end
                    end
                    for _,effect in ipairs(effects) do
                        local mod=call(o,'FindModifierByName',effect.name)
                        local a=call(mod,'GetAbility')
                        local caster=call(mod,'GetCaster')
                        local enemy=call(caster,'GetTeamNumber')
                        local remaining=call(mod,'GetRemainingTime')
                        clearTeam(o,team,effect.name)
                        if finite(enemy) and enemy~=team and call(a,'GetAbilityName')==effect.ability
                            and finite(remaining) and remaining>0 and remaining<=30 then
                            -- Primary Sticky slow marks the attached bomb's countdown;
                            -- secondary explosion slow is deliberately excluded.
                            local impact=effect.envelope and now or now+remaining
                            local expiry=effect.envelope and now+math.min(MEMORY,remaining) or impact
                            record(o,effect.name,team,effect,a,now,impact,expiry)
                        end
                    end
                end
            end
        end
    end
    prune(now)
end
function M.Threats(viewer,now)
    local result={}
    if not finite(now) then return result end
    prune(now)
    local team=call(viewer,'GetTeamNumber')
    if not finite(team) then return result end
    for _,entries in pairs(objects) do
        for _,r in pairs(entries) do
            local s=r.snapshots[team]
            if s then
                local copy={}; for k,v in pairs(s) do copy[k]=v end
                copy.position=point(s.position); result[#result+1]=copy
            end
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
function M.Reset(unit)
    if unit then objects[unit]=nil; signs[unit]=nil; roster[unit]=nil
    else objects={}; signs={}; roster={}; nextScan=-math.huge end
end
return M
