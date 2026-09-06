# Dota2 RPG issue 修复安装结果

本次只处理 issue.txt 中的 10 项，不修改 EXP、GOLD、招募价格、存档、羁绊或词缀。

后续按使用反馈将第 9 项战场回退边界从 3200×1600 收紧为 **2400×900**（左右各 1200×900，略大于原 1040×760 待命区）；对应出生点、中线树障、准备期落点钳制和 Hammer 说明已同步。

## 新增文件
- `content/dota_addons/dota2_rpg/panorama/layout/custom_game/issue_fixes_ui.xml`
- `content/dota_addons/dota2_rpg/panorama/scripts/custom_game/issue_fixes_ui.js`
- `content/dota_addons/dota2_rpg/panorama/styles/custom_game/issue_fixes_ui.css`
- `docs/ISSUE_FIX_IMPLEMENTATION.md`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/arena_controller.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/bootstrap.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/compat.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/default_rules.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/enemy_runtime.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/init.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/inventory_transfer.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/level_uniqueness.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/roster_access.lua`
- `game/dota_addons/dota2_rpg/scripts/vscripts/modifiers/modifier_rpg_prepare_bench.lua`

## 覆盖文件（原文件已备份）
- `game/dota_addons/dota2_rpg/scripts/vscripts/tactics/order_filter.lua`

## 自动修改文件
- `content/dota_addons/dota2_rpg/panorama/layout/custom_game/custom_ui_manifest.xml`
- `game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua`

## 检查
- Panorama JavaScript 语法检查通过
- Panorama XML 解析通过

## 仍需 Dota 2 Tools 实机检查
- 小精灵转交普通装备、可叠加物品和会自动合成的组件。
- 等待区英雄和场上英雄在准备阶段使用原版升级按钮。
- 两类英雄通过原版商店购买后，物品进入当前选中英雄物品栏/背包。
- 当前关实际敌人进入 FIGHT 后主动攻击，且不再引用固定三英雄列表。
- Hammer 中线门和外墙导航阻挡是否与地图实体名一致。
- 若现有 UI 的 Panel ID 不在自动候选中，按 integration/PANORAMA_INTEGRATION.md 显式绑定。

## 警告
- 安装时 HEAD 为 cab44ff6f252163351b8268d91cc82417a9df8eb，与当时修复包期望的 638e272 不同；已使用兼容补丁方式，而非行号补丁。当前包文档已改以 cab44ff 为已验证基础。
- 安装时未找到 texlua，跳过 Lua 语法检查；后续已通过 Lupa 完成 Lua 模拟验证。

备份目录：`.rpg_issue_fix_backup/20260906_195418`
