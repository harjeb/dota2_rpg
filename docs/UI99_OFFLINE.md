# UI99: offline results and removal of external networking

Campaign completion now calculates and displays only the current run's local score. Permanent score/speedrun tables, personal/global ranks, record congratulations, submission states and their HUD controls have been removed. The addon no longer uploads scores or reads player Steam identity for results.

Arena HTTP matchmaking, remote rating/profile persistence and hosted team export have been removed. Local preset practice remains in the retained arena module; the existing main HUD still starts in campaign mode with the arena entry closed. Obsolete client capabilities cannot re-enable formal matches or exports. Native game-to-HUD events remain necessary for local gameplay.

Removed the endpoint configuration, upload/retry implementation, HTTP callback publication queue and unused SteamID utility. Local accounting is named `runResults`; terminal/reconnect/replay publication uses `rpg_run_result`. Both locale build markers are **99**, and difficulty help now describes offline scoring.

This change concerns addon runtime networking. Historical reports, development research tools and the private backend archive are not runtime dependencies; no remote Worker or stored data was deleted, and no Workshop publication was performed.

## Validation

- Offline regression report: `tests/results/ui99-regression.json`, **148/151** groups passed, including all Lua and JavaScript groups and source syntax gates. The AoE Python test passed after making portable Lua visible on PATH.
- The remaining three Python failures also reproduce from a clean archive of parent commit `cf2f363`: campaign loot native-source checksum mismatch, stale generated condition-help data, and changed native equipment prices. Follow-up: `dota2_rpg-ruan`.
- Local result tests cover score/difficulty scaling, duplicate settlement, defeat, terminal events, owner-only resend and replay isolation while forbidding HTTP, identity reads and network retry timers. Arena tests cover local practice and refusal of stale online start/export requests.
- Compiled the five changed Panorama resources successfully: HUD XML, campaign and arena JavaScript, HUD CSS and fantasy CSS.
- Installed to the local Dota addon. Verified hashes for 123 game source files and 29 content source files; both installed locale files match. Removed the obsolete installed `leaderboard_config.lua`. Reinstalled and rechecked locales after correcting difficulty help.
- Existing legacy `tests/verify-addon.ps1` static checks are separately tracked in `dota2_rpg-qi4t`.

Dota was not launched or controlled. Native end-of-run stability and the visible UI still require a fresh user-run game; this removal does not establish the cause of earlier engine crashes.
