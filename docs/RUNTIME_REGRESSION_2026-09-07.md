# 2026-09-07 实机反馈回归修正与部署记录

关联 Beads：`dota2_rpg-ylf`。用户反馈 CSS 非法属性、树木悬空、开战后空气墙、英雄无法购买装备及技能无法点击。此前模拟测试不能覆盖这些真实引擎接口和资源编译问题。

**后续更正：** 用户在本次部署后再次反馈购买和菜单等问题，后续记录见 `docs/RUNTIME_FOLLOWUP_2026-09-07.md`（`dota2_rpg-h2y`）。下文 `GetAbilityNameByID` 方案未在实际引擎中成立，已改为读取游戏自带的物品 ID 注册表；本记录仅保留前次部署经过，不能作为购买问题已解决的依据。

## 本轮修正

- `issue_fixes_ui.css` 的 `hittest` 不是合法 CSS 属性。live/overlay 删除该声明，通过 JS 面板属性设置按钮点击检测，并添加回归断言。
- 全屏 `DropdownLayer` 设置 `hittest="false"`、`hittestchildren="true"`，让空白区域不拦截原版 HUD 点击，保留下拉菜单交互。
- 装备目标头像通过服务端英雄实体索引选择真实原版英雄，不再只更新自定义面板状态。无 units 的技能升级订单从技能实体的 caster 验证归属，不从 UI 选择猜测。
- 原版购买订单的 `entindex_ability` 是物品定义 ID，不是物品实体；先用 `GetAbilityNameByID` 解析物品名，再做价格与购买归属校验。
- VMAP 删除中线静态 `func_brush`，防止其作为高度/导航障碍被烘焙。临时树使用平坦战场 marker 高度，避免地面查询命中旧阻挡顶部。准备阶段只用原生临时树隔开，开战逐棵砍除；旧中线实体只禁用，绝不重新启用。
- 安装脚本显式编译修复 UI 的 XML/CSS/JS，并拒绝非法属性、关联编译失败和非零失败计数。

## 验证与部署

- `python dota2_rpg_issue_fixes/tests/run_checks.py` 通过：49 个 Lua 文件语法、live/overlay 运行时、购买与技能权限、Panorama、安装器和 VMAP 测试。
- VMAP 11 项测试通过，其中依赖外部原版地图的模型来源检查跳过 1 项。新增中线删除迁移的幂等性及其余地图数据不变检查。
- `tests/compile-vmap.ps1` 隔离静态编译通过，未启动客户端。
- `scripts/install-addon.ps1 -Compile` 正式部署通过，地图 `19 compiled, 0 failed`；全部 8 个 Panorama 源资源也单独编译通过。
- 正式 VPK：3,123,798 字节，SHA-256 `af8877ab071cbe516a973321ecb6402c9d6d0e560a2b5451cd1a0bae5686b7a1`。包内未检出 `rpg_mid_gate_nav`，保留外围墙实体。
- 65 个部署源码文件与仓库逐字节一致。正式部署前 Dota 进程已退出；本轮没有由 agent 关闭、启动或操作客户端。

完整部署前备份和编译日志：

```text
C:\Users\harjeb\AppData\Local\Temp\dota2_rpg_regression_20260907_213901
C:\Users\harjeb\AppData\Local\Temp\dota2_rpg_regression_20260907_213901\compile.log
```

编译输出仍包含基础游戏 `soundevents_test.vsndevts_c`、`surfaceproperties_steamaudio.txt`、`nav_hulls.vdata_c` 缺失警告。它们没有令资源编译失败，但这不证明游戏内渲染和运行完全正常。

## 验收边界

本轮完成的是源码修正、自动化回归、真实资源编译和部署一致性核查，**尚未完成进游戏验收**。必须重新加载地图后检查：CSS 报错消失、树木落地、开战跨越中线、场上与待命英雄原版购买和技能升级。技能测试覆盖的是准备阶段升级；不改变原有战斗阶段禁止手动升级及准备期沉默等规则。
