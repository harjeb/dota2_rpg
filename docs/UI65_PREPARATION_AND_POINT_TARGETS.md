# UI65：准备阶段状态与点地技能目标

## 行为

- 不朽尸王：`setup` 时清除原生先天 `undying_ceaseless_dirge` 的冷却；英雄准备完成时立即处理，并由准备阶段 tick 重试，覆盖延迟初始化、上阵、替补及保留的英雄。战斗中不刷新冷却，不改原生复活与战斗冷却机制。
- 墓碑／小僵尸：原生 1–5 级墓碑及两种僵尸单独登记，仅用于清理，不接管战斗 AI。离开战斗后先移除墓碑，再移除僵尸；原生实体类别查询补抓丢失生成事件、无 owner 和远处残留单位。后续非战斗 tick 继续清理延迟生成物。
- 影魔：准备阶段将现有原生 `modifier_nevermore_necromastery` 填至原生当前魂上限，优先读取 `current_max_souls_tooltip`，回退到解析后的 `necromastery_max_souls`。不写死魂数，不替换原生 modifier，战斗中不补魂。
- 指挥官小精灵：专用隐藏、不可驱散、永久且死亡不移除的缴械 modifier。只给 `placeholderHero` 指挥官实体，不影响招募的 Io。保持原来的沉默和无敌机制。
- 点地技能：保留目标面板已有的我方／敌方选择，新增点地专用说明，并修正 point+self 模式误用单位施法过滤的问题。所选单位只是施法位置参照，不改变技能实际影响阵营；原生落点过滤仍生效，敌方单体技能不能因此对友军施放。

猛犸示例：巨角冲撞 → 目标 → 我方 → 增加“目标是英雄”，再用条件／优先级选队友位置。实际冲刺距离、路径与能否带到敌人仍由原生技能决定。

## 验证与部署（2026-09-13）

- 完整离线回归 **102/102**，包含全部 Lua / Panorama 语法检查。使用 Lua 5.1、原生 API 替身及 Node Panorama 替身，不等同于游戏实测。
- 新增 `undying-preparation.test.lua`、`nevermore-preparation.test.lua`、`commander-disarm.test.lua`、`point-anchor-targets.test.lua`；扩展能力 UI 测试并更新三个测试加载器。
- 原生 VPK 只读取证确认尸王先天 480 秒 CD、墓碑／僵尸名称及类别，影魔当前基础上限 20 和 +5 天赋；没有操控游戏。
- 本机安装 9 个变更的 addon 源文件，逐文件字节一致。中英文 locale 均为 **UI65** 且与仓库一致。
- `condition_catalog.js` 使用 Dota `resourcecompiler.exe` 编译成功：1 compiled、0 failed，生成 `condition_catalog.vjs_c`。
- 安装备份及校验清单：`%TEMP%/dota2-rpg-idkx-t4x9w6n0/`。
- 离线完整报告：`%TEMP%/dota2-rpg-idkx-regression.json`。保留原有未提交报告、验证脚本及临时文件未改动。

尚需用户自行重载地图，在 UI65 下验证尸王首轮先天可用、退出战斗后无墓碑／小僵尸、影魔准备满魂及天赋上限、小精灵不会普攻，以及猛犸以队友位置为目标的实际冲刺。未启动、停止或发送游戏指令。
