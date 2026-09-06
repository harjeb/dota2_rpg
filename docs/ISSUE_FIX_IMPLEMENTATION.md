# 当前 10 项 issue 实现说明

本文件随修复层安装到仓库。范围仅限用户列出的 10 项，不修改经济、经验、招募、存档、羁绊、词缀或关卡奖励。

## 1. 小精灵转交装备

服务端事件 `rpg_transfer_warehouse_item` 必须发送：

```text
source_entindex
item_entindex
hero_entindex
```

`issue_fixes/inventory_transfer.lua` 从来源单位移除原 item handle，再把同一 handle 加入目标英雄。目标满载或拒绝时，原 handle 回滚到来源；成功路径不销毁源物品，也不按物品名创建副本。

## 2. 准备区和场上英雄升级技能

准备阶段的玩家英雄必须具有正确的 PlayerID、Owner 和控制权。待命锁定使用 `modifier_rpg_prepare_bench`，只保留无敌、定身、缴械、沉默和无碰撞，不使用 `MODIFIER_STATE_STUNNED` 或 `MODIFIER_STATE_COMMAND_RESTRICTED`。

订单过滤器在 `PREPARE` 放行 `DOTA_UNIT_ORDER_TRAIN_ABILITY`。项目若单独保存未分配技能点，应在生成英雄后调用 `RosterAccess.EnsureAbilityPoints()` 恢复该值。

## 3. 默认行动规则

没有有效玩家规则时，只生成一条：

```text
普通攻击 -> 敌方 -> 最近 -> 仅当前范围
```

不再按主动技能数、主动装备数或固定槽数补齐空行。玩家已有 N 条有效规则时只显示 N 条；只有点击“新增规则”才创建新行。

## 4. 敌人主动进攻

切换到 `FIGHT` 后：

- 移除准备阶段限制；
- 开启 IdleAcquire，并设置索敌范围；
- 对当前关每个实际敌人发出首次攻击目标订单；
- 每 0.25 秒只对空闲、未引导、未施法、没有有效攻击目标且没有 TacticEngine 活动订单的单位执行兜底攻击。

## 5. 第 1/2 关敌人不同

运行时仅在检测到第 1、2 关单位多重集合完全相同时替换第 2 关敌人，并保留第 2 关奖励、时间、掉落等字段。正式发布仍应把第 2 关配置写入 `levels.kv`，建议组合为三个半人马征服者和一个半人马可汗。

## 6. 敌方逻辑使用当前关单位

敌方运行时优先读取 `currentEnemyUnits`、`enemyUnits` 或 `spawnedEnemies`。每个实际单位先按 `GetUnitName()` 匹配当前关展开后的 entry，再绑定该 entry 的 `ai_profile`；只有单位名不可用时才按顺序回退。代码中没有固定三英雄名单或固定数量。

## 7. 行动面板箭头与收起尺寸

展开时按钮显示 `<`，收起时显示 `>`。按钮固定为 44×44，收起容器固定为 56×56，不把父容器宽度改为 0/1 像素。

## 8. 英雄商店透明 UI

商店根容器及常见 Frame/Body 背景、边框和阴影设为透明。单个英雄报价卡保留轻微半透明底，以保证文字与购买按钮可读。

## 9. 矩形战场

逻辑默认使用两个 1200×900 准备区拼成 2400×900 紧凑矩形；单个准备区略大于原 1040×760 待命区。准备阶段我方只能位于左半区、敌方只能位于右半区；开战关闭中线视觉/导航门并开放全场。Lua 同时钳制场上英雄的移动订单并定时纠正战斗单位越界，避免影响小精灵和待命区。

`content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap` 现已实际包含三枚边界 marker、四面永久可视 `func_brush` 外墙、四块 `nonavclip` 导航 slab，以及分离的 visual/nav 中线 `func_brush`。`ArenaController` 在开战时同时隐藏 visual、解除 nav 碰撞，在准备/结算时恢复二者；Lua 的 0.2 秒纠正仍只是第二层保护。修复包 overlay 也包含同一 VMAP，安装到有自定义地图的 checkout 前应先审查/备份并按 Hammer 说明合并。

## 10. 原版商店购买

初始化时开启 Universal Shop，并启用 easy-buy；准备阶段订单过滤器放行购买、出售、给予、移动、拾取、丢弃、拆分与合成锁等原版物品订单。等待区和场上英雄均需设置为玩家拥有且可控。`FIGHT`、`COUNTDOWN`、`SETTLE` 阶段继续阻止玩家购买和升级。

## 验收边界

自动测试只验证 Lua/JS/XML 语法、服务逻辑和模拟订单。以下内容必须在 Dota 2 Workshop Tools 中验收：真实物品合成/堆叠、原版技能升级按钮、专用服务器商店行为、TacticEngine 与兜底 AI 的优先级、Panorama 实际 Panel ID，以及 Hammer 导航连通性。
