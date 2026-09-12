# UI53：选中英雄后无法点击原版商店购买

用户复述问题：**英雄不能购买装备，仍然必须选中小精灵先买才行**。本轮先确认了现象归属，再改代码。

## 现象确认

用户在游戏里的实际表现是：**选中上阵/待命英雄时，原版商店里的物品可以点，但点下去完全没有任何反应，金币和物品栏都不变，也没有任何错误提示**；选中小精灵再点就正常。

"没有任何提示"意味着引擎没有下发 `DOTA_INVALID_ORDER_*`：这个点击没有产生购买订单，而不是被订单过滤器拒绝。项目侧的 `TraceNativeShopOrder` 会为每条到达过滤器的原版订单打印 `Native order signature`，因此复现后 `console.log` 里没有任何签名行即可确认点击没有离开客户端。

## 为什么之前的修复没有生效

两次部署记录都写着未上传：

- 创意工坊包 `3799645167` 的发布时间是 **19:12:43**，用户 **19:26** 重新下载的就是它。包内是旧的 `RosterAccess.EnableNativeShop({enable_easy_buy=true})`，**没有** UI51 的 `native-shop-range-v1`，也**没有** UI52 的编译产物。
- UI51（19:52）与 UI52（20:07）只装进了本机开发 addon。`console.log` 最后写入是 16:10（Workshop Tools 启动后停在 `ToolsStallMonitor Stall detected`，不含任何 `Dota2Rpg` 行），此后没有新的客户端启动记录。

也就是说：这两版修复在用户机器上一次都没有跑过。

## 根因判断

`dota_easybuy` 在引擎里的官方说明是：

> Everything is free, all shops are in range, and **you can purchase for other heroes**

也就是说"能给别的英雄买"本来就是这条作弊指令提供的，它在没有 `sv_cheats` 的普通客户端里从来不生效。UI51 为了防止"购买变成免费"删掉了它，但没有替代"为其他英雄下单"这一条。

项目侧的结构性差别同样指向同一个方向：上阵/待命英雄是 `CreateUnitByName` 造出来的，没有经过引擎选人流程；`addon_game_mode.lua` 从来没有调用过 `PlayerResource:SetSelectedHero`，客户端因此不把它们算作"玩家自己的英雄"（`ReplaceHeroWith` 生成的指挥官小精灵才是）。

引擎二进制核对：`SetSelectedHero`、`GetSelectedHeroEntity`、`IsInRangeOfShop`、`SpawnDOTAShopTriggerRadiusApproximate` 都存在于安装版本，UI51 的商店范围接口是真实存在的。

## 修改

`addon_game_mode.lua`：

1. 新增 `SyncNativePlayerHero`：把当前选中的装备载体发布成 `PlayerResource` 的 selected hero，选中小精灵时回落到小精灵。只按实体索引去重，读取 `GetSelectedHeroEntity` 回读校验；接口缺失、调用失败或没有生效都会留下可定位日志（`Native player hero synced ...` / `SetSelectedHero did not take effect`）。
2. 新增 `EnsureNativePlayerHero`：准备阶段每个 tick 检查一次；阵容重建销毁旧实体后自动退回小精灵，不会留下失效句柄。指挥官生成时也会同步一次。
3. `SetNativePurchaseSelection`：选中小精灵不再清掉已经选定的上阵/待命英雄交付目标（新增 `HasLiveNativePurchaseTarget`）。选中小精灵只是为了让原版商店可点，不代表"这次购买进小精灵"；购买后仍按原目标自动交付，不需要再手动转交。没有存活英雄目标时照旧回落到 `__wisp`。

价格、库存、合成、扣款与交付路径完全不变：订单仍由 `ValidatePrepareOrder` 改派给小精灵执行，再按 `nativePurchaseSelectionHero` 交付同一名英雄。

## 验证与部署

- `LUA_BIN=... python scripts/test-all.py`：**87 / 87** 测试组通过。
- `tests/shop-state.test.lua` 新增覆盖：选中英雄发布为原生玩家英雄、同一实体不重复调用、存活选中不被每 tick 巡检重置、实体销毁后退回小精灵、非法载体不发布、以及"选中小精灵不清掉英雄交付目标 / 空阵容才回落"。
- 本机开发 addon 已同步 `addon_game_mode.lua`，SHA-256 `cb948e52...d97`。
- 用户此前已授权的本机工坊包重打包流程已重跑：用 `scripts/patch-workshop-vpk.py` 把**当前**开发 addon 的 14 个差异条目写回自包含 VPK（137 条，其余 123 条原样保留），并替换两份本机工坊包。包内已确认包含 `SyncNativePlayerHero` 与 UI51 的 `native-shop-range-v1`。备份与哈希见 `tests/results/ui53-shop-hero-sync-workshop.json`。没有修改 Steam 清单、没有上传远端、没有启动或关闭 Dota。

## 待实机验收

本轮没有启动 Dota，也没有截图。客户端为什么拒绝为项目生成的英雄下单，属于对客户端行为的**推断**，离线测试无法证明。请普通客户端重进地图（必要时重启客户端以重新挂载包）后按顺序确认：

1. 选中一名上阵英雄，打开原版商店点购买：物品应进入该英雄，金币按原价只扣一次。
2. 待命英雄同样确认一次。
3. 选中小精灵时购买：物品仍应交付给此前选定的英雄，而不是留在小精灵身上。
4. 换关（阵容重建）后再买一次，确认没有失效目标。
5. `console.log` 里出现 `Native player hero synced for the native shop: <英雄>`，并且购买时出现 `Native order signature` + `ShopTxn ... preflight`。

如果仍然"点了没反应"，说明客户端的资格判定不是 selected hero：届时**没有** `Native order signature` 行即为证据，需要改走项目侧下单（面板内发起 `PURCHASE_ITEM` 订单）而不是继续猜客户端。
