# UI100 — debug reset and restart

The debug dialog previously disabled Reset during combat. Its server handler also preserved learned skills and authored conditions, making it unsuitable for a clean skill/condition reset.

UI100 provides two controls, both available during an active test in preparation, combat, or results:

- **Restart (keep build)** immediately stops the test and returns to preparation, retaining learned skills, talents, conditions, selected hero, enemy damage, and equipment. It uses the existing roster preparation/cooldown refresh path.
- **Reset current test** immediately stops the test, captures and detaches equipment, removes the old hero, refunds the level-30 skill points, and recreates the selected hero with fresh skills/talents and generated default conditions. Equipment and enemy damage remain. The rule generation advances so client drafts/import intent from the previous configuration cannot restore stale conditions.

Successful reset/restart closes the debug dialog and condition editor to reveal preparation. Pending requests prevent duplicate clicks. Both actions enforce the existing engine-provided player ownership check, invalidate prior settlement callbacks and cast observations, and use battle/respawn cleanup before rebuilding. Automatic post-result preparation continues to preserve the build.

Explicit reset bypasses the retained Winter Wyvern entity so native learned talents and Edda ability upgrades cannot survive a requested skill reset. Native consumed Edda skill upgrades are consequently cleared; held equipment remains. Restart continues using the existing retention behavior.

## Verification

Nine focused offline test groups passed: debug Lua (25 cases), debug Panorama in both languages, hero ability policy, Edda, item cooldowns, respawn policy, condition UI, rule library, and rule-library/HUD integration. Evidence: `tests/results/ui100-debug-reset.json`. New coverage exercises resets in setup/fight/result, preservation on restart and automatic return, stale result callbacks, refunded skills/talents, default conditions, equipment identity, in-fight buttons, duplicate-request suppression, and successful dialog closure.

Installed to the local Steam Dota addon and compiled the changed XML, JS, and CSS. Verified 123 game and 29 content source hashes including both UI100 locale files. No Dota process was started or controlled. Native in-game rendering, ability charges, and complex hero native behavior still require a user-run game; mocked tests do not prove those engine behaviors.
