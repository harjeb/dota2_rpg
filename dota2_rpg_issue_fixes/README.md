# `harjeb/dota2_rpg` 当前 issue 修复包

目标：只处理 `issue.txt` 中列出的 10 项，不增加新玩法，也不改动 EXP、GOLD、招募、存档、羁绊、词缀或关卡奖励。

## 当前交付方式

本包随仓库源码一同提交，既可作为已合并修复的可复现记录，也可用于兼容 checkout 的保守安装。本包提供：

- 可直接复制进项目的 Lua、Panorama 和 Modifier 文件；
- 会备份原文件的自动安装器；
- 对现有 `addon_game_mode.lua` 的兼容 bootstrap；
- 必须在 Hammer 中完成的矩形战场实体说明；
- 静态检查和模拟单元测试；
- 可直接用于 PR 的标题、正文和提交信息。

代码接口按当前仓库已验证的基础提交 `cab44ff6f252163351b8268d91cc82417a9df8eb` 组织。自动安装器不依赖固定行号，并会在当前 checkout 中创建备份。

## 一键应用

```bash
python3 tools/apply_issue_fixes.py /path/to/dota2_rpg \
  --expected-head cab44ff
```

安装器会：

1. 复制 `overlay/` 到仓库对应路径；
2. 备份并替换 `tactics/order_filter.lua`；
3. 在 `custom_ui_manifest.xml` 加载 UI 修复层；
4. 在 `addon_game_mode.lua` 末尾安装 compatibility bootstrap；
5. 只在准备/待命类 modifier 中移除 `STUNNED`、`COMMAND_RESTRICTED` 状态；
6. 运行 Lua、JavaScript、XML 静态检查；
7. 在目标仓库生成 `ISSUE_FIX_APPLY_RESULT.md`。

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
| 9 两个正方形组成矩形战场 | `issue_fixes/arena_controller.lua`、`integration/HAMMER_ARENA_SETUP.md` |
| 10 原版商店无法购买 | `issue_fixes/roster_access.lua`、`tactics/order_filter.lua` |

## 不能只靠源码完成的部分

第 9 项包含地图几何与导航阻挡。Lua 已实现中线门开关、树木清理、移动订单限制和越界纠正，但外墙、出生区域和中线门实体必须在实际 `.vmap` 中按 `integration/HAMMER_ARENA_SETUP.md` 放置并重新构建地图。

## 验证

在本包根目录执行：

```bash
python tests/run_checks.py
```

静态测试不等于 Dota 2 引擎实测。Lua 检查优先使用 `texlua`，不可用时会自动使用已安装的 Python `lupa`；合并前仍需按 `integration/TEST_CHECKLIST.md` 在 Workshop Tools 中逐项回归。
