<#
.SYNOPSIS
    启动 dota2_rpg 自定义地图（Workshop Tools 模式），并验证真的进入了地图。

.DESCRIPTION
    解决三类反复出现的启动问题：
      1. 直接拉起 dota2.exe 在部分上下文里拿不到 GPU 会话，秒退并留下
         NVAPI_ACCESS_DENIED（-Mode auto 会自动改走 Steam 协议重试）。
      2. "看起来启动了" 其实没进图 —— 本脚本会核对 console.log 是否真的开始写，
         以及是否出现进入地图的标记，失败时给出日志尾部。
      3. 旧实例还在跑导致新实例起不来 —— 用 -KillExisting 先清理。

    日志：<Dota>\game\dota\console.log（由 -condebug 产生）。
    引擎会自己把上一局的日志轮转成 console.log.bak-<stamp>，不要手工删除 console.log。

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch-addon.ps1 -KillExisting -WaitForMap

.EXAMPLE
    # 直连模式失败（NVAPI）时强制走 Steam
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch-addon.ps1 -Mode steam -KillExisting
#>
param(
    [string]$DotaPath = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta",
    [string]$SteamExe = "",
    [string]$Addon = "dota2_rpg",
    [string]$Map = "dota2_rpg_demo",
    [ValidateSet("auto", "direct", "steam")][string]$Mode = "auto",
    [switch]$KillExisting,
    [switch]$WaitForMap,
    [int]$LaunchTimeoutSeconds = 90,
    [int]$MapTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

function Get-NewLogText {
    param([string]$Path, [long]$FromByte)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -lt $FromByte) { $FromByte = 0 }   # 日志被轮转过，从头读
        $stream.Seek($FromByte, [System.IO.SeekOrigin]::Begin) | Out-Null
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    } finally { $stream.Dispose() }
}

function Get-LogLength {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return (Get-Item -LiteralPath $Path).Length
}

function Get-DotaProcess {
    return @(Get-Process -Name dota2 -ErrorAction SilentlyContinue)
}

function Resolve-SteamExe {
    param([string]$DotaInstall, [string]$Override)
    if ($Override -and (Test-Path -LiteralPath $Override)) { return $Override }
    # <Steam>\steamapps\common\dota 2 beta  ->  上溯三级到 <Steam>
    $candidate = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $DotaInstall))) "steam.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $fromRegistry = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamExe -ErrorAction SilentlyContinue).SteamExe
    if ($fromRegistry -and (Test-Path -LiteralPath $fromRegistry)) { return $fromRegistry }
    return ""
}

$executable = Join-Path $DotaPath "game\bin\win64\dota2.exe"
if (-not (Test-Path -LiteralPath $executable)) {
    throw "Dota executable not found: $executable"
}
$consoleLog = Join-Path $DotaPath "game\dota\console.log"

# ---- 1. 清理旧实例 ----------------------------------------------------------
$existing = Get-DotaProcess
if ($existing.Count -gt 0) {
    if (-not $KillExisting) {
        throw ("Dota is already running (PID {0}). Close it, or pass -KillExisting to restart." -f (($existing | ForEach-Object { $_.Id }) -join ", "))
    }
    Write-Host ("Stopping {0} running dota2 process(es)..." -f $existing.Count)
    $existing | Stop-Process -Force
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ((Get-DotaProcess).Count -eq 0) { break }
    }
    if ((Get-DotaProcess).Count -gt 0) { throw "dota2 did not exit within 30s." }
    Start-Sleep -Seconds 2
}

$gameArgs = @(
    "-tools", "-addon", $Addon, "-novid", "-console", "-condebug",
    "+dota_launch_custom_game", $Addon, $Map
)

function Start-DirectLaunch {
    Write-Host "Mode: direct (dota2.exe)"
    $script:logBaseline = Get-LogLength -Path $consoleLog
    $script:launchTime = Get-Date
    Start-Process -FilePath $executable -WorkingDirectory (Split-Path -Parent $executable) -ArgumentList $gameArgs | Out-Null
}

function Start-SteamLaunch {
    $steam = Resolve-SteamExe -DotaInstall $DotaPath -Override $SteamExe
    if (-not $steam) { throw "steam.exe not found; pass -SteamExe explicitly." }
    Write-Host ("Mode: steam ({0} -applaunch 570)" -f $steam)
    if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) {
        Write-Host "Starting Steam..."
        Start-Process -FilePath $steam | Out-Null
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 1
            if (Get-Process -Name steam -ErrorAction SilentlyContinue) { break }
        }
        Start-Sleep -Seconds 5
    }
    $script:logBaseline = Get-LogLength -Path $consoleLog
    $script:launchTime = Get-Date
    Start-Process -FilePath $steam -ArgumentList (@("-applaunch", "570") + $gameArgs) | Out-Null
}

# ---- 2. 启动 + 确认日志真的开始写 -------------------------------------------
function Wait-ForLogStart {
    param([int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $item = Get-Item -LiteralPath $consoleLog -ErrorAction SilentlyContinue
        if ($item -and $item.LastWriteTime -gt $script:launchTime) {
            return (Get-NewLogText -Path $consoleLog -FromByte $script:logBaseline)
        }
    }
    return $null
}

function Stop-LaunchAttempt {
    $procs = Get-DotaProcess
    if ($procs.Count -gt 0) {
        Write-Host ("Cleaning up {0} unfinished dota2 process(es)..." -f $procs.Count)
        $procs | Stop-Process -Force
        Start-Sleep -Seconds 3
    }
}

function Start-Attempt {
    param([string]$Which)
    if ($Which -eq "direct") { Start-DirectLaunch } else { Start-SteamLaunch }
    $text = Wait-ForLogStart -TimeoutSeconds $LaunchTimeoutSeconds
    if ($null -eq $text -or $text.Trim().Length -eq 0) {
        Write-Host "FAIL: console.log did not start writing - the game never reached its own logging setup."
        return @{ ok = $false; text = ""; reason = "no-log" }
    }
    if ($text -match "(?i)NVAPI_ACCESS_DENIED|Failed to initialize NVidia driver") {
        Write-Host "FAIL: GPU session unavailable (NVAPI_ACCESS_DENIED)."
        return @{ ok = $false; text = $text; reason = "nvapi" }
    }
    if (-not (Get-Process -Name dota2 -ErrorAction SilentlyContinue)) {
        Write-Host "FAIL: dota2 process exited during startup."
        return @{ ok = $false; text = $text; reason = "exited" }
    }
    return @{ ok = $true; text = $text; reason = "" }
}

$result = $null
if ($Mode -eq "direct") {
    $result = Start-Attempt -Which "direct"
} elseif ($Mode -eq "steam") {
    $result = Start-Attempt -Which "steam"
} else {
    $result = Start-Attempt -Which "direct"
    if (-not $result.ok) {
        Stop-LaunchAttempt
        Write-Host "Falling back to the Steam protocol launch..."
        $result = Start-Attempt -Which "steam"
    }
}

if (-not $result.ok) {
    Write-Host "LAUNCH FAILED (reason: $($result.reason))."
    if ($result.text) {
        Write-Host "--- console.log tail of this attempt ---"
        Write-Host (($result.text -split "`r?`n" | Select-Object -Last 20) -join "`n")
    }
    exit 1
}

$launchedPid = (Get-DotaProcess | Select-Object -First 1).Id
Write-Host ("LAUNCH OK: dota2 PID {0}; console.log is writing." -f $launchedPid)

# ---- 3. 等进图 --------------------------------------------------------------
if ($WaitForMap) {
    Write-Host "Waiting for the map to load (up to $MapTimeoutSeconds s)..."
    $cursor = $script:logBaseline
    $deadline = (Get-Date).AddSeconds($MapTimeoutSeconds)
    $build = $null
    $spawn = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $chunk = Get-NewLogText -Path $consoleLog -FromByte $cursor
        if ($chunk) {
            $cursor = Get-LogLength -Path $consoleLog
            foreach ($line in ($chunk -split "`r?`n")) {
                if ($line -match "\[RPGPrecache\] startup_complete build=(\S+)") { $build = $Matches[1]; Write-Host $line.Trim() }
                elseif ($line -match "\[Dota2Rpg\] Level '(\w+)' spawned (\d+) enemy units") { $spawn = $Matches[2]; Write-Host $line.Trim() }
                elseif ($line -match "(?i)NVAPI_ACCESS_DENIED|Failed to initialize NVidia driver") { Write-Host "FAIL: $($line.Trim())"; exit 1 }
            }
        }
        if (-not (Get-Process -Id $launchedPid -ErrorAction SilentlyContinue)) { Write-Host "FAIL: dota2 exited while loading the map."; exit 1 }
        if ($build -and $spawn) { break }
    }
    if ($build -and $spawn) {
        Write-Host ("MAP READY: build={0}, first stage spawned {1} enemy unit(s)." -f $build, $spawn)
    } else {
        Write-Host "MAP NOT CONFIRMED within the timeout. Grep the log for [RPGPrecache]/[Dota2Rpg]/errors:"
        Write-Host ("  Select-String -Path '{0}' -Pattern 'RPGPrecache|Dota2Rpg|lua_run|ERROR' | Select-Object -Last 40" -f $consoleLog)
        exit 1
    }
}

Write-Host ("Console log: {0}" -f $consoleLog)
exit 0
