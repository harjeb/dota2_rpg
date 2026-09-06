# 离线战斗模拟器

DESIGN.md §5.5 的平衡工具：在不启动 Dota 2 的情况下批量模拟战斗，复用离线模拟器专用的
`game/dota_addons/dota2_rpg/scripts/vscripts/battle/tactic_engine.lua` 适配层；线上地图运行时使用
`game/dota_addons/dota2_rpg/scripts/vscripts/tactics/tactic_engine.lua` 与 RuleService。

## 结构

| 文件 | 职责 |
| --- | --- |
| `mock_env.lua` | Dota VScript 全局最小替代（`class`、`bit`、实体索引表等） |
| `sim_units.lua` | 模拟单位模型：位置/HP/MP/普攻/冷却技能/移动结算，`Vector` 实现 |
| `simulator.lua` | 离线兼容引擎的 `SimAdapter` + `run_battle(config)` + 自检 |

## 运行

任意 Lua 5.1 / LuaJIT（本仓库用 Python lupa 验证）：

```bash
cd sim
lua simulator.lua
# 或
python -c "from lupa import LuaRuntime; l=LuaRuntime(); l.execute('package.path=\"./?.lua;\"'); l.execute(open('simulator.lua',encoding='utf-8').read())"
```

## 用法

```lua
local sim = dofile("simulator.lua")
local result = sim.run_battle({
	team_a = { units = { { name="sven", position=Vector(-300,0), maxHealth=1200, attackDamage=90, abilities={} } },
	           rules  = { { {action="attack", condition="always", target="enemy_nearest", forced=true} } } },
	team_b = { units = { { name="brute", position=Vector(300,0), maxHealth=1500, attackDamage=70, abilities={} } },
	           rules  = { { {action="attack", condition="always", target="enemy_nearest", forced=false} } } },
	max_time = 120,
})
-- result = { winner="team_a"|"team_b"|"draw"|"timeout", duration=秒, survivors={{name,hp,team}} }
```

## 自检输出（当前基线）

```
[simulator] selftest winner=team_a duration=13.2 survivors=2
[simulator] batch: team_a winrate=100% (20 runs)
```

注意：模拟器只做数值平衡粗估（无 Dota 护甲/魔抗/技能细节），胜负趋势参考即可。
