package.path = "game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;" .. package.path
local C = require("tactics/condition_registry")
local H = require("tactics/condition_context")
local R = require("tactics/rule_service")
local S = require("tactics/target_selector")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function vec(x)
    return setmetatable({x=x}, {__sub=function(a,b) return {Length2D=function() return math.abs(a.x-b.x) end} end})
end
local function unit(id, team, x)
    return { entindex=function() return id end, IsNull=function() return false end,
        IsAlive=function() return true end, GetTeamNumber=function() return team end,
        GetAbsOrigin=function() return vec(x) end, GetHealth=function() return 40 end,
        GetMaxHealth=function() return 100 end, GetMana=function() return 20 end,
        GetMaxMana=function() return 100 end, GetUnitName=function() return "hero" end }
end
local caster, ally, enemy, far = unit(1,2,0), unit(2,2,100), unit(3,3,200), unit(4,3,1000)
local ctx = {caster=caster, count_enemies_around=function(center,radius)
    return H.CountAround({caster,ally,enemy,far},center,radius,false) end,
    count_allies_around=function(center,radius) return H.CountAround({caster,ally,enemy,far},center,radius,true) end}
check(C:EvaluateUseConditions({{type="nearby_enemies_gte",value=1,radius=200}},ctx),"near enemy")
check(not C:EvaluateUseConditions({{type="nearby_enemies_gte",value=2,radius=200}},ctx),"radius matters")
check(H.CountAround({caster,ally,enemy},enemy,300,false)==2,"counts relative to observed team")
check(H.CountAround({caster,ally,ally},caster,300,true)==1,"exclude center and duplicates")
for _, name in ipairs({"self_hp_pct_lte","self_hp_pct_gte","self_mana_pct_lte","self_mana_pct_gte"}) do
    check(C:EvaluateUseConditions({{type=name,value=name:find("hp") and .4 or .2}},ctx),name)
end
for _, pair in ipairs({{"hp_pct_lte",.4},{"hp_pct_gte",.4},{"mana_pct_lte",.2},{"mana_pct_gte",.2},
    {"missing_health_gte",60},{"missing_health_lte",60},{"distance_gte",200},{"distance_lte",200}}) do
    check(C:EvaluateTargetFilters({{type=pair[1],value=pair[2]}},ctx,enemy),pair[1])
end
check(not C:EvaluateTargetFilters({{type="exclude_self"}},ctx,caster),"exclude self")
for _, method in ipairs({"IsStunned","IsRooted","IsSilenced","IsHexed"}) do
    enemy[method]=function() return true end
    check(C:EvaluateTargetFilters({{type="is_controlled"}},ctx,enemy),method)
    enemy[method]=nil
end
enemy.IsChanneling=function() return true end
check(C:EvaluateTargetFilters({{type="is_casting"}},ctx,enemy),"channel is casting")
enemy.IsChanneling=nil; enemy.IsInAbilityPhase=function() return true end
check(C:EvaluateTargetFilters({{type="is_casting"}},ctx,enemy),"phase is casting")
check(not C:EvaluateTargetFilters({{type="not_spell_immune"}},ctx,enemy),"unknown immunity fails closed")
enemy.IsMagicImmune=function() return false end
check(C:EvaluateTargetFilters({{type="not_spell_immune"}},ctx,enemy),"known immunity")
local mod = {GetStackCount=function() return 3 end, GetRemainingTime=function() return .5 end,
    IsPurgable=function() return true end, IsDebuff=function() return true end}
enemy.FindModifierByName=function(_,name) if name=="mark" then return mod end end
check(C:EvaluateTargetFilters({{type="modifier_stacks_gte",modifier="mark",value=3},
    {type="modifier_remaining_lte",modifier="mark",value=.5}},ctx,enemy),"mark detonation window")
check(not C:EvaluateTargetFilters({{type="modifier_remaining_lte",modifier="absent",value=1}},ctx,enemy),"missing modifier is not expired")
mod.GetRemainingTime=function() return -1 end
check(not C:EvaluateTargetFilters({{type="modifier_remaining_lte",modifier="mark",value=1}},ctx,enemy),"permanent not expiring")
enemy.FindAllModifiers=function() return {mod} end
check(H.HasDispellable(enemy,true) and not H.HasDispellable(enemy,false),"dispel polarity")
mod.IsPurgable=function() error("native unavailable") end
check(not H.HasDispellable(enemy,true),"guarded native failure")
check(not H.HasShield(enemy),"no fabricated shield")
enemy.GetAllDamageBarrier=function() return 42 end
check(H.HasShield(enemy),"measured shield")
ctx.get_ability_charges=function() return 2 end
check(C:EvaluateUseConditions({{type="ability_charges_gte",value=2}},ctx),"charges")
check(not C:EvaluateUseConditions({{type="action_use_count_lt",value=1}},ctx),"unknown history")
ctx.get_action_use_count=function() return 1 end
check(not C:EvaluateUseConditions({{type="action_use_count_lt",value=1}},ctx),"order limit")
local service=R.new({get_phase=function() return "PREPARE" end,is_roster_hero=function() return true end,
    is_action_allowed=function(_,_,a) return a.logical_id=="spell" end,state={rules={}}})
local removedUse={"dead_ally_count_gte","self_strength_gte","self_agility_gte","owned_summons_gte",
    "owned_summons_lte","action_used_within","action_not_used_within"}
local removedTarget={"not_illusion","is_creep","is_invulnerable","not_invulnerable","has_tag","not_has_tag"}
for _, group in ipairs({{removedUse,C.use_conditions,"use_conditions"},{removedTarget,C.target_filters,"target_filters"}}) do
    for _, id in ipairs(group[1]) do
        local condition={type=id,value=1}
        check(group[2][id]==nil,"removed registry entry "..id)
        local ok,reason=service:ValidateCondition(condition,group[2])
        check(not ok and reason=="unknown_condition:"..id,"removed submission rejected "..id)
        if group[3]=="use_conditions" then
            ok,reason=C:EvaluateUseConditions({condition},ctx)
        else
            ok,reason=C:EvaluateTargetFilters({condition},ctx,enemy)
        end
        check(not ok and reason:find("unknown_",1,true)==1,"removed runtime rejected "..id)
    end
end
local stored=service:DecodeFlat({action_kind="ability",action_id="spell"})
for _,id in ipairs(removedUse) do table.insert(stored.use_conditions,{type=id,value=1}) end
stored.use_conditions[#stored.use_conditions+1]={type="always"}
for _,id in ipairs(removedTarget) do table.insert(stored.target_filters,{type=id,value="boss"}) end
stored.target_filters[#stored.target_filters+1]={type="is_illusion"}
service.state.rules.hero={stored}
local migrated=service:GetHeroRules(caster)[1]
check(migrated==stored and #stored.use_conditions==1 and stored.use_conditions[1].type=="always","stored use conditions compacted")
check(#stored.target_filters==1 and stored.target_filters[1].type=="is_illusion","stored filters preserve retained condition")
check(service:ValidateRule(0,caster,stored),"migrated rule remains valid")
check(#service:GetHeroRules(caster)[1].target_filters==1,"migration is idempotent")
service.state.rules.hero[7]={use_conditions={{type="owned_summons_gte",value=1}},target_filters={{type="not_illusion"},{type="is_illusion"}}}
service:GetHeroRules(caster)
check(#service.state.rules.hero[7].use_conditions==0 and #service.state.rules.hero[7].target_filters==1,"sparse saved rule slots are migrated")
check(C.HasTag({get_tags=function() return {boss=true} end},enemy,"boss"),"native tag helper retained")
local args={action_kind="ability",action_id="spell",desired_toggle_state="0",rule_count=32}
for i=1,4 do args["use_condition_"..i.."_type"]="self_hp_pct_lte";args["use_condition_"..i.."_value"]=.5
    args["target_filter_"..i.."_type"]="hp_pct_lte";args["target_filter_"..i.."_value"]=.5 end
args.target_priority_1_type="lowest_attack_damage";args.target_priority_2_type="highest_magic_resistance"
local rule=service:DecodeFlat(args)
check(#rule.use_conditions==4 and #rule.target_filters==4 and #rule.target_priorities==2,"4/4/2 decode")
check(rule.action.desired_toggle_state==false,"false toggle preserved")
check(service:ValidateRule(0,caster,rule),"valid v2 rule")
rule.use_conditions[4].value=.3
check(not C:EvaluateUseConditions(rule.use_conditions,ctx),"fourth AND enforced")
for _, bad in ipairs({0/0,math.huge,-math.huge,{},false,"nan","bad",1.1}) do
    check(not service:ValidateCondition({type="hp_pct_lte",value=bad},C.target_filters),"reject invalid fraction")
end
check(not service:ValidateCondition({type="nearby_enemies_gte",value=1,radius="bad"},C.use_conditions),"reject radius")
local payload
CustomNetTables={SetTableValue=function(_,_,_,data) payload=data end}
EntIndexToHScript=function() return caster end
check(service:UpdateRule(0,1,32,args),"slot 32")
check(payload.use_condition_4_value==.5 and payload.target_filter_4_type=="hp_pct_lte","sync all fields")
check(payload.desired_toggle_state=="0","sync toggle off")
check(not service:UpdateRule(0,1,33,args),"slot 33 rejected")
check(not service:UpdateRule(0,1,0/0,args),"NaN slot rejected")
args.action_id="forged";check(not service:UpdateRule(0,1,1,args),"server action authority")
args.action_id="spell"; args.use_condition_5_type="always"
check(not service:UpdateRule(0,1,1,args),"extra flat condition rejected")
local spec={kind="ability",target_mode="unit",ability={CastFilterResultTarget=function(_,target) return target==enemy and 1 or 0 end}}
ctx.get_candidates=function() return {enemy,ally} end
local selected=S.new():SelectUnit({target={},target_filters={},target_priorities={}},spec,ctx)
check(selected==ally,"illegal native candidate removed before sorting")
enemy.GetAverageTrueAttackDamage=function() return 100 end;ally.GetAverageTrueAttackDamage=function() return 10 end
enemy.GetMagicalArmorValue=function() return .5 end;ally.GetMagicalArmorValue=function() return .2 end
check(S.new():SortCandidates({enemy,ally},{{type="lowest_attack_damage"}},ctx)[1]==ally,"lowest attack")
check(S.new():SortCandidates({enemy,ally},{{type="highest_magic_resistance"}},ctx)[1]==enemy,"highest MR")
-- Soft teammate preference survives the server save/nettable/load boundary.
local teammateArgs={action_kind="ability",action_id="spell",target_team="ally",target_types="hero",
    target_priority_1_type="prefer_teammate",target_priority_2_type="nearest"}
check(service:UpdateRule(0,1,1,teammateArgs),"save teammate priority")
check(payload.target_priority_1_type=="prefer_teammate" and payload.target_priority_2_type=="nearest","serialize teammate priorities")
local teammateRule=service:DecodeFlat(payload)
check(service:ValidateRule(0,caster,teammateRule),"serialized teammate priority remains valid")
check(service:GetHeroRules(caster)[1].target_priorities[1].type=="prefer_teammate","stored teammate priority survives migration")
local fartherAlly=unit(8,2,500)
local preferenceSpec={kind="ability",target_mode="unit",ability={CastFilterResultTarget=function() return 0 end}}
local preferenceCtx={caster=caster,get_candidates=function() return {caster,fartherAlly,ally} end}
local selector=S.new()
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==ally,"prefer closest teammate over zero-distance self")
preferenceCtx.get_candidates=function() return {caster,fartherAlly} end
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==fartherAlly,"any legal teammate outranks self")
preferenceCtx.is_in_range=function(_,target) return target==caster end
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==caster,"out-of-range teammate permits legal self")
preferenceCtx.is_in_range=nil
preferenceSpec.ability.CastFilterResultTarget=function(_,target) return target==caster and 0 or 1 end
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==caster,"native-illegal teammate permits legal self")
preferenceSpec.ability.CastFilterResultTarget=function() return 0 end
fartherAlly.IsAlive=function() return false end
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==caster,"dead teammate permits legal self")
fartherAlly.IsAlive=function() return true end
teammateRule.target_filters={{type="distance_lte",value=100}}
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==caster,"hard-filtered teammate permits legal self")
preferenceCtx.get_candidates=function() return {caster} end
teammateRule.target_filters={{type="exclude_self"}}
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==nil,"preference cannot bypass exclude_self")
teammateRule.target_filters={}
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==caster,"solo legal self fallback")
preferenceSpec.ability.CastFilterResultTarget=function() return 1 end
check(selector:SelectUnit(teammateRule,preferenceSpec,preferenceCtx)==nil,"native-illegal self cannot be fallback")
-- Install the actual bridge with engine/order plumbing stubbed, then exercise
-- the context callbacks and validation handed to the real RuleService.
local filterOptions
package.loaded["tactics/order_filter"]={OrderGate={new=function() return {} end},
    OrderFilter={new=function(options) filterOptions=options; return {Install=function() end} end}}
local engineOptions
package.loaded["tactics/tactic_engine"]={new=function(options)
    engineOptions=options; return {Reset=function() end} end}
package.loaded["issue_fixes.default_rules"]={Normalize=function(rules) return rules end}
local Bridge=require("tactics/tactic_bridge") or TacticBridge
Bridge=TacticBridge
for _, source in ipairs({teammateArgs,{action="spell",target="ally_distance_nearest",target_priorities=teammateRule.target_priorities}}) do
    local converted=Bridge.ConvertLegacyRule(1,source)
    check(converted.target_priorities[1].type=="prefer_teammate" and converted.target_priorities[2].type=="nearest",
        "bridge preserves flat and structured teammate priority order")
end
for _, legacy in ipairs({{"always",0,"always"},{"self_hp_pct_lte",50,"self_hp_pct_lte"},
    {"self_mana_pct_gte",50,"self_mana_pct_gte"},{"alive_enemy_count_gte",2,"alive_enemy_count_gte"},
    {"elapsed_gte",3,"elapsed_gte"},{"self_recently_damaged",2,"self_recently_damaged"},
    {"any_ally_recently_damaged",2,"any_ally_recently_damaged"}}) do
    local converted=Bridge.ConvertLegacyRule(1,{action="attack",condition=legacy[1],value=legacy[2]})
    check(converted.use_conditions[1].type==legacy[3],"legacy "..legacy[1])
    if legacy[2]==50 then check(converted.use_conditions[1].value==.5,"legacy percent migration") end
end
for _,id in ipairs(removedUse) do
    check(#Bridge.ConvertLegacyRule(1,{condition=id,value=1}).use_conditions==0,"removed legacy use stripped "..id)
end
for _,id in ipairs(removedTarget) do
    local converted=Bridge.ConvertLegacyRule(1,{target_filter_1_type=id,target_filter_2_type="is_illusion"})
    check(#converted.target_filters==1 and converted.target_filters[1].type=="is_illusion","removed numbered legacy filter stripped "..id)
end
local bossRule=Bridge.ConvertLegacyRule(1,{target="enemy_boss"})
check(#bossRule.target_filters==0 and bossRule.target_priorities[1].type=="prefer_tag","legacy boss migrates to retained tag priority")
check(Bridge.ConvertLegacyRule(1,{condition="bogus"}).use_conditions[1].type=="bogus","unknown legacy not always")
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_BADGUYS=3;ABILITY_TYPE_ULTIMATE=1
local time=0
GameRules={GetGameTime=function() return time end,GetGameModeEntity=function() return {} end}
CustomGameEventManager={RegisterListener=function() end}
local function ability(name,hidden,passive)
    return {IsNull=function() return false end,GetAbilityName=function() return name end,
        GetAbilityType=function() return 1 end,IsHidden=function() return hidden end,
        IsPassive=function() return passive end,IsActivated=function() return true end,
        GetCurrentAbilityCharges=function() return 2 end}
end
local abilities={ability("hidden",true,false),ability("passive",false,true),ability("native_active",false,false)}
caster.GetAbilityCount=function() return 12 end
caster.GetAbilityByIndex=function(_,index) return index==11 and abilities[3] or abilities[index+1] end
caster.FindAbilityByName=function(_,name) for _,a in ipairs(abilities) do if a:GetAbilityName()==name then return a end end end
caster.GetItemInSlot=function() return nil end
ally.IsAlive=function() return false end
far.IsAlive=function() return false end
local gm={phase="setup",playerId=0,heroData={hero={}},heroRulesByName={},battleManager={
    teamHeroes={[2]={caster,ally},[3]={enemy,far}},teamRules={[3]={}},GetEnemyTeam=function(_,team) return team==2 and 3 or 2 end,
    GetBattleTime=function() return time end,allyDeathCount=99}}
local bridge=Bridge.new({game_mode=gm});bridge:Install()
local real=engineOptions.build_context(caster)
check(real.dead_ally_count==1,"current deaths, not cumulative events")
check(engineOptions.build_context(enemy).dead_ally_count==1,"enemy own-side deaths")
ally.IsAlive=function() return true end
check(engineOptions.build_context(caster).dead_ally_count==0,"revival removes dead count")
check(real.resolve_action_name(caster,"ultimate")=="native_active","first visible active ultimate")
check(real.resolve_action_name(caster,"ability_12")=="native_active","multi-digit slot")
check(real.resolve_action_name(caster,"my_ability_12_suffix")=="my_ability_12_suffix","anchored slot alias")
check(real.resolve_action_name(caster,"native_active")=="native_active","raw identity")
check(real.get_ability_charges(caster,"native_active")==2,"real charge callback")
real.record_action_order(caster,"ultimate")
check(real.get_action_use_count(caster,"native_active")==1,"canonical order count")
check(real.action_used_within(caster,"native_active",1),"real recent order")
time=2;check(not real.action_used_within(caster,"native_active",1),"history window expires")
local valid=bridge.ruleService:DecodeFlat({action_kind="ability",action_id="ultimate",target_team="enemy"})
check(bridge.ruleService:ValidateRule(0,caster,valid) and valid.action.logical_id=="native_active","server canonical identity")
local forged=bridge.ruleService:DecodeFlat({action_kind="ability",action_id="native_active",action_name="hidden"})
check(not bridge.ruleService:ValidateRule(0,caster,forged),"client action name cannot override identity")
-- Actor selectors travel through the actual flat payload, server validator,
-- snapshot and legacy rehydration before the real bridge evaluates them.
local Snapshot=require("tactics/rule_snapshot")
enemy.ruleSnapshotKey="enemy:hero:0";far.ruleSnapshotKey="enemy:hero:1"
gm.currentLevelId="ch05"
local targetKey="ch05:enemy:hero:0"
local targetArgs={action_kind="ability",action_id="native_active",target_team="enemy",
    target_filter_1_type="specified_enemy",target_filter_1_target_actor=targetKey}
local targetRule=bridge.ruleService:DecodeFlat(targetArgs)
check(real.get_target_actor(targetKey)==enemy,"real bridge resolves chapter-qualified on-field target")
check(bridge.ruleService:ValidateRule(0,caster,targetRule),"real service accepts current roster selection")
check(C:EvaluateTargetFilters(targetRule.target_filters,real,enemy),"real bridge callback matches selected enemy")
check(not C:EvaluateTargetFilters(targetRule.target_filters,real,far),"real bridge distinguishes same-name occurrences")
local benchTarget=unit(77,3,0);benchTarget.ruleSnapshotKey="enemy:hero:2"
gm.benchHeroes={benchTarget}
check(real.get_target_actor("ch05:enemy:hero:2")==nil,"bridge excludes bench units")
targetRule.target_filters[1].target_actor="ch05:enemy:hero:2"
check(not bridge.ruleService:ValidateRule(0,caster,targetRule),"real service rejects bench target")
targetRule.target_filters[1].target_actor=targetKey
gm.currentLevelId="ch06"
check(real.get_target_actor(targetKey)==nil and not C:EvaluateTargetFilters(targetRule.target_filters,real,enemy),"existing context reads current chapter dynamically")
check(not bridge.ruleService:ValidateRule(0,caster,targetRule),"real service rejects stale newly submitted selection")
gm.currentLevelId="ch05"
check(real.get_target_actor(targetKey)==enemy,"same chapter retry retains target identity")
local actorKey=Snapshot.HeroKey(gm.battleManager,far)
local actorArgs={action_kind="ability",action_id="native_active",
    use_condition_1_type="action_elapsed_gte",use_condition_1_value=3,
    use_condition_1_action_id="native_active",use_condition_1_action_actor=actorKey,
    use_condition_2_type="action_use_count_lt",use_condition_2_value=2,
    use_condition_2_action_id="native_active",use_condition_2_action_actor=actorKey}
-- A reference must be owned at save time, not injected only after validation.
far.FindAbilityByName=caster.FindAbilityByName
local actorRule=bridge.ruleService:DecodeFlat(actorArgs)
check(bridge.ruleService:ValidateRule(0,caster,actorRule),"actor flat payload validates")
gm.battleManager.getRules=function() return {actorRule} end
local saved=Snapshot.ForHero(gm.battleManager,caster)[1]
check(saved.use_conditions[1].action_actor==actorKey and saved.use_conditions[2].action_actor==actorKey,"snapshot retains both actor selectors")
local restored=Bridge.ConvertLegacyRule(1,saved)
check(bridge.ruleService:ValidateRule(0,caster,restored),"snapshot rehydrates to valid rule")
check(restored.use_conditions[1].action_actor==actorKey,"rehydration preserves duplicate occurrence")
check(bridge.ruleService:UpdateRule(0,1,1,actorArgs),"actor flat update accepted")
check(payload.use_condition_1_action_actor==actorKey and payload.use_condition_2_action_actor==actorKey,"nettable sync preserves actor fields")
check(real.get_action_actor(actorKey)==far and real.get_action_actor("enemy:hero:0")==enemy,"duplicate enemy occurrence resolves separately")
check(real.get_action_actor(Snapshot.HeroKey(gm.battleManager,caster))==caster,"local roster actor resolves")
for _,kind in ipairs({"action_elapsed_gte","action_elapsed_lte","action_use_count_lt","ability_charges_gte"}) do
    check(bridge.ruleService:ValidateCondition({type=kind,value=1,action_id="native_active",action_actor=actorKey},C.use_conditions),"approved actor condition "..kind)
    check(not C:EvaluateUseConditions({{type=kind,value=1,action_id="native_active",action_actor="enemy:missing:0"}},real),"unresolved actor fails closed "..kind)
end
for _,bad in ipairs({{},false,12,"enemy:hero:1!",string.rep("x",257)}) do
    check(not bridge.ruleService:ValidateCondition({type="action_elapsed_gte",value=1,action_id="native_active",action_actor=bad},C.use_conditions),"malformed actor rejected")
end
check(not bridge.ruleService:ValidateCondition({type="action_elapsed_gte",value=1,action_actor=actorKey},C.use_conditions),"actor requires explicit action id")
check(not bridge.ruleService:ValidateCondition({type="always",action_id="native_active",action_actor=actorKey},C.use_conditions),"unapproved actor condition rejected")
local emptyActor={type="action_elapsed_gte",value=1,action_actor=""}
check(bridge.ruleService:ValidateCondition(emptyActor,C.use_conditions) and emptyActor.action_actor==nil,"empty actor normalizes to caster")
far.FindAbilityByName=caster.FindAbilityByName
check(C:EvaluateUseConditions({{type="ability_charges_gte",value=2,action_id="native_active",action_actor=actorKey}},real),"charges observed on selected enemy")
time=10;real.record_action_order(far,"native_active")
time=13;real.record_action_order(caster,"native_active");real.record_action_order(enemy,"native_active")
time=14
check(C:EvaluateUseConditions(restored.use_conditions,real),"selected duplicate elapsed and count differ from local and first enemy")
check(not C:EvaluateUseConditions({{type="action_elapsed_gte",value=3,action_id="native_active"}},real),"nil actor uses local elapsed history")
check(not C:EvaluateUseConditions({{type="action_elapsed_gte",value=3,action_id="native_active",action_actor=""}},real),"empty actor uses local elapsed history")
check(C:EvaluateUseConditions({{type="action_elapsed_lte",value=4,action_id="native_active",action_actor=actorKey}},real),"selected elapsed upper bound")
check(not C:EvaluateUseConditions({{type="action_use_count_lt",value=2,action_id="native_active"}},real),"local count independent of selected duplicate")
real.current_action_id="native_active"
check(not C:EvaluateUseConditions({{type="action_use_count_lt",value=2}},real),"implicit current action retains local history")
check(not C:EvaluateUseConditions({{type="action_elapsed_gte",value=3,action_id="native_active",action_actor=actorKey}},
    {caster=caster,get_action_elapsed=function() return 100 end}),"explicit actor without resolver never falls back to caster")
-- Respawning the same handle retains history and the key; replacing the handle
-- keeps the roster selector but cannot inherit history through its entity index.
far.IsAlive=function() return true end
check(real.get_action_actor(actorKey)==far and real.get_action_elapsed(far,"native_active")==4,"same-handle revival retains actor history")
local replacement=unit(4,3,1000);replacement.ruleSnapshotKey=actorKey
replacement.FindAbilityByName=caster.FindAbilityByName
gm.battleManager.teamHeroes[3]={replacement}
check(Snapshot.HeroKey(gm.battleManager,replacement)==actorKey and real.get_action_actor(actorKey)==replacement,"replacement retains stable duplicate key after first disappears")
check(real.get_action_actor("enemy:hero:0")==nil,"removed hero is no longer selectable")
check(not C:EvaluateUseConditions(restored.use_conditions,real),"replacement cannot inherit old elapsed timer")
check(real.get_action_use_count(replacement,"native_active")==0 and not real.action_used_within(replacement,"native_active",100),"reused index cannot inherit count or recent history")
real.record_action_order(replacement,"native_active")
check(real.get_action_use_count(replacement,"native_active")==1 and real.get_action_use_count(far,"native_active")==1,"new and removed handles keep separate counters")
bridge:ResetState()
check(real.get_action_elapsed(replacement,"native_active")==nil and real.get_action_use_count(replacement,"native_active")==0,"reset clears actor history")
check(not real.action_used_within(caster,"native_active",10),"history reset")
local NativeSuccess=require("tactics/native_events")
NativeSuccess.Attach(caster)
NativeSuccess.Attach(replacement)
local successItem=ability("item_blink",false,false)
local previousItems=caster.GetItemInSlot
caster.GetItemInSlot=function(_,slot) return slot==0 and successItem or nil end
real.current_action_id="native_active"
local chainGate={{type="action_succeeded_after",action_id="item_1",seconds=2}}
real.record_action_order(caster,"item_blink")
check(not C:EvaluateUseConditions(chainGate,real),"real bridge order history cannot unlock success condition")
NativeSuccess.RecordSuccess(caster,"item_blink",time)
check(C:EvaluateUseConditions(chainGate,real),"real bridge resolves item slot prerequisite to native success")
NativeSuccess.RecordSuccess(caster,"native_active",time)
check(not C:EvaluateUseConditions(chainGate,real),"real bridge consumes prerequisite after downstream success")
chainGate[1].action_id="native_active";chainGate[1].action_actor=actorKey
NativeSuccess.RecordSuccess(replacement,"native_active",time)
check(C:EvaluateUseConditions(chainGate,real),"real bridge resolves distinct actor success with equal timestamps")
NativeSuccess.Detach(caster);NativeSuccess.Detach(replacement)
check(not C:EvaluateUseConditions(chainGate,real),"real bridge observes detached cross-actor history")
caster.GetItemInSlot=previousItems
local merged=Bridge.ConvertLegacyRule(1,{action="native_active",condition="always",
    use_condition_4_type="self_hp_pct_lte",use_condition_4_value=.25,
    target_filter_4_type="modifier_stacks_gte",target_filter_4_value=2,target_filter_4_modifier="mark"})
check(merged.use_conditions[1].value==.25 and merged.target_filters[1].modifier=="mark","legacy flat v2 clauses preserve fractions")
local sparse=service:DecodeFlat({action_kind="ability",action_id="spell"})
sparse.use_conditions[4]={type="always"}
check(not service:ValidateRule(0,caster,sparse),"sparse arrays rejected")
spec.ability.CastFilterResultTarget=function() error("native unavailable") end
check(S.new():SelectUnit({target={},target_filters={},target_priorities={}},spec,ctx)==nil,"native filter errors fail closed")
-- Hidden follow-ups are accepted by the real server and retain a distinct
-- identity and cross-stage condition through authoritative snapshots.
for _, pair in ipairs({
    {"dawnbreaker_celestial_hammer", "dawnbreaker_converge"},
    {"phoenix_fire_spirits", "phoenix_launch_fire_spirit"},
}) do
    abilities[#abilities+1] = ability(pair[1],false,false)
    abilities[#abilities+1] = ability(pair[2],true,false)
    local rules = {}
    for index, name in ipairs(pair) do
        local args = {action_kind="ability",action_id=name,target_team="self",
            use_condition_1_type="action_elapsed_gte",use_condition_1_value=index,
            use_condition_1_action_id=pair[1]}
        rules[index] = bridge.ruleService:DecodeFlat(args)
        check(bridge.ruleService:ValidateRule(0,caster,rules[index]), "owned phase validates before native reveal "..name)
    end
    gm.battleManager.getRules = function() return rules end
    local snapshot = Snapshot.ForHero(gm.battleManager,caster)
    for index, name in ipairs(pair) do
        local rehydrated = Bridge.ConvertLegacyRule(index,snapshot[index])
        check(bridge.ruleService:ValidateRule(0,caster,rehydrated), "phase snapshot revalidates "..name)
        check(rehydrated.action.logical_id==name and rehydrated.use_conditions[1].action_id==pair[1]
            and rehydrated.use_conditions[1].value==index, "phase identity and independent condition survive save "..name)
    end
end
abilities[#abilities+1] = ability("ember_spirit_activate_fire_remnant",false,false)
local destinationRule=bridge.ruleService:DecodeFlat({action_kind="ability",action_id="ember_spirit_activate_fire_remnant",
    destination="remnant_safe",cast_preference="point",min_aoe_hits=2,target_team="enemy"})
check(bridge.ruleService:ValidateRule(0,caster,destinationRule),"destination validates on native remnant activation")
gm.battleManager.getRules=function() return {destinationRule} end
local destinationSnapshot=Snapshot.ForHero(gm.battleManager,caster)[1]
local destinationRestored=Bridge.ConvertLegacyRule(1,destinationSnapshot)
check(bridge.ruleService:ValidateRule(0,caster,destinationRestored)
    and destinationRestored.action.destination=="remnant_safe" and destinationRestored.action.cast_preference=="point"
    and destinationRestored.min_aoe_hits==nil and destinationSnapshot.min_aoe_hits==nil,
    "snapshot and legacy restore retain destination and cast choice while discarding hit count")
local controlled=unit(99,2,100)
check(not filterOptions.is_battle_unit(controlled),"unrelated unit is not order-managed")
for _,field in ipairs({"managedSummons","tempestDoubles","specialObjects"}) do
    gm[field]={[controlled]=true}
    check(filterOptions.is_battle_unit(controlled),"native auxiliary unit obeys the battle order lock: "..field)
    gm[field]={}
end
gm.treeGrabBusy={[caster]=true}
local included=false
for _,u in ipairs(engineOptions.get_battle_units()) do if u==caster then included=true end end
check(not included,"native tree cast reserves caster from tactic orders")
gm.treeGrabBusy={}
bridge:RecordAuxiliaryAction(caster,"tiny_tree_grab")
check(real.get_action_use_count(caster,"tiny_tree_grab")==1 and real.get_action_elapsed(caster,"tiny_tree_grab")==0,
    "automatic native tree order participates in action history")
print("condition-v2: "..checks.." checks passed")
