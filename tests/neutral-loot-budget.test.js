"use strict";
// Cross-module economic contract: keep authored purchase-equivalent credit tied
// to unchanged tier liquidation, without treating native zero as retail price.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname,"..","game/dota_addons/dota2_rpg/scripts/vscripts");
const read = name => fs.readFileSync(path.join(root,name),"utf8");
const loot = read("battle/campaign_loot.lua");
const sales = read("issue_fixes/item_sales.lua");
const catalog = read("data/campaign_loot_catalog.lua");
const numbers = value => value.split(",").map(x=>Number(x.trim()));
const liquidation = numbers(sales.match(/local neutralTierPrices = \{([^}]+)\}/)[1]);
const equivalents = numbers(loot.match(/function Loot\.NeutralEquivalent\(row\)[\s\S]*?return \(\{([^}]+)\}/)[1]);
assert.deepStrictEqual(liquidation,[100,200,400,800,1600]);
assert.deepStrictEqual(equivalents,liquidation.map(value=>value*2));
const pogo = catalog.split("\n").find(line=>line.includes('name="item_pogo_stick"') || line.includes('name = "item_pogo_stick"'));
assert(pogo && /cost\s*=\s*0\b/.test(pogo) && /power\s*=\s*2\b/.test(pogo));
const flush = loot.slice(loot.indexOf("function Loot.Flush("),loot.indexOf("function Loot.UpgradeEquipment("));
assert(!/NeutralBundle|Loot\.Award\(|Loot\.Roll\(/.test(flush),"delivery cannot issue or re-budget earned bundles");
const doc = fs.readFileSync(path.resolve(__dirname,"../docs/UI79_NEUTRAL_REWARD_BUDGET.md"),"utf8");
for(const term of ["purchase-equivalent","425","6075","4050","2835","200"]) assert(doc.includes(term));
console.log("PASS neutral economy contract: native zero/tier2, fixed sale schedule, explicit x2 equivalent, delivery separation, documented chapter9 budgets");
