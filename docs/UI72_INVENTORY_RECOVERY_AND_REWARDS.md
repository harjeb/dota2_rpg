# UI72 — inventory receipts, rewards and condition scrollbar

## Inventory loss recovery

UI71 emitted bounded snapshots but had no receipt/recovery path. A native send can silently fail and the server could consider its cache current while the HUD remained stale. Latest evidence `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-wisp-loot-s0_x9r05/console.log` has eight CEM serialization failures at 22:59:10, while 23:00:17 explicitly records Aegis/Cheese delivered to stash. The failed event family/native limit is not proven.

UI72 reduces JSON chunk data from1,200 to256 bytes and small-message budget to512. Existing atomic generation/revision assembly remains. Every five seconds the HUD reports its last fully committed inventory revision. An authorized owner-only, server-throttled receipt handler compares that against the newest targeted or broadcast snapshot; mismatches cause a fresh targeted inventory serialization, not replay of stale mirrors. Matching receipts do not resend. Missing entire messages and partial chunks are covered. Native engine-supplied PlayerID is mandatory. No periodic global resend and no item creation on retries.

`RPGShopSync v=72` records sent revision/size and client commitment. This is recovery hardening, not proof of native serialization limits or resolution of every CEM event family. Other rule/capability messages and the native server.dll final-score crash are unchanged.

## Equipment rewards

User requested a onefold increase, implemented as **two copies of every successfully rolled item**. Three original independent gates and their probabilities remain; a win can now earn up to six items. Gold, experience and life-loss rewards are not doubled. Existing queued rewards are not retroactively duplicated. Settlement lists earned items, including those waiting for inventory capacity.

A concrete early-neutral-in-midgame path existed: Wisp's one neutral slot was occupied, leaving old rewards queued until later. Before delivery, an unambiguous pending neutral below the current chapter tier upgrades to a same-category neutral at that tier. This applies to still-pending equipment/enchantment entries, never to already-held items; replaying an early chapter cannot downgrade an earned reward. Native tier progression remains every six chapters (1–6 tier1,7–12 tier2,13–18 tier3,19–24 tier4,25–30 tier5). Log records rolls, successful deliveries, one-time pending reasons and upgrades.

## Condition UI

Hidden native scrollbars in the rule list and condition settings body; scroll containers and mouse-wheel navigation remain. Removed the reserved scrollbar padding. Equipment-page scrollbar is unchanged.

## Verification/install

Offline **113/113 passed**, report `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui72-regression.json`. Coverage includes dropped/partial messages, receipt limits and owner validation, newer broadcasts versus old targeted snapshots, actual Lua→JS wire reconstruction, doubled reward settlement/queue counts, pending neutral upgrades/no downgrade, and scrollbar CSS.

Eight addon sources installed byte-identically. Native HUD JS127122bytes, transport JS4180bytes, HUD CSS69045bytes compiled successfully. Both installed locale markers match UI72. Backup `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui72-x51ws7pj`.

No game operations performed. Reload/recreate the addon session for native live verification. Do not claim inventory, neutral sales or final-score crash fully resolved based on offline tests alone.
