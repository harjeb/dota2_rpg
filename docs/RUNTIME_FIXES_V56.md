# UI56：扩大商店开合探测

承接 UI55。用户实机反馈 `shop open query unavailable; selection swap disabled`：`GameUI.IsShopOpen` 与 `Players.IsShopOpen` 在普通客户端都调不到。同时用户报告了同一根因的第二个症状：**选中英雄时打开商店后商店关不掉（要选中小精灵才能关）**——说明整个原版商店面板在"选中的不是玩家自己的英雄"时都不响应点击，购买和关闭是一件事。

## 修改（`rpg_demo_hud.js`）

按顺序尝试多种判定，并在控制台打印一次探测结果：

1. `GameUI.IsShopOpen()`；
2. `Game.IsShopOpen()`（安装版本 `client.dll` 的 API 表里 `IsShopOpen` 与 `Game` 命名空间的接口相邻）；
3. `Players.IsShopOpen()`；
4. 回退：从 HUD 根节点 `FindChildTraverse` 找原版商店网格面板 `GridMainShop`（该 id 取自 Valve 自己的 `dota_hud_shop` 脚本），用 `actuallayoutwidth/height` 判断它是否被真正布局——商店关闭时该面板不存在或尺寸为 0。

探测结果打印为 `[Dota2Rpg] shop probe GameUI=… Game=… Players=… gridPanel=…`（取值 `true/false/missing/threw/no-namespace/yes/no`），状态翻转时打印 `native shop opened` / `native shop closed`。这样即使这次仍不生效，也能从一行日志判断是哪一种情况，不必再猜。

版本号提到 **56**（用户按这个标签确认包有没有换）。

## 验证与部署

- `LUA_BIN=… python scripts/test-all.py`：**87 / 87** 通过。
- `tests/hud-sidebar.test.js` 新增：商店网格折叠时不切换、布局出来时切到小精灵、再次折叠时还原。既有钱包用例的 0.25 秒定时器取用方式已在 UI55 改为"跑完当前这批"。
- 本机 addon 同步 3 个文件并单独编译 Panorama JS（`1 compiled, 0 failed`）；本机工坊包重打包并替换两份拷贝，备份见 `tests/results/ui56-shop-probe-workshop.json`。未改 Steam 清单、未上传远端、未启动或关闭 Dota。

## 待实机验收

重进地图后确认界面为 **56**，然后把控制台里那一行 `shop probe` 贴回来。四种可能：

- `gridPanel=yes` 且打开商店时打印 `native shop opened` → 探测成功，商店在选中英雄时应该也能点、能关；
- 三者都是 `missing`、`gridPanel=no` → 客户端既不暴露查询也没有该面板 id，两轮探测到此为止，改为面板内下单；
- 打开/关闭商店时没有任何 `native shop opened/closed` → 说明信号存在但没有随商店开合变化，需要换判据；
- 其余情况按打印出来的取值再定。
