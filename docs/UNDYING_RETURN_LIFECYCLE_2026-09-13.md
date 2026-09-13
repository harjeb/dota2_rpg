# Undying native return lifecycle investigation (UI68)

Issue: `dota2_rpg-y89l`. Base: `df6116e`. Backend changes only; UI remains 68. No game operations were performed. Main-agent delivery installed and byte-verified the changed backend files alongside network recovery changes; both installed UI68 locales match. Backup: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-return-network-h6zdcec4`. The combined offline suite passed 104/104 groups; live verification remains outstanding.

## Observed failure

Read-only source: `C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota/console.log`, 2026-09-13 17:10–17:11. Selected exact lines with original line numbers are retained in `tests/results/undying-return-evidence.txt`.

- Line 88047: lineup Undying entity 850 is alive and not out of game. Initial native modifier is `modifier_undying_ceaseless_dirge`.
- Line 88050: preparation adds invulnerable, disarmed and silence; no out-of-game modifier is recorded.
- Lines 88158–88284: the same entity successfully submits attacks after battle start. Preparation disables are removed by `OnStartBattle`.
- Line 88290, game time 22.77: death on entity 850 reports `reincarnating=false allow=false disabled=true`, although global hero respawn is enabled.
- Line 88333, game time 24.77: native spawn arrives for entity 850; policy restores permission in the fight.
- Lines 88336–88577, game time 24.93–40.03: AI repeatedly rejects the same entity with `caster_out_of_game`. AI still tracks and evaluates the original entity. This is not evidence of an entity replacement or lost roster membership.

The current native ability snapshot in `data/native_skill_conditions.json:83780` declares `respawn_delay=2.0` and a 480-second cooldown, matching the observed death/spawn interval. A read-only ASCII-string scan of installed `game/dota/bin/win64/server.dll` confirms the native intrinsic `modifier_undying_ceaseless_dirge` and separate `modifier_undying_ceaseless_dirge_buff` (`CDOTA_Modifier_Undying_CeaselessDirge_Buff`). Binary string names do not prove modifier timing or implementation semantics.

## Change

`issue_fixes/undying.lua` exposes a narrowly scoped pending-return predicate: actual Undying plus the dedicated native return buff. The permanent intrinsic, ability readiness and cooldown are deliberately insufficient; readiness may already have been spent when `entity_killed` arrives.

`battle/respawn_policy.lua` shares a native-return predicate between death handling and `battle_manager.lua` wipe detection. It accepts either native `IsReincarnating()` or Undying's dedicated return buff. A pending native return during a fight retains respawn permission and does not count as a team wipe. Ordinary deaths still disable automatic respawn; settlement still disables all roster heroes, and the 120-second deadline still wins over pending returns.

Death/spawn diagnostics now include alive/out-of-game state, return-buff classification and modifier names. Native respawn, native modifiers, cooldowns, health/mana, items, entity identity, AI rules and the out-of-game order gate are preserved. No manual resurrection or broad modifier removal was added. `OnNpcSpawned` still handles roster heroes before commander conversion. The deferred movement patch was not applied.

## Validation and limits

Using `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-lua515-4lsm6zwd/lua.exe`:

- All 74 `tests/*.test.lua` suites passed.
- `tests/respawn-policy.test.lua`: 15 cases passed, including false-reincarnation-flag Undying returns on both teams, ordinary second death with only the intrinsic, wrong-hero rejection, deadline and late-spawn containment, Wraith King/Aegis, identity/state preservation and stale/non-roster exclusions.
- The updated regression run against HEAD versions of respawn policy and battle manager in a temporary copy fails the new Undying permission/wipe case (14 pass, 1 fail).
- Existing preparation cooldown and real root lifecycle suites passed.
- `git diff --check` passed (only existing Windows line-ending conversion notices).

This fixes the policy's missing native-return classification under the active-buff contract. The existing console does **not** record which native modifier is present during the death/spawn callbacks, nor prove that disabling respawn is the sole cause of the persistent out-of-game state. The mocked tests cannot establish either fact. Live resolution of the user-visible inability to act is therefore not claimed as proven. Follow-up `dota2_rpg-siv7` tracks user-run verification of callback-time buff presence, successful native buff exit and resumed actions, spent-cooldown death, and deadline containment. The added diagnostics make that remaining boundary observable without stripping native states speculatively.
