"use strict";
const assert = require('assert');
const { runHud, panel } = require('./condition-ui-v2.test');
const hud = runHud();
const hero = 'npc_dota_hero_witch_doctor';
const localize = hud.context.$.Localize;
hud.context.$.Localize = token => ({
    '#dota2_rpg_gris_gris_saved': '护符：已存 {gold} 金',
    '#dota2_rpg_gris_gris_redeem': '出售兑现'
}[token] || localize(token));
function shop(gold, equipped) {
    hud.subscriptions.rpg_shop_state({gold:100, owned_text:hero, lineup_text:hero,
        equipped_text:hero + ':' + equipped, gris_gris_gold:gold,
        stock_text:'', stash_free_slots:6, neutral_slot_free:1});
}
shop(10, 'item_grisgris|801|16');
const row = () => panel(hud, 'Equipped_' + hero + '_0');
const label = () => row().children.find(child => child.BHasClass('ItemRowName')).text;
assert.equal(label(), '护符：已存 10 金');
assert.equal(panel(hud, 'Unequip_' + hero + '_0').enabled, false);
let sell = panel(hud, 'Sell_' + row().id);
assert.equal(sell.children[0].text, '出售兑现');
assert.equal(sell.enabled, true);
shop(11, 'item_grisgris|801|16');
assert.equal(label(), '护符：已存 11 金', 'bank display follows authoritative server amount');
sell = panel(hud, 'Sell_' + row().id);
sell.events.onactivate();
let sent = hud.sentEvents.filter(event => event.name === 'rpg_item_sell').pop();
assert.equal(sent.payload.item_index, 801);
assert.equal(sent.payload.hero, hero);
assert.equal(sent.payload.item, 'item_grisgris');
assert.equal(panel(hud, 'Sell_' + row().id).enabled, false, 'pending redemption is locked');
shop(0, '');
assert(!panel(hud, 'ItemEquippedList').children.some(child => child.id === 'Equipped_' + hero + '_0'),
    'redeemed item disappears from the live panel tree');
console.log('PASS Gris-Gris bank display and exact-entity redemption');
