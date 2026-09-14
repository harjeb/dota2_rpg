# UI73: central battlefield +30% on both axes

- Previous inner dimensions: 2400 × 1350.
- New inner dimensions: 3120 × 1755 (width ×1.30, height ×1.30; area ×1.69).
- Center remains (0, 0), ground Z=128. Bounds: X ±1560, Y ±877.5.
- Updated four collision walls, four NONAV perimeter slabs, 28 decorative rocks, min/max markers, Lua fallback bounds and preparation movement clamps. Wall thickness and rock model scales are unchanged.
- Terrain, player starts, bench positions, lighting and combat spawn definitions were not resized. Existing temporary middle divider uses map marker height automatically.
- `scripts/update-arena-map.py` sets absolute dimensions and synchronizes the issue-fixes overlay; repeated runs do not multiply the expansion.

## Verification and installation

Full offline suite: **115/115 groups passed**, report `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui73-regression.json`. VMAP tests verify exact wall/slab extents, decorative placements, marker bounds, width migration and idempotence. Default-boundary and preparation-clamp Lua assertions were updated to the new dimensions.

Native resourcecompiler rebuilt the installed map: **19 compiled, 0 failed**, including physics and gridnav. Installed `maps/dota2_rpg_demo.vpk`: 3,133,816 bytes, compiler-reported MD5 `48fb94660ee785b0b6a32979a9f1a912`.

Five changed addon sources byte-match the installed addon, including both locales with UI73. Backups of previous map source/VPK, Lua/locale sources, compile log and manifest: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-arena73-er8tbrmf`.

No game session was launched or controlled. Reload the map to load the newly compiled perimeter; visual appearance, pathfinding at the expanded edges and preparation divider behavior still need user-driven gameplay verification.
