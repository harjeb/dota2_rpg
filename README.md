# Dota 2 RPG Combat Demo

This repository contains a real Dota 2 Workshop Tools custom-game addon named `dota2_rpg`.

## Demo behavior

- Radiant starts with level-30 Sven, Lina, and Dazzle. Dire starts with level-30 Axe, Lion, and Crystal Maiden.
- All six battle heroes are script controlled. Player-issued unit orders are rejected.
- Both teams are frozen and invulnerable until the center **Start Battle** button is pressed.
- Click any hero portrait to switch the active editor. All six heroes keep independent five-rule priority lists for ultimate, abilities 1-3, and basic attack.
- Rules can be reordered and use HP thresholds, current action range, highest/lowest HP enemy, nearest/farthest enemy, selected enemy effects, or enemy channeling as execution and target-selection conditions. HP thresholds accept integers from 1 to 100.
- Effect rules provide BKB/magic immunity, stunned, silenced, and rooted selectors, with separate "has effect" and "lacks effect" conditions.
- Heroes automatically select enemy/friendly targets, move into cast range, cast ready abilities, and fall through to lower-priority rules when a rule cannot run.
- The two formations start near the center, roughly half the previous distance apart, so combat begins quickly after pressing Start Battle.
- Respawning and buyback are disabled. The first team with no living battle heroes loses.
- Fog of war is disabled for the entire match.
- The map uses a full `64 x 64` Dota terrain grid from `-8192` to `8192`, with no height variation, water, terrain objects, river, or buildings.
- A custom 1024 x 1024 tactical minimap shows the two team halves, arena grid, center zone, and starting formations.

## Verify the source

```powershell
pwsh -File .\tests\verify-addon.ps1
```

Expected signal: the command ends with `PASS:` and no XML or JavaScript syntax errors.

## Install and compile

The installer overwrites only files inside the existing `dota2_rpg` addon folders with matching names. It does not delete other files.

```powershell
pwsh -File .\scripts\install-addon.ps1 -Compile
```

Expected signals:

- Every listed resource reports successful compilation.
- The final output prints the installed content/game addon paths.
- `game\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vpk` exists after map compilation.
- `game\dota_addons\dota2_rpg\materials\overviews\dota2_rpg_demo.vtex_c` and `dota2_rpg_demo.vmat_c` exist after minimap compilation.

For a non-default Steam library, pass the Dota installation path explicitly:

```powershell
pwsh -File .\scripts\install-addon.ps1 -DotaPath "D:\SteamLibrary\steamapps\common\dota 2 beta" -Compile
```

## 启动方式

1. 从 Steam 启动 **Dota 2 Workshop Tools**。
2. 在 addon 选择界面选择 `dota2_rpg`。
3. 等待 Asset Browser 和 VConsole 完成加载。
4. 在 VConsole 命令输入框执行：

```text
dota_launch_custom_game dota2_rpg dota2_rpg_demo
```

也可以从 PowerShell 直接启动 Tools，不经过 addon 选择界面：

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe" -tools -addon dota2_rpg -novid -console
```

Asset Browser 和 VConsole 加载完成后，再执行进图命令：

```text
dota_launch_custom_game dota2_rpg dota2_rpg_demo
```

也可以在启动参数中直接请求进入地图：

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe" -tools -addon dota2_rpg -novid -console +dota_launch_custom_game dota2_rpg dota2_rpg_demo
```

正常结果：双方各 3 名 30 级英雄在地图中央附近等待；左右显示我方/敌方行动逻辑编辑器；点击任意英雄头像可切换该英雄自己的 5 条规则；只有点击中间“开始战斗”后双方才自动行动。

## 运行监听方式

测试时保持 Workshop Tools 的 **VConsole** 窗口打开。在搜索/过滤框输入：

```text
[Dota2RpgDemo]
```

正常启动会依次出现类似日志：

```text
[Dota2RpgDemo] 3v3 battle mode initialized.
[Dota2RpgDemo] Spawned three level-30 heroes for each team.
[Dota2RpgDemo] Battle started with player-configured rules.
[Dota2RpgDemo] Battle finished. Result=radiant
```

同时检查 `Script Runtime Error`、`Lua`、`Panorama`、`rpg_demo_hud.js` 和 `XML`。包含这些关键词的红色日志通常表示服务端脚本或 UI 加载失败。Dota Tools 自身偶尔会输出缺失 staging 资源或 shader 的提示；只要没有指向 `dota2_rpg` 文件，一般不是本 addon 的错误。

当前 Workshop Tools 会在本机 `29000` 端口监听 VConsole。用 PowerShell 检查进程和端口：

```powershell
Get-Process dota2 | Select-Object Id, MainWindowTitle, Responding
Get-NetTCPConnection -LocalPort 29000 -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess
```

正常信号：`dota2` 的 `Responding` 为 `True`，并存在 `127.0.0.1:29000` 或 `0.0.0.0:29000` 的监听。端口存在只表示 VConsole 可连接；必须同时看到上面的 `[Dota2RpgDemo]` 日志，才能确认 addon 已实际载入。
