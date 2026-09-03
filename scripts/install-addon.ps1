param(
    [string]$DotaPath = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta",
    [switch]$Compile
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceContent = Join-Path $repoRoot "content\dota_addons\dota2_rpg"
$sourceGame = Join-Path $repoRoot "game\dota_addons\dota2_rpg"
$targetContent = Join-Path $DotaPath "content\dota_addons\dota2_rpg"
$targetGame = Join-Path $DotaPath "game\dota_addons\dota2_rpg"

if (-not (Test-Path -LiteralPath $sourceContent) -or -not (Test-Path -LiteralPath $sourceGame)) {
    throw "Addon source folders are missing under $repoRoot"
}

if (-not (Test-Path -LiteralPath $DotaPath)) {
    throw "Dota 2 installation was not found at $DotaPath"
}

Write-Host "Installing dota2_rpg addon. Existing files with the same names will be overwritten."
New-Item -ItemType Directory -Force $targetContent, $targetGame | Out-Null
Copy-Item -Path (Join-Path $sourceContent "*") -Destination $targetContent -Recurse -Force
Copy-Item -Path (Join-Path $sourceGame "*") -Destination $targetGame -Recurse -Force

if ($Compile) {
    $compiler = Join-Path $DotaPath "game\bin\win64\resourcecompiler.exe"
    $gameInfoDirectory = Join-Path $DotaPath "game\dota"
    if (-not (Test-Path -LiteralPath $compiler)) {
        throw "resourcecompiler.exe was not found at $compiler"
    }

    $resources = @(
        (Join-Path $targetContent "maps\dota2_rpg_demo.vmap"),
        (Join-Path $targetContent "materials\overviews\dota2_rpg_demo.vtex"),
        (Join-Path $targetContent "materials\overviews\dota2_rpg_demo.vmat"),
        (Join-Path $targetContent "panorama\layout\custom_game\custom_ui_manifest.xml"),
        (Join-Path $targetContent "panorama\layout\custom_game\rpg_demo_hud.xml"),
        (Join-Path $targetContent "panorama\styles\custom_game\rpg_demo_hud.css"),
        (Join-Path $targetContent "panorama\scripts\custom_game\rpg_demo_hud.js")
    )

    foreach ($resource in $resources) {
        Write-Host "Compiling $resource"
        & $compiler -game $gameInfoDirectory -f -i $resource
        if ($LASTEXITCODE -ne 0) {
            throw "Resource compilation failed for $resource with exit code $LASTEXITCODE"
        }
    }
}

Write-Host "Installed content addon: $targetContent"
Write-Host "Installed game addon:    $targetGame"
Write-Host "In VConsole run: dota_launch_custom_game dota2_rpg dota2_rpg_demo"
