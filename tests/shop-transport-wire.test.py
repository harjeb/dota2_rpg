"""Lua-produced frames must survive JSON/native-shaped strings and the real JS assembler."""
import json
import subprocess
from lua_test_runtime import run_lua, ROOT

wire = run_lua(r'''
local T = require('issue_fixes.shop_transport')
local game = {SendStateTo=function(_, player, event, data)
    local text, budget = T.Encode(data)
    assert(budget < 2000, 'native envelope exceeds conservative budget')
    print(text)
end}
local snapshot = {rule_generation=17, gold=725, hero_entity_indices={npc_dota_hero_axe=123},
    inventories_text=string.rep('npc_dota_hero_axe:item_ultimate_scepter,item_butterfly,item_assault;',180),
    equipped_text=string.rep('npc_dota_hero_axe:item_ultimate_scepter|123|0,item_butterfly|456|1;',180),
    escaped='quote" slash\\ controls\n\t\0 中文装备'}
T.Send(game, {}, snapshot)
print(T.Encode(snapshot))
''').splitlines()
# print propagates Encode's second return as a tab-separated budget.
expected = json.loads(wire.pop().rsplit('\t', 1)[0])
frames = [json.loads(line) for line in wire]
assert len(frames) > 10
assert all(len(f['data'].encode('utf-8')) <= 1200 for f in frames)
script = r'''
const fs=require('fs'), assert=require('assert');
const T=require('./content/dota_addons/dota2_rpg/panorama/scripts/custom_game/shop_transport.js');
const {frames, expected}=JSON.parse(fs.readFileSync(0,'utf8'));
const results=[]; const r=T.create(s=>results.push(s));
frames.reverse().forEach(f=>{r.chunk(f);r.chunk(f);});
assert.deepStrictEqual(results,[expected]);
console.log('PASS actual Lua wire -> JS atomic assembler, UTF-8 and escaped strings');
'''
result = subprocess.run(['node', '-e', script], cwd=ROOT, input=json.dumps({'frames': frames, 'expected': expected}),
                        text=True, encoding='utf-8', capture_output=True)
assert result.returncode == 0, result.stdout + result.stderr
print(result.stdout.strip())
