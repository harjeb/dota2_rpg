# 10 项修复核查与当前实现

本轮逐项检查了实际 addon、Panorama 和修复包接线，而不是只检查 `issue_fixes` 模块是否存在。发现并修正了主 HUD 默认十行、真实关卡/出战单位读取缺失、技能点被自动分配、原版商店订单绕过回调等遗漏。

范围仍限于这 10 项及地图原生资源替换，不改变经济、经验奖励、招募价格、存档、羁绊、词缀或关卡奖励。以下“已修复”指源码和回归测试层面；不代表已经完成 Dota 2 实机验收。

## 1. 小精灵转交装备

`rpg_transfer_warehouse_item` 的参数为 `source_entindex`、`item_entindex`、`hero_entindex`。`inventory_transfer.lua` 验证准备阶段、玩家归属、目标 roster 身份及物品确实位于来源单位。

转交使用同一个 item handle：先从来源移除，再加入目标，保留充能等实体状态；满载直接拒绝，目标拒绝时回滚来源。如果引擎在合成/堆叠时已经消费原实体，不再错误地尝试恢复失效实体。异常回滚无法放回来源时保留原物品到地面，不按名字复制或销毁装备。

实际主 HUD 的 `rpg_item_equip` 通过 `MoveStashItemToHero` 接入同一修复服务，支持背包空位；`rpg_item_unequip` 保留原有精确实体转回入口。测试同时覆盖真实 HUD 服务端入口和修复层事件。

## 2. 准备区和场上英雄升级技能

玩家英雄绑定 PlayerID、Owner、控制权。`modifier_rpg_prepare_bench` 仅使用无敌、定身、缴械、沉默、无碰撞，不使用眩晕或命令限制。

本轮去掉了待命英雄生成时自动分配所有技能点的行为，并在 roster 重建前记录原版技能等级和剩余技能点，重建后恢复；新增等级的技能点保留给玩家分配。敌方升级逻辑不受影响。

准备阶段允许 `DOTA_UNIT_ORDER_TRAIN_ABILITY`；战斗、倒计时、结算阶段仍禁止玩家升级。

## 3. 默认行动规则

没有有效规则时，客户端和服务端均只生成一条：

```text
普通攻击 -> 敌方 -> 最近 -> 仅当前范围
```

主 HUD 不再按十槽或技能/装备数生成默认行；已有 N 条规则就显示 N 条，只有“新增规则”增加行。动作列表刷新保留已有编辑结果，滚动范围随实际行数变化。

同步携带 `rule_count`，服务端验证后裁掉已删除的尾部槽位，不再通过十个禁用占位规则维持旧长度。玩家主动禁用的有效规则仍保留，不与占位行混淆。战术桥的旧规则缓存与 RuleService 当前 Run 规则分离，开战重置不再清空玩家规则。

## 4. 敌人主动进攻

只有真正进入 `FIGHT` 才启动敌人运行时，拒绝的开战请求不会误发进攻订单。移除准备限制、开启 IdleAcquire、设置索敌范围，并为当前关的实际敌人下发首次攻击。

每 0.25 秒的兜底只处理空闲、未引导、未施法、没有有效攻击目标且没有 TacticEngine 活动订单的单位。读取真实 `tacticBridge.tacticEngine` 状态，避免覆盖战术施法/移动订单。

## 5. 第 1/2 关敌人不同

正式 `levels.kv` 已是不同配置：`ch01` 为三个豺狼人刺客，`ch02` 为两个豺狼人刺客加两个狗头人。本轮保留这组实际配置，不因旧文档的半人马建议而改动现有关卡平衡。

兼容修复正确识别 `ch01` / `ch02` 等关卡键。仅在两关单位多重集合完全相同时替换已有第 2 关的敌人，不创建不存在的第 2 关，不修改奖励、时间、掉落等字段。

## 6. 敌方逻辑使用当前关单位

兼容层读取本项目的 `dataLoader`、`currentLevelId` 和 `battleManager.teamHeroes`，同时兼容 `currentEnemyUnits`、`enemyUnits`、`spawnedEnemies` 等入口。

每个实际敌人按 `GetUnitName()` 匹配当前关展开的 entry，再使用 `ai_profile` 或本项目实际使用的 `ai` 字段绑定战术；没有单位名时才按顺序回退。不再因读不到本项目容器而只看到待命英雄或空关卡。

## 7. 行动面板箭头与收起尺寸

Radiant/Dire 两个真实面板都显式绑定共享按钮逻辑：展开 `<`，收起 `>`。按钮 44×44，收起容器 56×56；清除收起时继承的内边距，隐藏实际 EditorBody、头像和标题，关闭已打开菜单。

修复样式直接由主 HUD 在基础样式之后加载，不再依赖兄弟布局的样式传播。实际像素尺寸仍需 Panorama 验收。

## 8. 英雄商店透明 UI

真实 `ShopPanel`、Frame/Body、整条 `ShopOffer` 报价容器背景、边框和阴影透明。半透明底只保留在单个 `ShopOfferSlot` 报价卡和交互控件上。

同时移除了附加布局 `issue_fixes_ui.xml` 根 Panel 的 `id`；该属性曾在历史 resourcecompiler 日志中造成编译失败。回归检查现在同时验证 XML 结构和 Panorama 根 Panel 约束。

## 9. 矩形战场与原生边界

战场保持两个 1200×900 准备区拼接的 2400×900 矩形。准备阶段左右分区，开战开放全场；只对场上战斗单位进行订单钳制和每 0.2 秒越界纠正，不把小精灵或待命英雄拉进战场。

可见外围改用 Dota 原版岩石模型，删除自定义可见中线刷子。原版模型引用来自本地原版 `dota.vmap`，并非新建自定义模型。四面外边界刷子只作不可见碰撞保护，保留四块 `nonavclip` 和中线 `rpg_mid_gate_nav`。

中间隔断使用 `CreateTempTree` 原生树木，覆盖中线全长。准备阶段补齐被砍掉的隔断树；开战逐个砍掉并移除本控制器创建的树，解除中线碰撞；下一关重新生成。不会用中心圆形清树误删其他树木，也不会漏掉两端。

源码 VMAP 与 overlay 同步。地图编辑前仍应备份；详细坐标及模型来源见 `dota2_rpg_issue_fixes/integration/HAMMER_ARENA_SETUP.md`。

## 10. 原版商店购买

开启 Universal Shop、easy-buy；准备阶段允许购买、出售、给予、移动、拾取、丢弃、拆分与合成锁等原生物品订单。

订单过滤器保留并调用真实的 `is_inventory_unit`、`is_managed_order` 和准备阶段原生商店校验/购买归属回调，不再提前放行而跳过来源验证和购买路由。小精灵、场上和待命英雄保持玩家归属与控制权；战斗、倒计时、结算阶段仍禁止玩家购买和升级。

## 验证与剩余边界

统一源码回归入口：

```text
python dota2_rpg_issue_fixes/tests/run_checks.py
python tests/vmap.test.py
```

前者需要 Node.js 和 Lua/texlua 或 Python `lupa`，涵盖 live/overlay Lua 语法与模拟运行、真实 addon 方法、原版商店、技能点、树木循环、Panorama 事件/默认行/样式结构和安装器。后者离线解析实际二进制 VMAP，检查原生模型、碰撞/导航几何及 overlay 一致性。

当前环境没有 Dota 2 安装、`dmxconvert.exe` 或 `resourcecompiler.exe`，因此本轮没有重新编译、部署或启动游戏。历史文档中的 `19 compiled, 0 failed` 只适用于旧版几何墙，不能当作本次原生岩石地图的编译结果。

仍需在 Workshop Tools 检查：岩石实际尺寸/朝向/显示、外圈碰撞、树木与中线门切换后的导航、原版技能按钮、真实物品合成/堆叠、服务器商店购买归属、战术与兜底 AI 优先级，以及 Panorama 实际布局。后续实机验收统一记录在 Beads `dota2_rpg-4rk`；本轮源码修复记录为 `dota2_rpg-dle`。

独立修复包只覆盖其自有模块和 VMAP，不覆盖目标 checkout 的整个主 HUD/addon。移植到其他分支时还需要按 integration 说明合并本轮主 HUD、技能快照、RuleService 和 tactic bridge 的接线修改；不能只复制 overlay 就宣称获得完整 live 修复。
