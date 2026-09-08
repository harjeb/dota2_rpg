param(
    [string]$DotaPath = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"
)

$ErrorActionPreference = "Stop"
$executable = Join-Path $DotaPath "game\bin\win64\dota2.exe"
if (-not (Test-Path -LiteralPath $executable)) {
    throw "Dota executable not found: $executable"
}
if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) {
    throw "Dota is already running. Close it before starting a new addon session."
}

# Current Source 2 removed con_logfile; -condebug captures native errors and
# RPGTrace messages in game/dota/console.log from the start of this session.
$process = Start-Process -FilePath $executable -WorkingDirectory (Split-Path -Parent $executable) -ArgumentList @(
    "-tools", "-addon", "dota2_rpg", "-novid", "-console", "-condebug",
    "+dota_launch_custom_game", "dota2_rpg", "dota2_rpg_demo"
) -PassThru
Write-Host "Dota launch requested (PID $($process.Id))."
Write-Host "Console log: $(Join-Path $DotaPath 'game\dota\console.log')"
