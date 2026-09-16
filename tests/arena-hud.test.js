"use strict";
// Arena entry is paused in the live XML; load the retained module explicitly
// so its full behavior remains covered before it is reopened.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {runHud, panel, click} = require("./condition-ui-v2.test");
const root = path.resolve(__dirname, "..");
const panorama = path.join(root, "content/dota_addons/dota2_rpg/panorama");
const css = fs.readFileSync(path.join(panorama, "styles/custom_game/arena_hud.css"), "utf8");
const translations = {};
for (const language of ["schinese", "english"]) {
    const source = fs.readFileSync(path.join(root, "game/dota_addons/dota2_rpg/resource/addon_" + language + ".txt"), "utf8");
    translations[language] = Object.fromEntries([...source.matchAll(/"(arena_[^"]+)"\s+"([^"]*)"/g)].map(m => ["#" + m[1], m[2]]));
}
assert.deepStrictEqual(Object.keys(translations.schinese).sort(), Object.keys(translations.english).sort());

assert.strictEqual(translations.schinese["#arena_positions"], "站位会随阵容保存，对手阵容按战场另一侧还原");
assert(translations.schinese["#arena_choose_hint"].includes("30级") && translations.schinese["#arena_choose_hint"].includes("99999"));
const catalogSource = fs.readFileSync(path.join(root, "game/dota_addons/dota2_rpg/scripts/data/debug_heroes.kv"), "utf8");
const catalog = [...new Set(catalogSource.match(/npc_dota_hero_[a-z0-9_]+/g))];
assert(catalog.length >= 127, "test exercises the full server catalog");
const HERO = "npc_dota_hero_axe";
function launch(language) {
    const hud = runHud();
    assert.strictEqual(hud.subscriptions.rpg_arena_state, undefined, "live HUD starts PVE without arena entry or subscriptions");
    assert(!hud.sentEvents.some(event => event.name.startsWith("rpg_arena_")), "live HUD sends no arena requests");
    hud.context.Players.GetLocalPlayer = () => 0;
    // This shared harness indexes real XML IDs; attach their actual XML parents as well.
    const tree = JSON.parse(require("child_process").execFileSync("python", ["-c", "import json,sys,xml.etree.ElementTree as E; f=lambda e:dict(type=e.tag,attrs=e.attrib,children=[f(c) for c in e]); print(json.dumps(f(E.parse(sys.argv[1]).getroot())))", path.join(panorama,"layout/custom_game/rpg_demo_hud.xml")], {encoding:"utf8"}));
    function attach(node, parent) {
        const current = node.attrs.id ? panel(hud,node.attrs.id) : parent;
        if (current && current !== parent) {current.parent = parent;}
        node.children.forEach(child => attach(child,current));
    }
    attach(tree,hud.context.$.GetContextPanel());
    hud.context.$.Localize = token => translations[language][token] || ({"#npc_dota_hero_axe": "斧王 Axe"}[token]) || token;
    require("vm").runInContext(fs.readFileSync(path.join(panorama,"scripts/custom_game/arena_hud.js"),"utf8"),hud.context);
    const base = {mode:"campaign", phase:"preparing", rating:1500, round:1, wins:0, generation:1, catalog, results:[], can_start:true, can_edit:true, can_buy:true};
    return {hud, p:id => panel(hud,id), click:id => click(hud,id),
        events:() => hud.sentEvents.filter(e => e.name.startsWith("rpg_arena_")),
        owner(id=0) {hud.subscriptions.rpg_battle_state({phase:"setup", ready:1, owner_player_id:id});},
        state(patch={}) {hud.subscriptions.rpg_arena_state({state_json:JSON.stringify(Object.assign({},base,patch))});},
        search(value) {panel(hud,"ArenaSearch").text=value; panel(hud,"ArenaSearch").events.ontextentrychange();}
    };
}
function hidden(p) {return p.BHasClass("ArenaHidden");}
function last(ui) {const events=ui.events(); return events[events.length-1];}
function chooseFive(ui) {catalog.slice(0,5).forEach(hero => ui.click("ArenaHero_"+hero));}
for (const language of ["schinese", "english"]) {
    const ui = launch(language), dispatches = [];
    ui.hud.context.$.DispatchEvent = (...args) => dispatches.push(args);
    ui.owner(); ui.state({mode:"select"});
    ui.click("ArenaChooseLadder"); chooseFive(ui); ui.click("ArenaEnter");
    assert.strictEqual(last(ui).name,"rpg_arena_enter");
    ui.state({mode:"arena",generation:2,can_test:true,can_export:true,can_start:true});
    assert(!ui.hud.panels["#ArenaStart"],"online matchmaking control is removed even with stale capabilities");
    assert.strictEqual(ui.hud.subscriptions.rpg_arena_export_result,undefined,"hosted export responses have no listener");
    assert(!ui.hud.panels["#ArenaSummary"] && !ui.hud.panels["#ArenaResultsChips"],"online rating summary is removed");
    for (const strength of ["lower","similar","higher"]) {
        ui.state({mode:"arena",generation:3,can_test:true});
        ui.click("ArenaStrength_"+strength);ui.click("ArenaTest");
        assert.strictEqual(last(ui).name,"rpg_arena_test");assert.strictEqual(last(ui).payload.strength,strength);
        assert(!ui.p("ArenaTest").enabled,"pending local test blocks double clicks");
    }
    ui.state({mode:"arena",generation:4,phase:"fighting",practice:true,can_test:true});
    assert(!ui.p("ArenaTest").enabled);
    ui.state({mode:"arena",generation:5,can_test:true,test_result:{won:true,survivors:4,deaths:1,opponent_name:"<b>Local</b>",strength:"higher"}});
    assert(ui.p("ArenaTestResult").text.includes("<b>Local</b>") && !ui.p("ArenaTestResult").html);
    ui.click("ArenaExit");ui.click("ArenaAbandon");assert.strictEqual(last(ui).name,"rpg_arena_exit");
    assert.strictEqual(dispatches.length,0,"arena never opens external browser");
    assert(!ui.events().some(e=>e.name==="rpg_arena_export" || e.name==="rpg_arena_start"));
    ui.owner(1);assert(!ui.p("ArenaTest").enabled);
}
const source=fs.readFileSync(path.join(panorama,"scripts/custom_game/arena_hud.js"),"utf8");
assert(!/https?:|ExternalBrowserGoToURL/.test(source),"no hosted URLs or browser actions remain");
console.log("PASS offline arena HUD: local selection/practice, stale online flags blocked, no cloud export listener or browser dispatch");
