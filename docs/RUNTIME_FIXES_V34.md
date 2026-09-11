# UI34：尸王噬魂目标修复与条件按钮高度

尸王的二技能规则保存成功，且自身血量低于阈值后仍被 `no_legal_target` 拦截。原因是噬魂的原生目标阵营和类型均为 CUSTOM；通用 `UnitFilter` 不能直接解释这两个特殊值，会把自身和友军判为 `UF_FAIL_FRIENDLY`。本次为 `undying_soul_rip` 增加限定的目标掩码转换，选目标、最终订单检查及界面能力描述共用该转换。

修复追踪：beads `dota2_rpg-t74`；重载后的原生治疗验收记录在 `dota2_rpg-80w`。用户追加的条件设置按钮高度调整记录在 `dota2_rpg-650`：移除可靠性更新中 52px 的覆盖，恢复 36px；上下内边距改为 1px，主标题行 17px、诊断行 13px，保留诊断提示和按钮行为。

## 日志和原生查询

本机 VConsole TCP 29000 抓取现存历史 22,693 条消息，原始记录为 `C:/Users/harjeb/AppData/Local/Temp/rpg_undying_console_20260911.log`。运行标识仍是 `rpg-runtime-v32-20260910`；磁盘上上一轮安装的 UI33 尚未出现新的运行启动标识。

| 游戏时间 | 证据 |
| --- | --- |
| 2990.30 | 英雄 252 的规则 2 保存成功：`undying_soul_rip`，`target_team=ally`，`self_hp_pct_lte=0.8`，最近优先，无目标硬筛选。原始日志第 32555 行为成功回复。 |
| 2995.87、3000.87 | 因 `use_condition_failed:self_hp_pct_lte` 跳过。 |
| 3001.87–3011.87 | 条件通过后，规则 2 每隔约 5 秒记录 `no_legal_target`，未提交噬魂订单。 |
| 3034.00 | 英雄 352 的规则 2 保存成功，目标改为 `self`，其余条件相同。原始日志第 33688 行为成功回复。 |
| 3042.67–3052.67 | 自身目标同样因 `no_legal_target` 跳过。 |
| 3083.67–3093.67 | 重置后的英雄 483 保留规则，仍是相同拒绝原因。 |

使用临时 Lua 脚本只读取现有英雄和技能 API，没有提交施法订单、修改血量/规则或重启地图。查询脚本已从安装目录移除；查询源码留在本机 Temp。首次直接 `script` 控制台查询不可用，未执行 Lua，之后通过独立临时脚本 `script_reload_code` 完成读取。

原生输出保存在 `C:/Users/harjeb/AppData/Local/Temp/rpg_soul_rip_native_state_20260911.log`：

```text
[SoulRipState] invulnerable=true outOfGame=false allowInvulnerableProbe=true:0 UF_FAIL_INVULNERABLE=18
[SoulRip] hero=338 hp=2825/2825 team=4 type=128 flags=0 castfilter=absent rawfilter=true:1 normalfilter=true:18 UF_SUCCESS=0 UF_FAIL_FRIENDLY=1
```

此时英雄处于准备阶段无敌状态。CUSTOM 原始掩码返回 1（不允许友军）；转换为 BOTH / HERO+BASIC 后返回 18（不允许无敌目标），表明阵营错误已解除，原生保护仍生效。仅在只读 `UnitFilter` 对照查询中加入允许无敌的 flag，结果为 0；修复代码不增加该 flag，也没有解除英雄无敌。准备阶段查询不等于实战施法或回血验证。

## 修改边界

- live 与 overlay 的 `tactics/native_targeting.lua` 均增加噬魂的精确技能名。
- 仅转换恰好为 CUSTOM 的字段：阵营 → BOTH，类型 → HERO+BASIC；正常目标元数据与原生 flags 保持原值。可调用的 `CastFilterResultTarget` 仍可拒绝目标。
- 噬魂允许自身成为普通候选；幻影突袭的禁止自身规则仍仅属于幻影突袭。其他未审核 CUSTOM 技能不变。
- 使用条件、目标硬筛选、距离、冷却、魔法/充能与原生状态保护不变。`self_hp_pct_lte=0.8` 检查的是施法者血量；若要挑受伤队友，应另外配置目标血量筛选或优先级。
- 本次覆盖普通英雄/基础单位目标，不扩展到任意建筑或墓碑特殊目标，不更改噬魂原生治疗量、范围取魂或墓碑机制，也不把专属机制标记为已实现。

## 验证与使用

新增 `tests/soul-rip.test.lua` 从日志中的扁平规则解码，经真实战术引擎和最终动作适配器捕获订单。旧实现在自身血量恰好 80% 时以 `no_legal_target` 失败；修复后通过。覆盖友方含自身、排除自身后选队友、敌方/双方普通单位、HP 阈值语义、无敌/死亡/无效目标、建筑拒绝、原生 flags、自定义过滤失败/异常、射程、冷却/未学习/不可施法、普通元数据、未知 CUSTOM 以及界面能力描述。

`python scripts/test-all.py` **65/65 通过**；`tests/verify-addon.ps1` 通过（外部原生地图模型来源检查按原脚本为可选跳过项）。这些是原生 API 和订单替身测试；未触发 Dota 实战噬魂，未验证实际回血数值。

UI34 已于 2026-09-11 20:58 安装：更新 4 个服务端/本地化源文件，以及 1 个 Panorama CSS 源文件；对应样式编译为 58,879 字节，114 个安装源文件与仓库逐字节一致。备份：`C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_ui34_backup_20260911_205841`。按钮样式修改后，条件编辑与能力限制 UI 回归再次通过；未进行实机截图或布局像素验收。用户重新载入地图后应看到「界面版本 34」，日志启动标识为 `rpg-runtime-v34-20260911`。原设置“自身 + 自身生命 ≤80%”可以继续使用；新的运行日志应确认规则 2 的目标指令及实际回血效果。
