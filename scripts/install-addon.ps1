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
        (Join-Path $targetContent "panorama\images\custom_game\rpg_loading_art_png.vtex"),
        (Join-Path $targetContent "panorama\styles\custom_game\custom_loading_screen.css"),
        (Join-Path $targetContent "panorama\layout\custom_game\custom_loading_screen.xml"),
        (Join-Path $targetContent "panorama\layout\custom_game\custom_ui_manifest.xml"),
        (Join-Path $targetContent "panorama\layout\custom_game\rpg_demo_hud.xml"),
        (Join-Path $targetContent "panorama\styles\custom_game\rpg_demo_hud.css"),
        (Join-Path $targetContent "panorama\layout\custom_game\issue_fixes_ui.xml"),
        (Join-Path $targetContent "panorama\styles\custom_game\issue_fixes_ui.css"),
        (Join-Path $targetContent "panorama\scripts\custom_game\issue_fixes_ui.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\rpg_demo_hud.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\arena_hud.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\campaign_difficulty.js"),
        (Join-Path $targetContent "panorama\styles\custom_game\campaign_difficulty.css"),
        (Join-Path $targetContent "panorama\styles\custom_game\arena_hud.css"),
        (Join-Path $targetContent "panorama\scripts\custom_game\native_shop_wallet.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\shop_transport.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\neutral_recruitment.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\rule_library.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\panorama_rule_sync.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\condition_catalog.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\ability_capabilities.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\rule_diagnostics.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\condition_help.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\condition_help_data.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\skill_debug.js"),
        (Join-Path $targetContent "panorama\scripts\custom_game\skill_condition_presets.js")
    )

    # UI98 uses local textures and hand-inked icons. Compile their explicit
    # descriptors before the HUD so a source-only install cannot show missing art.
    $uiArt = Join-Path $targetContent "panorama\images\custom_game\fantasy_ui"
    $resources = @((Get-ChildItem -LiteralPath $uiArt -Filter "*_png.vtex" | Sort-Object Name | ForEach-Object { $_.FullName })) + @(
        (Join-Path $targetContent "panorama\styles\custom_game\fantasy_ui.css")
    ) + $resources

    foreach ($resource in $resources) {
        Write-Host "Compiling $resource"
        $compilerOutput = (& $compiler -game $gameInfoDirectory -f -i $resource 2>&1 | Out-String)
        Write-Host $compilerOutput
        if ($LASTEXITCODE -ne 0) {
            throw "Resource compilation failed for $resource with exit code $LASTEXITCODE"
        }
        if ($compilerOutput -match '(?i)invalid property name|associate compile failed|\b[1-9][0-9]* failed\b') {
            throw "Resource compiler reported invalid properties or failed resources for $resource"
        }
        if ($resource -like "*maps\dota2_rpg_demo.vmap") {
            $vpk = Join-Path $targetGame "maps\dota2_rpg_demo.vpk"
            if (($compilerOutput -match 'Write .*dota2_rpg_demo\.vpk Failed!') -or ($compilerOutput -notmatch 'Wrote .*dota2_rpg_demo\.vpk')) {
                throw "Map compiler did not confirm a successful VPK write: $vpk"
            }
            if (-not (Test-Path -LiteralPath $vpk)) {
                throw "Map compiler reported a VPK write but the file is missing: $vpk"
            }
            $vpkInfo = Get-Item -LiteralPath $vpk
            if ($vpkInfo.Length -le 0) {
                throw "Map compiler reported a VPK write but the file is empty: $vpk"
            }
            Write-Host ("PASS: deployed VPK exists ({0} bytes, {1})." -f $vpkInfo.Length, $vpkInfo.LastWriteTime.ToString("o"))
        }
    }
}

# Verify both locale files, not only the visible language of this machine.
foreach ($locale in @("addon_english.txt", "addon_schinese.txt")) {
    $from = Join-Path $sourceGame ("resource\" + $locale)
    $to = Join-Path $targetGame ("resource\" + $locale)
    if ((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath $to).Hash) {
        throw "Installed locale differs from this package: $locale"
    }
}
Write-Host "Installed content addon: $targetContent"
Write-Host "Installed game addon:    $targetGame"
Write-Host "In VConsole run: dota_launch_custom_game dota2_rpg dota2_rpg_demo"
