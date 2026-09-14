# Correction: upgrade per-item value, not quantity

User clarified that UI72's doubled count was not intended. This update supersedes the **reward quantity** section of the historical UI72 report; historical deployment/test numbers remain unchanged.

- Restore one reward per successful original gate, at most three per victory. Gate probabilities unchanged.
- For each ordinary item, target200% of its original native cost. Choose among native recipe results priced90–110% of that target (180–220% of original).
- Example: Ogre Axe1000 can become Dragon Lance1900, Sange2100, Yasha2100 or other eligible assembled components. Hyperstone and Demon Edge are excluded because they are raw components, not recipe results.
- If no candidates fit, select the nearest more-expensive assembled item. If none is more expensive, retain the original item; never downgrade. Very cheap/expensive items therefore cannot guarantee an exact2x native price.
- Neutral/special zero-cost rewards retain their existing tier policy; pending low-tier neutral upgrade behavior remains. No changes to held items, gold, XP, life rewards, scrollbar visibility or inventory recovery.
- Existing queued rewards are not retroactively duplicated or upgraded by this ordinary-price conversion; it applies at new reward creation.

Allowlist `data/assembled_loot_items.lua` contains129 native recipe result names extracted from the existing `scripts/data/campaign_loot_catalog.json` snapshot. A parity test prevents stale/mistaken raw-component entries.

Validation: **115/115 offline groups passed**, including real Roll→Award per-item value increases, the explicit Ogre Axe example, max-native-price saturation and quantity restoration. Report `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-loot-value-regression.json`.

Two backend sources installed byte-identically. Backup `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-loot-value-njx735qp`. Both locale files still matchUI72; no frontend changes/compilation. No gameplay operations performed; reload addon session to verify live drops.
