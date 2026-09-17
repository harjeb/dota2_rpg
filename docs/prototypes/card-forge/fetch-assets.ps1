$ErrorActionPreference = 'Stop'
$assetRoot = Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null
$heroNames = @('lina', 'crystal_maiden', 'dragon_knight', 'kunkka', 'omniknight', 'nevermore', 'ursa', 'windrunner', 'storm_spirit', 'invoker', 'legion_commander', 'dawnbreaker', 'queenofpain', 'treant')
foreach ($heroName in $heroNames) {
    $targetPath = Join-Path $assetRoot "$heroName.png"
    if (-not (Test-Path -LiteralPath $targetPath)) {
        Invoke-WebRequest -Uri "https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/heroes/crops/$heroName.png" -OutFile $targetPath
    }
}
$stonePath = Join-Path $assetRoot 'stone.jpg'
if (-not (Test-Path -LiteralPath $stonePath)) {
    Invoke-WebRequest -Uri 'https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/backgrounds/greyfade.jpg' -OutFile $stonePath
}
Write-Output "Downloaded Valve Dota 2 presentation assets to $assetRoot"
