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

## Stage Multi

Each runtime stage has `multi = 1 + 0.05 * (stage_number - 1)` (linear,
not compounded). This authored field can be tuned per stage in `levels.kv`;
keep `levels_v07.json` in sync and update the curve contract when tuning.
Missing, nonpositive or nonfinite values fall back to 1.

Only newly spawned non-hero enemies are scaled. Native maximum HP and base
attack are multiplied by `multi` before existing per-entry HP/attack
multipliers. HP is rounded to whole points. Base armor is multiplied by
`multi`, then `bonus_armor` is added. Zero base armor stays zero before the
bonus; negative base armor remains negative. Magic/status resistance, attack
speed, abilities, rewards and enemy heroes are not scaled.

For example, stage 4 combines `multi=1.15` with HP `1.35` and attack `1.2`:
about 1.5525x native HP and 1.38x base attack (subject to rounding), with
`native_armor * 1.15 + 3` armor. Scaling happens once on spawn, not each tick.

Run the runtime helper regression with Lua from the repository root:
`lua tests/enemy-scaling.test.lua`.

## Verification

Run `python tests/opening-balance.test.py` or `tests/verify-addon.ps1`.
Offline contracts check compositions, runtime/source agreement and rewards;
they do not simulate Dota damage, native passives, targeting or movement.

Engine acceptance remains tracked in beads: test three low-level allies with
starter equipment, record survivors, remaining HP and clear time, then test
focus fire and a stronger lineup. Tune the first stage before changing later
multipliers. Confirm all native units spawn and no later-stage difficulty
cliff is introduced. No editor or Dota combat run was available for this pass.
