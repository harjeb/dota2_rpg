# 已落地的 Hammer 紧凑矩形战场

第 9 项的地图内容已写入仓库和修复包中的：

```text
content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap
```

地图使用两个相邻的 **1200×900** 准备区，整体为 **2400×900**。Lua 仍保留越界纠正作为异常兜底；正常移动、寻路和中线切换由以下 VMAP 几何负责。

> 自动安装器现在会备份并复制该 VMAP。对有自行编辑地图的 checkout，应先保留备份或在 Hammer 中手工合并下列实体，而不是忽略地图冲突。

## 坐标契约

地面 Z 为 `128`；Lua 读取的标记已经实际写入地图：

| targetname | 坐标 | 用途 |
| --- | --- | --- |
| `rpg_arena_min` | `(-1200, -450, 128)` | 整体左下角 |
| `rpg_arena_max` | `(1200, 450, 128)` | 整体右上角 |
| `rpg_arena_center` | `(0, 0, 128)` | 中线和攻击移动目标 |

因此当前 Lua 的 X 轴左右划分为：

```text
我方准备区：x -1200 ~ 0，y -450 ~ 450
敌方准备区：x     0 ~ 1200，y -450 ~ 450
```

若在 Hammer 中整体平移或旋转这些元素，必须同步改动 `ArenaController:BoundsForUnit()`、出生点和准备期订单钳制；不能只移动其中一个 marker。

## 永久外墙与导航阻挡

四个永久 `func_brush` 墙同时是可见边界与物理碰撞体，均为 `Solidity = 2`，使用 `materials/dev/primary_white.vmat`，其内侧面恰好落在 2400×900 矩形边缘：

| targetname | 中心 | 半尺寸 (X, Y, Z) | 内侧边缘 |
| --- | --- | --- | --- |
| `rpg_arena_wall_north` | `(0, 466, 384)` | `(1224, 16, 256)` | `y = 450` |
| `rpg_arena_wall_south` | `(0, -466, 384)` | `(1224, 16, 256)` | `y = -450` |
| `rpg_arena_wall_east` | `(1216, 0, 384)` | `(16, 466, 256)` | `x = 1200` |
| `rpg_arena_wall_west` | `(-1216, 0, 384)` | `(16, 466, 256)` | `x = -1200` |

四块独立的 `CMapMesh` 地面 slab 使用 `materials/tools/nonavclip.vmat`，在 `z = 96~160` 覆盖四条外边缘。这让地面单位的导航网格在物理墙处停止生成，而不是仅依靠 0.2 秒 Lua 拉回。不要删除或以普通可视模型替换这些 NONAV slab。

## 可重复开关的中线门

中线采用**视觉和物理/导航分离**的两个 `func_brush`，都覆盖 `x = -24~24`、`y = -450~450`、`z = 128~640`：

| targetname | 材质 | Solidity | 职责 |
| --- | --- | --- | --- |
| `rpg_mid_gate_visual` | `materials/dev/primary_white.vmat` | `1`（Never Solid） | 蓝色可见中线门 |
| `rpg_mid_gate_nav` | `materials/tools/toolsclip.vmat` | `2`（Always Solid） | 不可见的物理和导航阻挡 |

`ArenaController` 对它们保留共同的 `Enable` / `Disable` 调用，并针对实际 `func_brush` 再发出以下输入，避免仅隐藏视觉或仅改变碰撞：

| 阶段 | visual | nav |
| --- | --- | --- |
| 准备/结算（关门） | `Enable`，`Alpha 255` | `Enable`，`SetSolid` |
| 开战（开门） | `Alpha 0`，`Disable` | `SetNonsolid`，`Disable` |

树墙仍可作为额外装饰，开战时会被清除；它们不是可恢复的边界机制。

## 静态验证记录

本次修改通过以下**未启动 Dota 客户端**的检查：

1. `dmxconvert`：VMAP KeyValues2 → binary → KeyValues2 往返成功；
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/compile-vmap.ps1`：临时副本成功构建 world、physics 和 gridnav，`19 compiled, 0 failed`；脚本会清理测试 VPK 和临时资源，构建日志确认生成四面墙和两个中线门实体；
3. `tests/verify-addon.ps1`：验证三 marker、四面永久 `func_brush`、两个门及四块 `nonavclip` slab 的 targetname、材质、位置、缩放和 Solidity 契约。

这些是结构/编译验证，不等价于引擎内行为验证。

## 仍需在 Workshop Tools 验收

在允许启动 Dota 2/Workshop Tools 时，按 `TEST_CHECKLIST.md` 验收：准备阶段不能跨中线、开战 visual/nav 同步打开、双方能直接接敌、外圈不可穿越、位移越界会被 Lua 兜底拉回，以及下一关中线门恢复。本次工作按要求**没有启动 Dota 2 进行实机测试**。
