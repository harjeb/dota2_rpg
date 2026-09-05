# 验证报告

验证日期：2026-09-05

## 已通过的静态与逻辑检查

- 修订文档：1182 行；Markdown 代码围栏配对正常。
- Demo 文件：36 个。
- Lua：29 个文件通过 `texluac -p` 语法检查。
- Panorama JavaScript：2 个文件通过 `node --check`。
- Panorama XML：2 个文件通过 XML 解析。
- 运行时代码未调用 `LocalStorage`，目录中不存在 `save/` 模块。
- 经验/金币总量复算：stage1-29 active XP=33720; gold=125400; level30 cumulative XP=33700。
- 纯逻辑测试结果：

```text
progression tests passed
affix generation tests passed
target selector tests passed
rule service tests passed
All demo checks passed.
```

测试覆盖了：经验曲线、词缀威胁预算与确定性、目标硬条件/软优先级、同一技能多规则，以及旧 `target_exists` 条件拒绝。

## 尚未在本环境完成的验证

本环境没有运行 Dota 2 Workshop Tools 或 Valve 专用服务器，因此以下项目仍必须在真实项目中验证后才能标记“发布可用”：

- Hammer 地图碰撞、出生点、站位格与屏障。
- 上传后专用服务器上的 Panorama 默认 UI 隐藏和自建商店。
- 每名英雄的命石/变体、先天技能、天赋、魔晶、神杖与特殊施法 adapter。
- `ExecuteOrderFromTable`、订单过滤、引导保持、追击和物品创建的引擎内行为。
- 30 关真实 Dota 战斗的胜率、时长和装备预算。
- 完整 Run 的 75~110 分钟节奏目标。

因此，Demo 是经过静态和纯逻辑验证的工程骨架，不是已经在 Dota 2 中完整编译发布的成品地图。
