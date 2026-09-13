# Snapshot state publication and reconnect recovery — 2026-09-13

Issue: `dota2_rpg-zely`, discovered from `dota2_rpg-pt4x`. Backend change based on HEAD `df6116e`; UI remains 68. No game operations were performed.

## Scope

`addon_game_mode.lua` now starts a publication window when rebuilding the player roster or spawning level enemies. Repeated battle, level, hero/capability, shop and damage publication requests in that window collapse by state family. Serialization happens on the following scheduled server update (the existing 0.1-second think interval), after entity construction. While asynchronous enemy preparation is pending, the window waits for its existing completion/failure flag. The delay is a scheduling boundary, not a guessed network size limit.

Payloads are built from live state when the window flushes: no saved entity handles, serialized rule lists, or rule generations are cached in the queue. Hero slots and their per-action capabilities are emitted together with matching capability revisions. This reduces repeated capability discovery/publication as well as repeated shop serialization. Unrelated later updates still publish normally; there is no permanent content cache that could suppress a reconnect response.

The existing `player_connect_full` listener now requests full state recovery. The existing HUD `rpg_request_battle_state` handler queues the same recovery using engine-supplied `PlayerID`. Requests for the same player in one window merge. Recovery sends battle/level state, enemy roster, hero slots, capabilities, saved rules, shop/inventory state, and available damage statistics to that player. A pending global publication already covers that family for a reconnecting player, so it is not sent twice in the same flush. The capability catalog accepts an optional recipient while retaining its existing broadcast default.

The latest campaign settlement is retained for recovery only while the server is in result phase and its settlement generation still matches. Existing leaderboard result recovery remains in use. Resending display state does not award gold, XP, loot, or restore/reset rules. Normal settlement events and sale/rule acknowledgements do not enter the replaceable-state queue. State serialization failures are isolated through the existing lifecycle error reporter and retried on a later update; other families continue. A missing recipient is skipped rather than converted to a global send.

## Offline validation

Portable Lua 5.1.5: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-lua515-4lsm6zwd/lua.exe`.

- All 75 Lua test files pass, including the new `tests/state-publication.test.lua`; all 13 JavaScript test files pass. The Lua suite was run once, then the affected fixture failures were fixed and those tests rerun. Existing progression/precache fixtures now provide the scheduler required by real roster rebuilding; the specified-enemy serializer fixture accepts the recipient parameter and state sender.
- The new deterministic fixture uses five allied and four enemy units, each with two basic actions, real state serializers and the real capability publisher. A modeled reset sequence of three hero-state requests, two shop requests, one level request and one battle request emits **88 events immediately before batching versus 31 after batching** (57 fewer, approximately 65%). No replaceable state is emitted during the reconstruction update. These are fixture event counts, not measured engine bytes or a replay of the incident log.
- Repeated connect/HUD requests emit one complete **32-event targeted recovery** in that fixture, with no messages to the other player. Tests verify current entity identities, saved rule edits/generations, matching slot/capability revisions, overlapping global requests, asynchronous preparation, settlement generation rejection, departed recipients and recovery from a transient serializer failure.
- The real `SpawnLevelEnemies` entry point is exercised with native assembly stubbed: duplicate assembly publications are held until completion and emit one hero state family. Nonreplaceable sale replies and settlement events remain immediate during the pending window.
- Existing shop-transition tests preserve single settlement/reward execution and final damage statistics. Their pre-existing mock omission for `battle.item_cooldowns` logs a caught lifecycle error but does not fail those tests.

## Limits and follow-up

This does not identify or fix a proven native snapshot root cause. The incident's `SendData reliable data too big (4401)` remains unassigned to a specific entity update or custom event; the number is not treated as a byte limit. Individual payloads are not split, entity reconstruction is unchanged, and one coherent roster publication can still contain many capability messages. Actual reduction depends on the live roster/action count and the order of subsequent engine inventory callbacks.

Recovery runs after Dota reconnects the player, or after the existing HUD state request. There is no engine reconnect command, automatic reconnect claim, or guarantee that a failed native snapshot/session can be resumed. No live reconnect or ch12 replay was attempted. Awaiting stage resources also delays the queued HUD snapshot until that preparation completes or fails; server-side start validation continues to reject an unprepared stage.

Main-agent validation passed all 104 offline test groups, with the final expanded publication regression also passing. Five backend sources, including the Undying lifecycle change, were installed and byte-verified; both installed UI68 locale files match. Backup: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-return-network-h6zdcec4`. Full-suite report: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-return-network-regression.json`.

Implementation issue `dota2_rpg-zely` is complete; parent `dota2_rpg-pt4x` remains open for user-run snapshot/reconnect verification. The deferred numeric movement-flag change and pre-existing dirty report/install files were not changed.
