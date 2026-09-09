# 当前关卡配置表导出

`python scripts/export-level-configuration.py` 从运行时实际读取的：

```text
game/dota_addons/dota2_rpg/scripts/data/levels.kv
```

生成到 `exports/level_configuration_current/`：

- `当前关卡配置.xlsx`：可筛选 Excel 工作簿。
- `关卡总览.csv`：每关奖励、推荐等级、时间、倍率、战利品与敌方数量。
- `单位明细.csv`：每个 `levels/<chXX>/enemies/<N>` 配置行的单位、数量、等级、AI、标签、普通强化、Boss 强化及装备 1–5（中文名和原生 ID 并列）。
- `装备明细.csv`：一件装备一行，便于按关卡、英雄、槽位、中文名或物品 ID 过滤。
- `单位出现汇总.csv`：单位出现次数、累计刷出数、等级范围与 Boss 关卡。
- `源文件差异.csv`：只读显示 `levels.kv` 与维护用 `levels_v07.json` 的差异。
- `导出清单.json`：输入文件 SHA256、行数与生成文件清单。

Excel 内也有同名工作表及“说明”页。所有单位和装备均保留原生 ID，便于精确定位回 KV。Excel/CSV 是审阅快照，**编辑它们不会改变游戏**；需要调整时编辑 `levels.kv`，并根据维护策略同步 `levels_v07.json`，再运行导出工具。

## 当前校验状态

本次导出包含 30 关、139 条敌方配置、343 条装备槽、73 种单位及 61 种实际出现装备。61 个装备中文名已按当前 Dota 简体中文物品本地化核对并嵌入工具；原生 ID 不被替换。`item_halberd` 是当前 KV 中的兼容旧 ID，表中显示“天堂之戟（兼容旧 ID）”。工具刻意不让旧 JSON 覆盖运行时 KV。当前 `源文件差异` 中有 93 项，均为英雄 `level`：运行时 KV 是逐关等级，`levels_v07.json` 的这些英雄行仍为 30。此差异需要单独决定是否同步，不能在不经确认的情况下用其中一份覆盖另一份。

导出脚本和 `tests/export-level-configuration.test.py` 约束上述行数、关键单位/Boss 数值、Excel 过滤表、UTF-8 BOM CSV、运行时哈希及差异可见性。该工具不启动、停止 Dota，也不作实机平衡结论。
