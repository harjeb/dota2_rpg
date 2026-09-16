# UI101 — Continuous conditions and concise difficulty entry

## Delivered behavior

The condition editor now presents all four groups in one continuous scrolling document: use conditions, target filters (including target-team controls), priorities, and action settings. Left navigation scrolls to a group; scrolling the middle column updates the highlighted category, current heading, and right-hand preview. Numbered group headings and framed sections separate the groups visually.

Existing controls are reparented into ordered section panels, retaining their readers, values, and event handlers. Navigation and scroll observation do not serialize, apply, or rebuild a draft. Native conditional visibility (such as chase timeout) remains independent. Each section has a minimum height of one viewport so native scroll-to-fit can align its start, including the final group. A generation-scoped observer runs only while the editor is open and stops after closing, resetting, replacing, or disposing the dialog. Buyback retains its special editor.

Campaign entry displays only three buttons: 简单 / 普通 / 困难 (Easy / Normal / Hard). Clicking one sends that selection immediately. There is no title, explanation, reward/ranking text, or separate confirm button. Normal still uses the existing server ID `default`. Server ownership and locked difficulty remain authoritative; pending requests disable repeated selections, and a guarded timeout permits retry when a response is lost.

Both localization files advertise UI101. The condition navigation hint explains click-or-scroll browsing.

## Validation

All 11 focused groups passed; captured output is in `tests/results/ui101-condition-scroll.json`:

- Condition scroll geometry, native anchor requests, scaled thresholds, selected category and preview, draft/payload preservation, observer lifecycle, read-only navigation.
- Full condition editor, condition refresh/save, fantasy UI, existing wheel-scroll contract, buyback, rule library and its HUD integration, and skill debug.
- Campaign difficulty UI direct selection, only-three-controls structure, duplicate requests, stale retry timers, owner/lock gating, reconnect, and bilingual labels.
- Campaign difficulty Lua validation, lock/recovery, reward calculations and isolation.

The shared HUD mock now records native scroll requests, supports nested section ownership, and exposes a deterministic scheduled-callback clock. Refresh/save tests flush one snapshot of scheduled callbacks so recurring UI observers do not create an infinite drain loop.

Installed to `C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta`. The native resource compiler successfully compiled `condition_catalog.js`, `fantasy_ui.css`, `campaign_difficulty.js`, and `campaign_difficulty.css`. Verified 123 game source hashes and 29 content source hashes against the installation, including both complete locale files.

No Dota session was launched or controlled. Native compilation and offline panel tests do not establish the final visual appearance or wheel behavior inside a running match; that remains the practical validation limit. No Workshop publication was performed.
