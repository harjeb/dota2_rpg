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

Both `rpg_mid_gate_visual` and `rpg_mid_gate_nav` are absent from the current VMAP. The former nav brush occupied `x=-24..24`, `y=-450..450`, `z=128..640` with `Solidity=2`, `AlwaysSolidIgnoreNav=0`, and `solidbsp=1`. Installed `game/core/base.fgd:1294-1311` defines this as always solid and participating in navigation generation. Toggling physical collision at runtime does not remove the authored navigation/height obstruction.

| Phase | Native trees | Legacy brush compatibility inputs |
| --- | --- | --- |
| Prepare/settle | Create the entire row and replace cut trees | `Disable`, then `SetNonsolid` |
| Fight | Cut each owned tree, then remove its handle | `Disable`, then `SetNonsolid` |

`ArenaController:EnsureMiddleTrees()` creates 10 temporary trees at `x=0`, `y=-426..426`, with gaps at most 96 units. Roots use the flat arena marker plane (`z=128`), not a ground query over the obsolete brush. Direct `OpenMiddleGate()` calls suspend repair even before the phase wrapper runs. Subsequent preparation recreates the row. Cleanup never clears unrelated trees by radius.

`python scripts/update-arena-map.py` removes only the obsolete brush and its private mesh graph, including when nested in a Hammer group, and syncs the binary source overlay. The operation is idempotent. Existing compiled VPKs must be rebuilt and the map reloaded; Lua-only deployment cannot repair baked grid navigation.

Lua 每 0.2 秒的越界纠正仅针对场上战斗单位。小精灵和待命英雄不注册进战场边界控制。

## 验证入口与限制

```text
python tests/vmap.test.py
python dota2_rpg_issue_fixes/tests/run_checks.py
pwsh -NoProfile -File tests/verify-addon.ps1
pwsh -NoProfile -File tests/compile-vmap.ps1
```

2026-09-07 evidence for this divider change (Beads `dota2_rpg-8lz`):

- The new map regression failed against the original source because `rpg_mid_gate_nav` was present. The new tree-height regression failed against the original runtime with a mocked ground height of 640; the fixed runtime uses marker height 128.
- `tests/vmap.test.py`: 10 passed, 1 optional external-model-provenance check skipped. Includes unchanged perimeter/terrain contracts, no middle brush or crossing collision mesh, typed-data preservation, nested-group migration, idempotence, and overlay byte equality.
- Lupa runtime tests and focused arena tree tests passed for both live and overlay modules. These are mocks, not engine navigation or rendering measurements.
- `tests/verify-addon.ps1` passed, including native DMX conversion.
- `tests/compile-vmap.ps1` passed an isolated static `resourcecompiler` build and wrote a 3,126,207-byte temporary VPK. The script removed its temporary outputs. No playable VPK was replaced and no Dota client was launched.

Static compilation does not prove that units cross the center or trees render at the correct height in-game. Rebuild/reload the playable map before user verification of preparation blocking, battle crossing, repeated stages, perimeter containment, and unrelated bench trees. In-engine acceptance is tracked by Beads `dota2_rpg-ef9` (the previously documented `dota2_rpg-4rk` is absent from the current database).
