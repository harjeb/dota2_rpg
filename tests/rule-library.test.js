'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('content/dota_addons/dota2_rpg/panorama/scripts/custom_game/rule_library.js', 'utf8');
const KEY = 'dota2_rpg_rule_library_v1';
const AXE = 'npc_dota_hero_axe', LION = 'npc_dota_hero_lion';
function boot(store = {}, options = {}) {
    const context = vm.createContext(options.absent ? {} : {$:{LocalStorage:{
        GetItem(key) { if (options.readFail) throw Error('read denied'); return store[key]; },
        SetItem(key, value) { if (options.writeFail) throw Error('quota exceeded'); store[key] = value; }
    }}});
    vm.runInContext(source, context);
    const lib = context.RpgRuleLibrary;
    // Actual Panorama callers share the library's JavaScript realm.
    return {lib, track(id, hero, rules, slot = 1) {
        context.input = JSON.stringify({id,hero,rules,slot});
        vm.runInContext('var arg=JSON.parse(input); RpgRuleLibrary.track(arg.id,arg.hero,arg.rules,arg.slot);', context);
    }, context};
}
function rule(action = 'attack') { return {action,enabled:true}; }
function text(heroes) { return JSON.stringify({format:'dota2_rpg_rule_library',version:1,heroes}); }
function get(lib, hero) { return JSON.parse(JSON.stringify(lib.get(hero))); }
function ack(lib, id, ok = 1) { lib.result({request_id:id,ok}); }
{
    const store = {}, {lib,track} = boot(store);
    const nested = [{...rule('item_blink'),forced:false,desired_toggle_state:null,
        use_conditions:[{type:'hp_pct_below',value:35,custom:{list:['a',false,2,null]}}],
        target_filters:[{type:'specified_ally',target_actor:'ally:lion:1'}],target_priorities:[{type:'nearest'}],
        movement_loop:true,cast_variant:'point',state_mana_off:12}];
    track(1, AXE, nested); nested[0].action = 'buyback';
    assert.equal(lib.hasPending(),true); assert.equal(lib.get(AXE),null);
    ack(lib,1); assert.equal(lib.hasPending(),false);
    const expected = {...nested[0],action:'item_blink'};
    assert.deepEqual(get(lib,AXE),[expected]);
    const returned = lib.get(AXE); returned[0].target_filters[0].target_actor = 'mutated';
    assert.equal(get(lib,AXE)[0].target_filters[0].target_actor,'ally:lion:1');
    track(2,LION,[rule('lion_impale')]); ack(lib,2);
    assert.equal(lib.count(),2); assert.equal(boot(store).lib.count(),2);
    assert.deepEqual(get(boot(store).lib,AXE),[expected]);
    assert.ok(lib.exportText().includes('\n  "format"'));
    assert.deepEqual(JSON.parse(store[KEY]),JSON.parse(lib.exportText()));
}
{
    const store = {}, {lib,track} = boot(store);
    lib.importText(text({[AXE]:[rule()]})); const backup = store[KEY];
    track('a',AXE,[rule('buyback'),rule()],1);
    track('b',AXE,[rule('buyback'),rule('sustained_move')],2);
    ack(lib,'a'); assert.equal(store[KEY],backup);
    ack(lib,'b',0); assert.equal(store[KEY],backup); assert.equal(lib.hasPending(AXE),true);
    track('c',AXE,[rule('basic_attack'),rule('sustained_move')],1); ack(lib,'c');
    assert.equal(store[KEY],backup,'other slots cannot clear a rejection');
    track('d',AXE,[rule('basic_attack'),rule('lion_impale')],2); ack(lib,'d');
    assert.equal(lib.hasPending(AXE),false); assert.equal(get(lib,AXE)[1].action,'lion_impale');
    track('old',AXE,[rule('buyback')]); track('new',AXE,[rule('sustained_move')]);
    ack(lib,'old',0); assert.equal(lib.hasPending(),true);
    ack(lib,'new'); ack(lib,'old'); assert.equal(get(lib,AXE)[0].action,'sustained_move');
    track('removed',AXE,[rule('sustained_move'),rule('buyback')],2); ack(lib,'removed',0);
    track('shrink',AXE,[rule('sustained_move')],1); ack(lib,'shrink');
    assert.equal(lib.hasPending(),false,'deleting a rejected row unblocks saving');
    assert.equal(get(lib,AXE).length,1);
    track('late',AXE,[rule('buyback')]); lib.resetPending(); ack(lib,'late');
    assert.equal(lib.hasPending(),false); assert.equal(get(lib,AXE)[0].action,'sustained_move');
}
{
    const store = {}, {lib} = boot(store), events = [];
    const unsubscribe = lib.subscribe(type => events.push(type));
    assert.equal(lib.importText(text({[AXE]:[rule()]})),1);
    assert.equal(lib.importText(text({[LION]:[rule('lion_impale')]})),1);
    assert.equal(lib.count(),2); assert.equal(lib.revision(),2);
    assert.deepEqual(events,['import','import']); unsubscribe();
    lib.importText(text({[AXE]:[rule('buyback')]}));
    assert.equal(get(lib,LION)[0].action,'lion_impale'); assert.equal(events.length,2);
    const before = lib.exportText(), saved = store[KEY];
    const bad = [
        '{', JSON.stringify({format:'dota2_rpg_rule_library',version:2,heroes:{}}),
        text({bad:[rule()]}), text({[AXE]:[]}), text({[AXE]:Array(33).fill(rule())}),
        text({[AXE]:[{action:23}]}), text({[AXE]:[{action:'123'}]}),text({[AXE]:[{action:'attack',enabled:1}]}),
        text({[AXE]:[{...rule(),target_filters:[null]}]}),
        text({[AXE]:[{...rule(),use_conditions:Array(5).fill({type:'always'})}]}),
        text({[AXE]:[{...rule(),target_filters:Array(5).fill({type:'always'})}]}),
        text({[AXE]:[{...rule(),target_priorities:Array(3).fill({type:'nearest'})}]}),
        text({[AXE]:[{...rule(),target_filters:{type:'always'}}]}),
        text({[AXE]:[{...rule(),target_filters:[{type:'specified_ally',target_actor:123}]}]}),
        text({[AXE]:[{...rule(),entity_index:123}]}),
        text({[AXE]:[{...rule(),custom:'x'.repeat(8193)}]}),
        text({[AXE]:[{...rule(),custom:JSON.parse('{"__proto__":{"x":1}}')}]}),
        text({[AXE]:[{...rule(),custom:{constructor:'bad'}}]}),
        text(Object.fromEntries(Array.from({length:201},(_,i)=>['npc_dota_hero_h'+i,[rule()]]))),
        ' '.repeat(2*1024*1024+1)
    ];
    let deep = {}; for(let i=0;i<18;i++) deep={nested:deep};
    bad.push(text({[AXE]:[{...rule(),deep}]}));
    for(const input of bad) {
        assert.throws(()=>lib.importText(input));
        assert.equal(lib.exportText(),before); assert.equal(store[KEY],saved);
    }
    assert.throws(()=>lib.importText(text({[AXE]:[rule('buyback')],[LION]:[{action:null}]})));
    assert.equal(lib.exportText(),before,'validation cannot partially import first valid hero');
}
{
    const store = {}, options = {}, {lib,track} = boot(store,options);
    lib.importText(text({[AXE]:[rule()]})); const before = lib.exportText(), persisted = store[KEY];
    options.writeFail = true;
    assert.throws(()=>lib.importText(text({[LION]:[rule()]})),/not saved/);
    assert.equal(lib.exportText(),before); assert.match(lib.status(),/quota/);
    track(1,AXE,[rule('buyback')]); ack(lib,1);
    assert.equal(get(lib,AXE)[0].action,'buyback'); assert.equal(store[KEY],persisted);
    assert.match(lib.status(),/quota/);
    options.writeFail = false; track(2,LION,[rule()]); ack(lib,2);
    assert.equal(lib.status(),''); assert.equal(boot(store).lib.count(),2);
}
{
    const {lib,track,context} = boot({}, {absent:true});
    assert.match(lib.status(),/unavailable/); track(1,AXE,[rule()]); ack(lib,1);
    assert.equal(lib.count(),1); assert.throws(()=>lib.importText(text({[LION]:[rule()]})),/not saved/);
    assert.equal(lib.count(),1);
    assert.throws(()=>vm.runInContext('RpgRuleLibrary.track(2,"'+AXE+'",[{action:"attack",custom:new Date()}],1)',context),/plain/);
    assert.throws(()=>vm.runInContext('var cyc={action:"attack"};cyc.cycle=cyc;RpgRuleLibrary.track(3,"'+AXE+'",[cyc],1)',context),/depth/);
    assert.match(boot({}, {readFail:true}).lib.status(),/read denied/);
    assert.match(boot({[KEY]:'invalid'}).lib.status(),/invalid JSON/);
}
{
    const {lib,track} = boot();
    track(1,AXE,[rule()]);
    assert.throws(()=>lib.importText(text({[LION]:[rule()]})),/await acknowledgement/);
    ack(lib,1,0);
    lib.importText(text({[LION]:[rule()]}));
    assert.equal(lib.hasPending(AXE),true); assert.equal(lib.revision(AXE),0); assert.equal(lib.revision(LION),1);
    lib.importText(text({[AXE]:[rule('buyback')]}));
    assert.equal(lib.hasPending(),false); assert.equal(lib.revision(AXE),1); assert.equal(lib.revision(),2);
    for (const action of ['item_1','ability_1','ultimate']) assert.throws(()=>lib.importText(text({[AXE]:[rule(action)]})),/stable/);
    const nodeHeavy = Object.fromEntries(Array.from({length:110},(_,i)=>['field'+i,Array(1000).fill(null)]));
    assert.throws(()=>lib.importText(text({[AXE]:[{...rule(),extra:nodeHeavy}]})),/node limit/);
    const unicodeHeavy = Object.fromEntries(Array.from({length:100},(_,i)=>['field'+i,'界'.repeat(8000)]));
    assert.throws(()=>lib.importText(text({[AXE]:[{...rule(),extra:unicodeHeavy}]})),/2MB/);
}
console.log('rule-library: persistence, atomic merge, bounded validation, ACK races and storage failures passed');
