"use strict";
// Reuse the existing harness: it parses the live XML and loads every included script in order.
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
assert.strictEqual(translations.schinese["#arena_mode"], "天梯对战");
assert.strictEqual(translations.schinese["#arena_positions"], "站位会随阵容保存，对手阵容按战场另一侧还原");
assert(translations.schinese["#arena_choose_hint"].includes("30级") && translations.schinese["#arena_choose_hint"].includes("99999"));
const catalogSource = fs.readFileSync(path.join(root, "game/dota_addons/dota2_rpg/scripts/data/debug_heroes.kv"), "utf8");
const catalog = [...new Set(catalogSource.match(/npc_dota_hero_[a-z0-9_]+/g))];
assert(catalog.length >= 127, "test exercises the full server catalog");
const HERO = "npc_dota_hero_axe";
function launch(language) {
    const hud = runHud();
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
    const entrance = launch(language);
    assert(!hidden(entrance.p("ArenaModeSelector")), "map entry presents mode selection");
    assert(!entrance.p("ArenaChooseCampaign").enabled, "wait for an authoritative owner and generation");
    entrance.owner(); entrance.state({mode:"select"});
    entrance.click("ArenaChooseLadder");
    assert(!hidden(entrance.p("ArenaPicker")) && hidden(entrance.p("ArenaModeSelector")));
    entrance.click("ArenaPickerClose");
    assert(!hidden(entrance.p("ArenaModeSelector")), "cancel hero picking returns to mode selection");
    entrance.click("ArenaChooseCampaign");
    assert.strictEqual(last(entrance).name, "rpg_arena_campaign");
    assert.strictEqual(last(entrance).payload.generation, 1);
    entrance.state({mode:"campaign",generation:2});
    assert(hidden(entrance.p("ArenaModeSelector")) && !hidden(entrance.p("ArenaModeButton")));
    entrance.state({mode:"campaign",generation:2});
    assert(hidden(entrance.p("ArenaModeSelector")), "campaign reconnect does not prompt again");
    const ui = launch(language);
    assert.deepStrictEqual(ui.events().map(e=>e.name), ["rpg_arena_request"], "initial load only requests state");
    assert(hidden(ui.p("ArenaModeButton")) && hidden(ui.p("ArenaHUD")));
    ui.owner(1); assert(hidden(ui.p("ArenaModeButton")), "non-owner cannot enter");
    ui.owner(); ui.state(); assert(!hidden(ui.p("ArenaModeButton")));
    assert.strictEqual(last(ui).name,"rpg_arena_request", "owner assignment refreshes state");
    ui.click("ArenaModeButton"); ui.click("ArenaChooseLadder"); assert(!hidden(ui.p("ArenaPicker")) && !ui.p("ArenaEnter").enabled);
    assert.strictEqual(last(ui).name,"rpg_arena_request");
    const numericCatalog = Object.fromEntries(catalog.map((hero,i)=>[String(i+1),hero]));
    numericCatalog[999]=HERO; numericCatalog[1000]="<img src=x>";
    ui.state({catalog:numericCatalog});
    assert.strictEqual(ui.p("ArenaHeroes").children.length,catalog.length,"numeric Panorama catalog is deduplicated and validated");
    ui.search("斧王"); assert.strictEqual(ui.p("ArenaHeroes").children.length,1);
    assert.strictEqual(ui.p("ArenaHeroes").children[0].children[0].heroname,HERO);
    ui.search("no_hero_matches"); assert.strictEqual(ui.p("ArenaHeroes").children[0].text,translations[language]["#arena_no_matches"]);
    ui.search(""); chooseFive(ui);
    assert(ui.p("ArenaEnter").enabled && ui.p("ArenaSelectedCount").text.includes("5 / 5"));
    ui.click("ArenaHero_"+catalog[5]); assert.strictEqual(ui.p("ArenaSelectedHeroes").children.length,5,"sixth pick is blocked");
    ui.click("ArenaChosen_"+catalog[0]); assert(!ui.p("ArenaEnter").enabled,"selected tiles can deselect");
    ui.click("ArenaHero_"+catalog[0]);
    ui.click("ArenaEnter");
    assert.strictEqual(last(ui).name,"rpg_arena_enter");
    assert.strictEqual(new Set(last(ui).payload.heroes_text.split(";")).size,5);
    assert.deepStrictEqual(Object.keys(last(ui).payload),["heroes_text","generation"]);
    let n=ui.events().length; ui.click("ArenaEnter"); assert.strictEqual(ui.events().length,n,"pending enter is guarded");
    ui.state({mode:"arena",generation:2});
    assert(hidden(ui.p("ArenaPicker")) && !hidden(ui.p("ArenaHUD")));
    assert(!ui.p("ArenaRoot").BHasClass("ArenaModalOpen"),"preparation leaves rule editor modal accessible");
    assert(ui.p("ArenaRoot").GetParent().BHasClass("ArenaActive"));
    assert(ui.p("ArenaStart").enabled && ui.p("ArenaInstructions").text.includes("99999"));
    ui.click("ArenaStart"); assert.strictEqual(last(ui).name,"rpg_arena_start"); assert.strictEqual(last(ui).payload.generation,2);
    n=ui.events().length; ui.click("ArenaStart"); assert.strictEqual(ui.events().length,n);
    ui.state({generation:1}); assert(ui.p("ArenaRoot").GetParent().BHasClass("ArenaActive"),"stale campaign event cannot undo arena");
    assert(!ui.p("ArenaStart").enabled,"stale response cannot unlock pending button");
    ui.hud.subscriptions.rpg_arena_state({state_json:"broken"});
    for (const phase of ["matching","fighting","transition","saving"]) {
        ui.state({mode:"arena",phase,generation:3});
        assert(!ui.p("ArenaStart").enabled,phase+" disables start despite true flags");
    }
    ui.state({mode:"arena",phase:"adjusting",generation:4,can_buy:false});
    assert(ui.p("ArenaStart").enabled);
    assert.strictEqual(ui.p("ArenaStartLabel").text,translations[language]["#arena_continue"]);
    assert.strictEqual(ui.p("ArenaInstructions").text,translations[language]["#arena_adjust_hint"]);
    ui.click("ArenaStart"); assert.strictEqual(last(ui).payload.generation,4);
    ui.state({mode:"arena",phase:"adjusting",generation:5,can_start:false}); assert(!ui.p("ArenaStart").enabled);
    ui.state({mode:"arena",phase:"error",generation:6,error:"matching_failed"});
    assert(!hidden(ui.p("ArenaRetry")) && ui.p("ArenaRetry").enabled);
    assert.strictEqual(ui.p("ArenaError").text,translations[language]["#arena_matching_failed"]);
    ui.click("ArenaRetry"); assert.strictEqual(last(ui).name,"rpg_arena_retry"); assert.strictEqual(last(ui).payload.generation,6);
    ui.state({mode:"arena",phase:"fighting",generation:7});
    n=ui.events().length; ui.click("ArenaExit"); assert.strictEqual(ui.events().length,n,"unfinished exit requires an explicit confirmation");
    assert(!hidden(ui.p("ArenaExitConfirm")));
    ui.click("ArenaKeepPlaying"); assert(hidden(ui.p("ArenaExitConfirm")));
    ui.click("ArenaExit"); ui.click("ArenaAbandon"); assert.strictEqual(last(ui).name,"rpg_arena_exit"); assert.strictEqual(last(ui).payload.generation,7);
    ui.state({generation:8}); assert(!ui.p("ArenaRoot").GetParent().BHasClass("ArenaActive") && hidden(ui.p("ArenaHUD")));
    ui.click("ArenaModeButton"); ui.click("ArenaChooseLadder"); ui.click("ArenaPickerClose"); assert(hidden(ui.p("ArenaPicker")));
    ui.click("ArenaModeButton"); ui.click("ArenaChooseLadder"); ui.click("ArenaPickerBackdrop"); assert(hidden(ui.p("ArenaPicker")));
    const unsafeName = '<font color="red">对手 & <img src="x"></font>';
    const results = Array.from({length:7},(_,i)=>({won:i!==3,survivors:i===3?0:5,deaths:i===3?5:0,delta:i===3?-8:10,opponent_name:unsafeName+i,opponent_rating:1500+i}));
    const final = {mode:"arena",phase:"saving",generation:9,round:7,wins:6,results:Object.fromEntries(results.map((r,i)=>[i+1,r])),rating_before:1500,rating_after:1552,rating_change:52,perfect_bonus:0,opponent_name:unsafeName};
    ui.state(final);
    assert.strictEqual(ui.p("ArenaSummaryRows").children.length,7);
    assert.strictEqual(ui.p("ArenaResultsChips").children.length,7);
    assert(ui.p("ArenaResultsChips").children[3].BHasClass("ArenaLost"));
    assert(ui.p("ArenaResult1").text.includes(unsafeName+"0") && ui.p("ArenaResult1").html===false);
    assert(ui.p("ArenaOpponent").text.includes(unsafeName) && ui.p("ArenaOpponent").html===false);
    assert(ui.p("ArenaResult4").text.includes("-8") && ui.p("ArenaResult7").text.includes("1506"));
    assert(ui.p("ArenaScores").text.includes("1500 → 1552 (+52)"));
    assert.strictEqual(ui.p("ArenaSaveStatus").text,translations[language]["#arena_saving"]);
    assert(hidden(ui.p("ArenaReplay")));
    ui.state(Object.assign({},final,{phase:"error",error:"arena_save_failed",generation:10}));
    assert.strictEqual(ui.p("ArenaSaveStatus").text,translations[language]["#arena_save_error"]);
    assert.strictEqual(ui.p("ArenaError").text,translations[language]["#arena_save_failed"]);
    ui.click("ArenaRetry"); assert.strictEqual(last(ui).payload.generation,10);
    ui.state(Object.assign({},final,{phase:"finished",generation:11,perfect_bonus:20}));
    assert(ui.p("ArenaPerfectBonus").text.includes("+20"));
    assert.strictEqual(ui.p("ArenaSaveStatus").text,translations[language]["#arena_saved"]);
    ui.click("ArenaReplay"); assert(!hidden(ui.p("ArenaPicker")) && !ui.p("ArenaEnter").enabled);
    ui.click("ArenaPickerClose"); assert(!hidden(ui.p("ArenaHUD")),"closing replay selector leaves final arena HUD visible");
    ui.click("ArenaExit"); assert.strictEqual(last(ui).name,"rpg_arena_exit"); assert.strictEqual(last(ui).payload.generation,11);
    ui.state({generation:12});
    assert(ui.events().every(e => !("PlayerID" in e.payload)),"identity comes from engine");
}
for (const language of ["schinese", "english"]) {
    const ui = launch(language);
    const worker = "https://dota2-rpg-leaderboard-api.dota2-rpg-leaderboard-worker.workers.dev";
    const configuredWorker = fs.readFileSync(path.join(root,"game/dota_addons/dota2_rpg/scripts/vscripts/data/leaderboard_config.lua"),"utf8").match(/endpoint\s*=\s*"([^"]+)"/)[1];
    assert.strictEqual(worker,configuredWorker,"download allowlist matches the actual configured Worker");
    const url = worker + "/api/v1/arena/exports/aB09_-0123456789abcdef0123456789ab";
    const dispatches = [];
    ui.hud.context.$.DispatchEvent = (...args) => dispatches.push(args);
    const result = patch => ui.hud.subscriptions.rpg_arena_export_result(Object.assign({generation:2,url,filename:"arena-team.json"},patch));
    ui.owner(); ui.state();
    assert(!ui.p("ArenaExport").enabled && !ui.p("ArenaTest").enabled,"campaign cannot export a missing arena capture");
    ui.state({mode:"arena",generation:2});
    assert(!ui.p("ArenaExport").enabled && !ui.p("ArenaTest").enabled,"server capabilities default to false");
    const ready = {mode:"arena",generation:2,can_export:true,can_test:true};
    ui.state(ready);
    assert(ui.p("ArenaExport").enabled && ui.p("ArenaTest").enabled);
    assert(ui.p("ArenaStrength_similar").BHasClass("ArenaSelected"));
    ui.click("ArenaExport");
    assert.deepStrictEqual(JSON.parse(JSON.stringify(last(ui))),{name:"rpg_arena_export",payload:{generation:2}});
    assert.strictEqual(ui.p("ArenaExportStatus").text,translations[language]["#arena_exporting"]);
    let n = ui.events().length;
    ui.click("ArenaExport"); ui.click("ArenaTest"); ui.click("ArenaStart");
    assert.strictEqual(ui.events().length,n,"pending export blocks duplicate and concurrent actions");
    ui.state(ready);
    assert(!ui.p("ArenaExport").enabled,"same-generation broadcast preserves export pending");
    result({generation:1}); assert(!ui.p("ArenaExport").enabled,"stale result ignored");
    result();
    assert(ui.p("ArenaDownload").enabled && ui.p("ArenaExportStatus").text.includes("arena-team.json"));
    assert.strictEqual(dispatches.length,0,"result never opens a browser automatically");
    ui.click("ArenaDownload");
    assert.deepStrictEqual(dispatches,[["ExternalBrowserGoToURL",url]]);
    ui.state(Object.assign({},ready,{phase:"fighting"}));
    assert(!ui.p("ArenaDownload").enabled,"existing download disabled during combat");
    ui.click("ArenaDownload"); assert.strictEqual(dispatches.length,1);
    ui.state(Object.assign({},ready,{can_export:false}));
    assert(!ui.p("ArenaExport").enabled && !ui.p("ArenaDownload").enabled,"server revocation disables export and download");
    ui.state(ready);
    for (const invalid of [
        "https://evil.example/api/v1/arena/exports/0123456789abcdef",
        "javascript:alert(1)", worker+"/api/v1/arena/teams/0123456789abcdef",
        worker+".evil.example/api/v1/arena/exports/0123456789abcdef",
        worker.replace("https:","http:")+"/api/v1/arena/exports/0123456789abcdef",
        worker+":443/api/v1/arena/exports/0123456789abcdef",
        worker+"@evil.example/api/v1/arena/exports/0123456789abcdef",
        url+"/../bad", url+"?redirect=https://evil.example", url+"#fragment", url+"%2f", url+"\n",
        worker+"/api/v1/arena/exports/short"
    ]) {
        ui.click("ArenaExport"); result({url:invalid});
        assert(hidden(ui.p("ArenaDownload")) && !ui.p("ArenaDownload").enabled,invalid);
        assert.strictEqual(ui.p("ArenaExportStatus").text,translations[language]["#arena_export_invalid_url"]);
        ui.click("ArenaDownload"); assert.strictEqual(dispatches.length,1);
        assert(ui.p("ArenaExport").enabled,"bad URL unlocks retry");
    }
    ui.click("ArenaExport"); result({error:"backend_unavailable"});
    assert.strictEqual(ui.p("ArenaExportStatus").text,translations[language]["#arena_export_failed"]);
    ui.click("ArenaExport"); ui.state(Object.assign({},ready,{generation:3}));
    assert(ui.p("ArenaExport").enabled && hidden(ui.p("ArenaDownload")));
    result(); assert(hidden(ui.p("ArenaDownload")),"new generation invalidates old response");
    for (const strength of ["lower","similar","higher"]) {
        ui.state(Object.assign({},ready,{generation:3,phase:"adjusting"}));
        ui.click("ArenaStrength_"+strength); ui.click("ArenaTest");
        assert.deepStrictEqual(JSON.parse(JSON.stringify(last(ui))),{name:"rpg_arena_test",payload:{generation:3,strength}});
        n=ui.events().length; ui.click("ArenaTest"); ui.click("ArenaExport");
        assert.strictEqual(ui.events().length,n,"one test at a time");
        assert(!ui.p("ArenaStrength_lower").enabled);
    }
    for (const phase of ["matching","fighting","saving","transition"]) {
        ui.state(Object.assign({},ready,{generation:3,phase}));
        assert(!ui.p("ArenaExport").enabled && !ui.p("ArenaTest").enabled && !ui.p("ArenaDownload").enabled,phase);
        n=ui.events().length; ui.click("ArenaExport"); ui.click("ArenaTest");
        assert.strictEqual(ui.events().length,n);
    }
    for (const phase of ["fighting","transition"]) {
        ui.state(Object.assign({},ready,{generation:3,phase,practice:true,round:4}));
        assert.strictEqual(ui.p("ArenaHeading").text,translations[language]["#arena_practice"]);
        assert.strictEqual(ui.p("ArenaPhase").text,translations[language]["#arena_practice"]);
        assert.strictEqual(ui.p("ArenaInstructions").text,translations[language]["#arena_test_hint"]);
        assert(hidden(ui.p("ArenaResultsChips")) && hidden(ui.p("ArenaSummary")));
    }
    ui.state(Object.assign({},ready,{generation:4,phase:"adjusting",practice:false,test_result:{won:true,survivors:3,deaths:2,opponent_name:"<b>Enemy</b>",strength:"higher"}}));
    assert(ui.p("ArenaTest").enabled && ui.p("ArenaStart").enabled,"practice returns to normal preparation controls");
    assert(ui.p("ArenaTestResult").text.includes("<b>Enemy</b>") && ui.p("ArenaTestResult").html===false);
    assert(ui.p("ArenaTestResult").text.includes(translations[language]["#arena_strength_higher"]));
    assert(ui.p("ArenaTestResult").text.includes("3") && ui.p("ArenaTestResult").text.includes("2"));
    ui.owner(1); assert(!ui.p("ArenaExport").enabled && !ui.p("ArenaTest").enabled);
}
for (const id of ["StartBattleButton","ShopPanel","BattleResult","RunLivesPanel","LevelProgress"]) {
    assert(css.includes(".ArenaActive #"+id),"campaign-only control hidden: "+id);
}
for (const id of ["RightSidebar","RadiantEditor","ItemShopPanel","ItemEquippedList","ItemStockList"]) {
    assert(!css.includes(".ArenaActive #"+id),"editor/inventory remain usable: "+id);
}
assert(/#ArenaRoot\.ArenaModalOpen\s*\{[^}]*z-index:\s*2200/.test(css),"selector overlays existing editor dialogs");
assert(/#ArenaRoot\s*\{[^}]*z-index:\s*90/.test(css),"compact HUD stays below the rule editor modal");
assert(/\.ArenaBackdrop\s*\{[^}]*width:\s*100%;[^}]*height:\s*100%/.test(css));
console.log("PASS arena: live XML/script integration, full catalog, owner gates, bilingual search, five distinct picks, phases, generation guards, requests, exit confirmation, seven results, saving, literal names, export payloads and URL validation, exact browser dispatch, practice controls and unrated display");
