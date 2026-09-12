# Normal client stage preparation investigation — 2026-09-12

Issue: `dota2_rpg-bpgb` (open, diagnosis awaiting current console dump).

User reports missing resources and the HUD remaining at “正在准备本关资源” in ordinary Dota, outside Tools. No game process was launched/stopped, no gameplay commands or screenshots were taken, and no speculative runtime changes were made.

## Verified evidence

- Running Dota PID 7052 was started by Steam at 18:35:02. Its command line contains `-steam`, `-perfectworld` and the user's other existing options, but neither `-tools`, `-condebug` nor a VConsole port option.
- `game/dota/console.log` is 88,482 bytes and was last modified at 16:10:12. It predates this ordinary-client session and is not evidence of this failure. No newer `.log` exists under the game installation. A read-only connection attempt to localhost:29000 timed out; the process listener inventory did not list that port.
- Steam `logs/workshop_log.txt` records item `3799645167` requested at 18:44:18 and successfully downloaded at 18:44:21, manifest `8736555878857445817`. Earlier downloads at 18:36/18:39 also succeeded.
- Downloaded archive: `steamapps/workshop/content/570/3799645167/3799645167.vpk`, 15,302,423 bytes, modified 18:44:19. A publish copy exists under `game/dota_addons/vpks/3799645167/`.
- Parsed all 137 entries in the downloaded VPK and compared the repository's game-addon files byte for byte. All are present and identical (the VPK root directory is encoded as the standard single-space sentinel). This includes every Lua module, `levels.kv`, hero/item/loot/enemy AI data, custom NPC definitions and localization. There is no evidence of missing source files or old Lua in this downloaded package.
- Every repository game/content source file also matches the installed loose addon directory. The installed map VPK is 3,124,596 bytes, modified 18:32:24; its directory includes map, world, entity, model, physics and navigation entries.

These checks establish deployment contents, not which archive manifest an already-running server mounted or whether native precache callbacks completed.

## Code boundaries for the next log

`rpg_demo_hud.js` displays this exact text when the server sends `stage_loading=1`. It is not Steam's download-progress text. `AwaitEnemyResources` sets the flag while waiting, and `SpawnLevelEnemies` also sets it around enemy assembly. The first configured stage is seeded ready, so an initial-stage failure should not automatically be attributed to later-stage async resource loading.

`battle/stage_precache.lua` logs resource start/completion/failure and stage observer failure. Timeout is 30 seconds on the game scheduler after the native call returns; it cannot interrupt a blocking native call. A callback observer exception can also prevent the final battle-state broadcast. These are diagnostic possibilities, not established causes of this incident.

## Additional symptom: skill debug hero list

The user also reports “正在获取英雄列表” in the skill-debug panel. `skill_debug.js` sends `rpg_debug_request` both on script initialization and whenever the panel opens. The server listener in `battle/skill_debug.lua` calls `Debug.Publish`, which reads the already-loaded hero pool plus `debug_heroes.kv` and returns `rpg_debug_state`. It does not wait for hero models or stage precache. Therefore repeated list loading is additional evidence to investigate server initialization, event dispatch, player identity and reply delivery before attributing both symptoms to missing models.

The request listener is installed near the end of `InitGameMode`, after recruitment and tactic-bridge installation. It ignores requests unless the engine-supplied PlayerID equals the initialized game owner; publication also requires `PlayerResource:GetPlayer` to return a player. An empty catalog can produce the same UI placeholder. No current console dump was present on the follow-up check. These paths narrow the investigation but do not establish which one failed in the reported session.

## Required evidence to continue

In the current ordinary-client console run `condump`. The installed engine includes the command and output filename pattern `condump%03d.txt` (its help mentions `.log`, but its filename format is `.txt`). Inspect the newly written file under `game/dota/` for Lua stack traces, `[RPGTrace]`, `[RPGPrecache]`, `StagePrecache`, `stage observer failure` and resource errors. Console availability and whether it contains remote-server Lua messages must be assessed from that actual output.

If console dumping is unavailable or lacks startup history, add `-console -condebug` to the existing Steam launch options for a subsequent user-run ordinary-client reproduction. Retain the existing launch options and omit `-tools`. Do not infer a successful gameplay fix from offline mocks or unchanged deployment hashes.
