"use strict";
// 中立装备占用原版专属中立槽 16：它不占物品栏/背包/储藏栏。
// 面板必须按它自己的容量判断交付与卸下，并且必须把槽 16 显示出来——
// 之前的 0..14 过滤会把它整行丢掉，玩家因此看不到也拿不回这件奖励。
const assert = require('assert');
const { runHud, panel } = require('./condition-ui-v2.test');

const hero = 'npc_dota_hero_axe';
const SIX_ACTIVE = ['item_blink|601|0', 'item_force_staff|602|1', 'item_power_treads|603|2',
    'item_black_king_bar|604|3', 'item_heart|605|4', 'item_assault|606|5'].join(',');
const NEUTRAL_EQUIPPED = 'item_enhancement_alert|701|16';

function labelOf(row) {
    var label = (row.children || []).filter(function (child) {
        return child.type === 'Label' && (child.BHasClass('ItemRowName') || String(child.text).length > 0);
    })[0];
    return label ? String(label.text) : '';
}
function stockLabel(hud, index) { return labelOf(panel(hud, 'Stock' + index)); }
function equippedLabel(hud, index) { return labelOf(panel(hud, 'Equipped_' + hero + '_' + index)); }
function shop(hud, overrides) {
    var payload = {
        gold: 500, lineup_text: hero, owned_text: hero,
        stock_text: 'item_blink|501;item_occult_bracelet|502',
        stock_neutral_text: '502',
        stash_free_slots: 0, neutral_slot_free: 1,
        equipped_text: hero + ':' + SIX_ACTIVE
    };
    Object.keys(overrides || {}).forEach(function (key) { payload[key] = overrides[key]; });
    hud.subscriptions.rpg_shop_state(payload);
}

// 场景 1：6 个主动栏已满、英雄没有中立装备。普通装备不能交付，中立装备可以。
var hud = runHud();
shop(hud);
assert(panel(hud, 'Equip0').enabled === false, 'ordinary gear still needs an inventory slot');
assert(panel(hud, 'Equip1').enabled === true, 'neutral gear fits the dedicated neutral slot');
assert(stockLabel(hud, 1).indexOf('（中立）') >= 0, 'neutral stock row is marked');
assert(stockLabel(hud, 0).indexOf('（中立）') < 0, 'ordinary stock row is not marked');
panel(hud, 'Equip1').events.onactivate();
var equip = hud.sentEvents.filter(function (event) { return event.name === 'rpg_item_equip'; }).pop();
assert(equip && equip.payload.item_index === '502', 'neutral equip sends the exact entity id');

// 场景 2：英雄已有中立装备。交付必须被拒绝，槽 16 的行必须显示出来。
hud = runHud();
shop(hud, { equipped_text: hero + ':' + SIX_ACTIVE + ',' + NEUTRAL_EQUIPPED });
assert(panel(hud, 'Equip1').enabled === false, 'one neutral item per hero');
assert(panel(hud, 'Equipped_' + hero + '_6'), 'neutral slot row is rendered instead of filtered out');
assert(equippedLabel(hud, 6).indexOf('（中立）') >= 0, 'neutral equipped row is marked');
assert(panel(hud, 'Unequip_' + hero + '_6').enabled === true,
    'neutral unequip only needs the commander neutral slot');
assert(panel(hud, 'Unequip_' + hero + '_0').enabled === false,
    'ordinary unequip still needs a free 0..14 slot');

// 场景 3：指挥官中立槽被占用时，中立装备不能卸下。
shop(hud, { equipped_text: hero + ':' + SIX_ACTIVE + ',' + NEUTRAL_EQUIPPED, neutral_slot_free: 0 });
assert(panel(hud, 'Unequip_' + hero + '_6').enabled === false, 'occupied commander neutral slot blocks unequip');
assert(panel(hud, 'Equip1').enabled === false, 'occupied commander neutral slot blocks delivery');

// 场景 5：物品名优先走原版本地化 token —— 转交面板不能只显示英文原名。
hud = runHud();
var originalLocalize = hud.context.$.Localize;
hud.context.$.Localize = function (token) {
    if (token === '#DOTA_Tooltip_ability_item_occult_bracelet') { return '秘术手镯'; }
    return originalLocalize(token);
};
shop(hud);
assert(stockLabel(hud, 1).indexOf('秘术手镯') >= 0, 'item names use the native localization token');
assert(stockLabel(hud, 0).indexOf('blink') >= 0, 'missing tokens still fall back to the readable name');
hud.context.$.Localize = originalLocalize;

// 场景 4：回城卷轴槽（15）不进面板 —— 本模式不提供回城卷轴，商店已下架、
// 掉落池已排除，面板也不展示、不转交它。
hud = runHud();
shop(hud, { equipped_text: hero + ':' + SIX_ACTIVE + ',item_tpscroll|801|15' });
assert(!panel(hud, 'Equipped_' + hero + '_6'), 'the TP scroll slot renders no row');

console.log('PASS: neutral items use the dedicated slot 16 for delivery, display and unequip');
