# UI54：打开原版商店时自动选中小精灵

承接 UI53。上一版确认了"自动交付"已经生效，但用户仍必须**手动选中小精灵**才能买。本轮用用户提供的控制台日志把原因钉死了。

## 证据链

**失败那次（选中英雄 bristleback 时点击购买）**，控制台里只有选中变更的绑定行：

```
[RPGTrace t=325.00] Wallet carrier_bound player=0 hero=npc_dota_hero_bristleback native_before=2301 native_after=2301
```

**没有任何 `Native order signature`** —— 订单根本没到服务端。

**成功那次（选中小精灵时点击购买）**，同一次点击的完整链路都在：

```
Native order signature: … shop_item_name=item_clarity|units=189
Wallet carrier_bound player=0 hero=npc_dota_hero_wisp
ShopTxn id=3 stage=preflight … target=npc_dota_hero_bristleback decision=accepted
ShopTxn id=3 stage=event … decision=queued
ShopTxn id=3 stage=debit … decision=native:0
Native purchase routed: item_clarity -> npc_dota_hero_bristleback.
ShopTxn id=3 stage=transfer … decision=resolved
```

两次唯一的差别是"选中的是谁"。另外 `NativeShopRange ready native-shop-range-v1 center=-768,0,128 radius=4096` 确认 UI51 的商店触发区**已经建成**，所以不是范围问题。

**结论**：原版客户端只为"玩家自己的英雄"下发购买订单；选中上阵/待命英雄时点击不产生任何订单，也没有错误提示。UI53 试过的 `PlayerResource:SetSelectedHero` 没有改变这条判定（引擎里 `SetSelectedHero`/`GetSelectedHeroEntity`/`SelectUnit`/`DOTAHUDShopOpened`/`DOTAHUDShopClosed` 都存在，但调用它不影响客户端的点工资格）。

## 修改

`rpg_demo_hud.js`：订阅原生 HUD 派发的 `DOTAHUDShopOpened` / `DOTAHUDShopClosed`。商店打开时，如果当前选中不是小精灵，就记下当前单位并用 `GameUI.SelectUnit` 临时选中小精灵；商店关闭时，只在选中仍是小精灵的情况下还原成原来那个单位（不覆盖玩家在商店里自己改选的单位）。仅准备阶段生效。

`addon_game_mode.lua`：`rpg_shop_state` 增加 `commander_index`，HUD 需要知道小精灵的实体索引。

**交付目标不受影响**：UI53 的规则保持有效——服务端不会因为选中小精灵而清掉已选定的上阵/待命英雄目标。玩家点英雄 →（商店打开时选中自动切成小精灵）→ 点购买 → 订单按原价原生扣款 → 物品交付给那个英雄。

## 验证与部署

- `LUA_BIN=… python scripts/test-all.py`：**87 / 87** 测试组通过。
- `tests/hud-sidebar.test.js` 新增：打开商店切到小精灵、关闭还原、可重复、已选中小精灵时不切换、战斗阶段不切换。
- 本机开发 addon 同步 `addon_game_mode.lua` 与 `rpg_demo_hud.js`，并用 `resourcecompiler.exe` 单独编译该 JS（`1 compiled, 0 failed`）。
- 本机工坊包重打包：3 个差异条目（地图 VPK、`rpg_demo_hud.vjs_c`、`addon_game_mode.lua`），137 条其余原样保留；两份拷贝都已替换，备份见 `tests/results/ui54-shop-selection-swap-workshop.json`。包内已确认含 `commander_index` 与 `DOTAHUDShopOpened`/`DOTAHUDShopClosed`。没有修改 Steam 清单、没有上传远端、没有启动或关闭 Dota。

## 待实机验收

本轮没有启动 Dota。**关键未知项是这两个原生事件是否真的会派发**；`DOTAHUDShopOpened`/`DOTAHUDShopClosed` 只在本机 `client.dll` 里确认了名字存在，没有实机触发记录。请重进地图后确认：

1. 选中一名上阵英雄，打开原版商店：选中应自动变成小精灵（右下角头像变化），关闭商店后自动切回原英雄。
2. 商店打开时点购买：物品应进入此前选中的英雄，原价只扣一次。
3. 待命英雄同样确认。
4. 换关（阵容重建）后再买一次。
5. 控制台出现 `Native order signature` + `ShopTxn … preflight accepted` + `Native purchase routed: <物品> -> <英雄>`。

若打开商店时选中**没有**自动切换，说明这两个事件没有派发；那就不再走"原生商店点击"这条路，改为在项目面板内下单（服务端自己发 `PURCHASE_ITEM`），代价是面板里要重新放一份可购清单。
