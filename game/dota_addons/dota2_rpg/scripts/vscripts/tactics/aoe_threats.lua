-- Confirmed native releases only. Never discover casts from orders/phases/cursor polling.
local Profiles = require('tactics/aoe_profiles')
local Techies = require('tactics/techies_threats')
local M = {}
local records, viewers, executed, pending = {}, {}, {}, {}
local sequence = 0
local function call(object, method, ...)
    if not object then return nil end
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= 'function' then return nil end
    local success, value = pcall(fn, object, ...)
    if success then return value end
end
local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function point(v)
    local ok,x,y,z=pcall(function() return v.x,v.y,v.z end)
    if ok and finite(x) and finite(y) and finite(z) then return {x=x,y=y,z=z} end
end
local function origin(u) return point(call(u,'GetAbsOrigin')) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function visible(team,u)
    for v in pairs(viewers) do
        if call(v,'GetTeamNumber')==team and call(v,'IsNull')~=true and call(v,'IsAlive')~=false
            and call(v,'CanEntityBeSeenByMyTeam',u)==true then return true end
    end
    return false
end
local function seenBy(u)
    local seen, enemy = {},call(u,'GetTeamNumber')
    if not finite(enemy) then return seen end
    for v in pairs(viewers) do
        local team=call(v,'GetTeamNumber')
        if finite(team) and team~=enemy and visible(team,u) then seen[team]=true end
    end
    return seen
end
local function value(a,spec)
    if type(spec)=='number' then return spec end
    if type(spec)=='table' then
        local a1,b=value(a,spec[1]),value(a,spec[2])
        if not finite(a1) or not finite(b) then return nil end
        if spec.op=='add' then return a1+b elseif spec.op=='sub' then return a1-b elseif spec.op=='mul' then return a1*b
        elseif spec.op=='div' and b>0 then return a1/b end
    elseif spec=='@channel' then return call(a,'GetChannelTime')
    elseif type(spec)=='string' then return call(a,'GetSpecialValueFor',spec) end
end
local function prune(now)
    for id,r in pairs(records) do
        local alive=false
        for team,s in pairs(r.snapshots) do
            if now>=s.expires_at then r.snapshots[team]=nil else alive=true end
        end
        if not alive then records[id]=nil end
    end
    for u,events in pairs(pending) do
        for a,e in pairs(events) do if now>e.deadline then events[a]=nil end end
        if not next(events) then pending[u]=nil end
    end
end
local function emit(unit,ability,now,p,seen)
    local radius,delay,duration=value(ability,p.radius),value(ability,p.delay),value(ability,p.duration)
    if not finite(radius) or radius<=0 or not finite(delay) or delay<0 or not finite(duration) or duration<0 then return end
    local target=p.origin=='target' and call(ability,'GetCursorTarget') or nil
    -- Filter before position reads as well as before storing the team snapshot.
    if target then for team in pairs(seen) do if not visible(team,target) then seen[team]=nil end end end
    if not next(seen) then return end
    local anchor=p.origin=='caster' and unit or target
    local start=anchor and origin(anchor) or nil
    if p.origin=='cursor' then start=point(call(ability,'GetCursorPosition')) end
    if not start then return end
    local endpoint,length
    if p.shape=='line' or p.shape=='cone' then
        local source=origin(unit)
        if not source then return end
        local d=distance(source,start)
        length=p.length=='@cursor' and d or value(ability,p.length)
        if not finite(length) or length<=0 or d<=0 then return end
        local base=p.path_from_cursor and start or source
        endpoint={x=base.x+(start.x-source.x)*length/d,y=base.y+(start.y-source.y)*length/d,z=base.z}
        start=base
    end
    if p.speed then
        local speed=value(ability,p.speed)
        if not finite(speed) or speed<=0 then return end
        duration=length/speed
    end
    if p.travel_speed then
        local source,speed=origin(unit),value(ability,p.travel_speed)
        if not source or not finite(speed) or speed<=0 then return end
        delay=delay+distance(source,start)/speed
    end
    local inner=p.inner_radius and value(ability,p.inner_radius)
    local ending=p.end_radius and value(ability,p.end_radius)
    if p.shape=='ring' and (not finite(inner) or inner<0 or inner>=radius) then return end
    if p.shape=='cone' and (not finite(ending) or ending<=0) then return end
    if delay+duration<=0 or not finite(now+delay+duration) then return end
    local follow=p.follow=='caster' and unit or (p.follow=='target' and target or nil)
    local count,step,increase=0,0,0
    if p.repeats and call(unit,'HasShard')==true then
        count,step,increase=value(ability,'shard_max_count'),value(ability,'shard_secondary_delay'),value(ability,'shard_radius_increase')
        if not finite(count) or count<0 or count>16 or not finite(step) or step<=0 or not finite(increase) or increase<0 then
            count,step,increase=0,0,0 -- base release remains valid if upgrade specials unavailable
        end
    end
    for i=0,math.floor(count) do
        sequence=sequence+1
        local impact,expiry=now+delay+i*step,now+delay+i*step+duration
        local r={id=sequence,caster=unit,ability=ability,profile=p,follow=follow,snapshots={}}
        for team in pairs(seen) do
            r.snapshots[team]={id=sequence,caster=unit,ability=ability,position=point(start),endpoint=point(endpoint),
                radius=radius+i*increase,inner_radius=inner,end_radius=ending,shape=p.shape,
                phase='released',released_at=now,impact_at=impact,expires_at=expiry,
                active_from=impact,active_until=expiry,envelope=p.envelope or nil}
        end
        records[sequence]=r
    end
end
function M.OnExecuted(unit,ability,now)
    if not unit or not ability or not finite(now) then return end
    local name=call(ability,'GetAbilityName')
    if name=='techies_reactive_tazer_stop' then
        -- The visible early explosion consumes the scheduled charge immediately.
        for _,r in pairs(records) do
            if r.caster==unit and call(r.ability,'GetAbilityName')=='techies_reactive_tazer' then
                for team in pairs(r.snapshots) do if visible(team,unit) then r.snapshots[team]=nil end end
            end
        end
        prune(now)
        return
    end
    local p=Profiles[name]
    if not p then return end
    local events=executed[unit] or {}; executed[unit]=events
    if events[ability] and now<=events[ability] then return end
    events[ability]=now
    prune(now)
    local seen=seenBy(unit)
    if p.channel_release then
        -- Remember visibility only, never expose or sample a charging cursor.
        local queue=pending[unit] or {}; pending[unit]=queue
        local channel=call(ability,'GetChannelTime')
        queue[ability]={seen=seen,deadline=now+(finite(channel) and math.max(channel,0) or 1)+1}
        return
    end
    if next(seen) then emit(unit,ability,now,p,seen) end
end
function M.OnChannelEnd(unit,ability,now,interrupted)
    if not finite(now) then return end
    prune(now)
    local queue=pending[unit]
    local event=queue and queue[ability]
    if event then
        queue[ability]=nil
        for team in pairs(event.seen) do if not visible(team,unit) then event.seen[team]=nil end end
        local p=Profiles[call(ability,'GetAbilityName')]
        if p and next(event.seen) and (not p.require_completion or interrupted==false) then
            emit(unit,ability,now,p,event.seen)
        end
    end
    for _,r in pairs(records) do
        if r.caster==unit and r.ability==ability and r.profile.channel then
            for team in pairs(r.snapshots) do if visible(team,unit) then r.snapshots[team]=nil end end
        end
    end
    prune(now)
end
function M.Observe(units,now)
    if not finite(now) then return end
    prune(now)
    viewers={}; for _,u in pairs(units or {}) do viewers[u]=true end
    Techies.Observe(units,now)
    for _,r in pairs(records) do
        for team,s in pairs(r.snapshots) do
            local anchor=r.follow
            if anchor and visible(team,anchor) then
                if call(anchor,'IsAlive')==false or call(anchor,'IsNull')==true then r.snapshots[team]=nil
                else s.position=origin(anchor) or s.position end
            end
            if r.profile.leash and visible(team,r.caster) then
                local pos=origin(r.caster)
                if call(r.caster,'IsAlive')==false or (pos and distance(pos,s.position)>s.radius) then r.snapshots[team]=nil end
            end
            if r.profile.channel and visible(team,r.caster) then
                local stopped=call(r.caster,'IsAlive')==false
                -- Allow the native execution event to precede the channel flag.
                -- Reconcile only already-known channels, never discover casts here.
                if now>s.released_at+0.1 then
                    local channeling=call(r.caster,'IsChanneling')
                    local active=call(r.caster,'GetCurrentActiveAbility')
                    stopped=stopped or channeling==false or (channeling==true and active~=nil and active~=r.ability)
                end
                if stopped then r.snapshots[team]=nil end
            end
        end
    end
    for u in pairs(executed) do if call(u,'IsNull')==true then executed[u]=nil end end
end
function M.Threats(caster,now)
    if not finite(now) then return {} end
    prune(now)
    local team,result=call(caster,'GetTeamNumber'),{}
    if not finite(team) then return result end
    for _,r in pairs(records) do
        local s=r.snapshots[team]
        if s and now>=s.released_at then
            local copy={}; for k,v in pairs(s) do copy[k]=v end
            copy.position=point(s.position); copy.endpoint=point(s.endpoint)
            result[#result+1]=copy
        end
    end
    for _,threat in ipairs(Techies.Threats(caster,now)) do result[#result+1]=threat end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
function M.Reset(unit)
    Techies.Reset(unit)
    if unit then
        for id,r in pairs(records) do if r.caster==unit then records[id]=nil end end
        viewers[unit],executed[unit],pending[unit]=nil,nil,nil
    else records,viewers,executed,pending={},{},{},{} end
end
return M
