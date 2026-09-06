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
    "content\dota_addons\dota2_rpg\panorama\scripts\custom_game\panorama_rule_sync.js",
    "content\dota_addons\dota2_rpg\panorama\styles\custom_game\rpg_demo_hud.css",
    "game\dota_addons\dota2_rpg\addoninfo.txt",
    "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua",
    "game\dota_addons\dota2_rpg\scripts\vscripts\data\progression_data.lua",
    "game\dota_addons\dota2_rpg\scripts\vscripts\patches\recruitment_patch.lua",
    "game\dota_addons\dota2_rpg\scripts\vscripts\patches\progression_patch.lua",
    "game\dota_addons\dota2_rpg\scripts\vscripts\patches\enemy_items_patch.lua",
    "game\dota_addons\dota2_rpg\scripts\vscripts\battle\unit_helpers.lua",
    "game\dota_addons\dota2_rpg\scripts\npc\npc_items_custom.txt",
    "game\dota_addons\dota2_rpg\scripts\vscripts\items.lua",
    "game\dota_addons\dota2_rpg\resource\addon_english.txt",
    "game\dota_addons\dota2_rpg\resource\addon_schinese.txt",
    "scripts\generate-minimap.ps1",
    "tests\panorama-save.test.js",
    "tests\shop-state.test.lua",
    "tests\precache-battlefield.test.lua"
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
& node --check (Join-Path $repoRoot "content\dota_addons\dota2_rpg\panorama\scripts\custom_game\panorama_rule_sync.js")
if ($LASTEXITCODE -ne 0) {
    throw "Panorama rule sync JavaScript syntax validation failed"
}
& node (Join-Path $repoRoot "tests\panorama-save.test.js")
if ($LASTEXITCODE -ne 0) {
    throw "Panorama save-state regression test failed"
}

# --- Lua 模块化架构检查（TacticEngine / BattleManager / DataLoader / 主入口） ---
$luaChecks = @(
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua";
       Patterns = @(
           'pcall\(require, .battle\.unit_helpers.\)',
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
           'local SHOP_REFRESH_COST = 20',
           'local SHOP_BENCH_SLOT_COST = 200',
           'local BENCH_SLOT_MAX = 5',
           'local LINEUP_MAX = 5',
           'self\.currentLevelId',
           'RollShop',
           'ProgressionData',
           'InitializeRecruitmentState',
           'freeRecruitChoices',
           'AwardStageXp',
           'CalculateTimeBonus',
           'runComplete',
           'isFinalWin',
           'SCROLL_LIMIT_PER_STAGE',
           'tactic_bridge',
           'battle.unit_helpers',
           'SetUseUniversalShopMode\(true\)',
           'SetCanSellAnywhere',
           'npc_items_custom.txt',
           'pcall\(require, .items.\)',
           'item_rpg_scroll_low',
           'dota_item_purchased',
           'IsNativeItemShopOrder',
           'GetGoldBalance',
           'rpg_item_equip',
           'rpg_item_unequip',
           'StashAddItem',
           'Vector\(-650, -420, 128\)',
           'Vector\(650, 420, 128\)',
           'SetAcquisitionRange\(BATTLE_ACQUISITION_RANGE\)'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\battle\unit_helpers.lua";
       Patterns = @(
           'function UnitHelpers.IsValidUnit',
           'function UnitHelpers.HealthPercent',
           'function UnitHelpers.ManaPercent',
           'return UnitHelpers'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\tactics\rule_service.lua";
       Patterns = @(
           'InstallEventListener',
           'rpg_update_rule',
           'get_hero_key',
           'find_roster_hero',
           'target_filters',
           'target_priorities',
           'use_conditions'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\tactics\tactic_bridge.lua";
       Patterns = @(
           'RuleService.new',
           'InstallEventListener',
           'get_hero_key',
           'is_action_allowed_for_hero',
           'allow_approach',
           'getRules'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\data\progression_data.lua";
       Patterns = @(
           'INITIAL_GOLD = 500',
           'TIME_BONUS_CAP = 0.10',
           'BENCH_XP_RATE = 0.50',
           'XP_TO_LEVEL',
           'STAGE_XP',
           'RECRUIT_BANDS',
           'PriceForLevel'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\patches\recruitment_patch.lua";
       Patterns = @(
           'freeRecruitChoices',
           'RollRecruitLevel',
           'PriceFor',
           'OnShopBuy',
           'SpendGold'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\patches\progression_patch.lua";
       Patterns = @(
           'AddXpToHero',
           'AwardStageXp',
           'XpNeededForNextLevel',
           'CalculateTimeBonus'
       ) },
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\patches\enemy_items_patch.lua";
       Patterns = @(
           'EquipConfiguredItems',
           'AddItemByName',
           'orderedValues'
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

# --- 进度与敌方配置静态契约 ---
$levelsText = Get-Content -LiteralPath (Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\data\levels.kv") -Raw
if ($levelsText -match '"time_bonus_cap"\s+"0\.25"') {
    throw "levels.kv must use the 10 percent time bonus cap"
}
foreach ($oldCondition in @('enemy_exists', 'ally_exists', 'self_hp_below')) {
    if ($levelsText -match [regex]::Escape($oldCondition)) {
        throw "levels.kv contains removed legacy condition: $oldCondition"
    }
}
foreach ($heroStage in @(@(5, 8), @(10, 14), @(15, 19), @(20, 24), @(25, 28), @(30, 30))) {
    $stage = $heroStage[0]
    $expected = $heroStage[1]
    $chapterMatch = [regex]::Match($levelsText, '(?s)"ch' + $stage.ToString('00') + '".*?(?=\n\t"ch\d+"\n\{|\z)')
    if (-not $chapterMatch.Success -or $chapterMatch.Value -notmatch ('"level"\s+"' + $expected + '"')) {
        throw "hero level configuration for ch$($stage.ToString('00')) must include level $expected"
    }
}

# --- Panorama 事件与新系统接线 ---
$javascript = Get-Content -LiteralPath $javascriptPath -Raw
$ruleSyncJavascript = Get-Content -LiteralPath (Join-Path $repoRoot "content\dota_addons\dota2_rpg\panorama\scripts\custom_game\panorama_rule_sync.js") -Raw
$hudLayout = Get-Content -LiteralPath $hudPath -Raw
$gameModeText = Get-Content -LiteralPath (Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua") -Raw
foreach ($eventName in @("rpg_start_battle", "rpg_request_battle_state", "rpg_battle_state", "rpg_settlement", "rpg_shop_buy", "rpg_shop_refresh", "rpg_bench_buy", "rpg_lineup_set", "rpg_scroll_buy", "rpg_scroll_use", "rpg_item_equip", "rpg_item_unequip", "rpg_update_rule")) {
    $combined = $javascript + "`n" + $ruleSyncJavascript + "`n" + $gameModeText
    if ($combined -notmatch [regex]::Escape($eventName)) {
        throw "Missing event wiring: $eventName"
    }
}

$conditionSource = $javascript + "`n" + $ruleSyncJavascript + "`n" + $hudLayout
$hudXml = [xml]$hudLayout
$expectedConditionValues = @(
    "always",
    "self_hp_pct_lte",
    "self_mana_pct_gte",
    "alive_enemy_count_gte",
    "elapsed_gte",
    "self_recently_damaged",
    "any_ally_recently_damaged",
    "dead_ally_count_gte"
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

# 金币已改走 Dota 原版 HUD 钱包，普通装备走原版商店，项目面板只保留双卷轴与转交。
if ($javascript -match 'item_catalog|rpg_item_buy_equip|rpg_item_buy|rpg_item_sell' -or $hudLayout -match 'ItemCatalogList') {
    throw "Custom ordinary-item catalog/purchase controls must remain removed"
}
$scrollItemText = Get-Content -LiteralPath (Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\npc\npc_items_custom.txt") -Raw
if ($scrollItemText -match '"ItemPurchasable"\s+"1"') {
    throw "project scrolls must not be natively purchasable; panel stock limits are server-authoritative"
}
foreach ($nativeShopPattern in @('SetUseUniversalShopMode', 'SetCanSellAnywhere', 'dota_item_purchased', 'IsNativeItemShopOrder', 'GetGoldBalance', 'NativeShopHint', 'ScrollShopList', 'RpgRuleSync', 'rpg_update_rule', 'NATIVE_STASH_FIRST_SLOT', 'NATIVE_STASH_LAST_SLOT', 'NormalizeNativeStashItems', 'MAX_STASH_SLOTS', 'BindEquipmentCarrierToPlayer', 'RoutePendingNativePurchases', 'rpg_native_purchase_target')) {
    if (($javascript + "`n" + $ruleSyncJavascript + "`n" + $hudLayout + "`n" + $gameModeText) -notmatch [regex]::Escape($nativeShopPattern)) {
        throw "Native shop / scroll-only wiring is missing: $nativeShopPattern"
    }
}

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
    'self_hp_pct_lte:',
    'self_mana_pct_gte:',
    'alive_enemy_count_gte:',
    'elapsed_gte:',
    'self_recently_damaged:',
    'any_ally_recently_damaged:',
    'dead_ally_count_gte:'
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

foreach ($thresholdPattern in @("ThresholdEntry", "clampValue", "putCondition")) {
    if (($javascript + "`n" + $ruleSyncJavascript) -notmatch [regex]::Escape($thresholdPattern)) {
        throw "Panorama JavaScript is missing configurable value behavior: $thresholdPattern"
    }
}

foreach ($shopPattern in @('id="ShopOffer"', 'id="RefreshShopButton"', 'id="RefreshShopLabel"', 'id="BenchBuyButton"', 'id="BenchBuyLabel"', 'id="LineupStrip"', 'id="NativeShopHint"', 'id="ScrollShopList"', 'renderShop', 'renderLineupStrip', 'renderRadiantHeroStrip', 'localizeHeroName', 'updateShopEconomyLabels', 'selectedHeroIndex', 'selectHero', 'shopState')) {
    if ($conditionSource -notmatch [regex]::Escape($shopPattern)) {
        throw "Panorama UI is missing shop/lineup behavior: $shopPattern"
    }
}

$recruitmentPatchText = Get-Content -LiteralPath (Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\vscripts\patches\recruitment_patch.lua") -Raw
foreach ($shopStatePattern in @(
    'ProgressionData\.INITIAL_GOLD',
    'InitializeRecruitmentState',
    'freeRecruitChoices',
    'local heroName = pool\[math\.random\(#pool\)\]',
    'for _, owned in ipairs\(self\.ownedHeroes\) do',
    'ownedSet\[owned\] = true',
    'self:SpendGold\(chargedPrice\)',
    'self:RespawnPlayerRoster\(\)'
)) {
    if (($gameModeText + "`n" + $recruitmentPatchText) -notmatch $shopStatePattern) {
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

foreach ($forcedPattern in @('dota2_rpg_force_column', 'forced: true', 'ForceToggle', 'toggleForced', 'approach', 'allow_approach', 'dota2_rpg_force_enabled', 'dota2_rpg_force_disabled')) {
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
