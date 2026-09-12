# Neutral pursuit and centered spell correction

User acceptance remains pending. Build log marker: `neutral-pursuit-v1`.

The user reports an opening stomp at spawn, pursuit only after a hero attacks,
and Ogre Smash never firing. Earlier Khan cooldown/stun observations establish
that particular cast, not reliable pursuit or every neutral ability.

Source findings:

- Enemy self spells fell back to `alive_enemy_count_gte` when `GetAOERadius()`
  returned zero. This allows an opening stomp with no enemy in its effect area.
- The interrupted Ogre patch inferred centered targeting from a behavior bit and
  effective zero range. Self-cast permission does not establish centered effects
  (Dawnbreaker also carries it). The exact live failing predicate was not captured:
  current `console.log` only contained the subsequent client startup.
- `NeutralAttack.Submit` already calls the supplied attack-order callback.
  The extra opening `Approach` duplicated that order. A cached attack target
  outside attack range also incorrectly counted as continuous progress.
- Point location validation received an entity before position normalization,
  which could reject the previous self-point routing even after resolution.

Implemented:

- Reviewed contracts for `centaur_khan_war_stomp` and
  `ogre_bruiser_ogre_smash`, using the native `radius` special when the AOE
  accessor returns zero. No nearby enemy means no generated centered cast.
- Ogre Smash selects its caster position independently of missing behavior
  globals and range bonuses. The native location filter receives a Vector.
  Directional hero spells retain their point-selection behavior.
- `npc_dota_creature` uses ordinary attack orders with Lua intent ownership.
  Native neutral classes retain the existing force-target path. Distant cached
  targets cannot suppress bounded recovery; control/cast windows remain protected.
- Removed the redundant opening order. Preserved the interrupted sandbox tracing
  changes and custom Khan/Ogre definitions. No chapter data changed.

Native KV inspected: local extracted `npc_abilities.txt` (2026-09-12 15:53).
Khan: radius 250, cooldown 12, cast point 0.4, mana 50.
Ogre: radius 200 at level one, cooldown 12, cast point 2.8, mana 0.
The previous claim that Ogre requires 60 mana was incorrect.

Verification (PowerShell, from repository root):

```powershell
$env:LUA_BIN = 'C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-lua515-4lsm6zwd/lua.exe'
python scripts/test-all.py
pwsh -NoProfile -ExecutionPolicy Bypass -File ./tests/verify-addon.ps1
```

Result: 81/81 offline groups passed. The legacy addon verifier fails at line 218
because it requires `item_rpg_scroll_low` in `addon_game_mode.lua`; the committed
HEAD also lacks that literal. This independent stale assertion is tracked in
`dota2_rpg-je8k`; it was not changed for this fix. Regressions
cover the native radius fallback, zero distant-enemy count, Ogre self position,
location filter input, directional isolation, ordinary custom-creature attacks,
stale target recovery, and protected control windows. These tests use native API
doubles and do not prove game execution.

After the user reloads the addon, acceptance requires opening pursuit before any
hero attack, no distant opening stomp, and Ogre finishing its 2.8-second cast
and entering cooldown. `rule_executed` alone means order submission only.
Later native neutral classes remain a separate follow-up; this patch does not
claim their abilities now work. No client launch, shutdown or gameplay commands.

Deployment: ten related files copied and verified byte-for-byte. Previous files
are backed up in
`C:/Users/harjeb/AppData/Local/Temp/dota2_rpg_neutral_pursuit_0ea6b926e2874934845279785993f564`.
Live acceptance: `dota2_rpg-cd65`. Later native classes: `dota2_rpg-3ipt`.
