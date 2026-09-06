# 紧凑战场 VMAP 部署后红线与闪退：静态事件记录

日期：2026-09-06

关联提交：`cfbce93295af82758ad3366814d1d0a831f8ec6e`

关联 Beads：`dota2_rpg-e1j`（P0，待后续调查）

## 范围与当前决定

本记录只固化已经观察到的现象、部署事实和静态证据，**不在本次提交中修复、回退或再次部署地图**。用户要求先保留问题原因文档；本次排查没有由 agent 启动 Dota 2 或 Workshop Tools 来复现/验证，现象来自用户自行启动后的报告。

部署前的完整 addon 备份仍保留在：

```text
C:\Users\harjeb\AppData\Local\Temp\dota2_rpg_predeploy_20260906_230956
```

其中旧运行时地图包为：

```text
game_dota2_rpg\maps\dota2_rpg_demo.vpk
```

## 用户报告的现象

部署新版 `dota2_rpg_demo.vpk` 后，用户启动本地 Dota 2 / Tools 进入地图时观察到：

- 模型显示异常，画面出现大量红线/错误资源外观；
- 随后客户端闪退。

本机留下了同一时段的新崩溃转储：

```text
C:\Program Files (x86)\Steam\dumps\crash_dota2.exe_20260906231643_1.dmp
```

文件大小为 `2,834,642` 字节，修改时间为 `2026-09-06T15:16:43Z`。

## 已完成的部署事实

已部署的 VMAP 源文件：

```text
C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\content\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vmap
```

它与仓库源文件逐字节一致，SHA-256 均为：

```text
a8522ab2fe281be7b2b14339009bffc2217e8505121b6683b8dbf8c7318f35b2
```

运行时地图包为：

```text
C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vpk
```

部署前旧包大小为 `3,033,048` 字节、SHA-256 为：

```text
c87bce4a8bbe75887299b4221785e975314d0d5fd1495f4d39bd818815af4b47
```

重新编译后包大小为 `3,078,659` 字节、SHA-256 为：

```text
e47df9ffb522d3dfe3f502049798b52b83b11be93ca0e36d03742303ace3cf41
```

首次尝试时 Dota 仍在运行，导致 VPK 写入失败；用户关闭 Dota 后，仅用 `resourcecompiler.exe` 重建地图，日志报告 `OK: 19 compiled, 0 failed`，并成功写入新的 VPK。该部署动作没有启动或停止 Dota 客户端。

## 静态证据

### 新地图包新增的资源引用

新 VPK 包含下列由本次 `func_brush` 几何生成的实体模型；旧 VPK 中没有这些条目：

```text
maps/dota2_rpg_demo/entities/rpg_arena_wall_east_107.vmdl
maps/dota2_rpg_demo/entities/rpg_arena_wall_north_103.vmdl
maps/dota2_rpg_demo/entities/rpg_arena_wall_south_105.vmdl
maps/dota2_rpg_demo/entities/rpg_arena_wall_west_109.vmdl
maps/dota2_rpg_demo/entities/rpg_mid_gate_nav_117.vmdl
maps/dota2_rpg_demo/entities/rpg_mid_gate_visual_115.vmdl
```

同一新 VPK 还引用了：

```text
materials/dev/primary_white.vmat
materials/tools/toolsclip.vmat
materials/tools/nonavclip.vmat
```

它们分别来自可见外墙/可见中线门、物理中线门和外围 NONAV slab。

### 编译期材质异常

`resourcecompiler` 虽然完成了 world、physics、visibility 和 gridnav 构建，但对新增可见墙材质反复输出了以下信息：

```text
No valid vcs file found for shader generic.vfx
CMaterial2::LoadShadersAndSetupModes(...): Error creating shader generic.vfx for material materials/dev/primary_white.vmat!
```

同一轮构建也对原地图已有的 `materials/dev/luminaire.vmat` 输出了相同类别的信息。`materials/tools/toolsclip.vmat` 与 `materials/tools/nonavclip.vmat` 是工具/阻挡材质；静态构建成功不等价于它们或 `materials/dev/primary_white.vmat` 在本地运行时渲染路径中可安全显示。

另外，在 loose `game/dota/` 目录中未找到上述三个材质对应的 `.vmat_c` 文件。该查询**不能证明资源在运行时不存在**，因为 Dota 的基础资源也可能封装在官方 VPK 中；但编译期 shader 报错与用户看到的红色错误几何相吻合，因而这是当前最强的渲染问题候选原因。

### 崩溃转储结论

对最新 minidump 的结构解析结果：

```text
Exception code: 0xC0000005（访问冲突）
Faulting module: particles.dll
Fault address: particles.dll + 0x1AE04C
Faulting thread: 19348
Runtime command line: `dota2.exe -addon dota2_rpg -tools -steam -perfectworld`
```

转储中没有可直接归因到 `rpg_arena_wall_*`、`rpg_mid_gate_*` 或具体材质名的符号化调用栈。当前机器未提供匹配的 Dota PDB/WinDbg 符号链，因此不能从此 dump 断言“某一个 VMAP 实体直接造成闪退”。

Steam dumps 目录中还存在多份早于本次部署的 `crash_dota2.exe` 转储。因此，时间上新版 VPK 与本次闪退相关，但现有证据不足以将 `particles.dll` 访问冲突唯一归因于本次地图改动。

### 独立的 Panorama 编译问题

完整执行 `scripts/install-addon.ps1 -Compile` 时还发现：

```text
issue_fixes_ui.xml: Found root panel with 'id' attribute, which is not permitted.
custom_ui_manifest.xml: Associate compile failed for issue_fixes_ui.xml
```

该问题已单独登记为 `dota2_rpg-4eh`。它发生在地图 VPK 成功编译之后；目前没有证据证明它是本次红线或 `particles.dll` 崩溃的原因，不能将二者混为同一根因。

## 原因判断（按证据强度）

| 判断 | 证据 | 结论边界 |
| --- | --- | --- |
| 新增墙/门使用的开发或工具材质存在运行时渲染兼容风险 | 新 VPK 首次引入三项材质引用；`primary_white.vmat` 在编译中出现 `generic.vfx` 创建错误；用户观察到红色错误几何 | **高度可疑，尚未通过引擎内复现或替换材质对照确认。** |
| 实际闪退是 `particles.dll` 中的访问冲突 | 最新 minidump 明确记录 `0xC0000005` 和模块地址 | **已确认崩溃落点，不代表已确认上游根因。** |
| 新地图改动是唯一闪退来源 | 仅有“部署后发生”的时间相关性 | **未证实。** 机器中有早期 Dota 崩溃转储，且 dump 未符号化到地图实体。 |
| Panorama 根 Panel 编译错误导致本次闪退 | 编译错误可稳定观察到 | **未证实且当前独立跟踪。** |

## 后续调查入口

后续工作统一在 Beads `dota2_rpg-e1j` 中跟踪。开始修复前，应保留上述旧 VPK 备份，并先在不影响当前可运行版本的隔离副本中完成下列取证：

- 对比使用已验证运行时材质的最小 `func_brush` 地图与当前三种新增材质的依赖和渲染结果；
- 为 dump 配置与当前 Dota 版本匹配的符号化工具链，确认 `particles.dll` 崩溃调用者；
- 将地图、Panorama 根布局和完整 addon 编译链分开验证，避免把独立故障误判为同一根因；
- 只有获得用户明确允许后，才由后续排查人员进行 Dota/Workshop Tools 中的实际启动、加载和回归测试。
