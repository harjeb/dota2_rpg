# Campaign difficulty — UI79

Issue: `dota2_rpg-3202`. Backend follow-up: `dota2_rpg-n421`.

## Entry and lifecycle

The campaign entry overlay offers **简单 / 默认 / 困难** (Easy / Default / Hard), initially highlighting Default. Confirmation sends only an enum; the server validates engine PlayerID, setup phase and a one-time lock. Reward factors are exclusively server-owned: **1.5 / 1 / 0.7**. Confirmation locks the choice before play, not only before the first fight. Native earned ticks are withheld and campaign preparation mutations/start are blocked while awaiting confirmation, avoiding default-rate pre-selection farming.

The confirmed choice survives retry, chapter transitions, replay and reconnect. A new lobby allows a new choice. Replay clears native fractional credits but retains difficulty. Missing metadata means Default for old fixtures/callers. HUD refresh does not erase an unconfirmed draft; reconnect uses the server selection. Published local settlement/result metadata contains `campaign_difficulty`, `reward_multiplier`, `difficulty_version=1` (terminal metadata also carries the lock).

**Arena remains disabled in this branch**: its existing commented integration and HUD include are intentionally not re-enabled. If reopened separately, its mode publication updates the difficulty overlay, the campaign selector only appears for campaign, all reward multipliers are bypassed in arena/select modes, and arena exports retain their existing independent competitive team contract. No campaign inventory is exported into arena; arena already reconstructs a fresh team.

## Reward boundaries

| Stream | Policy |
| --- | --- |
| Chapter victory base gold | Multiply once in actual EndBattle settlement, before wallet credit |
| Victory time bonus | Compute existing 10%-cap bonus from original base gold, then multiply once independently |
| Chapter XP | Multiply once before active/bench distribution; active gets scaled integer, bench gets floor(active × 0.5); zero XP stays zero |
| Native gold | Owner-only positive earned reason filter: game ticks, building/hero/creep/Roshan/courier/ward kills, shared gold, ability gold, supported rune constants |
| Native XP | Owner-only positive kill/unspecified (native ability income)/outpost/wisdom-rune reasons; native TomeOfKnowledge excluded as fixed consumable value |
| Custom Jinada | Multiply explicit custom payout once; existing native gold suppression remains, wallet itself never scales |
| Gris-Gris | Scale earned bank ticks on one-time redemption, and show that payout in HUD; actual death-loss deposits are returned principal, not multiplied again |
| Three-heart compensation | 2000 base becomes 3000 / 2000 / 1400; existing one-time threshold guard remains |
| Ordinary loot equipment | Preserve existing three rolls and existing x2 assembled upgrade; scale the **post-upgrade native price budget**, choose highest catalog price within budget, random among ties. No item stat edits or duplicate copies |
| Neutral equipment/enchantments | Preserve rolled native tier; draw an ordinary chapter reward reference and scale its post-upgrade price budget once. Credit neutral tier liquidation ×2 as purchase-equivalent value; supplement the difference with assembled ordinary equipment. New pending bundles never re-roll or auto-upgrade. See `UI79_NEUTRAL_REWARD_BUDGET.md`; this supersedes the initial tier-multiplier implementation following user clarification |
| Special utility rewards | Aegis/cheese and other zero-price non-equipment special rewards retain quantity/function. Five lives remain five |
| Starting capital/free recruits/innate kit | Not earned campaign rewards: remain 500 gold, two free recruits, original innate grants |
| Purchases, sales, refunds, returned principal | Fixed/native values. AddGold, SetGoldBalance and AddXpToHero are deliberately NOT global multiplier hooks; sales cannot buy/resell for extra money |
| XP scrolls | Current catalog/reward tables do **not** award RPG XP scrolls; both actual scroll-use routes consume purchased fixed-value stock. They remain fixed XP. Future reward-scroll issuance must add explicit provenance; do not globally multiply scroll consumption |
| Retry / full stash | Defeat does not grant victory gold/XP/loot. Earned pending items preserve selected names/entities and existing ambiguous-delivery protection; flush does not roll or scale again |

Gold/XP stage rewards round nonnegative values half-up. Native micro-income keeps a separate fractional remainder per reason and stream, so ten 1-gold ticks pay 15/10/7, rather than Hard rounding each tick back to one. Default native events remain byte-value unchanged. Discrete native prices and catalog ceiling mean ordinary item realized price is not guaranteed to equal the budget exactly; below the cheapest equipment no over-budget item is invented. Neutral supplements leave less than the cheapest assembled-item price (currently 425) unspent; the retained neutral itself can exceed very small early-stage budgets, in which case no supplement is added. Enemy stats, shop prices and item stats are unchanged.

## Leaderboard fairness and backend boundary

Read-only inspection: `docs/leaderboards.md`, ignored `backend/leaderboard-worker/src/domain.ts`, types and SQL-facing index. `/api/v1/runs` rejects unknown fields and has no difficulty partition; historical records and per-player bests share one v1 board. Adding a JSON difficulty field would currently be rejected, and sending boosted Easy without it would pollute the default board.

UI79 therefore blocks **both Easy and Hard** in terminal generation **and** direct submission entry. Local scores and terminal/reconnect views remain available with explicit difficulty and localized `difficulty_unranked` explanation. Default payload and score version stay exactly compatible; no unsupported backend field is sent. There is no campaign persistent export endpoint; local settlement/result is the appropriate metadata boundary. No cloud calls, migrations, backend writes or backend commits were made.

Future separately authorized work (`dota2_rpg-n421`): add a validated difficulty/version schema, migrate historical rows as default, include difficulty in relevant uniqueness/idempotency, partition score/speedrun/personal/history/neighbor queries and immutable response snapshots, test migration and cross-difficulty isolation, deploy compatible backend before enabling addon payload/ranking changes. This local guard is fairness policy, not anti-cheat authentication.

## Offline evidence / handoff

Focused tests execute the actual EndBattle, loss rewards, loot selection/delivery, progression primitives, native filter contracts, Jinada/Gris-Gris, result submission guards and actual XML-loaded Panorama script. New tests: `campaign-difficulty.test.lua`, `campaign-difficulty.test.js`; extended `shop-transition`, `loot-value-upgrades`, `gris-gris`; existing broad lifecycle mocks explicitly load the new pure policy module.

Focused run report: `tests/results/campaign-difficulty-ui79-focused.json`: **21/22 passed**, including all new difficulty tests and all tested Lua gameplay groups plus syntax of every addon Lua source. The one failure is existing `condition-ui-v2.test.js:273`: concurrent enemy-target roster implementation now requires `target_actor` in roster entries, while that legacy fixture populates it only through capability slots. This agent did not modify that concurrent roster implementation or its new `enemy-target-roster.test.js`; main should reconcile the fixture during full regression. `git diff --check` passes.

Native filter reason emissions, native XP persistence already owned by the existing hero lifecycle, actual Dota layout/input, and native item delivery require user-run game verification. Offline substitutes do not prove those engine behaviors. Agent performed no game operations, installation, resource compilation, cloud deployment, commit or push. Main integration reconciled roster fixtures, added policy-module loads to focused mocks, and registered the new JS/CSS in the installer. Final full regression, installed-locale verification and deployment evidence are recorded below. Preexisting `.install_out.txt`, `.verify_out.txt`, `scripts/_extract_vpk_entry.py` were preserved.


## Final main-agent integration and installation

Full `LUA_BIN=.../lua.exe python scripts/test-all.py`: **124/124 offline groups passed** after neutral supplementation and roster fixture reconciliation. Evidence: `tests/results/reliability-regression.json`. An independent read-only review found no confirmed critical regression in difficulty locking, XP/gold double-scaling or ranked submission guards. This is not native gameplay acceptance.

Installed **15 runtime sources**, each byte/SHA-256 verified against this worktree. Compiled HUD XML, HUD JS, difficulty JS and difficulty CSS with Dota resourcecompiler: each **1 compiled, 0 failed**. Both installed locales match source and display **UI79**. Original-file backup, manifest and four compiler logs: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui79-xtfqngub/`. No game process or in-game commands were operated.

User clarification changes neutral reward policy from scaled tiers to supplementary equipment; the final policy is `UI79_NEUTRAL_REWARD_BUDGET.md`. Chapter15 target incident remains unconfirmed despite fixing a reproducible specified-enemy dropdown data dependency. Live follow-up: `dota2_rpg-x99y`; backend difficulty partition follow-up: `dota2_rpg-n421`. Existing terminal native crash is not claimed fixed by UI79.
