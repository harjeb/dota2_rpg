# 验证报告

验证日期：2026-09-06

## 紧凑战场增量验证

- 默认回退边界已从 3200×1600 收紧为 **2400×900**；显式传入旧 `square_size = 1600` 的调用仍保持 3200×1600 兼容行为。
- 通过 Lupa 执行 `tests/test_runtime.lua`：验证紧凑边界钳制、旧尺寸兼容，以及 bootstrap 只把 `battleManager.teamHeroes` 的场上/敌方单位注册到战场，不会拖入待命英雄或小精灵。
- 通过 Lupa 执行根目录 `tests/precache-battlefield.test.lua`：验证五个双方出生点和准备期持久化排位均落在紧凑边界内。
- `node --check`、Panorama UI 模拟、Python 语法检查及安装器幂等测试均通过；没有 `texlua` 时已由 Lupa 执行 Lua 检查。
- 根目录的 `tests/shop-state.test.lua`、`tests/panorama-save.test.js` 与 `pwsh tests/verify-addon.ps1` 均通过；后者现会静态验证实际 VMAP 的三枚 marker、四面永久墙、两枚中线 `func_brush` 和四块 `nonavclip` slab。
- 实际 VMAP 已通过 `dmxconvert` KeyValues2 → binary → KeyValues2 往返，以及 `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/compile-vmap.ps1` 的临时副本 `resourcecompiler` world/physics/gridnav 构建（`19 compiled, 0 failed`）；脚本会清理测试 VPK，构建日志确认生成四面墙与 visual/nav 中线门。
- 按用户要求，本次没有启动 Dota 2 或 Workshop Tools 客户端进行实机回归。

## 已执行检查

```text
Python 语法检查：通过
Lua loadfile 语法检查：11 个文件通过
Lua 模拟运行测试：通过
Panorama JavaScript node --check：通过
Panorama UI 行为模拟测试：通过
Panorama XML 解析：通过
自动安装器测试：通过
自动安装器重复执行幂等测试：通过
```

执行命令：

```bash
python tests/run_checks.py
```

## 模拟测试覆盖

- 小精灵把同一个 item handle 转给英雄；来源不再保留该物品，目标获得同一句柄。
- 英雄物品栏和背包已满时拒绝转交，装备仍留在小精灵。
- 没有玩家规则时只建立一条默认普攻规则；有效玩家规则不被补满或删除。
- 第 1/2 关阵容重复时只替换第 2 关敌人，并保留奖励等其他字段。
- 当前关生成 4 个敌人时，4 个单位全部绑定 profile 并收到开战订单，不固定为 3 个。
- PREPARE 阶段技能升级和购买订单放行。
- PREPARE 阶段敌方/引擎空闲 AI 订单被阻止。
- FIGHT 阶段玩家控制订单被阻止，issuer=-1 的 AI 订单放行。
- FIGHT 阶段即使购买订单没有 unit 列表，也会被阻止。
- 默认紧凑矩形边界为 2400×900；准备阶段场上英雄移动被限制在左侧 1200×900 区域，且不会拉动小精灵或待命英雄。旧的显式 `square_size = 1600` 调用保持兼容。
- 中线门模拟覆盖 `Enable`/`Disable` 与 `func_brush` 的 `Alpha`、`SetSolid`/`SetNonsolid` 成对调用；这样 visual 和物理/导航门不会只切换其中一面。
- UI 展开/收起箭头、固定按钮尺寸、透明商店类和单条默认规则归一化通过模拟。
- 安装器会备份覆盖文件、加载 UI manifest、在顶层 return 之前安装 bootstrap、修正准备类 modifier，并可安全重复执行。

## 尚未执行的验证

本次没有启动 Dota 2/Workshop Tools 进入游戏实测；因此尚未执行：

- 真正的 `CDOTA_Item` 转交、堆叠、自动合成和购买者归属测试；
- 原版技能升级按钮、先天技能、命石及英雄重建后的技能点测试；
- 原版商店在本地 Tools 和已上传专用服务器上的购买测试；
- 当前项目 TacticBridge 的实际 profile 注册函数和指令优先级测试；
- 当前 HUD 的真实 Panel ID、分辨率和 UI 缩放测试；
- `.vmap` 在真实比赛中的外墙碰撞、中线门开关后的路径更新、导航连通性及位移交互测试；静态结构/编译检查已完成。
- 30 关完整回归。

因此本包的状态是：**源码修复层和安装流程已通过静态/模拟验证；合并前必须按 `integration/TEST_CHECKLIST.md` 做引擎内回归。**
