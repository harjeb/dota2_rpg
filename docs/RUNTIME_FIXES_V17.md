# v17：切换技能两阶段独立条件编辑

日期：2026-09-09。运行标记 `rpg-runtime-v17-20260909`，界面版本 17。

## 问题与行为

v13 的动作目录把所有 `IsHidden()` 技能过滤掉，导致原生切换技能只有当前显示的一半可选。上界重锤的 `dawnbreaker_converge`、烈火精灵的 `phoenix_launch_fire_spirit` 在准备阶段通常隐藏，因此无法提前设置条件。

`AbilityCatalog` 现在统一处理动作列表和 U21/U22 等条件的技能图标列表。经过核对的 22 组原生阶段技能中，只要英雄实际拥有一个可见成员，就列出该英雄实际拥有的其他成员。保留每个技能的原生名称；隐藏的第一阶段在第二阶段显示后仍可配置。整组隐藏的升级/命石技能不强行显示，不生成英雄未持有的技能，也继续过滤无关隐藏内部技能、天赋、占位技能；行动列表继续排除被动技能。

部分覆盖关系：

| 英雄 | 第一阶段 | 后续动作 |
| --- | --- | --- |
| 破晓晨星 | `dawnbreaker_celestial_hammer` | `dawnbreaker_converge` |
| 破晓晨星 | `dawnbreaker_solar_guardian` | `dawnbreaker_land` |
| 凤凰 | `phoenix_fire_spirits` | `phoenix_launch_fire_spirit` |
| 凤凰 | `phoenix_icarus_dive` | `phoenix_icarus_dive_stop` |
| 凤凰 | `phoenix_sun_ray` | `phoenix_sun_ray_stop`、`phoenix_sun_ray_toggle_move` |
| 帕克 | `puck_illusory_orb` | `puck_ethereal_jaunt` |
| 昆卡 | `kunkka_x_marks_the_spot` | `kunkka_return` |
| 远古冰魄 | `ancient_apparition_ice_blast` | `ancient_apparition_ice_blast_release` |

完整分组位于 `game/dota_addons/dota2_rpg/scripts/vscripts/tactics/ability_catalog.lua`，包含 45 个技能身份，已逐个核对 `data/native_skill_conditions.json` 存在对应原生定义。其他分组包括炼金术士、伐木机、巨牙海民、光之守卫、森海飞霞、獸、齐天大圣、娜迦海妖、噬魂鬼、拉比克、百戏大王、小小、艾欧、司夜刺客的阶段动作。

## 使用

准备阶段，在规则行点“＋”新增规则，点新行的技能图标，选择后续动作并打开“条件设置”。两个阶段可以各用一条规则，分别配置使用条件、目标和优先级。U21/U22 的技能图标也包含这两个动作，可引用第一阶段的使用时间。

默认规则生成策略保留当前行为。停止、返回等动作由玩家主动新增规则，避免自动生成无条件停止规则导致技能刚开始就被终止。编辑后的规则按技能名独立保存，原生技能交换位置不会把第二阶段改成第一阶段。已有条件不会被重写。

执行层仍检查原生学习等级、隐藏状态、激活状态、冷却、可施法状态及控制限制；可编辑不代表尚未激活的技能可以执行。没有修改原生技能交换、计时、冷却、伤害或升级逻辑。

## 验证与部署

- `tests/action-v2.test.lua`：上界重锤、烈火精灵、幻象法球两阶段提前配置、原生位置交换后的名称解析、手写条件保留；隐藏/禁用/未学习阶段仍拒绝执行；无关隐藏技能、整组隐藏与孤立隐藏成员不被误列出。
- `tests/condition-v2.test.lua`：真实服务端解码、校验、快照及重建验证两个阶段独立身份与引用条件；本项合计 195 个检查通过。
- `tests/condition-ui-v2.test.js`：真实 HUD 脚本和 XML 中点击新增规则、选择两个阶段图标、分别编辑、保存、刷新和重开；第一阶段条件与第二阶段引用分别保持。
- `python dota2_rpg_issue_fixes/tests/run_checks.py` 全部通过，包括 75 个 Lua 语法检查、主目录和 overlay 运行测试及既有行为/UI/数据/安装检查。
- `tests/verify-addon.ps1`、`git diff --check` 通过。独立只读复核未发现可执行修正项。

部署先完整备份，再运行安装器（不编译地图）。79 个源文件与安装目录逐字节一致；14 个既有编译资源保持不变。本次只变更 Lua 和版本本地化文本，无 Panorama 源码变更。

备份、部署日志及哈希清单：`C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_v17_5qk4ipv9`。地图 VPK 与部署前备份一致，SHA256：`981b81d32370ea9f5dfd22cefe5f3b433889ca4e045f4a30eeb50fb5d8cdac05`。

没有启动、关闭 Dota 或截图。离线模拟验证了配置与执行状态拦截，实际游戏中的技能句柄、图标和原生切换操作仍需用户重载到界面版本 17 后验证。
