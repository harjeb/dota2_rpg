# Final stage: Skeleton King and five level-30 heroes

Stage 30 contains the existing Skeleton King boss followed by Lifestealer, Mirana, Pangolier, Bane and Dark Seer at level 30. The five ordinary heroes use Team Spirit's match-end equipment from The International 2026 (TI15) grand-final GAME5, public OpenDota match [8960991322](https://api.opendota.com/api/matches/8960991322), league 19719, duration 3862 seconds, won against TEAM VISION.

| Hero | Main slots 0–5, in order | Neutral slot 16 | Backpack slots 6–8 | Consumed upgrades |
| --- | --- | --- | --- | --- |
| Lifestealer | armlet, monkey_king_bar, abyssal_blade, nullifier, assault, satanic | desolator_2 | empty, empty, empty | scepter, shard |
| Mirana | essence_distiller, wind_waker, aeon_disk, ward_sentry, ultimate_scepter, boots | conjurers_catalyst | dust, empty, empty | none |
| Pangolier | lotus_orb, gem, disperser, refresher, blink, abyssal_blade | desolator_2 | power_treads, bottle, empty | scepter, shard |
| Bane | blink, tranquil_boots, aeon_disk, ultimate_scepter, quelling_blade, dust | demonicon | empty, empty, empty | shard |
| Dark Seer | shivas_guard, overwhelming_blink, sheepstick, travel_boots_2, refresher, aeon_disk | riftshadow_prism | lotus_orb, black_king_bar, empty | shard |

Names above are native item suffixes (`item_` in configuration). The curated public snapshot in `data/ti15_2026_game5_equipment.json` records source item IDs, source slots, hero IDs and the consumed-upgrade buff IDs used (2=scepter, 12=shard). It excludes account IDs, personal names and unrelated match data. Held Scepters remain inventory items without an additional consumed Scepter. Lifestealer's accumulated permanent HP buff 16 is excluded. Item charges, cooldowns, toggled states and neutral enchantments (`item_neutral2`) are outside this equipment configuration.

Both runtime `levels.kv` and maintenance `levels_v07.json` contain the equipment. Roster and equipment generators reproduce it offline. `backpack_items` uses indices 1–3, preserving empty positions; native `GetItemSlot` and `SwapItems` place these items in slots 6–8 and `neutral_item` in slot 16. Failed optional placements are logged and removed instead of leaving their bonuses active in a main slot. Stage precaching includes the extra items. Native item definitions, including Essence Distiller and all selected neutrals, were verified against the installed Dota VPK.

The five heroes retain normal level/skill progression and existing enemy AI, without Boss tags or custom stat bonuses. Chapter multipliers affect creeps only. Skeleton King's complete Boss configuration, stages 1–29, rewards and time limit remain unchanged. UI stays 69 because this is a gameplay data/backend change.

Validation covers source/runtime inventories, consumed-upgrade distinctions, generator idempotence, native item availability, sparse numeric/string backpack indices, neutral placement, failed-swap cleanup and configuration export. The full offline suite passed 104/104 groups. Five changed addon files were installed and byte-verified; both installed locale files still match UI69. Offline checks do not verify native inventory placement or item-active behavior in a running Dota match; reload the map for user-driven verification.
