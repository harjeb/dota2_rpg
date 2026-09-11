# 技能条件可靠性更新

本次将 `C:/Temp/dota2_rpg_reliability.patch` 的可靠性改动整合到当前工程，并修复评审中发现的回归。`dota2_rpg_reliability_fixed.zip` 与该补丁是同一份原始交付，未重复覆盖。

按当前产品取舍，**技能命中人数条件不再提供**。编辑器、预设、前后端校验、快照和执行层一起移除该条件；旧规则里的 `min_aoe_hits` 被忽略，重新保存后不再携带此字段。独立的“附近敌人数”“附近友军数”和目标筛选继续生效。

## 回归修复

| 问题 | 修复后的行为 |
|---|---|
| 腐烂、脉冲新星等 Toggle 被人数兼容性校验拦住 | 移除人数门槛及相应几何校验，旧字段不再阻止正常开关和施法。 |
| 首次编辑后刷新能力，应用静默丢失 | 同一英雄的相同有序规则快照保留规则对象，忽略 JSON 对象字段顺序，保留规则、条件和优先级数组顺序；刷新后能提交尚未保存的草稿。设置编辑和切换动作两条路径都覆盖。 |
| 刷新期间英雄、动作或规则发生变化 | 保存前核对英雄实体、规则键、规则位置、内容和实际动作；冲突时保留编辑窗口并提示重新打开。 |
| 龙破斩宽度估算错误、死亡一指被复杂几何分类限制 | 删除命中人数估算模块及生成资料中的几何分类；普通目标选择继续使用原生施法约束和目标排序。 |
| Windows 技能矩阵测试找不到 Lua 模块 | 测试模块路径统一分隔符，并通过 `lua_literal()` 转义后嵌入 Lua 源码。 |

命中人数是本次明确删除的功能，不自动换成另一项人数条件。范围技能预设保留已有的附近敌人观察条件。目标在观察半径内不代表技能一定命中。

单位技能按合法性、射程和排序选择目标；地点技能以合格目标位置作为落点；基础矢量技能保留原有锚点和方向逻辑。无目标技能的筛选用于判断是否存在匹配单位，没有筛选时不因旧人数配置额外限制施放。魔法、冷却、学习状态、原生目标限制等检查继续执行。

## 保留的可靠性改动

`ability_capability.lua` 根据当前原生技能对象描述目标阵营、目标类型、施法模式、状态控制和生命周期能力，`ability_catalog.lua` 发布给 Panorama。`ability_profiles.lua` 从入库快照生成主动技能的表达覆盖及来源资料，不再生成命中几何。

UI 使用 `ability_capabilities.js` 约束可选项并检查草稿，服务端 `rule_compatibility.lua` 在保存和执行时重新检查。客户端资料包含英雄归属和版本，不能代替服务端授权。技能槽位尽量转换为稳定技能名称；物品保留槽位语义。

兼容性校验包含目标阵营/类型、原生单位或地点模式、自身与排除自身冲突、区间条件矛盾、状态控制类型、动作引用归属，以及没有执行器的 Alt 模式。点地技能的观察目标与原生单位施法目标分别处理。未知原生数据保留运行时判断，不按确定不支持处理。

`state_controller.lua` 分开管理 Toggle 和 Autocast。Autocast 使用原生自动施法开关订单，显式 `false` 状态会完整经过序列化、快照和执行。魔法滞回策略例如 40% 开、20% 关，配合最短保持时间和原生状态确认，减少反复切换。额外使用条件仍作用于开启和关闭两种情况，应在状态策略中设置滞回阈值。

`action_lifecycle.lua` 观察请求下令、前摇、原生执行、持续施法和结束。新增 `channel_elapsed_gte`、`channel_elapsed_lte`、`action_phase_is`、`release_action_available` 条件。持续施法期间只允许当前父技能精确对应的释放路径；普通攻击、移动或其他技能仍受保护限制。非原生 channel 的特殊蓄力机制需要专用适配。

`modifier_catalog.lua` 收集实际观察到或技能声明的 modifier 名称，未知名称使用高级确认。`condition_observation.lua` 和 `rule_diagnostics.lua` 把可观察条件值、失败原因和最后一次评价返回规则行，记录有上限并限频。下令提交不等于原生施放成功，更不等于命中或伤害生效。

## 验证

离线检查 **63/63 通过**：44 个 Lua 测试文件、7 个 JavaScript 测试文件、9 个 Python 测试文件，以及生成资料一致性、全部 Lua 和 Panorama JavaScript 语法检查。`verify-addon.ps1` 离线检查通过；引擎转换因缺少 `dmxconvert.exe` 未执行，外部地图模型来源复核按工具说明跳过。

完整机器结果：`tests/results/reliability-regression.json`。逐技能矩阵结果：`tests/results/ability-condition-matrix.json`。

新增回归覆盖首次编辑刷新后保存、动作切换草稿、过期英雄/动作/规则保护、旧命中人数字段清理，以及保留附近人数条件。后端覆盖单位、地点、矢量、Toggle 和特殊目的地的旧字段兼容。

矩阵将实际 JavaScript 序列化结果交给 Lua RuleService，并比较前端兼容性判断。覆盖 439 个技能、505 个预设变体、11,546 个配置组合，前后端判断差异为 0；包括目标类型、矛盾条件、施法模式、状态开关和旧人数字段。使用原生半径为 0 和合成半径 400 两种环境，验证兼容性不再受人数几何影响；400 仅为模拟输入。所有默认预设必须结构兼容；非法组合被拒绝也属于测试成功。

本机使用 Python 3.14、Node 24 和 Lupa 2.8 内嵌的 Lua 5.1，通过临时 CLI 适配器指定 `LUA_BIN` 执行。适配器位于 `C:/Temp/dota2_rpg_review_tools/`，不属于 addon 运行时依赖。其他机器可直接使用 Lua CLI。

```powershell
$env:LUA_BIN = "C:\Tools\Lua\lua.exe"
python scripts/test-all.py
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-addon.ps1
```

生成资料可分别复核：

```text
python scripts/build-condition-coverage.py --check
python scripts/build-condition-help.py --check
python scripts/build-ability-capabilities.py --check
```

**离线验证不等于 Dota 实机验收。** 本次没有运行 Dota 或 Workshop 资源编译器，`native_execution_validated` 保持 0；439 是表达覆盖数量。原生 callback 时序、UnitFilter、升级/形态切换、视觉效果和逐技能实际施法仍需游戏内检查，由 beads `dota2_rpg-4rk` 跟踪。

## 安装

本次同时修改 Lua、Panorama、布局、CSS 和中英文本。原始补丁仅用于此次整合；后续应从当前仓库版本安装，不能再叠加原始补丁或用旧 ZIP 覆盖修正版。

在具有 Workshop 工具的环境中使用已有安装脚本：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-addon.ps1 `
  -DotaPath "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta" -Compile
```

安装前保留目标目录备份；回滚时一起恢复 `content/dota_addons/dota2_rpg/` 与 `game/dota_addons/dota2_rpg/`，重编译并重启自定义游戏。当前 Run 保存在服务端内存，重启不能保留本局。

本次未安装到 Dota 目录。原交付的 `RELIABILITY_MANIFEST.json` 散列已不适用于修正版，因此不纳入仓库；修正版以 Git 提交和重新生成的测试结果为准。
