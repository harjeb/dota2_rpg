# Winter Wyvern retained respawn

Issue: `dota2_rpg-ju4o`. Backend change from HEAD `7dc71af`; UI remains 69.

The read-only backup `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-wyvern-outofgame-0_kq49u0/console.8997007202.log` shows entity 500 executing Arctic Burn at 20:36:58, dying with `outofgame=false` at 20:37:10, and returning as the same alive entity with `outofgame=true` at 20:37:18. Its ready snapshot contains `modifier_fountain_invulnerability` alongside the frost-attack intrinsic and preparation modifiers. At 20:38:14 all four rules report `caster_out_of_game`.

`Edda.TakeRetained` now explicitly removes `modifier_fountain_invulnerability` during roster preparation, after the existing cleanup. Native fountain protection can be permanent and not a debuff, so the duration/debuff sweep misses it. Both dead and already-alive retained heroes receive this narrow cleanup. The hero entity, native ability upgrades, intellect growth, and permanent intrinsic modifiers are preserved. No additional general modifier stripping or tactics eligibility bypass is introduced.

The existing lifecycle logger records `retained_before_respawn`, `retained_before_cleanup`, and `retained_after_cleanup`, including entity identity, alive/out-of-game state, and modifier names. The existing lineup/bench `ready` snapshot then shows the result after preparation and inventory restoration.

Respawn permissions are unchanged. The evidence already shows `RespawnHero(false,false)` returning an alive entity despite disabled automatic respawns. It does not establish that temporarily enabling respawns is necessary. Preparation and battle-start permission handling remain owned by the existing respawn policy.

Validation: the full offline suite passes 104/104 groups using Lua 5.1.5 and the existing Python/Node harnesses. New Edda assertions model permanent non-debuff fountain protection, verify cleanup for dead and alive retention, preserve native growth/intrinsics and unrelated permanent out-of-game state, and check the lifecycle snapshots. Running the new regression against the previous implementation fails at the retained spawn-protection assertion.

Native engine behavior remains unverified. The log identifies fountain protection as the strong candidate; the Lua test models its out-of-game effect and cannot prove native removal clears that state or that the engine will not reapply protection asynchronously. A user-driven native check should confirm the three retained snapshots and the final ready snapshot share one entity, show protection disappearing and `outofgame=false`, preserve Edda growth, and allow rules to execute in the next fight. The changed Lua module is installed and byte-verified, with a backup at `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-wyvern-respawn-luekyxl7`. Both installed locales match UI69. Reload the map to load the fix. No game operations were performed.
