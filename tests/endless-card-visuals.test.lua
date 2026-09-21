-- Run from repository root with Lua 5.1+.
package.path='game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;'..package.path
local Visuals=require('endless.card_visuals')
local WAVE='particles/units/heroes/hero_razor/razor_plasmafield.vpcf'
local WALL='particles/units/heroes/hero_dark_seer/dark_seer_wall_of_replica.vpcf'
local context,precached={},{}
function PrecacheResource(kind,path,ctx)
    assert(kind=='particle' and ctx==context)
    precached[#precached+1]=path
end
Visuals.Precache(context)
assert(#precached==2 and precached[1]==WAVE and precached[2]==WALL)

-- Offline gameplay tests do not define engine particle/vector globals.
local offline={}
Visuals.SpawnWave(offline,{})
Visuals.SpawnWall(offline,{})
Visuals.Tick(offline,100)
Visuals.Stop(offline)
assert(offline.card_visuals==nil)

function Vector(x,y,z) return {x=x,y=y,z=z} end
PATTACH_WORLDORIGIN=0
local handles,nextHandle={},0
ParticleManager={}
function ParticleManager:CreateParticle(path,attach,owner)
    assert(attach==PATTACH_WORLDORIGIN and owner==nil)
    nextHandle=nextHandle+1
    handles[nextHandle]={path=path,cp={},sets={},destroyed=0,released=0}
    return nextHandle
end
function ParticleManager:SetParticleControl(handle,cp,value)
    local p=assert(handles[handle])
    assert(p.destroyed==0 and p.released==0)
    p.cp[cp]=value
    p.sets[cp]=(p.sets[cp] or 0)+1
end
function ParticleManager:DestroyParticle(handle,immediate)
    local p=assert(handles[handle])
    assert(immediate==true and p.destroyed==0 and p.released==0,'double destroy')
    p.destroyed=p.destroyed+1
end
function ParticleManager:ReleaseParticleIndex(handle)
    local p=assert(handles[handle])
    assert(p.destroyed==1 and p.released==0,'release must follow a single destroy')
    p.released=p.released+1
end
local function vector(actual,x,y,z)
    assert(actual and actual.x==x and actual.y==y and actual.z==z)
end
local function live(handle) assert(handles[handle].destroyed==0 and handles[handle].released==0) end
local function gone(handle) assert(handles[handle].destroyed==1 and handles[handle].released==1) end

local s,other={},{}
local wave=Visuals.SpawnWave(s,{center=Vector(100,200,30),speed=1200,range=2000,started=10})
assert(handles[wave].path==WAVE)
vector(handles[wave].cp[0],100,200,30)
vector(handles[wave].cp[1],1200,2000,1)
local wall=Visuals.SpawnWall(s,{center=Vector(100,200,30),dx=0.6,dy=0.8,length=900,expires=15})
assert(handles[wall].path==WALL)
vector(handles[wall].cp[0],370,560,30)
vector(handles[wall].cp[1],-170,-160,30)
local isolated=Visuals.SpawnWall(other,{center=Vector(0,0,5),dx=1,dy=0,expires=100})
vector(handles[isolated].cp[0],450,0,5)
vector(handles[isolated].cp[1],-450,0,5)
Visuals.Tick(s,10+2000/1200-0.001)
live(wave);live(wall)
vector(handles[wave].cp[1],1200,2000,1)
Visuals.Tick(s,10+2000/1200)
vector(handles[wave].cp[1],1200,2000,-1)
Visuals.Tick(s,12)
assert(handles[wave].sets[1]==2,'reverse exactly once')
Visuals.Tick(s,10+2*2000/1200)
gone(wave);live(wall);live(isolated)
assert(#s.card_visuals==1)
Visuals.Tick(s,15)
gone(wall)
assert(s.card_visuals==nil)
Visuals.Tick(s,100)
Visuals.Stop(s)
Visuals.Stop(s)
live(isolated)

-- Stop cleans every pending handle; fresh combats can reuse the same state.
local a=Visuals.SpawnWave(s,{center=Vector(0,0,0),started=20})
local b=Visuals.SpawnWall(s,{center=Vector(0,0,0),dx=0,dy=1,length=400,expires=50})
vector(handles[a].cp[1],1200,2000,1)
vector(handles[b].cp[0],0,200,0)
Visuals.Stop(s)
Visuals.Stop(s)
Visuals.Tick(s,100)
gone(a);gone(b);live(isolated)
assert(s.card_visuals==nil)
Visuals.Stop(other)
gone(isolated)

-- A late tick retires all expired visuals without changing dead control points.
local c=Visuals.SpawnWave(s,{center=Vector(0,0,0),speed=100,range=300,started=30})
local d=Visuals.SpawnWave(s,{center=Vector(0,0,0),speed=100,range=300,started=30})
Visuals.Tick(s,100)
gone(c);gone(d)
assert(handles[c].sets[1]==1 and s.card_visuals==nil)

-- Present-but-broken engine APIs must surface errors, never silently skip VFX.
local create=ParticleManager.CreateParticle
ParticleManager.CreateParticle=function() error('engine particle failure') end
local ok,err=pcall(Visuals.SpawnWave,{}, {center=Vector(0,0,0),started=0})
assert(not ok and tostring(err):find('engine particle failure',1,true))
ParticleManager.CreateParticle=create
for _,p in pairs(handles) do assert(p.destroyed==1 and p.released==1) end
print('endless card visuals: precache, control points, turnaround, expiry, isolation and Stop passed')
