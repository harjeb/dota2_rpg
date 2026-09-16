param(
    [string]$DotaPath = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"
)
# UI-only deployment for an existing installation of the uploaded UI97 project.
# No map rebuild, VPK edits, combat-script changes, or network access.
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$contentRelative = "content\dota_addons\dota2_rpg"
$gameRelative = "game\dota_addons\dota2_rpg"
$sourceContent = Join-Path $repoRoot $contentRelative
$targetContent = Join-Path $DotaPath $contentRelative
$sourceGame = Join-Path $repoRoot $gameRelative
$targetGame = Join-Path $DotaPath $gameRelative
$compiler = Join-Path $DotaPath "game\bin\win64\resourcecompiler.exe"
$gameInfo = Join-Path $DotaPath "game\dota"
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "Dota Workshop Tools resourcecompiler.exe is missing. Check -DotaPath and install Workshop Tools."
}
if (-not (Test-Path -LiteralPath (Join-Path $targetGame "scripts\vscripts\addon_game_mode.lua"))) {
    throw "The base dota2_rpg addon is not installed. Use scripts\install-addon.ps1 -DotaPath <path> -Compile from the full project first."
}
$contentFiles = @(
    "panorama\styles\custom_game\fantasy_ui.css",
    "panorama\scripts\custom_game\condition_catalog.js",
    "panorama\scripts\custom_game\rpg_demo_hud.js",
    "panorama\layout\custom_game\rpg_demo_hud.xml"
)
# Verify everything before overwriting an existing installation.
foreach ($relative in $contentFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceContent $relative))) { throw "Package is incomplete: $relative" }
}
$artRelative = "panorama\images\custom_game\fantasy_ui"
$sourceArt = Join-Path $sourceContent $artRelative
if (-not (Test-Path -LiteralPath $sourceArt)) { throw "Package is missing UI98 artwork." }
$locales = @("addon_english.txt", "addon_schinese.txt")
foreach ($locale in $locales) {
    $source = Join-Path $sourceGame ("resource\" + $locale)
    $text = Get-Content -LiteralPath $source -Raw -Encoding UTF8
    if ($text -notmatch '"dota2_rpg_build_tag"\s+"[^"\r\n]*98"') { throw "Unexpected UI build tag in $locale" }
}
foreach ($relative in $contentFiles) {
    $target = Join-Path $targetContent $relative
    New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceContent $relative) -Destination $target -Force
}
$targetArt = Join-Path $targetContent $artRelative
New-Item -ItemType Directory -Force $targetArt | Out-Null
Copy-Item -Path (Join-Path $sourceArt "*") -Destination $targetArt -Recurse -Force
New-Item -ItemType Directory -Force (Join-Path $targetGame "resource") | Out-Null
foreach ($locale in $locales) {
    Copy-Item -LiteralPath (Join-Path $sourceGame ("resource\" + $locale)) -Destination (Join-Path $targetGame ("resource\" + $locale)) -Force
}
$resources = @((Get-ChildItem -LiteralPath $targetArt -Filter "*_png.vtex" | Sort-Object Name | ForEach-Object { $_.FullName }))
$resources += @($contentFiles | ForEach-Object { Join-Path $targetContent $_ })
foreach ($resource in $resources) {
    Write-Host "Compiling $resource"
    $output = (& $compiler -game $gameInfo -f -i $resource 2>&1 | Out-String)
    $code = $LASTEXITCODE
    Write-Host $output
    if ($code -ne 0 -or $output -match '(?i)invalid property name|associate compile failed|resource compile error|\b[1-9][0-9]* failed\b') {
        throw "Compilation failed. Do not publish this build until resolved: $resource"
    }
    $relative = $resource.Substring($targetContent.Length).TrimStart('\','/')
    $extension = [IO.Path]::GetExtension($relative)
    $compiledExtension = switch ($extension) { '.css' {'.vcss_c'} '.js' {'.vjs_c'} '.xml' {'.vxml_c'} '.vtex' {'.vtex_c'} default { throw "Unexpected resource: $relative" } }
    $compiled = Join-Path $targetGame ([IO.Path]::ChangeExtension($relative, $compiledExtension))
    if (-not (Test-Path -LiteralPath $compiled) -or (Get-Item -LiteralPath $compiled).Length -le 0) {
        throw "Expected compiled output was not written: $compiled"
    }
}
foreach ($locale in $locales) {
    $from = Join-Path $sourceGame ("resource\" + $locale)
    $to = Join-Path $targetGame ("resource\" + $locale)
    if ((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath $to).Hash) { throw "Locale verification failed: $locale" }
}
Write-Host "PASS: UI98 source, textures, compiled resources and both locales installed."
Write-Host "Restart the custom game and confirm the visible UI version is 98."
Write-Host "Workshop publication remains a separate step; this script changes your local addon only."
