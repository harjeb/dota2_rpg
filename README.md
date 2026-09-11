# Dota 2 RPG Combat Demo

这是一个 Lua + Panorama 的 Dota 2 Workshop Tools 单人 PVE 自定义游戏 addon：玩家在准备阶段招募英雄、配置规则和装备，战斗阶段由服务端自动执行。

## 技能条件可靠性更新

本版新增 UI 按技能自动限制、服务端兼容性复验、条件冲突检测、独立 Autocast / Toggle 状态控制、持续施法对应释放保护，以及每条规则的失败诊断。技能命中人数条件已从配置、预设和执行链路移除，旧字段不再影响施法；附近敌人数等观察条件保留。修复首次编辑刷新能力后无法保存的回归，草稿冲突时保留窗口并提示。完整实现、安装和验证边界见 [RELIABILITY_UPDATE_ZH.md](RELIABILITY_UPDATE_ZH.md)。

离线检查 **72 / 72 通过**；矩阵覆盖 **439 个技能、505 个预设变体、11,546 个配置组合**，UI 与服务端判断不一致为 0。这不是原生施法成功率；本次未执行 Dota/Workshop 原生验收，仍保留 `native_execution_validated = 0`。

运行全部检查：`python scripts/test-all.py`。需要 Python、Node 和 Lua 命令行运行时，非标准 Lua 路径通过 `LUA_BIN` 指定；后端检查不再因缺少 Lupa 而跳过。

## 当前玩法边界

- 每局 Run 只保存在服务端内存；不使用 Panorama `LocalStorage`、跨局存档、存档码、每日重置或迁移。第 30 关胜利后当前 Run 进入终局，不会重复发放终局奖励。
- 初始金币为 **500**；开局拥有 **2 次免费招募选择**。系统不随机赠送英雄，前两次成功选择免费，之后按招募等级固定价格扣款。
- 英雄价格由招募等级决定：1/5/10/15/20/24 级分别为 500/900/1600/2600/4000/5500；品质只决定出现概率和内置魔晶/神杖效果，不乘价格倍率。
- 关卡经验按英雄发放：上阵英雄获得表中全部经验，待命英雄获得向下取整的 50%；升级使用累计经验阈值的相邻差值。时间金币奖励上限为基础金币的 10%。
- 英雄商店报价由服务端生成，每次 5 个不重复报价。普通 Dota 装备完全交给 Valve 原版商店处理；准备阶段选中小精灵、上阵英雄或待命英雄均可购买和管理装备。额外英雄的购买若被原版引擎送到 assigned hero 小精灵，服务端会按本次新增实体自动补转到所选英雄；9~14 号原生储藏栏也会被扫描并保留。
- 普通装备的购买、出售、合成、堆叠、充能和原版价格不由项目复制；项目只在 `setup` 阶段接收装备转移、丢弃、拾取、卷轴购买/使用等操作。
- 战术规则结构为：动作 → 目标硬条件 → 目标优先级 → 使用条件（AND）→ 接近策略。不存在“目标存在”条件；同一技能/主动装备可以出现在多条规则中。Panorama 通过 `rpg_update_rule` 逐条同步，服务端按英雄名稳定键保存当前 Run 规则。
- **界面版本 39**：阿哈利姆魔晶开局即可购买，取消原生首次上架等待；原价、原生效果与后续补货规则继续沿用。见 [RUNTIME_FIXES_V39.md](docs/RUNTIME_FIXES_V39.md)。
- UI38：敌方骷髅王不再主动自杀触发重生；敌方主动装备按血量、距离、充能及冷却等条件行动。第 20 / 30 关 Boss 最大生命分别提高到 20,000 / 32,000，并增加攻击、护甲与魔抗；第 11、16、21、26 关全部换成强化远古。数值、装备策略与验证边界见 [RUNTIME_FIXES_V38.md](docs/RUNTIME_FIXES_V38.md)。
- UI37 的状态选择显示中文施法阶段、原生状态名称及来源技能／装备图标；战斗结算立即刷新装备冷却；敌方英雄按实际等级与定位配置装备。93 条敌方英雄配置已更新，低等级小件、过渡核心和后期装备分段生成；详见 [RUNTIME_FIXES_V37.md](docs/RUNTIME_FIXES_V37.md)。
- UI36 修复电炎绝手“蜥蜴绝吻”持续期间被其他自动技能、装备、普攻和追击打断的问题，按原生施法状态结束恢复。证据与验证边界见 [RUNTIME_FIXES_V36.md](docs/RUNTIME_FIXES_V36.md)。
- UI35 修复公共库存装备转交中误用删除 API 导致物品消失的问题；转交和失败退回保留原实体，界面显示转交结果。点击“＋”新增行动时，使用条件、目标筛选和优先级均为空白，不再复制上一行条件。证据与验证边界见 [RUNTIME_FIXES_V35.md](docs/RUNTIME_FIXES_V35.md)。
- 条件设置按钮为 36px 高，并保留紧凑的诊断提示。尸王噬魂选择友方/自身时，已修正 CUSTOM 原生目标掩码被通用检查误拒绝的问题；血量、距离、冷却及原生 flags 等限制继续生效。见 [RUNTIME_FIXES_V34.md](docs/RUNTIME_FIXES_V34.md)。
- 重新创建技能测试（包括同一英雄）或退出测试时，规则列表、未保存草稿、动作菜单及保存提示随服务端一起清除，再显示新一局的默认规则。战斗重置、英雄重生和普通关卡推进保留已配置规则；取消尚未加载完成的首次测试也保留当前配置。
- 新英雄的默认战术包含已学习、可见且可用的主动技能，使用无额外限制的释放条件，根据技能类型选择敌人、友军或自身，最后执行最近敌人的普通攻击。未编辑的默认配置会随技能学习更新；玩家编辑过的规则保留。配置战术不会自动学习技能，需要先在原版技能栏分配技能点。
- 胜利实际掉入共享仓库的物品会以图标和名称弹出，带简单缩放淡入动画；点击“确定”或 3 秒后关闭，没有物品掉落时不弹窗。
- 主战场尺寸为 **2400 × 1350**；准备阶段只能在己方半场排位，开战时中央树墙移除。
- 敌方英雄的等级和原版装备由 `scripts/data/levels.kv` 配置并在生成时实际装备；敌我双方共用修订版战术执行引擎。修改敌方等级后，运行 `python scripts/author-enemy-equipment.py` 更新对应配装，再运行 `python scripts/export-level-configuration.py` 更新 [关卡配置表](exports/level_configuration_current/当前关卡配置.xlsx)。

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

`tests/shop-state.test.lua` 和 `tests/precache-battlefield.test.lua` 需要 Lua 运行时；统一测试入口通过 Lua 命令行执行，不要求 Lupa。上述检查只验证源码契约、数据和 UI 静态结构，不等同于原版 Dota 商店在干净地图中的实机购买/出售/合成验收。

## 部署

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-addon.ps1 -Compile
```

启动地图并保存本局控制台日志：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch-addon.ps1
```

启动脚本使用 `-condebug`，日志写入 Dota 安装目录的 `game/dota/console.log`。当前引擎已废弃 `AppendToLogFile`，也不再支持 `con_logfile` 命令。日志中的 `BUILD` 标记可核对实际加载版本；`GoldWallet`、`ShopTxn`、`RuleUpdate` 和 `Tactic` 分别记录金币、装备购买、规则保存和执行原因。

装备的原实体搬运使用 `TakeItem`；`RemoveItem` 会删除实体，只用于真正需要销毁物品的路径。实机排查记录及验证边界见 [`docs/RUNTIME_DIAGNOSIS_2026-09-08.md`](docs/RUNTIME_DIAGNOSIS_2026-09-08.md)。
