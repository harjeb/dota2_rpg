"use strict";
// Catalog contract retained separately from the live server/UI integration suite.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const base=path.join(root,'content/dota_addons/dota2_rpg_endless/panorama');
const M=require(path.join(base,'scripts/custom_game/card_forge_model.js'));
execFileSync('python',[path.join(root,'scripts/build-native-card-data.py'),'--check']);
assert.equal(M.definitions.length,100);
for(const [type,n] of [['buff',45],['charge',35],['field',20]])assert.equal(M.definitions.filter(c=>c.type===type).length,n);
assert.equal(M.definitions.find(c=>c.id==='C-g1').name,'冲锋号角');
assert.equal(M.initial().cards.length,0,'no invented ownership before synchronization');
assert.equal(M.initial().heroes.length,0);
const dictionaries={};
for(const lang of ['schinese','english']){
 const text=fs.readFileSync(path.join(root,'game/dota_addons/dota2_rpg_endless/resource/addon_'+lang+'.txt'),'utf8');
 dictionaries[lang]=Object.fromEntries([...text.matchAll(/"((?:cf_|endless_)[^"]+)"\s+"([^"]*)"/g)].map(m=>[m[1],m[2]]));
 assert(text.includes(lang==='english'?'"UI version 101"':'"界面版本 101"'));
 for(const card of M.definitions)assert(dictionaries[lang]['cf_card_'+card.id.replace(/-/g,'_')]);
}
assert.deepEqual(Object.keys(dictionaries.english).sort(),Object.keys(dictionaries.schinese).sort());
const css=fs.readFileSync(path.join(base,'styles/custom_game/card_forge.css'),'utf8');
assert(!/display\s*:\s*(grid|flex)|var\(--|:root|@media|line-height\s*:/.test(css));
const source=fs.readFileSync(path.join(base,'scripts/custom_game/card_forge.js'),'utf8');
assert(!/document\.|window\.|localStorage|dataTransfer/.test(source));
const manifest=fs.readFileSync(path.join(base,'layout/custom_game/custom_ui_manifest.xml'),'utf8');
for(const f of ['card_forge.xml','rpg_demo_hud.xml','issue_fixes_ui.xml'])assert(manifest.includes(f));
console.log('PASS current 100-card catalog, native source contracts, empty initial state, UI101 locale parity');
