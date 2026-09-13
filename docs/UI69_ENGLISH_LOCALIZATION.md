# UI69 English localization completion

The recruitment and inventory HUD displayed several Chinese literals even when the client language was English. These now use the existing addon localization system, with Chinese wording retained.

Added 11 paired tokens: four recruitment qualities, free recruitment count, bench and neutral-item suffixes, stash and backpack slot suffixes, scroll remaining count, and the initial stage-progress label. Hero, skill and native item names continue using Dota localization. Both visible build markers are UI69.

The audit found existing bilingual condition help and skill-debug text and matching locale keys. Chinese level names in server data are not currently published to the HUD (the level-list event carries IDs); those unused display names were not changed. Chinese comments and internal help coverage metadata are not player-facing translations.

Validation:

- Complete offline suite: 104/104 passed. Existing HUD tests now expect localization tokens in their identity-localizer mock.
- All 560 locale keys match, without duplicates; format placeholders match and English values contain no Chinese characters.
- Ad hoc actual-HUD harness with each real locale loaded before initialization verified all four qualities, free count, bench, neutral stock/equipment, stash/backpack and scroll counts. English rendered labels contained no Chinese in that scenario; Chinese values were preserved.
- Native resource compilation succeeded for the changed HUD JS and XML. Four installed addon sources byte-match; both installed locales match UI69. Backup: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui69-guid53ik`.
- Full regression report: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui69-regression.json`. Locale-render check: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui69-localization-check.js`.

No game operations or live English layout verification were performed. Use English as the Dota client language, restart the client as needed, and reload the addon to inspect UI69. This is the same addon; a separate English map is unnecessary. Workshop publishing and Workshop-page translation were not part of this change.
