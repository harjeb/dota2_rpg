# UI57：选中英雄后原生商店无法关闭

用户在 UI56 反馈：`shop probe GameUI=threw Game=threw Players=threw gridPanel=yes`，随后显示 `shop state available; selection swap armed`，选中英雄后依然无法关闭商店。

## 原因与修复

直接读取安装版本 `dota/pak01_dir.vpk` 中的 `panorama/styles/hud/dota_hud_shop.vcss_c`，并用 Source2Viewer 解码对应 `dota_hud_shop.vxml_c`，确认：

- 原生根面板类型是 `DOTAHUDShop`；`GridMainShop` 位于它的子树中。
- 默认根样式是 `transform: translateX(mainPanelWidth); opacity: 0`；`DOTAHUDShop.ShopOpen` 才变为 `translateX(0px); opacity: 1`。
- `GridMainShop` 的 `visibility: collapse/visible` 由商店分类控制，与整个商店开关不是同一件事。关闭商店不会保证网格尺寸变为零，切换分类又可能让已打开商店的主网格折叠。

UI56 的尺寸判据因此无法可靠观察开关。UI57 从 `GridMainShop` 向上找到 `DOTAHUDShop`，直接读取其 `ShopOpen` 状态类；仅当根面板不可访问时才使用布尔查询 API，未知结果不触发选择切换。可访问的原生面板状态优先于 API 的过时结果。

另一个漏项是旧轮询只处理开关变化：商店保持打开时再选英雄不会重新切到小精灵。现在每次观察到打开都会检查头像，先同步该英雄的购买交付目标，再切到小精灵；关闭时还原最近选中的英雄。重复事件/轮询不会清掉还原目标，玩家在关闭期间自己改选的单位会保留，阶段变化和新一局会清掉旧还原状态。

诊断移除 `eval(namespace)`，直接访问命名空间。旧日志中的三个 `threw` 不能区分 `eval` 自身被禁用和原生函数抛错。新日志给出 `shopPanel=DOTAHUDShop source=ShopOpen-class`，仍记录 `native shop opened/closed`；HUD 延迟创建后会从不可用状态恢复。

## 验证与本机部署

- `LUA_BIN=... python scripts/test-all.py`：**87/87** 测试组通过。
- HUD 行为用例覆盖：关闭根仍有正尺寸网格、打开根但主分类网格为零、API 缺失/抛错/过时、禁用 eval、延迟创建 HUD、重复打开信号、打开期间换英雄及交付目标更新、关闭恢复最近英雄、保留手动改选、阶段与新局重置。
- 原生 Panorama 编译：**1 compiled, 0 failed**。
- UI 版本号更新为 **57**，已同步开发 addon 和两份本机工坊 VPK。工坊包 137 个条目，仅替换 HUD 编译脚本与中英文版本号共 3 个条目，其余内容逐字节保留；确认包内 Lua 与当前源码一致，包含既有 `commander_index` 交付支持。
- Source2Viewer `--vpk_verify`：**Success**；两份安装包哈希均与暂存包一致。备份与哈希见 [部署记录](../tests/results/ui57-shop-close-deploy.json) 和 [工坊包记录](../tests/results/ui57-shop-close-workshop.json)。

本轮没有启动/关闭 Dota、执行游戏指令或截图，也没有上传远端工坊。离线面板模拟与编译不能证明实际原生选择事件的时序。用户重新载入本机包、确认 **界面版本 57** 后，应验证：选英雄 → 开商店 → 关闭，以及商店开着时换另一名英雄 → 购买 → 关闭，物品应交付给最近所选英雄且关闭后还原该英雄。
