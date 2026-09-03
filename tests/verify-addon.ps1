param(
    [string]$DotaPath = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    "content\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vmap",
    "content\dota_addons\dota2_rpg\materials\overviews\dota2_rpg_demo.png",
    "content\dota_addons\dota2_rpg\materials\overviews\dota2_rpg_demo.vtex",
    "content\dota_addons\dota2_rpg\materials\overviews\dota2_rpg_demo.vmat",
    "game\dota_addons\dota2_rpg\resource\overviews\dota2_rpg_demo.txt",
    "content\dota_addons\dota2_rpg\panorama\layout\custom_game\custom_ui_manifest.xml",
    "content\dota_addons\dota2_rpg\panorama\layout\custom_game\rpg_demo_hud.xml",
    "content\dota_addons\dota2_rpg\panorama\scripts\custom_game\rpg_demo_hud.js",
    "content\dota_addons\dota2_rpg\panorama\styles\custom_game\rpg_demo_hud.css",
    "game\dota_addons\dota2_rpg\addoninfo.txt",
    "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua",
    "game\dota_addons\dota2_rpg\resource\addon_english.txt",
    "game\dota_addons\dota2_rpg\resource\addon_schinese.txt",
    "scripts\generate-minimap.ps1"
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $relativePath"
    }
}

$manifestPath = Join-Path $repoRoot "content\dota_addons\dota2_rpg\panorama\layout\custom_game\custom_ui_manifest.xml"
$hudPath = Join-Path $repoRoot "content\dota_addons\dota2_rpg\panorama\layout\custom_game\rpg_demo_hud.xml"
[xml](Get-Content -LiteralPath $manifestPath -Raw) | Out-Null
[xml](Get-Content -LiteralPath $hudPath -Raw) | Out-Null

$javascriptPath = Join-Path $repoRoot "content\dota_addons\dota2_rpg\panorama\scripts\custom_game\rpg_demo_hud.js"
& node --check $javascriptPath
if ($LASTEXITCODE -ne 0) {
    throw "Panorama JavaScript syntax validation failed"
}

$luaPath = Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua"
$lua = Get-Content -LiteralPath $luaPath -Raw
$requiredLuaPatterns = @(
    'RegisterListener\("rpg_start_battle"',
    'RegisterListener\("rpg_request_battle_state"',
    'SetCustomGameForceHero\(PLAYER_PLACEHOLDER_HERO\)',
    'local HERO_LEVEL = 30',
    'npc_dota_hero_sven',
    'npc_dota_hero_lina',
    'npc_dota_hero_dazzle',
    'npc_dota_hero_axe',
    'npc_dota_hero_lion',
    'npc_dota_hero_crystal_maiden',
    'SetFogOfWarDisabled\(true\)',
    'SetUnseenFogOfWarEnabled\(false\)',
    'SetHeroRespawnEnabled\(false\)',
    'SetRespawnsDisabled\(true\)',
    'SetExecuteOrderFilter',
    'issuerPlayerId >= 0',
    'MoveToTargetToAttack\(target\)',
    'ABILITY_TYPE_ULTIMATE',
    'enemy_below = true',
    'self_below = true',
    'ally_below = true',
    'enemy_in_range = true',
    'enemy_highest_hp = true',
    'enemy_lowest_hp = true',
    'enemy_nearest = true',
    'enemy_farthest = true',
    'enemy_has_effect = true',
    'enemy_lacks_effect = true',
    'enemy_channeling = true',
    'magic_immune = true',
    'stunned = true',
    'silenced = true',
    'rooted = true',
    'self\.heroRules',
    'teamIndex = index',
    'heroPrefix = string\.format\("%s_hero_%d"',
    'UnitHasEffect',
    'IsEnemyWithinActionRange',
    'Script_GetAttackRange',
    'IsDebuffImmune',
    'IsMagicImmune',
    'IsStunned',
    'IsSilenced',
    'IsRooted',
    'IsChanneling',
    'ClampThreshold',
    '_threshold_',
    '_effect_',
    'Vector\(-1100, -650, 128\)',
    'Vector\(1100, 650, 128\)',
    'DOTA_UNIT_ORDER_CAST_TARGET',
    'DOTA_UNIT_ORDER_CAST_POSITION',
    'DOTA_UNIT_ORDER_CAST_NO_TARGET',
    'GameRules:SetGameWinner\(winnerTeam\)'
)

foreach ($pattern in $requiredLuaPatterns) {
    if ($lua -notmatch $pattern) {
        throw "Lua implementation is missing required behavior: $pattern"
    }
}

$javascript = Get-Content -LiteralPath $javascriptPath -Raw
$hudLayout = Get-Content -LiteralPath $hudPath -Raw
foreach ($eventName in @("rpg_start_battle", "rpg_request_battle_state", "rpg_battle_state")) {
    if ($javascript -notmatch [regex]::Escape($eventName)) {
        throw "Panorama JavaScript is missing event wiring: $eventName"
    }
}

$conditionSource = $javascript + "`n" + $hudLayout
foreach ($conditionName in @(
    '"always"',
    '"enemy_below"',
    '"self_below"',
    '"ally_below"',
    '"enemy_in_range"',
    '"enemy_highest_hp"',
    '"enemy_lowest_hp"',
    '"enemy_nearest"',
    '"enemy_farthest"',
    '"enemy_has_effect"',
    '"enemy_lacks_effect"',
    '"enemy_channeling"'
)) {
    if ($conditionSource -notmatch [regex]::Escape($conditionName)) {
        throw "Panorama UI is missing condition: $conditionName"
    }
}

foreach ($snippetPattern in @('name="RpgConditionEditor"', 'id="ConditionSelect"', 'id="ConditionMenu"', 'id="EffectSelect"', 'id="EffectMenu"', 'id="AlwaysOption"', 'id="EnemyInRangeOption"', 'id="EnemyHighestHpOption"', 'id="EnemyLowestHpOption"', 'id="EnemyNearestOption"', 'id="EnemyFarthestOption"', 'id="EnemyHasEffectOption"', 'id="EnemyLacksEffectOption"', 'id="EnemyChannelingOption"', 'BLoadLayoutSnippet("RpgConditionEditor")', 'toggleEditorMenu', 'chooseCondition', 'chooseEffect')) {
    if ($conditionSource -notmatch [regex]::Escape($snippetPattern)) {
        throw "Panorama UI is missing declarative dropdown behavior: $snippetPattern"
    }
}

foreach ($thresholdPattern in @("ThresholdEntry", "clampThreshold", '"_threshold_"')) {
    if ($javascript -notmatch [regex]::Escape($thresholdPattern)) {
        throw "Panorama JavaScript is missing configurable threshold behavior: $thresholdPattern"
    }
}

foreach ($heroPattern in @('id="RadiantHero1"', 'id="RadiantHero2"', 'id="RadiantHero3"', 'id="DireHero1"', 'id="DireHero2"', 'id="DireHero3"', 'buildHeroRuleSets', 'selectedHeroIndex', 'selectHero', 'wireHeroPortraits', '"_hero_"', '"_effect_"')) {
    if ($conditionSource -notmatch [regex]::Escape($heroPattern)) {
        throw "Panorama UI is missing per-hero rule behavior: $heroPattern"
    }
}

foreach ($effectName in @('"magic_immune"', '"stunned"', '"silenced"', '"rooted"')) {
    if ($conditionSource -notmatch [regex]::Escape($effectName)) {
        throw "Panorama UI is missing effect selector: $effectName"
    }
}

$addonInfoPath = Join-Path $repoRoot "game\dota_addons\dota2_rpg\addoninfo.txt"
$addonInfo = Get-Content -LiteralPath $addonInfoPath -Raw
if ($addonInfo -notmatch '"DrawCustomTeamHeroesOnMinimap"\s+"1"') {
    throw "addoninfo.txt must draw custom team heroes on the minimap"
}

$minimapPath = Join-Path $repoRoot "content\dota_addons\dota2_rpg\materials\overviews\dota2_rpg_demo.png"
Add-Type -AssemblyName System.Drawing
$minimap = [System.Drawing.Bitmap]::new($minimapPath)
try {
    if ($minimap.Width -ne 1024 -or $minimap.Height -ne 1024) {
        throw "The minimap must be 1024 by 1024 pixels"
    }

    $sampledColors = [System.Collections.Generic.HashSet[int]]::new()
    for ($x = 8; $x -lt $minimap.Width; $x += 16) {
        for ($y = 8; $y -lt $minimap.Height; $y += 16) {
            [void]$sampledColors.Add($minimap.GetPixel($x, $y).ToArgb())
        }
    }
    if ($sampledColors.Count -lt 8) {
        throw "The minimap does not contain enough visual contrast"
    }
}
finally {
    $minimap.Dispose()
}

$overviewPath = Join-Path $repoRoot "game\dota_addons\dota2_rpg\resource\overviews\dota2_rpg_demo.txt"
$overview = Get-Content -LiteralPath $overviewPath -Raw
foreach ($pattern in @('materials/overviews/dota2_rpg_demo.vmat', 'pos_x\s+-8192', 'pos_y\s+8192', 'scale\s+16\.000')) {
    if ($overview -notmatch $pattern) {
        throw "The minimap overview is missing required setting: $pattern"
    }
}

$mapPath = Join-Path $repoRoot "content\dota_addons\dota2_rpg\maps\dota2_rpg_demo.vmap"
$mapHeader = [System.IO.File]::ReadAllBytes($mapPath)[0..31]
$mapHeaderText = [System.Text.Encoding]::ASCII.GetString($mapHeader)
if ($mapHeaderText -notmatch "dmx encoding binary") {
    throw "The VMAP source does not have a valid Source 2 DMX header"
}

$dmxConverter = Join-Path $DotaPath "game\bin\win64\dmxconvert.exe"
if (-not (Test-Path -LiteralPath $dmxConverter)) {
    throw "dmxconvert.exe was not found at $dmxConverter"
}

$temporaryMap = Join-Path ([System.IO.Path]::GetTempPath()) ("dota2_rpg_verify_{0}.vmap" -f [guid]::NewGuid().ToString("N"))
try {
    & $dmxConverter -i $mapPath -o $temporaryMap -oe keyvalues2 -of vmap | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to convert the VMAP for structural verification"
    }

    $mapText = Get-Content -LiteralPath $temporaryMap -Raw
    if ($mapText -notmatch '"origin"\s+"vector3"\s+"-8192 -8192 128"') {
        throw "The terrain grid must start at -8192 -8192 128"
    }
    if ($mapText -notmatch '"gridWidth"\s+"int"\s+"64"' -or $mapText -notmatch '"gridHeight"\s+"int"\s+"64"') {
        throw "The terrain grid must be 64 by 64 cells"
    }

    $flatArrayRequirements = @{
        cellsHidden = 4096
        verticesHeight = 4225
        verticesWater = 4225
        objectConfiguration = 66049
    }

    foreach ($entry in $flatArrayRequirements.GetEnumerator()) {
        $arrayMatch = [regex]::Match(
            $mapText,
            '"' + $entry.Key + '"\s+"(?:int|bool)_array"\s*\[(.*?)\]',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if (-not $arrayMatch.Success) {
            throw "The terrain grid is missing $($entry.Key)"
        }

        $values = [regex]::Matches($arrayMatch.Groups[1].Value, '"?(-?\d+)"?')
        if ($values.Count -ne $entry.Value) {
            throw "$($entry.Key) must contain $($entry.Value) entries, found $($values.Count)"
        }
        if ($values | Where-Object { $_.Groups[1].Value -ne "0" } | Select-Object -First 1) {
            throw "$($entry.Key) must contain only zero values"
        }
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryMap) {
        Remove-Item -LiteralPath $temporaryMap -Force
    }
}

Write-Host "PASS: per-hero 3v3 rules, advanced conditions, no-respawn battle flow, minimap contrast, Panorama wiring, and the 64x64 flat VMAP are valid."
