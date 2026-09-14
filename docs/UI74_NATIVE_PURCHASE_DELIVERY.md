# UI74 — native purchase delivery and recipe assembly

## Reported behaviour

The user bought items for a hero and received only part of the components; the rest
stayed in another carrier's inventory (the commander Wisp). The purchased item then
never combined, and it had to be moved by hand.

## Root cause (live evidence)

`C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-wisp-loot-s0_x9r05/console.log`
(`console.8997185207.log`), Phantom Assassin buying Battle Fury components:

- 22:52:22 `ShopTxn id=2 stage=transfer item=item_void_stone target=npc_dota_hero_phantom_assassin decision=attachment-failed-preserved`
- 22:56:16 `ShopTxn id=6 stage=transfer item=item_recipe_bfury target=npc_dota_hero_phantom_assassin decision=attachment-failed-preserved`

Both components were paid for, but the hero had no room (`0..8` full), so the transfer
ended in `PreserveDetachedItem` — the item was returned to the Wisp and the purchase
was marked **resolved**. Nothing ever retried the delivery, so:

1. the hero kept only part of the components,
2. the rest stayed with the Wisp (B),
3. the recipe could never combine, because the native engine only combines items that
   are in the **same** carrier's main inventory (`0..5`).

The earlier UI70 combination qualifier (`FindNativePurchaseCombination`) covers the case
where the engine already combined the whole batch in one carrier. It cannot cover a
batch that was split across carriers, and UI71/UI72 explicitly recorded this as
unverified (`docs/UI71_LIVE_INVENTORY_AND_MINES.md`: "exact BKB batch automatic
routing ... remain unverified").

## Fix

`game/dota_addons/dota2_rpg/scripts/vscripts/addon_game_mode.lua`

1. **A paid purchase is never silently stranded.** When the exact purchased entity
   cannot be attached to the intended hero, the order is kept in
   `pendingNativePurchases` with `awaiting_delivery` and retried every think
   (`ShouldRetryNativePurchaseDelivery`, `NATIVE_PURCHASE_DELIVERY_RETRY_SECONDS` /
   `_ATTEMPTS`, logged as `awaiting-space`). As soon as the hero frees
   a slot (combination, sale, consumption) the same entity is delivered and the native
   engine combines it on the hero. The item is never destroyed or recreated by name.
2. **Recipe assembly assist for a full hero** (`TryDeliverNativePurchaseWithAssist`).
   Only when the arriving item verifiably completes a native recipe
   (`DescribeNativePurchaseRecipe`, explicit `ItemResult`/`ItemRequirements` data):
   free the needed main-inventory slots by temporarily moving equipment that is *not*
   part of that recipe to the source carrier, promote recipe parts that sit in the
   backpack/stash into `0..5`, deliver the purchased entity, and put the temporarily
   moved equipment back. Everything is verified by exact entity id and rolled back if
   the combination does not happen; swaps that cannot be returned yet are queued
   (`ReturnNativePurchaseSwapItems`) instead of being dropped.
3. **Post-delivery assembly** (`TryFitNativePurchaseRecipeIntoMainInventory`). If the
   delivery landed but the engine did not combine (a part was placed in the backpack),
   the parts of that same recipe are promoted into `0..5` — with a temporary swap when
   the main inventory is full — so the purchase still assembles on the hero. Without a
   verifiable combination the promotion is undone and the temporary equipment returns.
4. Guard rails: only recipes that contain the purchased item are considered, growth
   items (Gris-Gris / Eldwurms Edda) are never used as swap candidates, experiments are
   throttled (`NATIVE_PURCHASE_SWAP_INTERVAL`, with a think-count fallback when no game
   clock exists), and every failure path preserves the item with a log line
   (`attachment-failed-preserved`, `assist-rolled-back`, `delivered-after-assist`,
   `delivered-after-assembly`).

`CollectNativePurchaseBatch` was extracted from `FindNativePurchaseCombination` so the
combination qualifier and the assembly assist share one definition of "one purchase
batch" (same recipient, issuer and adjacent tick/time).

## Validation

- New offline regression `tests/native-purchase-delivery.test.lua` (native API doubles,
  real recipe shapes: a two-part recipe without a scroll, a three-part recipe with a
  scroll, and a recipe whose combination is deliberately unavailable):
  1. retained order: charged exactly once, stays with the source, delivered later;
  2. assist: full hero + recipe-completing arrival → combination on the hero and the
     temporarily moved equipment returns;
  3. no recipe evidence → no equipment is moved (no per-think churn);
  4. a part resting in the backpack is promoted and the purchase combines;
  5. failed combination prediction → full rollback, nothing lost.
- Full offline suite `python scripts/test-all.py`: **116/116 passed**
  (report `tests/results/reliability-regression.json`), including the existing
  `shop-state`, `shop-transition`, `shop-transport*`, `item-sales` and
  `native-purchase-combination` suites.
- Lua sources parse under portable Lua 5.1; no Panorama/resource file changed, so no
  resource recompilation is required for this version.

## Limits

- Only offline simulation was executed. Native engine timing, the real `AddItem`
  placement (main inventory vs backpack) and the actual combination still require a
  user-driven session; this document makes no live-verified claim.
- If the hero's main inventory is completely occupied by recipe parts, no swap
  candidate exists and the purchase waits (retry) until the player frees a slot.
- A queued swap return stays with the source carrier for at most the retry window
  (`600 s` of game time) and then logs a warning; the item is never removed.
