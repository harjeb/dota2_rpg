> 初版 PR 正文历史模板：下文 visual/nav 几何门和编译结果已被后续原生岩石/树木方案替代。当前修复及验证状态见 `../docs/ISSUE_FIX_IMPLEMENTATION.md` 和 `VALIDATION_REPORT.md`，不要直接将此模板作为本轮完成声明。

## 范围

只修复当前 issue.txt 中的 10 项，不增加其他需求，也不修改经济、经验、招募、存档、羁绊或词缀。

## 修复

- 小精灵仓库转交改为移动原物品句柄；失败时回滚，不再先删除源装备。
- 准备阶段放行技能升级和原版商店/物品订单；待命 modifier 不再使用 `STUNNED` 或 `COMMAND_RESTRICTED`。
- 默认行动规则只创建 1 条“攻击最近敌人”，不再按技能/装备槽强制排满。
- 敌人开战时解除准备限制、开启索敌，并用当前关实际生成单位执行主动攻击兜底。
- 敌方战术 profile 按当前关 `entries[i] -> spawnedUnits[i]` 绑定，不使用固定三英雄。
- 第 2 关敌人改为不同于第 1 关的半人马组合，并增加全关卡阵容签名重复校验。
- 行动面板按钮改为 `<` / `>`，收起状态保留固定 56px 宽度。
- 英雄商店移除整块不透明背景、边框和阴影，仅保留单个交互卡片可读背景。
- 增加两个 1200×900 准备区拼接的 2400×900 紧凑矩形战场控制、中线门开关和越界纠正，并将 marker、永久外墙、NONAV slab 与 visual/nav 中线门实际写入 VMAP。
- 开启 universal shop 与 `dota_easybuy`，使等待区和场上英雄在准备阶段可使用原版商店。

## 验证

- Lua 文件通过 `loadfile` 语法检查。
- Panorama JavaScript 通过 `node --check`。
- Panorama XML 可解析。
- 模拟测试覆盖物品转交/回滚、默认规则数量、关卡 1/2 唯一性、当前关敌人数量、订单过滤。

## 需要人工实机验证

- 在 Workshop Tools 中确认 visual/nav 门开关、寻路连通性和位移碰撞；本次只完成 DMX/resourcecompiler 静态构建，未启动 Dota 客户端。
- 原版商店在本地 Tools 与上传后的专用服务器均可购买。
- 组件自动合成、可叠加物品、背包满时转交不丢失。
- 所有当前关敌人主动进攻，TacticEngine 指令不被 fallback 打断。
