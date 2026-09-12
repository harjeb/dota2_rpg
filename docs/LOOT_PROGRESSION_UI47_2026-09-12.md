# Campaign loot progression and five-row DPS panel — 2026-09-12

The previous loot selector uniformly sampled the current and preceding power tiers, advancing only once per six stages. It carried no price history between victories. An expensive early reward could therefore be followed by a much cheaper item, including within the same chapter.

Ordinary drops now use the installed native ItemCost, exported alongside category and power by `scripts/author-campaign-loot.py`. The three existing independent reward gates retain their configured probabilities (ordinary/hero fights average 0.85 rewards, bosses 1.35). After a successful gate, 85% of selections are ordinary items and 15% are current-tier neutral or special rewards. Nonstandard items use their existing power classifications rather than treating their zero native price as low equipment value.

The ordinary price ceiling grows by 250 gold per stage. The lower bound follows 1,000 gold below that ceiling, capped at 6,000 to retain the full top tier at the end.

| Stage | Ordinary price range |
| --- | --- |
| 1 | 1–250 |
| 6 | 500–1,500 |
| 12 | 2,000–3,000 |
| 18 | 3,500–4,500 |
| 24 | 5,000–6,000 |
| 30 | 6,000–7,500 |

90% of ordinary selections prefer an item above the run's highest earned value, falling back to equal value when the current stage has no higher candidate. The other 10% sample the current price window. Lower rolls do not reduce the remembered maximum. Prices above 6,000 count as one top tier, so receiving Dagon 5 does not force all subsequent protected drops to repeat it: all nine top-tier items remain eligible at stage 30. Price is a progression proxy; a hero's best item still depends on its build.

History lives in `runLives.campaignLootProgress`, is updated when rewards are earned even if delivery is queued, and resets with the existing session reset. Returning to an earlier stage still obeys that stage's ceiling. Calls without a usable stage retain the full catalog behavior. Delivery, native RNG, and life-reward handling are unchanged.

The DPS hero list is 255px tall, increased from 176px: five rows × (48px row + 3px bottom margin). The surrounding sidebar already provides enough space for the header, tabs, and list. UI build tag is 47.

Validation: all 83 offline regression groups pass, including native catalog reproduction, gate/protection boundaries, top-tier variety, queued reward history, replay reset, actual EndBattle settlement, and existing HUD checks. A deterministic 1,000-run simulation produced 25,294 rewards: 84.70% ordinary equipment, 96.48% of adjacent ordinary drops held or improved the progression value, 92.93% held or increased actual price, and 86.29% strictly increased price. Mean ordinary price rose from 147 gold at stage 1 to 6,624 at stage 30. These are offline simulation results, not live gameplay measurements.

Native Panorama CSS compilation succeeded; five installed source files matched repository SHA-256 hashes. Deployment evidence and backup location are recorded in `tests/results/ui47-loot-deploy.json`. Dota was not launched or controlled for this change.
