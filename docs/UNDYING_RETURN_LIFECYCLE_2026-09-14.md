# Undying native return: September 14 follow-up

Issue: `dota2_rpg-siv7`. No game operations or live commands were performed. No UI changes.

## Read-only evidence

Source: installed `C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota/console.log`, September 14. Exact selected lines are preserved in `tests/results/undying-return-evidence-2026-09-14.txt`.

- Lines 7775–7776, t=1217.03: entity 469 dies in fight; `IsReincarnating=false`, native Undying return buff present, `allow=true`, `disabled=false`, global respawn enabled.
- Lines 7847–7848, t=1219.03: the same entity returns alive after the native two-second delay, but `outofgame=true`. The return buff is gone. Modifiers include the innate, an empty modifier name (possibly an in-flight native removal; not identified), and `modifier_fountain_invulnerability`.
- Lines 7852–7854 and 8012–8014: AI correctly rejects spells/attacks as `caster_out_of_game`, including over five seconds after return.
- Line 8086, t=1227.833: entity remains alive/out-of-game with innate, fountain protection, and tactics event modifier when the next preparation removes it.

This disproves the earlier hypothesis that denied respawn permission alone caused this observed recurrence. Native rebirth already succeeds; action legality remains blocked. Persistent fountain protection is the identifiable spawn-only residue, and the existing retained-Wyvern lifecycle already removes this exact modifier after native respawn. The log does **not** prove this modifier is the sole source of out-of-game state. No claim of verified live recovery is made.

## Narrow implementation

`battle/respawn_policy.lua` records an Undying-specific pending return only for a current roster death in fight with the native return buff. The next roster spawn consumes that token. During fight, `issue_fixes/undying.lua` removes only `modifier_fountain_invulnerability` if the entity is alive, is Undying, and the native return buff has already ended. Before/after cleanup diagnostics expose native out-of-game state and modifier lists.

No damage simulation, manual respawn, forced orders, generic purge, native return-buff removal, ability/item rewrite, cooldown reset, AI legality bypass, or new timer. Other heroes, ordinary cooldown-spent deaths, initial/repeated spawns, active native return buffs, and late settlement returns retain their existing behavior. Settlement containment is unchanged. If the return buff still exists at spawn, cleanup is deliberately refused rather than ending native lifecycle early; this unobserved ordering would need separate evidence.

## Offline verification

Runtime: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-lua515-4lsm6zwd/lua.exe`.

- `tests/respawn-policy.test.lua`: 17 passed, 0 failed.
- `tests/undying-preparation.test.lua`: passed.
- `tests/eldwurms-edda.test.lua`: passed (existing analogous cleanup regression).
- Regression sensitivity: copied module tree to an isolated temporary directory, replaced only respawn policy with pre-change `HEAD`, ran current tests: 16 passed, 1 failed (new confirmed-return regression). Working files were not rolled back.
- `git diff --check`: passed (existing line-ending warnings only).

Tests prove scope, sequencing, state preservation, and the cleanup call, not native modifier semantics. The test also preserves an unrelated mocked out-of-game modifier to ensure no broad state bypass.

## Remaining user-run verification

On a future user-controlled game, confirm `undying_return_before_cleanup` shows fountain protection/out-of-game and `undying_return_after_cleanup` removes that protection and reports `outofgame=false`. Confirm real native attack damage and cast effects after return, not merely submitted orders; cooldown remains spent and a subsequent ordinary death does not grant another return. Confirm deadline/settlement containment. If out-of-game remains, collect the before/after modifier snapshots and keep investigating rather than claiming this fixes the root cause. No game session has been started, stopped, or controlled by this work.
