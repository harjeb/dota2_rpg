"""All 439 expression-covered abilities: snapshot-contract matrix, not Dota certification.
Missing and positive mocked native radii exercise compatibility independently of
spell geometry. Native flags/values come from the bundled snapshot.
The real JS serializer, Lua RuleService and JS capability validator must agree.
"""
import collections
import copy
import json
from pathlib import Path
import subprocess
from lua_test_runtime import ROOT, lua_literal, run_lua

BASE = ROOT / 'content/dota_addons/dota2_rpg/panorama/scripts/custom_game'

def first(value):
    if isinstance(value, dict): value=value.get('value', 0)
    try: return float(str(value).split()[0])
    except (ValueError, IndexError): return 0

def run():
    data=json.loads((ROOT/'data/native_skill_conditions.json').read_text(encoding='utf-8'))
    rows=[r for r in data['rows'] if r['expression_covered']]
    assert len(rows)==439
    names=sorted({f for r in data['rows'] for f in r['native']['behavior_flags']})
    behavior={name:2**i for i,name in enumerate(names)}  # distinct flags, including >32 bits
    flags={name:2**i for i,name in enumerate(sorted({f for r in data['rows'] for f in r['native']['target_flags']}|{'DOTA_UNIT_TARGET_FLAG_NOT_SELF'}))}
    other={'DOTA_UNIT_TARGET_HERO':1,'DOTA_UNIT_TARGET_CREEP':2,'DOTA_UNIT_TARGET_BUILDING':4,
           'DOTA_UNIT_TARGET_COURIER':16,'DOTA_UNIT_TARGET_BASIC':18,'DOTA_UNIT_TARGET_TREE':64,
           'DOTA_UNIT_TARGET_CUSTOM':128,'DOTA_UNIT_TARGET_CREEP_HERO':256,'DOTA_UNIT_TARGET_SELF':512,
           'DOTA_UNIT_TARGET_TEAM_FRIENDLY':1,'DOTA_UNIT_TARGET_TEAM_ENEMY':2,
           'DOTA_UNIT_TARGET_TEAM_BOTH':3,'DOTA_UNIT_TARGET_TEAM_CUSTOM':4}
    constants={**behavior,**flags,**other}
    def mask(values):
        if isinstance(values,str): values=[v.strip() for v in values.split('|') if v.strip()]
        m=0
        for name in values: m |= constants[name]
        return m
    fixtures=[]; cases=[]
    for row in rows:
        native=row['native']; definition=native['definition']; values=definition.get('AbilityValues',{})
        fixtures.append({'id':row['id'],'behavior':mask(native['behavior_flags']),'team':mask(native['target_team']),
            'types':mask(native['target_types']),'flags':mask(native['target_flags']),
            'values':{k:first(v) for k,v in values.items()},
            'range':first(native['cast_range']) or first(values.get('AbilityCastRange',0))})
        for scenario,radius in [('radius_missing',0),('radius_positive_mock',400)]:
            key=row['id']+'@'+scenario
            def add(label,rule):
                rule=copy.deepcopy(rule);rule['action']=row['id']
                cases.append({'id':row['id'],'key':key,'scenario':scenario,'label':label,'radius':radius,'rule':rule})
            for variant in row['preset_variants']: add('preset:'+variant,data['families'][variant]['rule'])
            base={'target_team':'enemy','target_types':['hero','monster','summon'],'use_conditions':[], 'target_filters':[], 'target_priorities':[]}
            for team in ['self','ally','enemy']: add('team:'+team,{**base,'target_team':team})
            add('contradiction',{**base,'use_conditions':[{'type':'self_hp_pct_gte','value':80},{'type':'self_hp_pct_lte','value':20}]})
            add('self_excluded',{**base,'target_team':'self','target_filters':[{'type':'exclude_self'}]})
            add('magic_immune',{**base,'target_filters':[{'type':'is_spell_immune'}]})
            for preference in ['unit','point']: add('cast:'+preference,{**base,'cast_preference':preference})
            add('alternate',{**base,'cast_variant':'alternate'})
            add('legacy_hit_count_ignored',{**base,'min_aoe_hits':20})
            add('autocast_off',{**base,'desired_autocast_state':False})
            add('toggle_off',{**base,'desired_toggle_state':False})
    node_serialize=r'''
const fs=require('fs'),vm=require('vm'),path=require('path'); const base=process.argv[1];
const ctx=vm.createContext({console}); ['condition_catalog.js','panorama_rule_sync.js'].forEach(f=>vm.runInContext(fs.readFileSync(path.join(base,f),'utf8'),ctx));
const cases=JSON.parse(fs.readFileSync(0,'utf8'));
for(const c of cases) {
 c.payload=ctx.RpgRuleSync.serialize({rule:c.rule,actionId:c.id,actionName:c.id,heroIndex:7,slot:1});
 if ('min_aoe_hits' in c.payload) throw new Error('Retired hit-count field reached wire: '+c.id);
}
process.stdout.write(JSON.stringify(cases));
'''
    cases=json.loads(subprocess.check_output(['node','-e',node_serialize,str(BASE)],input=json.dumps(cases),text=True,timeout=40))
    source='package.path='+lua_literal((ROOT/'tests/?.lua').as_posix()+';')+'..package.path\nlocal H=require("capability_test_helpers")\n'
    source+='for k,v in pairs('+lua_literal(constants)+') do _G[k]=v end\n'
    source+='local fixtures='+lua_literal(fixtures)+'\nlocal cases='+lua_literal(cases)+'\n'
    source+=r'''
local A=require('tactics/ability_capability');local S=require('tactics/rule_service')
local service=S.new({state={rules={}},get_phase=function() return 'PREPARE' end,is_roster_hero=function() return true end,is_action_allowed=function() return true end})
local by={}; for _,f in ipairs(fixtures) do by[f.id]=f end
local function json(v)
 local kind=type(v)
 if kind=='nil' then return 'null' end
 if kind=='number' or kind=='boolean' then return tostring(v) end
 if kind=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 local out={}; local array=#v>0
 if array then for _,item in ipairs(v) do out[#out+1]=json(item) end
 else for k,item in pairs(v) do out[#out+1]=json(tostring(k))..':'..json(item) end end
 return (array and '[' or '{')..table.concat(out,',')..(array and ']' or '}')
end
local caps={};local result={}
for _,case in ipairs(cases) do
 local f=by[case.id];local hero=H.unit();local a=H.ability(hero,f.id,f.behavior,f.team,f.types,f.flags)
 a.values=f.values;a.range=f.range;a.radius=case.radius
 local action={kind='ability',logical_id=f.id,name=f.id}
 if not caps[case.key] then caps[case.key]=A.ForAction(hero,action) end
 local rule=service:DecodeFlat(case.payload)
 local ok,reason=service:ValidateRule(0,hero,rule)
 if case.label=='contradiction' or case.label=='self_excluded' or case.label=='alternate' then assert(not ok,f.id..':'..case.label) end
 if case.label:sub(1,7)=='preset:' then assert(ok,f.id..':'..case.label..':'..tostring(reason)) end
 result[#result+1]={key=case.key,id=case.id,scenario=case.scenario,label=case.label,rule=case.rule,ok=ok,reason=reason or ''}
end
print(json({caps=caps,results=result}))
'''
    result=json.loads(run_lua(source,timeout=40))
    node_validate=r'''
const fs=require('fs'),vm=require('vm'),path=require('path'),assert=require('assert');
const ctx=vm.createContext({console});vm.runInContext(fs.readFileSync(path.join(process.argv[1],'ability_capabilities.js'),'utf8'),ctx);
const input=JSON.parse(fs.readFileSync(0,'utf8'));let mismatches=[];
for(const r of input.results){const v=ctx.RpgAbilityCapabilities.validate(r.rule,input.caps[r.key],{requireCapability:true});
 if(v.ok!==r.ok) mismatches.push({key:r.key,label:r.label,server:r.reason,client:v.errors});}
process.stdout.write(JSON.stringify(mismatches));
'''
    mismatches=json.loads(subprocess.check_output(['node','-e',node_validate,str(BASE)],input=json.dumps(result),text=True,timeout=40))
    assert not mismatches, json.dumps(mismatches[:20],ensure_ascii=False,indent=2)
    by_case={(r['key'],r['label']):r for r in result['results']}
    for record in result['results']:
        if record['label']=='legacy_hit_count_ignored':
            baseline=by_case[(record['key'],'team:enemy')]
            assert (record['ok'],record['reason'])==(baseline['ok'],baseline['reason']), record
        baseline=by_case[(record['id']+'@radius_missing',record['label'])]
        assert (record['ok'],record['reason'])==(baseline['ok'],baseline['reason']), record
    outcomes=collections.Counter('compatible' if r['ok'] else r['reason'] for r in result['results'])
    per=[]
    for row in rows:
        preset=[r for r in result['results'] if r['id']==row['id'] and r['label'].startswith('preset:')]
        per.append({'id':row['id'],'hero':row['hero'],'family':row['family'],
                    'preset_results':[{k:r[k] for k in ('scenario','label','ok','reason')} for r in preset]})
    report={'scope':'Offline snapshot/native-API contract mocks; no Dota engine execution',
            'abilities':len(rows),'preset_variants':sum(len(r['preset_variants']) for r in rows),
            'matrix_cases':len(cases),'ui_server_mismatches':len(mismatches),'native_execution_validated':0,
            'runtime_scenarios':['GetAOERadius=0 with first-level snapshot specials','synthetic GetAOERadius=400; not a claim about any actual ability'],
            'outcomes':dict(outcomes),'abilities_detail':per}
    dest=ROOT/'tests/results/ability-condition-matrix.json';dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS matrix: %d abilities, %d preset variants, %d cases, zero UI/server mismatches; native execution NOT tested' % (len(rows),report['preset_variants'],len(cases)))
    print(json.dumps(dict(outcomes),sort_keys=True))

if __name__=='__main__': run()
