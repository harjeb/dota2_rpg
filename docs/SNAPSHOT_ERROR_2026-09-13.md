# 2026-09-13 15:19 快照断线取证

## 已确认

只读已运行游戏的文件，未启动、关闭游戏、执行游戏命令或截图。原始 `game/dota/console.log` 已复制到本机 `%TEMP%/dota2-rpg-snapshot-0913-5m0ze_7x/console.log`（72636 行）。

关键原文（原日志行号）：

```text
72231 09/13 15:19:22 [RPGLifecycle ... level=ch12 phase=result] reset_begin from=ch12 to=ch12
72307 09/13 15:19:22 [RPGLifecycle ... level=ch12 phase=setup] reset_complete from=ch12
72308 09/13 15:19:22 [Entity System] SERVER: dota_base_game_mode([224]) thinking for 230.17 ms!
72309 09/13 15:19:22 [Networking] ERROR! SendData reliable data too big (4401)
72310 09/13 15:19:22 [Server] Disconnect client ... NETWORK_DISCONNECT_SNAPSHOTERROR
```

- 本地 loopback 服务端主动断开客户端，不是排行榜 HTTP 错误，也不是只能根据中文弹窗猜测的普通网络故障。
- 发生在 ch12 战败结算、返回同关准备阶段；本次重置在一个日志 tick 内删除/重建敌我英雄，生成四个敌方英雄和五个玩家英雄，并广播界面状态。
- 本次日志只有一处 `SendData reliable data too big`，没有 `Script Runtime Error` 或 `stack traceback`。
- 15:18:54 另有 `Overflow of the sheet cache texture`。这是不同子系统的纹理缓存警告，不能据此认定它就是网络断线根因。
- 游戏 `game/bin/win64` 和 Steam `dumps` 中最近 Dota dump 为 9 月 12 日；`%LOCALAPPDATA%/CrashDumps` 最近 Dota dump 为 9 月 13 日 00:14。均不对应本次 15:19 断线，不拿旧 dump 冒充本次调用栈。

## 版本与结论边界

本局在 14:30 加载，而 UI65 后端安装文件时间约 15:16，提交时间 15:18:47。不能把已安装文件版本等同于早先启动局的 Lua 实际加载版本，也不能称为 UI65 新局复现。日志中旧 `rpg-runtime-v44-20260912` 标识沿用多版，不能单独用于确认本局具体提交。

已确定直接失败类别为可靠同步数据过大。尚未确认具体原生消息、哪个自定义事件或实体属性导致，也未证明括号中的 `4401` 是字节数或某个容量上限。不能把它直接称为 `SnapshotOverflow`，或认定墓碑、影魔、装备刷新某一个功能是唯一原因。

代码核对重点：`addon_game_mode.lua` 的返回准备阶段回调、`RespawnPlayerRoster` / `BroadcastHeroInfo`，及 `tactics/ability_catalog.lua` 的逐动作能力广播。实体重建与自定义状态发送处于同一轮更新；后续应对实际消息来源、单条载荷及每轮数量补证，避免靠高频全量刷新扩大可靠通道压力。

追踪：`dota2_rpg-pt4x`。本文件是取证记录，不代表快照断线已修复。
