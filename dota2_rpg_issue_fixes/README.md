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

代码接口按当前仓库已验证的基础提交 `cab44ff6f252163351b8268d91cc82417a9df8eb` 组织。自动安装器不依赖固定行号，并会在当前 checkout 中创建备份。

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

第 9 项的实际地图几何已包含在 overlay：三枚边界 marker、四面永久 `func_brush` 外墙、四块 `nonavclip` slab，以及分离的 `rpg_mid_gate_visual` / `rpg_mid_gate_nav`。安装器会备份后覆盖目标 `dota2_rpg_demo.vmap`；若目标有自定义地图，应按 `integration/HAMMER_ARENA_SETUP.md` 手工合并而不是盲目覆盖。Lua 只保留中线开关、树木清理、移动订单限制和越界纠正作为逻辑/异常兜底。

## 验证

在本包根目录执行：

```bash
python tests/run_checks.py
```

还可在已安装 Dota 2 工具链但不启动客户端的环境中执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ../tests/compile-vmap.ps1
```

它会临时编译 VMAP 的 world/physics/gridnav 后清理生成物。静态测试不等于 Dota 2 引擎实测。Lua 检查优先使用 `texlua`，不可用时会自动使用已安装的 Python `lupa`；合并前仍需按 `integration/TEST_CHECKLIST.md` 在 Workshop Tools 中逐项回归。
