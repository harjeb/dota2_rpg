param(
    [Parameter(Mandatory = $true)][string]$DotaPath,
    [switch]$Compile
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$dotaRoot = [System.IO.Path]::GetFullPath($DotaPath)
if (-not (Test-Path -LiteralPath (Join-Path $dotaRoot 'game/dota'))) { throw "Dota installation not found: $dotaRoot" }
$compiler = Join-Path $dotaRoot 'game/bin/win64/resourcecompiler.exe'
if ($Compile -and -not (Test-Path -LiteralPath $compiler)) { throw "Workshop resource compiler not found: $compiler" }

# Verify every existing ancestor: lexical containment alone does not protect against junctions.
function Assert-SafeDestination([string]$Target) {
    $resolved = [System.IO.Path]::GetFullPath($Target)
    if (-not $resolved.StartsWith($dotaRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw "Destination escapes Dota root: $resolved" }
    if ((Split-Path -Leaf $resolved) -ne 'dota2_rpg_endless') { throw "Refusing non-endless addon destination: $resolved" }
    $ancestor = $resolved
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $entry = Get-Item -LiteralPath $ancestor -Force
            if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Refusing reparse-point destination ancestor: $ancestor" }
        }
        $next = Split-Path -Parent $ancestor
        if ($next -eq $ancestor) { break }
        $ancestor = $next
    }
    if (Test-Path -LiteralPath $resolved) {
        $linked = Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } | Select-Object -First 1
        if ($linked) { throw "Refusing addon containing reparse points: $($linked.FullName)" }
    }
}

$targetContent = Join-Path $dotaRoot 'content/dota_addons/dota2_rpg_endless'
$targetGame = Join-Path $dotaRoot 'game/dota_addons/dota2_rpg_endless'
Assert-SafeDestination $targetContent
Assert-SafeDestination $targetGame
& (Join-Path $PSScriptRoot 'prepare-card-ui-assets.ps1')
& (Join-Path $PSScriptRoot 'prepare-card-ui-assets.ps1') -Check

Write-Warning 'This installs the isolated dota2_rpg_endless UI gallery and overwrites matching files only in that addon. Existing dota2_rpg is not a destination.'
foreach ($kind in @('content', 'game')) {
    $source = Join-Path $repoRoot ($kind + '/dota_addons/dota2_rpg_endless')
    $destination = Join-Path $dotaRoot ($kind + '/dota_addons/dota2_rpg_endless')
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force }
}

if ($Compile) {
    $resources = @()
    foreach ($name in @('element', 'civilization', 'divine', 'abyss', 'wild', 'stone')) {
        $resources += Join-Path $targetContent ('panorama/images/custom_game/card_forge/' + $name + '_png.vtex')
    }
    $resources += @(
        (Join-Path $targetContent 'panorama/scripts/custom_game/card_forge_data.js'),
        (Join-Path $targetContent 'panorama/scripts/custom_game/card_forge_model.js'),
        (Join-Path $targetContent 'panorama/scripts/custom_game/card_forge.js'),
        (Join-Path $targetContent 'panorama/styles/custom_game/card_forge.css'),
        (Join-Path $targetContent 'panorama/layout/custom_game/card_forge.xml'),
        (Join-Path $targetContent 'panorama/layout/custom_game/custom_ui_manifest.xml')
    )
    foreach ($resource in $resources) {
        $output = (& $compiler -game (Join-Path $dotaRoot 'game/dota') -f -i $resource 2>&1 | Out-String)
        Write-Output $output
        if ($LASTEXITCODE -ne 0 -or $output -match '(?i)invalid property name|associate compile failed|\b[1-9][0-9]* failed\b') { throw "Compilation failed: $resource" }
    }
}
foreach ($locale in @('addon_schinese.txt', 'addon_english.txt')) {
    $source = Join-Path $repoRoot ('game/dota_addons/dota2_rpg_endless/resource/' + $locale)
    $target = Join-Path $targetGame ('resource/' + $locale)
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Locale mismatch: $locale" }
}
Write-Output 'PASS: native gallery installed; both locale files match UI 100 sources.'
Write-Output 'VConsole: dota_launch_custom_game dota2_rpg_endless dota'
