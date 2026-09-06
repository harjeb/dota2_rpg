# `addon_game_mode.lua` 接线说明

自动安装器会在文件末尾追加：

```lua
require("issue_fixes.bootstrap").Install(CDota2RpgDemo)
```

启动日志应出现：

```text
[RPG][IssueFixes] bootstrap installed (spawn=..., start=..., end=...)
```

任何一项为 `nil`，说明 compatibility bootstrap 没识别到你的方法名，应按本页显式接线。

## 1. 初始化

在创建现有 `OrderFilter` 后初始化：

```lua
local IssueFixes = require("issue_fixes.init")

self.issueFixes = IssueFixes.new({
    game_mode_entity = GameRules:GetGameModeEntity(),
    get_phase = function()
        return self.state.phase -- 必须返回 PREPARE/COUNTDOWN/FIGHT/SETTLE
    end,
    get_player_units = function()
        return self.currentPlayerUnits or {}
    end,
    is_roster_hero = function(playerID, hero)
        return self:IsRosterHero(playerID, hero)
    end,
    order_gate = self.filters.gate,
    bind_tactic_profile = function(unit, profile, entry)
        -- 改成项目现有 TacticBridge 的真实注册函数。
        self.tacticBridge:RegisterEnemyUnit(unit, profile, entry)
    end,
})
self.issueFixes:Install()
```

`Install()` 只做本 issue 范围的事情：加载待命 modifier、开启原版商店购买、安装小精灵转交事件、读取战场边界并启动越界检查。

## 2. 准备阶段英雄

每次重新生成或换阵容后：

```lua
self.issueFixes:PrepareRoster(playerID, activeHeroUnits, benchHeroUnits)
```

如果项目单独维护未分配技能点：

```lua
local RosterAccess = require("issue_fixes.roster_access")
RosterAccess.EnsureAbilityPoints(hero, heroData.skill_points)
```

不要再给准备阶段英雄使用以下状态：

```lua
MODIFIER_STATE_STUNNED
MODIFIER_STATE_COMMAND_RESTRICTED
```

待命英雄改用本包的 `modifier_rpg_prepare_bench`。它会限制移动/攻击/施法，但保留技能升级和原版商店订单。

## 3. 小精灵装备转交

前端按钮发送：

```javascript
GameEvents.SendCustomGameEventToServer("rpg_transfer_warehouse_item", {
    source_entindex: courierIndex,
    item_entindex: itemIndex,
    hero_entindex: selectedHeroIndex
});
```

如果保留现有服务器事件，不要复制物品名称后删除源物品，直接调用：

```lua
self.issueFixes:TransferWarehouseItem(
    playerID,
    warehouseCourier,
    sourceItem,
    targetHero
)
```

成功后刷新仓库和英雄物品栏 UI。不要在调用后再执行：

```lua
UTIL_Remove(sourceItem)
sourceItem:RemoveSelf()
```

## 4. 默认行动规则

删除所有根据主动技能数、主动装备数或固定上限补齐默认规则的循环，例如：

```lua
while #rules < slotCount do
    table.insert(rules, BuildDefaultRule(...))
end
```

替换为：

```lua
local DefaultRules = require("issue_fixes.default_rules")
heroData.rules = DefaultRules.Normalize(heroData.rules)
```

没有玩家规则时只会得到一条：普通攻击 → 最近敌人 → 仅范围内。玩家增加规则后不再自动补行。

## 5. 当前关敌人注册

生成本关全部单位后，保存真实句柄，并用本关配置绑定：

```lua
self.currentEnemyUnits = spawnedEnemyUnits
self.issueFixes:RegisterCurrentStage(
    currentLevel.enemies,
    self.currentEnemyUnits
)
```

不要使用：

```lua
{ enemyHero1, enemyHero2, enemyHero3 }
```

也不要从演示 3v3 配置构造 AI 列表。`EnemyRuntime` 会展开每个 `entry.count`，再用 `entries[i]` 对应 `spawnedEnemyUnits[i]`。

## 6. 开始战斗

在状态正式切到 `FIGHT` 后调用：

```lua
self.issueFixes:OnBattleStarted(
    self.currentPlayerUnits,
    self.currentEnemyUnits
)
```

这会：

- 打开中线 visual/nav gate；
- 清理中线可选树木；
- 解除敌人准备状态；
- 开启 IdleAcquire 和 AcquisitionRange；
- 对所有本关敌人发出首次攻击；
- 启动 0.25 秒空闲兜底，不打断引导和当前有效攻击目标。

## 7. 战斗结束

```lua
self.issueFixes:OnBattleEnded(allCurrentUnits)
```

这会停止敌人兜底，并恢复中线门进入下一关准备阶段。

## 8. 订单过滤

本包提供完整替换文件：

```text
game/dota_addons/dota2_rpg/scripts/vscripts/tactics/order_filter.lua
```

现有初始化保持同样接口：

```lua
self.filters = Filters.OrderFilter.new({
    get_phase = function() return self.state.phase end,
    is_battle_unit = function(unit) return self:IsBattleUnit(unit) end,
    validate_prepare_order = function(filterTable)
        return self.issueFixes:ValidatePrepareOrder(filterTable)
    end,
})
```

关键语义：

- PREPARE：放行升级技能、购买、出售、移动/给予/拾取物品；移动位置仍走矩形战场校验。
- COUNTDOWN/FIGHT/SETTLE：阻止玩家手动控制。
- FIGHT 且 `issuer_player_id_const == -1`：允许引擎/服务器 AI 订单。
- `OrderGate:Execute()`：始终允许 TacticEngine 内部订单。

## 9. 第 1/2 关配置

运行时兼容层会在检测到两关签名相同后只替换第 2 关的敌人，不改奖励。正式版本仍应按 `LEVELS_STAGE_1_2.md` 修改 `levels.kv`，避免依赖运行时修复。
