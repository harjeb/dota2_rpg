# 原生岩石边界与树木隔断

地图源码位于 `content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap`，修复包 overlay 保存同一份二进制 VMAP。场地仍为两个相邻 1200×900 准备区，总计 2400×900。

安装器会备份并覆盖 VMAP；有自行编辑地图的 checkout 应先审查差异并在 Hammer 中合并，不能盲目覆盖。

## 坐标与不可见保护

| targetname | 坐标 | 用途 |
| --- | --- | --- |
| `rpg_arena_min` | `(-1200, -450, 128)` | 左下角 |
| `rpg_arena_max` | `(1200, 450, 128)` | 右上角 |
| `rpg_arena_center` | `(0, 0, 128)` | 中线中心 |

四个永久 `func_brush` 使用不可见 `materials/tools/toolsclip.vmat`，只承担物理边界，`Solidity = 2`：

| targetname | 中心 | 半尺寸 (X, Y, Z) |
| --- | --- | --- |
| `rpg_arena_wall_north` | `(0, 466, 384)` | `(1224, 16, 256)` |
| `rpg_arena_wall_south` | `(0, -466, 384)` | `(1224, 16, 256)` |
| `rpg_arena_wall_east` | `(1216, 0, 384)` | `(16, 466, 256)` |
| `rpg_arena_wall_west` | `(-1216, 0, 384)` | `(16, 466, 256)` |

四块 `materials/tools/nonavclip.vmat` 地面 slab 继续覆盖外边缘，禁止该处生成地面导航。不要用可见岩石的物理模型代替这些固定导航边界。

## 可见外围：原版岩石

外围使用 Dota 原版 `prop_static` 岩石，不再以 `materials/dev/primary_white.vmat` 几何墙作为外观。模型引用来源是本地原版地图 `C:/Temp/lanpang/content/test2/maps/dota.vmap`：

```text
models/props_rock/riveredge_rock_wall003a.vmdl
models/props_rock/riveredge_rock_wall002a.vmdl
```

外围共 28 个原版岩石 prop：南北边各 11 个，东西边各 3 个，模型碰撞关闭，由不可见边界统一保护。仓库没有新增自定义模型文件。离线检查只能证明 VMAP 引用了来源中存在的路径；无法验证当前游戏版本 VPK 中的模型、实际包围盒、朝向或渲染效果。需在 Hammer 中预览，必要时仅调整装饰岩石位置/旋转，不改变 marker 和不可见边界契约。

## 中间隔断：原生树木

已移除 `rpg_mid_gate_visual` 可见刷子。只保留覆盖 `x=-24~24`、`y=-450~450`、`z=128~640` 的 `rpg_mid_gate_nav` 不可见碰撞门。

| 阶段 | 树木 | nav 输入 |
| --- | --- | --- |
| 准备/结算 | 生成整条中线树木并补齐被砍的树 | `Enable`、`SetSolid` |
| 战斗 | 逐个砍掉并移除本控制器创建的树 | `SetNonsolid`、`Disable` |

`ArenaController:EnsureMiddleTrees()` 使用 `CreateTempTree`，默认在 `x=0`、`y=-426~426` 生成 10 棵树，相邻距离不超过 96。不会通过中心半径清树影响待命区或其他装饰；下一关重新生成，重复准备调用不叠加树木。

Lua 每 0.2 秒的越界纠正仅针对场上战斗单位。小精灵和待命英雄不注册进战场边界控制。

## 验证入口与限制

```text
python tests/vmap.test.py
python dota2_rpg_issue_fixes/tests/run_checks.py
pwsh -NoProfile -File tests/verify-addon.ps1
pwsh -NoProfile -File tests/compile-vmap.ps1
```

前两项是可在无 Dota 安装环境中执行的结构/模拟回归。`verify-addon.ps1` 也可运行离线部分，并明确报告跳过引擎转换；地图编译仍需要 Workshop Tools。本轮环境没有 `dmxconvert.exe` 和 `resourcecompiler.exe`，未完成重新编译，也没有部署或启动 Dota。

旧文档中 `19 compiled, 0 failed` 属于原几何墙地图的历史结果，不适用于本轮岩石地图。必须在 Workshop Tools 确认原生岩石无错误模型、准备阶段不能跨线、开战整条中线开放且双方能接敌、下一关树木/碰撞恢复、外围不能逃出，以及位移异常会被纠正。实机验收由 Beads `dota2_rpg-4rk` 跟踪。
