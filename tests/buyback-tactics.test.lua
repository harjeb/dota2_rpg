local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Engine = require("tactics/tactic_engine")
require("tactics/tactic_bridge")
local calls = {}
-- Spy on native cleanup boundaries while exercising the real engine reset method.
for module, methods in pairs({
    ["tactics/neutral_attack"]={"Release"},
    ["tactics/persistent_movement"]={"Release"},
    ["tactics/native_events"]={"Detach"},
    ["tactics/action_lifecycle"]={"Reset"},
    ["tactics/state_controller"]={"Reset"},
}) do
    for _, method in ipairs(methods) do
        local key = module .. "." .. method
        require(module)[method] = function(...) calls[key] = {...} end
    end
end
local unit = {entindex=function() return 11 end}
local other = {entindex=function() return 12 end}
local state = {unit=unit, chase={rule={}}, movement={}, wait_until=100, posture_order={}}
local otherState = {unit=other, wait_until=200}
local engine = setmetatable({states={[11]=state,[12]=otherState}}, Engine)
engine:ResetUnit(unit)
assert(engine.states[11]==nil and engine.states[12]==otherState, "reset only the returning hero")
assert(calls["tactics/neutral_attack.Release"][1]==unit)
local release=calls["tactics/persistent_movement.Release"]
assert(release[1]==engine and release[2]==unit and release[3]==state and release[5]==false)
for _, key in ipairs({"tactics/native_events.Detach", "tactics/action_lifecycle.Reset", "tactics/state_controller.Reset"}) do
    assert(calls[key][1]==unit, "cleanup omitted: " .. key)
end
engine:ResetUnit(unit) -- Idempotent even before a tactic state has been recreated.
assert(engine.states[12]==otherState)
local bridge = setmetatable({unitObservation={cached=true},tacticEngine=engine}, {__index=TacticBridge})
engine.states[11]=state
bridge:ResetUnit(unit)
assert(bridge.unitObservation==nil and engine.states[11]==nil, "bridge invalidates observation and delegates reset")
print("PASS: ResetUnit clears chase, movement, wait, native events and action state for one hero")

local attempted = {}
function engine:TryRule(_, _, _, rule)
    attempted[#attempted+1]=rule.id
    return rule.id=="attack"
end
function engine:Debug() end
local rules = {
    {id="revive", enabled=true, action={kind="buyback"}},
    {id="spell", enabled=true, action={kind="ability",name="spell"}},
    {id="revive2", enabled=true, action={kind="buyback"}},
    {id="attack", enabled=true, action={kind="attack"}},
}
assert(engine:EvaluateRules(unit, {}, {}, rules, 1, #rules))
assert(#attempted==2 and attempted[1]=="spell" and attempted[2]=="attack", "buyback must neither execute nor starve live rules")
attempted={}
assert(not engine:EvaluateRules(unit, {}, {}, {rules[1],rules[3]},1,2))
assert(#attempted==0, "buyback-only live rules leave fallback available")
print("PASS: live rule evaluation skips duplicate buyback rules and continues to spell/attack/fallback")
