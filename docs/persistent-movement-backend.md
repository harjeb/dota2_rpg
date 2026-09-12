# Persistent movement and native-release positioning

## Capability boundary

Implemented in the production Lua engine, adapter, selector, rule service, snapshots and legacy importer. Tests execute these modules with mocked native APIs; **no Dota client execution has been verified**. No spells, damage, modifiers representing native buffs, teleports or motion controllers are fabricated. The only added modifier is a hidden, non-purgable event observer. Movement uses native move-to-position orders through the existing order gate.

The action catalog publishes `sustained_move` as kind `move`. The condition editor uses the **same flattened fields** below; real-HUD tests verify its controls and save/reopen flow. Structured rules put these fields under `rule.action`. `RuleService.DecodeFlat`, `SyncRule`, `Snapshot.ForHero` and `ConvertLegacyRule` preserve them. Snapshot target types/team, numeric disabled state and approach flags also survive legacy conversion.

## Wire contract

| Field | Values / default |
| --- | --- |
| `action_kind`, `action_id` | `move`, `sustained_move` |
| `movement_mode` | `follow` (default), `pass`, `orbit`, `cycle` |
| `movement_buff` | Required native modifier name; checked on caster with `HasModifier` |
| `movement_trigger_ability` | Optional native ability name; requires a NEW observed `OnAbilityExecuted` |
| `movement_duration` | Finite 0.1–60 seconds; default 8; wall-clock cap includes control pauses |
| `movement_distance` | 32–3000 units; default 250 |
| `movement_retarget` | Boolean, default true; explicit false is preserved |
| `movement_loop` | Boolean, default true; explicit false is preserved |
| `movement_interruptible` | Boolean, default false |
| `movement_direction` | `auto` (starts ccw, reverses on obstruction), `cw`, `ccw`; orbit direction |
| `positioning_mode` | `default`, `fixed`, `attack_range`, `cast_range`; default disables posture |
| `positioning_distance` | Finite 0–3000 units; default 250, used by fixed posture |
| `positioning_tolerance` | Finite 0–300 units; default 40 |

Flat booleans accept booleans, 0/1, or strings `0`, `1`, `false`, `true`. Unknown enum values, invalid booleans, non-finite/out-of-bounds numbers and malformed native identifiers are rejected by validation. Omitted retarget/loop fields default to true; explicitly stored false (including `0` and `"false"`) remains off through save, snapshots, legacy conversion and reopening. The example below deliberately opts out of both defaults.

Example flat rule:

```lua
{
    action_kind = "move", action_id = "sustained_move",
    movement_mode = "pass", movement_buff = "modifier_weaver_shukuchi",
    movement_trigger_ability = "weaver_shukuchi", movement_duration = 4,
    movement_distance = 250, movement_retarget = false,
    movement_loop = false, movement_interruptible = false,
    movement_direction = "auto", target_team = "enemy", target_types = "hero,monster,summon",
    target_priority_1_type = "nearest"
}
```

A separate ordinary native ability rule must cast the buff. The movement action never casts its trigger ability. Normally put the movement rule above the ability rule: it falls through until armed.

## UI52 authoring

Choosing a skill automatically applies its first recommended configuration to the draft. The user can then edit it and apply; reopening an existing rule preserves its authored settings rather than applying the recommendation again. Recommendations have no separate buttons or previews in the condition editor.

The red **重置** button at the top right (`V2ClearConditions`) clears all four use conditions, four target filters and two priorities. It resets skill switches to On where supported, restores the default destination and rebuilds movement/positioning fields from defaults. It preserves the selected action, target team and approach behavior. Reset changes the draft; Apply submits it and Cancel discards the current edits.

The single **开关技能** selector (`V2ToggleSelect`) offers On/Off for supported skills. Native Toggle maps to `desired_toggle_state`; native autocast maps to `desired_autocast_state`, with Toggle taking precedence if both are available. A missing state defaults to On; an explicitly stored Off survives reopening. Target types and cast mode are derived from native capability. There are no separate capability refresh/summary, target-type or cast-mode selectors, autocast/policy/hysteresis/hold controls, variant controls, or unverified-name acknowledgment. Only error feedback remains (`RuleSettingsError`). These backend fields are not additional user inputs in UI52.

The three **movement preset buttons remain** (`V2MovementPreset_shukuchi`, `_trample`, `_gyroshell`). They overwrite only movement settings in the draft, preserving team, conditions and priorities. **关联原生增益** (`V2MovementBuffSelect`) has only Custom; the adjacent status dropdown (`V2MovementStatusSelect`) selects an observed/declared native status and stores `movement_buff`. There is no raw modifier textbox. Condition status parameters likewise use status dropdowns. Unknown saved names remain visible as unavailable entries with a reason and must be replaced with a valid selection. Selecting a status changes only the buff, while a movement preset fills the whole movement configuration.

New movement drafts and all movement presets default `movement_retarget` and `movement_loop` to true. Explicitly switching either off remains preserved on save/reopen. Clicking a movement preset or Reset intentionally restores the corresponding defaults. The trigger ability remains an event reference and never casts the ability itself.

The standalone Chinese [condition settings reference](CONDITION_SETTINGS_UI_REFERENCE.html) documents every current control and all 85 named conditions, with offline search and printing.

## Session semantics

- Initial acquisition goes through the existing selector and all authored use conditions, target filters and priorities (including specified-enemy/F39 behavior). The persistent move has no spell cast-range restriction.
- Without a trigger ability, one buff episode arms one session. Termination cannot immediately restart the same episode. Observing buff absence re-arms the next episode.
- With a trigger ability, each rule baselines the observer's cast count on its first evaluation. A cast preceding that baseline is deliberately not eligible. New native cast observations can arm a session while the buff is present; issued-order history is never sufficient. New entities/stages start fresh histories. A buff loss clears pending readiness; delayed or entirely unobserved buff episodes are not reconstructed.
- Active movement is exclusive: ordinary skill/item/attack rules and fallback do not run. Native idle acquisition is disabled and its range set to zero until release; original acquisition settings are restored during battle, while preparation stays passive. Tiny's auxiliary tree cast observes the same exclusive state. Only `movement_interruptible=true` permits an executable higher-priority non-attack rule to interrupt. Its new cast is not cancelled by a cleanup STOP.
- Active sessions recheck authored use conditions and target filters. A target stays locked within its current leg. Loss of eligibility, death, null handle or out-of-game state ends the session unless explicit retargeting finds another eligible target. Buff loss, timeout or persistent navigation failure also ends it; later rules can run in the same evaluation.
- `follow` approaches within the requested distance. `pass` crosses the target. `cycle` crosses each eligible unvisited target in turn using the existing selector; looping resets the visited set after all are visited. Cycle advancement is explicit in this mode and does not require the invalid-target retarget toggle. F39 still constrains every selection. `orbit` follows collision-hull-aware radius waypoints; automatic direction can reverse on obstruction/stalling. Nonloop orbit completes one revolution. Native navigation still determines the actual path.
- Root, stun, frozen, command restriction, out-of-game and native channel/cast-phase checks remain authoritative. Control pauses movement orders; timeout still expires. There is no attempt to break forced motion/control. Native navigation is used, with a no-progress fallback if `GridNav.CanFindPath` is unavailable.
- Ending an owned movement order emits a native stop only when control permits and no native cast phase/channel is active. Stage reset removes sessions and event observers; it does not interrupt native channels. Existing stage lifecycle remains responsible for its native unit cleanup.

## Standalone positioning and attack safety

Positioning applies only to authored attack/ability rules, after their use and target gates pass. Fixed distance may prevent an ability from casting if authored outside its legal range; there is no automatic override of contradictory configuration. `attack_range` reads `Script_GetAttackRange` live; `cast_range` uses the adapter's current native required range. Ability positioning occurs before issuing the cast, never during native phase/channel.

Attack positioning is armed **only by `MODIFIER_EVENT_ON_ATTACK` / `OnAttack`** on the actual caster. `OnAttackStart` only invalidates a previous release, never arms movement. Extra attacks marked `no_attack_cooldown` do not arm positioning. The release must concern the selected target, and no later attack order may have superseded it. The window uses the current `GetSecondsPerAttack`, ending 0.25 seconds before the next interval. Very fast attacks can therefore have no positioning window. This is intentionally conservative rather than a prediction of attack windup. Damage/projectile-hit events and elapsed time from an issued attack are not release evidence.

Attack-range positioning aims inside the live range by the configured tolerance; its accepted upper bound is the actual attack range. The native event observer survives same-handle reincarnation and is explicitly detached on stage reset.

The actual event ordering, availability on all native units, forced/extra-attack edge cases, engine navigation and visible attack cadence require live verification. API declarations in local `F:/dota-api-types.txt` confirm `OnAttack`, `OnAttackStart` and `OnAbilityExecuted` callback names, not a live execution result.

## Named buff presets and native evidence

`movement_contract.presets` publishes:

- Shukuchi: `modifier_weaver_shukuchi`, trigger `weaver_shukuchi`.
- Trample: `modifier_primal_beast_trample`, trigger `primal_beast_trample`.
- Rolling Thunder: `modifier_pangolier_gyroshell`, trigger `pangolier_gyroshell`.

Shukuchi/Trample use cycling/orbit respectively, radius 150 and a 15-second safety deadline. All three movement presets enable both retargeting and looping, disable interruption and use automatic direction. Rolling Thunder uses orbit, radius 150 and a 20-second safety deadline (native duration is 10/11/12 seconds, plus a 2-second talent). Native buff disappearance ends movement earlier. The requested radius is a waypoint target; Rolling Thunder's native forward speed, turning radius and collisions determine its actual route. This preset does not force an exact 150-unit circle or guarantee repeated collisions. Ordinary blank UI movement fields default to 5 seconds and 150 units; the backend defaults above apply to omitted wire fields.

Repository `data/native_skill_conditions.json`, native snapshot client 6924 / revision 10969619, records:

- `scripts/npc/heroes/npc_dota_hero_weaver.txt`: Shukuchi no-target/immediate behavior, duration 4 seconds, damage while passing enemies, radius 175.
- `scripts/npc/heroes/npc_dota_hero_primal_beast.txt`: Trample no-target/immediate behavior, duration 5.5 seconds, step distance 140, effect radius 200, native disarm during the ability.

These native definitions support the movement feature but **do not contain runtime modifier declarations**. The requested modifier identifiers and Rolling Thunder's steerability through native motion-control gates remain live-unverified. Missing/wrong modifiers fail closed: no persistent movement starts. The backend does not simulate their damage or claim every orbit waypoint triggers a native damage tick.

## Regression execution

`tests/persistent-movement.test.lua` runs the real production engine/adapter/selector, RuleService, Snapshot/Legacy conversion, and event-modifier callbacks against mock entities and native functions. It covers buff lifecycle, ancient/new cast discrimination, no order-history trigger, no same-cast retrigger, dead-target fallthrough, locked/explicit retargeting, all modes, orbit direction, looping, native control and phase safety, unreachable/no-progress/deadline termination, explicit interrupts, attack windup vs release, live range/interval, authoring gates, standalone ability positioning, stage cleanup, validation and field roundtrips.

Run with a Lua 5.1 runtime from the repository root. In this environment Python's installed `lupa.lua51.LuaRuntime` can execute each `tests/*.test.lua` in an isolated runtime. These are backend regressions, not Dota acceptance tests.
