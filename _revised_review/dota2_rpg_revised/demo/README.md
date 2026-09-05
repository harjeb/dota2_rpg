# Dota 2 RPG 修订版 Demo 骨架

本目录对应 `DESIGN_REVISED.md`，重点演示以下难点：

1. 《圣兽之王》式规则：动作、目标硬条件、目标优先级、使用条件分离。
2. 同一技能可配置多条规则；无目标时自动检查下一条。
3. 服务端权威的规则验证、订单过滤、订单去重和有限追击。
4. 不使用存档：所有状态只保存在当前比赛服务端内存。
5. 自建商店与虚拟仓库；装备时才生成真实 Dota 物品。
6. 30 级经验曲线、逐关金币/经验。
7. 羁绊快照和无存档词缀稳定随机。

## 接入顺序

在 `addon_game_mode.lua` 中按以下顺序初始化：

```lua
LinkLuaModifier("modifier_rpg_bond_stats", "modifiers/modifier_rpg_bond_stats", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_opening_shield", "modifiers/modifier_rpg_opening_shield", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_hunt_mark", "modifiers/modifier_rpg_hunt_mark", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_affix_blood_frenzy", "modifiers/modifier_rpg_affix_blood_frenzy", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_affix_thick_hide", "modifiers/modifier_rpg_affix_thick_hide", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_rpg_affix_spell_shell", "modifiers/modifier_rpg_affix_spell_shell", LUA_MODIFIER_MOTION_NONE)

local Progression = require("progression/progression")
local OrderFilter = require("tactics/order_filter")
local TacticEngine = require("tactics/tactic_engine")
local ShopService = require("shop/shop_service")
local BondSystem = require("bonds/bond_system")
local AffixSystem = require("affixes/affix_system")
```

然后把项目现有的 BattleManager 作为依赖注入：

- `get_phase()`
- `get_battle_units()`
- `get_rules(unit)`
- `build_context(unit)`
- `is_battle_unit(unit)`
- `is_roster_hero(player_id, hero)`
- `get_active_lineup(player_id)`

## 重要限制

- 这是工程骨架，不包含完整地图、全部英雄 adapter、全部词缀 modifier 或完整 UI 美术。
- `action_adapter.lua` 只通用处理单位目标、点目标、无目标、切换和普通攻击。向量技能、树木目标、双阶段技能必须写专用 adapter。
- 词缀数据中 `enabled = false` 的项目只是接口样例；补齐对应 modifier、特效、日志和回归测试后才能开启。
- Dota 只允许每类 script filter 安装一个回调。若项目已有 damage/order filter，应把本 Demo 的逻辑合并到中央 FilterManager，而不是重复安装。
- 自建商店必须在上传后的专用服务器测试；不要只依赖本地 Tools 模式。
- 命石/英雄变体、主动先天技能和 30 级天赋行为必须逐英雄在专用服务器登记；示例兼容表中的字段不是自动检测结果。
- 本 Demo 不读写 `LocalStorage`，也不包含任何存档接口。
