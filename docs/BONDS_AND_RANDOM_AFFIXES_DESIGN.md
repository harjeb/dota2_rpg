# 羁绊与敌方随机词缀具体设计

> 文档状态：实现规格草案
>
> 适用版本：基础 30 关、经济和战术规则稳定后的后期版本
>
> 关联总设计：`DESIGN.md` §9
>
> 当前实现状态：仓库只有 `bond_service_demo.lua`、`affix_service_demo.lua` 和 3 个 modifier 原型；本文件描述目标行为，不表示功能已经接入主流程。

## 1. 设计结论

羁绊服务于玩家的长期阵容构筑，随机词缀服务于当前关卡的战前解题。二者都必须增强“观察情报 → 配规则 → 自动验证”的核心循环，不能把胜负重新变成纯数值或重开刷随机数。

首发版本采用以下固定口径：

| 项目 | 结论 |
| --- | --- |
| 羁绊对象 | 仅玩家实际上阵英雄 |
| 羁绊标签 | 当前 32 名可招募英雄每人固定 2 个标签 |
| 羁绊阈值 | 常规羁绊均为 2/3/5；只生效达到的最高档 |
| 羁绊计算时点 | 准备阶段实时预览，开战按钮通过校验后生成不可变快照 |
| 词缀对象 | 当前关卡的敌方英雄和野怪，不作用于召唤物与分身 |
| 词缀预算 | 第 1~4 关为 0；之后按 1/2/3/4/5/6 点递增 |
| 词缀随机性 | 关卡首次生成后持久化到当前 Run；失败、换阵和重试不重抽 |
| 情报 | 开战前公开敌人、词缀、准确数值、触发条件和反制标签 |
| 经济 | 不修改金币、经验、掉落、招募价格、刷新价格和卷轴限购 |
| 功能开关 | `enable_bonds` 与 `enable_affixes` 独立启停 |

## 2. 目标与非目标

### 2.1 目标

- 让招募报价产生“补羁绊还是补单卡能力”的可读选择。
- 让同一套阵容能围绕不同羁绊调整站位、装备和行动规则。
- 让固定关卡出现可复现的战术变体，同时保留失败后的学习价值。
- 所有强效果都必须有 UI、状态图标和战斗日志三种反馈中的至少两种。
- 服务器是唯一权威；Panorama 只展示快照，不能提交羁绊或词缀结果。

### 2.2 非目标

- 不做跨局收藏、赛季词缀、每日词缀或账号成长。
- 不让敌人读取玩家阵容、装备、羁绊或规则后定向克制。
- 不允许花金币重抽敌方词缀，也不允许失败后自动降级词缀。
- 不让羁绊自动选择目标、插入玩家规则或改变规则优先级。
- 不把 Dota 原生英雄技能名直接当作羁绊；羁绊标签是本项目自己的稳定数据。
- 首发版本不开放玩家装备随机词缀，避免与原版 Dota 商店物品语义冲突。

## 3. 共同术语与权威边界

| 术语 | 定义 |
| --- | --- |
| Contributor | 对某个羁绊贡献人数的上阵英雄 |
| Lineup | 点击开始战斗时服务器确认的上阵英雄集合，最多 5 名 |
| Bond preview | 准备阶段根据当前 Lineup 计算的可变预览，不产生战斗效果 |
| Bond snapshot | 本次战斗使用的不可变羁绊档位和最终参数 |
| Unit profile | 敌方单位的基础职责标签，例如 `frontliner`、`healer` |
| Spawn key | 某个敌人在关卡配置中的稳定实例键，不使用实体索引 |
| Threat point | 随机词缀的强度预算单位，普通/稀有/史诗分别为 1/2/3 点 |
| Affix roll | 某关完整的“敌人实例 → 词缀”持久化结果 |
| Counter tag | 提示玩家可使用的反制方向，不直接替玩家修改规则 |

权威数据流固定为：

```text
JSON source data
  -> build-time validation
  -> generated KV runtime data
  -> server-side preview/roll/snapshot
  -> flattened CustomGameEvent payload
  -> Panorama rendering only
```

JSON 是策划源数据，KV 是 Dota 运行时数据。两份文件不得人工分别维护；生成器必须覆盖 KV，并在 CI 中验证生成结果无差异。

## 4. 玩家羁绊系统

### 4.1 计数规则

1. 只读取服务器 `self.lineup` 中的稳定英雄名。
2. 同一英雄名最多计数一次；重复实体、分身、幻象、召唤物和小精灵占位英雄不计数。
3. 每名英雄读取恰好 2 个不同的 `bond_tags`；缺失、未知或重复标签均为构建错误。
4. 每个羁绊分别计数；达到多个阈值时只选择最高阈值，不叠加低档数值。
5. 不同羁绊可以同时激活，但效果进入统一叠加组和全局上限。
6. 英雄死亡不减少羁绊；复活不重复添加羁绊；战斗中不得重新计算。
7. 准备阶段换人后重新计算预览。只有 `OnStartBattle` 的服务器校验通过后，预览才冻结为战斗快照。

### 4.2 当前 32 名英雄标签表

标签分为两层：第一层描述基本作战阵位，第二层描述战术配合。每名英雄恰好从两层各取一个标签，避免某些英雄天然更容易凑出多羁绊。

| 属性 | 英雄 | 第一标签 | 第二标签 |
| --- | --- | --- | --- |
| 力量 | Axe | `ironwall` 坚阵 | `executioner` 处决 |
| 力量 | Sven | `duelist` 争锋 | `breaker` 破阵 |
| 力量 | Dragon Knight | `ironwall` 坚阵 | `guardian` 守护 |
| 力量 | Huskar | `duelist` 争锋 | `executioner` 处决 |
| 力量 | Sand King | `ironwall` 坚阵 | `breaker` 破阵 |
| 力量 | Centaur Warrunner | `ironwall` 坚阵 | `breaker` 破阵 |
| 力量 | Mars | `ironwall` 坚阵 | `breaker` 破阵 |
| 力量 | Omniknight | `ironwall` 坚阵 | `guardian` 守护 |
| 敏捷 | Juggernaut | `duelist` 争锋 | `guardian` 守护 |
| 敏捷 | Phantom Assassin | `duelist` 争锋 | `executioner` 处决 |
| 敏捷 | Sniper | `backline` 后阵 | `executioner` 处决 |
| 敏捷 | Drow Ranger | `backline` 后阵 | `fieldcraft` 控场 |
| 敏捷 | Faceless Void | `mystic` 秘仪 | `fieldcraft` 控场 |
| 敏捷 | Ursa | `duelist` 争锋 | `executioner` 处决 |
| 敏捷 | Troll Warlord | `duelist` 争锋 | `breaker` 破阵 |
| 敏捷 | Clinkz | `backline` 后阵 | `fieldcraft` 控场 |
| 智力 | Lina | `mystic` 秘仪 | `executioner` 处决 |
| 智力 | Lion | `mystic` 秘仪 | `executioner` 处决 |
| 智力 | Crystal Maiden | `mystic` 秘仪 | `guardian` 守护 |
| 智力 | Witch Doctor | `backline` 后阵 | `guardian` 守护 |
| 智力 | Dazzle | `backline` 后阵 | `guardian` 守护 |
| 智力 | Shadow Shaman | `backline` 后阵 | `fieldcraft` 控场 |
| 智力 | Lich | `mystic` 秘仪 | `fieldcraft` 控场 |
| 智力 | Zeus | `mystic` 秘仪 | `breaker` 破阵 |
| 全才 | Marci | `duelist` 争锋 | `fieldcraft` 控场 |
| 全才 | Primal Beast | `ironwall` 坚阵 | `breaker` 破阵 |
| 全才 | Dawnbreaker | `ironwall` 坚阵 | `guardian` 守护 |
| 全才 | Muerta | `mystic` 秘仪 | `executioner` 处决 |
| 全才 | Snapfire | `backline` 后阵 | `fieldcraft` 控场 |
| 全才 | Void Spirit | `duelist` 争锋 | `breaker` 破阵 |
| 全才 | Io | `backline` 后阵 | `guardian` 守护 |
| 全才 | Phoenix | `mystic` 秘仪 | `fieldcraft` 控场 |

每个标签都有 8 名英雄。新增或移除可招募英雄时，必须同时更新标签覆盖测试；不要求永远保持每组 8 人，但任一标签可招募成员少于 6 人时不得发布。

### 4.3 八个羁绊的首发数值

表中百分比均为百分点。`Contributors` 表示只影响贡献该标签的英雄，`Lineup` 表示影响本次上阵的全部英雄。

| ID / 名称 | 作用域 | 2 人 | 3 人 | 5 人 |
| --- | --- | --- | --- | --- |
| `ironwall` 坚阵 | Contributors | 最大生命 +5% | 最大生命 +9%，护甲 +2 | 最大生命 +13%，护甲 +4；开战获得最大生命 8% 的护盾，持续 8 秒 |
| `duelist` 争锋 | Contributors | 攻速 +10 | 攻速 +18 | 攻速 +28；开战前 10 秒额外获得 8% 移速 |
| `mystic` 秘仪 | Contributors | 总魔法恢复 +8% | 总魔法恢复 +15%，技能增强 +4% | 总魔法恢复 +22%，技能增强 +7%；首次成功施法返还实际魔耗的 30% |
| `backline` 后阵 | Contributors | 攻击距离和施法距离 +50 | 攻击距离和施法距离 +85 | 攻击距离和施法距离 +120；开战 8 秒内受到的首次英雄伤害降低 25% |
| `executioner` 处决 | Contributors | 对生命不高于 30% 的敌人伤害 +6% | 对生命不高于 30% 的敌人伤害 +10% | 对生命不高于 35% 的敌人伤害 +14% |
| `breaker` 破阵 | Contributors | 开战 8 秒内移速 +5% | 开战 8 秒内移速 +8%、伤害 +4% | 开战 10 秒内移速 +10%、伤害 +8% |
| `guardian` 守护 | Lineup | 治疗增强 +6% | 治疗增强 +10%；开战获得最大生命 4% 的护盾，持续 8 秒 | 治疗增强 +15%；开战护盾提高到 8%，持续 10 秒 |
| `fieldcraft` 控场 | Lineup | 被贡献者施加硬控或沉默的敌人获得 4 秒“破绽”，受到伤害 +4% | “破绽”受到伤害 +7% | “破绽”受到伤害 +10%，持续时间提高到 5 秒 |

补充语义：

- “技能增强”使用 Dota 的 spell amplification，只影响引擎认定的技能伤害，不放大物品固定伤害、攻击伤害或生命移除。
- “首次成功施法”以 `dota_player_used_ability` 对应到该实体且实际消耗魔法为准；切换开关、取消施法和 0 魔耗技能不消耗返还机会。
- “首次英雄伤害”排除生命消耗、反伤、友军伤害和地图伤害；被降低后立即消耗保护次数。
- “硬控”首发仅包含眩晕、妖术、睡眠、恐惧、嘲讽、缠绕和龙卷；减速不算硬控。沉默单独计入。
- “破绽”由造成控制的 Contributor 触发，但增伤可被全体 Lineup 使用；刷新持续时间，不叠加层数。
- 开战限时效果从 `BattleManager:StartBattle` 的服务器时间开始，不从单位解除禁足的各自时间开始。

### 4.4 叠加顺序和硬上限

所有羁绊先选择最高档，再按下表合并。羁绊内部数值为加法，不与装备或英雄技能共享本表上限。

| Stacking group | 合并方式 | 羁绊总上限 |
| --- | --- | ---: |
| `bond_health_pct` | 加法 | 15% |
| `bond_armor_flat` | 加法 | 5 |
| `bond_attack_speed_flat` | 加法 | 35 |
| `bond_move_speed_pct` | 加法 | 12% |
| `bond_mana_regen_pct` | 加法 | 25% |
| `bond_spell_amp_pct` | 加法 | 10% |
| `bond_range_flat` | 同时加到攻击和施法距离 | 150 |
| `bond_heal_amp_pct` | 加法 | 18% |
| `bond_outgoing_damage_pct` | 对单次伤害事件合并 | 18% |
| `bond_incoming_damage_pct` | 对单次伤害事件合并 | 15% |
| `bond_opening_shield_pct` | 取最高值，不相加 | 10% 最大生命 |

单次伤害可能同时命中处决、破阵和破绽。此时先相加，再应用 `bond_outgoing_damage_pct` 的 18% 上限，最后交给护甲、魔抗、格挡和词缀减伤。该顺序必须在离线模拟器和 Dota 运行时一致。

### 4.5 预览与快照

准备阶段每次以下状态变化都重新广播 `rpg_bond_preview`：招募成功、换人、上阵人数变化、进入下一关后的阵容重建、客户端请求完整状态。

预览结构：

```json
{
  "lineup_revision": 17,
  "bonds": [
    {
      "id": "ironwall",
      "members": 3,
      "active_tier": 3,
      "next_tier": 5,
      "member_names_text": "npc_dota_hero_axe;npc_dota_hero_mars;npc_dota_hero_dawnbreaker",
      "effect_text_key": "#rpg_bond_ironwall_3"
    }
  ]
}
```

点击开始战斗时按以下顺序执行：

1. 校验 `phase == "setup"`、阵容非空且实体与 `self.lineup` 一致。
2. 重新计算服务器羁绊结果，不复用客户端预览。
3. 生成 `battle_id` 和 `bondSnapshot`，记录 `lineup_revision`、成员、档位、合并后参数和 `data_version`。
4. 给我方上阵英雄添加对应 modifier；任何一步失败都拒绝开战并保持 `setup`。
5. 完成后才设置 `phase = "fight"`、解除战前限制并调用 `BattleManager:StartBattle`。

战斗结算回到准备阶段时移除全部 `modifier_rpg_bond_*`。旧实体被销毁时无需反向写回基础属性，避免百分比生命加成被重复烘焙。

### 4.6 招募和编队 UI

招募卡片在英雄名下显示两个羁绊徽章。徽章右上角显示购买并上阵后的变化：

- `1/2 → 2/2` 使用绿色，表示立即激活。
- `2/3 → 3/3` 使用金色，表示升档。
- 已达到 5 人时显示 `5/5`，不再显示溢出人数。
- 英雄尚未购买时只预览“购买并替换当前最后一名上阵英雄”的结果，不自动改变实际阵容。

编队面板固定显示 8 个羁绊条目：已激活在前、接近阈值其次、0 人最后。每个条目展示当前人数、下一阈值、准确数值和成员头像。换人悬停预览分成“获得”“升档”“失去”“降档”四类，不使用只写“战力 +X”的综合分。

战斗中羁绊面板折叠为已激活图标；点击可查看本次快照，但不可编辑。

## 5. 敌方随机词缀系统

### 5.1 敌方职责标签

词缀白名单不直接根据英雄名写死。服务器将 `unit_profiles` 基础标签和 `levels` 当前实例标签取并集：

| 标签 | 含义 | 典型来源 |
| --- | --- | --- |
| `combat_unit` | 所有可获得词缀的正式敌人 | 所有关卡敌人 |
| `frontliner` | 预期在前排承伤 | 坦克英雄、近战巨兽 |
| `attacker` | 普攻是主要威胁 | 物理核心、射手 |
| `caster` | 主动技能伤害或控制是主要威胁 | 法师、技能型野怪 |
| `healer` | 有可稳定执行的治疗动作 | 治疗英雄、治疗野怪 |
| `support` | 主要提供强化、护盾或召唤 | 辅助英雄、支援野怪 |
| `controller` | 至少有一条可执行硬控或沉默规则 | 控制英雄、控制野怪 |
| `diver` | AI 具备突进或后排接近策略 | 刺客、冲阵单位 |
| `leader` | 本关承担核心职责 | 关卡实例标签 |
| `boss` | 章节 Boss | 关卡实例标签 |
| `final_boss` | 第 30 关最终 Boss | 关卡实例标签 |

每个敌方实例必须解析出 `combat_unit` 和至少一个职责标签。`elite` 只表示关卡身份，不替代职责标签。召唤物、分身和战斗中临时生成单位标记为 `affix_ineligible`，不会继承召唤者词缀；如果某个词缀需要影响召唤物，效果必须明确写在召唤者 modifier 内。

### 5.2 威胁预算与分配

| 关卡 | 总预算 | 稀有度开放 | 最少覆盖敌人数 | 单位上限 |
| --- | ---: | --- | ---: | --- |
| 1~4 | 0 | 无 | 0 | 0 |
| 5~9 | 1 | 普通 | 1 | 1 |
| 10~14 | 2 | 普通、稀有 | 1 | 普通单位 2，Boss 3 |
| 15~19 | 3 | 普通、稀有 | 2 | 普通单位 2，Boss 3 |
| 20~24 | 4 | 普通、稀有、史诗 | 2 | 普通单位 2，Boss 3 |
| 25~29 | 5 | 普通、稀有、史诗 | 3 | 普通单位 2，Boss 3 |
| 30 | 6 | 普通、稀有、史诗 | 3，且至少 1 个非最终 Boss | 普通单位 2，最终 Boss 3 |

普通、稀有、史诗固定消耗 1、2、3 点。抽取结果必须恰好用完预算。单关同一词缀最多出现 2 次；同一敌人不允许重复词缀，也不允许两个相同 `stacking_group`。

分配偏好不属于硬规则，但参与权重：

- `leader` 候选权重 ×1.35。
- `boss` 和 `final_boss` 候选权重 ×1.50。
- 已有 1 个词缀的普通单位，后续候选权重 ×0.60。
- 尚未达到最少覆盖敌人数时，新单位候选权重 ×1.80。
- 权重只影响同一合法集合内的选择，不得突破预算、白名单或互斥规则。

### 5.3 首发词缀池

#### 普通词缀：1 点，权重 100

| ID / 名称 | 允许标签 | 准确效果 | 反制标签 | 互斥组 |
| --- | --- | --- | --- | --- |
| `hardened` 坚韧 | `combat_unit` | 最大生命 +6% | `focus_fire`, `sustain_damage` | `body_defense` |
| `thick_hide` 厚皮 | `frontliner`, `attacker` | 最大生命 +12%；受到的物理攻击伤害降低 5% | `magic_damage`, `armor_reduction` | `body_defense` |
| `spell_shell` 法术护壳 | `combat_unit` | 首次受到来自敌方英雄的魔法或纯粹技能伤害降低 40%，随后护壳消失；可被基础驱散提前移除 | `dispel`, `spell_poke`, `physical_damage` | `spell_defense` |
| `blood_frenzy` 血怒 | `attacker`, `diver`, `frontliner` | 生命不高于 35% 时攻速 +25、移速 +10% | `control`, `execute`, `burst_damage` | `low_health` |
| `sundering_hits` 裂甲 | `attacker`, `diver` | 普攻命中使目标护甲 -2，持续 5 秒；重复命中只刷新 | `dispel`, `kite`, `control` | `attack_pressure` |
| `mending_focus` 愈合专注 | `healer` | 自身造成的治疗 +18% | `anti_heal`, `focus_healer` | `healing_power` |
| `warding_aura` 护阵光环 | `support`, `frontliner`, `leader` | 自身和 600 范围友军护甲 +2；同名光环不叠加 | `magic_damage`, `separate_enemies`, `focus_aura` | `defense_aura` |

#### 稀有词缀：2 点，权重 55，第 10 关开放

| ID / 名称 | 允许标签 | 准确效果 | 反制标签 | 互斥/排除 |
| --- | --- | --- | --- | --- |
| `barrier_heart` 壁垒之心 | `frontliner`, `leader`, `boss`, `final_boss` | 首次降到 50% 生命时获得最大生命 18% 的护盾，持续 6 秒；触发有 0.6 秒特效预警 | `dispel`, `switch_target`, `sustain_damage` | `low_health`; 排除 `blood_frenzy` |
| `purging_pulse` 净化脉冲 | `support`, `healer`, `controller`, `boss` | 开战后第 8 秒首次触发，此后每 14 秒一次；1.5 秒预警后对自身和 450 范围友军执行基础驱散 | `stagger_control`, `burst_window`, `separate_enemies` | `cleanse` |
| `grave_rally` 墓前号令 | `support`, `leader`, `frontliner` | 死亡时使 900 范围友军获得攻速 +25、移速 +10%，持续 6 秒；同名效果只刷新 | `kill_order`, `separate_enemies`, `control` | `death_trigger` |
| `arcane_surge` 奥术涌动 | `caster`, `controller` | 每 10 秒准备一次强化；下一次造成英雄技能伤害时伤害 +20% 并消耗，准备状态有图标 | `bait_spell`, `spell_shell`, `control` | `spell_burst` |
| `backline_hunter` 后排猎手 | `diver`, `attacker` | 开战前 8 秒添加只读 AI overlay：合法目标优先级改为攻击距离最远的玩家英雄；不改变动作、硬条件或施法合法性 | `protect_backline`, `frontline_decoy`, `control` | `targeting_overlay`; 排除 `grave_rally` |

#### 史诗词缀：3 点，权重 25，第 20 关开放

| ID / 名称 | 允许标签 | 准确效果 | 反制标签 | 互斥/排除 |
| --- | --- | --- | --- | --- |
| `warlord_aura` 战争领主 | `leader`, `boss`, `final_boss` | 700 范围内其他敌军造成的攻击和技能伤害 +8%；自身不受益；同名光环不叠加 | `focus_aura`, `separate_enemies`, `control` | `offense_aura`; 排除 `warding_aura` |
| `second_wind` 再起 | `frontliner`, `healer`, `boss`, `final_boss` | 首次降到 30% 生命时，在 6 秒内恢复最大生命 24%；治疗可被驱散并受减疗影响 | `anti_heal`, `dispel`, `burst_damage` | `low_health`; 排除 `blood_frenzy`, `barrier_heart` |
| `unstoppable_momentum` 不竭势能 | `attacker`, `diver`, `boss`, `final_boss` | 每连续 5 秒未受到硬控，伤害 +4%，最多 3 层；受到硬控立即清空，清空后 2 秒内不重新计时 | `hard_control`, `control_timing`, `focus_fire` | `ramping_offense`; 排除 `backline_hunter` |

首发共 15 个词缀。`hardened` 同时是运行时安全回退词缀，因此必须保持 1 点、允许所有 `combat_unit`、无事件依赖且永远不能被删除。

### 5.4 全局高风险互斥

除单个单位的 `stacking_group` 外，整关还执行以下组合限制：

| 组合 | 规则 | 原因 |
| --- | --- | --- |
| `backline_hunter` + `warlord_aura` | 整关不可同时出现 | 后排锁定与团队增伤叠加过强 |
| `arcane_surge` + `unstoppable_momentum` | 不得出现在同一单位 | 爆发与持续成长同时存在难以读懂 |
| `purging_pulse` | 单关最多 1 个 | 多个错峰净化会使控制反制失效 |
| `warlord_aura` | 单关最多 1 个 | 同名不叠加且重复抽取没有有效价值 |
| `second_wind` | 单关最多 1 个 | 防止多核心同时形成减疗硬门槛 |
| `grave_rally` | 单关最多 2 个，且相互距离按初始站位不得小于 350 | 防止同帧死亡触发难以辨认的爆发链 |

词缀不能与关卡固定机制重复。例如关卡 Boss 已有配置化的复苏阶段，则该实例必须在 `excluded_affixes` 中排除 `second_wind`。关卡数据的排除优先级高于词缀自身白名单。

### 5.5 确定性抽取算法

抽取输入只有：

```text
run_seed + level_id + affix_data_version + enemy spawn keys + enemy tags
```

禁止包含玩家 ID、阵容、装备、规则、失败次数、购买次数、系统时间或实体索引。

稳定 `spawn_key` 格式为：

```text
<level_id>:<enemy_entry_index>:<copy_index>
```

例如 `ch16:3:2` 表示第 16 关配置中第 3 个敌人条目的第 2 个实例。实体重建后仍使用同一个键。

抽取步骤：

1. 按 `spawn_key` 排序敌人，按 `affix_id` 排序词缀，禁止依赖 Lua `pairs` 顺序。
2. 合并单位基础职责标签和关卡实例标签，过滤阶段、白名单、实例排除和功能开关。
3. 为每个合法“敌人 × 词缀”候选计算确定性随机值：`Hash31(run_seed, level_id, data_version, spawn_key, affix_id)`。
4. 使用 `-log(U) / effective_weight` 作为候选排序键；相同排序键再按 `spawn_key`、`affix_id` 排序。
5. 深度优先搜索候选，必须同时满足精确预算、最少覆盖人数、单位上限、单关次数和所有互斥。
6. 搜索按排序键从小到大，找到第一个完整合法解即停止；因此相同输入必然得到相同结果。
7. 将完整结果保存到 `self.runState.rolledAffixes[level_id]`，之后只读取，不重新运行随机算法。

构建时验证器必须证明每一关至少存在一个合法精确预算解。若发布版本运行时仍意外无解：

- 写入 `AFFIX_ROLL_FALLBACK` 错误日志，包含关卡、版本和拒绝原因计数。
- 按稳定 `spawn_key` 顺序给前 `budget` 个不同敌人各添加 1 个 `hardened`。
- 若符合条件的敌人少于预算，拒绝进入战斗并保持准备阶段；绝不静默少用预算或临时重抽。

### 5.6 持久化结构

```json
{
  "level_id": "ch20",
  "seed": 734521,
  "data_version": 1,
  "budget": 4,
  "used_budget": 4,
  "fallback_used": false,
  "placements": [
    {
      "spawn_key": "ch20:1:1",
      "unit_name": "npc_dota_hero_mars",
      "affix_id": "barrier_heart",
      "threat_cost": 2
    },
    {
      "spawn_key": "ch20:3:1",
      "unit_name": "npc_dota_hero_lina",
      "affix_id": "arcane_surge",
      "threat_cost": 2
    }
  ]
}
```

必须持久化 `placements`，不能只保存 seed 后在重试时重算。当前 Run 无跨局存档，所以“持久化”仅指 Lua 内存跨本关失败重建保持。通关后旧关结果可保留到 Run 结束用于遥测，但不能再次挑战。

### 5.7 生成和应用时点

关卡首次进入准备阶段时：

1. 先解析当前关卡敌方配置并建立所有 `spawn_key`。
2. 调用 `GetOrRollForCurrentRun` 获取或生成 Affix roll。
3. 生成敌方实体并把 `spawn_key` 写到实体字段 `rpgSpawnKey`。
4. 根据已保存 placement 添加词缀 modifier 和只读 AI overlay。
5. 广播敌方情报；只有所有 placement 都找到对应实体时才允许开始战斗。

失败后重新进入准备阶段时会重建实体，但不会重抽。modifier 的剩余触发次数不跨战斗保留：例如法术护壳、再起和壁垒之心在每次新挑战开始时恢复，因为每次挑战都是新的战斗状态；词缀种类和归属保持不变。

### 5.8 关卡情报 UI

敌方头像右上角显示最多 3 个词缀图标，顺序固定为史诗、稀有、普通，再按 `affix_id`。颜色固定：普通灰蓝、稀有紫、史诗橙。

选中敌人后显示：

```text
壁垒之心 · 稀有 · 2 威胁
首次降到 50% 生命时，获得最大生命 18% 的护盾，持续 6 秒。
反制：驱散 / 换目标 / 持续伤害
```

面板顶部同时显示 `本关词缀威胁：4/4`。准备阶段词缀图标不可隐藏；战斗阶段仍可查看。若触发安全回退，开发版本显示红色 `FALLBACK` 标记，发布版本只写日志并仍展示实际“坚韧”词缀。

### 5.9 战斗反馈与日志

词缀采用以下日志事件：

| Event | 触发时点 | 必填字段 |
| --- | --- | --- |
| `AFFIX_APPLIED` | 敌方实体绑定词缀 | `battle_id`, `spawn_key`, `affix_id` |
| `AFFIX_TRIGGERED` | 一次性或周期效果实际触发 | 上述字段 + `target`, `value` |
| `AFFIX_CONSUMED` | 法术护壳等次数耗尽 | 上述字段 |
| `AFFIX_DISPELLED` | 可驱散效果被移除 | 上述字段 + `source` |
| `AFFIX_ROLL_FALLBACK` | 无合法解 | `level_id`, `seed`, `data_version`, `reason_counts` |

战斗飘字只显示短词，例如“护壳吸收”“净化脉冲”“再起”。同一词缀的周期提示每 2 秒最多出现一次，避免多单位刷屏。

## 6. 数据规格

### 6.1 文件职责

| 策划源文件 | 生成文件 | 内容 |
| --- | --- | --- |
| `scripts/data/heroes.json` | `scripts/data/heroes.kv` | 招募池和每名英雄的 `bond_tags` |
| `scripts/data/bonds.json` | `scripts/data/bonds.kv` | 羁绊定义、档位、作用域、效果 |
| `scripts/data/unit_profiles.json` | `scripts/data/unit_profiles.kv` | 敌方单位基础职责标签 |
| `scripts/data/affixes.json` | `scripts/data/affixes.kv` | 词缀定义、权重、互斥、效果 |
| `scripts/data/levels_v07.json` | `scripts/data/levels.kv` | 关卡实例标签和实例排除 |

当前 `heroes.json` 与 `heroes.kv` 的开放英雄范围并不一致。实施 P1 前必须先确定单一源数据并由生成器重建 KV；羁绊覆盖以运行时实际开放的 32 名英雄为准。

### 6.2 羁绊定义示例

```json
{
  "data_version": 1,
  "bonds": [
    {
      "id": "ironwall",
      "name_key": "#rpg_bond_ironwall",
      "scope": "contributors",
      "thresholds": [
        {
          "count": 2,
          "effects": [
            { "type": "max_health_pct", "value": 5, "stacking_group": "bond_health_pct" }
          ]
        },
        {
          "count": 3,
          "effects": [
            { "type": "max_health_pct", "value": 9, "stacking_group": "bond_health_pct" },
            { "type": "armor_flat", "value": 2, "stacking_group": "bond_armor_flat" }
          ]
        },
        {
          "count": 5,
          "effects": [
            { "type": "max_health_pct", "value": 13, "stacking_group": "bond_health_pct" },
            { "type": "armor_flat", "value": 4, "stacking_group": "bond_armor_flat" },
            { "type": "opening_shield_pct", "value": 8, "duration": 8, "stacking_group": "bond_opening_shield_pct" }
          ]
        }
      ]
    }
  ]
}
```

### 6.3 词缀定义示例

```json
{
  "id": "barrier_heart",
  "name_key": "#rpg_affix_barrier_heart",
  "description_key": "#rpg_affix_barrier_heart_desc",
  "tier": "rare",
  "threat_cost": 2,
  "roll_weight": 55,
  "min_stage": 10,
  "allowed_unit_tags": ["frontliner", "leader", "boss", "final_boss"],
  "excluded_affixes": ["blood_frenzy"],
  "stacking_group": "low_health",
  "max_copies_per_encounter": 2,
  "modifier": "modifier_rpg_affix_barrier_heart",
  "params": {
    "trigger_health_pct": 50,
    "shield_max_health_pct": 18,
    "duration": 6,
    "telegraph_delay": 0.6
  },
  "counter_tags": ["dispel", "switch_target", "sustain_damage"]
}
```

数据层只能引用注册表中已存在的 `effect.type`、`modifier`、`stacking_group`、职责标签和反制标签。不得从 JSON 直接执行任意 Lua 函数名。

## 7. 运行时模块与接入点

### 7.1 目标模块

| 模块 | 职责 |
| --- | --- |
| `data/data_loader.lua` | 加载 `bonds.kv`、`affixes.kv`、`unit_profiles.kv` |
| `tactics/bond_service.lua` | 计算预览、生成快照、合并上限、应用和移除 modifier |
| `tactics/affix_service.lua` | 生成稳定键、确定性抽取、持久化结果、应用 modifier |
| `tactics/affix_registry.lua` | 词缀 ID 到安全实现的显式注册表 |
| `battle/combat_effect_router.lua` | 统一处理伤害、治疗、控制、护盾和一次性触发事件 |
| `battle/battle_manager.lua` | 建立 `battle_id`、固定战斗起点、清理战斗级状态 |
| `addon_game_mode.lua` | 在关卡生成、阵容变化和开战事务中接线并广播 |

现有 `bond_service_demo.lua` 和 `affix_service_demo.lua` 只能作为算法起点。正式接入前需解决以下差异：

- demo 词缀结果用 `unit_index`，目标规格必须用 `spawn_key`。
- demo 依赖输入数组顺序，目标规格必须在服务内显式稳定排序。
- demo 只检查同单位互斥，目标规格还需要整关互斥与次数上限。
- demo 第 30 关没有最少覆盖要求，目标规格要求至少 3 个单位且至少 1 个非最终 Boss。
- `modifier_rpg_affix_thick_hide` 的物理减伤 getter 尚未接入统一伤害路由。
- `modifier_rpg_affix_spell_shell` 尚未消费层数和识别合法技能伤害。
- 正式系统不能在 modifier 内各自重复实现事件过滤规则。

### 7.2 开战事务

开战必须成为一次全有或全无的服务器事务：

```text
validate phase and lineup
  -> validate enemy entities against saved affix roll
  -> compute bond snapshot
  -> apply bond modifiers
  -> reset and apply affix battle state
  -> create battle_id and common effect router
  -> set phase to fight
  -> release units and start BattleManager
```

在 `phase = "fight"` 前任何错误都应回滚本次新加 modifier 并返回准备阶段。不得出现玩家已经能移动或攻击、但一部分羁绊/词缀尚未生效的中间状态。

### 7.3 伤害与事件顺序

统一伤害路由的顺序固定为：

1. 判断伤害是否合法以及攻击者、受害者归属。
2. 计算羁绊条件增伤，应用 18% 羁绊上限。
3. 计算词缀进攻增伤；同一词缀只应用一次。
4. 计算一次性词缀减伤并决定是否消耗。
5. 交给 Dota 原生护甲、魔抗、格挡和护盾。
6. 记录实际伤害，检查低血量触发。
7. 广播战斗日志和遥测。

生命阈值判断使用本次伤害结算后的生命。若一次伤害直接击杀单位，`barrier_heart` 和 `second_wind` 不会把死亡倒转；这两个效果不是免死。

## 8. 本地化与可访问性

- `addon_schinese.txt` 和 `addon_english.txt` 必须同时包含 8 个羁绊、15 个词缀、效果描述和全部反制标签。
- 描述中的数字来自服务器定义生成或参数化替换，不能在 JS 再维护一份数值。
- 词缀稀有度不能只靠颜色区分；图标边框同时显示 1/2/3 个菱形。
- 羁绊升档、降档同时使用图标和文字，不只用绿/红颜色。
- 动画关闭时仍保留状态图标、倒计时文本和战斗日志。

## 9. 验证方案

### 9.1 数据静态验证

发布构建必须验证：

- 运行时开放的每名英雄恰好有 2 个不同且存在的羁绊标签。
- 每个羁绊至少有 6 名可招募成员，阈值严格递增且为 2/3/5。
- 所有效果类型、叠加组、modifier 和本地化键存在。
- 词缀威胁点等于稀有度规定值，阶段开放合法，反制标签至少 2 个。
- 所有 `excluded_affixes` 对称化后无未知 ID。
- 每个关卡敌人都有稳定 `spawn_key`、`combat_unit` 和至少一个职责标签。
- 关卡实例的固定机制与词缀排除声明完整。
- 对第 1~30 关分别枚举至少 10,000 个固定 seed，全部精确用完预算且满足互斥。
- JSON 生成 KV 后 `git diff --exit-code` 无差异。

### 9.2 羁绊单元测试

| 用例 | 预期 |
| --- | --- |
| 同一英雄名出现两次 | 每个标签只计 1 人 |
| Axe + Dragon Knight | `ironwall` 激活 2 档 |
| Axe + Dragon Knight + Mars | 只生效 3 档，不叠加 2 档 |
| 5 个坚阵成员中 1 人死亡 | 快照和效果不变 |
| 战斗中生成英雄幻象 | 不增加任何羁绊人数 |
| 准备阶段替换英雄 | 预览 revision 增加，旧预览失效 |
| 羁绊增伤同时命中三种条件 | 合计不超过 18% |
| 关闭 `enable_bonds` | 基础属性、伤害结果与当前基线一致 |

### 9.3 词缀单元测试

| 用例 | 预期 |
| --- | --- |
| 同关卡、同 seed、敌人输入顺序不同 | placement 完全相同 |
| 同关卡失败后重建实体 | `spawn_key` 和词缀归属不变 |
| 调整玩家阵容、装备和规则 | 词缀归属不变 |
| 第 1~4 关 | 预算和 placement 均为 0 |
| 第 25~29 关 | 恰好 5 点且覆盖至少 3 个敌人 |
| 第 30 关 | 恰好 6 点、覆盖至少 3 个敌人且包含非最终 Boss |
| 同单位候选含两个 `low_health` | 最多选中一个 |
| 无合法解 | 记录 fallback，并按稳定顺序应用 `hardened` |
| 关闭 `enable_affixes` | 不抽取、不应用且基础战斗结果与当前基线一致 |

### 9.4 Dota 实机验收

- 最大生命 modifier 在重试、死亡、复活和换人后没有重复增长。
- 护盾、治疗增强、魔法返还、攻击距离和施法距离与 UI 数值一致。
- 法术护壳只消费一次，物理攻击、友军伤害和生命消耗不会误触发。
- 净化脉冲预警完整，基础驱散范围和周期与描述一致。
- 后排猎手只改变目标优先级，不使技能越过硬条件或非法施法。
- 再起受到减疗和驱散影响，致死伤害不会触发假复活。
- 关卡失败 3 次并多次换阵后，敌方头像词缀与首次进入完全一致。

### 9.5 平衡矩阵

现有每组 500 个固定战斗种子的模拟矩阵增加以下轴：

| 系统 | 档案 |
| --- | --- |
| 羁绊 | 关闭、自然构筑、单个 5 人羁绊、最大合法多羁绊 |
| 词缀 | 关闭、期望随机、最高合法进攻、最高合法防御、互斥边界 |
| 规则 | 默认、情报针对、优化 |
| 资源 | 70% 装备预算、100% 装备预算、终局 4/5/6 神装 |

平衡通过线：

- 自然构筑羁绊相对无羁绊的中位胜率提升目标为 4~8 个百分点。
- 单个 5 人羁绊相对无羁绊的中位胜率提升不得超过 12 个百分点。
- 期望随机词缀使针对规则胜率下降目标为 3~7 个百分点。
- 最强合法词缀组合不得使针对规则胜率低于 `DESIGN.md` §2.4 对应下限 10 个百分点以上。
- 同一关最高进攻与最高防御词缀组合的获胜时长中位数差不得超过 20 秒。
- 最大羁绊、高品质和 6 神装组合对第 30 关的优化规则胜率仍不得超过 95%。

## 10. 遥测与调参

每次战斗记录但不上传敏感信息的聚合字段：

```text
battle_id, level_id, attempt_index, seed_hash, data_version,
active_bond_ids_and_tiers, affix_ids_by_spawn_key,
result, duration, survivors, damage_by_unit,
affix_trigger_counts, affix_dispel_counts, bond_effect_totals
```

核心观察指标：

- 每个羁绊的招募率、2/3/5 档达成率和带入 Boss 关比例。
- 达成 5 人羁绊后是否显著压缩英雄选择多样性。
- 每个词缀的出现率、触发率、被驱散率、对应关卡胜率和额外战斗时长。
- 玩家看到词缀后是否实际修改规则或站位。
- 同一关失败后，第二次挑战胜率是否提高；如果不提高，优先检查反制是否不可表达或情报不清楚。

调参优先级固定为：修正不可表达的反制 → 修正 UI 情报 → 调整单个词缀/羁绊数值 → 调整威胁预算。不得用整体提高敌人基础属性来抵消羁绊收益。

## 11. 实施顺序与完成定义

| 阶段 | 交付物 | 完成信号 |
| --- | --- | --- |
| P1 数据基线 | 32 英雄标签、8 羁绊、职责标签、15 词缀、JSON→KV 生成与校验 | 静态验证全部通过，关闭开关时 30 关基线无变化 |
| P2 羁绊运行时 | 预览、快照、modifier、叠加上限、招募与编队 UI | 单元测试和羁绊实机清单通过 |
| P3 词缀运行时 | 稳定键、抽取、持久化、互斥、modifier、敌情 UI | 10,000 seed/关无非法组合，失败重试不重抽 |
| P4 统一事件路由 | 伤害、治疗、控制、驱散、日志的单一语义 | Dota 与模拟器对同一测试夹具结果一致 |
| P5 联合平衡 | 完整模拟矩阵和节点关实机验证 | 胜率、时长和第 30 关上限全部满足 |

首发发布的完成定义是：两个功能开关可独立启停；所有数据、本地化、UI、运行时和模拟器共享同一版本号；重试确定性已验证；没有已知无反制组合；关闭两个开关后当前基础玩法结果不变。

## 12. 需要保留的后续扩展点

- 新英雄通过现有 8 个标签接入，只有当标签成员过密或玩法空缺时才新增羁绊。
- 新词缀优先复用现有事件路由和反制标签，不为单个词缀增加无法测试的旁路。
- 可在后续版本增加关卡专属词缀白名单，但仍受当前固定预算和确定性规则约束。
- 若未来加入跨局存档，必须先定义 `data_version` 迁移；本版本不得提前把当前 Run 结果写入 LocalStorage。
