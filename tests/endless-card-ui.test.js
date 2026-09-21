/* Native Panorama event harness: node tests/endless-card-ui.test.js */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const base = path.join(root, 'content/dota_addons/dota2_rpg_endless/panorama');
const M = require(path.join(base, 'scripts/custom_game/card_forge_model.js'));
assert.equal(M.definitions.length, 100);
assert.deepEqual(M.initial().cards, []);
assert.deepEqual(M.initial().heroes, []);
const panels = {}, subscriptions = {}, sent = [], scheduled = [];
let serial = 0;
function panel(id = '') {
    const p = {id, enabled:true, children:[], events:{}, handlers:{}, classes:new Set(), style:{}, text:'',
        AddClass(c){this.classes.add(c);}, RemoveClass(c){this.classes.delete(c);},
        SetHasClass(c,b){b ? this.classes.add(c) : this.classes.delete(c);},
        SetPanelEvent(e,f){this.events[e]=f;}, SetDraggable(){}, SetFocus(){}, DeleteAsync(){this.deleted=true;},
        RemoveAndDeleteChildren(){this.children.forEach(c=>{c.deleted=true;}); this.children=[];}};
    if (id) panels[id]=p;
    return p;
}
for (const match of fs.readFileSync(path.join(base,'layout/custom_game/card_forge.xml'),'utf8').matchAll(/<\w+\s+id="([^"]+)"[^>]*>/g)) {
    const p=panel(match[1]); if (match[0].includes('CfHidden')) p.AddClass('CfHidden');
}
const $ = selector => panels[selector.slice(1)] || panel(selector.slice(1));
$.CreatePanel = (type,parent,id) => {const p=panel(id || 'generated'+ ++serial); parent.children.push(p); return p;};
$.Localize = key => key;
$.Schedule = (delay, fn) => scheduled.push(fn);
$.RegisterEventHandler = (event,p,fn) => {p.handlers[event]=fn;};
const context = { $, GameUI:{CustomUIConfig:()=>({CardForgeModel:M})},
    Game:{GetLocalPlayerID:()=>0}, GameEvents:{Subscribe:(e,f)=>subscriptions[e]=f,
        SendCustomGameEventToServer:(e,p)=>sent.push({event:e,payload:p})}};
vm.runInNewContext(fs.readFileSync(path.join(base,'scripts/custom_game/card_forge.js'),'utf8'),context);
vm.runInNewContext(fs.readFileSync(path.join(base,'scripts/custom_game/endless_hud.js'),'utf8'),context);
assert(panels.CardForgeOverlay.classes.has('CfHidden'));
assert(!panels.CardForgeEntry.classes.has('CfHidden'));
assert.equal(sent[0].event,'rpg_card_request_state');
const s = {...M.initial(),phase:'prepare',run_id:'run-1',revision:1,wave:1,gold:500,
    cards:[{...M.definitions.find(c=>c.id==='C-g1'),copies:1,level:1,load:1}],
    heroes:[{id:'lina',level:3,faction:'element'}], supported:['C-g1'],offers:['C-g1'],points:{civilization:3}};
const before=JSON.stringify(s);
assert(M.apply(s,{type:'equip',id:'C-g1',slot:'lina:general'}).intent);
assert.equal(JSON.stringify(s),before);
assert(M.apply(s,{type:'return'}).error);
assert(M.apply(s,{type:'exchange',id:'E-g1'}).error);
function receive(state){subscriptions.rpg_card_state({state_json:JSON.stringify(state)});}
function click(id){panels[id].events.onactivate();}
receive(s); click('CardForgeEntry');
assert.equal(panels.CfWallet.text,'◈ 500');
click('CfOffersTab'); click('CfBuy0');
const action=sent.find(e=>e.event==='rpg_card_action').payload;
assert.equal(action.type,'buy'); assert.equal(action.index,0); assert.equal(action.run_id,'run-1');
assert.equal(action.revision,1); assert.equal(action.wave,1); assert(action.request_id);
assert.equal(panels.CfWallet.text,'◈ 500');
assert(panels.CfModal.classes.has('CfHidden'));
receive({...s,gold:400,revision:2}); assert.equal(panels.CfWallet.text,'◈ 400');
// Keep drag source alive on a snapshot, and refuse its stale drop intent.
let source=Object.values(panels).find(p=>p.handlers.DragStart && !p.deleted);
const callback={}; assert(source.handlers.DragStart(source,callback));
const count=sent.filter(e=>e.event==='rpg_card_action').length;
receive({...s,gold:300,revision:3}); assert(!source.deleted);
panels.CfSlot_lina_general.handlers.DragDrop(null,callback.displayPanel);
assert.equal(sent.filter(e=>e.event==='rpg_card_action').length,count);
source.handlers.DragEnd(); assert.equal(panels.CfWallet.text,'◈ 300');
receive({...s,phase:'locked',revision:4}); assert(panels.CardForgeOverlay.classes.has('CfHidden'));
click('CardForgeEntry'); assert(panels.CfCatalogTab.classes.has('CfActive')); assert(!panels.CfConfirm.enabled);
subscriptions.rpg_card_error({message:'server rejected'});
assert.equal(panels.CfNotice.text,'server rejected'); assert.equal(sent.at(-1).event,'rpg_card_request_state');
subscriptions.rpg_endless_state({wave:8,lives:2,max_lives:3,phase:'fight',run_id:'run-1'});
assert(panels.EndlessWave.text.endsWith(' 8')); assert(panels.EndlessLives.text.endsWith(' 2 / 3'));
// Exercise the actual Lua runtime suites, not a JS reimplementation of combat.
for (const file of ['endless-mode.test.lua','endless-card-effects.test.lua']) {
    const result=spawnSync(process.env.LUA || 'lua',[path.join('tests',file)],{cwd:root,encoding:'utf8'});
    assert.equal(result.status,0,result.error?.message || result.stdout + result.stderr);
}
// Round-trip real Lua ownership, zero-based purchases and confirm through the JS decoder.
const contract = spawnSync(process.env.LUA || 'lua', ['-'], {cwd:root,encoding:'utf8',input:`
package.path='game/dota_addons/dota2_rpg_endless/scripts/vscripts/?.lua;'..package.path
local Cards=require('endless.cards')
local Json=require('lib.json')
local game={endlessRunId=42,endlessWave=1,phase='setup',playerId=0,lineup={'npc_dota_hero_lina'},heroData={},gold=500}
function game:GetGoldBalance() return self.gold end
function game:SpendGold(n) if self.gold<n then return false end self.gold=self.gold-n return true end
function game:OnStartBattle() self.phase='fight' end
local initial=Cards.Snapshot(game)
local buy={run_id=initial.run_id,revision=initial.revision,wave=initial.wave,type='buy',index=0,request_id='native-test-1'}
assert(Cards.Apply(game,buy)==nil)
local bought=Cards.Snapshot(game)
assert(bought.gold==400 and bought.bought[1]==0 and bought.revision>initial.revision)
assert(Cards.Apply(game,buy)~=nil)
assert(Cards.Apply(game,{run_id=bought.run_id,revision=bought.revision,wave=bought.wave,type='confirm'})==nil)
print(Json.encode({initial=initial,bought=bought,locked=Cards.Snapshot(game)}))
`});
assert.equal(contract.status,0,contract.error?.message || contract.stdout+contract.stderr);
const actual=JSON.parse(contract.stdout);
assert.equal(M.snapshot({state_json:JSON.stringify(actual.initial)}).heroes[0].id,'lina');
receive(actual.bought); assert.equal(panels.CfWallet.text,'◈ 400');
receive(actual.locked); assert(panels.CardForgeOverlay.classes.has('CfHidden'));
console.log('endless card UI: authoritative events, recovery, drag revisions, real Lua state/actions/mode/effects passed');
