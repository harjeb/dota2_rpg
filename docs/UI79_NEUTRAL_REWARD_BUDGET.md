# UI79 neutral reward supplementation

Issue: **dota2_rpg-huym**. Clarification: “是掉落装备的档次 如果掉200的中立就要补充其他装备” — improve the aggregate equipment reward, not the neutral's sale price.

This policy supersedes **only** the neutral-equipment row of `CAMPAIGN_DIFFICULTY_UI79.md` and the neutral exclusion in the older ordinary-value policy. The historical read-only diagnosis remains evidence of the original behavior, not current policy.

## Explicit common units and budget

Ordinary reward quality already uses native **purchase prices** as a proxy, with a stage-pool base draw followed by `UpgradeEquipment` (approximately x2 assembled equipment). Native neutral ItemCost remains **0**. Neutral liquidation remains **100 / 200 / 400 / 800 / 1600** at tiers 1–5; regular sales remain native transactions.

For budget accounting only, define neutral **purchase-equivalent** credit as **twice tier liquidation**: **200 / 400 / 800 / 1600 / 3200**. This is an authored economic proxy, not a claim that neutral native purchase price exists, combat utility equals that gold amount, or every actual ordinary sale refunds exactly half. Enchantments use the same tier proxy, without adding a sale permission or a new payout.

For **each successful gate that rolled a neutral**:

1. Preserve the originally rolled neutral name/category/tier; never difficulty-scale its tier as well.
2. Draw an ordinary reference from the same chapter's ordinary price pool, using the existing ordinary progression selection with a copied history. The real ordinary progression history is not changed by this reference draw.
3. Apply the existing `UpgradeEquipment` to that reference. Its actual assembled catalog cost, not the nominal x2 target, is the explicit ordinary-equivalent reference budget.
4. Multiply this budget **once** by Easy **1.5**, Default **1**, or Hard **0.7**, using existing half-up rounding. Arena multiplier bypass remains inherited.
5. Subtract the neutral's purchase-equivalent credit, floored at zero. Spend the shortfall on highest-affordable **assembled standard equipment**, random among equal prices, repeatedly until no assembled item fits. Supplements themselves are never upgraded/scaled again and never run another loot/drop gate.

Current cheapest assembled reward is Buckler, **425**. Residual is therefore **0–424**, rather than a potentially multi-thousand-gold shortfall. The package never exceeds target by adding supplements. If the preserved neutral credit alone exceeds target (possible early chapters), no supplement is added and the native neutral is not destroyed/downgraded. Catalog changes automatically change the residual bound; tests derive it from actual assembled data. Unknown-stage callers use the ordinary portion of the full catalog; a hypothetical pool with no ordinary candidate preserves only the neutral.

## Chapter 9 examples

Ch09 base ordinary pool is 1250–2250. A deterministic reference with ordinary history 1800 upgrades to Black King Bar at **4050**. Pogo Stick remains original tier2/native cost0 and still sells for **200**, accounting credit **400**:

| Difficulty | Scaled target | Neutral credit | Added assembled purchase value | Residual |
|---|---:|---:|---:|---:|
| Easy | 6075 | 400 | 5650 | 25 |
| Default | 4050 | 400 | 3500 | 150 |
| Hard | 2835 | 400 | 2400 | 35 |

These are reproducible test examples, not a fixed guaranteed BKB/reference for every ch09 roll. With empty history and first-choice deterministic RNG, the actual Award path instead references 3000: targets4500/3000/2100, supplemental equipment4100/2600/1700, all residual0. Thus “200的中立” no longer consumes a whole equipment gate without ordinary supplementation. We improve actual assembled equipment delivered; we do not merely relabel the neutral's tooltip or mint cash.

## Delivery, progression, RNG and compatibility

All bundle items and accounting metadata are fixed **once in Award**, before any delivery attempt. Settlement names include every earned item, even if storage is full. Each pending entry retains `neutralBudget`; `Flush` only delivers fixed entries and cannot calculate/append another supplement. Existing neutral-slot versus standard-slot capacity rules and ambiguous native callback quarantine remain unchanged.

New budgeted pending neutrals are **not auto-upgraded on a later chapter**: that would grant surplus after spending their original budget. Old unbudgeted pending neutral entries keep their inherited upgrade/no-downgrade behavior and receive **no retroactive supplements**. Held neutrals and prior rewards are untouched. No supplement is issued by flush, reconnect, queued delivery or inventory-capacity recovery. Existing victory settlement idempotency still owns whether Award is invoked; this module does not turn arbitrary repeated Award calls into one victory.

Three independent drop gates and 85% ordinary/15% bonus selection remain unchanged. Roll chooses all base rewards before bundle generation; only a neutral reward consumes the additional reference/supplement RNG draws. Ordinary-only and utility-only awards retain their previous selected items, quantities, progression and random-call counts. Aegis/cheese utility policy and its separate pending-item delivery are unchanged. Multiple neutral gates each independently earn their own bounded bundle.

## Offline validation and handoff

New `tests/neutral-loot-budget.test.lua`: all 30 chapters, all three difficulties, every eligible neutral category/tier, low/high RNG choices; residual/overspend bounds; all three ch09 low-tier examples; three neutral gates; absent/full carrier, later chapter/difficulty, successful delivery retry and ambiguous-callback quarantine; ordinary RNG and special utility preservation; legacy pending upgrades versus new frozen budget entries.

New `tests/neutral-loot-budget.test.js`: cross-module fixed liquidation schedule versus explicit x2 accounting proxy, native Pogo cost0/tier2, no reward generation in Flush, documentation contract. Existing difficulty fixture now expects original neutral identity rather than difficulty-scaled tier.

Focused suites passed: neutral-loot-budget Lua/JS, campaign-loot Lua, loot-value-upgrades Lua, campaign-difficulty Lua. Lua runtime: portable Lua5.1.5 under `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-lua515-4lsm6zwd/lua.exe`. No locale changes needed; existing visible version stays **UI79**. No installation, game operations, compilation, commit or push by this subagent; main agent owns economics review, full regression and delivery. Actual native item capacity/stacking requires in-game verification; mocked delivery is not native gameplay evidence.
