# v18：新增三位可招募英雄与大招限制

日期：2026-09-09。运行标记 `rpg-runtime-v18-20260909`，界面版本 18。

## 招募与技能

用户要求加入变体精灵、天穹守望者、朗戈；移除变体精灵与朗戈的大招，天穹分身只需自行攻击。

| 招募分类 | 新增英雄 | 大招处理 |
| --- | --- | --- |
| 敏捷 | 变体精灵 `npc_dota_hero_morphling` | 移除复制大招及其返回/历史附属动作 |
| 全才 | 天穹守望者 `npc_dota_hero_arc_warden` | 保留风暴双雄，分身开启原生自动索敌攻击 |
| 力量 | 朗戈 `npc_dota_hero_largo` | 移除大招及三个曲目技能 |

运行时招募池由 32 位扩展至 35 位，分类数量为力量 9、敏捷 9、智力 8、全才 9。原有 32 位保留。`heroes.kv` 使用现有加载器支持的显式 `recruitable` 节，避免原先全英雄目录与招募子集使用重复分类键。预缓存与商店均读取该子集。历史 `heroes.json` 仅同步新增三项，其他原有差异保留；本次不调整关卡敌人组合。

## 初始化政策

`issue_fixes/hero_ability_policy.lua` 根据英雄原生名称移除以下真实技能实体：

- 变体精灵：`morphling_replicate`、`morphling_morph_replicate`、`morphling_hybrid`。
- 朗戈：`largo_amphibian_rhapsody`、`largo_song_fight_song`、`largo_song_double_time`、`largo_song_good_vibrations`。

`PrepareBattleHero` 在捕获、恢复和升级技能前调用政策，覆盖上阵、替补及重建。先收集名称再移除，避免原生移除引起槽位紧缩和附属技能联动清理时遗漏或访问失效句柄。重复调用安全；水人的属性转换、波浪形态以及朗戈基础技能保留，手动技能点保留。

这是原生技能移除，不是隐藏规则按钮，也不是为水人复制或朗戈曲目实现新的条件系统。

## 风暴双雄

`battle/tempest_double.lua` 用原生 `IsTempestDouble()` 识别分身。`npc_spawned` 在玩家指挥官处理之前分流，防止把分身隐藏、缴械或移动到场外。

战斗中的分身开启 `SetIdleAcquire(true)` 和 4000 单位索敌范围，与当前战斗英雄的原生索敌范围一致。不给分身复制战术规则，也不主动发送技能指令；攻击目标和攻击过程交给原生 AI。分身保持原生持续时间，不加入英雄招募、库存或独立胜负名单。

已跟踪分身在战斗结算清理；准备阶段意外产生的分身先关闭索敌，等生成回调返回后的下一次逻辑帧清理。正常本体与其他单位不受该分支影响。

## 验证与部署

- `hero-ability-policy.test.lua`：精确移除、保留基础技能、稀疏/紧缩槽位、附属清理、重复调用、其他英雄不受影响。
- `precache-battlefield.test.lua`：真实 `PrepareBattleHero` 上阵/替补路径在技能捕获前移除大招；真实 `OnNpcSpawned` 将风暴双雄分流到原生索敌设置。
- `tempest-double.test.lua`：仅分身开启索敌、战斗保留、失效句柄忽略、结算及准备清理、本体不受影响。
- `recruitable-heroes.test.py`：显式子集、35 位唯一英雄、原生身份、分类及新增 JSON 条目。
- `python dota2_rpg_issue_fixes/tests/run_checks.py` 全部通过：77 个 Lua 语法检查、22 个 Lua 行为场景及既有 JS/UI/数据/安装检查。`tests/verify-addon.ps1` 通过；最终版本标记改动后另行检查 addon Lua 语法通过。`git diff --check` 通过。

部署先完整备份，再安装源文件。81 个源文件与安装目录逐字节一致，14 个既有编译资源保持不变；未编译地图或 Panorama。备份、日志及清单：`C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_v18_tryc7eea`。

地图 VPK 与部署前备份一致，SHA256：`981b81d32370ea9f5dfd22cefe5f3b433889ca4e045f4a30eeb50fb5d8cdac05`。

未启动、关闭 Dota 或截图。新增英雄加载、原生大招移除后技能栏表现以及风暴双雄实际自动攻击仍需用户重载到界面版本 18 后验证；离线测试不代表已取得实战证据。
