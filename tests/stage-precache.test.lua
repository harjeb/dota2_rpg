local root = arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = root .. "/?.lua;" .. package.path
local Cache = require("battle/stage_precache")
local function level(unit, items) return {enemies={["1"]={unit=unit, items=items}}} end
local levels = {
    ch01=level("npc_dota_first", {["1"]="item_first"}),
    ch02=level("npc_dota_next", {"item_next"}),
    ch03=level("npc_dota_next", {"item_next"}),
    ch04=level("npc_dota_future", {"item_future"}),
    ch05=level("npc_dota_foreground"),
    empty={enemies={}}, bad=level("bad"), baditem=level("npc_dota_valid", {false})
}
-- Explicitly omit invalid keys from startup fixture: lexical order is authoritative.
local stages = {}; for id, value in pairs(levels) do if id:match("^ch") then stages[id]=value end end
local p = Cache.Plan({enemies={
    ["1"]={unit="npc_dota_z",items={"item_z","item_a","item_z","garbage"}},
    ["2"]={unit="npc_dota_a"}, ["3"]={unit="npc_dota_z"}, ["4"]="bad"}})
assert(table.concat(p.units,",")=="npc_dota_a,npc_dota_z")
assert(table.concat(p.items,",")=="item_a,item_z")
assert(#Cache.Plan(nil).units==0)
local synced, context = {}, {}
PrecacheUnitByNameSync=function(name, ctx) assert(ctx==context); assert(not synced[name]); synced[name]=true end
PrecacheItemByNameSync=PrecacheUnitByNameSync
local startup = Cache.Startup(context, stages)
assert(startup.levelId=="ch01" and startup.ready.npc_dota_first and startup.ready.item_first)
assert(synced.npc_dota_hero_wisp and synced.item_aegis and synced.item_cheese)
assert(synced.item_rpg_scroll_low and synced.item_rpg_scroll_high)
assert(not synced.npc_dota_future and not synced.item_future and not synced.npc_dota_next)
local total=0; for _ in pairs(synced) do total=total+1 end; assert(total==7)
PrecacheUnitByNameSync=function() error("runtime must never sync") end
PrecacheItemByNameSync=PrecacheUnitByNameSync
local function fixture(mode)
    local f={time=0, queue={}, loads={}, logs={}}
    function f.schedule(callback, delay)
        assert(delay>0,"scheduler must yield")
        f.queue[#f.queue+1]={at=f.time+delay, callback=callback, order=#f.queue+1}
    end
    function f.tick()
        assert(#f.queue>0,"expected scheduled work")
        table.sort(f.queue,function(a,b) return a.at<b.at or a.at==b.at and a.order<b.order end)
        local event=table.remove(f.queue,1); f.time=event.at; event.callback()
    end
    function f.drain()
        local count=0
        while #f.queue>0 do count=count+1; assert(count<200,"busy loop"); f.tick() end
    end
    local function load(name, cb)
        f.loads[#f.loads+1]={name=name, cb=cb, at=f.time}
        if mode then return mode(name,cb,f) end
    end
    f.options={schedule=f.schedule,now=function() return f.time end,log=function(m) f.logs[#f.logs+1]=m end,
        load_unit=load,load_item=load,timeout=2}
    f.cache=Cache.new(stages,f.options)
    return f
end
local f=fixture()
assert(f.cache:IsReady("ch01") and not f.cache:IsReady("ch02"))
local done=0
f.cache:Request("ch01",function(ok) assert(ok); done=done+1 end)
assert(done==1 and #f.loads==0)
f.cache:Prefetch("ch04"); f.tick()
assert(#f.loads==1 and f.loads[1].name=="npc_dota_future")
f.cache:Request("ch02",function(ok) assert(ok); done=done+1 end)
f.cache:Request("ch03",function(ok) assert(ok); done=done+1 end)
f.loads[1].cb(); f.loads[1].cb()
assert(#f.loads==1,"callback cannot start next native load inline")
f.tick(); assert(f.loads[2].name=="npc_dota_next")
f.loads[2].cb(); f.tick(); assert(f.loads[3].name=="item_next")
f.loads[3].cb(); assert(done==3 and f.cache:IsReady("ch02") and f.cache:IsReady("ch03"))
f.tick(); assert(f.loads[4].name=="item_future")
f.loads[4].cb(); f.drain()
assert(f.cache:IsReady("ch04") and not f.cache:IsReady("ch05") and #f.loads==4)
for i=2,#f.loads do assert(f.loads[i].at-f.loads[i-1].at>=0.099) end
for i=1,10 do f.cache:Request("ch03",function(ok) assert(ok); done=done+1 end) end
assert(done==13 and #f.loads==4)
-- Native inline completion, duplicate completion, observer throw, and reentrancy.
f=fixture(function(_,cb) cb(); cb() end)
local observed=0
f.cache:Request("ch02",function() error("consumer exception") end)
f.cache:Request("ch02",function(ok) assert(ok); observed=observed+1 end)
f.cache:Request("ch03",function(ok)
    assert(ok); observed=observed+1
    f.cache:Request("ch05",function(ok2) assert(ok2); observed=observed+1 end)
end)
f.drain(); assert(observed==3 and #f.loads==3)
assert(f.loads[2].at>f.loads[1].at and f.loads[3].at>f.loads[2].at)
local observerLog=false; for _,m in ipairs(f.logs) do if m=="stage observer failure" then observerLog=true end end
assert(observerLog)
-- Each failure can be retried explicitly; stale callbacks cannot complete a retry.
for _, failure in ipairs({"missing", "throw", "false", "timeout", "callback", "inline-false", "inline-throw"}) do
    f=fixture(function(_,cb)
        if failure=="throw" then error("native exploded") end
        if failure=="false" then return false end
        if failure=="callback" then cb(false) end
        if failure=="inline-false" then cb(); return false end
        if failure=="inline-throw" then cb(); error("after inline") end
    end)
    if failure=="missing" then f.options.load_unit=nil end
    local results={}
    f.cache:Request("ch02",function(ok, reason) results[#results+1]={ok=ok,reason=reason} end)
    f.drain()
    assert(#results==1 and results[1].ok==false and results[1].reason and not f.cache:IsReady("ch02"),failure)
    if failure=="missing" then assert(#f.loads==0 and results[1].reason=="missing API") end
    local old=f.loads[1] and f.loads[1].cb
    local before=#f.loads
    f.cache:Prefetch("ch02"); f.drain(); assert(#f.loads==before,"background failures must not retry")
    local retryCB
    f.options.load_unit=function(_,cb) retryCB=cb end
    f.options.load_item=function(_,cb) cb() end
    f.cache:Request("ch02",function(ok) results[#results+1]={ok=ok} end)
    f.tick(); assert(retryCB)
    if old then old(); old() end
    assert(#results==1 and not f.cache:IsReady("ch02"),"late callback must not complete retry")
    retryCB(); retryCB(); f.drain()
    assert(#results==2 and results[2].ok and f.cache:IsReady("ch02"),failure .. " retry")
end
-- Item API absence must fail closed too.
f=fixture(function(_,cb) cb() end); f.options.load_item=nil
local failed=0
f.cache:Request("ch02",function(ok,reason) assert(not ok and reason=="missing API"); failed=failed+1 end)
f.drain(); assert(failed==1 and not f.cache:IsReady("ch02"))
-- Malformed or empty stages never appear ready, including a malformed seeded first stage.
local invalid=Cache.new(levels,f.options)
for _,id in ipairs({"missing","empty","bad","baditem"}) do
    assert(not invalid:IsReady(id)); invalid:Request(id,function(ok,reason) assert(not ok and reason); failed=failed+1 end)
end
invalid:Request(nil,function(ok) assert(not ok); failed=failed+1 end)
assert(failed==6)
-- A failed resource shared by observers can be retried from an observer safely.
f=fixture(function(_,cb) cb(false) end)
local outcomes={}
f.cache:Request("ch02",function(ok)
    outcomes[#outcomes+1]=ok
    f.options.load_unit=function(_,cb) cb() end
    f.options.load_item=f.options.load_unit
    f.cache:Request("ch03",function(retried) outcomes[#outcomes+1]=retried end)
end)
f.cache:Request("ch03",function(ok) outcomes[#outcomes+1]=ok end)
f.drain(); assert(#outcomes==3 and outcomes[1]==false and outcomes[2]==false and outcomes[3]==true)
-- A later stage reuses a startup unit while loading only its new item.
f=fixture(function(_,cb) cb() end)
local shared=Cache.new({a=level("npc_dota_first"),b=level("npc_dota_first",{"item_new"})}, f.options)
local sharedDone=0
shared:Request("b",function(ok) assert(ok); sharedDone=sharedDone+1 end)
f.drain(); assert(sharedDone==1 and #f.loads==1 and f.loads[1].name=="item_new")
-- Rapid level selection prioritizes the most recently requested foreground stage.
f=fixture(function(_,cb) cb() end)
f.cache:Request("ch02",function(ok) assert(ok) end)
f.cache:Request("ch05",function(ok) assert(ok) end)
f.tick(); assert(f.loads[1].name=="npc_dota_foreground")
f.drain(); assert(f.cache:IsReady("ch02") and f.cache:IsReady("ch05"))
print("stage-precache tests passed")
