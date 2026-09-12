# UI51：普通客户端中的英雄装备购买

用户反馈 F1 无法选中小精灵，部分装备因此无法通过小精灵购买再转交。本版补上原生商店范围，让准备阶段选中的上阵或待命英雄可以继续使用原版商店购买，并沿用现有自动交付。

## 确认的缺口与修复

原实现开启 `SetUseUniversalShopMode(true)` 并发送 `dota_easybuy 1`。Valve API 对 Universal Shop 的说明明确要求 **any shop is in range**；它统一商品目录，不提供全图商店范围。当前地图没有定义商店触发区。安装版本 `server.dll` 对 `dota_easybuy` 的描述还包括免费购买及为其他英雄购买，因此不能把这个开关当成普通客户端的正式商店设施。

`issue_fixes/roster_access.lua` 现在使用安装版本公开的 `SpawnDOTAShopTriggerRadiusApproximate` 创建真实商店触发区，并调用 `SetShopType(DOTA_SHOP_HOME)`。中心 `(-768, 0, 128)`、半径 `4096` 覆盖战场、待命区及小精灵停靠位置。保留 Universal Shop，使该范围提供统一目录；不再发送 easy-buy 开关。

`issue_fixes/init.lua` 在安装时建立范围；`bootstrap.lua` 的实际 `RespawnPlayerRoster` 包装器在准备阵容时重用已有触发区，创建过早失败或实体被移除时允许重试。兼容入口 `IssueFixes:PrepareRoster` 也作同样处理。失败不阻断阵容初始化，打印明确日志；成功标记为 `NativeShopRange ready native-shop-range-v1`。

选择英雄、购买订单校验、原价与库存、合成、原生扣款核对和真实物品实体转交仍走现有商店流程。后台仍以 assigned hero 小精灵执行原生订单，保留购买时选中的收货英雄；玩家不必手动先选小精灵或再点转交。战斗阶段仍由服务端拒绝购买。魔晶保留既有的按目标英雄授予并扣款路径。

F1 本身没有被重新绑定，也没有更换玩家主英雄。小精灵的 `AddNoDraw()` 和隐藏位置已确认，但尚无证据证明它们是这次 F1 失效的直接原因。

## 验证

- `python scripts/test-all.py`：**87/87** 组通过。
- 新回归覆盖真实安装／准备入口、API 缺失、创建抛错／返回空、类型设置失败清理、后续重试、跨关复用、实体删除后重建，以及所有装备载体位置的范围覆盖。
- 既有 shop-state 回归覆盖上阵／待命英雄收货、原生扣款不重复、同名与堆叠物品身份、满格处理、余额不足及非准备阶段禁购。
- `test_runtime.lua ... live` 通过。旧 overlay 的完整 `run_checks.py` 在中立槽转交用例失败；用修改前 HEAD 的测试复现相同失败，追踪于 `dota2_rpg-f37d`，不记为通过。
- 未启动或关闭 Dota、执行游戏命令或截图。原生客户端的具体商品点击与近店状态仍待验收，因此这是针对已确认代码缺口的修复，尚未证明覆盖用户遇到的所有受限装备。

本机 addon 的三份 Lua 与双语版本标记已同步；路径和 SHA-256 见 `tests/results/ui51-native-shop-range-deploy.json`。本次不修改 Workshop 下载包、不上传远端；普通客户端需要重新打包并更新订阅内容后加载 UI51。

## 后续实机验收

准备阶段分别选中上阵与待命英雄，购买普通装备及原先受限的装备，确认原价只扣一次、同一物品自动进入所选英雄；尝试秘银锤、极限法球等组件及成件合成。背包满格、魔晶、连续切换购买目标另行验证。若仍被拒绝，记录商品名、提示文本和是否产生 `ShopTxn preflight`：没有订单日志意味着点击可能在原生界面资格校验阶段被拒绝；有日志则继续检查执行与交付。

实现：`dota2_rpg-o2ns`；原生验收：`dota2_rpg-81vx`。
