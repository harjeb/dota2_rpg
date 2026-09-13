# Final stage: Skeleton King and five level-30 heroes

Stage 30 now contains six enemies: the existing Skeleton King boss, followed by Lifestealer, Mirana, Pangolier, Bane, and Dark Seer at level 30. The five added heroes have no equipment, quality upgrades, Boss tags, or special stat fields; their normal native level/skill progression and the existing enemy AI apply. Chapter multipliers affect creeps only. Skeleton King's complete existing Boss configuration and equipment remain unchanged, as do stages 1–29 and stage rewards/time limit.

Both runtime `levels.kv` and maintenance `levels_v07.json` contain the additions. The roster generator preserves the lineup, equipment authoring keeps the additions unequipped, and late-balance authoring skips ordinary heroes in Boss stages. Configuration comparison treats empty KV collections and JSON lists equivalently.

Validation: full offline suite 104/104 passed; roster/equipment generation is byte-idempotent; data comparison confirms only the five final-stage entries were added. Two installed data files byte-match source; UI stays 69 because this is a data-only gameplay change. Backup: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-final-stage-7h8d77__`. Regression report: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-final-stage-regression.json`.

No game operations or live balance verification were performed. Reload the addon to load the updated campaign data.
