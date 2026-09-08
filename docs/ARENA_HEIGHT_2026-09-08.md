# Arena height expansion — 2026-09-08

Beads `dota2_rpg-1d0`, discovered from `dota2_rpg-daj`. The authored playable arena changes from 2400×900 to 2400×1350: X stays −1200..1200, Y expands from −450..450 to −675..675, and ground Z stays 128. Each side gains 225 units. This is a top-down field dimension change.

| Geometry | New map-space extent |
| --- | --- |
| Arena markers | min `(−1200, −675, 128)`, max `(1200, 675, 128)`, center `(0, 0, 128)` |
| North collision wall | X −1224..1224, Y 675..707, Z 128..640 |
| South collision wall | X −1224..1224, Y −707..−675, Z 128..640 |
| East collision wall | X 1200..1232, Y −691..691, Z 128..640 |
| West collision wall | X −1232..−1200, Y −691..691, Z 128..640 |
| North/south NONAV slabs | center Y ±691, half-size `(1224, 32, 32)`, center Z 128 |
| East/west NONAV slabs | center X ±1200, half-size `(32, 691, 32)`, center Z 128 |
| Decorative rocks | north/south Y ±825; east/west X ±1350 and Y −540/0/540 |

The same 28 native rocks, four clip walls and four NONAV slabs remain. Wall thickness, source mesh vertices, materials, terrain tile grid, lights, player start entities, X coordinates and Z coordinates are preserved. No authored triggers or camera-bound entities require resizing; gameplay containment reads arena markers and Lua configuration. Existing arena spawn lanes fit inside the larger field. The bench center remains `(−2300, 0, 128)` with half-size `(520, 380)`, and stash/UI placement is untouched. Camera distance 1500 is retained; this does not promise that the entire arena fits a single viewport.

`scripts/update-arena-map.py` now sets these absolute Y dimensions and continues removing the obsolete permanent middle brush. It synchronizes the source VMAP and overlay and is idempotent. `tests/vmap.test.py` passes 11 tests with one optional external model-provenance test skipped. The new migration regression checks round-trip expansion, unchanged X/Z and all unrelated typed map data, plus idempotence. Collision and navigation slab tests check the actual transformed mesh extents.

## Runtime integration

The game mode and live/overlay arena controller now use half-height 675. Setup movement clamps Y to ±611 (64-unit margin), controller movement to ±627 (48-unit margin), and the middle row has 15 trees from Y −651 through +651 (24-unit endpoint inset, maximum gap 96). Runtime regressions cover these bounds, tree replacement/removal and repeated preparation/fight transitions. Existing spawn positions, bench bounds and camera distance remain as authored.

## Isolated native compile evidence

Existing `resourcecompiler.exe` compiled the map under temporary addon `dota2_rpg_arena_ff5d8beb2de0421495eb2e2db4e8951a`. Its isolated installed content/game directories were removed after copying out the artifacts. No active addon file was written, no deployment occurred, and Dota was neither launched nor closed.

Evidence directory: `C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_arena_ff5d8beb2de0421495eb2e2db4e8951a`.

| Artifact | Evidence |
| --- | --- |
| `compile.log` | Compiler exit 0; `OK: 19 compiled, 0 failed, 0 skipped`; world, physics, visibility and gridnav built; successful VPK write and check |
| `dota2_rpg_demo.vpk` | 3,124,853 bytes; SHA-256 `9991b68f0612abc324ede5872a2702a90e9c6d12625f298ae0db1cec77b17462` |
| `dota2_rpg_demo.vmap` | Expanded source; SHA-256 `65b2514e0c7a7a55df0047b2fb8ec2aa78dc284f7501c8294bae9121fcf3314c` |
| `manifest.json` | Compiler result, artifact hashes and before/after active VPK hashes |

During the isolated compile the active map was preserved. The final deployment replaced the installed VPK with the above artifact, verified all 74 addon sources byte-for-byte, and launched `rpg-runtime-v11-20260908` using `scripts/launch-addon.ps1`. The prior addon files, VPK and console log are backed up under `C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_runtime11_20260908_vgg884dm`. Read-only runtime inspection logged width 2400, height 1350, arena Y bounds ±675 and 15 preparation trees, confirming the expanded compiled map and runtime controller agree.

Compilation retains the known base-resource diagnostics concerning generic.vfx/dev materials, soundevents_test, surfaceproperties_steamaudio and nav_hulls, already tracked by `dota2_rpg-xrx`.
