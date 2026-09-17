param([switch]$Check)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $repoRoot 'content/dota_addons/dota2_rpg_endless/panorama/images/custom_game/card_forge'
$sources = [ordered]@{
    element = 'b4abc352-adac-4c04-b317-a50fda9b5ef7.png'
    civilization = 'be9a6cb4-b644-4567-8cbc-dc19aac2eb63.png'
    divine = 'cbc16103-fc85-4701-881d-4925517c5031.png'
    abyss = 'cc414802-49e5-4e01-a92f-5359e3ace084.png'
    wild = 'ea13d122-aee2-4716-856b-2ff57cbe5027.png'
}
foreach ($name in $sources.Keys) {
    $source = Join-Path $repoRoot ('pics/' + $sources[$name])
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing user-provided card back: $source" }
}
Add-Type -AssemblyName System.Drawing
if ($Check) {
    foreach ($name in @($sources.Keys) + @('stone')) {
        $target = Join-Path $assetRoot ($name + '.png')
        if (-not (Test-Path -LiteralPath $target)) { throw "Missing derived texture: $target" }
        $bitmap = [System.Drawing.Image]::FromFile($target)
        try {
            $expectedWidth = if ($name -eq 'stone') { 512 } else { 530 }
            $expectedHeight = if ($name -eq 'stone') { 512 } else { 742 }
            if ($bitmap.Width -ne $expectedWidth -or $bitmap.Height -ne $expectedHeight) { throw "Unexpected texture size: $target" }
        } finally { $bitmap.Dispose() }
    }
    Write-Output 'PASS: all six native card textures exist with expected dimensions.'
    exit 0
}
New-Item -ItemType Directory -Force -Path $assetRoot | Out-Null
Write-Output 'Regenerating derived native textures only. Original pics files are preserved.'
foreach ($name in $sources.Keys) {
    $source = [System.Drawing.Image]::FromFile((Join-Path $repoRoot ('pics/' + $sources[$name])))
    $target = [System.Drawing.Bitmap]::new(530, 742)
    $graphics = [System.Drawing.Graphics]::FromImage($target)
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($source, 0, 0, 530, 742)
        $target.Save((Join-Path $assetRoot ($name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $target.Dispose(); $source.Dispose() }
}
$source = [System.Drawing.Image]::FromFile((Join-Path $repoRoot ('pics/' + $sources['element'])))
$target = [System.Drawing.Bitmap]::new(512, 512)
$graphics = [System.Drawing.Graphics]::FromImage($target)
$shade = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(230, 10, 21, 22))
try {
    $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, 512, 512), [System.Drawing.Rectangle]::new(140, 140, 300, 300), [System.Drawing.GraphicsUnit]::Pixel)
    $graphics.FillRectangle($shade, 0, 0, 512, 512)
    $target.Save((Join-Path $assetRoot 'stone.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $shade.Dispose(); $graphics.Dispose(); $target.Dispose(); $source.Dispose() }
Write-Output "Prepared native card textures: $assetRoot"
