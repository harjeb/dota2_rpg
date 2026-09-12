param(
    [string]$DotaPath = "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installScriptText = Get-Content -LiteralPath (Join-Path $repoRoot "scripts\install-addon.ps1") -Raw
$compileScriptText = Get-Content -LiteralPath (Join-Path $repoRoot "tests\compile-vmap.ps1") -Raw
if (($installScriptText -notmatch 'Wrote .*dota2_rpg_demo') -or ($compileScriptText -notmatch 'did not confirm a successful VPK write')) {
    throw "Deployment scripts must verify a successful non-empty VPK write"
}
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
    "tests\shop-transition.test.lua",
    "tests\runtime-log.test.lua",
    "tests\precache-battlefield.test.lua",
    "tests\compile-vmap.ps1",
    "tests\vmap.test.py",
    "tests\vendor\datamodel.py"
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
[xml](Get-Content -LiteralPath $hudPath -Raw -Encoding UTF8) | Out-Null

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
           'StagePrecache\.Startup\(context, levels\)',
           'AwaitEnemyResources',
           'PrecacheUnitByNameAsync',
           'PrecacheItemByNameAsync',
           'SetFogOfWarDisabled\(true\)',
           'SetUnseenFogOfWarEnabled\(false\)',
           'SetHeroRespawnEnabled\(true\)',
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
           'BATTLEFIELD_HALF_WIDTH = 1200',
           'BATTLEFIELD_HALF_HEIGHT = 675',
           'Vector\(-720, -220, 128\)',
           'Vector\(720, 220, 128\)',
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
    @{ File = "game\dota_addons\dota2_rpg\scripts\vscripts\battle\stage_precache.lua";
       Patterns = @('function M\.Startup', 'function self:Request', 'function self:Prefetch', 'function self:IsReady') },
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
$hudLayout = Get-Content -LiteralPath $hudPath -Raw -Encoding UTF8
$gameModeText = Get-Content -LiteralPath (Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\vscripts\addon_game_mode.lua") -Raw
foreach ($eventName in @("rpg_start_battle", "rpg_request_battle_state", "rpg_battle_state", "rpg_settlement", "rpg_shop_buy", "rpg_shop_refresh", "rpg_bench_buy", "rpg_lineup_set", "rpg_scroll_buy", "rpg_scroll_use", "rpg_item_equip", "rpg_item_unequip", "rpg_update_rule")) {
    $combined = $javascript + "`n" + $ruleSyncJavascript + "`n" + $gameModeText
    if ($combined -notmatch [regex]::Escape($eventName)) {
        throw "Missing event wiring: $eventName"
    }
}

$catalogJavascript = Get-Content -LiteralPath (Join-Path $repoRoot "content\dota_addons\dota2_rpg\panorama\scripts\custom_game\condition_catalog.js") -Raw
$conditionSource = $javascript + "`n" + $ruleSyncJavascript + "`n" + $hudLayout + "`n" + $catalogJavascript
$hudXml = [xml]$hudLayout
foreach ($removed in @('RpgConditionEditor', 'ConditionSelect', 'ConditionMenu', 'ThresholdEntry', 'TargetAttrSelect', 'TargetSideSelect', 'ForceColumn')) {
    if ($hudLayout -match [regex]::Escape($removed)) { throw "Outer rule editor must remain removed: $removed" }
}
if ($javascript -match 'createConditionEditor|syncThreshold|syncAllRuleInputs|createForceToggle') {
    throw "Removed outer inputs must not be created or synchronized"
}

# 指挥官（小精灵）无敌必须常驻：切关/重开时摘掉它，准备阶段残留的敌方召唤物
# （蛇棒、地狱火）就会把它打死，而它是钱包、库存与转交的载体。
if ($gameModeText -match 'RemoveModifierByName\("modifier_invulnerable"\)') {
    throw "Commander invulnerability must stay permanent across phases"
}
if ($gameModeText -notmatch 'EnsureCommanderProtected') {
    throw "Commander protection helper is missing"
}

# 普通装备通过原版商店购买；项目面板提供原生出售包装、双卷轴与转交。
if ($javascript -match 'item_catalog|rpg_item_buy_equip|rpg_item_buy' -or $hudLayout -match 'ItemCatalogList') {
    throw "Custom ordinary-item catalog/purchase controls must remain removed"
}
$scrollItemText = Get-Content -LiteralPath (Join-Path $repoRoot "game\dota_addons\dota2_rpg\scripts\npc\npc_items_custom.txt") -Raw
if ($scrollItemText -match '"ItemPurchasable"\s+"1"') {
    throw "project scrolls must not be natively purchasable; panel stock limits are server-authoritative"
}
# 肉山盾（不朽盾）未拾取时的消失时间被拉长到 999 分钟；普通模式与 tooltip 必须同步，
# 且不能顺手改掉加速模式的原生 240 秒。
if ($scrollItemText -notmatch '"disappear_time"\s+"59940\.0"') {
    throw "Aegis disappear_time must be 59940.0 seconds (999 minutes)"
}
if ($scrollItemText -notmatch '"disappear_time_minutes_tooltip"\s+"999"') {
    throw "Aegis disappear_time_minutes_tooltip must match disappear_time (999 minutes)"
}
if ($scrollItemText -match '"disappear_time_turbo"') {
    throw "Aegis turbo disappear time must keep its native value"
}
foreach ($nativeShopPattern in @('SetUseUniversalShopMode', 'SetCanSellAnywhere', 'dota_item_purchased', 'IsNativeItemShopOrder', 'GetGoldBalance', 'ReadNativeGold', 'EnsureGoldWalletInitialized', 'goldWalletInitialized', 'CanAffordNativePurchase', 'GetPendingNativePurchaseReservation', 'RevertUnpaidNativePurchase', 'SyncRosterAbilities', 'NativeShopHint', 'ScrollShopList', 'RpgRuleSync', 'rpg_update_rule', 'NATIVE_STASH_FIRST_SLOT', 'NATIVE_STASH_LAST_SLOT', 'NormalizeNativeStashItems', 'NEUTRAL_ITEM_SLOT', 'stock_neutral_text', 'BindEquipmentCarrierToPlayer', 'RoutePendingNativePurchases', 'rpg_native_purchase_target', 'rpg_item_sell', 'OnItemSell', 'ItemSellNotice')) {
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
        Where-Object { -not $_.EndsWith('_') } | # Dynamic prefixes are expanded and checked by condition-ui-v2.test.js.
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
    'always',
    'self_hp_pct_lte',
    'self_mana_pct_gte',
    'alive_enemy_count_gte',
    'elapsed_gte',
    'self_recently_damaged',
    'any_ally_recently_damaged'
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
    'target_filters',
    'target_priorities'
)) {
    if ($conditionSource -notmatch [regex]::Escape($targetName)) {
        throw "Panorama UI is missing compositional target selector: $targetName"
    }
}

foreach ($snippetPattern in @('RuleSettings', 'RpgConditionCatalog.open', 'V2Team', 'use_conditions', 'target_filters', 'target_priorities')) {
    if ($conditionSource -notmatch [regex]::Escape($snippetPattern)) {
        throw "Panorama UI is missing declarative dropdown behavior: $snippetPattern"
    }
}

foreach ($thresholdPattern in @("putCondition", "use_condition", "target_filter")) {
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
    'local heroName = pool\[ShopRandomInt\(1, #pool\)\]',
    'return RandomInt\(minimum, maximum\)',
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

foreach ($forcedPattern in @('V2ApproachSelect', 'approach_chase', 'approach_wait', 'draft.forced', 'allow_approach')) {
    if ($conditionSource -notmatch [regex]::Escape($forcedPattern)) {
        throw "Panorama UI is missing forced execution toggle behavior: $forcedPattern"
    }
}

foreach ($effectName in @('"is_spell_immune"', '"is_stunned"', '"is_silenced"', '"is_rooted"')) {
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

# Parse binary-v9 data directly, including exact brush vertex bounds, material
# indices, native prop transforms, scene attachment, and overlay synchronization.
& python (Join-Path $repoRoot "tests\opening-balance.test.py")
if ($LASTEXITCODE -ne 0) {
    throw "Opening encounter balance contracts failed"
}

& python (Join-Path $repoRoot "tests\vmap.test.py")
if ($LASTEXITCODE -ne 0) {
    throw "Offline structured VMAP regression tests failed"
}

$dmxConverter = Join-Path $DotaPath "game\bin\win64\dmxconvert.exe"
if (-not (Test-Path -LiteralPath $dmxConverter)) {
    Write-Warning "dmxconvert.exe unavailable: engine conversion skipped. Offline checks passed; compilation and in-engine appearance/navigation remain unverified. Run tests\compile-vmap.ps1 on a Dota Workshop Tools installation."
    Write-Host "PASS: addon static checks and offline binary-v9 VMAP contracts (no engine compilation performed)."
    return
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

    # The combat arena is authored in the VMAP rather than relying only on Lua.
    # Parse complete CMapEntity blocks so a future map edit cannot silently detach
    # a target name from its class, transform, or brush material.
    function Get-VmapBlocks([string]$source, [string]$elementType) {
        $blocks = @()
        $elementMatches = [regex]::Matches($source, '"' + [regex]::Escape($elementType) + '"\s*\{')
        foreach ($match in $elementMatches) {
            $open = $source.IndexOf('{', $match.Index)
            $depth = 0
            $end = -1
            for ($index = $open; $index -lt $source.Length; $index++) {
                if ($source[$index] -eq '{') {
                    $depth++
                }
                elseif ($source[$index] -eq '}') {
                    $depth--
                    if ($depth -eq 0) {
                        $end = $index
                        break
                    }
                }
            }
            if ($end -lt 0) {
                throw "Unclosed $elementType block in VMAP"
            }
            $blocks += $source.Substring($match.Index, $end - $match.Index + 1)
        }
        return $blocks
    }

    $mapEntities = @(Get-VmapBlocks $mapText "CMapEntity")
    $mapMeshes = @(Get-VmapBlocks $mapText "CMapMesh")
    $markerOrigins = @{
        rpg_arena_min = "-1200 -675 128"
        rpg_arena_max = "1200 675 128"
        rpg_arena_center = "0 0 128"
    }
    foreach ($marker in $markerOrigins.GetEnumerator()) {
        $targetPattern = '"targetname"\s+"string"\s+"' + [regex]::Escape($marker.Key) + '"'
        $entityMatches = @($mapEntities | Where-Object { $_ -match $targetPattern })
        if ($entityMatches.Count -ne 1) {
            throw "VMAP must contain exactly one $($marker.Key) marker"
        }
        $entity = $entityMatches[0]
        if ($entity -notmatch '"classname"\s+"string"\s+"info_target"' -or
            $entity -notmatch ('"origin"\s+"vector3"\s+"' + [regex]::Escape($marker.Value) + '"')) {
            throw "$($marker.Key) must be an info_target at $($marker.Value)"
        }
    }

    $wallGeometry = @{
        rpg_arena_wall_north = @("0 691 384", '1\.59375\s+0\.03125\s+2')
        rpg_arena_wall_south = @("0 -691 384", '1\.59375\s+0\.03125\s+2')
        rpg_arena_wall_east = @("1216 0 384", '0\.02083333[0-9]*\s+1\.349609375\s+2')
        rpg_arena_wall_west = @("-1216 0 384", '0\.02083333[0-9]*\s+1\.349609375\s+2')
    }
    foreach ($wallName in $wallGeometry.Keys) {
        $targetPattern = '"targetname"\s+"string"\s+"' + $wallName + '"'
        $entityMatches = @($mapEntities | Where-Object { $_ -match $targetPattern })
        if ($entityMatches.Count -ne 1) {
            throw "VMAP must contain exactly one permanent wall: $wallName"
        }
        $wall = $entityMatches[0]
        foreach ($required in @(
            '"classname"\s+"string"\s+"func_brush"',
            '"Solidity"\s+"string"\s+"2"',
            '"AlwaysSolidIgnoreNav"\s+"string"\s+"0"',
            'materials/tools/toolsclip\.vmat'
        )) {
            if ($wall -notmatch $required) {
                throw "$wallName is missing required permanent-wall data: $required"
            }
        }
        $geometry = $wallGeometry[$wallName]
        if ($wall -notmatch ('"origin"\s+"vector3"\s+"' + [regex]::Escape($geometry[0]) + '"') -or
            $wall -notmatch ('"scales"\s+"vector3"\s+"' + $geometry[1] + '"')) {
            throw "$wallName does not retain its 2400x1350 boundary transform"
        }
    }

    if ($mapEntities | Where-Object { $_ -match '"targetname"\s+"string"\s+"rpg_mid_gate_visual"' }) {
        throw "The visible middle gate brush must be removed; runtime native trees provide the divider"
    }
    if ($mapMeshes | Where-Object { $_ -match 'materials/dev/primary_white\.vmat' }) {
        throw "Arena collision brushes must use invisible tool materials, not visible developer material"
    }
    $rockEntities = @($mapEntities | Where-Object { $_ -match '"targetname"\s+"string"\s+"rpg_arena_rock_(north|south|east|west)_\d+"' })
    if ($rockEntities.Count -ne 28) {
        throw "VMAP must retain 28 native perimeter rock props"
    }
    foreach ($rock in $rockEntities) {
        if ($rock -notmatch '"classname"\s+"string"\s+"prop_static"' -or
            $rock -notmatch '"model"\s+"string"\s+"models/props_rock/riveredge_rock_wall00[23]a\.vmdl"' -or
            $rock -notmatch '"solid"\s+"string"\s+"0"') {
            throw "Perimeter scenery must use verified native rock models with collision owned by clip brushes"
        }
    }

    if ($mapEntities | Where-Object { $_ -match '"targetname"\s+"string"\s+"rpg_mid_gate_nav"' }) {
        throw "Static middle brush must be removed; temporary trees own preparation navigation"
    }
    if ($mapMeshes.Count -ne 8) {
        throw "VMAP must contain only four perimeter wall meshes and four NONAV slabs"
    }

    # Four separately authored nonavclip slabs keep nav generation off each
    # outer edge; the fifth material occurrence is the map asset reference.
    $nonavGeometry = @{
        "0 691 128" = '1\.59375\s+0\.0625\s+0\.25'
        "0 -691 128" = '1\.59375\s+0\.0625\s+0\.25'
        "1200 0 128" = '0\.04166666[0-9]*\s+1\.349609375\s+0\.25'
        "-1200 0 128" = '0\.04166666[0-9]*\s+1\.349609375\s+0\.25'
    }
    foreach ($origin in $nonavGeometry.Keys) {
        $meshMatches = @($mapMeshes | Where-Object {
            $_ -match 'materials/tools/nonavclip\.vmat' -and
            $_ -match ('"origin"\s+"vector3"\s+"' + [regex]::Escape($origin) + '"') -and
            $_ -match ('"scales"\s+"vector3"\s+"' + $nonavGeometry[$origin] + '"')
        })
        if ($meshMatches.Count -ne 1) {
            throw "VMAP must retain exactly one NONAV edge slab at $origin"
        }
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryMap) {
        Remove-Item -LiteralPath $temporaryMap -Force
    }
}

Write-Host "PASS: modular TacticEngine/BattleManager/DataLoader, hero shop + lineup economy, unified levels, 20 data-driven levels, target selectors, forced/range modes, minimap contrast, Panorama wiring, the 64x64 terrain, and compact-arena VMAP contracts are valid."
