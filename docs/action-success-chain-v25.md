# v25 成功动作连招与物品条件英雄隔离

归属：`dota2_rpg-4t8`。部署与完整验证见 [RUNTIME_FIXES_V25.md](RUNTIME_FIXES_V25.md)。

## 成功施法条件 U39

`action_succeeded_after` 使用 `action_id`（必填）、`seconds`（默认 2 秒）和可选 `action_actor`。只有原生 `OnAbilityExecuted` 回调记录成功；下单记录、施法前摇和失败下单不会记录成功。此处“成功”指原生执行事件，不保证伤害命中或持续施法完整结束。

配置斧王规则时，跳刀目标选敌方并使用最近优先级；刃甲加 U39，前置动作选自己的跳刀；狂战士之吼加 U39，前置动作选自己的刃甲。刃甲和吼使用适合无目标技能的目标设置。顺序由成功条件决定，不依赖同一秒的时间戳大小。

每次原生成功事件有全局递增序号，各英雄独立保存最后一次动作成功。前置序号必须比当前后续动作最后一次成功的序号更新，且在时间窗口内。因此同一前置成功对于同一个英雄的同一个后续动作只允许一次成功释放；后续下单失败可重试，但不会继续解锁下一技能。重复规则行若使用同一个后续原生动作也共享该消费限制。不同后续动作各自消费，不实现所有规则之间的全局互斥令牌。

Engine.Reset 会 detach 已注册单位的观察器并清除成功/计数历史；新战斗重新 attach。普通同句柄复活保留当前战斗记录。前置成功不排队，使用最新记录。

原中断实现通过 `casts` 的 metatable proxy 监听计数赋值。该模式在 Lua 5.1 中可拦截每次递增，但普通 `pairs` 无法看到隐藏计数，任何计数赋值也暗含“成功事件”的副作用。现改为普通 `casts` 表，由 modifier 显式调用 `native_events.RecordSuccess`，统一更新计数和成功序号。桥接仍负责把 `item_1` 等槽位别名解析成原生动作名称。

## 物品条件共用的可复现原因

后端 RuleService 按 Snapshot.HeroKey 存储，物品不会以全局物品名作为规则键。己方当前招募模型按英雄名独立；敌方同名单位按 occurrence 独立。UI 的 getRules 按阵营、英雄名与 occurrence 建立规则对象。

修复前的弹窗捕获了打开时的 `authored` 规则对象，Apply 却调用 `sendRuleToServer(side, selectedHeroIndex[side], idx)`。打开 A 的弹窗后切到 B：本地修改 A，而发送的是 B 的规则。界面选中对象、规则对象和发包对象因此不一致。这是代码可复现的身份串号路径；没有用户实机操作日志证明它是所有“共用”反馈的唯一原因。

HUD 捕获 `editingHeroIndex` 与 `editingEntry`，Apply 校验英雄仍在该位置、规则对象未被替换，然后向原英雄发包；并为 actionHeroes 补入装备。condition_catalog 的动作选项也已显示原生 DOTAItemImage。

## 验证与整合状态

- 新 `tests/action-success-chain.test.lua`：真实 DecodeFlat/ValidateRule/Engine.TryRule + 原生 modifier 回调替身，验证最近敌方跳刀、失败前置/后续下单、同帧序号、一次成功消费、窗口过期、重复成功、新战斗重置、同物品不同英雄存储及 nettable 隔离、无效参数拒绝。
- `tests/condition-v2.test.lua`：新增真实 bridge 的物品槽位解析、跨 actor 成功历史、下单不触发及 detach 后失效；217 checks 通过。
- `tests/panorama-save.test.js`：新增两英雄相同跳刀/刃甲，弹窗切英雄再 Apply 的真实 HUD 模拟；验证发包 hero_index/hero_name、U39/前置装备/秒数往返及另一英雄规则不变。整套通过。
- 当前全部 Lua 测试在独立 `lupa.lua51.LuaRuntime` 中通过；新增 bridge 断言后单独重跑 condition-v2 通过。
- `tests/condition-coverage.test.py` 7 项通过。
- `tests/condition-ui-v2.test.js` 已把通用规则编辑场景迁至己方面板，保留敌方重复英雄的技能/装备引用、F39 和只读行为；U39、32 个使用条件及 472 个完整模板变体全部通过。
- 完整 `run_checks.py` 已通过，包括 32 个 Lua 行为场景、全部 HUD/Python/安装/地图检查。

离线 native 替身不等于 Dota 内施法实际效果验收。
