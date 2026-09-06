"use strict";

function Panel(id) {
    this.id = id;
    this.classes = {};
    this.children = {};
    this.parent = null;
    this.text = undefined;
}
Panel.prototype.GetParent = function () { return this.parent; };
Panel.prototype.FindChildTraverse = function (id) {
    if (this.id === id) { return this; }
    if (this.children[id]) { return this.children[id]; }
    var keys = Object.keys(this.children);
    for (var i = 0; i < keys.length; i += 1) {
        var found = this.children[keys[i]].FindChildTraverse(id);
        if (found) { return found; }
    }
    return null;
};
Panel.prototype.AddClass = function (name) { this.classes[name] = true; };
Panel.prototype.BHasClass = function (name) { return !!this.classes[name]; };
Panel.prototype.SetHasClass = function (name, value) { this.classes[name] = !!value; };
Panel.prototype.GetChildCount = function () { return Object.keys(this.children).length; };
Panel.prototype.GetChild = function (index) { return this.children[Object.keys(this.children)[index]]; };
Panel.prototype.SetPanelEvent = function (name, callback) { this[name] = callback; };
Panel.prototype.add = function (child) { this.children[child.id] = child; child.parent = this; return child; };

var root = new Panel("Root");
var context = root.add(new Panel("Context"));
var action = root.add(new Panel("ActionPanel"));
var button = root.add(new Panel("ActionPanelMinimizeButton"));
var label = button.add(new Panel("ActionPanelCollapseArrow"));
label.text = "";
var shop = root.add(new Panel("HeroShop"));

function dollar() { return null; }
dollar.GetContextPanel = function () { return context; };
dollar.Schedule = function (_delay, callback) { callback(); };
global.$ = dollar;

var customConfig = {};
global.GameUI = {
    CustomUIConfig: function () { return customConfig; }
};

require("../overlay/content/dota_addons/dota2_rpg/panorama/scripts/custom_game/issue_fixes_ui.js");

var api = customConfig.RpgIssueFixUI;
if (!api) { throw new Error("API not exported"); }
if (!action.BHasClass("RpgFixedActionPanel")) { throw new Error("action panel not bound"); }
if (!shop.BHasClass("RpgTransparentHeroShop")) { throw new Error("shop not transparent"); }
if (label.text !== "<") { throw new Error("expanded arrow must be <"); }
button.onactivate();
if (!action.BHasClass("RpgActionPanelCollapsed")) { throw new Error("collapse class missing"); }
if (label.text !== ">") { throw new Error("collapsed arrow must be >"); }

var defaults = api.normalizeDefaultRules([]);
if (defaults.length !== 1 || defaults[0].action.kind !== "attack") {
    throw new Error("one attack default expected");
}
var authored = api.normalizeDefaultRules([
    { action: { kind: "cast" } },
    { placeholder: true },
    { action: { kind: "attack" } }
]);
if (authored.length !== 2) { throw new Error("authored rules must remain without padding"); }

console.log("UI tests passed");
