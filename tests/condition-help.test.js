"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const {execFileSync} = require("child_process");
const root = path.resolve(__dirname, ".."), panorama = path.join(root, "content/dota_addons/dota2_rpg/panorama");
const xmlPath = path.join(panorama, "layout/custom_game/rpg_demo_hud.xml");
const tree = JSON.parse(execFileSync("python", ["-c", "import json,sys,xml.etree.ElementTree as E; f=lambda e:dict(type=e.tag,attrs=e.attrib,children=[f(c) for c in e]); print(json.dumps(f(E.parse(sys.argv[1]).getroot())))", xmlPath], {encoding:"utf8"}));
const source = fs.readFileSync(path.join(panorama, "scripts/custom_game/condition_help.js"), "utf8");
const dataSource = fs.readFileSync(path.join(panorama, "scripts/custom_game/condition_help_data.js"), "utf8");
const xml = fs.readFileSync(xmlPath, "utf8"), css = fs.readFileSync(path.join(panorama, "styles/custom_game/condition_help.css"), "utf8");
assert(xml.includes("condition_help.css") && xml.indexOf("condition_help_data.js") < xml.indexOf("condition_help.js"), "live layout loads tutorial assets in order");
assert(/#ConditionHelpButton\s*\{[^}]*horizontal-align:\s*right[^}]*vertical-align:\s*top/.test(css), "help entry is anchored top-right");
assert(/#ConditionHelpBody\s*\{[^}]*overflow:\s*squish scroll/.test(css), "long tutorials scroll independently");
const hudCss = fs.readFileSync(path.join(panorama, "styles/custom_game/rpg_demo_hud.css"), "utf8");
const helpLayer = Number(css.match(/#ConditionHelp\s*\{[^}]*z-index:\s*(\d+)/)[1]);
const dropdownLayer = Number(hudCss.match(/\.DropdownLayer\s*\{[^}]*z-index:\s*(\d+)/)[1]);
assert(helpLayer > dropdownLayer, "help blocks open action menus from editing rules through the backdrop");
function launch(language) {
    const ids = {}, sent = [];
    function panel(type, parent, id, attrs = {}) {
        const p = {id, type, parent, children:[], text:attrs.text || "", classes:new Set((attrs.class || "").split(/\s+/).filter(Boolean)), events:{}, hittest:attrs.hittest !== "false",
            AddClass(c) {this.classes.add(c);}, RemoveClass(c) {this.classes.delete(c);}, BHasClass(c) {return this.classes.has(c);},
            SetHasClass(c, enabled) {enabled ? this.AddClass(c) : this.RemoveClass(c);},
            SetPanelEvent(event, fn) {this.events[event] = fn;},
            RemoveAndDeleteChildren() { const erase = child => {if(child.id) delete ids[child.id]; child.children.forEach(erase);}; this.children.forEach(erase); this.children = []; },
            SetFocus() {this.focused = true;}, ScrollToTop() {this.scrolled = true;}
        };
        if (id) ids[id] = p;
        if (parent) parent.children.push(p);
        return p;
    }
    function build(node, parent) {const p=panel(node.type, parent, node.attrs.id || "", node.attrs); node.children.forEach(n => build(n,p)); return p;}
    build(tree, null);
    const $ = selector => ids[selector.slice(1)] || null;
    $.CreatePanel = panel; $.Language = () => language;
    $.Localize = token => token.startsWith("#npc_dota_hero_") ? "测试英雄 " + token.slice(1) : token;
    const context = vm.createContext({$, GameEvents:{SendCustomGameEventToServer:(...args)=>sent.push(args)}});
    vm.runInContext(dataSource, context); vm.runInContext(source, context);
    return {ids, data:context.RpgConditionHelpData, sent,
        click(id) {assert(ids[id], "live panel exists: "+id); ids[id].events.onactivate();},
        text(p) {return p.text + "\n" + p.children.map(c => this.text(c)).join("\n");}};
}
for (const language of ["schinese", "english"]) {
    const ui = launch(language), zh = language === "schinese";
    assert(ui.ids.ConditionHelp.BHasClass("Hidden"), "help starts closed");
    ui.click("ConditionHelpButton");
    assert(!ui.ids.ConditionHelp.BHasClass("Hidden"), "question mark opens help");
    assert(ui.text(ui.ids.ConditionHelpBody).includes(zh ? "选择英雄" : "Select a hero"), "intro teaches the actual setup path");
    for (const category of ui.data.categories) {
        ui.ids.ConditionHelpBody.scrolled = false;
        ui.click("HelpCategory_"+category.id);
        const article=ui.text(ui.ids.ConditionHelpBody);
        const title=typeof category.title === "string" ? category.title : category.title[zh ? "zh" : "en"];
        assert(article.includes(title) && !article.includes("[object Object]") && !article.includes("undefined"), category.id+" renders readable localized tutorial");
        assert(ui.ids.ConditionHelpBody.scrolled, "switching tutorials returns to the beginning");
        if (category.id === "combo") {
            const collect = p => [p].concat(...p.children.map(collect));
            const icons = collect(ui.ids.ConditionHelpBody).filter(p => p.type === "DOTAItemImage" || p.type === "DOTAAbilityImage");
            assert.deepStrictEqual(icons.map(p => p.itemname || p.abilityname), ["item_blink", "item_blade_mail", "axe_berserkers_call"], "user's three-step combo shows item and skill icons in sequence");
        }
    }
    const example=ui.data.categories.find(c => c.examples && c.examples.length);
    const query=example.examples[0].ability;
    ui.ids.ConditionHelpSearch.text=query;
    ui.ids.ConditionHelpSearch.events.ontextentrychange();
    assert(ui.ids["HelpCategory_"+example.id], "search finds example skills");
    const withHero = ui.data.categories.find(c => c.examples.some(e => e.hero));
    const hero = withHero.examples.find(e => e.hero);
    ui.ids.ConditionHelpSearch.text = hero.hero_label ? hero.hero_label[zh ? "zh" : "en"] : "测试英雄 " + hero.hero;
    ui.ids.ConditionHelpSearch.events.ontextentrychange();
    assert(ui.ids["HelpCategory_"+withHero.id], "search finds localized example hero names");
    ui.ids.ConditionHelpSearch.text="no_such_skill_987654";
    ui.ids.ConditionHelpSearch.events.ontextentrychange();
    assert(ui.text(ui.ids.ConditionHelpNav).includes(zh ? "没有找到" : "No matches"), "empty search gives recovery guidance");
    ui.click("ConditionHelpClear");
    assert(ui.data.categories.every(c => ui.ids["HelpCategory_"+c.id]), "clear restores all categories");
    for (const close of [() => ui.click("ConditionHelpClose"), () => ui.click("ConditionHelpBackdrop"), () => ui.ids.ConditionHelpSearch.events.oncancel()]) {
        close(); assert(ui.ids.ConditionHelp.BHasClass("Hidden"), "close route dismisses help"); ui.click("ConditionHelpButton");
    }
    assert.strictEqual(ui.sent.length,0,"browsing help never submits or modifies hero rules");
}
console.log("PASS: live help layout, bilingual categories, examples, search/clear, scrolling, close/reopen and read-only rule behavior");
