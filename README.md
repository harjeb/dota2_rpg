# Dota 2 RPG Combat Demo

这是一个 Lua + Panorama 的 Dota 2 Workshop Tools 单人 PVE 自定义游戏 addon：玩家在准备阶段招募英雄、配置规则和装备，战斗阶段由服务端自动执行。

## 当前玩法边界

- 每局 Run 只保存在服务端内存；不使用 Panorama `LocalStorage`、跨局存档、存档码、每日重置或迁移。第 30 关胜利后当前 Run 进入终局，不会重复发放终局奖励。
- 初始金币为 **500**；开局拥有 **2 次免费招募选择**。系统不随机赠送英雄，前两次成功选择免费，之后按招募等级固定价格扣款。
- 英雄价格由招募等级决定：1/5/10/15/20/24 级分别为 500/900/1600/2600/4000/5500；品质只决定出现概率和内置魔晶/神杖效果，不乘价格倍率。
- 关卡经验按英雄发放：上阵英雄获得表中全部经验，待命英雄获得向下取整的 50%；升级使用累计经验阈值的相邻差值。时间金币奖励上限为基础金币的 10%。
- 英雄商店报价由服务端生成，每次 5 个不重复报价。普通 Dota 装备完全交给 Valve 原版商店处理，项目装备面板只保留低级/高级经验卷轴、小精灵真实库存和当前上阵英雄之间的实体 ID 转交。
- 普通装备的购买、出售、合成、堆叠、充能和原版价格不由项目复制；项目只在 `setup` 阶段接收装备转移、丢弃、拾取、卷轴购买/使用等操作。
- 战术规则结构为：动作 → 目标硬条件 → 目标优先级 → 使用条件（AND）→ 接近策略。不存在“目标存在”条件；同一技能/主动装备可以出现在多条规则中。Panorama 通过 `rpg_update_rule` 逐条同步，服务端按英雄名稳定键保存当前 Run 规则。
- 敌方英雄的等级和原版装备由 `scripts/data/levels.kv` 配置并在生成时实际装备；敌我双方共用修订版战术执行引擎。

## 重要文件

- 规则与进度：
  - `game/dota_addons/dota2_rpg/scripts/vscripts/data/progression_data.lua`
  - `game/dota_addons/dota2_rpg/scripts/vscripts/patches/recruitment_patch.lua`
  - `game/dota_addons/dota2_rpg/scripts/vscripts/patches/progression_patch.lua`
  - `game/dota_addons/dota2_rpg/scripts/vscripts/patches/enemy_items_patch.lua`
- 服务端入口：`game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua`
- 战术接线：`game/dota_addons/dota2_rpg/scripts/vscripts/tactics/rule_service.lua`、`tactic_bridge.lua`
- 关卡数据：`game/dota_addons/dota2_rpg/scripts/data/levels.kv`
- UI：`content/dota_addons/dota2_rpg/panorama/layout/custom_game/rpg_demo_hud.xml`、`scripts/custom_game/rpg_demo_hud.js`、`scripts/custom_game/panorama_rule_sync.js`
- 原版商店边界说明：[`docs/native-dota-shop-integration.md`](docs/native-dota-shop-integration.md)
- 设计参考：[`_revised_review/dota2_rpg_revised/DESIGN_REVISED.md`](_revised_review/dota2_rpg_revised/DESIGN_REVISED.md)

## 静态检查

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-addon.ps1
```

也可以单独运行：

```powershell
node --check .\content\dota_addons\dota2_rpg\panorama\scripts\custom_game\rpg_demo_hud.js
node --check .\content\dota_addons\dota2_rpg\panorama\scripts\custom_game\panorama_rule_sync.js
node .\tests\panorama-save.test.js
```

`tests/shop-state.test.lua` 和 `tests/precache-battlefield.test.lua` 需要 Lua/Lupa 环境。上述检查只验证源码契约、数据和 UI 静态结构，不等同于原版 Dota 商店在干净地图中的实机购买/出售/合成验收。

## 部署

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-addon.ps1 -Compile
```

本次实现没有要求启动游戏；如果后续进行实机验收，应重点确认原版 `PURCHASE_ITEM`、`SELL_ITEM`、`DISASSEMBLE_ITEM` 的真实订单字段、无目标购买归属、出售范围以及原版物品转交行为，并据此再更新 `docs/native-dota-shop-integration.md` 的验收状态。
