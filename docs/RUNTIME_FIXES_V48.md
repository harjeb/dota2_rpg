# UI48：原生商店与顶部金币显示同步

用户反馈：购买装备后顶部余额正常扣除，原生商店按钮的余额不变。对应修复 `dota2_rpg-zxpk`。

## 已确认的显示路径

顶部 `WalletBalance` 由 `rpg_shop_state` 等服务器状态中的金币更新；服务器 `GetGoldBalance()` 从 `PlayerResource:GetGold(playerId)` 读取，购买、招募、卷轴与奖励已有统一钱包和防重复扣款逻辑。

本次用 Source 2 Viewer 20.0 从本机 Dota 的 `game/dota/pak01_dir.vpk` 只读解包并反编译 `panorama/layout/hud/dota_hud_quick_buy.vxml_c`，得到原生结构：

```xml
<Panel id="ShopCourierControls">
    <!-- ShopButtonContainer 包含下面的按钮 -->
    <Button id="ShopButton" onactivate="DOTAHUDToggleShop();">
        <Label id="GoldLabel" hittest="false"
               class="MonoNumbersFont ShopButtonValueLabel" text="{u:gold}" />
    </Button>
</Panel>
```

原生商店按钮的 `GoldLabel` 绑定 `{u:gold}`，项目的 `updateWalletLabel` 此前只写顶部 `WalletBalance`。两处显示更新路径独立，项目广播没有更新原生标签。旧记录 `RUNTIME_WALLET_RULES_2026-09-07.md` 也明确保留原生金币显示待验收。

这些资源证明了显示绑定，但不能证明引擎内部 `{u:gold}` 停留旧值的具体原因。多英雄所有权、网络字段或引擎刷新时机均没有本轮实机证据。本次没有据此改写英雄所有权或新增扣款。

## 修复

新增 `native_shop_wallet.js`，在同一个 `updateWalletLabel` 调用中将规范化的余额同时送到顶部和原生商店按钮。只查找 `ShopCourierControls → ShopButton → GoldLabel`，把该标签的文字改为权威余额字面值，解除这一个标签对原生 `gold` 对话变量的显示依赖。保留标签本身、原生样式和按钮点击、右键、提示事件。

每 0.25 秒检查一次原生控件，以便处理初次延迟创建、头像切换后的面板重建和引擎恢复旧文字；普通服务器余额更新会立即写入两处。没有收到余额时不主动写原生标签。缓存仅用于显示，不读取客户端购买事件推算扣款，也不写入服务器钱包。现有 run generation 检查仍在更新两处标签之前执行。

此次同步范围是商店按钮显示的总金币。原生金币详细提示、回购数据和物品可购买状态仍由引擎维护，完整原生商店验收继续由 `dota2_rpg-efs` 跟踪。

XML 在主 HUD 脚本之前加载同步模块；`scripts/install-addon.ps1` 已加入新 JS 的显式编译项。版本标识为 UI48。

## 验证与部署

- `scripts/test-all.py` 全部 **83/83** 通过，包含既有购买扣款、原生已扣款覆盖、防重复消费和出售退款回归。
- 执行实际 XML 加载顺序的 Panorama 测试新增原生按钮结构：500→360→220→0 的购买序列、70 出售退款、1045 奖励、延迟控件创建、旧文字恢复、面板替换、新局重置和过期代次拒绝；验证顶部与商店数字一致，按钮回调和标签样式仍保留。
- 两个旧测试环境把所有延时回调同步执行，新增常驻监测暴露其递归问题；已让 0.25 秒计时进入待执行队列。针对钱包的测试显式推进该队列。
- 原生编译 HUD XML、HUD JS 和钱包 JS 成功；5 个安装源文件 SHA256 与仓库一致。报告：`tests/results/ui48-wallet-deploy.json`。
- 备份：`C:/Users/harjeb/AppData/Local/Temp/rpg-ui48-wallet-backup-20260912-173448`。

未启动、关闭或重载 Dota，未执行游戏操作或截图。只读日志连接被本地 29000 端口拒绝；因此本轮没有游戏内显示验收。需重新进入地图加载 UI48，确认连续购买、出售与切换英雄时两处余额实际一致。
