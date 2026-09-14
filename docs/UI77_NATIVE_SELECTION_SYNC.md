# UI77 — native HUD / custom equipment selection synchronization

Issue: `dota2_rpg-el65`. No game launch/stop or in-game commands performed. Offline deployment is verified separately below.

## Diagnosed failure

The September 14 console showed a Windrunner hero-name target at 21:11:53, then shop opening at 21:11:58 read native portrait entity 70 (Leshrac) and overwrote that target. Transaction 4 (Mithril Hammer) was preflighted, charged and delivered to Leshrac. This was a pre-order selection disagreement, not post-order delivery rerouting.

## Contract

- Native portrait selection is the purchase authority. Native roster selection updates the equipment portrait and, for fielded heroes, the action editor selection. Bench selection updates equipment without selecting an unrelated action hero.
- Clicking a custom equipment/action portrait selects that exact native entity. Intent is recorded before `SelectUnit`, so synchronous callbacks or a temporarily stale native portrait cannot undo the click.
- Custom rendering, roster snapshots, and inventory refreshes no longer send competing hero-name target messages. Selection polling also works while the shop is closed.
- The existing native shop remains responsible for purchases, pricing, charging and combining. The necessary automatic Wisp selection carries an explicit `shop_carrier` marker while retaining the effective roster recipient. Shop close restores the latest effective hero. To deliberately target Wisp/public inventory, close the shop and then select Wisp. While the automatic carrier marker is active, reselecting already-selected Wisp cannot safely be distinguished from delayed engine notifications, so it retains the hero recipient. Hero target buttons remain available when Wisp is selected.
- There is one sequenced HUD target stream per run generation. The sequence is encoded as a string to avoid transport numeric precision loss and retained in `GameUI.CustomUIConfig` across HUD reloads. Backend validates owner, generation and increasing sequence, retains existing carrier validation, and rejects stale/duplicate messages. Once this protocol is active, unsequenced hero-name publications and raw engine selection notifications cannot overwrite either recipient or native-carrier binding. Legacy clients keep the previous fallback path until the ordered protocol is seen.
- Component purchases still snapshot their recipient in the existing native purchase order contexts. There is no manual ordinary-item purchase implementation, and existing paid-delivery/combination retry logic is unchanged.

## Asynchronous handling

Custom selections wait up to five 0.2-second checks for native acknowledgement. A genuinely different native selection wins. Superseded programmatic entity selections are remembered for one second; an old completion cannot override a newer request, including reverse completion order. Delayed automatic Wisp completion after a genuine different native selection is likewise guarded. Shop selection-induced close/reopen remains bounded and restores only when still on the expected carrier. Phase/generation changes invalidate outstanding work.

Panorama does not expose a reliable click-origin token for selected-unit notifications. All Wisp notifications retain the marked hero for the entire automatic-carrier lifetime, including delayed/duplicate events after settlement. Event counts are not used to infer clicks. This deliberately requires closing the shop before explicitly selecting Wisp as recipient; it prevents an indistinguishable late automatic notification from redirecting purchases. Similarly a genuine click on an entity with an outstanding superseded `SelectUnit` during the bounded one-second guard is indistinguishable from its stale completion. These timing boundaries require live validation; offline tests are not evidence that every engine notification ordering is covered. An order arriving before the native selection notification/CEM reaches the server also cannot retroactively change an already snapshotted transaction.

## Offline verification

- All 17 `tests/*.test.js` suites passed.
- Actual complete HUD/layout mocks in `hud-sidebar.test.js` cover the Windrunner/Leshrac mismatch, clicking custom Windrunner before shop opening, native bench switching, automatic carrier preservation including three duplicate post-settlement selected-unit notifications, explicit Wisp after closure, four inventory/component-refresh cycles without drift, no render-time publication, increasing sequence, old portrait during asynchronous custom selection, and forward/reverse completion ordering.
- `panorama-save.test.js` now checks the entity-based ordered bench target instead of the removed hero-name message.
- Backend `shop-state.test.lua` adds ordered target/carrier tests, duplicate/stale/wrong-generation/non-owner rejection, stale raw and hero-name publication rejection, three real native-order contexts retaining the bench recipient, explicit Wisp, later hero selection and invalid entities.
- Nine focused Lua suites passed with `LUA_BIN=C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-lua515-4lsm6zwd/lua.exe`: shop-state, native-purchase-delivery, native-purchase-combination, inventory-transfer, item-sales, shard-purchase, native-shop-range, shop-transition, shop-transport-recovery.
- `git diff --check` passed (existing repository line-ending warnings only).

## Deployment verification

- Full offline regression: **117/117 groups passed**, recorded in `tests/results/reliability-regression.json`.
- Installed HUD JS, server Lua, and both locale files by exact copy under `C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta`; source/installed bytes and SHA-256 match for all four files.
- Both source and installed locale markers are UI77 (`UI version 77` / `界面版本 77`).
- Offline `resourcecompiler.exe` returned exit 0: **1 compiled, 0 failed**. Installed `rpg_demo_hud.vjs_c`: 132490 bytes. Log: `C:/Users/harjeb/AppData/Local/Temp/rpg-ui77-compile.log`.
- No game launch/stop or in-game commands performed. Real shop opening/closing, native/custom clicks, deliberate Wisp selection after closure, multi-component purchases and live notification timing remain pending under follow-up `dota2_rpg-8lca`.
- Historical deployment reports were not rewritten.
