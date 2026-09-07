# 本轮核查验证报告

权威实现说明：`../docs/ISSUE_FIX_IMPLEMENTATION.md`。本轮不是重复确认初版 helper 测试，而是增加实际 addon、主 HUD、战术桥和地图的接线验证。

## 已通过

`python dota2_rpg_issue_fixes/tests/run_checks.py`：

- 48 个 live/overlay Lua 文件语法检查。
- overlay 与 live 两轮运行时回归，包括真实 addon 方法和战术桥初始化。
- 转交同一物品实体、满载/拒绝/异常回滚、来源归属、背包空位、原版购买归属与物品订单校验。
- 待命英雄手动技能点、技能等级及未用点数恢复、升级增量。
- 单条普攻默认、规则数量裁剪、开战重置不清空玩家规则。
- 当前关 `dataLoader/currentLevelId`、实际 `battleManager.teamHeroes`、entry AI 绑定、战术订单优先级、拒绝开战不误启动 AI。
- 中线整条原生树木、准备期补树、开战全部清理、下一关恢复、不清理其他场景树木。
- 主 HUD 实际行数、动作菜单、收起接线、透明商店、JS 语法、XML 解析及根 Panel 不得有 id 的 Panorama 约束。
- 安装器备份、幂等性及地图 overlay 一致性。

`python tests/vmap.test.py` 使用附带的 MIT DMX 解析器离线检查二进制地图：原生岩石引用、无可见中线刷子、不可见碰撞墙、NONAV、marker、变换、序列化往返和 overlay 一致性。带 `--native-map C:/Temp/lanpang/content/test2/maps/dota.vmap` 的来源复核为 10/10 通过；无外部原版地图时仅跳过来源复核一项。

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/verify-addon.ps1` 的源码/离线结构检查通过，并明确报告引擎转换不可用。

## 未完成的引擎验证

本轮机器没有 Dota 2 安装或 `resourcecompiler.exe` / `dmxconvert.exe`。地图编译检查已尝试但因工具缺失无法完成。没有部署、启动客户端、Panorama 截图或真实导航/物品测试。

旧报告的 `19 compiled, 0 failed` 是旧版几何墙地图的历史结果，不适用于本轮原生岩石地图，也不证明历史 `particles.dll` 崩溃已解决。

需要在 Workshop Tools 验证岩石实际尺寸/朝向/资源显示、完整中线树木与碰撞门的重复开关、双方寻路接敌、外围/位移碰撞、原版商店/合成/堆叠、技能按钮及实际 Panorama 尺寸。后续任务为 Beads `dota2_rpg-4rk`。

## 修复包边界

主 checkout 已包含主 HUD、技能快照、RuleService 和 tactic bridge 接线修改。独立 overlay 只复制自有 helper、modifier、order filter 和 VMAP，不整份覆盖目标主 HUD/addon。移植时必须同时合并 integration 文档列出的主源码改动；不能把 overlay 安装成功等同于本轮全部功能已合并。
