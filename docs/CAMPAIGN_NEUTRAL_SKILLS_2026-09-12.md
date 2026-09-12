# Campaign neutral skills — 2026-09-12

Implemented under `dota2_rpg-3ipt`; native acceptance remains `dota2_rpg-9rou`.
Runtime marker: `rpg-runtime-v44-20260912 neutral-skills-v2`.

## Coverage and native data

The active `levels.kv` uses 15 neutral types. Historical `levels*.json` adds seven types. All 22 now have custom `npc_dota_creature` definitions, plus the skeleton created by native Raise Dead. The sandbox definition is preserved.

`scripts/build-campaign-neutral-units.py` generates those definitions from the compact checked-in `scripts/data/campaign-neutral-native.json`. It preserves native ability slots, passive abilities, projectile/model data and combat fields. Only `BaseClass` changes; native `TeamName` and `IsNeutralUnitType` are omitted so battle creation supplies the team. The native unit names remain stable for existing level files.

The snapshot contains the selected installed native unit and ability definitions with source hashes. Raise Dead lives in `scripts/npc/heroes/npc_dota_hero_troll_warlord.txt`, not the monolithic ability file. No active ability contracts remain unresolved. Refreshing supports `--extract UNITS ABILITIES --extra-abilities TROLL_HERO_FILE`; normal generation and `--check` need no Dota installation.

Historical `npc_dota_neutral_hellbear_smasher` is absent from installed native units; it explicitly aliases `npc_dota_neutral_polar_furbolg_ursa_warrior`. Furbolg Champion itself has native Endurance Aura and Enrage Attack Speed passives, not Thunder Clap. Native `neutral_upgrade` is preserved, including on the previously customized Khan and Ogre. Ogre's former custom 200 mana is restored to native zero; Smash costs zero mana. Other previously omitted native fields and slots are restored as well.

## Active skill routing

| Native skill | Target/order policy |
| --- | --- |
| Khan War Stomp | No target; at least one enemy in native radius 250 |
| Ogre Smash | Point order; nearby enemy in native radius; refreshed cursor 16 units along current facing |
| Thunder Lizard Slam | No target; at least one enemy in native radius 350 |
| Thunder Lizard Frenzy | Friendly unit; native range and target validation |
| Black Dragon Fireball | Enemy position; native range and location validation |
| Troll Raise Dead | No target while an enemy is alive; native castability |
| Ice Shaman Incendiary Bomb | Enemy unit; native range and target validation |
| Satyr Shockwave | Enemy position; preserves its directional cursor |
| Harpy Chain Lightning (historical roster) | Enemy unit; native range and target validation |
| Ursa Warrior Thunder Clap (historical roster) | No target; at least one enemy in native radius 300 |

Radius values are read from the native ability handle, including its special value when `GetAOERadius` is unavailable/zero. Passives and auras are initialized through existing creep preparation and never become active cast rules. The native Troll's empty first ability slot is retained; scanning continues to Raise Dead in the next slot.

Raise Dead's installed contract is no-target, three skeletons, 35-second duration, 50 mana and 20-second cooldown. It declares no corpse requirement. An uncontrollable enemy skeleton may enter scripted combat only when its native owner chain resolves to a registered enemy Troll. That path initializes its native abilities through creep preparation, issues normal attacks and uses existing stage cleanup. Late owner assignment is retried by the existing summon scan. Matching unit names alone never fabricate ownership.

Ogre's old self-position snapshot could become a rear cursor as it moved. Selection and submission now use the current normalized forward vector; submission refreshes both origin and facing before validating the exact point. This remains an Ogre-specific mitigation. It does not establish native zero-range acceptance, cast start or final turning behavior; those require native observation.

## Verification and deployment

- `python scripts/test-all.py`: **83/83 offline groups passed**, including every native active contract through generated rules, target selection and order submission; sparse slots, radius gating, native castability, summon ownership/cleanup and Ogre cursor refresh/rejection.
- `python scripts/build-campaign-neutral-units.py --check`: all 22 campaign types and 23 creature definitions covered.
- `git diff --check`: passed.
- Six runtime files deployed into the local Dota addon and all six SHA-256 hashes matched. Exact hashes, destination and prior-file backup are in `tests/results/neutral-skills-deploy.json`.
- Prior-file backup: `C:/Users/harjeb/AppData/Local/Temp/rpg-neutral-skills-v2-backup-20260912-164713`.

These checks validate definitions and scripted order behavior using offline native-API doubles. Actual cast phases, cooldowns, mana, effects, Ogre first-cast facing and native skeleton ownership/passive effects remain the acceptance scope of `dota2_rpg-9rou`. Reload the addon session to load the new unit KV. No Dota launch/close, gameplay command or screenshot was performed. The earlier stale legacy verifier literal check remains tracked separately under `dota2_rpg-je8k`.
