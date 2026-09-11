local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..root..'/tests/?.lua;'..package.path
local H=require('capability_test_helpers')
local Engine=require('tactics/tactic_engine')
local Service=require('tactics/rule_service')
local hero,enemy=H.unit(2),H.unit(3,200)
local service=Service.new({get_phase=function() return 'PREPARE' end,is_roster_hero=function() return true end,
 is_action_allowed=function() return true end,state={rules={}}})
local orders={}
GameRules={GetGameTime=function() return 10 end}
local engine=Engine.new({order_gate={Execute=function(_,order) orders[#orders+1]=order end},
 get_phase=function() return 'FIGHT' end,get_battle_units=function() return {hero,enemy} end,
 get_rules=function() return {} end,build_context=function() return {get_candidates=function() return {enemy} end} end})
local function attempt(rule)
 engine:Reset();orders={}
 return engine:TryRule(hero,engine:GetState(hero),engine:BuildContext(hero,10),rule,1)
end
for _,entry in ipairs({{'pudge_rot',512,9},{'leshrac_pulse_nova',512,9},
 {'lion_impale',8+16,6},{'lina_light_strike_array',16,5},{'centaur_hoof_stomp',4,8}}) do
 local name,behavior,orderType=unpack(entry)
 local ability=H.ability(hero,name,behavior);ability.radius=300
 local flat={action_kind='ability',action_id=name,action_name=name,min_aoe_hits=999,
  target_team='enemy',target_types='hero',use_condition_1_type='self_mana_pct_gte',use_condition_1_value=0.5,
  target_filter_1_type='hp_pct_lte',target_filter_1_value=0.5,target_priority_1_type='lowest_hp_pct'}
 if name=='lion_impale' then flat.cast_preference='unit' end
 local rule=service:DecodeFlat(flat)
 assert(rule.min_aoe_hits==nil,name..' drops flat legacy count')
 rule.min_aoe_hits='obsolete malformed value'
 assert(service:ValidateRule(0,hero,rule) and rule.min_aoe_hits==nil,name..' discards invalid old in-memory count')
 rule.min_aoe_hits=999 -- Already-loaded rules need to work without save/revalidation.
 hero.mana=100;enemy.hp=40;enemy.position=Vector(200)
 assert(attempt(rule) and #orders==1 and orders[1].OrderType==orderType,name..' casts on one eligible enemy with high legacy count')
 hero.mana=40
 assert(not attempt(rule) and #orders==0,name..' still honors mana condition')
 hero.mana=100;enemy.hp=80
 assert(not attempt(rule) and #orders==0,name..' still honors target HP filter')
 enemy.hp=40
 if behavior==512 or behavior==4 then
  enemy.position=Vector(301)
  assert(attempt(rule),name..' preserves matching-trigger semantics independent of radius')
  rule.target_filters[2]={type='distance_lte',value=300}
  assert(not attempt(rule) and #orders==0,name..' still honors explicit target distance')
  rule.target_filters={}
  assert(attempt(rule),name..' needs no trigger when no target filters are configured')
 else
  ability.CastFilterResultTarget=function() return 1 end
  ability.CastFilterResultLocation=function() return 1 end
  assert(not attempt(rule) and #orders==0,name..' still honors native cast filtering')
 end
end
-- Native radius metadata never substitutes for explicit trigger conditions.
local a=H.ability(hero,'centaur_hoof_stomp',4);a.radius=150
local rule=H.rule(a.name);rule.min_aoe_hits=999;rule.target_filters={{type='hp_pct_lte',value=0.5}}
enemy.position=Vector(200);enemy.hp=40
assert(attempt(rule));a.radius=250;assert(attempt(rule),'native radius changes do not add implicit target restrictions')
a.radius=0;assert(attempt(rule),'zero-radius global/no-radius actions use matching trigger existence')
hero.channel=true;assert(not attempt(rule) and #orders==0,'legacy count removal does not permit channel interruption')
print('PASS legacy hit count: Rot/Pulse Nova/Lion/point/no-target casts, decode/discard, AND conditions, native filters, explicit distance, channel')
