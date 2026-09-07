param(
    [string]$DotaPath = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"
)

# Static Source 2 map compilation only. This script never starts dota2.exe or
# Workshop Tools; it copies the source map under a GUID name, invokes
# resourcecompiler, and removes every generated artifact in finally.
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$mapPath = Join-Path $repoRoot "content\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vmap"
$resourceCompiler = Join-Path $DotaPath "game\bin\win64\resourcecompiler.exe"
$contentMapDirectory = Join-Path $DotaPath "content\dota_addons\dota2_rpg\maps"
$gameMapDirectory = Join-Path $DotaPath "game\dota_addons\dota2_rpg\maps"
$gameDirectory = Join-Path $DotaPath "game\dota"

foreach ($path in @($mapPath, $resourceCompiler, $contentMapDirectory, $gameMapDirectory, $gameDirectory)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required map compiler path is missing: $path"
    }
}

$name = "__dota2_rpg_static_{0}" -f [guid]::NewGuid().ToString("N")
$temporarySource = Join-Path $contentMapDirectory ($name + ".vmap")
$temporaryVpk = Join-Path $gameMapDirectory ($name + ".vpk")
$temporaryVmapC = Join-Path $gameMapDirectory ($name + ".vmap_c")
$temporaryGameDirectory = Join-Path $gameMapDirectory $name
$temporaryStem = Join-Path ([System.IO.Path]::GetTempPath()) ("dota_addons\dota2_rpg\maps\" + $name)

try {
    Copy-Item -LiteralPath $mapPath -Destination $temporarySource -Force
    $compilerOutput = (& $resourceCompiler -nop4 -f -game $gameDirectory -i $temporarySource 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "resourcecompiler failed with exit code $LASTEXITCODE`n$compilerOutput"
    }
    if ($compilerOutput -notmatch 'OK:\s+\d+ compiled,\s+0 failed') {
        throw "resourcecompiler did not report a clean compilation`n$compilerOutput"
    }
    if (($compilerOutput -match ('Write .*' + [regex]::Escape($name) + '\.vpk Failed!')) -or ($compilerOutput -notmatch ('Wrote .*' + [regex]::Escape($name) + '\.vpk'))) {
        throw "resourcecompiler did not confirm a successful VPK write`n$compilerOutput"
    }
    if (-not (Test-Path -LiteralPath $temporaryVpk)) {
        throw "resourcecompiler returned success but did not write $temporaryVpk"
    }
    $vpkInfo = Get-Item -LiteralPath $temporaryVpk
    if ($vpkInfo.Length -le 0) {
        throw "resourcecompiler wrote an empty VPK: $temporaryVpk"
    }
    Write-Host ("PASS: static VMAP resourcecompiler build succeeded and wrote VPK ({0} bytes; no Dota client launched)." -f $vpkInfo.Length)
}
finally {
    Remove-Item -LiteralPath $temporarySource -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryVpk -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryVmapC -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryGameDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath ($temporaryStem + ".rte") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath ($temporaryStem + ".viscfg") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryStem -Recurse -Force -ErrorAction SilentlyContinue
}
