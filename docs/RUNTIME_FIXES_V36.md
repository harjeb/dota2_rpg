# UI36：蜥蜴绝吻持续期间的自动行动保护

用户反馈电炎绝手大招自行中断，进一步观察到敌人进入霰弹轰击范围后，系统使用一技能打断大招。修复按原生持续状态暂停其他自动行动，状态消失后恢复；不要求玩家给每条规则另加等待条件。

## 日志与原生证据

读取运行中 VConsole 的缓冲历史，未发送战斗控制或施法指令。原始记录在本机 `%TEMP%/rpg_snapfire_console_20260911.log`，运行版本为 `rpg-runtime-v34-20260911`。

| 英雄实体 | 大招指令时间 | 后续自动指令时间 | 间隔 |
| --- | --- | --- | --- |
| 337 | 1040.97：蜥蜴绝吻 | 1041.97：霰弹轰击 | 1.00 秒 |
| 712 | 1131.17：蜥蜴绝吻 | 1132.47：霰弹轰击 | 1.30 秒 |
| 913 | 1281.77：蜥蜴绝吻 | 1282.57：小蜥蜴快射 | 0.80 秒 |

这些 `rule_executed` 记录表示订单已提交，日志明确标为 `order_submitted_not_native_confirmation`。它们与用户观察一致，证明持续窗口内仍有后续自动施法指令；旧日志未记录每帧大招 modifier 或全部外部控制，不能逐次排除其他中断来源。

原生技能快照 `data/native_skill_conditions.json` 中，`snapfire_mortimer_kisses` 的行为为 POINT、AOE、DONT_RESUME_MOVEMENT、DONT_RESUME_ATTACK，没有 CHANNELLED；`AbilityDuration` 为 5.5，`channel_time` 为空。本机 `game/dota/bin/win64/server.dll` 包含精确名称 `modifier_snapfire_mortimer_kisses` 与独立的 `_vision_source`。

运行中只读查询在游戏时间 1934.70 读取实体 666：技能 `GetBehaviorInt()=33816624`、`GetChannelTime()=0`，当时未施法、无当前 active ability、无大招 modifier。查询记录 `%TEMP%/rpg_snapfire_native_state_2139.log`。这确认当前技能不是普通引导，但不是大招持续期间 modifier 生命周期的实测。

曾尝试临时只读观察回调，因诊断 helper 的 nil 返回值格式化错误提前终止，未采集到有效持续状态；随后修正为上述单次查询并清除了专用回调。此诊断错误发生在用户反馈之后，与原始中断无关。临时 Lua 文件均已从安装目录删除。

## 修改

- 新增 `tactics/sustained_cast.lua`，仅识别施法者身上的精确 `modifier_snapfire_mortimer_kisses`；不把持续时间、冷却、技能所有权、视野 helper 或其他普通 buff 当成正在持续施法。
- `TacticEngine:IsBusy` 在评估后续规则、普攻和追击前暂停行动。`action_adapter` 在 CanExecute、最终 Issue 和 IssueApproach 处再次检查，包括技能、装备、切换、移动以及自定义订单入口。
- 持续移动和站位已有 busy/adapter 检查，因此其 MOVE、接近及结束 STOP 同样受保护。敌方独立 fallback 的攻击和攻击移动入口也使用同一保护。
- 原生状态消失后，下一个可执行评估恢复行动；不设置固定 5.5 秒等待，不伪造 IsChanneling、引导时长或成功事件，不修改敌方控制效果。普通引导及已审核的对应释放动作保留原有行为。
- 对应 overlay 同步修改。运行和界面版本更新为 UI36。

## 验证

新增 `tests/snapfire-sustained-cast.test.lua` 使用真实战术引擎、目标选择及订单适配器，原生 API 由测试替身提供。修复前复现“大招开始 → 0.8 秒后目标进入 Q 范围 → 下令 Q”，修复后通过。live 与 overlay 均验证：Q/E、装备、切换、普攻、fallback、旧追击、直接接近、持续移动结束 STOP、正常结束、提前原生中断及连续状态重新出现。只剩视野 helper 或普通 buff 不会锁住英雄。

完整离线回归 **67/67 通过**；`tests/verify-addon.ps1` 通过（外部模型来源复核为既有可选跳过项）。原有 Chronosphere 测试的 HasModifier 替身从“所有 modifier 都存在”改为仅返回测试所需的 Chronosphere modifier，继续验证原生控制例外，不再虚构大招同时存在。

这些结果不等于原生完整吐炮验收。重载 UI36 后仍需验证：敌人进入一技能范围时完整持续、无目标时不被追击/普攻打断、真实敌方控制结束大招后的恢复。共享英雄战术和敌方 fallback 已覆盖；未扩展其他英雄持续技能、克隆或特殊召唤控制器。

## 安装

已于 2026-09-11 21:39 安装本次 7 个变更/新增源文件，全部 **115 个安装源文件**与仓库逐字节一致。备份位于本机 `%TEMP%/dota2_rpg_ui36_backup_20260911_213917`，含原文件和新增文件回滚清单。本次没有 Panorama 代码或布局变更，无需重新编译 UI 资源。未由 agent 启动、停止或重载地图；需要重新载入后使用 UI36。
