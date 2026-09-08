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
assert(table.concat(actions,",")=="first_ultimate,second_ultimate,extra_spell,later_phase,attack")
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
print("action-v2 tests passed")
