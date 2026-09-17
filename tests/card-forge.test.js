"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {execFileSync} = require("node:child_process");
const root = path.resolve(__dirname, "..");
const base = path.join(root, "content/dota_addons/dota2_rpg_endless/panorama");
const modelPath = path.join(base, "scripts/custom_game/card_forge_model.js");
const source = fs.readFileSync(path.join(base, "scripts/custom_game/card_forge.js"), "utf8");
const M = require(modelPath);
function mutate(s, a) { const result=M.apply(s,a); assert(!result.error,result.error); return result.state; }

let s=M.initial();
assert.equal(M.inventory(s).length,16);
assert.equal(M.used(s),19);
const original=JSON.stringify(s);
assert(M.apply(s,{type:"equip",id:"H-lina",slot:"kunkka:hero"}).error);
assert(M.apply(s,{type:"equip",id:"H-lina",slot:"lina:general"}).error);
assert.equal(JSON.stringify(s),original,"invalid actions are atomic");
s=mutate(s,{type:"equip",id:"H-lina",slot:"lina:hero"});
assert.equal(M.inventory(s).length,15,"equipped cards use no inventory capacity");
s=mutate(s,{type:"equip",id:"E-g1",slot:"lina:general"});
s=mutate(s,{type:"equip",id:"E-g1",slot:"kunkka:general"});
assert.equal(s.slots["lina:general"],undefined);
assert.equal(Object.values(s.slots).filter(id=>id==="E-g1").length,1);
s=mutate(s,{type:"equip",id:"E-g2",slot:"kunkka:general"});
assert(!M.location(s,"E-g1"),"displaced card returns to library");
assert(M.apply(s,{type:"level",id:"E-g2",level:3}).error);
assert(M.apply(s,{type:"level",id:"E-g2",level:1.5}).error);
s=mutate(s,{type:"level",id:"E-g2",level:2});
const load=M.get(s,"E-g2").load;
s.points.element=3;
s=mutate(s,{type:"exchange",id:"E-g2"});
assert.equal(M.get(s,"E-g2").level,3);
assert.equal(M.get(s,"E-g2").load,load,"duplicates preserve load level");
assert(M.apply(s,{type:"smelt",id:"E-g2"}).error);
assert(M.apply(s,{type:"smelt",id:"H-lina"}).error);
s=mutate(s,{type:"unequip",id:"H-lina"});
s=mutate(s,{type:"smelt",id:"H-lina"});
assert.equal(M.get(s,"H-lina").level,2);
assert.equal(s.points.element,1);
s=mutate(s,{type:"smelt",id:"H-kunkka"});
assert.equal(M.get(s,"H-kunkka"),undefined,"last smelted copy removes asset");
let full=M.initial();
while(M.inventory(full).length<24)full.cards.push({...full.cards[0],id:"filler-"+full.cards.length});
assert(M.apply(full,{type:"unequip",id:"H-cm"}).error);
const beforeFull=JSON.stringify(full);
assert(M.apply(full,{type:"equip",id:"C-g2",slot:"nevermore:general"}).error);
assert.equal(JSON.stringify(full),beforeFull,"full library replacement preserves all assets");
full=mutate(full,{type:"equip",id:"E-g1",slot:"nevermore:general"});
assert.equal(M.inventory(full).length,24,"inventory-to-slot replacement exchanges occupied space");
let purchases=M.initial();
for(const index of [0,1,2])purchases=mutate(purchases,{type:"buy",index});
assert.equal(purchases.purchases,3);assert.equal(purchases.gold,900);
assert(M.apply(purchases,{type:"buy",index:3}).error);
assert(M.apply(purchases,{type:"buy",index:0}).error);
assert.equal(M.get(purchases,"E-g1").plus,1);
let over=M.initial();over.heroes.forEach(h=>h.level=1);
assert(M.apply(over,{type:"confirm"}).error);
let locked=mutate(M.initial(),{type:"confirm"});
for(const action of [{type:"equip",id:"H-lina",slot:"lina:hero"},{type:"level",id:"E-g1",level:2},{type:"buy",index:0},{type:"smelt",id:"H-lina"}])assert(M.apply(locked,action).error);

const tree=JSON.parse(execFileSync("python",["-c","import json,sys,xml.etree.ElementTree as E; f=lambda n:dict(tag=n.tag,attrs=n.attrib,children=[f(c) for c in n]); print(json.dumps(f(E.parse(sys.argv[1]).getroot())))",path.join(base,"layout/custom_game/card_forge.xml")],{encoding:"utf8"}));
const dictionaries={};
for(const lang of ["schinese","english"]){
    const locale=fs.readFileSync(path.join(root,"game/dota_addons/dota2_rpg_endless/resource/addon_"+lang+".txt"),"utf8");
    dictionaries[lang]=Object.fromEntries([...locale.matchAll(/"(cf_[^"]+)"\s+"([^"]*)"/g)].map(m=>["#"+m[1],m[2]]));
    assert(locale.includes(lang==="english"?'"UI version 98"':'"界面版本 98"'));
}
assert.deepEqual(Object.keys(dictionaries.schinese).sort(),Object.keys(dictionaries.english).sort());
function launch(lang){
    const ids={},subscriptions={},commands={},scheduled=[],missing=[];
    class Panel{
        constructor(type,parent,id="") {this.type=type;this.parent=parent;this.id=id;this.children=[];this.classes=new Set();this.events={};this.handlers={};this.enabled=true;this.text="";this.style={};this.alive=true;if(parent)parent.children.push(this);if(id)ids[id]=this;}
        AddClass(c){this.classes.add(c);}RemoveClass(c){this.classes.delete(c);}SetHasClass(c,v){v?this.AddClass(c):this.RemoveClass(c);}BHasClass(c){return this.classes.has(c);}
        SetPanelEvent(e,fn){this.events[e]=fn;}SetDraggable(v){this.draggable=v;}SetFocus(){this.focused=true;}
        RemoveAndDeleteChildren(){for(const c of this.children)c.destroy();this.children=[];}
        destroy(){this.alive=false;for(const c of this.children)c.destroy();if(ids[this.id]===this)delete ids[this.id];}
        DeleteAsync(){this.destroy();if(this.parent)this.parent.children=this.parent.children.filter(c=>c!==this);}
        FindChildTraverse(id){return this.children.find(c=>c.id===id)||this.children.map(c=>c.FindChildTraverse(id)).find(Boolean);}
    }
    const global=new Panel("Panel",null,"TestRoot");
    function attach(n,parent){if(n.tag==="styles"||n.tag==="scripts")return;const p=new Panel(n.tag,parent,n.attrs.id);for(const c of (n.attrs.class||"").split(" ").filter(Boolean))p.AddClass(c);if(n.attrs.text)p.text=n.attrs.text;for(const child of n.children)attach(child,p);}
    tree.children.filter(n=>n.tag==="Panel").forEach(n=>attach(n,global));
    const $=selector=>ids[selector.replace(/^#/,"")];
    $.CreatePanel=(type,parent,id)=>new Panel(type,parent,id);
    $.Localize=key=>{if(dictionaries[lang][key])return dictionaries[lang][key];if(key.startsWith("#npc_dota_hero_"))return key.slice(1);missing.push(key);return key;};
    $.RegisterEventHandler=(name,p,fn)=>{p.handlers[name]=fn;};
    $.Schedule=(delay,fn)=>{scheduled.push(fn);};
    const config={};
    const context=vm.createContext({$,GameUI:{CustomUIConfig:()=>config},Game:{AddCommand:(name,fn)=>commands[name]=fn},Players:{GetLocalPlayer:()=>0},GameEvents:{Subscribe:(name,fn)=>subscriptions[name]=fn,SendCustomGameEventToServer:()=>{throw Error("Preview must never send gameplay mutations");}},console});
    vm.runInContext(fs.readFileSync(modelPath,"utf8"),context);vm.runInContext(source,context);
    const click=id=>{const p=ids[id];assert(p,"Missing panel "+id);assert(p.enabled,"Disabled panel "+id);p.events.onactivate();};
    function all(p=global){return [p,...p.children.flatMap(c=>all(c))];}
    function card(id){const name=dictionaries[lang]["#cf_card_"+id.replace(/-/g,"_")];return all(ids.CfGrid).find(p=>p.classes.has("CfCard")&&all(p).some(c=>c.text===name));}
    return {ids,subscriptions,commands,click,card,all,missing,flush:()=>{while(scheduled.length)scheduled.shift()();}};
}
for(const lang of ["schinese","english"]){
    const ui=launch(lang);
    assert(!ui.ids.CardForgeEntry.BHasClass("CfHidden"));
    assert.equal(Object.keys(ui.subscriptions).length,0,"isolated gallery has no dependency on campaign state");
    ui.click("CardForgeEntry");assert(!ui.ids.CardForgeOverlay.BHasClass("CfHidden"));
    assert.equal(ui.ids.CfCapacity.text,"16 / 24");
    // Native drag lifecycle: source must stay alive until DragEnd.
    let source=ui.card("H-lina"),callback={};assert(source.handlers.DragStart(source,callback));
    let wrong=ui.ids.CfSlot_kunkka_hero;
    assert.equal(wrong.handlers.DragEnter(wrong,callback.displayPanel),false);
    assert.equal(wrong.handlers.DragDrop(wrong,callback.displayPanel),false);
    source.handlers.DragEnd();assert.equal(ui.ids.CfCapacity.text,"16 / 24");
    source=ui.card("H-lina");callback={};source.handlers.DragStart(source,callback);
    let dest=ui.ids.CfSlot_lina_hero;assert(dest.handlers.DragEnter(dest,callback.displayPanel));
    assert(dest.handlers.DragDrop(dest,callback.displayPanel));assert(source.alive,"no render may destroy native drag source before DragEnd");
    source.handlers.DragEnd();assert.equal(ui.ids.CfCapacity.text,"15 / 24");assert(!callback.displayPanel.alive,"drag ghost cleaned up");
    ui.click("CfUndo");assert.equal(ui.ids.CfCapacity.text,"16 / 24");
    ui.card("H-lina").events.onactivate();ui.click("CfSlot_lina_hero");assert.equal(ui.ids.CfCapacity.text,"15 / 24");
    ui.click("CfLevel3");assert.equal(ui.ids.CfCost.text,"COST  34 / 64");
    source=ui.ids.CfSlot_lina_hero;callback={};source.handlers.DragStart(source,callback);
    dest=ui.ids.CfInventory;assert(dest.handlers.DragDrop(dest,callback.displayPanel));source.handlers.DragEnd();assert.equal(ui.ids.CfCapacity.text,"16 / 24");
    // Blank-space cancellation is DragEnd without DragDrop.
    source=ui.card("H-lina");callback={};source.handlers.DragStart(source,callback);source.handlers.DragEnd();assert.equal(ui.ids.CfCapacity.text,"16 / 24");
    ui.ids.CfSearch.text="unmatched-asset";ui.ids.CfSearch.events.ontextentrychange();assert(ui.ids.CfGrid.children.length===0);assert(!ui.ids.CfEmpty.BHasClass("CfHidden"));
    ui.ids.CfSearch.text="";ui.ids.CfSearch.events.ontextentrychange();
    ui.click("CfOffersTab");
    const before=ui.all(ui.ids.CfModalContent).map(p=>p.text).join("|");
    assert(!before.includes(dictionaries[lang]["#cf_card_E_g1"]),"hidden offers must not leak card names");
    for(const i of [0,1,2])ui.click("CfBuy"+i);
    assert(!ui.ids.CfBuy3.enabled);assert.equal(ui.ids.CfWallet.text,"◈ 900");
    ui.click("CfModalClose");ui.card("H-lina").events.onactivate();ui.click("CfDetailSmelt");
    assert(ui.ids.CfSmeltConfirm.enabled);ui.click("CfSmeltConfirm");assert(ui.ids.CfModalContent.children.length>0);
    ui.click("CfModalClose");ui.click("CfConfirm");assert(!ui.ids.CfConfirm.enabled);ui.click("CfReturn");assert(ui.ids.CfConfirm.enabled);
    ui.click("CfHelp");ui.click("CfModalClose");
    source=ui.card("H-lina");callback={};source.handlers.DragStart(source,callback);
    ui.click("CfClose");
    assert(ui.ids.CardForgeOverlay.BHasClass("CfHidden"));
    dest=ui.ids.CfSlot_lina_hero;assert.equal(dest.handlers.DragDrop(dest,callback.displayPanel),false,"closing mid-drag blocks stale drop");source.handlers.DragEnd();
    assert.deepEqual(ui.missing,[],"all visible native text is localized");
}
const css=fs.readFileSync(path.join(base,"styles/custom_game/card_forge.css"),"utf8");
assert(!/display\s*:\s*(grid|flex)|var\(--|:root|@media/.test(css),"native styles must not rely on browser layout");
assert(!/document\.|window\.|localStorage|dataTransfer/.test(source),"native controller must not use browser APIs");
assert(fs.readFileSync(path.join(base,"layout/custom_game/custom_ui_manifest.xml"),"utf8").includes("card_forge.xml"));
console.log("PASS card model transactions, native drag lifecycle, click fallback, inventory, purchases, smelting, gallery isolation, confirmation and both locales");
