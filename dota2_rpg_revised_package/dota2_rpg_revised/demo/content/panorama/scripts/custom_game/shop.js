(function () {
    "use strict";

    let requestCounter = 1;
    const pending = {};

    function hideDefaultShop() {
        if (typeof GameUI.SetDefaultUIEnabled !== "function") {
            return;
        }
        GameUI.SetDefaultUIEnabled(DotaDefaultUIElement_t.DOTA_DEFAULT_UI_INVENTORY_SHOP, false);
        if (DotaDefaultUIElement_t.DOTA_DEFAULT_UI_SHOP_SUGGESTEDITEMS !== undefined) {
            GameUI.SetDefaultUIEnabled(DotaDefaultUIElement_t.DOTA_DEFAULT_UI_SHOP_SUGGESTEDITEMS, false);
        }
    }

    function send(eventName, body, callback) {
        const requestId = String(requestCounter++);
        body.request_id = requestId;
        pending[requestId] = callback || function () {};
        GameEvents.SendCustomGameEventToServer(eventName, body);
    }

    function buy(itemName, callback) {
        send("rpg_shop_buy", { item_name: itemName }, callback);
    }

    function equip(warehouseUid, heroIndex, callback) {
        send("rpg_shop_equip", {
            warehouse_uid: String(warehouseUid),
            hero_index: String(heroIndex)
        }, callback);
    }

    function unequip(itemIndex, callback) {
        send("rpg_shop_unequip", { item_index: String(itemIndex) }, callback);
    }

    function sell(warehouseUid, callback) {
        send("rpg_shop_sell", { warehouse_uid: String(warehouseUid) }, callback);
    }

    function parseWarehouse(serialized) {
        if (!serialized) {
            return [];
        }
        return serialized.split(";").filter(Boolean).map(function (row) {
            const fields = row.split("|");
            return {
                uid: fields[0],
                itemName: fields[1],
                purchaseCost: Number(fields[2] || 0),
                source: fields[3] || ""
            };
        });
    }

    function onResult(args) {
        const callback = pending[String(args.request_id)];
        if (!callback) {
            return;
        }
        delete pending[String(args.request_id)];
        callback(Number(args.ok) === 1, args.reason || "", Number(args.extra || 0));
    }

    function onShopNetTableChanged(tableName, key, value) {
        if (tableName !== "rpg_shop") {
            return;
        }
        $.GetContextPanel().SetDialogVariableInt("rpg_gold", Number(value.gold || 0));
        $.GetContextPanel().warehouseItems = parseWarehouse(value.warehouse || "");
        $.GetContextPanel().AddClass("ShopStateDirty");
    }

    hideDefaultShop();
    GameEvents.Subscribe("rpg_shop_result", onResult);
    CustomNetTables.SubscribeNetTableListener("rpg_shop", onShopNetTableChanged);

    $.GetContextPanel().RPGShop = {
        buy: buy,
        equip: equip,
        unequip: unequip,
        sell: sell,
        parseWarehouse: parseWarehouse
    };
})();
