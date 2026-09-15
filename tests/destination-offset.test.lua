local root = arg and arg[1] or "game/dota_addons/dota2_rpg/scripts/vscripts"
package.path = root .. "/?.lua;" .. package.path
UF_SUCCESS = 0
local vectorMeta = {}
vectorMeta.__index = vectorMeta
function vectorMeta:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
function vectorMeta.__sub(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=0},vectorMeta) end
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z},vectorMeta) end

local Special = require("tactics/special_targets")
local Service = require("tactics/rule_service")

local function unit(id,team,x,y,fx,fy)
    local u={id=id,team=team,x=x,y=y,fx=fx or 1,fy=fy or 0}
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:GetTeamNumber() return self.team end
    function u:GetAbsOrigin() return setmetatable({x=self.x,y=self.y,z=0},vectorMeta) end
    function u:GetForwardVector() return {x=self.fx,y=self.fy,z=0} end
    function u:entindex() return self.id end
    return u
end
local function close(point,x,y) return point~=nil and math.abs(point.x-x)<0.01 and math.abs(point.y-y)<0.01 end

local caster = unit(1,2,0,0)
local enemy = unit(3,3,0,100,1,0)  -- enemy faces +x, deliberately not along the caster line
local spec = {logical_id="item_blink", target_mode="point",
    source={CastFilterResultLocation=function() return UF_SUCCESS end}}
local actions = {GetRequiredRange=function() return 1200 end}
local function offset(mode,distance) return Special.OffsetDestination(mode,caster,enemy,spec,{destination_distance=distance},actions) end

-- away_from_target 从施法者背向敌人；target_front/behind 用敌人朝向；around 取连线近侧。
assert(close(offset("away_from_target",400),0,-400), "away_from_target steps back from the caster")
assert(close(offset("target_front",400),400,100), "target_front follows enemy facing")
assert(close(offset("target_behind",400),-400,100), "target_behind reverses enemy facing")
assert(close(offset("around_target",400),0,-300), "around_target lands between caster and enemy")

-- 距离按施法距离封顶；缺省时用敌人参考距离。
assert(close(offset("away_from_target",5000),0,-1200), "backstep distance clamps to cast range")
assert(close(offset("around_target",nil),0,-300), "missing distance falls back to the default offset")
assert(close(offset("away_from_target",nil),0,-1200), "missing backstep falls back to cast range")

-- d 大于施法者与敌人间距时按原样计算，不收缩（可能越过施法者）。
local nearEnemy = unit(4,3,0,300,0,-1)
local farPoint = Special.OffsetDestination("around_target",caster,nearEnemy,spec,{destination_distance=400},actions)
assert(close(farPoint,0,-100), "distance larger than the gap is computed as authored")

-- 背离方向被地形挡住时扫描可站立方向。
GridNav = {CanFindPath=function(_,from,to) return to.x >= 300 end}
local swept = offset("away_from_target",400)
assert(swept~=nil and swept.x>300 and swept.y<0, "blocked backstep sweeps to a walkable direction")
GridNav = nil

-- 原生位置校验失败时安全放弃。
local rejected = {logical_id="item_blink",target_mode="point",source={CastFilterResultLocation=function() return 1 end}}
assert(Special.OffsetDestination("around_target",caster,enemy,rejected,{destination_distance=400},actions)==nil,
    "native location rejection fails closed")

-- 非点目标动作在运行时按无效落点拒绝。
assert(Special.OffsetDestination("away_from_target",caster,enemy,{logical_id="spell",target_mode="unit"},nil,actions)==nil,
    "unit-target action cannot use an offset destination")

-- 校验：偏移落点对任意技能名开放，但仍拒绝无关的残焰落点。
assert(Special.ValidDestination("item_blink","away_from_target"), "offset destination is accepted")
assert(Special.ValidDestination("any_spell","target_front"), "offset destination is not name-gated")
assert(not Special.ValidDestination("any_spell","remnant_nearest"), "remnant destinations stay name-gated")
assert(not Special.ValidDestination("elder_titan_move_spirit",{}), "table mode remains invalid")
local handled,_,_,reason = Special.SelectDestination(
    {action={destination="around_target"}},spec,{}, {})
assert(handled and reason=="offset_destination_requires_engine", "direct SelectDestination defers offset modes to the engine")

-- 服务端解码/校验保留落点与距离。
local service = Service.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function() return true end,state={rules={}}})
local rule = service:DecodeFlat({action_kind="item",action_id="item_blink",destination="away_from_target",
    destination_distance=400,target_team="enemy"})
assert(rule.action.destination=="away_from_target" and rule.action.destination_distance==400,
    "offset destination and distance survive wire decoding")
assert(service:ValidateRule(0,caster,rule), "offset destination rule validates")
local bad = service:DecodeFlat({action_kind="item",action_id="item_blink",destination="away_from_target",
    destination_distance="bad",target_team="enemy"})
assert(not service:ValidateRule(0,caster,bad), "non-numeric offset distance is rejected")
local huge = service:DecodeFlat({action_kind="item",action_id="item_blink",destination="target_front",
    destination_distance=99999,target_team="enemy"})
assert(not service:ValidateRule(0,caster,huge), "offset distance above the cap is rejected")

-- Conflicting old/client payloads retain their destination but lose both rankings.
for mode in pairs(Special.destinations) do
    local migrated = service:DecodeFlat({action_kind="ability",action_id="ember_spirit_activate_fire_remnant",
        destination=mode,target_team="enemy",target_priority_1_type="farthest",target_priority_2_type="lowest_hp_pct"})
    assert(migrated.action.destination==mode, "decoding preserves destination "..mode)
    assert(#migrated.target_priorities==(mode=="target" and 2 or 0), "exclusive decoded ranking "..mode)
    migrated.target_priorities={{type="farthest"},{type="lowest_hp_pct"}}
    assert(service:ValidateRule(0,caster,migrated), "structured destination validates "..mode)
    assert(#migrated.target_priorities==(mode=="target" and 2 or 0), "exclusive validated ranking "..mode)
end
for _, mode in ipairs({"", "target"}) do
    local ordinary=service:DecodeFlat({action_kind="item",action_id="item_blink",destination=mode,
        target_priority_1_type="farthest",target_priority_2_type="lowest_hp_pct"})
    assert(#ordinary.target_priorities==2, "ordinary target ranking stays intact")
end
require("tactics/tactic_bridge")
local restored=TacticBridge.ConvertLegacyRule(1,{action="item_blink",target="lowest_hp",
    destination="target_behind",destination_distance=500,target_priorities={{type="farthest"}}})
assert(#restored.target_priorities==0 and restored.action.destination=="target_behind"
    and restored.action.destination_distance==500, "legacy restore clears explicit and inferred ranking")

-- 引擎层：偏移落点先选出锚点，再用它计算落点；没有锚点或非点目标都安全失败。
local Engine = require("tactics/tactic_engine")
local engine = Engine.new({order_gate={Execute=function() return true end},
    get_phase=function() return "FIGHT" end,get_battle_units=function() return {caster} end,
    get_rules=function() return {} end,build_context=function() return {} end,actions=actions})
local rule = {action={destination="away_from_target",destination_distance=400},
    target={team="enemy",types={"hero"}},target_filters={},target_priorities={}}
local candidates = {enemy}
local ctx = {caster=caster,now=1,get_candidates=function() return candidates end}
local point, anchor = engine:ResolveRuleTarget(rule, spec, ctx)
assert(anchor==enemy and close(point,0,-400), "engine resolves the offset destination from the selected anchor")
candidates={nearEnemy,enemy}
rule.target_priorities={{type="farthest"},{type="lowest_hp_pct"}}
point,anchor=engine:ResolveRuleTarget(rule,spec,ctx)
assert(anchor==enemy and close(point,0,-400) and #rule.target_priorities==0,
    "runtime legacy conflict uses nearest legal anchor rather than hidden farthest priority")
candidates = {}
assert(engine:ResolveRuleTarget(rule, spec, ctx)==nil, "missing legal anchor fails the offset destination")
candidates = {enemy}
assert(engine:ResolveRuleTarget(rule, {target_mode="unit"}, ctx)==nil, "offset destination rejects non-point actions")
print("destination-offset tests passed")
