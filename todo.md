# v1.0 代码审查与 LLM 修复交接说明

> **用户拍板结果（2026-09-05，优先级高于本文其它描述）**：
> 1. 保留：随机招募品质（含倍率/概率插值）、经验卷轴（双档限购）、初始 300 金币购买制开局、时间奖励上限 25%→**按 v1.0 改为 10%**、经济曲线按 v1.0（1~29 关金币 125400、上阵经验 33720）。
> 2. 采纳：彻底取消存档（删除 LocalStorage 与 `rpg_save_sync`，状态仅存服务端内存）；战斗规则换用修订版战术模块（固定 10 条+兜底、同技能多条、单条仅 AND）。
> 3. 暂缓：Run 时长目标、每五关休整、认输命令（本文 §4.6 相关项挂起）。
> 4. 阵容保持现状（最多 5 上阵 + 5 待命，不做前 4 关限 3 与前后排格子制）。
> 本文以下内容凡与上述冲突者，以本拍板为准；P0 修复（§3.1~3.4）与去重（§4.2）不受影响，继续执行。

> 审查日期：2026-09-05。基线提交：`3dafd34`，同时检查了当前未提交工作树。
> 本文是审查证据与实现说明，不是独立任务跟踪器；优先级、认领、依赖和完成状态以 **beads** 为准。总审查任务：`dota2_rpg-l47`。
> **结论：当前处于“旧版产品 + 部分新版模块”的迁移中间态，不能认定 v1.0 可玩或迁移完成。存在阻止初始化、规则找不到目标、战斗不进入结算的 P0 问题。**

## 1. 先确认最新设计，禁止按旧方向继续补功能

### 1.1 本次采用的权威来源

仓库中的 `dota2_rpg_revised_package.zip` 包含：

- `dota2_rpg_revised/DESIGN_REVISED.md`：**v1.0 可实施修订版**，2026-09-05，共 1183 行。
- `dota2_rpg_revised/DESIGN.md`：修订包中的同版设计。
- `dota2_rpg_revised/CHANGELOG.md`：明确删除旧存档、品质、卷轴和实体仓库依赖。
- `dota2_rpg_revised/demo/`：供整合的骨架，设计 §16 明确说明它不是完整地图。

根目录 `DESIGN.md` 仍是 **v0.8**；`README.md` 仍描述 30 级 3v3 Demo。最新提交 `3dafd34` 已开始采用修订版模块，现有 beads 任务也对应修订版方向。因此本次以包内 v1.0 为“最新设计”进行审查，**不能因根文档仍旧就把新模块回退为旧方案**。这是根据仓库证据作出的版本判断，不是新增需求。

工作树已有用户改动：`.gitignore`、`tactics/tactic_bridge.lua`，以及两份展开修订包目录的暂存删除。本次不修改游戏代码，不撤销这些改动；后续 LLM 也不要恢复被删除的副本目录。建议将唯一权威设计提升到根目录，来源和旧版差异保留在文档历史中，而非继续维护三份设计。

读取压缩包时可用 Python `zipfile` 或解压到仓库外临时目录；不要把归档 Demo 整体覆盖正式 addon。

### 1.2 必须采用的新旧差异

| 项目 | 当前旧实现/旧文档 | v1.0 要求 |
| --- | --- | --- |
| 状态 | LocalStorage + 客户端存档回传 | 当前服务端内存 RunState；同场重连，不做跨局存档 |
| 开局 | 300 金币，空英雄池自行购买 | 1000 金币，从验证过的 12 名新手英雄中免费选 3 名 |
| 招募 | 随机等级、品质及品质升级 | 固定章节等级与售价；无随机品质 |
| 成长 | 全英雄平分经验池 + 必买卷轴 | 上阵每人 100% XP，待命每人 50%；删除卷轴 |
| 经济 | 1~29 关 145500；时间奖 25% | 1~29 关 125400；时间奖最多 10% |
| 规则 | 动态槽、同技能一条、AND/OR | 固定 10 条 + 系统兜底；同技能多条；单条仅 AND |
| 规则 UI | 条件→动作→组合目标 | 动作 / 硬筛选 / 软优先级 / 使用条件 / 接近策略 |
| 控制权 | 默认 AI + 战术引擎 | 战术引擎唯一决策；显式兜底 |
| 仓库 | 12 格小精灵、按物品名操作 | 60 项虚拟实例仓库，装备时创建实体，保留 UID/充能/状态 |
| 阵容 | 自由移动、统一最多 5 人 | 前四关最多 3 人，第五关最多 5 人；六站位格；总英雄 10 人 |
| 失败 | 旧文档五次、回购/每日重置 | 无限免费重试、认输重布阵、三败反制提示 |
| 平衡 | 简化离线模型当主要依据 | 纯逻辑测试 + Dota 引擎内批测；首发仅 1x |

**明确不要做**：修复旧存档迁移、补每日重置/次数回购、继续完善卷轴和品质、加入未经验证的 2x/跳过、把实时自动战斗改成回合制逐动作确认。通用桌游技能中的存档/回合确认要求与这里明确的无存档、实时全自动产品设计冲突时，应记录适用性，不擅自改变产品。

## 2. 当前真实进度与验证边界

### 2.1 已有基础，但不代表已交付

- 正式地图、Panorama HUD、招募/装备/阵容界面和 KV 数据加载入口存在。
- `tactics/` 已有条件、选择器、adapter、引擎、订单过滤、规则服务、战斗记忆。
- `shop/shop_service.lua` 和 `data/progression_data.lua` 已复制进正式目录，但不能据此认定新版商店/成长接入完成。
- 主入口仍主要走旧经济、旧规则提交、旧实体仓库和旧存档协议。
- `DataLoader:Init()` 实际读取 **`scripts/data/levels.kv`、`enemy_ai.kv`、`loot.kv`**。只改 JSON 或 `levels_v07.json` 不会改变游戏。

### 2.2 本次实际执行的检查

| 检查 | 实际结果 | 可以说明什么 |
| --- | --- | --- |
| `pwsh -NoProfile -File tests/verify-addon.ps1` | PASS | XML、JS 和既有静态正则通过；不证明 Lua 初始化/战斗通过 |
| `node tests/panorama-save.test.js` | PASS | 旧存档与商店显示回归通过；不是 v1.0 验收 |
| Python `lupa 2.8` 执行 `tests/shop-state.test.lua` | FAIL：`addon_game_mode.lua:1477`，`string.match` 收到 nil | 现有测试与当前代码/数据契约不一致，需定位，不可跳过 |
| 同环境执行 `tests/precache-battlefield.test.lua` | FAIL：测试第 97 行 `npc_dota_hero_sven must be precached exactly once` | 预缓存测试夹具/实现有偏差；不等同实机预缓存必然崩溃 |
| Lua 模块探针，直接调用 `TacticBridge:Install()` | FAIL：`tactic_bridge.lua:315` 调用 nil `new` | 已复现桥接初始化接口错误 |
| Lua 模块探针 | 新引擎 `IsValidUnit` 为 nil；无 `get_candidates` 的选择器返回 `no_legal_target` | 已验证模块契约缺失 |
| 静态同名方法统计 | 26 个方法名重复定义 2~3 次 | 后定义覆盖前定义 |

Lua 使用的是 lupa 默认 Lua 5.5，并非 Dota VScript 运行时。本次没有启动 Workshop Tools、上传专服、跑真实战斗或完成 UI 交互测试；不能报告实机通过。两个旧 Lua 测试失败可能包含过时夹具因素，应修复契约后在受支持 Lua 环境与 Dota 中复验。

可复跑旧 Lua 测试（仓库根目录，已安装 lupa 的环境）：

```python
from pathlib import Path
from lupa import LuaRuntime
for path in ('tests/shop-state.test.lua', 'tests/precache-battlefield.test.lua'):
    try:
        LuaRuntime().execute(Path(path).read_text(encoding='utf-8-sig'))
    except Exception as exc:
        print(path, 'FAIL', exc)
```

## 3. 必须先修的执行链缺陷

下文路径缩写：

- `VS/` = `game/dota_addons/dota2_rpg/scripts/vscripts/`
- `DATA/` = `game/dota_addons/dota2_rpg/scripts/data/`
- `UI/` = `content/dota_addons/dota2_rpg/panorama/`

行号对应本次工作树，后续可能漂移，定位时同时搜索函数名。

### 3.1 初始化失败与结算驱动断链

**beads：`dota2_rpg-59b`，P0；设计 §3.1、§7.9、§12。**

证据：

- `VS/tactics/order_filter.lua:76` 返回 `{ OrderGate, OrderFilter }`，没有顶层 `new`；`tactic_bridge.lua:315` 却调用 `OrderFilterModule.new(...)`。实际调用 Install 已报错。
- 桥接第 11 行局部 `TacticEngine` 是新版模块；第 178、291 行调用它未导出的 `IsValidUnit`。旧全局同名 helper 不会穿透局部变量遮蔽。
- `VS/addon_game_mode.lua:272-273` 在注册主 think 和事件之前执行 Install，故第一个异常会阻断后续初始化。
- `addon_game_mode.lua:2490-2503` 的 `OnThink` 只调用 bridge；`battle/battle_manager.lua:154-165` 的胜负检查没有被该主循环调用。搜索整个正式 VS 运行链未发现 `battleManager:OnThink()` 调用。

修复方法：正确解包 `OrderFilterModule.OrderFilter.new`；实体有效性抽到明确的公共 helper，或使用 `Conditions.IsValidEntity` 并按调用场景补存活判定。主循环中以明确顺序驱动一次战术 tick 与一次胜负检查，后者检查阶段后再执行；勿注册两套重叠计时器。关键 require 不应只打印 false 后继续运行，应报告可定位错误并停止初始化。

验收：通过实际模块创建 bridge/Install 的集成测试；setup→fight→敌方全灭/己方全灭/同时死亡/120 秒超时全部到达一次结算；第二次 think 不重复奖励。实机日志必须无 nil method 错误。

### 3.2 缺少候选与战斗 Context，规则和兜底都可能无目标

**beads：`dota2_rpg-n3x`，P0；设计 §7.3、§7.6~7.9。**

证据：`tactic_bridge.lua:256-271` 只提供 caster/allies/enemies/elapsed/enemy_tags/combat_memory 等字段；`target_selector.lua:122-145、161-170、237-240` 实际只通过 `ctx.get_candidates` 取得候选。传 `enemies` 数组不能替代回调。因此单位/点目标与系统普攻兜底会失败。

`condition_registry.lua:51-54` 需要 `get_tags`；第 155-156 行读取 `dead_ally_count`；第 174-181、184-196 行需要动作次数、近期伤害回调。桥接未接。`OnEntityHurt` 只记录旧 BattleManager，未构成新 registry 所需契约。

修复方法：建立有测试的 `BattleContext` 工厂，为双方按相对阵营提供候选、动作目标合法性、可见性、类型、标签、范围、伤害窗口、死亡数、动作计数、阶段、接敌点。近期记录必须有界；标签要统一实体 ID；召唤物候选与 must_kill 判定名单分开。

验收：真实桥接 Context 下，治疗选友军、敌方伤害选玩家、Boss/后排筛选、近期受伤、阵亡数量、有限次数规则均能触发。范围内有次优目标、范围外有最优目标时，`range_only` 必须选范围内的合法者，不能先全场排序再失败。非法目标应软失败并继续下一条规则。

### 3.3 敌方 AI 被忽略，规则身份与缓存生命周期错误

**beads：`dota2_rpg-n3x`，P0，关联旧任务 `dota2_rpg-3aq`。**

证据：`addon_game_mode.lua:2230` 将敌方规则写到 `battleManager.teamRules[BADGUYS][enemyIndex]`；`tactic_bridge.lua:235-249` 却只从 `heroRulesByName[unit:GetUnitName()]` 读取，完全没读敌方规则。敌我同名英雄还可能错误共享玩家规则。第 330 行有 ResetState，但主入口没有调用；缓存键是 entindex。

修复方法：玩家按稳定 roster ID，敌方按 stage enemy instance ID / ai_profile 取规则；entindex 只做当前实体映射。COUNTDOWN/重试/换关清 chase、订单签名、次数和旧实体缓存；编辑规则、换装、技能变化按 revision 失效。长期消除“转换缓存与 RuleService 正式状态共用一张表”的隐患。

验收：敌我同名 Dazzle 使用不同规则；敌方治疗真实释放；下一关同模型不同 profile 不继承上一关规则；改规则后下一场立即生效；重试动作次数归零。

### 3.4 默认 AI、追击与下单成功语义未完成迁移

**beads：`dota2_rpg-cq0`，P1；设计 §7.8~7.10。**

证据：`addon_game_mode.lua:2444-2454` 仍 `SetIdleAcquire(true)` 和 4000 索敌范围；`tactics/tactic_engine.lua:375-395` 系统兜底采用全场允许追击，而设计要求“范围内最近敌人，否则预设接敌点”。`ContinueChase` 主要复验存活，没有完整复验无敌、可见、阵营、可达性；超时后本 tick 又可能从同一高优先级规则重新开始追击。

`action_adapter.lua:303` 附近忽略 `order_gate:Execute` 返回值并直接报告 true；`tactic_engine.lua:362` 通过 `record_action_order` 计次数，桥接立即把订单计为动作使用。下单成功也不等于实际施法成功。

修复方法：关闭默认决策且保留内部 gate；兜底明确分范围内攻击/接敌点移动。追击失败本 tick 排除该规则或设置有界重试退避，继续低优先级规则；紧急规则中断范围按设计限定。传播 gate 失败，区分 order_requested、order_accepted、cast_completed/attack_landed，并明确“本场使用次数”的计数事件。

验收：同签名 0.25 秒内不重发；施法前摇/引导不被打断；无敌/死亡/越界目标解除锁定；超时不会无限重新锁定同目标；失败订单不增加成功次数；无规则时仍按显式兜底接敌。

## 4. 规则协议与产品迁移

### 4.1 固定十槽和五段编辑器尚未端到端接入

**beads：`dota2_rpg-2iz`、`dota2_rpg-bte`、`dota2_rpg-otk`；P1。设计 §7、§12.3、§15。**

证据：桥接创建 RuleService 但不调用 `InstallEventListener()`；旧 `OnStartBattle:2426-2432` 仍按 `RULE_COUNT` 截断并走旧 `ParseRules`。UI 第 552、599-602、773 行仍使用 `logic=any/all`，动态动作槽仍是旧产品逻辑。

`ConvertLegacyRule:111-146` 丢掉 `logic`，把两条件塞到固定 AND 数组；未知条件返回 nil，相当于无条件。`ally_hit_count_ge` 还被改成“最近受伤”而忽略 N。切换动作没有显式 desired state。目标映射没有覆盖全部旧组合，未匹配项默认为 nearest。

新模块也不能直接无审核启用：

- `rule_service.lua:124-125` 用 Lua `and false or nil` 解码关闭状态，`"0"` 最终是 nil，不是 false。
- `UpdateRule:254` 按 slot 写表，但引擎用 `#rules` / `ipairs`；只编辑槽 10 会形成空洞，不能保证遍历。
- `SyncRule:260-275` 只同步条件类型，丢失数值、次序细节和 toggle 等参数，不能完整重建编辑器。
- 桥接 `is_action_allowed` 恒 true，`is_roster_hero` 仅判断实体，不能直接当正式所有权/adapter 校验。

实现方法：统一 Rule DTO 和注册表元数据；固定初始化 10 个 disabled 条目，UI 支持复制/禁用/排序/模板/重复技能；服务端按 1..10 遍历。系统兜底不占玩家槽。新 UI 发送单条编辑命令，由 RuleService 规范化后回传完整字段；动作类型、目标类型、AOE 半径来自服务器 adapter，不信任客户端覆写。

旧规则仅作显式一次性内存导入：OR 拆成连续两条，超过十槽提示用户处理；无法等价转换的条件拒绝/标记需重配，绝不静默变为 always。新产品不再显示“存在目标”及 OR 选项。显式 if/elseif 解码 toggle 的 true/false/nil。

验收：槽 10 单独启用可执行；同治疗技能三条阈值规则按序工作；false 开关能回传并只切换一次；错误条件、非有限数值、超范围参数、敌方英雄编辑均拒绝且保留旧状态；提交→确认→重连完整字段一致。

### 4.2 同名方法重复覆盖：修改代码可能根本不生效

**beads：`dota2_rpg-347`，P1。**

`addon_game_mode.lua` 中 26 个方法名重复。例：`OnSaveSync` 在 964/1286/1829，`OnItemBuy` 在 761/1083/1626，`DistributeXpPool` 在 868/1190/1733，`RollShop` 在 567/1432，`OnHeroLevels` 在 1324/1866。Lua 最后定义覆盖前定义；第一份较完整存档逻辑实际上不生效。

实现方法：先列出每个重复块差异和最后有效版本，再去重；不要盲删后半文件或只修第一份。按 RunState、Progression、RecruitService、ShopService、BattleManager 分职责迁移；入口只做初始化与事件绑定。增加重复方法扫描门禁。

验收：同类同名方法重复数为零；事件只能注册一次；相关真实调用测试通过。文档权威入口、README 与测试提示不再描述旧 Demo 为当前状态。

### 4.3 无存档 RunState、权威边界与最终关重复奖励

**beads：`dota2_rpg-xr6`，P1；设计 §1.3、§3、§12。**

证据：UI `rpg_demo_hud.js:1251-1341` 仍读写 LocalStorage；`addon_game_mode.lua:326-327` 注册存档回传；最后有效 `OnSaveSync:1829-1863` 接受客户端金币、英雄、阵容、当前关并重建战场。不是“客户端镜像”，是覆盖服务端权威。

`EndBattle:2575-2610` 仅靠 phase 防当前一次重复调用，没有 claimed_rewards。第 30 关没有 next level 时保留当前关，三秒后重新 setup，因此恢复结算驱动后可再次挑战并重复获奖。这是确定的生命周期缺陷，而非仅安全猜测。

实现方法：接入服务端 RunState（修订包 run_state 骨架仅供参考）；客户端不发送金币/库存/进度结果。命令验证发起玩家、阶段、归属、规则 revision 与 request ID。建立 run_id/battle_id/stage_id、claimed_rewards、final_completed；终局转完成页，不再 setup ch30。当前阶段种子缓存只在 Run 内保存。

重连请求 `rpg_request_full_state`，从服务端分片恢复 UI。新增必要的 CustomNetTables 声明文件与订阅，单 key 测量序列化大小≤12 KB；网络命令用 CEM，拒绝也回传原因。不要只在 UI 删除按钮而保留旧改金币事件。

验收：同场重连状态一致；新房金币1000且无旧进度；旧存档回传和改关请求无效；结算重入/延迟回调只能发一次；第30关不能重新刷奖。无限重试是新需求，不应补五次上限。

### 4.4 新版装备服务未接入，复制骨架仍会丢物品状态

**beads：`dota2_rpg-0a6`，P1；设计 §6.4~6.6。**

证据：入口只 require 旧 helper、bridge、BattleManager、DataLoader，没有实例化 ShopService。实际仍走 `StashAddItem:1941` 等。`RemoveBattleBarrier:2001-2013` 还会删除 stash 实体，与开战调用链相连；当前库存是否已完整快照需实机专项验证，不能假设安全。

新 `shop_service.lua:85-132、143-214` 虽有 uid，但实例没保存 charges/custom_state；卸下销毁实体后不能恢复这些状态；仓库满时 AddDrop 仅失败，没有结算暂存区。`InitializePlayer` 每次会重设金币，不能用作重连恢复。

接入注意：新服务注册 `rpg_shop_buy` 表示购买装备，旧入口同名事件表示招募英雄（`addon_game_mode.lua:332`），直接并装会发生协议冲突！

实现方法：统一命名 `rpg_recruit_buy` 与装备命令，删除重复监听；仓库以 UID 为唯一身份，名字仅用于展示。通过 item adapter 序列化/恢复充能、永久层数、自定义状态；买入价随实例保存，出售返50%。装备失败回滚，确认物品确实进入合法槽后才移除仓库条目。满仓掉落进入 pending_loot，处理完才推进。禁止地面掉落、原生购买与战斗穿脱。

验收：同名不同充能实例往返状态不混淆；满仓不丢掉落；实体创建/转移失败不扣钱丢物；重连不重置金币；重复请求不重复扣款；招募和买装备不会触发彼此监听；专服验证真实实体清理。

### 4.5 经济、XP、招募必须整体切换，不能只改常量

**beads：`dota2_rpg-8qn`，P1；设计 §4~6。**

证据：初始化仍有品质和卷轴字段；有效 `DistributeXpPool:1733` 是旧平分模式；`EndBattle` 是25%时间奖和xp_pool。实际 `levels.kv:2503-2504` 的第30关仍14500金币/3000池经验。已复制的 progression_data 没有成为加载入口。

实现方法：以版本化数据作为唯一来源，接入 Progression；引擎自定义累计 XP 与项目显示用同一曲线，30级需求33700。倒计时冻结上阵名单：上阵每人整份、待命50%向下取整，死亡不扣。招募等级/价格按六个区间：1/500、5/900、10/1600、15/2600、20/4000、24/5500。首次刷新免费，之后100/200/300/400/500封顶。删除品质/卷轴事件、UI、状态、测试断言，升级改为白名单购买项。金币奖励与敌方预算同时切换版本，不保留两套并行结算。

验收：常驻英雄第30关前33720XP到30级；新增待命不稀释主力；1~29关基础金币和125400；初始1000+免费三选；第30关奖励不能参与第30关配装；时间奖≤10%；招募和刷新每个区间边界直接断言。

### 4.6 阵容、站位、倒计时、认输和休整缺口

**beads：`dota2_rpg-7j5`，P2；设计 §1.3/1.5、§3。**

证据：`OnStartBattle` 直接 setup→fight；`OnLineupSet:1793-1813` 只检查 ownedSet 和统一上限，未对输入英雄去重；站位保存自由坐标。正式 HUD 未找到认输、三败提示与五关休整流程。

实现方法：三个前排+三个后排格，以 grid_id 保存，最多占5格；第1~4关限3，之后5，总池10。去重英雄与站位；服务器校验所属半场，不信任任意坐标。COUNTDOWN 冻结等级/装备/规则/站位标签；所有修改命令在倒计时和战斗拒绝。认输走普通失败结算路径；第三次失败显示既定 counter_tags，每五关进入当前Run休整而非存档。

验收：重复hero、重复格、越界坐标和超编均不改变原阵容；战斗移动不改变front_row/back_row快照；认输只记录一次失败且不扣钱；本场重试保留配置但清战斗临时状态。

## 5. 内容、兼容性与发布门禁

### 5.1 敌方装备、技能和机制“数据存在但未消费”

**beads：`dota2_rpg-zs9`，P1；设计 §3.5、§8~9。**

证据：`SpawnLevelEnemies:2165-2235` 消费level、怪物倍率、quality_upgrades、tags、ai，但没有给单位创建 `entry.items`；`levels.kv` 却大量配置 items。`PrepareEnemyHero` 仍自动加点。`BuildEnemyRules:2249-2269` 只取 action.type，不保留 action.skill（cast类可能最终被解析成名为cast的技能）；对原生KV数字字符串键使用ipairs也必须统一归一化验证，不能假定是Lua数组。

实现方法：数据导入阶段把有序KV列表归一化；规范 ai_profile DTO 并校验引用。生成敌人时真正装备清单物品、执行固定技能/天赋计划、应用被白名单允许的升级。绑定角色variant、innate策略和level_30_verified报告。替换普通兵线单位占位为明确的自定义怪物模板，完整配置五类属性与职责。Boss阶段表必须被运行时消费，转阶段清追击并重评，显示阈值/前摇/反制；不可选中演出按§3.3排除计时。

验收：第5/10/15/20/25/30关逐实体检查实际等级、技能点、装备格与总价；第30敌方92000~108000预算。治疗/打断/驱散/切后/三阶段真实执行，不能以UI文字或表里有字段代替。召唤物被选中、可被攻击，但仅must_kill者影响胜负。

### 5.2 adapter 兼容名单不等于英雄目录或通用行为推断

同属 `dota2_rpg-zs9`，关联 `dota2_rpg-2iz`。

`action_adapter.lua` 存在 custom registry，但桥接没有注册英雄/物品专用adapter；仅通过 behavior 推断无法保证树木/向量/子技能/神杖升级合法。桥接还把所有转换动作 `target_team` 写成enemy，友方技能不能依赖此字段决定目标。

从当前Dota版本目录生成候选，以逐技能/装备adapter报告决定开放范围；目标阵营/类型/技能名/行为只能服务器决定。注册跳刀等专用adapter，AOE半径与评分、安全性进入统一数据；动作ID不应因物品移动槽位或技能变身指向另一动作。未验证内容标记partial/blocked，不默默回退为普攻并称兼容。

验收：每个开放英雄具有专服patch/variant/innate/talent/30级证据；单位/点/无目标/显式切换四类基础动作完整回归，特殊类型逐项测；两份同名装备按实例绑定；未适配主动装备不进入可选动作。

### 5.3 现有绿灯门禁检查了旧需求，漏掉实际初始化失败

**beads：`dota2_rpg-4p3`，P1；设计 §12.5、§13。**

`tests/verify-addon.ps1:52-153` 主要检索代码字符串，仍要求INITIAL_GOLD=300、TIME_BONUS_CAP=0.25、RollQuality、卷轴、默认索敌等旧字段；只要求两个Lua测试文件存在，没有实际执行它们。输出还写“20 data-driven levels”。`sim/README.md:4` 明示使用旧 `battle/tactic_engine.lua`，不能验证线上新 `tactics/tactic_engine.lua`。

实现方法：

1. 保留资源/XML/JS检查，新增完整Lua加载、bridge Install、真实Context、双方规则与战斗生命周期测试；不要mock掉所有require后声称整合通过。
2. 把设计§1~15拆成稳定rule_id覆盖矩阵，记录实现位置、正常/边界/非法输入测试、审计断言、未验证原因；另列PREPARE/COUNTDOWN/FIGHT/SETTLE边界走查。
3. 单一内容源+可重复生成KV脚本；检查30关9/21分布、人数、金币/XP、装备预算、profile/adapter/benchmark引用与技能天赋合法性，失败阻止发布。
4. sim切换新规则内核但明确是近似工具；最终平衡必须Dota内批测：提交关键关50种子、章节5关×200、发布30关×档案×500。保存完整英雄/等级/加点/装备/站位/规则档案及版本。
5. 输出胜率、中位数/P90、规则命中/超时/取消、实际装备总价；完整Run至少30样本验证75~110分钟、P90≤120分钟。

验收：先加入能让本次P0缺陷真实失败的测试，再修至通过；故意删get_candidates/敌方规则接入/结算tick时门禁必须变红。不能仅修改PASS文案或删除旧断言来制造绿色。

### 5.4 战斗日志与引导仍是需求缺口

**beads：`dota2_rpg-u61`，P2（日志基础设施应随P0修复优先接入）；设计 §1.2、§7.12、R6。**

当前 bridge 的 on_debug 只是 `print('[TacticDebug]...')`，正式HUD没有完整可导出战斗日志、新手教程、独立界面导览与术语帮助。不能沿用v0.8“TacticDebug已具备”当作玩家日志完成。

实现方法：服务端生成有序审计事件：Run设置/阵容快照、编辑与拒绝、购买成本、规则选择/失败原因、追击、订单与真实动作结果、伤害治疗、阶段、奖励和终局。包含run/stage/battle/time/actor/rule_id/action/target、原因和数值delta；正式UI显示摘要与按英雄/战斗过滤，开发模式才逐tick trace。提供Panorama可行的文本查看/复制/导出路径，实机验证；日志只保留本Run内存，导出的审查文本不能用于恢复进度，不偷偷恢复存档功能。

引导分别实现：500~800字入门说明、可重开的游戏内指南、界面介绍spotlight、右上角“新手教程”确认入口。教程使用固定已验证三英雄、装备/技能与固定关卡，独立教学状态，不改正常Run；教会配置治疗/打断、完整开战→结算→重配1~2场。首次弹层串行卸载，不能遮挡叠加。是否跨局保存纯UI偏好需明确产品裁定，默认不写游戏进度或LocalStorage。

验收：玩家从日志能解释规则为什么失败、费用/伤害/奖励来源，实际UI导出内容与面板一致；模板/术语/所有阶段指示来自同一数据；教程取消不改变正常Run，退出恢复可操作界面。以Dota/Panorama实机自动化或录制证据为准，不能用普通浏览器DOM测试代替引擎交互。

### 5.5 羁绊与词缀不要抢在基础迁移前启用

**沿用：`dota2_rpg-cao`、`dota2_rpg-bs8`；设计 P1→P2→P3。**

正式VS目录有相关modifier，但没有完整bonds/affixes服务接入；存在modifier文件不等于完整系统。先完成R0~R6基础，再按v1.0§10/11迁移阈值、叠加上限、成员快照和事件触发，不能采用旧版2/3/5阈值。

词缀用Hash(run_seed,stage,version)在当前Run首次进入缓存，不读玩家强度；预算0/1/2/3/4/5/6，严格检查成员上限、互斥与两种可表达反制。满预算无法生成时构建失败，不在运行时暗减预算。功能开关关闭时基线战斗不变。

验收：死亡/召唤不重新算羁绊；同Run失败/重连不重抽词缀；新Run重新生成；阶段、日志与UI同步；最高合法组合通过联合批测后再开放。

## 6. 给其他 LLM 的执行约束与分工

推荐顺序：先处理 `59b`、`n3x` 并补回归，随后去重和权威文档；再统一规则协议与RunState；然后仓库/成长/阵容/敌方内容；最后兼容、教学和发布平衡。日志事件应从基础修复开始，不要等最后才追加。

可并行边界：

| 工作方向 | 负责文件 | 并行限制 |
| --- | --- | --- |
| 运行链负责人 | addon、BattleManager、bridge、RunState | 同一时段只允许一个LLM写主入口 |
| 规则负责人 | tactics内核、RuleService、规则测试 | 先约定Context/DTO，不能自行改入口 |
| UI负责人 | Panorama XML/JS/CSS | 必须等事件和DTO契约固定，不再写旧协议 |
| 内容负责人 | data、导入校验、benchmarks | 依照v1.0数表；不要只改未加载JSON |
| 独立测试审查 | tests、专服批测报告 | 验证真实入口，不把mock覆盖缺陷当通过 |

每个修复单元都应：读取本条设计来源→`bd show`→认领→补失败用例→最小代码修复→运行相关测试→实机核验需要Dota的部分→记录证据→关闭对应issue。复用已存在的`2iz/3aq/cq0/otk/0a6/bte/cao/bs8`，不要为同一工作再建平行任务。源码集成存在不代表可以关闭旧issue。

可直接交给执行LLM的提示词：

> 阅读todo.md和压缩包内v1.0设计；执行指定beads issue。不要按根v0.8补已删除功能，不要直接覆盖归档Demo。先确认当前调用链和已有用户改动，先补失败测试。所有客户端输入服务端重新验证，禁止未知条件变always；每次只迁移一个有端到端验收的垂直切片。提交时写清修改文件、设计条款、已运行测试输出、实机未验证项和后续依赖。不得把代码存在、静态PASS或简化sim结果当作完整交付。

## 7. 审查自检与交付声明

本次交付的是审查文档和beads问题，不是游戏修复。**游戏实现仍未完成**；不声称全部设计条款/全部英雄技能已经审计通过。静态确证、Lua探针复现、待实机验证已分开标注。

| 产品审计项 | 当前结论 | 证据/缺口 |
| --- | --- | --- |
| 全流程可审查日志 | 未完成 | 仅控制台trace，无UI完整导出 |
| 权威规则/设计与覆盖矩阵 | 部分 | 已确认包内v1.0；根文档仍旧，无逐条映射验收 |
| 初始桌面/阵容忠实性 | 不符合v1.0 | 旧300金币/空队伍；未实机截图 |
| 界面介绍 | 未完成 | 未见独立spotlight流程 |
| 完整阶段条 | 未完成 | setup/fight/result，缺COUNTDOWN与全流程走查 |
| AI逐动作确认 | 不适用桌游默认要求 | v1.0明确实时全自动，不强改玩法 |
| 玩家可选操作与非法输入 | 部分 | 有准备期限制，缺完整服务器权威/重复输入测试 |
| 独立指南/onboarding/tutorial | 未完成 | 固定教学、隔离、首屏串行均无验收 |
| tooltip与术语覆盖 | 未完整验证 | 有Dota动作显示；未建立术语全集及逐处覆盖报告 |
| 存档版本迁移 | v1.0删除项 | 应删旧存档，改验证同场重连与新Run清空 |
| 布局/交互/可访问性 | 未实机验证 | 不凭源码判断响应式、点击或触摸已通过 |
| 交付平台 | 部分 | 本地源码检查PASS；Dota加载/编译/专服未验收 |
| 全条款测试与规则效果 | 未完成 | P0已复现，旧Lua测试失败，批测未执行 |
| 羁绊/词缀 | 未接入完成 | 后置阶段，不能用modifier文件充当实现 |

关闭本次审查issue只表示交接文档已经完成，不表示上述实现问题已修复。任务状态请始终查询beads，不在本文维护勾选框或平行完成清单。
