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

Write-Output 'Installing isolated dota2_rpg_endless gameplay and UI; matching files are overwritten only in that addon.'
foreach ($kind in @('content', 'game')) {
    $source = Join-Path $repoRoot ($kind + '/dota_addons/dota2_rpg_endless')
    $destination = Join-Path $dotaRoot ($kind + '/dota_addons/dota2_rpg_endless')
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force }
}

if ($Compile) {
    # The playable addon includes the copied battlefield and ordinary HUD, not only cards.
    $resources = Get-ChildItem -LiteralPath $targetContent -Recurse -File |
        Where-Object { $_.Extension -in @('.vtex', '.vmat', '.js', '.css', '.xml', '.vmap') } |
        Sort-Object FullName | ForEach-Object { $_.FullName }
    foreach ($resource in $resources) {
        $output = (& $compiler -game (Join-Path $dotaRoot 'game/dota') -f -i $resource 2>&1 | Out-String)
        Write-Output $output
        if ($LASTEXITCODE -ne 0 -or $output -match '(?i)invalid property name|associate compile failed|\b[1-9][0-9]* failed\b') { throw "Compilation failed: $resource" }
        if ($resource.EndsWith('dota2_rpg_demo.vmap') -and ($output -match 'Write .*dota2_rpg_demo\.vpk Failed!' -or $output -notmatch 'Wrote .*dota2_rpg_demo\.vpk')) {
            throw 'Map compiler did not confirm a successful endless battlefield VPK write.'
        }
    }
    $mapPackage = Join-Path $targetGame 'maps/dota2_rpg_demo.vpk'
    if (-not (Test-Path -LiteralPath $mapPackage) -or (Get-Item -LiteralPath $mapPackage).Length -le 0) {
        throw "Compiled battlefield package is missing or empty: $mapPackage"
    }
}
function Get-ContentHash([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.BitConverter]::ToString($sha.ComputeHash($stream)) }
    finally { $stream.Dispose(); $sha.Dispose() }
}
foreach ($locale in @('addon_schinese.txt', 'addon_english.txt')) {
    $source = Join-Path $repoRoot ('game/dota_addons/dota2_rpg_endless/resource/' + $locale)
    $target = Join-Path $targetGame ('resource/' + $locale)
    if ((Get-ContentHash $source) -ne (Get-ContentHash $target)) { throw "Locale mismatch: $locale" }
}
Write-Output 'PASS: endless gameplay sources installed; both locale files match UI 101 sources.'
Write-Output 'VConsole: dota_launch_custom_game dota2_rpg_endless dota2_rpg_demo'
