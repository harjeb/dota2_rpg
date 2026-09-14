local root=TEST_REPO_ROOT or '.'
package.path=root..'/game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..root..'/tests/?.lua;'..package.path
local H=require('capability_test_helpers')
GameRules={GetGameTime=function() return 10 end}
local C=require('tactics/condition_registry')
local Selector=require('tactics/target_selector').new()
local R=require('tactics/rule_compatibility')
local Service=require('tactics/rule_service')
local Snapshot=require('tactics/rule_snapshot')
local E=require('tactics/tactic_engine')
local hero=H.unit(2); hero.hp=50
local a,b,c=H.unit(3,100),H.unit(3,200),H.unit(3,300)
a.hp=20;b.hp=40;c.hp=90
local ability=H.ability(hero,'test_modes',8)
function ability:CastFilterResultTarget(target) return target.illegal and 1 or 0 end
local spec={kind='ability',logical_id=ability.name,source=ability,ability=ability,cast_type='unit',target_mode='unit'}
local ctx={caster=hero,now=10,get_candidates=function() return {a,b,c} end,is_in_range=function(_,target) return not target.outside end}
local use={{type='self_hp_pct_gte',value=.8},{type='self_hp_pct_lte',value=.6}}
local filters={{type='hp_pct_lte',value=.5},{type='hp_pct_gte',value=.8}}
assert(not C:EvaluateUseConditions(use,ctx))
assert(not C:EvaluateUseConditions(use,ctx,'all'))
assert(C:EvaluateUseConditions(use,ctx,'priority'))
assert(not C:EvaluateUseConditions(use,ctx,'invalid'))
local calls={}
C:RegisterUseCondition('mode_test_false',function() calls[#calls+1]='false';return false end)
C:RegisterUseCondition('mode_test_true',function() calls[#calls+1]='true';return true end)
C:RegisterUseCondition('mode_test_late',function() error('must short circuit') end)
assert(C:EvaluateUseConditions({{type='mode_test_false'},{type='mode_test_true'},{type='mode_test_late'}},ctx,'priority'))
assert(table.concat(calls,',')=='false,true','ordered OR stops at first satisfied condition')
assert(not C:EvaluateUseConditions({{type='mode_test_false'}},ctx,'priority'))
assert(C:EvaluateUseConditions({},ctx,'priority') and C:EvaluateTargetFilters({},ctx,a,'priority'))
local rule=H.rule(ability.name);rule.use_conditions=use;rule.target_filters=filters
rule.target_priorities={{type='farthest'}}
assert(R.Contradictions(rule),'AND contradiction remains rejected')
rule.use_conditions_mode='priority';rule.target_filters_mode='priority'
assert(not R.Contradictions(rule),'alternative ranges are not an AND contradiction')
assert(Selector:SelectUnit(rule,spec,ctx)==b,'first tier wins over farther later tier; ranking within tier retained')
a.illegal=true;b.illegal=true
assert(Selector:SelectUnit(rule,spec,ctx)==c,'native-illegal first tier cannot suppress legal fallback')
a.illegal=false;b.illegal=false;a.outside=true;b.outside=true
assert(Selector:SelectUnit(rule,spec,ctx)==c,'range-only falls through unavailable tiers')
rule.approach='allow_approach'
assert(Selector:SelectUnit(rule,spec,ctx)==b,'approachable tiers remain eligible')
rule.approach='range_only';a.outside=nil;b.outside=nil
rule.target_filters_mode='all';assert(not Selector:SelectUnit(rule,spec,ctx))
rule.target_filters_mode='unknown';assert(not Selector:SelectUnit(rule,spec,ctx),'unknown mode safely uses AND')
rule.target_filters_mode='priority';rule.target_filters={{type='hp_pct_lte',value=.01}}
assert(not Selector:SelectUnit(rule,spec,ctx));assert(not Selector:CheckNoTarget(rule,{kind='ability',target_mode='none'},ctx))
rule.target_filters={};assert(Selector:SelectUnit(rule,spec,ctx)==c)
assert(Selector:CheckNoTarget(rule,{target_mode='none'},ctx),'empty target group is unrestricted')
rule.target_filters=filters
assert(Selector:CheckNoTarget(rule,{kind='ability',target_mode='none'},ctx))
rule.target_filters_mode='all';assert(not Selector:CheckNoTarget(rule,{kind='ability',target_mode='none'},ctx))
-- Both independent switches flow through the actual executor, not only helpers.
local orders={}
local engine=E.new({order_gate={Execute=function(_,o) orders[#orders+1]=o;return true end},get_phase=function() return 'FIGHT' end,
 get_battle_units=function() return {hero} end,get_rules=function() return {rule} end,build_context=function() return ctx end})
function engine:Debug() end
for _,um in ipairs({'all','priority'}) do for _,tm in ipairs({'all','priority'}) do
 rule.use_conditions_mode=um;rule.target_filters_mode=tm
 engine:Reset();orders={}
 local passed=engine:TryRule(hero,engine:GetState(hero),ctx,rule,1)
 assert((passed==true)==(um=='priority' and tm=='priority'),um..'/'..tm..' independent execution')
 if passed then assert(#orders==1 and orders[1].TargetIndex==b.id) end
end end
-- Location cast filters and vector construction/range are viability, before tier choice.
rule.use_conditions={};rule.target_filters_mode='priority'
ability.behavior=16
function ability:CastFilterResultLocation(point) return point.x<250 and 1 or 0 end
spec.cast_type='point';spec.target_mode='point'
local point,anchor=Selector:SelectPoint(rule,spec,ctx)
assert(anchor==c and point==c.position,'illegal location tier falls back')
ability.behavior=1073741824+16
spec.cast_type='vector';spec.target_mode='vector';spec.vector_mode='point'
local vector,primary=Selector:SelectVector(rule,spec,ctx)
assert(primary==c and vector.primary==c,'vector point native rejection falls back')
ability.behavior=1073741824+8
spec.vector_mode='unit';a.illegal=true;b.illegal=true
vector,primary=Selector:SelectVector(rule,spec,ctx)
assert(primary==c,'vector unit native rejection falls back')
a.illegal=nil;b.illegal=nil
ability.behavior=8;spec.cast_type='unit';spec.target_mode='self'
rule.target_filters={{type='hp_pct_gte',value=.8},{type='hp_pct_lte',value=.6}}
assert(Selector:SelectUnit(rule,spec,ctx)==hero,'self target priority is ordered OR')
rule.target_filters_mode='all';assert(not Selector:SelectUnit(rule,spec,ctx))
-- Decode, validation, saved migration, public snapshot, nettable and deep copies.
local state={rules={}}
local service=Service.new({state=state,get_phase=function() return 'PREPARE' end,is_roster_hero=function() return true end,
 is_action_allowed=function() return true end,get_hero_key=function() return 'hero' end})
local flat={action_kind='ability',action_id=ability.name,action_name=ability.name,target_team='enemy',target_types='hero',
 use_conditions_mode='priority',target_filters_mode='priority',use_condition_1_type='self_hp_pct_gte',use_condition_1_value=.8,
 use_condition_2_type='self_hp_pct_lte',use_condition_2_value=.6,target_filter_1_type='hp_pct_lte',target_filter_1_value=.5,
 target_filter_2_type='hp_pct_gte',target_filter_2_value=.8}
local decoded=service:DecodeFlat(flat)
assert(service:ValidateRule(0,hero,decoded),'schema accepts alternative ranges independently')
state.rules.hero={decoded}
local manager={getRules=function() return service:GetHeroRules(hero) end}
local snap=Snapshot.ForHero(manager,hero)[1]
assert(snap.use_conditions_mode=='priority' and snap.target_filters_mode=='priority')
local wire
CustomNetTables={SetTableValue=function(_,_,_,payload) wire=payload end}
service:SyncRule(0,hero,1,decoded)
assert(wire.use_conditions_mode=='priority' and wire.target_filters_mode=='priority')
local restored=service:DecodeFlat(wire)
assert(restored.use_conditions_mode=='priority' and restored.target_filters_mode=='priority' and #restored.use_conditions==2)
local copy=require('battle/arena_profile').Copy(restored)
copy.use_conditions_mode='all';copy.target_filters[1].value=.1
assert(restored.use_conditions_mode=='priority' and restored.target_filters[1].value==.5,'copy isolation retains switch values')
for _,mode in ipairs({'all','priority','garbage',false,123,{}}) do
 local r=service:DecodeFlat({use_conditions_mode=mode,target_filters_mode=mode})
 assert(r.use_conditions_mode==(mode=='priority' and 'priority' or 'all') and r.target_filters_mode==r.use_conditions_mode)
end
local old=H.rule(ability.name);state.rules.hero={old};service:GetHeroRules(hero)
assert(old.use_conditions_mode=='all' and old.target_filters_mode=='all','old saves migrate to independent AND defaults')
old.use_conditions_mode={};old.target_filters_mode='bad';assert(service:ValidateRule(0,hero,old))
assert(old.use_conditions_mode=='all' and old.target_filters_mode=='all','canonical schema normalizes malformed modes safely')
print('PASS condition modes: ordered OR, independent engine combinations, tier/ranking/native/range fallback, self/point/vector/no-target, schema/nettable/snapshot/migration/copy')
