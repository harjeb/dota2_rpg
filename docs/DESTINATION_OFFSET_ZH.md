# 落点偏移：远离目标 / 敌人前方 / 敌人后方 / 敌人周围

面向"地板释放"（点目标）技能与物品的落点方式。跳刀、闪烁这类技能过去只能落在
规则选中的敌人身上；本次新增四种**相对锚点**的落点，让落点可以带距离地偏到敌人
周围，或者背向敌人逃生。

## 1. 四种落点

记：

- `C` = 施法者位置，`T` = 规则选中的敌人锚点位置
- `u = normalize(T - C)`（施法者指向敌人的单位向量）
- `f` = 敌人当前朝向 `GetForwardVector()` 的水平单位向量
- `d` = 规则里填写的**落点距离**

| 内部值 | 中文 | 落点公式 | 距离起算点 |
| --- | --- | --- | --- |
| `away_from_target` | 远离目标 | `P = C - u × d` | 施法者 |
| `target_front` | 敌人前方 | `P = T + f × d` | 敌人 |
| `target_behind` | 敌人后方 | `P = T - f × d` | 敌人 |
| `around_target` | 敌人周围 | `P = T - u × d` | 敌人 |
| `target`（原有默认） | 目标位置 | 锚点自身位置 | — |

- **远离目标**：背向敌人、从自己起算，`d` 就是你能退多远。
- **敌人前方 / 后方**：只看**敌人朝向**，与你在哪一侧无关。
- **敌人周围**：不看朝向，取"你→敌人"连线在**敌人近侧**、距敌 `d` 处，即落在
  你与敌人之间。

## 2. 距离与边界行为

- **背向距离封顶**：`away_from_target` 的 `d` 会被技能/物品的施法距离封顶
  （例：跳刀 1200）。超出没有意义，`d` 缺省时直接用施法距离。
- **敌人参照的距离不收缩**：`target_front / target_behind / around_target` 的 `d`
  原样使用。**若 `d` 大于你与敌人的距离，落点会越过你、落到你身后**，这是刻意
  选择的行为，不做收缩也不改判；能否真正释放仍由原生位置与射程校验决定。
- **可达性与原生校验**：候选落点必须同时满足
  - `GridNav:CanFindPath(施法者, 落点)`（可站立/可寻路），以及
  - 原生的 `CastFilterResultLocation(落点) == UF_SUCCESS`（射程、地形、目标限制）。
- **贴近边缘时扫描方向**：仅 `away_from_target` 在直线背向点被挡住时，会以 15° 步长
  在 ±90° 内左右扫描，取第一个可站立且原生合法的方向再释放（与"保持最大攻击距离"
  同思路）。
- **失败关闭**：扫描也找不到合法落点时，本次规则**不释放**，不会退化成"落在锚点上"
  或"原地释放"。非点目标动作（单位/无目标/开关）一律拒绝偏移落点。

## 3. UI 行为

- 只要动作是**地板释放**（capability `mode == "point"`）或者是残焰类动作，就会在
  「条件设置」里出现「目的地」下拉。
- 模式列表按能力生成：点目标给 `target` + 四种偏移；残焰类额外保留 `self` 与
  `remnant_*` 专属落点。
- 选中任一偏移模式时，才出现「落点距离」输入框；切回「目标位置」时该字段会被清除，
  不会带给服务端。

## 4. 数据契约

- 落点方式：`rule.action.destination`，取值见上表。
- 落点距离：`rule.action.destination_distance`，`0..3000`。

`destination_distance` 加入了共享的编写字段集合（`tactics/action_options.lua`），
因此旧规则转换、快照、存档、NetTable 同步与前端编解码都会原样保留它；只有偏移
落点才会把它写进平面协议。

## 5. 涉及文件

| 文件 | 改动 |
| --- | --- |
| `tactics/special_targets.lua` | 新增 `offset_destinations`、`OffsetDestination` 几何与 `ValidDestination` 放行 |
| `tactics/tactic_engine.lua` | 新增 `ResolveOffsetDestination`，在 `ResolveRuleTarget` 里先选锚点再算落点 |
| `tactics/action_options.lua` | `destination_distance` 字段与数值校验 |
| `panorama/.../condition_catalog.js` | 地板释放显示落点下拉、偏移模式显示距离输入 |
| `panorama/.../panorama_rule_sync.js` | `destination_distance` 收发编解码 |
| `resource/addon_schinese.txt` / `addon_english.txt` | 四种落点与「落点距离」文案 |

## 6. 测试

- `tests/destination-offset.test.lua`：四种落点的几何、距离封顶、越过施法者、
  边缘扫描、原生校验失败、引擎选取锚点、服务端解码与校验。
- `tests/condition-ui-v2.test.js`：地板释放出现落点下拉、偏移模式出现距离输入、
  保存与重开后保持。

## 7. 已知限制

- 只有点目标动作支持偏移落点；单位目标/无目标动作会在运行时被拒绝。
- `target_front / target_behind / around_target` 不做方向扫描：唯一候选点被挡住时
  本次不释放，需要玩家调整距离或站位。
- 偏移落点的可达性判断依赖 `GridNav`；离线模拟器没有该模块时会跳过寻路检查，
  实际能否落地仍以原生施法校验为准。
