# `harjeb/dota2_rpg` 当前 issue 修复包

目标：只处理 `issue.txt` 中列出的 10 项，不增加新玩法，也不改动 EXP、GOLD、招募、存档、羁绊、词缀或关卡奖励。

## 当前交付方式

本包随仓库源码一同提交，既可作为已合并修复的可复现记录，也可用于兼容 checkout 的保守安装。本包提供：

- 可直接复制进项目的 Lua、Panorama 和 Modifier 文件；
- 会备份原文件的自动安装器；
- 对现有 `addon_game_mode.lua` 的兼容 bootstrap；
- 已完成的 2400×900 VMAP 外墙、中线门和导航阻挡，以及 Hammer 合并说明；
- 静态检查和模拟单元测试；
- 可直接用于 PR 的标题、正文和提交信息。

初版代码接口基于 `cab44ff6f252163351b8268d91cc82417a9df8eb`。本轮核查发现仅安装 helper 不足以修好实际接线，因此主仓库还修改了主 HUD、技能等级/技能点快照、原生订单回调、RuleService 行数裁剪及战术桥缓存。overlay 不会覆盖目标的整份主 HUD/addon；移植到旧 checkout 时必须合并这些主文件修改，参见 `../docs/ISSUE_FIX_IMPLEMENTATION.md` 和 integration 说明。自动安装器完成不代表十项实机验收通过。

## 一键应用

```bash
python3 tools/apply_issue_fixes.py /path/to/dota2_rpg \
  --expected-head cab44ff
```

安装器会：

1. 复制 `overlay/` 到仓库对应路径（包括已写入战场实体的 `dota2_rpg_demo.vmap`）；
2. 备份并替换已有文件；若目标已有地图，也会先备份再覆盖；
3. 备份并替换 `tactics/order_filter.lua`；
4. 在 `custom_ui_manifest.xml` 加载 UI 修复层；
5. 在 `addon_game_mode.lua` 末尾安装 compatibility bootstrap；
6. 只在准备/待命类 modifier 中移除 `STUNNED`、`COMMAND_RESTRICTED` 状态；
7. 运行 Lua、JavaScript、XML 静态检查；
8. 在目标仓库生成 `ISSUE_FIX_APPLY_RESULT.md`。

先预览而不写文件：

```bash
python tools/apply_issue_fixes.py /path/to/dota2_rpg --dry-run
```

## 修复文件总览

| Issue | 主要文件 |
| --- | --- |
| 1 小精灵转交后装备丢失 | `issue_fixes/inventory_transfer.lua` |
| 2 准备区/场上无法升级技能 | `issue_fixes/roster_access.lua`、`modifier_rpg_prepare_bench.lua`、`tactics/order_filter.lua` |
| 3 默认条件强制排满 | `issue_fixes/default_rules.lua`、`issue_fixes_ui.js` |
| 4 敌人开战不主动攻击 | `issue_fixes/enemy_runtime.lua`、`tactics/order_filter.lua` |
| 5 第 1/2 关敌人重复 | `issue_fixes/level_uniqueness.lua` |
| 6 敌方逻辑固定三英雄 | `issue_fixes/enemy_runtime.lua`、`issue_fixes/compat.lua` |
| 7 最小化按钮异常 | `issue_fixes_ui.js`、`issue_fixes_ui.css` |
| 8 英雄商店遮挡画面 | `issue_fixes_ui.css` |
| 9 两个正方形组成矩形战场 | `issue_fixes/arena_controller.lua`、`overlay/content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap`、`integration/HAMMER_ARENA_SETUP.md` |
| 10 原版商店无法购买 | `issue_fixes/roster_access.lua`、`tactics/order_filter.lua` |

## 不能只靠源码完成的部分

第 9 项现为原版岩石可见外围、四面不可见碰撞边界、四块 `nonavclip` slab 和 `rpg_mid_gate_nav`。已移除可见中线几何；Lua 使用原生临时树木在准备阶段形成整条隔断，开战移除、下一关恢复。安装器会备份后覆盖 VMAP；自定义地图请按 `integration/HAMMER_ARENA_SETUP.md` 合并。当前环境没有 Dota 编译器，岩石模型的实机显示、尺寸和导航尚待验收，不能沿用旧几何墙的历史编译成功记录。

## 验证

在本包根目录执行：

```bash
python tests/run_checks.py
python ../tests/vmap.test.py
```

统一回归入口会同时测试同一 checkout 的 live 源码与 overlay；不适用于脱离主仓库的旧独立 ZIP。

还可在已安装 Dota 2 工具链但不启动客户端的环境中执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ../tests/compile-vmap.ps1
```

它会临时编译 VMAP 的 world/physics/gridnav 后清理生成物。静态测试不等于 Dota 2 引擎实测。Lua 检查优先使用 `texlua`，不可用时会自动使用已安装的 Python `lupa`；合并前仍需按 `integration/TEST_CHECKLIST.md` 在 Workshop Tools 中逐项回归。
