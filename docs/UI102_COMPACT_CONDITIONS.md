# UI102 — Compact condition layout

UI101 gave every condition group `min-height: 100%` to align native navigation. This stretched short groups, especially priorities, to a full viewport. UI102 removes that minimum and sizes every group to its contents, with smaller padding and spacing.

Condition cards now use a vertical layout with a dedicated horizontal heading. The selector fills the remaining heading width instead of combining an 84% width with fixed icons in a wrapping row. Parameters and explanations follow the heading directly. Cards have no minimum height; active conditions without parameters hide the empty parameter panel. F41 keeps its facing explanation in a content-sized label with no bottom margin.

Navigation still uses native scroll-to-fit, now immediate. The observer retains an explicitly clicked category while the document geometry is unchanged, allowing several compact groups to share the viewport. On subsequent scrolling it follows visible group positions, including the final short group at the document bottom. No spacer panels or minimum viewport-sized sections are added.

Both locales display version 102. Nine focused groups passed, recorded in `tests/results/ui102-compact-conditions.json`: continuous scrolling, full condition editor including F41 save/reopen, refresh/save, fantasy layout, scrollbar contract, buyback, difficulty entry, rule-library HUD, and skill debug. Added checks cover shared-viewport navigation, final short section selection, F41 explanation visibility, and collapsed parameterless priority rows.

Installed to `C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta`; native compilation passed for `condition_catalog.js` and `fantasy_ui.css`. Verified 123 game source hashes and 29 content source hashes including both locale files. No live Dota visual session was performed.
