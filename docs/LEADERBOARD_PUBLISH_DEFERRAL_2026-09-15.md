# 终局闪退：把排行榜回执移出 HTTP 回调（2026-09-15）

用户观察：**每局结束时必定先显示排行榜，然后卡住、闪退**。远程数据库里能看到成绩已上传，因此怀疑是网络问题。

两份取证文档（[SCORE_CRASH_2026-09-13](./SCORE_CRASH_2026-09-13.md)、[END_CRASH_2026-09-14](./END_CRASH_2026-09-14.md)）已经排除"掉线"这个解释：崩溃是 native 空指针读，两次（恐怖利刃 / 卓尔游侠）**24 层调用栈偏移完全一致**，`server.dll+0x503226`，`mov rbx,[rcx+0x270]`，RCX=0。日志里是 loopback 本地局，崩溃边界之前没有任何 disconnect / snapshot / HTTP 报错。

## 为什么"上传成功"和"闪退"可以同时成立

成绩落库说明 POST 已送达、Dota 后端已算分并返回 200 —— **请求与响应都完整发生了**。问题不在网络，而在响应回来之后跑的那段代码：

```lua
-- 修改前 battle/run_results.lua
local function finish(response)
    if code == 200 or code == 201 then
        if ok and acceptResponse(run, data) then
            run.result.status = "success"
            Results.Publish(game, run)   -- 在 SteamWorks HTTP 回调栈里调用
```

`Results.Publish` 最终执行 `CustomGameEventManager:Send_ServerToPlayer`。也就是**在网络服务回调内部重入引擎的事件发送/序列化**。这条路径只在终局发生（只有终局才发成绩），且与英雄无关，和"换英雄仍同签名"吻合。

面板"卡住"也是同一件事的另一面：结算事件到达时面板先按 `status = "pending"` 显示（`run_results.lua:183` → `rpg_demo_hud.js:2357`），刷新最终名次**完全依赖**这条回执事件。回执的那一帧打崩，面板就永远停在"等待提交"文字上。

## 改动

HTTP 回调现在只做纯 Lua 的解析与校验，并把"该发布了"记成标志；真正的引擎事件发送交给下一帧主循环。

- `battle/run_results.lua`：新增 `Results.FlushPublish(game)`；回调里的三处 `Results.Publish(game, run)`（200/201 成功、4xx、重试耗尽）改为 `run.publishPending = true`。
- `addon_game_mode.lua`：`OnThink` 新增生命周期步骤 `leaderboard_publish` → `RunResults.FlushPublish(self)`。
- 结算/重开语义不变：面板仍在结算到达时立刻显示 pending，最终名次最多晚 100ms（`OnThink` 周期）到达；`Results.Reset` 会换成新表，旧 run 的待发标志自动作废，重开后旧回执不会弹回新局。

## 这是待验证的假设，不是已确认的修复

- 崩溃转储没有符号，24 帧全是 `server.dll`/`engine2.dll` 偏移，**无法从栈上证实**就是这一行。
- 次要嫌疑：终局 `phase = "result"` 期间 0.1 秒的 `OnThink` 仍在跑 `tempest/summon/gris_gris/tiny_tree/enemy_diagnostics` 这些触达原生单位句柄的 think（`addon_game_mode.lua:3848-3852`）。它们与英雄相关，和"换英雄同签名"相矛盾，因此本轮未改动，保留为后备方向。
- 本轮没有启动/关闭 Dota、没有执行游戏指令、没有采集新转储。离线测试不能证明原生时序。

## 验证

- `python scripts/test-all.py`：**88/88** 测试组通过。
- `tests/leaderboard-results.test.lua` 新增：HTTP 回执本身**不得**发出引擎事件（此刻仍为 `pending`）、显式 flush 后才变 `success`、无待发内容时 flush 不重发。
- 6 个显式列举 `battle.run_results` 模块 API 的测试替身补上 `FlushPublish`（`battle-reincarnation-lifecycle`、`campaign-loot`、`precache-battlefield`、`respawn-policy`、`shop-state`、`shop-transition`）。

本机用 Python `lupa.lua51` 适配器提供 Lua 5.1 运行时（临时工具，不属于 addon 依赖）。

## 待用户实测

重新安装本机插件后，正常游玩到全通或红心耗尽：

- **若崩溃消失**：说明触发点确在网络回执的引擎重入，可把该假设转为结论并清理后备方向。
- **若仍然闪退**：说明触发点在别处（优先查 `result` 阶段仍在运行的 `*_think`），此时应采集新转储并与 `END_CRASH_2026-09-14.md` 的调用栈比对。
- 两种情况都要确认面板能走到 `success` / `error` 状态，而不是一直停在等待文字。

跟踪 issue：`dota2_rpg-t7q`（本机 master 库）。同一崩溃在分支取证记录中的编号为 `dota2_rpg-p5wp`。
