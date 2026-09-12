# UI55：改用引擎查询判断商店是否打开

UI54 让 HUD 监听 `DOTAHUDShopOpened` / `DOTAHUDShopClosed`，在商店打开期间临时选中小精灵。用户实机反馈：**打开商店时选中没有切换**，说明这两个原生事件没有派发（它们在 `client.dll` 里只有名字，没有实机触发记录）。

## 修改

`rpg_demo_hud.js` 改为主判定 = **轮询引擎自带的查询接口**。安装版本的 `client.dll` 里有这样一条 API 描述：

> Ask whether the in game shop is open.
> IsShopOpen

因此每 0.25 秒（仅准备阶段）查询一次 `GameUI.IsShopOpen()`，缺失时退回 `Players.IsShopOpen()`；状态从关到开执行 UI54 的切换逻辑，从开到关执行还原逻辑。原生事件订阅保留作为补充信号，不再依赖它。

诊断：首次查询成功会打印 `[Dota2Rpg] shop open query available; selection swap armed`；接口缺失则打印 `shop open query unavailable; selection swap disabled`，两者都通过 `$.Msg` 进游戏控制台。这样即使这次仍然不生效，也能立刻区分"接口不存在"和"接口存在但切换没成功"。

版本号同时从 54 提到 **55**：此前 UI53/UI54 的代码部署了但版本号没动，用户按约定看这个标签判断包有没有换，所以这次必须跟着改。

## 验证与部署

- `LUA_BIN=… python scripts/test-all.py`：**87 / 87** 测试组通过。
- `tests/hud-sidebar.test.js` 新增轮询用例：商店关闭时不切换、打开时切到小精灵、关闭时还原、已选中精灵不重复切换、接口缺失时不做任何动作也不抛错。
- 该文件既有的钱包同步用例原本用 `walletTimers.shift()` 取"下一个 0.25 秒回调"，现在 0.25 秒回调里多了商店轮询，改为一次性跑完当前这批（语义仍是"一次刷新"）。
- 本机 addon 同步 4 个文件，Panorama JS 单独编译通过（`1 compiled, 0 failed`）；本机工坊包重打包 4 个差异条目并替换两份拷贝，备份见 `tests/results/ui55-shop-open-poll-workshop.json`。没有修改 Steam 清单、没有上传远端、没有启动或关闭 Dota。

## 待实机验收

重进地图后先确认界面显示 **55**，再点一个上阵英雄 → 打开原版商店：

- 选中自动变成小精灵 → 说明轮询生效，接着点购买、关商店，确认物品进了那个英雄且关闭后选中切回英雄。
- 控制台出现 `shop open query unavailable` → 说明这个 API 在普通客户端不可用，两条客户端路径都断了，下一步只能改成项目面板内下单（服务端自己发 `PURCHASE_ITEM`）。
- 出现 `available` 但选中仍不切换 → 说明 `GameUI.SelectUnit` 在商店打开时被引擎忽略，需要换一种改选方式。
