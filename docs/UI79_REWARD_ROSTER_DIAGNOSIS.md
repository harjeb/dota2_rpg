# UI79 read-only reward / enemy-target diagnosis — 2026-09-14

Scope: investigate user reports only. No addon source edits, install, compilation, gameplay operations, commits or pushes. Other agent owns difficulty/reward/UI implementation (`dota2_rpg-3202`). New evidence bugs: **dota2_rpg-1cyf** (target roster), **dota2_rpg-huym** (neutral reward economy), both discovered-from that task. These remain open for implementation/clarification.

## Evidence identity

Live log: `C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota/console.8998798026.log`, Sep14, ends22:56:40. SHA256 `1f2b080cabb59e1608c9042cb3209e8b611d1f29ce42eba9ebcbef59465f0fa0`; byte-identical to existing `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-end-crash-kg198xk6/console.8998798026.log`. Line numbers below refer to this file.

At investigation time, installed and workspace `battle/campaign_loot.lua`, `issue_fixes/item_sales.lua`, and Panorama `rpg_demo_hud.js` match byte-for-byte. Whole `addon_game_mode.lua` differs, but its `BroadcastHeroInfo` and `AssembleLevelEnemies` methods match exactly. This establishes the relevant current installed source, not a retrospective guarantee of which bytes the already-running VM loaded. The loot and sale logs independently corroborate those paths.

## 1. “Enemy targets shows two, actually four”

### Confirmed live entities, not confirmed transmitted/received roster

Four-enemy starting chapters in this run: ch02, ch12, ch13, ch14. Other chapters have different starting counts; battle summons can add visible units.

| Chapter / setup time | Ready log lines | Ready entity IDs / names | All four alive at fight start |
|---|---|---|---|
| ch02 /22:30:59 |1800,1804,1808,1812; spawned4 at1813|738/747 ogre_mauler,772 centaur_khan,598 alpha_wolf|Setup explicitly logs alive=true for all four|
| ch12 /22:45:18 |18618,18623,18628,18633; spawned4 at18634|969 Lina,804 Lion,479 Tidehunter,620 Sven|21183–21186,22:47:11,t1055.27,alive=1|
| ch13 /22:47:33–34 |21546,21551,21556,21561; spawned4 at21562|842 Viper,866 Shadow Shaman,862 Bristleback,885 Razor|21721–21724,22:47:46,t1090.47,alive=1|
| ch14 /22:49:36 |23691,23696,23701,23706; spawned4 at23707|695 Gyrocopter,659 Warlock,684 Slardar,807 Luna|27205–27208,22:50:54,t1274.57,alive=1|

Retries also spawned four: ch13 at22077; ch14 at27626 and28366. The ch14 retry entity sets are100/496/334/557 and693/856/869/919. None of these spawn counts proves which screen the user saw.

**No `rpg_enemy_roster` or `rpg_hero_slots` payload/send/commit telemetry exists in this console.** “Wallet roster_before/after” is player recruitment bookkeeping, not enemy roster delivery. Therefore exact affected chapter, server wire roster count, client received identities, and packet loss cannot be recovered from this log. Do not label four server sends or two client receipts as measured facts.

### Confirmed reproducible UI defect

Paths below are under `content/dota_addons/dota2_rpg/panorama/scripts/custom_game/rpg_demo_hud.js` and `game/dota_addons/dota2_rpg/scripts/vscripts/`:

- `addon_game_mode.lua:4924–4970`, `BroadcastHeroInfo`: builds enemy roster from every valid registered opposing unit, including creeps; includes `{id,name,target_actor}`. Then independently publishes capabilities and `rpg_hero_slots` for each unit.
- HUD `onEnemyRoster:2043–2062` retains only name/entityIndex, **discarding the authoritative target_actor already supplied in the roster**. Signature also ignores target_actor.
- HUD `targetActors:169–181` requires a matching positional `heroSlots.dire_N`, target_actor, name and entity ID before offering a specified-enemy choice. Thus a complete roster alone is insufficient.
- Server roster is compacted with table.insert after validity filtering, whereas hero slots retain original team-array indices. A missing earlier native handle can shift the roster relative to the slots even when all messages arrive.
- `tactics/rule_snapshot.lua:58–64` already supplies chapter-qualified duplicate-safe identities. No reason to require ability/capability delivery just to select one of those targets.

Read-only Node stdin used the **actual** `tests/condition-ui-v2.test.js` exported HUD harness (no test files changed), loaded one authorized allied attack row and a four-enemy roster whose entries each include target_actor, opened F39 specified-enemy menu, and counted children excluding Clear:

```
all:     roster4 + dire slots1,2,3,4 -> targets4
missing: roster4 + dire slots1,2     -> targets2
sparse:  roster4 + dire slots1,2,4,5 -> targets2
```

This confirms the code-level failure mechanism, **not** that dropped slot events or vanished handles caused this particular live report. The sparse fixture models an invalid registered third unit omitted from a five-position source list; it is not asserted to have happened in the four-unit setup evidence above.

### Inspecting the other meanings of “enemy targets”

- F39 “指定敌方目标 / 选择当前敌方目标”: uses `targetActors`; affected by the above defect. Duplicates must remain distinct, not deduplicated by unit name.
- Action-reference condition picker (`actionHeroes:184–205`, e.g. elapsed time since enemy ability): also joins roster/slots but genuinely needs ability data. It needs missing capability/slot recovery, not fabricated abilities or borrowing another slot.
- There is no enemy-editing side panel in the current HUD layout; `onEnemyRoster` explicitly says “without an enemy editor.” Enemy slot data still supports allied condition references; developer-mode server permission does not imply a visible enemy editor here.
- DPS “敌方” and “目标”: `renderDamage:2083–2128` uses **damage snapshots**, not enemy-roster events. Its Targets area enumerates only victims damaged by the selected actor/source. `battle/damage_stats.lua:Record` only records positive accepted damage. Two damage targets out of four enemies can be correct and must not be “fixed” by adding undamaged targets to the damage breakdown.
- Spawned summons/illusions are not automatically all registered chapter target actors; a four-visible-vs-two-authored report requires identifying those units before changing inclusion policy.

### Minimal recommended fix and tests

Use the roster's own `{id,name,target_actor}` for specified-enemy options, independent of heroSlots; preserve generation authorization and chapter-qualified opaque identities, include target_actor in roster signature, and retain stale-choice fail-closed behavior. Keep specified-ally/action-reference paths separate. Avoid simply increasing limits: no two-target cap was found.

Extend `tests/condition-ui-v2.test.js` with full roster + no/partial/out-of-order enemy slots, numeric-key CEM object arrays, sparse original slot indices, duplicate names, same IDs/names with changed chapter actor, removed target/stale menu click, reconnect and stale generation. Existing F39 coverage around250–300 always supplies every enemy slot and misses the defect. Extend `tests/specified-enemy.test.lua` actual broadcast fixture with a missing native handle and verify entity/actor identities independently of positional gaps.

If diagnostics are added, log small roster revision/chapter/count/IDs/actors at send and commit plus picker count/rejection reason. Existing shop receipts are not roster receipts. Recover a wholly missing roster via revision/request rather than repeatedly publishing all ability payloads.

**Needed clarification:** Which chapter and which panel (F39 dropdown, action-reference picker, or DPS Targets), preparation or combat, and names of the two missing enemies? Without that, this reproducible defect is a strong candidate, not unique live attribution.

## 2. Chapter9 neutral reward worth200

### Exact live chain — confirmed

```
17493 22:43:48 [RPG][Loot] rolled level=ch09 count=1 items=item_pogo_stick
17494 22:43:48 [RPG][Loot] delivered level=ch09 item=item_pogo_stick location=stash
17645 22:43:53 [RPGItemSale v=71] neutral_remove item=item_pogo_stick entity=995 price=200 called=true live=false held=false error=none
17646 22:43:53 [Dota2Rpg] Neutral item sold: item=item_pogo_stick id=995 holder=__stash refund=200.
17647 22:43:53 [RPGItemSale v=71] request=2 player=0 phase=setup item=item_pogo_stick entity=995 holder=__stash ok=true reason=sold refund=200
```

This was a **new ch09 roll, immediately delivered, then successfully sold**, not an old pending tier1 reward, failed sale or cosmetic200 label. Earlier ch06 Kobold Cup also sold successfully for100 (12207–12209).

### Native cost, catalog, budget and multiplier — distinct concepts

Read-only extraction of installed `pak01_dir.vpk/scripts/npc/items.txt` and existing `scripts/data/campaign_loot_catalog.json` (under the addon) agree for Pogo Stick:

```
ItemCost = 0
ItemPurchasable = 0
ItemSellable = 0
ItemIsNeutralActiveDrop = 1
catalog category = neutral; power = 2; delivery = item_pogo_stick
```

Generated `data/campaign_loot_catalog.lua:189` likewise has neutral=true,power=2,cost=0. Native KV extraction used existing author-campaign-loot/native read helpers with Python -B; no extraction files or generated catalogs written.

**No live GetItemCost("item_pogo_stick") return is logged or was queried.** Native KV establishes the configured zero price; treating an engine call as measured would be false. More importantly, that API is not used by this reward/sale branch. `addon_game_mode.lua:GetNativePurchaseCost:1834–1852` is the purchase reconciliation helper, not neutral reward valuation.

- `battle/campaign_loot.lua:22–59`: `PowerCeiling(9)=ceil(9/6)=2`. Neutrals/specials use the current exact tier; ordinary ch09 base price window is1250–2250.
- `ProgressionPick:85–115`: successful gates choose85% ordinary equipment /15% current-tier bonus when both pools exist. Progression protection applies to ordinary equipment, not neutral resale value.
- `UpgradeEquipment:216–234`: only category standard with positive cost gets the approximately200%-of-base-cost assembled-item upgrade. It immediately returns Pogo unchanged. For ordinary ch09 candidates, nominal targets are2500–4500; actual choices use90–110% target bands or nearest higher assembled fallback. This is an ordinary purchase-price proxy, **not** a guaranteed sale-value budget for every reward.
- ch09 `levels.kv:514–583` uses `loot_hero`: gates0.30/0.20/0.35, three independent chances,0.85 expected reward count. Gold1800 and XP540 are separate victory rewards, not Pogo's economic value.
- `issue_fixes/item_sales.lua:5,18–28,66–94`: explicit neutral tier resale table100/200/400/800/1600; Pogo tier2 returns200, destruction is verified, then `game:AddGold(neutralPrice)` pays200 **directly**. No `GetItemCost` fallback overrides it and no0.5 or difficulty multiplier is applied here.
- Ordinary sale is delegated to native `holder:SellItem`; refund is observed from wallet delta, not calculated with a project-wide fixed multiplier. Do not globally change native cost or multiply all refund deltas to repair this neutral-only economy gap.
- `docs/UI70_EQUIPMENT_TRANSACTIONS.md` explicitly described modest neutral duplicate recovery. `docs/LOOT_VALUE_200_PERCENT.md` explicitly preserved neutral/special tier policy while correcting UI72's ordinary reward quantity. Thus current behavior follows prior documented policy, but does not satisfy the user's newer expectation of more valuable chapter9 neutrals.

**Root confirmed:** two independent authored policies were never economically aligned: ordinary rewards gained a200%-price conversion; zero-native-price neutrals retained the old tier schedule and very low fixed resale table. It is not a native-zero-cost override bug. The exact desired ch09 neutral value is not specified in existing data/docs and cannot be inferred from “too low.”

### Minimal recommended fix and tests

If the complaint is **sale recovery only**, minimally rebalance an explicit neutral tier resale policy in `issue_fixes/item_sales.lua`, with both locale tooltip values updated and UI version marker handled by the implementing agent. This does not change Pogo's actual combat strength.

If the complaint is **reward strength/value parity**, define an authored neutral equivalent-value/tier budget shared by reward selection and resale. Map chapter/difficulty reward budget to that value rather than multiplying native zero; use the approved policy in `campaign_loot.lua` neutral selection/pending upgrade and in item_sales. Do not relabel native catalog cost0 as a gold purchase price; native reproducibility tests intentionally require that zero. Do not silently reinterpret every previously held reward or grant retroactive money; specify whether new rewards only or all neutral sales are affected. No exact replacement200 value is justified without a design decision.

Tests: `tests/campaign-loot.test.lua` tier2 ch09 selection/standard multiplier separation, fixed three gates/count, deterministic ordinary/neutral branch choice, pending upgrade/no downgrade, difficulty boundary and replay behavior; `tests/shop-state.test.lua` / item-sales unit suite native zero+IsSellable=false exact validated neutral destruction and one authoritative payout, failed/no-op/detached removal pays0, forged refund ignored, duplicate request pays once, wrong owner/phase rejected; verify UI tooltip parity. `tests/campaign-loot-data.test.py` must keep generated catalog equal to native KV. Existing tier1 sale coverage is insufficient to establish new ch09 economy correctness.

**Needed decision:** Is200 too little resale, or is tier2 Pogo itself too weak? What chapter9 equivalent value/resale target should the difficulty policy promise? Those are separate adjustments.

## Validation boundary

Performed targeted actual-HUD read-only reproductions (4/4,4/2, sparse4/2), source/data/doc inspection, installed-source method comparison, native KV extraction, and preserved-log identity verification. No source regression suite changes or full test-all run; no native GetItemCost call, game interaction, network delivery measurement or claim of an installed fix.


## 3. ch15clarification — last defeated chapter (read-only follow-up)

User clarification: “敌方目标只有2实际4” concerns **ch15, the terminal loss Sep14 22:56:39**, NOT ch12. The earlier four-unit reproduction is not a mapping of this incident. This appendix preserves the historical report. Only this report is appended; no source changes, install, gameplay operations or commit.

### Exact initial entities and counts

Installed `game/dota/console.8998798026.log` still has SHA256 `1f2b080cabb59e1608c9042cb3209e8b611d1f29ce42eba9ebcbef59465f0fa0`. **30739 /22:54:11: `Level 'ch15' spawned 5 enemy units.`**

|Initial position|Entity|Unit|Ready line (all22:54:11,alive=true)|Expected actor suffix|
|---|---:|---|---:|---|
|1|341|npc_dota_hero_slark|30718|npc_dota_hero_slark:0|
|2|969|npc_dota_hero_troll_warlord|30723|npc_dota_hero_troll_warlord:0|
|3|276|npc_dota_hero_jakiro|30728|npc_dota_hero_jakiro:0|
|4|615|npc_dota_hero_skeleton_king|30733|npc_dota_hero_skeleton_king:0|
|5|286|npc_dota_hero_bloodseeker|30738|npc_dota_hero_bloodseeker:0|

Each expected actor is `ch15:enemy:` plus the listed suffix, derived from RuleSnapshot, **not a captured wire payload**. All five alive again at fight start **33066–33070 /22:56:16,t1592.07**. There is one ch15 initial assembly, not a four-unit retry.

Boundary trap:30683–30686 show outgoing DEAD ch14 heroes Gyrocopter693,Warlock856,Slardar869,Luna919 under newly advanced level=ch15 before reset_begin30701 at22:54:11. Those four are NOT ch15 initial enemies.

Registered-enemy life timeline:

- Start: **5 alive**.
- **33188 /22:56:22,t1597.57**: WK615 dies,reincarnating=true;33200,t1597.67 confirms alive=0/reincarnating=1. **4 alive +1 returning**.
- **33288 /22:56:25,t1600.67**: same entity615 respawns;33290,t1600.77 confirms alive=1/reincarnating=0. **5 alive**, not a new actor or sixth enemy.
- **33530 /22:56:36,t1611.47**: WK615 final death,reincarnating=false;33542,t1611.57 confirms dead. Briefly **4 alive**.
- **33551 /22:56:36,t1611.93**: Bloodseeker286 dies,reincarnating=false;33555,t1611.97 confirms dead. **3 alive** thereafter: Slark341,Troll969,Jakiro276. Last living observations are33574 /22:56:38,t1613.37 and33586–33587 /22:56:39,t1615.07. No later deaths of these three logged.
- **33584 /22:56:39,t1615.00**: final allied Drow259 dies;33589 remaining=0;33591 all five lives lost.

Observed registered count sequence: **5 →4 →5 →4 →3**, never2. Four visible living authored enemies is plausible during reincarnation or the short final-death interval. This does not explain two dropdown choices; exact user observation time is unmeasured.

### Summons, illusions, sparse indices, and BuildEnemyRoster

At **33155 /22:56:20,t1596.07**, WK615 is active=`skeleton_king_bone_guard`. Skeleton summoning is relevant, but ch15 combat has **no individually identified creep/skeleton summon or illusion spawn roster**. Exact summon/illusion counts are **unknown, not zero**. An active-ability observation is not proof of successful summon count. Allied Drow carries Manta; that is not evidence of enemy illusions.

No `BuildEnemyRoster` symbol was found in searched workspace/installed addon sources. The actual builder is inline `addon_game_mode.lua:BroadcastHeroInfo` (workspace4933 onward): registered teamHeroes[BADGUYS] → IsValidUnit → id/name/target_actor. **No IsRealHero, IsIllusion or IsAlive filter. Registered initial creeps are included, just like heroes.** Nonregistered combat summons are omitted by registration scope, not a hero-only serializer filter.

The IsRealHero exclusion instead appears in `summon_behavior.lua:TrackEnemySummon`149–160: enemy non-realhero/nonregistered units enter `game.enemySummons` for cleanup; real heroes and authored enemyRuleIndex/registered enemies are protected. This is NOT the dropdown roster builder. Neither realhero summons nor creep summons automatically become chapter actors; registration is decisive. `OnNpcSpawned` routes summon handling separately.

`BattleManager:RegisterHero` uses table.insert, compact initial positions1–5. All five ch15 handles remain in diagnostics; dead WK615/Bloodseeker286 still produce valid records33578–33579. No evidence of sparse initial slots or removed earlier handles in THIS chapter. The prior sparse-slot reproduction remains a code-level fixture, not a measured ch15 cause.


### Exact UI wording and dataflow — do not claim this clarified incident fixed

- No standalone locale value exactly `敌方目标` found. The phrase occurs in `指定敌方目标` (dota2_rpg_v2_specified_enemy,workspace455/installed446), `选择当前敌方目标` (dota2_rpg_v2_choose_target,workspace461/installed452), a validation sentence and help prose. These most closely identify the F39 dropdown, but shorthand alone does not establish a panel.
- **Specified enemy:** registered team → BroadcastHeroInfo → rpg_enemy_roster → onEnemyRoster/HEROES.Dire → targetActors → rule editor. Other agent's workspace HUD now uses roster-owned target_actor independent of capability slots. Installed HUD inspected here still lacks that new branch and differs from workspace. Installed/workspace BroadcastHeroInfo and AssembleLevelEnemies method extraction matches; whole addon_game_mode does not. The historical whole-HUD parity statement is no longer current. No install was done here. The fix addresses the known slot dependency, not proven live ch15 attribution.
- **Remaining-enemy counter:** BuildBattleState publishes dire_alive=GetAliveCount(BADGUYS), registered valid IsAlive units only. Returning WK is excluded from ordinary count; CheckBattleEnd separately includes returning heroes. However **neither installed nor workspace inspected Panorama HUD consumes dire_alive**. A purported visible battle counter cannot be mapped to this unused field without identifying the screen/native HUD.
- **All-enemy panel/DPS:** no enemy rule-editor panel in current custom layout. DPS `敌方` tab lists damage-snapshot attackers by team, and `受击目标` lists victims of selected actor/source; rpg_damage_stats → renderDamage, not rpg_enemy_roster. Two victims can be correct with five enemy actors. Enemy-tab victims are generally allied units, not a census of enemy heroes. Action-reference pickers separately retain a genuine ability-slot dependency.

**Conclusion:** ch15 conclusively starts with **five authored heroes** and has **three surviving at terminal loss**, with observed intervals of four alive. Neither two initial heroes plus two summons nor four initial enemies fits the log. No roster-send/client-commit telemetry measures the two dropdown identities. Needed mapping: panel screenshot or exact two names and observation time (specified-enemy, action-reference, DPS attackers/victims, or native counter). Do not advertise the workspace specifiedenemy fix as resolving this clarified report without that mapping. Follow-up was read-only except this appendix; no tests/source writes, game operations, install or commit.
