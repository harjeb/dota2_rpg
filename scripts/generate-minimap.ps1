param(
    [int]$Size = 1024,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "content\dota_addons\dota2_rpg\materials\overviews\dota2_rpg_demo.png"
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force $outputDirectory | Out-Null

$bitmap = [System.Drawing.Bitmap]::new($Size, $Size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$margin = [int]($Size * 0.045)
$arenaSize = $Size - ($margin * 2)
$right = $Size - $margin
$bottom = $Size - $margin
$center = [int]($Size / 2)

$backgroundBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 13, 20, 26))
$arenaBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 32, 43, 46))
$radiantBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(185, 34, 103, 91))
$direBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(185, 126, 48, 47))
$centerBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(230, 38, 45, 49))
$gridPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(90, 148, 164, 166), 1)
$majorGridPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(135, 174, 185, 184), 2)
$borderPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 219, 198, 125), 6)
$dividerPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(190, 218, 210, 177), 3)
$centerPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(220, 232, 218, 164), 4)
$radiantSpawnBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 96, 225, 190))
$direSpawnBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 244, 111, 98))
$spawnRingPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(230, 243, 238, 217), 3)

try {
    $graphics.FillRectangle($backgroundBrush, 0, 0, $Size, $Size)
    $graphics.FillRectangle($arenaBrush, $margin, $margin, $arenaSize, $arenaSize)

    $radiantPolygon = [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new($margin, $margin),
        [System.Drawing.Point]::new($margin, $bottom),
        [System.Drawing.Point]::new($right, $bottom)
    )
    $direPolygon = [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new($margin, $margin),
        [System.Drawing.Point]::new($right, $margin),
        [System.Drawing.Point]::new($right, $bottom)
    )
    $graphics.FillPolygon($radiantBrush, $radiantPolygon)
    $graphics.FillPolygon($direBrush, $direPolygon)

    for ($index = 1; $index -lt 16; $index++) {
        $coordinate = $margin + [int](($arenaSize / 16.0) * $index)
        $pen = if ($index % 4 -eq 0) { $majorGridPen } else { $gridPen }
        $graphics.DrawLine($pen, $coordinate, $margin, $coordinate, $bottom)
        $graphics.DrawLine($pen, $margin, $coordinate, $right, $coordinate)
    }

    $graphics.DrawLine($dividerPen, $margin, $margin, $right, $bottom)
    $centerRadius = [int]($Size * 0.085)
    $graphics.FillEllipse($centerBrush, $center - $centerRadius, $center - $centerRadius, $centerRadius * 2, $centerRadius * 2)
    $graphics.DrawEllipse($centerPen, $center - $centerRadius, $center - $centerRadius, $centerRadius * 2, $centerRadius * 2)
    $graphics.DrawRectangle($borderPen, $margin, $margin, $arenaSize, $arenaSize)

    function Convert-WorldPoint([double]$WorldX, [double]$WorldY) {
        $pixelX = $margin + (($WorldX + 8192.0) / 16384.0 * $arenaSize)
        $pixelY = $bottom - (($WorldY + 8192.0) / 16384.0 * $arenaSize)
        return [System.Drawing.PointF]::new([single]$pixelX, [single]$pixelY)
    }

    $radiantSpawns = @(
        (Convert-WorldPoint -1100 -650),
        (Convert-WorldPoint -1350 0),
        (Convert-WorldPoint -1100 650)
    )
    $direSpawns = @(
        (Convert-WorldPoint 1100 650),
        (Convert-WorldPoint 1350 0),
        (Convert-WorldPoint 1100 -650)
    )

    foreach ($point in $radiantSpawns) {
        $graphics.DrawEllipse($spawnRingPen, $point.X - 15, $point.Y - 15, 30, 30)
        $graphics.FillEllipse($radiantSpawnBrush, $point.X - 9, $point.Y - 9, 18, 18)
    }
    foreach ($point in $direSpawns) {
        $graphics.DrawEllipse($spawnRingPen, $point.X - 15, $point.Y - 15, 30, 30)
        $graphics.FillEllipse($direSpawnBrush, $point.X - 9, $point.Y - 9, 18, 18)
    }

    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    $backgroundBrush.Dispose()
    $arenaBrush.Dispose()
    $radiantBrush.Dispose()
    $direBrush.Dispose()
    $centerBrush.Dispose()
    $gridPen.Dispose()
    $majorGridPen.Dispose()
    $borderPen.Dispose()
    $dividerPen.Dispose()
    $centerPen.Dispose()
    $radiantSpawnBrush.Dispose()
    $direSpawnBrush.Dispose()
    $spawnRingPen.Dispose()
}

Write-Host "Generated minimap: $OutputPath"
