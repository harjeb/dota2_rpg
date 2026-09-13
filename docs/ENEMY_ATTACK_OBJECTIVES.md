# Enemy hero priority: Tombstone and Supernova

Generated enemy hero AI now chooses a basic attack against an eligible opposing Undying Tombstone or Phoenix Supernova egg before ordinary spell/item/attack rows. The normal engine separately evaluates non-attack and attack rows, so prepending an attack alone was insufficient; the engine now explicitly evaluates this generated objective rule after its existing pending-cast/channel gates.

- Native names verified in installed `scripts/npc/npc_units.txt`: `npc_dota_unit_tombstone1` through `npc_dota_unit_tombstone5`, and `npc_dota_phoenix_sun` (Phoenix egg model).
- Acquisition: native enemy-unit query within 1,200 units, matching existing maximum chase distance. This avoids dependence on a hero-only observed roster.
- Same priority for both kinds; nearest first, entity-index tie-break.
- Requires a live, opposing, visible, non-invisible, attackable target. Invulnerable, attack-immune and out-of-game entities are rejected.
- Revalidates while chasing, switches to another eligible objective and falls back to normal rules when none remain.
- Does not interrupt pending casts/channels or bypass native control restrictions. Existing wait windows and exclusive movement remain authoritative.
- Applies to generated campaign enemies and arena preset defenders, not player default rules, creeps, authored arena defender rules or developer overrides.

## Validation and installation

`tests/enemy-attack-objectives.test.lua` exercises the actual engine, selector and action adapter with native API doubles: priority over a ready spell and existing hero chase, every tombstone name, egg targeting, nearest/tie selection, invalid/hidden/allied exclusions, target death, fallback and casting/channel/disarm guards.

Full offline suite: **108/108 passed**, report `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-objectives-regression.json`.

Four backend sources installed and byte-verified. Backup: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-objectives-btvpyen6`. Both installed locale files remain identical to repository UI70. No frontend change or compilation required. No game operations performed; actual native hit-count/pathfinding and gameplay response require user-driven verification after map reload.
