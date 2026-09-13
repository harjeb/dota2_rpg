# 2026-09-13：远程英雄普攻默认使用最大攻击距离站位

## 改动

远程英雄的**普攻行**默认站位方式由「默认」改为「最大攻击距离（保留安全容差）」。

- 服务端生成默认规则时套用策略：`issue_fixes/default_rules.lua` 新增
  `DefaultRules.ApplyRangedAttackPosture(rule, unit)`，在 `CreateForHero` 里作用于普攻行。
- 敌方英雄的普攻行可能来自关卡 AI 预设（`enemy_ai.kv` 里的 `action.type = "attack"`），
  会顶掉生成的那条，所以 `issue_fixes/enemy_rules.lua` 在选定的普攻行上再落一次策略。

## 范围与边界

| 对象 | 是否生效 |
| --- | --- |
| 远程英雄的普攻行（未手动配置过） | ✅ 默认 `attack_range` |
| 全部敌方远程英雄的普攻行 | ✅ 含关卡 AI 自带普攻行的情况 |
| 近战英雄 | ❌ 保持原状 |
| 技能行 | ❌ 保持原状（技能仍可选默认 / 固定距离 / 原生施法距离） |
| 野怪、小兵、召唤物 | ❌ 只认 `IsRealHero`，非英雄单位不受影响 |
| 玩家已显式配置过 `positioning_mode` 的行 | ❌ 原样保留，不会被覆盖 |

「远程」判定：`IsRangedAttacker` 优先，拿不到时退回 `Script_GetAttackRange > 300`
（近战约 150，远程 400 以上）。两个接口都拿不到时按近战处理，即不改变行为。

## 实现要点

- 策略是**就地改写**规则里的 `rule.action.positioning_mode`，不是复制。
  `enemy_rules` 的既有契约是返回同一个普攻规则对象（测试断言身份相等），
  复制会破坏它；而 `profileRules` 每次都由 `ConvertLegacyRule` 新建，就地改写不会外泄。
- `is_ranged_hero` 里必须先把 `call(unit, "Script_GetAttackRange")` 落到局部变量再
  `tonumber`。方法不返回值时，`tonumber(call(...))` 会退化成**零参数调用**并抛
  `bad argument #1 to 'tonumber' (value expected)`。这个坑被 `marci-targets`
  与 `inventory-transfer` 两个用例当场抓到。

## 客户端表现

服务端规则经 `rule_snapshot.lua` 的 `movement_contract.Copy` 把 `positioning_mode`
带到 wire 规则上，客户端 `RpgRuleSync.fromServer` → `actionSettings` 回填，
设置面板的「站位方式」因此直接显示为「最大攻击距离（保留安全容差）」。

## 验证

- 97/97 组离线回归通过（Lua 5.1 原生接口替身与 Panorama 面板替身）。
  新增用例覆盖：远程英雄普攻行拿到 `attack_range`、近战英雄不变、
  技能行不变、非英雄远程单位不变、已配置的行不被覆盖、
  缺原生标记时按攻击距离兜底、近战距离不改、无单位时不改，
  以及生成规则仍通过 `RuleService:ValidateRule`。
  `enemy-rules` 侧覆盖远程敌方英雄、近战敌方英雄与远程野怪三种情况。
- 已安装到本机插件目录，四个源文件（两份 Lua + 两份本地化）与安装副本逐字节一致。
- 可见版本号同步递增至 **界面版本 62 / UI version 62**。
- 未启动或操控 Dota，离线用例使用原生 API 替身，**不是真实对局验收**。
  实机仍需复核：远程英雄是否真的在攻击间隔内拉开距离、被墙/树阻挡时是否换边、
  以及近战英雄与野怪的手感没有变化。
