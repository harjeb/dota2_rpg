local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..root..'/tests/?.lua;'..package.path
local H=require('capability_test_helpers')
local Service=require('tactics/rule_service')
local Snapshot=require('tactics/rule_snapshot')
local Registry=require('tactics/condition_registry')
local Compatibility=require('tactics/rule_compatibility')
require('tactics/tactic_bridge')
local hero=H.unit()
local spell=H.ability(hero,'test_reaction',16,2,1)
hero.GetUnitName=function() return 'npc_dota_hero_test' end
EntIndexToHScript=function() return hero end
local state={rules={}}
local service=Service.new({state=state,get_phase=function() return 'PREPARE' end,
 is_roster_hero=function() return true end,is_action_allowed=function() return true end})
local published
CustomNetTables={SetTableValue=function(_,_,_,v) published=v end}
local function flat(extra)
 local v={action_kind='ability',action_id=spell.name,target_team='enemy',target_types='hero',use_condition_1_type='incoming_aoe'}
 for k,x in pairs(extra or {}) do v[k]=x end
 return v
end
local function validate(extra)
 local r=service:DecodeFlat(flat(extra));local ok,reason=service:ValidateRule(0,hero,r);return ok,reason,r
end
for _,response in ipairs({'walk','cast'}) do
 for _,bounds in ipairs({{0,0},{80,500},{2000,2000},{12.5,1999.5}}) do
  assert(service:UpdateRule(0,1,1,flat({use_condition_1_response=response,use_condition_1_reaction_min_ms=tostring(bounds[1]),use_condition_1_reaction_max_ms=tostring(bounds[2])})))
  local stored=state.rules.npc_dota_hero_test[1]
  local c=stored.use_conditions[1]
  assert(c.response==response and c.reaction_min_ms==bounds[1] and c.reaction_max_ms==bounds[2])
  local decoded=service:DecodeFlat(published)
  assert(service:ValidateRule(0,hero,decoded))
  local saved=Snapshot.ForHero({getRules=function() return {stored} end},hero)[1]
  local restored=TacticBridge.ConvertLegacyRule(1,saved)
  assert(service:ValidateRule(0,hero,restored))
  for _,field in ipairs({'response','reaction_min_ms','reaction_max_ms'}) do
   assert(published['use_condition_1_'..field]==c[field])
   assert(decoded.use_conditions[1][field]==c[field])
   assert(saved.use_conditions[1][field]==c[field])
   assert(restored.use_conditions[1][field]==c[field])
  end
 end
end
local retired=service:DecodeFlat(flat({use_condition_1_feint_policy='early'}))
assert(retired.use_conditions[1].feint_policy==nil,'released-only wire omits retired feint policy')
assert(not service:ValidateCondition({type='incoming_aoe',feint_policy='early'},Registry.use_conditions),'nested schema rejects retired feint policy')
local ok,reason,r=validate()
assert(ok and r.use_conditions[1].response=='walk' and r.use_conditions[1].reaction_min_ms==80 and r.use_conditions[1].reaction_max_ms==500)
for _,field in ipairs({'reaction_min_ms','reaction_max_ms'}) do
 for _,bad in ipairs({-1,2001,math.huge,0/0,'abc',false,{}}) do
  ok,reason=validate({['use_condition_1_'..field]=bad})
  assert(not ok and reason=='invalid_condition_'..field,tostring(reason))
 end
end
for _,extra in ipairs({{use_condition_1_reaction_min_ms=501},{use_condition_1_response='blink'},
 {use_condition_1_modifier='modifier_bad'},
 {use_condition_1_value=1},{use_condition_1_action_id='other'}}) do assert(not validate(extra)) end
assert(not validate({use_condition_1_type='',target_filter_1_type='incoming_aoe'}),'USE only')
ok,reason=validate({use_condition_2_type='incoming_aoe'})
assert(not ok and reason=='duplicate_incoming_aoe')
assert(not validate({use_condition_1_response='cast',prediction_direction='forward'}))
assert(Compatibility.IncomingAoeCastReason({kind='ability',destination='retreat'},{cast={},mode='point'},'enemy')=='incoming_aoe_cast_unsupported')
ok,reason,r=validate({use_condition_1_type='always',use_condition_1_response='cast',use_condition_1_reaction_min_ms=100,use_condition_1_feint_policy='early'})
assert(ok,reason)
assert(r.use_conditions[1].response==nil and r.use_conditions[1].reaction_min_ms==nil and r.use_conditions[1].feint_policy==nil)
local previous,previousPayload=state.rules.npc_dota_hero_test[1],published
assert(not service:UpdateRule(0,1,1,flat({use_condition_1_reaction_max_ms=-1})))
assert(previous==state.rules.npc_dota_hero_test[1] and previousPayload==published,'rejection is atomic')
for _,kind in ipairs({'attack','move','wait'}) do
 assert(validate({action_kind=kind}),'walk keeps existing row action')
 assert(not validate({action_kind=kind,use_condition_1_response='cast'}))
end
assert(Compatibility.IncomingAoeCastReason({kind='buyback'},nil,'self')=='incoming_aoe_cast_requires_ability_or_item')
assert(Compatibility.IncomingAoeCastReason({kind='ability'},nil,'self')=='incoming_aoe_cast_requires_known_capability')
for _,behavior in ipairs({4,16}) do spell.behavior=behavior;assert(validate({use_condition_1_response='cast'})) end
for _,behavior in ipairs({16+DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING,4+DOTA_ABILITY_BEHAVIOR_TOGGLE,8+DOTA_ABILITY_BEHAVIOR_AUTOCAST}) do
 spell.behavior=behavior;assert(not validate({use_condition_1_response='cast'}))
end
spell.behavior=8;spell.team=2
assert(not validate({use_condition_1_response='cast'}),'offensive unit cannot evade')
spell.team=1
assert(validate({use_condition_1_response='cast',target_team='self'}),'friendly unit may self cast')
assert(not validate({use_condition_1_response='cast',target_team='ally'}),'other ally is not self')
local ctx,condition={}, {type='incoming_aoe'}
local result=false
package.loaded['tactics/aoe_reaction']={Match=function(actualCtx,actualCondition)
 assert(actualCtx==ctx and actualCondition==condition);return result
end}
assert(Registry.use_conditions.incoming_aoe(ctx,condition)==false)
result=true;assert(Registry.use_conditions.incoming_aoe(ctx,condition)==true)
assert(Registry.target_filters.incoming_aoe==nil)
print('PASS: incoming AOE schema, atomic saves, flat sync, snapshots/restoration, cast compatibility and evaluator delegation')
