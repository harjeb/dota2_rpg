-- Spatial card mechanics. State belongs to one fight; no global timers survive Stop.
local M={}
local Visuals=require('endless.card_visuals')
local function pos(u) return u and u.GetAbsOrigin and u:GetAbsOrigin() end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function random(n) return RandomInt and RandomInt(1,n) or math.random(n) end
local function point(x,y,z) return Vector(x,y,z or 0) end
local function enemies(ctx,game,s)
    local result={};ctx.each(game,s,false,function(u) result[#result+1]=u end);return result
end
function M.Fire(ctx,game,s,c)
    if c.id=='E-c4' then ctx.each(game,s,true,function(u) ctx.heal(u,({150,250,400})[c.load]) end)
    elseif c.id=='E-c7' then
        local center,ratio=nil,math.huge
        ctx.each(game,s,true,function(u) if ctx.body(game,s,u) then
            local r=u:GetHealth()/math.max(1,u:GetMaxHealth());if r<ratio then ratio=r;center=pos(u) end
        end end)
        if center then ctx.each(game,s,false,function(u) local p=pos(u)
            if p and distance(p,center)<=500 then ctx.damage(game,s,u,({120,200,320})[c.load],DAMAGE_TYPE_MAGICAL,'card_rune') end
        end) end
    end
end
function M.Attack(ctx,game,s,attacker,victim,amount)
    local c=s.by_id['E-c4']
    if not c or not c.active_until or s.time>=c.active_until or amount<=0 then return end
    s.burns=s.burns or {}
    -- One recipient burn: refresh three ticks, retain the stronger attack's tick damage.
    local old=s.burns[victim]
    local ongoing=old and old.expires>=s.time
    s.burns[victim]={amount=math.max(amount*.35/3,ongoing and old.amount or 0),
        next=ongoing and old.next or s.time+1,expires=s.time+3,attacker=attacker}
end
local pools={
    {'npc_dota_neutral_centaur_khan','npc_dota_neutral_satyr_hellcaller','npc_dota_neutral_dark_troll_warlord','npc_dota_neutral_polar_furbolg_ursa_warrior'},
    {'npc_dota_neutral_centaur_khan','npc_dota_neutral_satyr_hellcaller','npc_dota_neutral_dark_troll_warlord','npc_dota_neutral_polar_furbolg_ursa_warrior'},
    {'npc_dota_neutral_black_dragon','npc_dota_neutral_granite_golem','npc_dota_neutral_big_thunder_lizard'},
}
local function randomPosition(ctx,game,s)
    local xmin,xmax,ymin,ymax=s.center.x,s.center.x,s.center.y,s.center.y
    for _,u in ipairs(ctx.units(game,s)) do if ctx.alive(u) and not u.endlessCardSummon then local p=pos(u);if p then
        xmin=math.min(xmin,p.x);xmax=math.max(xmax,p.x);ymin=math.min(ymin,p.y);ymax=math.max(ymax,p.y)
    end end end
    local function sample(a,b) return a+(b-a)*(random(10001)-1)/10000 end
    return point(sample(xmin-200,xmax+200),sample(ymin-200,ymax+200),s.center.z)
end
function M.Periodic(ctx,game,s,c)
    local id=c.id
    if id=='E-g7' then
        local centers={}
        ctx.each(game,s,true,function(u)
            -- The shield axis is a build tag, not an activation condition.
            if pos(u) then centers[#centers+1]=pos(u) end
        end)
        ctx.each(game,s,false,function(u) local p=pos(u);if p then for _,center in ipairs(centers) do
            if distance(p,center)<=400 then ctx.damage(game,s,u,({40,70,110})[c.load],DAMAGE_TYPE_MAGICAL,'card_fire_shield');break end
        end end end)
    elseif id=='D-f1' then
        s.waves=s.waves or {}
        for i=1,3 do
            local positions={}
            ctx.each(game,s,false,function(u) local p=pos(u);if p then positions[u]=point(p.x,p.y,p.z) end end)
            local wave={center=randomPosition(ctx,game,s),started=s.time,previous=0,positions=positions,hits={{},{}},scale=s.field_scale}
            s.waves[#s.waves+1]=wave;Visuals.SpawnWave(s,wave)
        end
    elseif id=='D-f3' then
        local targets=enemies(ctx,game,s);if #targets==0 then return end
        local target=targets[random(#targets)];local p=pos(target);if not p then return end
        local angle=(random(10001)-1)/10000*math.pi*2
        s.walls=s.walls or {};s.walls[#s.walls+1]={center=point(p.x,p.y,p.z),dx=math.cos(angle),dy=math.sin(angle),
            expires=s.time+3*s.field_scale,hits={},previous={},load=c.load,scale=s.field_scale}
        Visuals.SpawnWall(s,s.walls[#s.walls])
    elseif id=='W-f2' and CreateUnitByName then
        local count=0;for u,entry in pairs(s.spawned) do if entry.kind=='den' and ctx.alive(u) and entry.expires>s.time then count=count+1 end end
        if count>=8 then return end
        local pool=pools[c.load];local p=randomPosition(ctx,game,s)
        local u=CreateUnitByName(pool[random(#pool)],p,true,nil,nil,s.team)
        if ctx.valid(u) then
            u.endlessCardSummon=true
            if u.SetDeathXP then u:SetDeathXP(0) end
            if u.SetMinimumGoldBounty then u:SetMinimumGoldBounty(0);u:SetMaximumGoldBounty(0) end
            if FindClearSpaceForUnit then FindClearSpaceForUnit(u,p,true) end
            s.spawned[u]={kind='den',expires=s.time+15*s.field_scale}
        end
    end
end
local function crossedWall(w,p,old)
    local function localpos(v) local x,y=v.x-w.center.x,v.y-w.center.y;return x*w.dx+y*w.dy,-x*w.dy+y*w.dx end
    local x,y=localpos(p)
    if math.abs(x)<=450 and math.abs(y)<=50 then return true end
    if old then
        local ox,oy=localpos(old)
        -- Intersect movement segment with the finite wall rectangle (slab clipping).
        local lo,hi=0,1
        for _,axis in ipairs({{ox,x-ox,450},{oy,y-oy,50}}) do
            local o,d,r=axis[1],axis[2],axis[3]
            if math.abs(d)<.00001 then if math.abs(o)>r then return false end
            else local a,b=(-r-o)/d,(r-o)/d;if a>b then a,b=b,a end;lo=math.max(lo,a);hi=math.min(hi,b);if lo>hi then return false end end
        end
        return true
    end
    return false
end
-- Solve the unit movement segment against each linear half of the moving ring.
-- This also catches a unit crossing both sides between ticks, and a tick spanning the apex.
local function waveCrossing(w,old,p,progress,pass)
    local lo=math.max(w.previous,pass==1 and 0 or 2000)
    local hi=math.min(progress,pass==1 and 2000 or 4000)
    if hi<lo then return nil end
    local span=progress-w.previous
    local a=span>0 and (lo-w.previous)/span or 0
    local b=span>0 and (hi-w.previous)/span or 1
    local x=old.x+(p.x-old.x)*a-w.center.x
    local y=old.y+(p.y-old.y)*a-w.center.y
    local dx,dy=(p.x-old.x)*(b-a),(p.y-old.y)*(b-a)
    local radius=pass==1 and lo or 4000-lo
    local dr=(hi-lo)*(pass==1 and 1 or -1)
    local A=dx*dx+dy*dy-dr*dr
    local B=2*(x*dx+y*dy-radius*dr)
    local C=x*x+y*y-radius*radius
    local roots={}
    if math.abs(C)<.00001 then roots[1]=0
    elseif math.abs(A)<.00001 then
        if math.abs(B)>.00001 then roots[1]=-C/B end
    else
        local discriminant=B*B-4*A*C
        if discriminant>=0 then
            local r=math.sqrt(discriminant);roots={(-B-r)/(2*A),(-B+r)/(2*A)};table.sort(roots)
        end
    end
    for _,t in ipairs(roots) do
        if t>=-.00001 and t<=1.00001 then return math.max(0,math.min(2000,radius+dr*t)) end
    end
end
function M.Tick(ctx,game,s)
    Visuals.Tick(s,s.time)
    for u,burn in pairs(s.burns or {}) do
        if not ctx.alive(u) then s.burns[u]=nil
        elseif s.time>=burn.next then
            -- Honor the final due tick with ordinary frame jitter, never replay
            -- an old expired burn after a pause or emit several ticks at once.
            if burn.next<=burn.expires and s.time-burn.next<1 then
                ctx.damage(game,s,u,burn.amount,DAMAGE_TYPE_MAGICAL,'card_burn')
            end
            burn.next=burn.next+math.floor(s.time-burn.next)+1
            if burn.next>burn.expires then s.burns[u]=nil end
        elseif s.time>burn.expires then s.burns[u]=nil end
    end
    local waves={}
    for _,w in ipairs(s.waves or {}) do
        local elapsed=math.max(0,s.time-w.started);local progress=math.min(4000,elapsed*1200)
        ctx.each(game,s,false,function(u) local p=pos(u);if p then
            for pass=1,2 do
                local d=not w.hits[pass][u] and waveCrossing(w,w.positions[u] or p,p,progress,pass)
                if d then
                    w.hits[pass][u]=true
                    ctx.damage(game,s,u,(80+105*d/2000)*w.scale,DAMAGE_TYPE_MAGICAL,'card_storm')
                    ctx.timed(s,u,'D-f1',{move_speed=-40*w.scale},1.5*(1-ctx.call(u,'GetStatusResistance',0)))
                end
            end
            w.positions[u]=point(p.x,p.y,p.z)
        end end)
        w.previous=progress;if progress<4000 then waves[#waves+1]=w end
    end
    s.waves=waves
    local walls={}
    for _,w in ipairs(s.walls or {}) do if s.time<w.expires then
        ctx.each(game,s,false,function(u) local p=pos(u);if p then
            if crossedWall(w,p,w.previous[u]) then
                ctx.timed(s,u,'D-f3',{move_speed=-({30,50,80})[w.load]*w.scale},1*(1-ctx.call(u,'GetStatusResistance',0)))
                local illusionCount=0
                for unit,entry in pairs(s.spawned) do
                    if entry.kind=='wall_illusion' and ctx.alive(unit) and entry.expires>s.time then illusionCount=illusionCount+1 end
                end
                if illusionCount<24 and not w.hits[u] and ctx.call(u,'IsRealHero',false) and not ctx.call(u,'IsIllusion',false) and CreateIllusions then
                    w.hits[u]=true
                    local owner=ctx.source(game,s)
                    for _,illusion in pairs(CreateIllusions(owner,u,{outgoing_damage=({50,80,100})[w.load]*w.scale-100,
                        incoming_damage=100,duration=8},1,0,false,false) or {}) do
                        if illusion.SetTeam then illusion:SetTeam(s.team) end
                        illusion.endlessCardSummon=true
                        if FindClearSpaceForUnit then FindClearSpaceForUnit(illusion,p,true) end
                        s.spawned[illusion]={kind='wall_illusion',expires=s.time+8}
                    end
                end
            end
            w.previous[u]=point(p.x,p.y,p.z)
        end end)
        walls[#walls+1]=w
    end end
    s.walls=walls
end
function M.Stop(s) Visuals.Stop(s) end
return M
