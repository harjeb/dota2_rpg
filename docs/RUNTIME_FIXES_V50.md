# UI50: all-unit Jinada income, Rolling Thunder orbit and inventory space

## Result

The user explicitly authorizes Jinada income from every enemy unit type, including campaign creatures, without requiring a victim player wallet. A dedicated RPG gold component now credits the owning player's authoritative balance on eligible landed attack records. Targets have no hero, owner, or gold-balance restriction: creatures, summons, heroes and buildings qualify. Allies do not. Native Jinada retains damage, cast/autocast behavior and cooldown.

`issue_fixes/jinada_income.lua` attaches to the player's roster Bounty Hunter during `PrepareBattleHero`, before restoring levels. Its server-only special override sets native Jinada `gold_steal` to zero, and refreshes an already-created native intrinsic modifier to refresh cached specials. Client tooltips retain native values. The custom amount temporarily bypasses only this modifier's override while reading `GetSpecialValueFor`, preserving native talent adjustments; this does not pay gold on a value query.

Attack-start/record callbacks capture native cooldown readiness and autocast/manual-order eligibility. Release marks the record, and landing claims it before paying, preventing duplicate landed callbacks. Failed/unreleased attacks do not pay. The addon does not run a second cooldown: native refreshes and the no-cooldown talent immediately permit new eligible records. Non-proccing extra attacks, break, untrained abilities, non-owned/illusion casters and non-fight phases are excluded. Scepter Shuriken damage callbacks supply the separate per-hit income path, including tracked-target bounces. Income never debits the target; it is an RPG reward based on Jinada's native special (15/22/29/36, plus the current talent).

The existing wallet only actively published changes in setup. It now also publishes changed native balances during fights and settlement, so earned gold does not wait for another preparation phase before appearing. Existing setup purchase reconciliation remains confined to setup.

## Condition preset

Under `持续移动` → condition settings, `地雷滚滚：绕行` supplies `pangolier_gyroshell` / `modifier_pangolier_gyroshell`, orbit, distance 150, automatic direction, looping and retargeting enabled, interruption disabled, and a 20-second safety deadline. Native buff loss ends movement earlier. Keep a separate native Rolling Thunder cast rule and put the movement rule above it. The associated-buff selector and backend preset catalog include the same mapping.

Native Rolling Thunder duration is 10/11/12 seconds, with a +2-second talent. Its native speed/turn rate and collision behavior determine the route; 150 is a requested waypoint radius, not a forced physical circle. Existing control and motion-controller safety gates remain in force.

## Equipment layout

Hero equipment and stock lists each use `fill-parent-flow(1)` with a 216px minimum, replacing fixed 146px heights. They split surplus height when equipment has more sidebar space, showing three card rows at the minimum. Each list retains scrolling; the whole equipment body remains scrollable when both sidebar sections are open or vertical room is limited. Scroll shop follows the two inventory frames.

## Verification and limits

- 86/86 offline regression groups pass. New Jinada tests model native special override dispatch, both callback orders around cooldown consumption, exactly-once records, all enemy types, manual/autocast, misses, break, talents, native cooldown refresh, Scepter and ownership/phase guards. These mocks verify the authored RPG rules, not an actual C++ Jinada proc signal.
- Extended production-engine movement tests cover cast/buff gating, orbit, retarget, native control and buff exit; real-HUD tests cover the third preset's save/reopen/server roundtrip.
- Wallet tests cover reliable/unreliable native credits, subsequent custom spending/rewards and combat/settlement publication.
- Deployment and native Panorama JS/CSS compilation evidence: `tests/results/ui50-jinada-movement-deploy.json`.

No Dota launch/stop, gameplay or screenshots were performed. Native callback ordering, intrinsic special caching and gold suppression on every native/Scepter path, and Rolling Thunder steerability through native motion-control gates require engine acceptance. They are tracked in `dota2_rpg-9aqe`; implementation is tracked in `dota2_rpg-ixm3`. No claim of live acceptance is made.
