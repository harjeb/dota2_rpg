-- Shared planar threat geometry; signed distance is negative inside a damaging region.
local G={}
local atan2=math.atan2 or function(y,x) return math.atan(y,x) end
local function distance(a,b) local x,y=a.x-b.x,a.y-b.y;return math.sqrt(x*x+y*y) end
local function segment(t,p)
 local a,b=t.position,t.endpoint or t.position
 local x,y=b.x-a.x,b.y-a.y;local length=x*x+y*y
 local f=length>0 and math.max(0,math.min(1,((p.x-a.x)*x+(p.y-a.y)*y)/length)) or 0
 return {x=a.x+x*f,y=a.y+y*f},f
end
function G.SignedDistance(t,p)
 local radius=t.radius or 0
 if t.shape=='line' or t.shape=='cone' then
  local q,f=segment(t,p)
  if t.shape=='cone' and t.endpoint then
   -- Minimize distance to the swept disks; projection alone underestimates sloping sides.
   local a,b=t.position,t.endpoint
   local length=distance(a,b)
   if length>0 then
    local ux,uy=(b.x-a.x)/length,(b.y-a.y)/length
    local along=(p.x-a.x)*ux+(p.y-a.y)*uy
    local across=math.abs((p.x-a.x)*uy-(p.y-a.y)*ux)
    local slope=((t.end_radius or radius)-radius)/length
    if math.abs(slope)<1 then
     local at=math.max(0,math.min(length,along+slope*across/math.sqrt(1-slope*slope)))
     q={x=a.x+ux*at,y=a.y+uy*at};radius=radius+slope*at
    else
     local da=distance(p,a)-radius
     local db=distance(p,b)-(t.end_radius or radius)
     return math.min(da,db)
    end
   end
  end
  return distance(p,q)-radius
 end
 local d=distance(t.position,p)
 if t.shape=='ring' then return math.max(d-radius,(t.inner_radius or 0)-d) end
 return d-radius
end
function G.Contains(t,p,padding) return G.SignedDistance(t,p)<=(padding or 0) end
function G.Candidates(t,origin,padding)
 local result={};padding=padding or 0
 local function circle(center,r)
  if r<=0 then return end
  local initial=atan2(origin.y-center.y,origin.x-center.x)
  for i=0,15 do
   local a=initial+i*math.pi/8
   result[#result+1]={x=center.x+math.cos(a)*r,y=center.y+math.sin(a)*r,z=origin.z or center.z or 0}
  end
 end
 if t.shape=='line' or t.shape=='cone' then
  local q,f=segment(t,origin)
  circle(q,(t.radius or 0)+((t.end_radius or t.radius or 0)-(t.radius or 0))*f+padding)
  circle(t.position,(t.radius or 0)+padding)
  circle(t.endpoint or t.position,(t.end_radius or t.radius or 0)+padding)
 else
  circle(t.position,(t.radius or 0)+padding)
  if t.shape=='ring' then
   circle(t.position,(t.inner_radius or 0)-padding)
   if (t.inner_radius or 0)>padding then result[#result+1]={x=t.position.x,y=t.position.y,z=origin.z or 0} end
  end
 end
 return result
end
return G
