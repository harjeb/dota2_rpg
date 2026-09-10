"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const {execFileSync} = require("child_process");
const root = path.resolve(__dirname, ".."), panorama = path.join(root, "content/dota_addons/dota2_rpg/panorama");
const xmlPath = path.join(panorama, "layout/custom_game/rpg_demo_hud.xml");
const tree = JSON.parse(execFileSync("python", ["-c", "import json,sys,xml.etree.ElementTree as E; f=lambda e:dict(type=e.tag,attrs=e.attrib,children=[f(c) for c in e]); print(json.dumps(f(E.parse(sys.argv[1]).getroot())))", xmlPath], {encoding:"utf8"}));
const source = fs.readFileSync(path.join(panorama, "scripts/custom_game/skill_debug.js"), "utf8");
const xml = fs.readFileSync(xmlPath, "utf8"), css = fs.readFileSync(path.join(panorama, "styles/custom_game/skill_debug.css"), "utf8");
const nativeInventory = fs.readFileSync(path.join(root,"data/native_skill_conditions.json"),"utf8");
const debugCatalog = fs.readFileSync(path.join(root,"game/dota_addons/dota2_rpg/scripts/data/debug_heroes.kv"),"utf8");
const heroNames = text => [...new Set(text.match(/npc_dota_hero_[a-z0-9_]+/g))].sort();
assert.deepStrictEqual(heroNames(debugCatalog),heroNames(nativeInventory),"debug chooser includes every hero in the native skill inventory, including recruitment exclusions");
assert(xml.includes("skill_debug.js") && xml.includes("skill_debug.css"));
assert(/#SkillDebug\s*\{[^}]*z-index:\s*2100/.test(css), "dialog covers existing help and action menus");
function launch(language) {
    const ids = {}, sent = [], handlers = {};
    function panel(type, parent, id, attrs = {}) {
        const p = {id, type, parent, children:[], text:attrs.text || "", enabled:true,
            classes:new Set((attrs.class || "").split(/\s+/).filter(Boolean)), events:{},
            AddClass(c) {this.classes.add(c);}, RemoveClass(c) {this.classes.delete(c);}, BHasClass(c) {return this.classes.has(c);},
            SetHasClass(c, yes) {yes ? this.AddClass(c) : this.RemoveClass(c);}, SetPanelEvent(e, fn) {this.events[e] = fn;},
            RemoveAndDeleteChildren() { const erase = c => {if(c.id) delete ids[c.id]; c.children.forEach(erase);}; this.children.forEach(erase); this.children=[]; },
            SetFocus() {this.focused=true;}, ScrollToTop() {this.scrolled=true;}
        };
        if(id) ids[id]=p; if(parent) parent.children.push(p); return p;
    }
    function build(n, parent) {const p=panel(n.type,parent,n.attrs.id || "",n.attrs); n.children.forEach(c=>build(c,p)); return p;}
    build(tree,null);
    const $ = q => ids[q.slice(1)] || null;
    $.CreatePanel=panel; $.Language=()=>language;
    $.Localize=token=>({"#npc_dota_hero_axe":"斧王 Axe", "#npc_dota_hero_phantom_assassin":"幻影刺客 PA", "#npc_dota_hero_wisp":"艾欧 Io"}[token] || token);
    vm.runInNewContext(source, {$,GameEvents:{Subscribe:(e,fn)=>handlers[e]=fn,
        SendCustomGameEventToServer:(e,data)=>sent.push([e,JSON.parse(JSON.stringify(data))])}});
    return {ids,sent,click(id) {ids[id].events.onactivate();}, event(e,data) {handlers[e](data);},
        type(id,text) {ids[id].text=text; ids[id].events.ontextentrychange();}};
}
const HERO="npc_dota_hero_axe", PA="npc_dota_hero_phantom_assassin";
for (const language of ["schinese", "english"]) {
    const ui=launch(language), p=ui.ids;
    assert(p.SkillDebug.BHasClass("Hidden"));
    assert.deepStrictEqual(ui.sent, [["rpg_debug_request",{}]], "loading the UI only requests read-only state");
    ui.click("SkillDebugButton"); assert(!p.SkillDebug.BHasClass("Hidden"));
    ui.click("SkillDebugStart"); assert(!p.SkillDebugStart.enabled && ui.sent.length===2);
    ui.event("rpg_debug_state", {active:0,pending:0,phase:"setup",hero:"",attack_damage:100,heroes_text:[HERO,PA,HERO,"npc_dota_hero_wisp"].join(";")});
    assert(p.SkillDebugHeroes.children.length===3, "catalog deduplicates server entries");
    ui.type("SkillDebugSearch","幻影刺客"); assert(p.SkillDebugHeroes.children.length===1);
    ui.type("SkillDebugSearch","missing_hero_999"); assert(p.SkillDebugHeroes.children[0].type==="Label");
    ui.type("SkillDebugSearch",""); ui.click("DebugHero_"+HERO);
    assert(p.SkillDebugSelected.text.includes("斧王") && p.SkillDebugSelected.text.includes("30"));
    const before=ui.sent.length;
    for (const value of ["", "-1", "1.5", "10001", "Infinity", "NaN", "0x10"]) {
        ui.type("SkillDebugDamage",value); ui.click("SkillDebugStart"); assert(ui.sent.length===before && p.SkillDebugError.text);
    }
    ui.type("SkillDebugDamage","0"); ui.click("SkillDebugStart");
    assert.deepStrictEqual(ui.sent.at(-1),["rpg_debug_start",{hero:HERO,attack_damage:0}]);
    assert(!p.SkillDebugStart.enabled, "a pending request cannot be double clicked");
    ui.event("rpg_debug_state",{active:0,pending:1,phase:"setup"});
    assert(p.SkillDebugExit.enabled, "loading can be cancelled");
    ui.click("SkillDebugExit"); assert.deepStrictEqual(ui.sent.at(-1),["rpg_debug_exit",{}]);
    ui.event("rpg_debug_state",{active:0,pending:0,hero:"",phase:"setup"});
    assert(p.SkillDebug.BHasClass("Hidden"), "confirmed cancellation closes the dialog");
    ui.click("SkillDebugButton"); ui.click("DebugHero_"+PA);
    ui.type("SkillDebugDamage","10000"); ui.click("SkillDebugStart");
    assert.deepStrictEqual(ui.sent.at(-1),["rpg_debug_start",{hero:PA,attack_damage:10000}]);
    ui.event("rpg_debug_state",{active:1,pending:0,phase:"setup",hero:PA,attack_damage:10000});
    assert(p.SkillDebug.BHasClass("Hidden") && p.ShopPanel.BHasClass("DebugHideRecruitment"));
    ui.click("SkillDebugButton"); ui.event("rpg_battle_state",{phase:"fight",run_complete:0});
    assert(!p.SkillDebugStart.enabled && !p.SkillDebugApplyDamage.enabled && !p.SkillDebugReset.enabled);
    assert(p.SkillDebugExit.enabled, "exit remains available during a problematic fight");
    const inFight=ui.sent.length; ui.click("SkillDebugStart"); ui.click("SkillDebugApplyDamage"); ui.click("SkillDebugReset");
    assert.strictEqual(ui.sent.length,inFight, "blocked controls do not submit gameplay mutations");
    ui.event("rpg_battle_state",{phase:"setup"}); ui.type("SkillDebugDamage","333"); ui.click("SkillDebugApplyDamage");
    assert.deepStrictEqual(ui.sent.at(-1),["rpg_debug_damage",{attack_damage:333}]);
    ui.event("rpg_debug_state",{active:1,pending:0,phase:"setup",hero:PA,attack_damage:333,error:""});
    ui.click("SkillDebugReset"); assert.deepStrictEqual(ui.sent.at(-1),["rpg_debug_reset",{}]);
    ui.event("rpg_debug_state",{active:1,pending:0,phase:"setup",hero:PA,error:"spawn_failed"});
    assert(p.SkillDebugError.text && !p.SkillDebug.BHasClass("Hidden"), "errors stay visible and controls recover");
    ui.event("rpg_debug_state",{active:1,pending:0,phase:"fight",hero:PA,error:""});
    ui.click("SkillDebugExit"); ui.event("rpg_debug_state",{active:0,pending:0,phase:"setup",hero:"",error:""});
    assert(p.SkillDebug.BHasClass("Hidden") && !p.ShopPanel.BHasClass("DebugHideRecruitment"));
    for (const close of [()=>ui.click("SkillDebugClose"),()=>ui.click("SkillDebugBackdrop"),()=>p.SkillDebugSearch.events.oncancel()]) {
        ui.click("SkillDebugButton"); const n=ui.sent.length; close();
        assert(p.SkillDebug.BHasClass("Hidden") && ui.sent.length===n, "closing the window is distinct from exiting the test");
    }
    assert(ui.sent.every(([event,data])=>event.startsWith("rpg_debug_") && !("PlayerID" in data)), "controls only send their explicit debug request; identity belongs to the engine");
}
console.log("PASS: live debug XML, bilingual hero search, validated requests, asynchronous cancellation, phase gates, reset/exit and close semantics");
