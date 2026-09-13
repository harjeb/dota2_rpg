# UI70 equipment purchases, rule identity and neutral sales

## Reported BKB purchase

The preserved `console.8997057435.log` records three native orders at 2026-09-13 21:15:48 (lines 14196–14198): mithril hammer, ogre axe and the BKB recipe. At 21:15:49, lines 14201–14203 report that each component could not be located for Axe and the native result was retained. The user observed the resulting BKB on the commander Wisp.

These warnings establish the component lookup failure. They occur after debit validation; they do **not** establish that no gold was charged. The session's bounded wallet/transaction diagnostics had already expired, so the precise balance for this purchase is unavailable. Evidence copy: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-bkb-purchase-08f70wrt/console.8997057435.log`.

Native purchase reconciliation now recognizes fresh combined results using explicit native/custom recipe definitions. Qualification requires consumed baseline components on that holder or matching contemporaneous purchase contexts for the same recipient. All component prices settle individually and share evidence for a single transfer of the result. Existing, unrelated, ambiguous, moved or still-present components do not qualify as consumed recipe evidence. This covers the reported direct BKB recipe; unsupported or unproven combinations retain the conservative fallback.

A separate reproducible wallet bug treated any net balance decrease as native purchase payment. Project spending and rewards now adjust unsettled order baselines; addon purchase debits are kept separate. The regression with a 1,000 starting balance, a separate 250 expense and an engine-free 250 purchase produced 750 before the fix and correctly produces 500 afterward. Native payment plus concurrent project income is also covered. This does not retrospectively prove the user's particular BKB was free.

Transaction diagnostics use a renewable 200-entry/minute budget and the critical trace channel so late purchases remain observable after general tracing is exhausted.

## Equipment conditions

Server snapshots previously translated equipment names into inventory positions (`item_1`, etc.). An authored HUD row could retain that position as new equipment changed the inventory, causing its conditions to follow the next occupant.

Snapshots and item selection now retain native equipment names. Legacy slot snapshots resolve their name using the inventory mapping received with that snapshot. Rule order and conditions survive additional purchases, repacking and removal. This retains the existing item-name action semantics.

## Neutral equipment resale

Neutral equipment resale values are defined by the server:

| Neutral tier | Gold |
| --- | ---: |
| 1 | 100 |
| 2 | 200 |
| 3 | 400 |
| 4 | 800 |
| 5 | 1600 |

The modest early-tier values recover some value from duplicates; each higher tier doubles the recovery. Regular equipment retains native sale prices. Hovering over Sell displays both policies in Chinese or English. Existing phase/ownership/pending-purchase restrictions remain applicable, and successful sale requires destruction of the exact item entity before paying gold.

## Validation scope

Full offline regression: **107/107 passed** (`scripts/test-all.py`, portable Lua 5.1 and Node). The report is `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui70-regression.json`; the existing tracked historical report was not overwritten.

Installed six changed addon sources and byte-verified them against the workspace. Native resource compilation of `rpg_demo_hud.js` succeeded (126,801-byte `vjs_c`). Both installed locale files match UI70. Previous installed files and a manifest are backed up in `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui70-olie1ph2`.

Offline coverage includes component batch settlement and routing with/without native purchase events or native debits, concurrent project wallet changes, item rule hydration/editing/inventory changes, and neutral sale validation. No Dota session was started or operated. Native purchase event timing, game UI behavior and actual neutral removal still require user-driven verification after reloading the map. Both locale markers are UI70.
