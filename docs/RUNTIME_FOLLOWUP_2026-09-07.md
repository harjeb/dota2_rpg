# 2026-09-07 Follow-up Runtime Regression

Beads: `dota2_rpg-h2y`, discovered from `dota2_rpg-ylf`.

The user reported failures after the previous deployment: 500 gold became 980 after refreshing, native equipment purchases still failed, action/condition menus were unusable and had no skill icons, enemies returned to their spawn position, and one hero appeared silenced in the first battle.

## Confirmed Findings

- `ReadNativeGold` added `GetUnreliableGold()` to `GetGold()`, even though `GetGold()` already returns the total. A 500-unreliable-gold wallet was read as 1,000 and charged 20 for refresh. The regression fixture now exposes both APIs and proves 500 -> 480, including subsequent synchronization.
- The dynamically created action menu passed `"ActionMenu Hidden"` as one `AddClass` argument. The menu now receives separate class calls, and first-click visibility is tested explicitly.
- Action options only created text labels. They now create native ability/item images, localize names, and keep decorative children from intercepting button clicks.
- Menus used hard-coded old editor coordinates, omitted the action menu from floating-layer styling, and assigned CSS property values with a trailing semicolon. Positioning now uses the rendered button and actual UI scale, clamps to the viewport, and flips above buttons near the bottom. Rule scrolling closes any open menus.
- The former UI harness created empty placeholder snippet controls and did not assert visibility. It now parses the actual XML snippet with Python's XML parser and exercises real condition option callbacks, first-click opening, selection, icon creation, and scaled/edge positioning.
- Read-only inspection of the installed `client.dll` confirms the names `GetPositionWithinWindow`, `actualuiscale_x`, `actualuiscale_y`, `actuallayoutwidth`, and `actuallayoutheight` used by the positioning code are exposed in the current client binary. This is not a substitute for visual testing.

- Native purchases used `GetAbilityNameByID`, which is absent from the installed engine. The current VPK's authoritative mapping is `scripts/npc/npc_ability_ids.txt`, under `DOTAAbilityIDs -> ItemAbilities -> Locked` (Blink is ID 1). Resolution now loads/caches the item namespace through `LoadKeyValues`; `items.txt` supplies definitions/prices, not these IDs. Tests explicitly remove the invented APIs and cover real-shaped nested registries, recipes, newer IDs, unknown IDs, fractional IDs, namespace separation, caching, and retry after load errors.
- Native `npc_dota_neutral_*` templates retain autonomous behavior despite being spawned on Dire. Runtime combat now disables their idle acquisition and supplies a forced fallback attack target when no tactic/cast owns the unit. Non-idle returning neutrals can recover; moving heroes are not overridden. Targets clear on stop and before authored actions/approaches, including a different attack target or wait action. This mitigates native return behavior; exact in-engine pursuit still requires acceptance.
- The authoritative `OnStartBattle` path now removes `modifier_rpg_prepare_bench` from actual battle participants before starting the battle manager. The compatibility wrapper repeats that targeted release only after an accepted phase transition. Bench units remain restricted regardless of selected UI portrait. Runtime fallback cleanup no longer removes generic combat silence/stun/root/disarm effects. Tests cover release timing, rejected/repeated starts, selected-bench separation, preserved combat effects, casts, target death and tactic takeover. These are safeguards against preparation-state residue, not proof of the user's specific silence source.
- Startup logs now identify this source as `BUILD rpg-runtime-followup-20260907`.

## Verification and Deployment

- `python dota2_rpg_issue_fixes/tests/run_checks.py`: passed, including 50 Lua syntax checks, live and overlay runtime tests, native shop/wallet tests, authoritative battlefield transition tests, UI tests, installer tests, and VMAP tests (10 passed, one optional external provenance check skipped).
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-addon.ps1`: passed.
- `scripts/install-addon.ps1 -Compile`: deployed to the actual Steam Dota installation. Map summary: 19 compiled, 0 failed. All eight separately compiled Panorama resources succeeded; no invalid-property diagnostics were found.
- All 65 installed content/game source files are byte-for-byte equal to the repository after deployment.
- Installed map VPK: 3,123,798 bytes; SHA256 `c63fa2a246e2feb100fdd8166d166a122f1179f9fe26273a1e46baa276f3c7a3`.
- Full predeployment backup: `C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_followup_20260907_220556/content` and `/game`. Full compiler log is `compile.log` in that directory (PowerShell UTF-16 output).
- Compilation was not diagnostic-free: it printed `generic.vfx` errors for base developer materials and missing `soundevents_test`, `surfaceproperties_steamaudio`, and `nav_hulls` resources despite its zero-failed summary. Follow-up: `dota2_rpg-xrx`.

## Acceptance Boundary

Automated tests and resource compilation cannot establish live gameplay acceptance. The agent did not launch or stop Dota; no Dota process was present at the predeployment check. `dota2_rpg-h2y` remains in progress pending a newly loaded map confirming the 500 -> 480 refresh, purchases into the intended hero's equipment, condition and action/icon menus, continuous enemy pursuit, and the observed first-battle silence. Fielded heroes must release without selecting any portrait; a genuinely benched hero remains restricted. The user's specific silence source remains unconfirmed without a current gameplay trace.
