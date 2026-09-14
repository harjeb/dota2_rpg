# Native component purchase reservation correction — 2026-09-14

## Live evidence

Read-only `game/dota/console.log`, 09/14 20:34:54, lines 4319–4337:

- Mars's selected purchase started with 647 gold.
- Circlet cost 155: order snapshot 647, purchase event wallet 492.
- Gauntlets cost 140: order snapshot 492, purchase event wallet 352.
- Bracer recipe cost 210 was rejected despite the 352-gold wallet.
- At 20:35:07 a subsequent recipe purchase succeeded, leaving 142; later lifecycle logs included `modifier_item_bracer`. The original problem was a rejected component order, not a permanently broken native combination.

## Cause and correction

`GetPendingNativePurchaseReservation` selected the **lowest** outstanding `gold_before`. With the two component snapshots, it recognized only `492 - 352 = 140` already debited gold against 295 reserved cost. It incorrectly withheld another 155, reducing available gold to 197 and rejecting the recipe.

Use the **highest** outstanding snapshot instead: `647 - 352 = 295` recognizes both native debits. Outstanding snapshots still receive existing project-wallet rebasing; checked/failed contexts remain excluded and duplicate context references remain deduplicated. No item prices, native combination behavior, delivery routing, or wallet debit policy changed.

## Verification

Added `tests/shop-state.test.lua` regressions for the exact 155/140/210 sequence, with:

- 647 starting gold (142 left), exactly 505 (0 left), and 504 (recipe rejected).
- Immediate native debits, fully deferred debits, and mixed native debits.
- Outstanding purchases distributed across event-queued and still-waiting order-context lists.
- Observed debit accounting, exactly-once settlement, and no reservation after settlement.

Before correction the new test failed: `all native component debits recognized: expected 295, got 140`. After correction the focused test passed. The portable offline suite passed **116/116** groups, including all Lua source syntax checks. These are native-API doubles, not live Dota verification.

This correction changes no UI behavior. It is delivered with the user's additional ward-loot exclusion and Experience Scroll label changes as **UI version 75**; both installed locale files match source byte-for-byte. All seven changed game files (locales, catalogs, purchase handler, and Undying lifecycle modules) were installed and SHA-256 verified. No Panorama source changed, so no UI resource compilation was required. The full offline suite was rerun after all changes: **116/116** groups passed.

No game launch, restart, in-game commands, or screenshots were performed. A fresh user-run session is needed to validate one-click Bracer purchase in the engine. Undying cleanup still requires live action-recovery verification, tracked in `dota2_rpg-siv7` and `docs/UNDYING_RETURN_LIFECYCLE_2026-09-14.md`.
