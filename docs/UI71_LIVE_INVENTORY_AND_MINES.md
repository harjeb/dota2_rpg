# UI71 — live inventory transport and proximity mine cleanup

## Live report and limits

User reported BKB on a hero while inventory pages retained Wisp ownership, Wisp stock refreshing only at the next preparation phase, unsellable neutrals, persistent Techies mines and missing mine damage.

Preserved initial log: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui70-live-g_8um8hz/console.8997185207.log`. BKB entity595 manually transfers Wisp191 → Tidehunter365 at 22:20:57; preceding component lookup warnings mean automatic routing still failed for that incident. This update addresses state delivery and does not establish that the prior combination qualifier handles that exact live batch.

Ten native `SerializeAbstract ... CUserMsg_CustomGameEvent [148] failed` messages occur at 22:16:52. They establish event serialization failure, but do not identify a particular payload or its engine size limit. The later final-score native crash is separate evidence: see `SCORE_CRASH_2026-09-13.md`.

## Inventory state

- Publish inventory/shop before hero capabilities. A hero publication failure cannot prevent the inventory publication.
- Acknowledge equipment signatures and broadcast gold only after successful publication/queueing, preserving retries on Lua send/serialization errors.
- Refresh hero inventory mirrors from actual units at serialization time, not merely when deferred publication is queued.
- Shop-only transport preserves small snapshots; larger snapshots are deterministic JSON split into UTF-8-safe 1,200-byte chunks, with one monotonic revision and run generation. The HUD applies only a complete snapshot atomically.
- Reject stale/duplicate/mismatched snapshots, bound assembly to one snapshot/512 chunks, expire incomplete assembly after 15 seconds. This threshold is deliberately conservative, not a measured native CEM limit.
- Regression rejects old oversized monolithic payloads with a fake silent native serializer, then reconstructs actual Lua-produced chunks in the JS assembler, including Unicode/control/escape characters.

## Neutral sales

Forager's Kit229 and Pogo Stick361 are present in the authoritative tier catalog. The log has no rejection reason; the earlier failed Kit sales demonstrably left its exact entity alive for subsequent transfer. It does not establish the failing native API.

Added transaction result telemetry (`RPGItemSale v=71`) and removal outcome diagnostics. If native RemoveItem leaves the exact validated neutral still in its original carrier, explicit UTIL_Remove is attempted. No fallback follows a detached/transferred item, and payment still requires confirmed destruction. No-op/error, reentrant/duplicate calls, and detachment are covered offline. This is compatibility hardening, **not proof of the live rejection cause or an in-game verified fix**. Tier prices remain100/200/400/800/1600. Deferred native destruction remains a verification concern.

## Techies proximity mines

Native `npc_dota_techies_land_mine` / `npc_dota_techies_mines` is a stationary NO_ATTACK spell unit. It was previously skipped by generic summon handling and thus not cleaned up. Dedicated lifecycle tracking now bypasses generic AI, scans the native class (including distant/missed spawns/delayed owners), and clears managed mines outside combat. Both battle teams and actual bench owners are supported; cleanup responsibility survives owner replacement. Unrelated/ownerless mines are untouched.

No fake damage, attacks, modifier replacement or ForceKill is introduced. The session shows `modifier_techies_land_mine_burn` on combat deaths, so universal absence of native effects is not established. The individual reported no-damage case remains open for live verification; preparation cleanup alone does not prove combat damage fixed.

## Verification/install

Full offline suite **111/111 passed**, report `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui71-regression.json`. Existing tracked historical report preserved.

Ten addon sources installed byte-identically; native compiler succeeded for HUD XML (6,946 bytes), HUD JS (127,003 bytes), transport JS (3,670 bytes). Both installed locales match **UI71**. Backup `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui71-s3pd_i5d`. Main installer updated to compile the new transport dependency.

No game operations performed. Re-enter/recreate the addon session to load new Lua and Panorama; a mere transition to another preparation phase is not sufficient. Native crash root cause, exact BKB batch automatic routing, neutral live rejection and individual no-damage reports remain unverified.
