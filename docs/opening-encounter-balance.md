# Opening Encounter Balance

The runtime source is `game/dota_addons/dota2_rpg/scripts/data/levels.kv`.
`levels_v07.json` mirrors the opening enemy entries, but its historical reward
schema is not the runtime reward schema. `levels.json` is a legacy table, not
loaded by DataLoader.

## Composition

| Stage | Native neutral composition | Total | HP / attack multiplier |
| --- | --- | --- | --- |
| ch01 | centaur_khan x1, ogre_mauler x2 | 3 | 1.0 / 1.0 |
| ch02 | centaur_khan x1, alpha_wolf x1, ogre_mauler x2 | 4 | 1.1 / 1.05 |
| ch03 | centaur_khan x1, satyr_hellcaller x1, ogre_mauler x2, gnoll_assassin x1 | 5 | 1.2 / 1.1 |
| ch04 | centaur_khan x2, satyr_hellcaller x1, ogre_mauler x2, gnoll_assassin x1 | 6 | 1.35 / 1.2 |

All unit identifiers above have the `npc_dota_neutral_` prefix. Alpha wolves
and satyrs use the existing lowest-health attack profile; other units attack
the nearest enemy. Active neutral spell rules are not added by this change.
Native passive behavior still depends on the installed Dota version.

The intent is meaningful pressure on three approximately level-one allies,
with a large-camp frontliner and medium-camp bodies from the first stage.
These are provisional compositions, not measured win-rate guarantees.
Neutral `level` metadata does not level up creatures in the current spawn
path; native unit stats and explicit multipliers determine their strength.

Rewards, armor/resistance progression, timers, stages ch05 onward, player
progression, and all map geometry remain unchanged.

## Verification

Run `python tests/opening-balance.test.py` or `tests/verify-addon.ps1`.
Offline contracts check compositions, runtime/source agreement and rewards;
they do not simulate Dota damage, native passives, targeting or movement.

Engine acceptance remains tracked in beads: test three low-level allies with
starter equipment, record survivors, remaining HP and clear time, then test
focus fire and a stronger lineup. Tune the first stage before changing later
multipliers. Confirm all native units spawn and no later-stage difficulty
cliff is introduced. No editor or Dota combat run was available for this pass.
