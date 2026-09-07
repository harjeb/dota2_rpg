# Runtime Follow-up and Diagnostic Trace (2026-09-07)

Beads: `dota2_rpg-ch8`, discovered from `dota2_rpg-h2y`.

User retest after `01491e5`: bench/preparation native purchases appear free while active purchases charge; monsters still retreat; an attack in the first rule prevents later skills; collapsed tactic panels have no visible restore button. Additional request: refresh recruitment offers after advancing a stage or losing a fight.

## Confirmed Changes

- Editor restoration now uses dedicated root-level buttons outside the hidden editor. Their visibility toggles independently of the editor's size, header flow and clipping. Tests parse the real XML and assert root-sibling placement plus collapse/restore visibility for both teams. The previous nested-button CSS fix did not resolve the user's in-engine report.
- Returning from results to preparation rolls recruitment offers exactly once for free. Victory advances before rolling; defeat/timeout/draw refresh the retry stage. Duplicate callbacks and rejected settlements do not roll again; final victory stays terminal. Automatic retry refresh does not alter the existing manual-refresh counter policy.
- Runtime diagnostics use `AppendToLogFile` when available, writing `dota2_rpg_runtime.log` as well as the console, with game-time stamps. The helper caps diagnostic output at 1,500 messages per loaded session and falls back without disrupting gameplay if file logging fails. The installed `server.dll` exposes the `AppendToLogFile` name. Startup marker: `rpg-runtime-trace-20260907`. Actual file creation/location still depends on running the map; no runtime log is claimed to have been collected yet.
- UI toggles emit `[RPG][UI]` console messages. The visible build label is `UI version 5` / `界面版本 5`.
- Accepted native orders now reconcile from matching new item entities or increased stacks when no purchase event arrives. This is a tested missing-event recovery path, not proof that missing events caused the user's live bench report. Existing wallet decreases are consumed once across batches; repeated notifications without a matching preflight cannot cause another debit. Failed orders, unrelated items and consumed charges do not count as purchase evidence. Event-confirmed results reserve their evidence before silent orders inspect it. Stack evidence uses native `GetInitialCharges` when available so one three-charge bundle does not count as several purchases; its symbol is present in the installed server binary.
- Basic attacks are evaluated after authored non-attack rules. Skill/item order among themselves is unchanged; explicit wait and channel/cast protection remain. Attack chasing yields to a newly available skill anywhere in the list, and an earlier attack cannot interrupt a skill chase. New replacement chases are no longer cleared by the emergency-rule branch.
- Native-neutral tactic attacks retain their forced target instead of clearing it during handoff from fallback AI. Attack approaches issue attack-target orders. Skills/movement/wait release ownership, dead targets are cleared, and stopping battle releases both fallback and tactic targets. The neutral runtime reasserts an owned tactic target without replacing it with the nearest opponent. No global neutral AI convar, teleport correction or combat-modifier removal was introduced.

## Trace Fields

- `ShopTxn`: transaction ID, stage (`preflight`, `event`, `reconcile`, `debit`, `transfer`, `expire`), issuer, item, recipient, bench/active/stash location, wallet before/after, native/project/mixed debit decision.
- `ShopTransition`: result, previous/destination level, free refresh, offer count and retained/reset manual-refresh count.
- `Tactic`: unit, rule index, executed/skipped/chase event, action, target and skip reason. Identical per-rule events are throttled for five seconds.
- `EnemyMotion`: position, target distance and change, actual attack target, target owner, idle/stun/silence/cast state, sampled every two seconds. Increasing distance alone does not prove native retreat because the opponent may also be moving.

## Verification

`dota2_rpg_issue_fixes/tests/run_checks.py` passed: 53 Lua syntax checks, live/overlay runtime tests, wallet and native purchase cases, new shop-transition and logging tests, Panorama behavior/XML, installer, and VMAP tests (10 passed, one optional external provenance test skipped). `tests/verify-addon.ps1` passed. The missing-event cases include direct bench and active receipt, already-debited wallets, separate event/silent batches, identical same-recipient purchases, mixed and silent stack increments, multi-charge bundles, failed orders and duplicate/late events.

Formal local deployment uses `scripts/install-addon.ps1 -Compile`. Map compilation reported 19 compiled and zero failed; all eight explicitly compiled Panorama resources succeeded with no invalid-property report. Existing base-resource shader/file warnings persist (`generic.vfx`, `soundevents_test`, `surfaceproperties_steamaudio`, `nav_hulls`), tracked separately in `dota2_rpg-xrx`; this was not a warning-free compile. Build/test logs are in the backup directory below.

## Acceptance Boundary

No Dota client is launched or stopped by the agent. Automated regression tests and native resource compilation are not in-engine acceptance. The reported bench-charge and neutral-retreat mechanisms need the new trace to confirm their exact live cause.

Predeployment content/game backup: `C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_trace_20260907_224126`.

Final installed source verification: all 66 content/game files are byte-identical to the repository. The compiled map VPK is 3,123,798 bytes, SHA-256 `85ce05caf67c8f07e91b36ecba9c8cbbc53f5b98287be933aa276a4c9d4808e8`. The client was absent during backup and was neither launched nor stopped. Gameplay acceptance remains open in `dota2_rpg-ch8`; the next report should be correlated with this build's actual trace, not the old September 5 console log.
