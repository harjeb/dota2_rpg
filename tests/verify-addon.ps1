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
    "scripts\generate-minimap.ps1",
    "tests\panorama-save.test.js",
    "tests\shop-state.test.lua",
    "tests\precache-battlefield.test.lua",
    "tests\fixtures\save-v1-zero-gold.json"
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
& node (Join-Path $repoRoot "tests\panorama-save.test.js")
if ($LASTEXITCODE -ne 0) {
    throw "Panorama save-state regression test failed"
}

# --- Lua 模块化架构检查（TacticEngine / BattleManager / DataLoader / 主入口） ---
$luaChecks = @(
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua";
       Patterns = @(
           'pcall\(require, .battle\.tactic_engine.\)',
           'pcall\(require, .battle\.battle_manager.\)',
           'pcall\(require, .data\.data_loader.\)',
           'RegisterListener\("rpg_start_battle"',
           'RegisterListener\("rpg_request_battle_state"',
           'RegisterListener\("rpg_select_level"',
           'RegisterListener\("rpg_shop_buy"',
           'RegisterListener\("rpg_lineup_set"',
           'SetCustomGameForceHero\(PLAYER_PLACEHOLDER_HERO\)',
           'local HERO_LEVEL = 30',
           'local BATTLE_ACQUISITION_RANGE = 4000',
           'seenUnits\[unitName\]',
           'SetFogOfWarDisabled\(true\)',
           'SetUnseenFogOfWarEnabled\(false\)',
           'SetHeroRespawnEnabled\(false\)',
           'SetRespawnsDisabled\(true\)',
           'issuerPlayerId < 0',
           'local SHOP_HERO_COST = 100',
           'local SHOP_REFRESH_COST = 20',
           'local SHOP_BENCH_SLOT_COST = 200',
           'local INITIAL_GOLD = 300',
           'local BENCH_SLOT_MAX = 5',
           'local LINEUP_MAX = 5',
           'self\.currentLevelId',
           'RollShop',
           'TIME_BONUS_CAP = 0.25',
           'DistributeXpPool',
           'RollRecruitLevel',
           'RollQuality',
           'SCROLL_LIMIT_PER_STAGE',
           'tactic_bridge',
           'battle.tactic_engine'
           'StashAddItem',
           'BuildItemPrices',
           'Vector\(-650, -420, 128\)',
           'Vector\(650, 420, 128\)',
           'SetAcquisitionRange\(BATTLE_ACQUISITION_RANGE\)'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\battle\tactic_engine.lua";
       Patterns = @(
           'always = true',
           'self_hp_below = true',
           'self_mp_above = true',
           'enemy_exists = true',
           'ally_exists = true',
           'enemy_count_ge = true',
           'battle_time_ge = true',
           'TARGET_METRICS = {',
           'hp_pct = true',
           'armor = true',
           'attack = true',
           'mr = true',
           'IsValidTarget',
           'GetTargetSide',
           'enemy_casting',
           'SelectSelectorTarget',
           'item_1 = true',
           'item_6 = true',
           'forcedRuleIndex',
           'forcedTargetIndex',
           'ClearForcedLock',
           'CountAlive',
           'IsChanneling',
           'rule\.enabled == false',
           '"_enabled_"',
           '"_target_"',
           '"_value_"',
           '"_forced_"'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\battle\battle_manager.lua";
       Patterns = @(
           'MoveToTargetToAttack\(target\)',
           'ABILITY_TYPE_ULTIMATE',
           'DOTA_UNIT_ORDER_CAST_TARGET',
           'DOTA_UNIT_ORDER_CAST_POSITION',
           'DOTA_UNIT_ORDER_CAST_NO_TARGET',
           'Script_GetAttackRange',
           'GetItemInSlot',
           'BATTLE_TIME_LIMIT'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\data\data_loader.lua";
       Patterns = @(
           'levels\.kv',
           'enemy_ai\.kv',
           'loot\.kv',
           'LoadKeyValues'
       ) }
)

foreach ($luaCheck in $luaChecks) {
    $modulePath = Join-Path $repoRoot $luaCheck.File
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Missing Lua module: $($luaCheck.File)"
    }
    $moduleText = Get-Content -LiteralPath $modulePath -Raw
    foreach ($pattern in $luaCheck.Patterns) {
        if ($moduleText -notmatch $pattern) {
            throw "Lua module $($luaCheck.File) is missing required behavior: $pattern"
        }
    }
}

# --- 数据表检查 ---
$dataChecks = @(
    @{ File = "game\dota_addons\dota2_rpg\scripts\data\levels.kv"; Required = 20 },
    @{ File = "game\dota_addons\dota2_rpg\scripts\data\heroes.kv"; Required = $null },
    @{ File = "game\dota_addons\dota2_rpg\scripts\data\enemy_ai.kv"; Required = $null },
    @{ File = "game\dota_addons\dota2_rpg\scripts\data\loot.kv"; Required = $null }
)
foreach ($dataCheck in $dataChecks) {
    $dataPath = Join-Path $repoRoot $dataCheck.File
    if (-not (Test-Path -LiteralPath $dataPath)) {
        throw "Missing data table: $($dataCheck.File)"
    }
    $dataText = Get-Content -LiteralPath $dataPath -Raw
    if ($dataCheck.Required -ne $null) {
        $levelMatches = [regex]::Matches($dataText, '"ch\d\d"')
        if ($levelMatches.Count -lt $dataCheck.Required) {
            throw "levels.kv must contain at least $($dataCheck.Required) levels, found $($levelMatches.Count)"
        }
    }
    elseif ($dataText.Length -lt 100) {
        throw "Data table looks empty: $($dataCheck.File)"
    }
}

# --- Panorama 事件与新系统接线 ---
$javascript = Get-Content -LiteralPath $javascriptPath -Raw
$hudLayout = Get-Content -LiteralPath $hudPath -Raw
$gameModeText = Get-Content -LiteralPath (Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua") -Raw
foreach ($eventName in @("rpg_start_battle", "rpg_request_battle_state", "rpg_battle_state", "rpg_settlement", "rpg_shop_buy", "rpg_shop_refresh", "rpg_bench_buy", "rpg_lineup_set")) {
    $combined = $javascript + "`n" + $gameModeText
    if ($combined -notmatch [regex]::Escape($eventName)) {
        throw "Missing event wiring: $eventName"
    }
}

$conditionSource = $javascript + "`n" + $hudLayout
$hudXml = [xml]$hudLayout
$expectedConditionValues = @(
    "always",
    "self_hp_below",
    "self_mp_above",
    "enemy_exists",
    "ally_exists",
    "enemy_count_ge",
    "battle_time_ge",
    "ally_under_attack",
    "ally_hit_count_ge",
    "ally_death_ge",
    "toggle_state_off"
)
$actualConditionValues = @(
    $hudXml.SelectNodes("//Panel[@id='ConditionMenu']//Button") |
        ForEach-Object { $_.GetAttribute("value") }
)
$conditionDifference = @(Compare-Object -ReferenceObject $expectedConditionValues -DifferenceObject $actualConditionValues)
if ($conditionDifference.Count -gt 0) {
    throw "Condition dropdown values must exactly match the conditions supported by Panorama JavaScript"
}

$expectedTargetAttrValues = @("hp", "hp_pct", "armor", "attack", "mr", "distance", "casting", "boss", "healer", "controlled")
$actualTargetAttrValues = @(
    $hudXml.SelectNodes("//Panel[@id='TargetAttrMenu']//Button") |
        ForEach-Object { $_.GetAttribute("value") }
)
$targetAttrDifference = @(Compare-Object -ReferenceObject $expectedTargetAttrValues -DifferenceObject $actualTargetAttrValues)
if ($targetAttrDifference.Count -gt 0) {
    throw "Target attribute dropdown values must exactly match the attributes supported by Panorama JavaScript"
}

$expectedTargetSideValues = @("enemy_highest", "enemy_lowest", "ally_highest", "ally_lowest", "nearest", "farthest", "self")
$actualTargetSideValues = @(
    $hudXml.SelectNodes("//Panel[@id='TargetSideMenu']//Button") |
        ForEach-Object { $_.GetAttribute("value") }
)
$targetSideDifference = @(Compare-Object -ReferenceObject $expectedTargetSideValues -DifferenceObject $actualTargetSideValues)
if ($targetSideDifference.Count -gt 0) {
    throw "Target side dropdown values must exactly match the sides supported by Panorama JavaScript"
}
if ($hudLayout -match "ConditionMenuColumn|TargetMenuColumn") {
    throw "Condition and target dropdowns must use the readable single-column layout"
}

# 金币已改走 Dota 原版 HUD 钱包，商店面板不再放置金币条

$localizationFiles = @(
    "game\dota_addons\dota2_rpg\resource\addon_english.txt",
    "game\dota_addons\dota2_rpg\resource\addon_schinese.txt"
)
$referencedTokens = @(
    [regex]::Matches($conditionSource, "#(dota2_rpg_[a-z0-9_]+)") |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)
foreach ($localizationFile in $localizationFiles) {
    $localizationText = Get-Content -LiteralPath (Join-Path $repoRoot $localizationFile) -Raw
    foreach ($token in $referencedTokens) {
        if ($localizationText -notmatch ('"' + [regex]::Escape($token) + '"')) {
            throw "Missing localization token $token in $localizationFile"
        }
    }
}

foreach ($conditionName in @(
    'always:',
    'self_hp_below:',
    'self_mp_above:',
    'enemy_exists:',
    'ally_exists:',
    'enemy_count_ge:',
    'battle_time_ge:'
)) {
    if ($conditionSource -notmatch [regex]::Escape($conditionName)) {
        throw "Panorama UI is missing condition: $conditionName"
    }
}

foreach ($targetName in @(
    'TARGET_ATTR_TOKENS',
    'TARGET_SIDE_TOKENS',
    'composeTarget',
    'decomposeTarget',
    'chooseTargetAttr',
    'chooseTargetSide'
)) {
    if ($conditionSource -notmatch [regex]::Escape($targetName)) {
        throw "Panorama UI is missing compositional target selector: $targetName"
    }
}

foreach ($snippetPattern in @('name="RpgConditionEditor"', 'id="ConditionSelect"', 'id="ConditionMenu"', 'id="EffectSelect"', 'id="EffectMenu"', 'id="TargetAttrSelect"', 'id="TargetAttrMenu"', 'id="TargetSideSelect"', 'id="TargetSideMenu"', 'BLoadLayoutSnippet("RpgConditionEditor")', 'toggleEditorMenu', 'chooseCondition', 'chooseTarget', 'chooseEffect')) {
    if ($conditionSource -notmatch [regex]::Escape($snippetPattern)) {
        throw "Panorama UI is missing declarative dropdown behavior: $snippetPattern"
    }
}

foreach ($thresholdPattern in @("ThresholdEntry", "clampValue", '"_value_"')) {
    if ($javascript -notmatch [regex]::Escape($thresholdPattern)) {
        throw "Panorama JavaScript is missing configurable value behavior: $thresholdPattern"
    }
}

foreach ($shopPattern in @('id="ShopOffer"', 'id="RefreshShopButton"', 'id="RefreshShopLabel"', 'id="BenchBuyButton"', 'id="BenchBuyLabel"', 'id="LineupStrip"', 'renderShop', 'renderLineupStrip', 'renderRadiantHeroStrip', 'localizeHeroName', 'updateShopEconomyLabels', 'selectedHeroIndex', 'selectHero', 'shopState', '"_hero_"', '_hero_')) {
    if ($conditionSource -notmatch [regex]::Escape($shopPattern)) {
        throw "Panorama UI is missing shop/lineup behavior: $shopPattern"
    }
}

foreach ($shopStatePattern in @(
    'self\.gold = self\.shopCosts\.initial_gold',
    'local heroName = pool\[math\.random\(#pool\)\]',
    'ReadPayloadList\(payload, "owned_text", "owned"\)',
    'ReadPayloadList\(payload, "lineup_text", "lineup"\)',
    'ownedSet\[owned\] = true'
)) {
    if ($gameModeText -notmatch $shopStatePattern) {
        throw "Lua shop state is missing regression protection: $shopStatePattern"
    }
}
if ($gameModeText -match 'pool\[math\.random\(#pool\)\]\.name' -or $gameModeText -match 'owned\[owned\] = true') {
    throw "Lua shop state contains the old string/object mismatch"
}
# 无存档设计：客户端不再读写 LocalStorage、不再发送存档同步
foreach ($forbiddenPattern in @(
    'LocalStorage',
    'rpg_save_sync',
    'owned_text: saveData',
    'lineup_text: saveData'
)) {
    if ($javascript -match $forbiddenPattern) {
        throw "Panorama still references removed save system: $forbiddenPattern"
    }
}
if ($javascript -match 'owned: saveData\.owned' -or $javascript -match 'lineup: saveData\.lineup') {
    throw "Panorama save sync still sends nested arrays"
}

foreach ($forcedPattern in @('dota2_rpg_force_column', 'forced: true', 'ForceToggle', 'toggleForced', '"_forced_"', 'dota2_rpg_force_enabled', 'dota2_rpg_force_disabled')) {
    if ($conditionSource -notmatch [regex]::Escape($forcedPattern)) {
        throw "Panorama UI is missing forced execution toggle behavior: $forcedPattern"
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

Write-Host "PASS: modular TacticEngine/BattleManager/DataLoader, hero shop + lineup economy, unified levels, 20 data-driven levels, target selectors, forced/range modes, minimap contrast, Panorama wiring, and the 64x64 flat VMAP are valid."
