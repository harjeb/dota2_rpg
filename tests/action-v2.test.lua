local root = TEST_REPO_ROOT or "."
package.path = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local Adapter = require("tactics/action_adapter")
local Catalog = require("tactics/ability_catalog")
bit = { band = function(a,b)
    local out, p = 0, 1
    while a > 0 or b > 0 do
        if a % 2 == 1 and b % 2 == 1 then out = out + p end
        a,b,p = math.floor(a/2), math.floor(b/2), p*2
    end
    return out
end }
DOTA_ABILITY_BEHAVIOR_UNIT_TARGET = 8
DOTA_ABILITY_BEHAVIOR_POINT = 16
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
DOTA_ABILITY_BEHAVIOR_TOGGLE = 512
DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING = 1024
DOTA_UNIT_ORDER_CAST_TOGGLE = 9
DOTA_UNIT_ORDER_CAST_TARGET = 6
ABILITY_TYPE_ULTIMATE = 1
local spells = {}
local function ability(name, behavior, passive, hidden)
    local a = { name=name, behavior=behavior, passive=passive, hidden=hidden, toggle=false }
    function a:IsNull() return false end
    function a:GetAbilityName() return self.name end
    function a:GetBehaviorInt() return self.behavior end
    function a:IsPassive() return self.passive or false end
    function a:IsHidden() return self.hidden or false end
    function a:GetLevel() return 1 end
    function a:GetAbilityType() return 1 end
    function a:GetCastRange() return 600 end
    function a:GetToggleState() return self.toggle end
    function a:entindex() return 90 end
    function a:IsCooldownReady() return false end
    function a:IsFullyCastable() return false end
    spells[#spells+1] = a
    return a
end
local first=ability("first_ultimate",8)
ability("passive_ultimate",0,true)
ability("second_ultimate",4)
ability("extra_spell",4)
ability("later_phase",4,false,true)
ability("special_bonus_test",0)
local caster = {
    GetAbilityCount=function() return #spells end,
    GetAbilityByIndex=function(_,i) return spells[i+1] end,
    FindAbilityByName=function(_,name) for _,a in ipairs(spells) do if a.name==name then return a end end end,
    IsAlive=function() return true end,
    entindex=function() return 1 end,
    GetAbsOrigin=function() return {x=0,y=0,z=0} end,
}
local actions=Catalog.ListActions(caster)
assert(table.concat(actions,",")=="first_ultimate,second_ultimate,extra_spell,sustained_move,attack","action picker excludes hidden helpers")
assert(table.concat(Catalog.ListAbilities(caster),",")=="first_ultimate,passive_ultimate,second_ultimate,extra_spell","condition picker includes visible passives")
spells[5].hidden=false
assert(table.concat(Catalog.ListActions(caster),",")=="first_ultimate,second_ultimate,extra_spell,later_phase,sustained_move,attack","newly visible phase becomes selectable")
spells[5].hidden=true
local _,name=Catalog.DescribeAction(caster,"second_ultimate")
assert(name=="second_ultimate", "multi-ultimate identity does not collapse")
local order
local adapter=Adapter.new({Execute=function(_,o) order=o end})
local ctx={resolve_action_name=function(_,id) return id end}
local toggle=ability("mana_toggle",512)
local spec=assert(adapter:Resolve(caster,{kind="ability",logical_id="mana_toggle",desired_toggle_state=false},ctx))
toggle.toggle=true
assert(adapter:CanExecute(caster,spec,{}),"switching off must work without mana/cooldown")
assert(adapter:IsInRange(caster,spec,nil),"toggle needs no target position")
assert(adapter:Issue(caster,spec,nil,{}))
assert(order.OrderType==DOTA_UNIT_ORDER_CAST_TOGGLE)
toggle.toggle=false
assert(not adapter:CanExecute(caster,spec,{}),"off rule never turns it on")
local on=assert(adapter:Resolve(caster,{kind="ability",logical_id="mana_toggle"},ctx))
assert(on.desired_toggle_state==true,"legacy toggle defaults to on, never flips repeatedly")
local hidden=assert(adapter:Resolve(caster,{kind="ability",logical_id="later_phase"},ctx))
local ok,reason=adapter:CanExecute(caster,hidden,{})
assert(not ok and reason=="action_hidden")
first.GetAOERadius=function() return 275 end
first.CastFilterResultTarget=function(_,t) return t.legal and 0 or 1 end
local unitSpec=assert(adapter:Resolve(caster,{kind="ability",logical_id="first_ultimate",aoe_radius=5000},ctx))
assert(unitSpec.aoe_radius==275 and unitSpec.ability==first,"native radius and source are authoritative")
order=nil
local bad={IsAlive=function() return true end, entindex=function() return 2 end}
assert(not adapter:Issue(caster,unitSpec,bad,{}))
assert(order==nil,"native rejection cannot emit or record an order")
bad.legal=true
assert(adapter:Issue(caster,unitSpec,bad,{}))
assert(order.TargetIndex==2)
first.CastFilterResultTarget=function() error("native filter unavailable") end
assert(not adapter:Issue(caster,unitSpec,bad,{}),"failed native filter fails closed")
ability("vector_spell",1024+16)
assert(adapter:Resolve(caster,{kind="ability",logical_id="vector_spell"},ctx).cast_type=="vector","native vector+point resolves generically")
ability("malformed_vector_spell",1024)
assert(adapter:Resolve(caster,{kind="ability",logical_id="malformed_vector_spell"},ctx)==nil,"a bare vector flag has no supported native primary order")
-- Both real stages remain editable before/after a swap, while native execution
-- rejects the inactive half. Saved rules use names even when physical slots swap.
local Defaults = require("issue_fixes.default_rules")
DOTA_UNIT_ORDER_CAST_NO_TARGET = 8
for _, pair in ipairs({
    {"dawnbreaker_celestial_hammer", "dawnbreaker_converge", 4},
    {"phoenix_fire_spirits", "phoenix_launch_fire_spirit", 16},
    {"puck_illusory_orb", "puck_ethereal_jaunt", 4},
}) do
    local primary = ability(pair[1], 16)
    local secondary = ability(pair[2], pair[3], false, true)
    secondary.GetLevel = function() return secondary.level or 1 end
    secondary.IsActivated = function() return secondary.active ~= false end
    secondary.IsCooldownReady = function() return true end
    secondary.IsFullyCastable = function() return true end
    local function has(list, value)
        local count = 0
        for _, entry in ipairs(list) do if entry == value then count = count + 1 end end
        return count == 1
    end
    for _, list in ipairs({Catalog.ListActions(caster), Catalog.ListAbilities(caster)}) do
        assert(has(list, pair[1]) and has(list, pair[2]), "prepare exposes both stages " .. pair[1])
        assert(not has(list, "later_phase"), "unrelated hidden helpers stay excluded")
    end
    local saved = {
        {id="first", enabled=true, action={kind="ability", logical_id=pair[1]},
            use_conditions={{type="elapsed_gte", value=3}}, target={team="enemy"}},
        {id="second", enabled=true, action={kind="ability", logical_id=pair[2]},
            use_conditions={{type="action_elapsed_gte", action_id=pair[1], value=1}}, target={team="self"}},
    }
    local secondSpec = assert(adapter:Resolve(caster, saved[2].action, ctx))
    local ready, why = adapter:CanExecute(caster, secondSpec, {})
    assert(not ready and why == "action_hidden", "editable follow-up cannot cast before native reveal")
    primary.hidden, secondary.hidden = true, false
    spells[#spells-1], spells[#spells] = secondary, primary
    local after = Catalog.ListActions(caster)
    assert(has(after, pair[1]) and has(after, pair[2]), "swapped primary remains editable")
    local preserved = Defaults.Normalize(saved, caster)
    assert(#preserved == 2 and preserved[1] == saved[1] and preserved[2] == saved[2] and preserved[2].use_conditions[1].action_id == pair[1], "authored stages keep independent conditions")
    assert(Catalog.DescribeAction(caster, pair[1]) == "ability")
    assert(adapter:Resolve(caster, saved[1].action, ctx).source == primary, "stable name survives slot swap")
    secondary.active = false
    ready, why = adapter:CanExecute(caster, secondSpec, {})
    assert(not ready and why == "action_deactivated", "visible inactive stage still blocked")
    secondary.active = true
    secondary.level = 0
    ready, why = adapter:CanExecute(caster, secondSpec, {})
    assert(not ready and why == "ability_unlearned", "editor does not force native level")
    secondary.level = 1
    assert(adapter:CanExecute(caster, secondSpec, {}), "native-ready follow-up executes")
    secondary.hidden = true
    assert(not has(Catalog.ListActions(caster), pair[1]) and not has(Catalog.ListActions(caster), pair[2]), "entirely hidden groups remain unavailable")
    spells[#spells], spells[#spells-1] = nil, nil
end
local orphan = ability("dawnbreaker_converge", 4, false, true)
assert(not table.concat(Catalog.ListActions(caster), ","):find(orphan.name, 1, true), "no phantom primary is invented for lone hidden handle")
print("action-v2 tests passed")
