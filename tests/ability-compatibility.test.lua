local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..root..'/tests/?.lua;'..package.path
local H=require('capability_test_helpers')
local A=require('tactics/ability_capability'); local R=require('tactics/rule_compatibility')
local Service=require('tactics/rule_service'); local M=require('tactics/modifier_catalog')
local hero=H.unit(); local a=H.ability(hero,'friendly_test',8,1,1)
local rule=H.rule(a.name,'ally')
assert(R.Validate(hero,rule))
rule.target.team='enemy'; local ok,reason=R.Validate(hero,rule); assert(not ok and reason=='target_team_incompatible')
rule.target.team='self'; assert(R.Validate(hero,rule)); a.flags=4096
assert(not R.Validate(hero,rule)); a.flags=0; rule.target.team='ally'; rule.target.types={'monster'}
assert(not R.Validate(hero,rule)); rule.target.types={'hero'}
a.behavior=8+16; rule.target.team='enemy'; assert(R.Validate(hero,rule),'point anchor is not native friendly unit target')
rule.action.cast_preference='unit'; assert(not R.Validate(hero,rule)); rule.action.cast_preference='point'; assert(R.Validate(hero,rule))
a.behavior=8+2^36; rule.action.cast_preference='unit'; rule.target.team='ally'; assert(R.Validate(hero,rule))
rule.action.cast_variant='alternate'; assert(not R.Validate(hero,rule)); rule.action.cast_variant=nil
rule.target.team='enemy'; a.team=2; rule.target_filters={{type='is_spell_immune'}}
assert(not R.Validate(hero,rule)); a.flags=16; assert(R.Validate(hero,rule))
a.behavior=16; rule.action.cast_preference='point'; a.flags=0; assert(R.Validate(hero,rule),'point aim immune anchor is not statically illegal')
rule.target_filters={}; rule.action.cast_preference=nil
for _,pair in ipairs({{'self_hp_pct_gte',.8,'self_hp_pct_lte',.2},{'elapsed_gte',10,'elapsed_lte',5},{'action_use_count_gte',1,'action_use_count_lt',1}}) do
 rule.use_conditions={{type=pair[1],value=pair[2]},{type=pair[3],value=pair[4]}}
 assert(R.Contradictions(rule),'impossible interval must be rejected')
end
rule.use_conditions={{type='self_hp_pct_lte',value=.2}};rule.target.team='self';rule.target_filters={{type='hp_pct_gte',value=.8}}
assert(R.Contradictions(rule),'self target and self gate refer to same HP')
rule.target.team='enemy';assert(not R.Contradictions(rule),'caster and enemy HP are different variables')
rule.target_filters={};rule.use_conditions={{type='action_elapsed_gte',value=10,action_id='a'},{type='action_elapsed_lte',value=5,action_id='b'}}
assert(not R.Contradictions(rule),'distinct actions are independent')
rule.use_conditions={{type='action_phase_is',value='IDLE'},{type='action_phase_is',value='EXECUTED'}};assert(R.Contradictions(rule))
rule.use_conditions={{type='no_enemy_within',radius=600},{type='nearby_enemies_gte',radius=400,value=1}};assert(R.Contradictions(rule))
rule.use_conditions={};rule.target.team='self';rule.target_filters={{type='exclude_self'}};assert(not R.Validate(hero,rule))
rule.target_filters={{type='distance_gte',value=1}};assert(not R.Validate(hero,rule))
rule.target_filters={};rule.target.team='enemy';rule.use_conditions={{type='self_has_modifier',modifier='modifier_typo'}}
M.Reset();ok,reason=R.Validate(hero,rule);assert(not ok and reason=='unverified_modifier_requires_ack')
rule.allow_unverified_modifiers=true;assert(R.Validate(hero,rule),'advanced opt-in does not pretend the modifier exists')
rule.allow_unverified_modifiers=false;hero.modifiers.modifier_typo={GetName=function() return 'modifier_typo' end};assert(R.Validate(hero,rule))
rule.use_conditions={{type='channel_elapsed_gte',seconds=1}};assert(not R.Validate(hero,rule),'non-release cannot cast during its own channel')
rule.use_conditions[1].action_actor='other';rule.use_conditions[1].action_id='owned_channel';assert(R.Validate(hero,rule))
rule.use_conditions={{type='action_elapsed_gte',seconds=1,action_id='unknown'}}
ok,reason=R.Validate(hero,rule,{validate_reference=function() return false end});assert(not ok and reason=='condition_action_not_owned')
rule.use_conditions={};rule.min_aoe_hits=999;assert(R.Validate(hero,rule));a.radius=300;assert(R.Validate(hero,rule));a.radius=0;assert(R.Validate(hero,rule),'retired hit count does not depend on live radius')
rule.action={kind='attack',logical_id='basic_attack'};assert(R.Validate(hero,rule),'legacy hit count is ignored for basic attacks too')
local service=Service.new({state={rules={}},get_phase=function() return 'PREPARE' end,is_roster_hero=function() return true end,is_action_allowed=function() return true end})
local decoded=service:DecodeFlat({action_kind='ability',action_id=a.name,action_name=a.name,target_team='enemy',target_types='hero',min_aoe_hits=0,desired_autocast_state='0'})
assert(decoded.action.desired_autocast_state==false);a.behavior=8+4096;assert(service:ValidateRule(0,hero,decoded));assert(decoded.min_aoe_hits==nil)
local sync;CustomNetTables={SetTableValue=function(_,_,_,v) sync=v end};service.get_hero_key=function() return 'test' end
service:SyncRule(0,hero,1,decoded);assert(sync.desired_autocast_state==false and sync.min_aoe_hits==nil)
print('PASS ability compatibility: native roles, contradictions, modifiers, references, live refresh, switch false, builtin parity')
