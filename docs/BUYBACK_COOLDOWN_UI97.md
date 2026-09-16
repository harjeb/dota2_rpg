# Buyback cooldown — UI97

UI97 adds campaign buyback cooldowns counted in battle attempts and updates both languages and in-game help. Add and enable **Auto buyback** in a campaign hero's action list. After that hero dies during combat, paid revival still requires sufficient shared gold and all normal eligibility checks. This change adds no dynamic cooldown display.

| Difficulty | Successful buybacks per battle | Hero cooldown after success in battle N |
| --- | --- | --- |
| Easy | Once per hero | None between battles |
| Default | Once per hero | Block N+1 and N+2; eligible again at N+3 |
| Hard | Once for the whole team | Block N+1, N+2 and N+3 for the hero who bought back; eligible again at N+4 |

Retries are new battle attempts: they advance hero cooldowns and reset the per-battle allowance, including Hard's shared team quota. A new stage does not clear hero cooldowns; a fresh run does. Arena fights neither use campaign buyback nor advance its cooldown counter.

For example, if Axe buys back in campaign attempt 5 on Default, Axe cannot buy back in attempts 6 or 7, even if these are retries of the same stage. Axe can buy back again in attempt 8. On Hard, Axe must also skip attempt 8 and can return in attempt 9. A different eligible hero can use Hard's reset team quota in attempt 6; resetting that quota does not clear Axe's cooldown.

## Implementation

- The campaign attempt counter advances once per actual campaign fight start, including retries. Preparation, stage selection and arena starts do not advance it.
- Hero cooldown state uses persistent hero names, rather than entity handles, so entity recreation and bench swaps retain it. The attempt counter advances even while a hero is benched.
- Only a successful paid buyback consumes the hero allowance, starts its cooldown and consumes Hard's team quota. Failed eligibility checks do not spend those allowances.
- Per-battle counters reset independently of persistent hero cooldowns. Starting a fresh run clears the persistent cooldown state.
- Cost remains `(100 + 50 × level + 5 × level²) × difficulty`, rounded to the nearest 5 shared gold; multipliers remain Easy 0.75, Default 1 and Hard 1.25. Existing gold, death and native reincarnation checks still apply.

## Generation and validation

The help source is `data/condition_help_topics.json`. Generator usage is documented in `docs/CONDITION_HELP_COVERAGE.md`: `python scripts/build-condition-help.py` regenerates the JavaScript and coverage report; `python scripts/build-condition-help.py --check` checks both outputs without writing.

To regenerate only the assigned JavaScript output, use the existing generator's output function from the repository root:

```bash
python -c "import runpy; m=runpy.run_path('scripts/build-condition-help.py'); p=m['JS']; p.write_bytes(m['outputs']()[p].encode('utf-8'))"
python scripts/build-condition-help.py --check
git diff --check
```

Validation: the full offline regression suite passed 150/150 using LuaJIT, including 22 buyback backend scenarios. Coverage includes the exact two/three-attempt boundaries, same-stage retries, advancing stages, shared Hard quota reset, stable hero identity across entity replacement and bench swaps, arena exclusion, failed revival/refunds, repeated ticks, and fresh-run reset. The help generator freshness check passed, and both locale markers are UI97.

Native Dota verification remains pending: the default installation is unavailable in this environment. These checks use Lua engine mocks and Panorama test doubles; no native compilation or in-game acceptance is claimed.
