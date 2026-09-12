local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Pairing = require("battle.server_pairing")
local Json = require("lib.json")
local Config = require("data.leaderboard_config")
local Results = require("battle.run_results")
local steam, workshop = "76561198046228394", "3799645167"
local key = "Valve_only-secret_123456789"
local requests, events, timers, reads, cfgReads, account, player
local function setup()
    requests, events, timers, reads, cfgReads = {}, {}, {}, 0, 0
    account, player = 85962666, {connection = 1}
    Config.workshop_id, Config.pairing_owner_steam_id = workshop, steam
    Config.endpoint = "https://example.invalid/"
    IsDedicatedServer = function() return true end
    IsInToolsMode = function() return false end
    GetDedicatedServerKeyV3 = function(salt) assert(salt == Config.key_salt); reads = reads + 1; return key end
    LoadKeyValues = function() cfgReads = cfgReads + 1; error("must not read host config") end
    GameRules = {IsCheatMode = function() return false end, GetGameModeEntity = function() return {
        SetContextThink = function(_, name, fn, delay) timers[#timers + 1] = {name=name, fn=fn, delay=delay} end,
    } end}
    PlayerResource = {GetSteamAccountID = function(_, id) assert(id == 0); return account end,
        GetPlayer = function(_, id) assert(id == 0); return player end}
    CustomGameEventManager = {Send_ServerToPlayer = function(_, target, name, data)
        assert(target == player and name == "rpg_server_pairing")
        assert(not Json.encode(data):find(key, 1, true))
        local count = 0; for _ in pairs(data) do count = count + 1 end
        assert(count == 3 and data.status == "awaiting_confirmation")
        events[#events + 1] = {target=target, data=data}
    end}
    CreateHTTPRequestScriptVM = function(method, url)
        local r = {method=method, url=url}; requests[#requests + 1] = r
        function r:SetHTTPRequestHeaderValue(name, value) self[name] = value end
        function r:SetHTTPRequestAbsoluteTimeoutMS(value) self.timeout = value end
        function r:SetHTTPRequestRawPostBody(content, body) self.content, self.body = content, body end
        function r:Send(callback) self.callback = callback end
        return r
    end
    return {playerId=0}
end
local function check(g) Pairing.Check(g, 0, steam) end
local function response(changes)
    local data = {success=true, code="0123456789abcdef01234567", workshop_id=workshop, status="awaiting_confirmation"}
    for k,v in pairs(changes or {}) do data[k]=v end
    return {StatusCode=200, Body=Json.encode(data)}
end
assert(Results.SteamId(85962666) == steam)
local skips = {
    function() IsDedicatedServer=function() return false end end,
    function() IsDedicatedServer=nil end,
    function() IsDedicatedServer=function() error("unavailable") end end,
    function() IsDedicatedServer=function() return 1 end end,
    function() IsInToolsMode=function() return true end end,
    function() IsInToolsMode=nil end,
    function() GameRules.IsCheatMode=function() return true end end,
    function() GameRules.IsCheatMode=nil end,
    function() GameRules=nil end,
    function() account=1 end,
    function() PlayerResource.GetSteamAccountID=nil end,
    function() Config.workshop_id=workshop .. "x" end,
    function() Config.workshop_id=3799645167 end,
    function() Config.endpoint="http://example.invalid" end,
    function() Config.endpoint="https://" end,
    function() GetDedicatedServerKeyV3=nil end,
    function() GetDedicatedServerKeyV3=function() error("unavailable") end end,
    function() CreateHTTPRequestScriptVM=nil end,
    function() GameRules.GetGameModeEntity=nil end,
}
for _, change in ipairs(skips) do
    local g=setup(); change(); check(g)
    assert(#requests == 0 and #events == 0 and cfgReads == 0)
end
for _, invalid in ipairs({"short", string.rep("a",257), string.rep("0",16), "invalid key abcdefgh", "abcdefghijklmnop\n"}) do
    local g=setup(); GetDedicatedServerKeyV3=function() return invalid end; check(g)
    assert(#requests==0 and cfgReads==0)
end
local g=setup()
Pairing.Check(g,1,steam); Pairing.Check(g,0,"76561197960265729")
assert(#requests==0 and reads==0)
check(g); check(g)
assert(#requests==1 and reads==1 and cfgReads==0)
local r=requests[1]
assert(r.method=="POST" and r.url=="https://example.invalid/api/v1/server-pairing")
assert(r.Authorization=="Bearer " .. key and r.timeout==15000 and r.content=="application/json")
local body=Json.decode(r.body)
assert(body.steam_id==steam and body.workshop_id==workshop)
local fields=0; for _ in pairs(body) do fields=fields+1 end; assert(fields==2)
r.callback(response({secret=key})); r.callback(response())
assert(#events==1 and g.leaderboardPairing.status=="success")
local cached=g.leaderboardPairing
Results.Reset(g); assert(g.leaderboardPairing==cached)
player={connection=2}; check(g)
assert(#events==2 and events[2].target==player and #requests==1)
Pairing.Check(g,1,steam); Pairing.Check(g,0,"wrong"); account=1; check(g)
assert(#events==2)

g=setup(); check(g); requests[1].callback({StatusCode=404}); check(g)
assert(g.leaderboardPairing.status=="disabled" and #requests==1 and #timers==0 and #events==0)
for _, status in ipairs({0,408,429,500,503}) do
    g=setup(); check(g)
    requests[1].callback({StatusCode=status}); requests[1].callback({StatusCode=status})
    check(g); assert(#requests==1 and #timers==1 and timers[1].delay==2)
    timers[1].fn(); assert(#requests==2 and requests[2].body==requests[1].body)
    requests[2].callback({StatusCode=status})
    assert(#timers==2 and timers[2].delay==4 and timers[1].name~=timers[2].name)
    timers[2].fn(); assert(requests[3].body==requests[1].body)
    requests[3].callback({StatusCode=status}); check(g)
    assert(#requests==3 and #timers==2 and #events==0 and g.leaderboardPairing.status=="error")
end
for _, change in ipairs({{success=false},{success=1},{code="ABCDEF0123456789abcdef01"},
    {code=string.rep("a",23)},{code=string.rep("a",25)},{code=string.rep("g",24)},
    {workshop_id="3799645168"},{workshop_id=3799645167},{status="confirmed"}}) do
    g=setup(); check(g); requests[1].callback(response(change))
    assert(#events==0 and #timers==1)
    timers[1].fn(); requests[2].callback(response()); assert(#events==1)
end
g=setup(); GetDedicatedServerKeyV3=function() return string.rep("a",24) end
check(g); requests[1].callback(response({code=string.rep("a",24)}))
assert(#events==0 and #timers==1) -- Even a valid-looking reflected bearer stays private.
for _, malformed in ipairs({"not json", "null", "[]", "{}"}) do
    g=setup(); check(g); requests[1].callback({StatusCode=200,Body=malformed})
    assert(#events==0 and #timers==1)
end
for _, status in ipairs({201,301,400,401,403,422}) do
    g=setup(); check(g); requests[1].callback({StatusCode=status}); check(g)
    assert(#events==0 and #timers==0 and #requests==1)
end
for _, stale in ipairs({function(g) g.playerId=1 end, function() account=1 end,
    function() IsInToolsMode=function() return true end end}) do
    g=setup(); check(g); stale(g); requests[1].callback(response()); assert(#events==0)
    g=setup(); check(g); requests[1].callback({StatusCode=429}); stale(g); timers[1].fn()
    assert(#requests==1 and #events==0)
end
g=setup(); check(g); player=nil; requests[1].callback(response()); assert(#events==0)
player={connection=3}; check(g); assert(#events==1 and #requests==1)
g=setup(); CreateHTTPRequestScriptVM=function() error("transport unavailable") end; check(g)
assert(#timers==1); timers[1].fn(); timers[2].fn(); assert(g.leaderboardPairing.attempts==3)
g=setup(); check(g); requests[1].callback({StatusCode=429})
local firstName=timers[1].name
local another={playerId=0}; check(another); requests[2].callback({StatusCode=429})
assert(firstName~=timers[2].name)
print("PASS server pairing: owner gates, direct V3, pending/cache, response validation, retries, 404, stale owner and secret isolation")
