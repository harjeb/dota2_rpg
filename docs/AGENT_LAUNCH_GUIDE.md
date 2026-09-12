# 用脚本启动 RPG 地图 —— Agent 操作手册

> 读者：接手本项目的 AI agent（人类同样适用）。
> 目标：**一条命令启动 `dota2_rpg` 地图，并且能证明真的进图了**，而不是"命令没报错就算成功"。

---

## 0. 最短路径（TL;DR）

```powershell
cd F:\dota2_rpg

# 1) 改了 Lua / JS / KV / 本地化 / 数据 之后必须先部署
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-addon.ps1

# 2) 启动（自动清理旧实例，并等到地图真的加载完）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch-addon.ps1 -KillExisting -WaitForMap
```

判据只看这两行输出，不要看"命令有没有报错"：

| 输出 | 含义 |
| --- | --- |
| `MAP READY: build=rpg-runtime-vXX-YYYYMMDD, first stage spawned N enemy unit(s).` 且退出码 `0` | ✅ 真的进图了，第一关敌人已生成 |
| `LAUNCH FAILED (reason: ...)` 或 `MAP NOT CONFIRMED` 且退出码 `1` | ❌ 没进去，脚本会打印日志尾部，按第 5 节排查 |

全程约 **70–110 秒**。实测（2026-09-12 12:47，`-Mode auto` 走 direct 成功）：

```
Mode: direct (dota2.exe)
LAUNCH OK: dota2 PID 12672; console.log is writing.
Waiting for the map to load (up to 300 s)...
09/12 12:48:17 [VScript] [RPGPrecache] startup_complete build=rpg-runtime-v44-20260912 level=ch01 units=3 items=4 elapsed=unavailable
09/12 12:48:25 [VScript] [Dota2Rpg] Level 'ch01' spawned 3 enemy units.
MAP READY: build=rpg-runtime-v44-20260912, first stage spawned 3 enemy unit(s).
EXIT=0
```

耗时：12:47:15 进程启动 → 12:47:21 GPU 初始化 → 12:48:17 `startup_complete` → 12:48:25 敌人出现（共约 70 秒）。

---

## 1. 环境事实（本机已核对）

| 项 | 值 |
| --- | --- |
| Dota 安装目录 | `C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta` |
| Dota 可执行文件 | `<Dota>\game\bin\win64\dota2.exe` |
| Steam 可执行文件 | `C:\Program Files (x86)\Steam\steam.exe` |
| addon 名 | `dota2_rpg` |
| 地图名 | `dota2_rpg_demo` |
| 已部署 VPK | `<Dota>\game\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vpk` |
| **控制台日志** | `<Dota>\game\dota\console.log`（靠 `-condebug` 产生） |
| 日志备份（**不保证存在**） | `<Dota>\game\dota\console.log.bak-<stamp>` |

启动前必须满足：

1. **Steam 已启动并已登录**（两种启动模式都需要它）。
2. 没有别的 `dota2` 实例在跑 —— 否则新实例起不来。用 `-KillExisting` 处理，或手工：
   ```powershell
   Get-Process dota2 -ErrorAction SilentlyContinue | Stop-Process -Force
   ```

---

## 2. 先部署，再启动

**Lua / KV / 本地化 / 数据 改动不会热加载，必须重新部署并重开一局。**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-addon.ps1
```

### 什么时候要加 `-Compile`

| 改了什么 | 需要 `-Compile` 吗 |
| --- | --- |
| `game/.../scripts/vscripts/**/*.lua`、`scripts/npc/*.txt`、`resource/*.txt`、`scripts/data/*.kv` | ❌ 不需要 |
| `content/.../maps/*.vmap` | ✅ 需要 |
| `content/.../panorama/**`（xml / css / js / 图片） | ✅ 需要 |
| `content/.../materials/**` | ✅ 需要 |

判断办法：`content\...\maps\dota2_rpg_demo.vmap` 的修改时间 **早于** 已部署 VPK 的修改时间，就不用重编译。

```powershell
Get-Item .\content\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vmap | Select-Object LastWriteTime
Get-Item "$env:ProgramFiles(x86)\Steam\steamapps\common\dota 2 beta\game\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vpk" | Select-Object LastWriteTime
```

### 确认部署真的生效（推荐）

`install-addon.ps1` 会把 `game/` 和 `content/` 覆盖复制到 Dota 目录。改完关键文件后对一次哈希：

```powershell
$rel = 'game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua'
$src = "F:\dota2_rpg\$rel"
$dst = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\$rel"
(Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash    # True = 已部署
```

---

## 3. 启动脚本 `scripts/launch-addon.ps1`

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch-addon.ps1 [参数]
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-DotaPath` | `C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta` | Dota 安装目录 |
| `-SteamExe` | 自动推断 | `steam.exe` 路径 |
| `-Addon` / `-Map` | `dota2_rpg` / `dota2_rpg_demo` | 一般不用改 |
| `-Mode` | `auto` | `auto` / `direct` / `steam`，见下 |
| `-KillExisting` | 关 | 先杀掉正在跑的 `dota2` 再启动（重开一局时必用） |
| `-WaitForMap` | 关 | 阻塞等待并确认"真的进图"（**agent 应该总是加上**） |
| `-LaunchTimeoutSeconds` | `90` | 等待日志开始写的上限 |
| `-MapTimeoutSeconds` | `300` | `-WaitForMap` 等待进图的上限 |

### 两种启动模式 —— 为什么需要两个

| 模式 | 做法 | 说明 |
| --- | --- | --- |
| `direct` | `Start-Process dota2.exe -tools -addon ... -condebug` | 最直接。历史上（9/8 之前）一直这么用 |
| `steam` | `steam.exe -applaunch 570 -tools -addon ... -condebug` | 由 Steam 以交互会话拉起，绕开 GPU 会话问题 |

**已知坑（已复现，会复发）**：某些执行上下文中直接拉起 `dota2.exe` 会因为拿不到 GPU 交互会话而**秒退**，日志里是：

```
[RenderSystem] Failed to initialize NVidia driver!
Driver error at 0x1035DB89+00000000: NVAPI_ACCESS_DENIED
```

驱动本身没问题，只是该进程上下文没有可用的图形会话。此时**改用 `steam` 模式即可**（该模式下日志正常出现 `Creating device for graphics adapter 0 'NVIDIA GeForce RTX 4060 Ti'` 与 `Successfully created dx11 swap chain`）。

`-Mode auto`（默认）的行为：先试 `direct`，**验证失败后自动清理残留进程并改走 `steam` 重试**。

---

## 4. 怎么确认"真的进图了"（本节最重要）

**不要相信"启动命令返回成功"。** 本项目历史上出现过连续三次 `launch_ok`，但实际一局都没起来，`console.log` 的修改时间停在更早的会话。

### 4.1 新会话怎么覆盖日志

每次启动，`console.log` 会被**覆盖重写**，内容从本次启动的
`[RenderSystem] Creating device for graphics adapter ...` 开始。

> 它**有时**会先把上一份另存为 `console.log.bak-<stamp>`（本机 12:10 那次出现过，
> 12:47 那次就没有），**所以不要用 `.bak` 判断有没有新会话**。
> 可靠判据只有一条：**`console.log` 的 `LastWriteTime` 晚于你的启动时刻**
> （`launch-addon.ps1` 用的就是这个判据），或者文件从 GPU 初始化行重新开头。

> ⚠️ **不要手工删除 `console.log`**。本环境的删除守卫会拦掉批量删除
> （`[safe-delete][SAFE_DELETE_BULK_GUARD_ERROR] bulk delete guard blocked deletion`），
> 而且这一步根本不需要 —— 用增量读取就够了（见 4.4）。

### 4.2 成功标记（在 `console.log` 里 grep）

| 标记 | 含义 |
| --- | --- |
| `[RPGTrace t=1.93] BUILD rpg-runtime-v44-20260912 loaded; log=console.log (-condebug)` | Lua 已加载，且**这一行能核对实际跑的是哪版代码**（grep `BUILD rpg-runtime-`） |
| `[RPGPrecache] startup_complete build=rpg-runtime-v44-20260912 level=ch01 units=3 items=4 ...` | 第一关资源预加载完成，可以开战 |
| `[Dota2Rpg] Level 'ch01' spawned 3 enemy units.` | 第一关敌人真的生成了 |

### 4.3 失败标记

| 标记 | 含义 |
| --- | --- |
| `NVAPI_ACCESS_DENIED` / `Failed to initialize NVidia driver!` | GPU 会话不可用 → 换 `-Mode steam` |
| 日志里完全没有本次会话的新内容 | 进程根本没跑到日志初始化就死了 |
| `[Client] CL: CGameRules::CGameRules destructed` 紧跟启动 | 起来又立刻退出了 |

### 4.4 只看增量，别把整个日志读进上下文

`console.log` 单局就有 **1.5 MB 以上**，整份读进上下文会直接炸掉。用这些方式：

```powershell
# 启动前记字节数 + 时刻
$log = 'C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\dota\console.log'
$before = (Get-Item $log).Length
$t0 = Get-Date

# 启动后只取新增部分（文件更短说明被覆盖重写过，那就从头读）
$fs = [IO.File]::Open($log,'Open','Read','ReadWrite')
if ($fs.Length -lt $before) { $before = 0 }
$fs.Seek($before,'Begin') | Out-Null
(New-Object IO.StreamReader($fs)).ReadToEnd()   # 只看这一段
$fs.Dispose()
```

更省事的三种等价做法：

```powershell
# A. 直接让脚本回答（推荐）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch-addon.ps1 -KillExisting -WaitForMap

# B. 只看关键行，最多 40 行
Select-String -Path $log -Pattern 'RPGPrecache|Dota2Rpg|RPGTrace|ERROR|lua_run|NVAPI' |
  Select-Object -Last 40

# C. 只看尾部
Get-Content $log -Tail 40
```

---

## 5. 故障对照表

| 现象 | 原因 | 处置 |
| --- | --- | --- |
| `dota2 process exited during startup` + 日志有 `NVAPI_ACCESS_DENIED` | GPU 会话不可用 | `-Mode steam`（`auto` 会自动重试） |
| `console.log did not start writing` | 进程没起来就被 Steam 拦下 | 确认 `dota2` 没有残留实例；确认 Steam 在跑且已登录 |
| 报 `Dota is already running (PID ...)` | 旧实例还在 | 加 `-KillExisting` |
| 启动成功但代码改动没生效 | 忘了部署，或改了 Lua 却没重开一局 | 跑 `install-addon.ps1` 再重开；用日志里的 `BUILD rpg-runtime-...` 核对版本号 |
| 进图了但资源/画面没更新 | 改了 `content/` 却没 `-Compile` | 加 `-Compile` 重新部署 |
| 日志被守卫拦住删不掉 | 本环境的 safe-delete 守卫 | **别删**，用 4.4 的增量读取 |
| PowerShell 命令看不到 stdout | 部分工具封装不回显 | 重定向到文件再读（`... *> out.txt`）。Claude Code 会话里从 Bash 调 `pwsh -File ...` 能直接拿到 stdout；若你的封装会拦 Bash→PowerShell，就用该封装自带的 PowerShell 工具 + 重定向 |

---

## 6. Agent 调用注意事项

1. **用 `pwsh -File` 调脚本**，不要在 Bash 里拼 PowerShell 内联命令 —— 引号和
   `$` 转义很容易出错。若工具封装拦了 Bash→PowerShell，改用封装自带的 PowerShell
   工具并把输出重定向到文件再读。
2. **启动一定要带 `-WaitForMap`**，靠退出码判断，不要靠"命令没报错"。
3. **重开一局必须 `-KillExisting`**：Steam 不允许同时跑两个 Dota 实例。
4. **不要读整个 `console.log`**（1.5 MB+），用 `Select-String` / `-Tail` / 字节偏移。
5. **不要删除 `console.log`**（守卫会拦，且无必要，引擎自己轮转）。
6. **确认代码版本**：日志里的 `BUILD rpg-runtime-vXX-YYYYMMDD` 必须和你刚改的源码一致，
   否则说明没部署或没重开。
7. 启动会**占用用户桌面约 1–2 分钟**（游戏窗口会抢焦点）。在无人值守/用户正在
   用机器时，先确认再启动。
8. 这一整个流程**只在本机**执行，不联网、不发布任何东西。

---

## 7. 典型循环（改代码 → 看效果）

```powershell
cd F:\dota2_rpg

# 1. 改 Lua / KV / 数据 ...

# 2. 静态检查
python scripts/test-all.py            # 需要 Lua 5.1 时用 LUA_BIN 指定，见 README

# 3. 部署
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-addon.ps1

# 4. 重开一局并确认进图
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch-addon.ps1 -KillExisting -WaitForMap

# 5. 读关心的日志（增量 / 关键字，不要整份读）
$log = 'C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\dota\console.log'
Select-String -Path $log -Pattern 'RPGPrecache|Dota2Rpg|RPGTrace|ERROR|lua_run' | Select-Object -Last 40

# 6. 收工：关掉游戏
Get-Process dota2 -ErrorAction SilentlyContinue | Stop-Process -Force
```

---

## 8. 本文档的验证边界

**已实机验证**（2026-09-12 12:47–12:48）：

- `scripts/launch-addon.ps1 -KillExisting -WaitForMap` 端到端跑通，退出码 `0`
  并打印 `MAP READY: build=rpg-runtime-v44-20260912, first stage spawned 3 enemy unit(s).`
- 本次 `-Mode auto` 走的是 **direct 模式且成功**（日志有
  `Creating device for graphics adapter 0 'NVIDIA GeForce RTX 4060 Ti'` 与
  `Successfully created dx11 swap chain`）。也就是说第 3 节那个 `NVAPI_ACCESS_DENIED`
  是**环境相关**的，不是每次都复现。
- 日志被覆盖重写、且本次**没有**生成 `.bak` 备份 —— 4.1 已按实测更正。
- `console.log` 里本次会话的 `BUILD rpg-runtime-v44-20260912` 与源码一致，
  说明部署与重开都生效了。

**仍未验证**：

- `-Mode auto` 里 "direct 失败 → 自动回退 steam" 那条**回退分支**没有被触发过
  （这次 direct 就成功了），`-Mode steam` 也尚未单独实测。
  真要遇到 NVAPI 失败时，先用 `-Mode steam` 显式指定跑一遍。
- `-Compile` 路径（改 vmap / panorama 资源后重新编译）不在本文档的验证范围内。
